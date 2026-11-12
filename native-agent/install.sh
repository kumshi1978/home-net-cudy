#!/bin/sh
set -eu
umask 077
fail() { echo "HOME NET native agent: $*" >&2; exit 1; }
[ "$(id -u)" = 0 ] || fail 'root required'
case "${1:-}" in --preflight|--install) mode=$1 ;; *) fail 'usage: install.sh --preflight|--install' ;; esac
[ "$#" = 1 ] || fail 'invalid invocation'
[ "$(uname -m)" = aarch64 ] || fail 'this payload is only for aarch64'
directory=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
cd "$directory"
awk '
    BEGIN {n=split("vpn-control-cudy home-net-vpn-router home-net-vpn-cudy-adapter home-net-vpn-manifest-validate home-net-vpn-persist vpn-control-cudy.init install.sh",a," ");for(i=1;i<=n;i++)allowed[a[i]]=1}
    NF!=2 || length($1)!=64 || $1 ~ /[^0-9a-f]/ || !($2 in allowed) || seen[$2]++ {bad=1}
    END {if(NR!=7 || bad)exit 1}
' SHA256SUMS || fail 'invalid payload manifest'
sha256sum -c SHA256SUMS >/dev/null || fail 'payload integrity failed'
./vpn-control-cudy self-test || fail 'native cryptographic self-test failed'
for path in /etc/home-net /etc/home-net/vpn /etc/home-net/keys /etc/home-net/native-agent-backups /etc/home-net/native-agent-files.sha256 /etc/home-net/vpn/podkop-section /etc/home-net/vpn/failover-lock-version /etc/vpn-control-agent.json /usr/sbin/vpn-control-cudy /usr/bin/home-net-vpn-router /usr/bin/home-net-vpn-persist /usr/bin/home-net-vpn-manifest-validate /etc/home-net/vpn/adapter /etc/init.d/vpn-control-cudy; do
    [ ! -L "$path" ] || fail 'unsafe installation path'
done
command -v flock >/dev/null 2>&1 || fail 'flock is required'
[ ! -L /var/run/home-net-vpn-maintenance.lock ] || fail 'unsafe maintenance path'
if ! [ /proc/self/fd/9 -ef /var/run/home-net-vpn-maintenance.lock ]; then
    exec 9>>/var/run/home-net-vpn-maintenance.lock
fi
flock -n 9 || fail 'VPN maintenance busy'

# A prepared transaction may be carried across a *code-only* native upgrade,
# but only with explicit operator opt-in bound to a single deployment. Never
# change the transaction phase, network, selected VPN or saved credentials here.
transaction=/etc/home-net/vpn/transaction
phase=idle
[ ! -f "$transaction/phase" ] || phase=$(cat "$transaction/phase")
case "$phase" in
    idle|verified) ;;
    prepared)
        [ "${HOME_NET_ALLOW_PREPARED_UPGRADE:-0}" = 1 ] ||
            fail 'prepared transaction: explicit recovery-upgrade opt-in required'
        expected="${HOME_NET_PREPARED_DEPLOYMENT_ID:-}"
        case "$expected" in
            ''|*[!0-9a-f]*) fail 'invalid prepared deployment id' ;;
        esac
        [ "${#expected}" -eq 32 ] &&
            [ ! -L "$transaction" ] &&
            [ "$(cat "$transaction/deployment-id" 2>/dev/null)" = "$expected" ] ||
            fail 'prepared transaction ID changed'
        boot=$(cat /proc/sys/kernel/random/boot_id 2>/dev/null) ||
            fail 'current boot ID unavailable'
        [ -n "$boot" ] && [ "$(cat "$transaction/boot-id" 2>/dev/null)" = "$boot" ] ||
            fail 'prepared transaction belongs to another boot'
        [ ! -L "$transaction/metadata" ] &&
            [ ! -L "$transaction/backup" ] &&
            [ ! -L "$transaction/backup/candidate.sha256" ] ||
            fail 'unsafe prepared transaction paths'
        [ "$(sed -n '1p' "$transaction/metadata")" = awg_main ] &&
            [ "$(sed -n '2p' "$transaction/metadata")" = awg_backup ] &&
            [ "$(sed -n '3p' "$transaction/metadata")" != '' ] ||
            fail 'prepared transaction targets unexpected VPN slots'
        section=$(cat /etc/home-net/vpn/podkop-section 2>/dev/null) ||
            fail 'Podkop section unavailable'
        case "$section" in ''|*[!A-Za-z0-9_]*) fail 'invalid Podkop section' ;; esac
        [ "$(uci -q get "podkop.$section.connection_type" 2>/dev/null)" = vpn ] &&
            [ "$(uci -q get "podkop.$section.interface" 2>/dev/null)" = awg_main ] ||
            fail 'active VPN is not awg_main'
        fingerprint=$(cat "$transaction/backup/candidate.sha256" 2>/dev/null) ||
            fail 'prepared candidate fingerprint missing'
        printf '%s\n' "$fingerprint" | grep -Eq '^[0-9a-f]{64}
