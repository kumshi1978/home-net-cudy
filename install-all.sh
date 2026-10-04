#!/bin/sh
set -eu

BUNDLE_REF="${HOME_NET_BUNDLE_REF:-main}"
BUNDLE_URL="https://raw.githubusercontent.com/kumshi1978/home-net-cudy/$BUNDLE_REF/bundle.conf"
TMP_DIR="/tmp/home-net-bundle.$$"
BUNDLE_CONF="$TMP_DIR/bundle.conf"
FAILOVER_INSTALL="$TMP_DIR/failover-install.sh"
MONITORING_INSTALL="$TMP_DIR/monitoring-install.sh"
HOME_NET_UPDATE_SRC="$TMP_DIR/home-net-update"
HOME_NET_UPDATE_INIT_SRC="$TMP_DIR/home-net-update.init"
HOME_NET_UPDATE_CONF_SRC="$TMP_DIR/home-net-update.conf"
HOME_NET_UPDATE_STATE="/etc/home-net-update.state"

fail() { echo "ERROR: $*" >&2; exit 1; }
cleanup() { rm -rf "$TMP_DIR"; }
trap cleanup EXIT HUP INT TERM

[ -f /etc/openwrt_release ] || fail "OpenWrt not detected"
mkdir -p "$TMP_DIR"

fetch() {
    url="$1"
    out="$2"
    if command -v wget >/dev/null 2>&1; then
        wget -q -T 120 -O "$out" "$url" || fail "download failed: $url"
    elif command -v curl >/dev/null 2>&1; then
        curl -fL --connect-timeout 10 --max-time 120 -o "$out" "$url" || fail "download failed: $url"
    else
        fail "wget or curl is required"
    fi
}

fetch "$BUNDLE_URL" "$BUNDLE_CONF"
. "$BUNDLE_CONF"

case "$UPDATE_ACTION_CLASS" in SAFE|CONTROLLED|CRITICAL) ;; *) fail "invalid UPDATE_ACTION_CLASS in bundle.conf" ;; esac
ACTION_CLASS="${HOME_NET_ACTION_CLASS:-$UPDATE_ACTION_CLASS}"
[ "$ACTION_CLASS" = "$UPDATE_ACTION_CLASS" ] || fail "HOME_NET_ACTION_CLASS does not match bundle.conf"
case "${HOME_NET_STAGE_ONLY:-0}" in 0|1) ;; *) fail "HOME_NET_STAGE_ONLY must be 0 or 1" ;; esac

if [ "${HOME_NET_AUTO_UPDATE_MODE+x}" = "x" ]; then
    AUTO_UPDATE_MODE="$HOME_NET_AUTO_UPDATE_MODE"
elif [ -r /etc/podkop-awg-update.conf ]; then
    AUTO_UPDATE_MODE="$(sed -n "s/^AUTO_UPDATE_MODE='\([^']*\)'$/\1/p" /etc/podkop-awg-update.conf | tail -n 1)"
    [ -n "$AUTO_UPDATE_MODE" ] || AUTO_UPDATE_MODE="$DEFAULT_AUTO_UPDATE_MODE"
else
    AUTO_UPDATE_MODE="$DEFAULT_AUTO_UPDATE_MODE"
fi
case "$AUTO_UPDATE_MODE" in check|apply) ;; *) fail "HOME_NET_AUTO_UPDATE_MODE must be check or apply" ;; esac

printf 'HOME NET bundle %s\n' "$HOME_NET_BUNDLE_VERSION"
printf 'Failover %s, Monitoring %s, auto-update %s, action class %s\n' "$FAILOVER_VERSION" "$MONITORING_VERSION" "$AUTO_UPDATE_MODE" "$ACTION_CLASS"

FAILOVER_URL="https://raw.githubusercontent.com/$FAILOVER_REPO/v$FAILOVER_VERSION/install.sh"
MONITORING_URL="https://raw.githubusercontent.com/$MONITORING_REPO/$MONITORING_BOOTSTRAP_REF/install.sh"
HOME_NET_UPDATE_URL="https://raw.githubusercontent.com/kumshi1978/home-net-cudy/$BUNDLE_REF/scripts/home-net-update"
HOME_NET_UPDATE_INIT_URL="https://raw.githubusercontent.com/kumshi1978/home-net-cudy/$BUNDLE_REF/init.d/home-net-update"
HOME_NET_UPDATE_CONF_URL="https://raw.githubusercontent.com/kumshi1978/home-net-cudy/$BUNDLE_REF/configs/home-net-update.conf.example"

fetch "$MONITORING_URL" "$MONITORING_INSTALL"
fetch "$HOME_NET_UPDATE_URL" "$HOME_NET_UPDATE_SRC"
fetch "$HOME_NET_UPDATE_INIT_URL" "$HOME_NET_UPDATE_INIT_SRC"
fetch "$HOME_NET_UPDATE_CONF_URL" "$HOME_NET_UPDATE_CONF_SRC"

sh -n "$MONITORING_INSTALL" || fail "monitoring installer syntax check failed"
sh -n "$HOME_NET_UPDATE_SRC" || fail "HOME NET updater syntax check failed"
sh -n "$HOME_NET_UPDATE_INIT_SRC" || fail "HOME NET updater init syntax check failed"

INSTALLED_FAILOVER="$(sed -n "s/^INSTALLED_VERSION='\([^']*\)'$/\1/p" /etc/podkop-awg-failover.conf 2>/dev/null | tail -n 1)"
NEED_FAILOVER=0
[ "$INSTALLED_FAILOVER" = "$FAILOVER_VERSION" ] || NEED_FAILOVER=1

