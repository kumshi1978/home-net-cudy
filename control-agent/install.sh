#!/bin/sh
set -eu
umask 077
fail() { echo "HOME NET Control: $*" >&2; exit 1; }
[ "$(id -u)" = 0 ] || fail 'root required'
mode=${1:-install}
case "$mode" in install|--preflight|--prepare-dependencies) ;; *) fail 'usage: install.sh [--preflight|--prepare-dependencies]' ;; esac
[ "$#" -le 1 ] || fail 'too many arguments'
ref=${HOME_NET_CONTROL_REF:-}
printf '%s\n' "$ref" | grep -Eq '^[0-9a-f]{40}$' || fail 'immutable source commit required'
directory=/etc/home-net/keys
for path in /etc/home-net "$directory" /usr/sbin/vpn-control-cudy.py /usr/sbin/home-net-prepare-slots.py /etc/init.d/vpn-control-cudy /etc/vpn-control-agent.json; do
    [ ! -L "$path" ] || fail 'unsafe installation path'
done
lock=/var/run/home-net-control-install.lock
mkdir "$lock" || fail 'installation already running'
work=$(mktemp -d /tmp/home-net-control.XXXXXX) || { rmdir "$lock"; exit 1; }
identity_temp=
agent_temp=
init_temp=
slots_temp=
trap 'rm -rf "$work"; [ -z "$identity_temp" ] || rm -f "$identity_temp"; [ -z "$agent_temp" ] || rm -f "$agent_temp"; [ -z "$init_temp" ] || rm -f "$init_temp"; [ -z "$slots_temp" ] || rm -f "$slots_temp"; rmdir "$lock"' EXIT
trap 'exit 1' HUP INT TERM
python_ready() {
    command -v python3 >/dev/null 2>&1 && python3 -B -c 'import ast,base64,email.parser,fcntl,hashlib,hmac,http.client,ipaddress,json,os,pathlib,re,signal,socket,ssl,subprocess,sys,tempfile,threading,time,urllib.parse' >/dev/null 2>&1
}
age_ready() {
    command -v age >/dev/null 2>&1 && command -v age-keygen >/dev/null 2>&1 &&
        age --version >/dev/null 2>&1 && age-keygen --version >/dev/null 2>&1
}
# A reserve covers controller/agent files, atomic replacements, backups and
# filesystem overhead. It is additional to uncompressed dependency sizes.
reserve_kib=4096
packages=
if ! python_ready; then
    packages='python3-light python3-openssl python3-email python3-urllib'
fi
if ! age_ready; then packages="$packages age"; fi
needed_bytes=0
manager=none
if [ -n "$packages" ]; then
    if command -v apk >/dev/null 2>&1; then
        manager=apk
        # Resolve ALL dependencies before touching flash. No binary fallback or
        # alternate feed is trusted implicitly when age is absent.
        apk add --simulate $packages >"$work/apk-plan" 2>&1 ||
            fail 'required packages unavailable; provision reviewed age/age-keygen or a supported feed first'
        # apk metadata differs across supported OpenWrt generations. Until an
        # exact installed-size plan is available, use a conservative minimum.
        needed_bytes=33554432
    elif command -v opkg >/dev/null 2>&1; then
        manager=opkg
        opkg update >"$work/opkg-update" 2>&1 || fail 'package index refresh failed'
        opkg status >"$work/package-metadata" || fail 'installed package metadata unavailable'
        for index in /var/opkg-lists/*; do
            case "$index" in *.sig) continue ;; esac
            [ -f "$index" ] || continue
            printf '\n' >>"$work/package-metadata"
            if gzip -t "$index" 2>/dev/null; then
                gzip -dc "$index" >>"$work/package-metadata" || fail 'invalid package index'
            else
                cat "$index" >>"$work/package-metadata" || fail 'unreadable package index'
            fi
        done
        # Resolve the complete closure, including Provides, using current
        # installed packages. Never source metadata or trust archive Size as
        # installed space. Unknown dependencies/sizes fail closed.
        awk -v roots="$packages" '
            BEGIN { RS=""; FS="\n" }
            {
                p=""; d=""; z=""; v=""; installed=0
                for(i=1;i<=NF;i++) {
                    if($i ~ /^Package: /) p=substr($i,10)
                    if($i ~ /^Depends: /) d=substr($i,10)
                    if($i ~ /^Installed-Size: /) z=substr($i,17)
                    if($i ~ /^Provides: /) v=substr($i,11)
                    if($i == "Status: install ok installed") installed=1
                }
                if(p=="") next
                if(installed) have[p]=1
                else { available[p]=1; deps[p]=d; sizes[p]=z }
                count=split(v, aliases, /, */)
                for(j=1;j<=count;j++) {
                    sub(/ .*/, "", aliases[j])
                    if(aliases[j]!="") {
                        if(installed) have[aliases[j]]=1
                        else if(!(aliases[j] in provider)) provider[aliases[j]]=p
                    }
                }
            }
            function visit(p, n,a,j,d) {
                if(p in have) return
                if(!(p in available) && p in provider) p=provider[p]
                if(p in have) return
                if(p in seen) return
                seen[p]=1
                if(!(p in available)) { print "unavailable package: " p > "/dev/stderr"; bad=1; return }
                if(sizes[p] !~ /^[0-9]+$/) { print "unknown installed size: " p > "/dev/stderr"; bad=1; return }
                total+=sizes[p]
                d=deps[p]; gsub(/\([^)]*\)/,"",d)
                n=split(d,a,/, */)
                for(j=1;j<=n;j++) {
                    gsub(/^[ \t]+|[ \t]+$/,"",a[j])
                    if(a[j]=="") continue
                    if(a[j] !~ /^[A-Za-z0-9+_.-]+$/) { bad=1; continue }
                    visit(a[j])
                }
            }
            END {
                n=split(roots,r,/ +/)
                for(k=1;k<=n;k++) if(r[k]!="") visit(r[k])
                if(bad) exit 1
                printf "%.0f\n",total
            }
        ' "$work/package-metadata" >"$work/needed-bytes" ||
            fail 'dependency plan incomplete; no packages installed (age may be unavailable in this feed)'
        needed_bytes=$(cat "$work/needed-bytes")
    else
        fail 'OpenWrt package manager unavailable'
    fi