mkdir "$lock" || fail 'installation already running'
backup=
staged=
dirty=0
was_running=0
cleanup() {
    rc=$?
    if [ "$rc" != 0 ] && [ "$dirty" = 1 ]; then
        /etc/init.d/vpn-control-cudy stop >/dev/null 2>&1 || true
        while IFS= read -r target; do
            relative=${target#/}
            if [ -f "$backup/files/$relative" ]; then
                cp -p "$backup/files/$relative" "$target" || echo 'RESTORE FAILED: inspect native backup' >&2
            else
                rm -f "$target"
            fi
        done <"$backup/targets"
        [ "$was_running" != 1 ] || /etc/init.d/vpn-control-cudy start >/dev/null 2>&1 || true
        echo "HOME NET native agent: installation stopped; backup: $backup" >&2
    fi
    for temporary in $staged; do rm -f "$temporary"; done
    rmdir "$lock" 2>/dev/null || true
}
trap cleanup EXIT
trap 'exit 1' HUP INT TERM
targets='/usr/sbin/vpn-control-cudy /usr/bin/home-net-vpn-router /etc/home-net/vpn/adapter /usr/bin/home-net-vpn-manifest-validate /usr/bin/home-net-vpn-persist /etc/init.d/vpn-control-cudy'
payloads='vpn-control-cudy home-net-vpn-router home-net-vpn-cudy-adapter home-net-vpn-manifest-validate home-net-vpn-persist vpn-control-cudy.init'
payload_bytes=0
backup_bytes=0
for file in $payloads; do n=$(wc -c <"$file"); payload_bytes=$((payload_bytes+n)); done
for target in $targets; do
    if [ -f "$target" ]; then
        # The private backup retains this inode with a hard link before rename.
        current=$(sha256sum "$target"); current=${current%% *}
        reviewed=0
        case "$target:$current" in
            /usr/bin/home-net-vpn-router:5ac78c50fe2e163bd42ec45b6101452c5322c6809a81b6cc8defbc27115cf704|/etc/home-net/vpn/adapter:90ede043f0b19fce694b082c244b9379b1c4875b9677a39b596b75162ec1924a|/usr/bin/home-net-vpn-manifest-validate:9d99142b237ebf221b8acd18604601dc954c0e71bb42f9f06ef700698bceb745|/etc/init.d/vpn-control-cudy:bd78f815539c5bc3fb56537620cf9df899aca3010794d4aa410af64a993fca5f) reviewed=1 ;;
        esac
        [ ! -f /etc/home-net/native-agent-files.sha256 ] || ! grep -Fxq "$current  $target" /etc/home-net/native-agent-files.sha256 || reviewed=1
        [ "$reviewed" = 1 ] || fail "custom target preserved: $target"
    fi
