#!/bin/sh
set -eu

BUNDLE_URL="https://raw.githubusercontent.com/kumshi1978/home-net-cudy/feature/unified-installer/bundle.conf"
TMP_DIR="/tmp/home-net-bundle.$$"
BUNDLE_CONF="$TMP_DIR/bundle.conf"
FAILOVER_INSTALL="$TMP_DIR/failover-install.sh"
MONITORING_INSTALL="$TMP_DIR/monitoring-install.sh"

fail() { echo "ERROR: $*" >&2; exit 1; }
cleanup() { rm -rf "$TMP_DIR"; }
trap cleanup EXIT HUP INT TERM

[ -f /etc/openwrt_release ] || fail "OpenWrt not detected"
mkdir -p "$TMP_DIR"

fetch() {
    url="$1"
    out="$2"
    if command -v wget >/dev/null 2>&1; then
        wget -q -O "$out" "$url" || fail "download failed: $url"
    elif command -v curl >/dev/null 2>&1; then
        curl -fL --connect-timeout 10 --max-time 120 -o "$out" "$url" || fail "download failed: $url"
    else
        fail "wget or curl is required"
    fi
}

fetch "$BUNDLE_URL" "$BUNDLE_CONF"
. "$BUNDLE_CONF"

case "$DEFAULT_AUTO_UPDATE_MODE" in check|apply) ;; *) fail "invalid DEFAULT_AUTO_UPDATE_MODE" ;; esac

printf 'HOME NET bundle %s\n' "$HOME_NET_BUNDLE_VERSION"
printf 'Failover %s, Monitoring %s\n' "$FAILOVER_VERSION" "$MONITORING_VERSION"

FAILOVER_URL="https://raw.githubusercontent.com/$FAILOVER_REPO/v$FAILOVER_VERSION/install.sh"
MONITORING_URL="https://raw.githubusercontent.com/$MONITORING_REPO/$MONITORING_BOOTSTRAP_REF/install.sh"

fetch "$FAILOVER_URL" "$FAILOVER_INSTALL"
fetch "$MONITORING_URL" "$MONITORING_INSTALL"

sh -n "$FAILOVER_INSTALL" || fail "failover installer syntax check failed"
sh -n "$MONITORING_INSTALL" || fail "monitoring installer syntax check failed"

grep -Fq "SCRIPT_VERSION=\"$FAILOVER_VERSION\"" "$FAILOVER_INSTALL" || fail "failover installer version mismatch"

printf '\n===== INSTALL FAILOVER =====\n'
UPDATE_SOURCE_REF="v$FAILOVER_VERSION" APPLY_NOW=1 sh "$FAILOVER_INSTALL"

printf '\n===== SET AUTO UPDATE MODE =====\n'
if [ -f /etc/podkop-awg-update.conf ]; then
    sed -i "s/^AUTO_UPDATE_MODE='[^']*'/AUTO_UPDATE_MODE='$DEFAULT_AUTO_UPDATE_MODE'/" /etc/podkop-awg-update.conf
    /etc/init.d/podkop-awg-update restart >/dev/null 2>&1 || true
fi

printf '\n===== INSTALL MONITORING =====\n'
sh "$MONITORING_INSTALL"

printf '\n===== FINAL CHECK =====\n'
grep '^INSTALLED_VERSION=' /etc/podkop-awg-failover.conf 2>/dev/null || true
uci -q get podkop.main.interface 2>/dev/null || true
pgrep -af '/usr/bin/podkop-awg-update' 2>/dev/null || true
pgrep -af '/usr/bin/podkop-awg-failover' 2>/dev/null || true
pgrep -af '/usr/bin/podkop-health' 2>/dev/null || true
cat /tmp/podkop-service-health/state 2>/dev/null || true

printf '\nHOME NET bundle installation complete.\n'