fi
free_kib=$(df -Pk /overlay 2>/dev/null | awk 'NR==2 {print $4}')
case "$free_kib" in ''|*[!0-9]*) fail 'cannot determine writable flash space' ;; esac
needed_kib=$(( (needed_bytes + 1023) / 1024 + reserve_kib ))
echo "HOME NET Control: dependency preflight requires ${needed_kib} KiB, available ${free_kib} KiB"
[ "$free_kib" -ge "$needed_kib" ] || fail 'insufficient flash for dependencies plus 4 MiB reserve; runtime unchanged'
[ "$mode" != --preflight ] || exit 0
case "$manager" in
    apk) apk add $packages || fail 'agent dependencies unavailable' ;;
    opkg) opkg install $packages || fail 'agent dependencies unavailable' ;;
esac
python_ready || fail 'required Python imports unavailable; runtime upgrade must not proceed'
age_ready || fail 'age/age-keygen unavailable; runtime upgrade must not proceed'
[ "$mode" != --prepare-dependencies ] || exit 0
for file in cudy.py vpn-control-cudy.init prepare-slots.py; do
    wget -q -T 60 -O "$work/$file" "https://raw.githubusercontent.com/kumshi1978/home-net-cudy/$ref/control-agent/$file" || fail 'download failed'
done
echo '2d5571ed2357a6dfdd81d91fb29e1372777ffaf9f2a1940d880e22508cb09e03  '"$work/cudy.py" | sha256sum -c - || fail 'agent integrity check failed'
echo 'bd78f815539c5bc3fb56537620cf9df899aca3010794d4aa410af64a993fca5f  '"$work/vpn-control-cudy.init" | sha256sum -c - || fail 'agent integrity check failed'
echo '1fb81899dafbc0c7240c41cd9c61938627906c9ac429b749d2a14e1ea59af730  '"$work/prepare-slots.py" | sha256sum -c - || fail 'agent integrity check failed'
python3 -c 'import ast,sys; ast.parse(open(sys.argv[1]).read())' "$work/cudy.py"
python3 -c 'import ast,sys; ast.parse(open(sys.argv[1]).read())' "$work/prepare-slots.py"
sh -n "$work/vpn-control-cudy.init"
mkdir -p "$directory"
chmod 0700 "$directory"
identity=$directory/age-identity.txt
[ ! -L "$identity" ] || fail 'unsafe encryption identity'
if [ ! -e "$identity" ]; then
    identity_temp=$(mktemp "$directory/.age-identity.XXXXXX")
    age-keygen >"$identity_temp" 2>/dev/null
    chmod 0600 "$identity_temp"
    ln "$identity_temp" "$identity"
fi
[ -f "$identity" ] || fail 'local encryption identity unavailable'
chmod 0600 "$identity"
age-keygen -y "$identity" >"$work/recipient"
backup=/etc/home-net/control-agent-backup
[ ! -L "$backup" ] || fail 'unsafe backup directory'
mkdir -p "$backup"
for file in /usr/sbin/vpn-control-cudy.py /usr/sbin/home-net-prepare-slots.py /etc/init.d/vpn-control-cudy; do
    [ ! -L "$backup/$(basename "$file")" ] || fail 'unsafe backup path'
    [ ! -e "$file" ] || cp -p "$file" "$backup/$(basename "$file")"
done
# Controller files are installed under the shared lock, without touching network or routes.
wget -q -T 60 -O "$work/install-three-slots.sh" "https://raw.githubusercontent.com/kumshi1978/home-net-cudy/$ref/control-agent/install-three-slots.sh" || fail 'controller installer unavailable'
echo 'cab66fa0fb59f86c4214d7a2e0e0e420b45f82d39a91ff67558340ae63af307f  '"$work/install-three-slots.sh" | sha256sum -c - || fail 'controller installer integrity failed'
HOME_NET_CONTROL_REF="$ref" sh "$work/install-three-slots.sh" || fail 'controller upgrade requires review'
# Existing credentials and any local AWG configuration are preserved.
agent_temp=$(mktemp /usr/sbin/.vpn-control-cudy.XXXXXX)
cp "$work/cudy.py" "$agent_temp"
chmod 0755 "$agent_temp"
mv "$agent_temp" /usr/sbin/vpn-control-cudy.py
init_temp=$(mktemp /etc/init.d/.vpn-control-cudy.XXXXXX)
cp "$work/vpn-control-cudy.init" "$init_temp"
chmod 0755 "$init_temp"
mv "$init_temp" /etc/init.d/vpn-control-cudy
slots_temp=$(mktemp /usr/sbin/.home-net-prepare-slots.XXXXXX)
cp "$work/prepare-slots.py" "$slots_temp"
chmod 0755 "$slots_temp"
mv "$slots_temp" /usr/sbin/home-net-prepare-slots.py
python3 /usr/sbin/home-net-prepare-slots.py || true
/etc/init.d/vpn-control-cudy enable
if /etc/init.d/vpn-control-cudy running; then
    /etc/init.d/vpn-control-cudy restart
else
    /etc/init.d/vpn-control-cudy start
fi
echo 'HOME NET Control: agent installed; new devices await approval in the panel.'