done
free_kib=$(df -Pk /overlay | awk 'NR==2 {print $4}')
case "$free_kib" in ''|*[!0-9]*) fail 'cannot determine writable space' ;; esac
# The allowance includes hard-link metadata; link failure aborts before stopping
# the old agent. Never fall back to an unbudgeted binary-sized copy.
# Current-install allowance only. The user explicitly waived a future-update
# reserve; do not silently require 4 MiB or attempt to consume all free flash.
required_kib=$(( (payload_bytes+backup_bytes+1023)/1024+512 ))
echo "HOME NET native agent: requires ${required_kib} KiB now, available ${free_kib} KiB"
[ "$free_kib" -ge "$required_kib" ] || fail 'not enough space to complete this installation'
[ "$mode" != --preflight ] || exit 0
mkdir -p /etc/home-net/keys /etc/home-net/vpn /etc/home-net/native-agent-backups
chmod 0700 /etc/home-net/keys /etc/home-net/native-agent-backups
backup=$(mktemp -d /etc/home-net/native-agent-backups/install.XXXXXX)
mkdir "$backup/files"
for target in $targets; do
    printf '%s\n' "$target" >>"$backup/targets"
    if [ -f "$target" ]; then mkdir -p "$backup/files/$(dirname "${target#/}")"; ln "$target" "$backup/files/${target#/}" || fail 'cannot retain existing code without copying'; fi
done
for file in /etc/config/network /etc/config/podkop /etc/podkop-awg-failover.conf; do [ ! -f "$file" ] || sha256sum "$file"; done >"$backup/protected.sha256"
set -- $payloads
for target in $targets; do
    temporary=$(mktemp "${target%/*}/.home-net-native.XXXXXX")
    staged="$staged $temporary"
    cp "$1" "$temporary"; chmod 0700 "$temporary"
    printf '%s %s\n' "$temporary" "$target" >>"$backup/staged"
    shift
done
if [ -x /etc/init.d/vpn-control-cudy ] && /etc/init.d/vpn-control-cudy running >/dev/null 2>&1; then was_running=1; fi
if [ -x /etc/init.d/vpn-control-cudy ]; then /etc/init.d/vpn-control-cudy stop >/dev/null 2>&1 || fail 'agent did not stop'; fi
dirty=1
while read -r temporary target; do mv "$temporary" "$target"; done <"$backup/staged"
staged=
/usr/sbin/vpn-control-cudy identity-init
chmod 0600 /etc/home-net/keys/age-identity.txt
if [ ! -f /etc/home-net/vpn/podkop-section ]; then
    section=$(sed -n "s/^PODKOP_SECTION='\([A-Za-z0-9_]*\)'$/\1/p" /etc/podkop-awg-failover.conf)
    case "$section" in ''|*[!A-Za-z0-9_]*) fail 'local Podkop section requires review' ;; esac
    uci -q get "podkop.$section" >/dev/null || fail 'local Podkop section missing'
    printf '%s\n' "$section" >/etc/home-net/vpn/podkop-section
fi
if grep -Fxq "INSTALLED_VERSION='1.5.0'" /etc/podkop-awg-failover.conf; then printf '%s\n' 1.5.0 >/etc/home-net/vpn/failover-lock-version; fi
sha256sum -c "$backup/protected.sha256" >/dev/null || fail 'protected configuration changed'
/etc/init.d/vpn-control-cudy enable
/etc/init.d/vpn-control-cudy start
/etc/init.d/vpn-control-cudy running >/dev/null 2>&1 || fail 'agent did not start'
for target in $targets; do sha256sum "$target"; done >/etc/home-net/native-agent-files.sha256
dirty=0
# Retain the successful upgrade's immediate rollback snapshot. Only after the
# new service is running, discard older *completed* native installer snapshots.
# Never remove incomplete/unknown directories or the current rollback.
for old in /etc/home-net/native-agent-backups/install.*; do
    [ -d "$old" ] && [ ! -L "$old" ] && [ "$old" != "$backup" ] || continue
    [ -d "$old/files" ] && [ ! -L "$old/files" ] || continue
    [ -f "$old/targets" ] && [ ! -L "$old/targets" ] || continue
    [ -f "$old/protected.sha256" ] && [ ! -L "$old/protected.sha256" ] || continue
    [ -f "$old/staged" ] && [ ! -L "$old/staged" ] || continue
    grep -Fxq '/usr/sbin/vpn-control-cudy' "$old/targets" || continue
    rm -rf -- "$old" || echo "WARNING: old native backup not pruned: $old" >&2