if [ "$NEED_FAILOVER" = "1" ] && [ "${HOME_NET_STAGE_ONLY:-0}" != "1" ]; then
    if [ "$ACTION_CLASS" = "SAFE" ] && [ "${HOME_NET_UPDATE_IN_PROGRESS:-0}" = "1" ]; then
        fail "SAFE automatic update cannot change the runtime failover version"
    fi
    fetch "$FAILOVER_URL" "$FAILOVER_INSTALL"
    sh -n "$FAILOVER_INSTALL" || fail "failover installer syntax check failed"
    grep -Fq "SCRIPT_VERSION=\"$FAILOVER_VERSION\"" "$FAILOVER_INSTALL" || fail "failover installer version mismatch"
    if grep -Eq '(^|[;&|[:space:]])(/etc/init\.d/network|service[[:space:]]+network)[[:space:]]+(restart|reload)|(^|[;&|[:space:]])reboot([;&|[:space:]]|$)|ubus[[:space:]]+call[[:space:]]+system[[:space:]]+reboot|shutdown[[:space:]].*-r' "$FAILOVER_INSTALL"; then
        fail "failover installer contains a forbidden network restart or reboot"
    fi
fi

if [ "${HOME_NET_STAGE_ONLY:-0}" = "1" ]; then
    printf '\n===== STAGE ONLY: RUNTIME FAILOVER ACTIVATION SKIPPED =====\n'
elif [ "$NEED_FAILOVER" = "1" ]; then
    printf '\n===== INSTALL FAILOVER (CONTROLLED) =====\n'
    UPDATE_SOURCE_REF="v$FAILOVER_VERSION" APPLY_NOW=1 sh "$FAILOVER_INSTALL"
else
    printf '\n===== FAILOVER ALREADY AT REQUIRED VERSION =====\n'
fi

printf '\n===== SET AUTO UPDATE MODE =====\n'
if [ "${HOME_NET_STAGE_ONLY:-0}" != "1" ] && [ -f /etc/podkop-awg-update.conf ]; then
    sed -i "s/^AUTO_UPDATE_MODE='[^']*'/AUTO_UPDATE_MODE='$AUTO_UPDATE_MODE'/" /etc/podkop-awg-update.conf
    /etc/init.d/podkop-awg-update restart >/dev/null 2>&1 || true
fi

printf '\n===== INSTALL MONITORING =====\n'
sh "$MONITORING_INSTALL"

printf '\n===== INSTALL HOME NET UPDATER =====\n'
UPDATER_BACKUP="/root/home-net-updater-backup-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$UPDATER_BACKUP"
for FILE in /usr/bin/home-net-update /etc/init.d/home-net-update /etc/home-net-update.conf "$HOME_NET_UPDATE_STATE"
do
    [ -f "$FILE" ] && cp -p "$FILE" "$UPDATER_BACKUP/"
done

cp "$HOME_NET_UPDATE_SRC" /usr/bin/home-net-update
cp "$HOME_NET_UPDATE_INIT_SRC" /etc/init.d/home-net-update
chmod 0755 /usr/bin/home-net-update /etc/init.d/home-net-update

if [ ! -f /etc/home-net-update.conf ]; then
    cp "$HOME_NET_UPDATE_CONF_SRC" /etc/home-net-update.conf
    chmod 0600 /etc/home-net-update.conf
fi

/etc/init.d/home-net-update enable
if [ "${HOME_NET_UPDATE_IN_PROGRESS:-0}" != "1" ]; then
    /etc/init.d/home-net-update restart
fi

printf '\n===== FINAL CHECK =====\n'
grep '^INSTALLED_VERSION=' /etc/podkop-awg-failover.conf 2>/dev/null || true
uci -q get podkop.main.interface 2>/dev/null || true
pgrep -af '/usr/bin/podkop-awg-update' 2>/dev/null || true
pgrep -af '/usr/bin/podkop-awg-failover' 2>/dev/null || true
pgrep -af '/usr/bin/podkop-health' 2>/dev/null || true
cat /tmp/podkop-service-health/state 2>/dev/null || true

if [ "${HOME_NET_SKIP_VERSION_RECORD:-0}" != "1" ]; then
    FINAL_HEALTH_STATUS="$(sed -n 's/^STATUS=//p' /tmp/podkop-service-health/state 2>/dev/null | tail -n 1)"
    [ -n "$FINAL_HEALTH_STATUS" ] || FINAL_HEALTH_STATUS=UNKNOWN
    STATE_TMP="$HOME_NET_UPDATE_STATE.tmp.$$"
    {
        printf "INSTALLED_VERSION='%s'\n" "$HOME_NET_BUNDLE_VERSION"
        printf "ACTIVE_VERSION='%s'\n" "$HOME_NET_BUNDLE_VERSION"
        printf "UPDATE_STATUS='OK'\n"
        printf "PENDING_ACTION='none'\n"
        printf "PENDING_REASON='none'\n"
        printf "PENDING_VERSION='none'\n"
        printf "PENDING_BOOT_ID='none'\n"
        printf "LAST_UPDATE='%s'\n" "$(date '+%F %T')"
        printf "LAST_HEALTH_STATUS='%s'\n" "$FINAL_HEALTH_STATUS"
        printf "INSTALL_SOURCE='install-all'\n"
    } > "$STATE_TMP"
    chmod 0600 "$STATE_TMP"
    mv "$STATE_TMP" "$HOME_NET_UPDATE_STATE"
fi

printf '\nHOME NET bundle installation complete.\n'
