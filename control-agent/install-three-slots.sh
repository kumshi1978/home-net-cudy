#!/bin/sh
set -eu
umask 077
fail() { echo "HOME NET controller: $*" >&2; exit 1; }
[ "$(id -u)" = 0 ] || fail 'root required'
ref=${HOME_NET_CONTROL_REF:-}
printf '%s\n' "$ref" | grep -Eq '^[0-9a-f]{40}$' || fail 'immutable source required'
[ "${HOME_NET_STAGE_ONLY:-0}" != 1 ] || exit 0
lock=/var/run/home-net-vpn-maintenance.lock
[ ! -L "$lock" ] || fail 'unsafe lock'
command -v flock >/dev/null 2>&1 || fail 'flock required'
if ! [ /proc/self/fd/9 -ef "$lock" ]; then exec 9>>"$lock"; fi
flock -n 9 || fail 'VPN maintenance busy'
config=/etc/home-net/vpn
for path in /etc/home-net "$config" "$config/adapter" "$config/transaction" /usr/bin/home-net-vpn-router /usr/bin/home-net-vpn-persist.py; do
    [ ! -L "$path" ] || fail 'unsafe installation path'
done
phase=idle
[ ! -f "$config/transaction/phase" ] || phase=$(cat "$config/transaction/phase")
case "$phase" in idle|verified) ;; *) fail 'unfinished transaction requires review before upgrade' ;; esac
# Known reviewed two-slot adapter/controller, including the newline-only canary copy.
if [ -f "$config/adapter" ]; then
    current=$(sha256sum "$config/adapter" | cut -d ' ' -f1)
    case "$current" in 450f6070aa11925917149c6e1ff349f50a257d6a89b1a8e7bca07ff9ebaff070|7fb7f1464b908e4dd8dad9c003bd0b228fca839c04b2cd5fb6df4395ae58d0ea|c297829fa2148a5aa055c92c0d637b23aa6adf3969f425f3e461e109ad488d54|72e7fd7d7334ffe990377f31da7fc93ad2ae031dfbc409a0aefbad80b9174046) ;;
        *) fail 'custom adapter preserved; review required' ;; esac
fi
if [ -f /usr/bin/home-net-vpn-router ]; then
    current=$(sha256sum /usr/bin/home-net-vpn-router | cut -d ' ' -f1)
    case "$current" in 5ac78c50fe2e163bd42ec45b6101452c5322c6809a81b6cc8defbc27115cf704|b37acc7146fee71e324f7a92d65e011fe95dad7a2a96790de373b2c502030743|f882f28f83a698c333e85d062f92fde86a19b4eacf0a5b081bee64d434675a60|f7942ee4d2a06421e477ed1ec1477a4fe9facdec4b2596cc8df275b30cad50ba) ;;
        *) fail 'custom controller preserved; review required' ;; esac
fi
work=$(mktemp -d /tmp/home-net-controller.XXXXXX)
trap 'rm -rf "$work"' EXIT
trap 'exit 1' HUP INT TERM
wget -q -T 60 -O "$work/home-net-vpn-router" "https://raw.githubusercontent.com/kumshi1978/home-net-cudy/$ref/scripts/home-net-vpn-router" || fail 'download failed'
echo '5ac78c50fe2e163bd42ec45b6101452c5322c6809a81b6cc8defbc27115cf704  '"$work/home-net-vpn-router" | sha256sum -c - || fail 'integrity mismatch'
wget -q -T 60 -O "$work/home-net-vpn-cudy-adapter" "https://raw.githubusercontent.com/kumshi1978/home-net-cudy/$ref/scripts/home-net-vpn-cudy-adapter" || fail 'download failed'
echo '450f6070aa11925917149c6e1ff349f50a257d6a89b1a8e7bca07ff9ebaff070  '"$work/home-net-vpn-cudy-adapter" | sha256sum -c - || fail 'integrity mismatch'
wget -q -T 60 -O "$work/home-net-vpn-manifest-validate" "https://raw.githubusercontent.com/kumshi1978/home-net-cudy/$ref/scripts/home-net-vpn-manifest-validate" || fail 'download failed'
echo '9d99142b237ebf221b8acd18604601dc954c0e71bb42f9f06ef700698bceb745  '"$work/home-net-vpn-manifest-validate" | sha256sum -c - || fail 'integrity mismatch'
wget -q -T 60 -O "$work/home-net-vpn-persist.py" "https://raw.githubusercontent.com/kumshi1978/home-net-cudy/$ref/scripts/home-net-vpn-persist.py" || fail 'download failed'
echo '98454b13b657d7ce7ffd5986d38cb91acf8ccadf17e3aaa455115f5d25fac29b  '"$work/home-net-vpn-persist.py" | sha256sum -c - || fail 'integrity mismatch'
for file in home-net-vpn-router home-net-vpn-cudy-adapter home-net-vpn-manifest-validate; do sh -n "$work/$file" || fail 'invalid shell'; done
python3 -c 'import ast,sys; ast.parse(open(sys.argv[1]).read())' "$work/home-net-vpn-persist.py"
backup=/etc/home-net/controller-backups
[ ! -L "$backup" ] || fail 'unsafe backup directory'
mkdir -p "$backup" "$config"
backup=$(mktemp -d "$backup/install.XXXXXX")
for file in /usr/bin/home-net-vpn-router /usr/bin/home-net-vpn-manifest-validate /usr/bin/home-net-vpn-persist.py "$config/adapter"; do
    [ ! -L "$file" ] || fail 'unsafe target'
    [ ! -f "$file" ] || cp -p "$file" "$backup/$(basename "$file")"
done
install_atomic() {
    if [ -f "$2" ] && cmp -s "$1" "$2"; then return; fi
    temporary=$(mktemp "${2%/*}/.home-net-controller.XXXXXX")
    cp "$1" "$temporary"; chmod 0700 "$temporary"; mv "$temporary" "$2"
}
install_atomic "$work/home-net-vpn-persist.py" /usr/bin/home-net-vpn-persist.py
install_atomic "$work/home-net-vpn-manifest-validate" /usr/bin/home-net-vpn-manifest-validate
install_atomic "$work/home-net-vpn-router" /usr/bin/home-net-vpn-router
install_atomic "$work/home-net-vpn-cudy-adapter" "$config/adapter"
if [ ! -e "$config/podkop-section" ]; then
    # Reuse the local section already selected by the common Failover installer.
    # No panel-supplied section name and no network changes are accepted here.
    section=$(sed -n "s/^PODKOP_SECTION='\([A-Za-z0-9_]*\)'$/\1/p" /etc/podkop-awg-failover.conf)
    case "$section" in ''|*[!A-Za-z0-9_]*) fail 'local Podkop section requires review' ;; esac
    uci -q get "podkop.$section" >/dev/null || fail 'local Podkop section missing'
    temporary=$(mktemp "$config/.podkop-section.XXXXXX")
    printf '%s\n' "$section" > "$temporary"; chmod 0600 "$temporary"; mv "$temporary" "$config/podkop-section"
fi
if grep -Fxq "INSTALLED_VERSION='1.5.0'" /etc/podkop-awg-failover.conf; then
    temporary=$(mktemp "$config/.lock-contract.XXXXXX")
    printf '%s\n' 1.5.0 > "$temporary"; chmod 0600 "$temporary"; mv "$temporary" "$config/failover-lock-version"
fi
echo 'HOME NET controller: three-slot code installed; active route and network unchanged'