done
echo "HOME NET native agent installed; backup: $backup; network and routes unchanged"
 ||
            fail 'invalid prepared candidate fingerprint'
        # Exact fingerprint algorithm mirrors adapter's fingerprint().
        candidate=$(awg showconf awg_backup 2>/dev/null) ||
            fail 'prepared candidate interface unavailable'
        observed=$(printf '%s\n' "$candidate" | sha256sum | cut -d ' ' -f 1)
        [ "$observed" = "$fingerprint" ] ||
            fail 'prepared candidate changed; recovery required'
        unset candidate
        echo 'HOME NET native agent: verified prepared upgrade opt-in; transaction preserved'
        ;;
    *) fail 'unfinished transaction requires review' ;;
esac
lock=/var/run/home-net-native-install.lock
mkdir "$lock" || fail 'installation already running'
backup=
staged=
dirty=0
was_running=0
cleanup() {
    rc=$?
    if [ "$rc" != 0 ] && [ "$dirty" = 1 ]; then
        /etc/init.d/vpn-control-cudy stop >/dev/null 2>&1 || true
        while IFS= read -r target; do
            relative=${target#/}
            if [ -f "$backup/files/$relative" ]; then
                cp -p "$backup/files/$relative" "$target" || echo 'RESTORE FAILED: inspect native backup' >&2
            else
                rm -f "$target"
            fi
        done <"$backup/targets"
        [ "$was_running" != 1 ] || /etc/init.d/vpn-control-cudy start >/dev/null 2>&1 || true
        echo "HOME NET native agent: installation stopped; backup: $backup" >&2
    fi
    for temporary in $staged; do rm -f "$temporary"; done
    rmdir "$lock" 2>/dev/null || true
}
trap cleanup EXIT
trap 'exit 1' HUP INT TERM
targets='/usr/sbin/vpn-control-cudy /usr/bin/home-net-vpn-router /etc/home-net/vpn/adapter /usr/bin/home-net-vpn-manifest-validate /usr/bin/home-net-vpn-persist /etc/init.d/vpn-control-cudy'
payloads='vpn-control-cudy home-net-vpn-router home-net-vpn-cudy-adapter home-net-vpn-manifest-validate home-net-vpn-persist vpn-control-cudy.init'
payload_bytes=0
backup_bytes=0
for file in $payloads; do n=$(wc -c <"$file"); payload_bytes=$((payload_bytes+n)); done
for target in $targets; do
    if [ -f "$target" ]; then
        # The private backup retains this inode with a hard link before rename.
        current=$(sha256sum "$target"); current=${current%% *}
        reviewed=0
        case "$target:$current" in
            /usr/bin/home-net-vpn-router:5ac78c50fe2e163bd42ec45b6101452c5322c6809a81b6cc8defbc27115cf704|/etc/home-net/vpn/adapter:90ede043f0b19fce694b082c244b9379b1c4875b9677a39b596b75162ec1924a|/usr/bin/home-net-vpn-manifest-validate:9d99142b237ebf221b8acd18604601dc954c0e71bb42f9f06ef700698bceb745|/etc/init.d/vpn-control-cudy:bd78f815539c5bc3fb56537620cf9df899aca3010794d4aa410af64a993fca5f) reviewed=1 ;;
        esac
        [ ! -f /etc/home-net/native-agent-files.sha256 ] || ! grep -Fxq "$current  $target" /etc/home-net/native-agent-files.sha256 || reviewed=1
        [ "$reviewed" = 1 ] || fail "custom target preserved: $target"
    fi
