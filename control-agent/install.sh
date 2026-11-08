#!/bin/sh
set -eu
umask 077
fail() { echo "HOME NET Control: $*" >&2; exit 1; }
[ "$(id -u)" = 0 ] || fail 'root required'
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
if ! command -v python3 >/dev/null 2>&1 || ! python3 -c 'import ssl,fcntl,json' >/dev/null 2>&1 ||
   ! command -v age >/dev/null 2>&1 || ! command -v age-keygen >/dev/null 2>&1; then
    if command -v apk >/dev/null 2>&1; then
        apk add python3 python3-ssl age || fail 'agent dependencies unavailable'
    elif command -v opkg >/dev/null 2>&1; then
        opkg update && opkg install python3 python3-ssl age || fail 'agent dependencies unavailable'
    else
        fail 'OpenWrt package manager unavailable'
    fi
fi
python3 -c 'import ssl,fcntl,json' || fail 'Python SSL unavailable'
command -v age >/dev/null && command -v age-keygen >/dev/null || fail 'age unavailable'
for file in cudy.py vpn-control-cudy.init prepare-slots.py; do
    wget -q -T 60 -O "$work/$file" "https://raw.githubusercontent.com/kumshi1978/home-net-cudy/$ref/control-agent/$file" || fail 'download failed'
done
echo 'b6bb86333d8658ae07d24d3f9e826758446d3e147884bdafca42b5c26a63905a  '"$work/cudy.py" | sha256sum -c - || fail 'agent integrity check failed'
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
echo 'cf42bc8d43ec042c8f912d20610ca3f71190a0d57eb96b8ef87e40064ebb6973  '"$work/install-three-slots.sh" | sha256sum -c - || fail 'controller installer integrity failed'
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