done
free_kib=$(df -Pk /overlay | awk 'NR==2 {print $4}')
case "$free_kib" in ''|*[!0-9]*) fail 'cannot determine writable space' ;; esac
# The allowance includes hard-link metadata; link failure aborts before stopping
# the old agent. Never fall back to an unbudgeted binary-sized copy.
# Current-install allowance only. The user explicitly waived a future-update
# reserve; do not silently require 4 MiB or attempt to consume all free flash.
required_kib=$(( (payload_bytes+backup_bytes+1023)/1024+512 ))
echo "HOME NET native agent: requires ${required_kib} KiB now, available ${free_kib} KiB"
[ "$free_kib" -ge "$required_kib" ] || fail 'not enough space to complete this installation'
[ "$mode" != --preflight ] || exit 0
mkdir -p /etc/home-net/keys /etc/home-net/vpn /etc/home-net/native-agent-backups
chmod 0700 /etc/home-net/keys /etc/home-net/native-agent-backups
backup=$(mktemp -d /etc/home-net/native-agent-backups/install.XXXXXX)
mkdir "$backup/files"
for target in $targets; do
    printf '%s\n' "$target" >>"$backup/targets"
    if [ -f "$target" ]; then mkdir -p "$backup/files/$(dirname "${target#/}")"; ln "$target" "$backup/files/${target#/}" || fail 'cannot retain existing code without copying'; fi
done
for file in /etc/config/network /etc/config/podkop /etc/podkop-awg-failover.conf; do [ ! -f "$file" ] || sha256sum "$file"; done >"$backup/protected.sha256"
set -- $payloads
for target in $targets; do
    temporary=$(mktemp "${target%/*}/.home-net-native.XXXXXX")
    staged="$staged $temporary"
    cp "$1" "$temporary"; chmod 0700 "$temporary"
    printf '%s %s\n' "$temporary" "$target" >>"$backup/staged"
    shift
done
if [ -x /etc/init.d/vpn-control-cudy ] && /etc/init.d/vpn-control-cudy running >/dev/null 2>&1; then was_running=1; fi
if [ -x /etc/init.d/vpn-control-cudy ]; then /etc/init.d/vpn-control-cudy stop >/dev/null 2>&1 || fail 'agent did not stop'; fi
dirty=1
while read -r temporary target; do mv "$temporary" "$target"; done <"$backup/staged"
staged=
/usr/sbin/vpn-control-cudy identity-init
chmod 0600 /etc/home-net/keys/age-identity.txt
if [ ! -f /etc/home-net/vpn/podkop-section ]; then
    section=$(sed -n "s/^PODKOP_SECTION='\([A-Za-z0-9_]*\)'$/\1/p" /etc/podkop-awg-failover.conf)
    case "$section" in ''|*[!A-Za-z0-9_]*) fail 'local Podkop section requires review' ;; esac
    uci -q get "podkop.$section" >/dev/null || fail 'local Podkop section missing'
    printf '%s\n' "$section" >/etc/home-net/vpn/podkop-section
fi
if grep -Fxq "INSTALLED_VERSION='1.5.0'" /etc/podkop-awg-failover.conf; then printf '%s\n' 1.5.0 >/etc/home-net/vpn/failover-lock-version; fi
sha256sum -c "$backup/protected.sha256" >/dev/null || fail 'protected configuration changed'
/etc/init.d/vpn-control-cudy enable
/etc/init.d/vpn-control-cudy start
/etc/init.d/vpn-control-cudy running >/dev/null 2>&1 || fail 'agent did not start'
for target in $targets; do sha256sum "$target"; done >/etc/home-net/native-agent-files.sha256
dirty=0
# Retain the successful upgrade's immediate rollback snapshot. Only after the
# new service is running, discard older *completed* native installer snapshots.
# Never remove incomplete/unknown directories or the current rollback.
for old in /etc/home-net/native-agent-backups/install.*; do
    [ -d "$old" ] && [ ! -L "$old" ] && [ "$old" != "$backup" ] || continue
    [ -d "$old/files" ] && [ ! -L "$old/files" ] || continue
    [ -f "$old/targets" ] && [ ! -L "$old/targets" ] || continue
    [ -f "$old/protected.sha256" ] && [ ! -L "$old/protected.sha256" ] || continue
    [ -f "$old/staged" ] && [ ! -L "$old/staged" ] || continue
    grep -Fxq '/usr/sbin/vpn-control-cudy' "$old/targets" || continue
    rm -rf -- "$old" || echo "WARNING: old native backup not pruned: $old" >&2
done
echo "HOME NET native agent installed; backup: $backup; network and routes unchanged"
