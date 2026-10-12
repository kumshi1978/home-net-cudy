#!/bin/sh
# HOME NET Cudy
# Monitoring installer
# Version: 1.7.2

set -e

BASE_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
CONF_SRC="$BASE_DIR/../configs/podkop-service-check.conf.example"
CONF_DST="/etc/podkop-service-check.conf"
LOG_CONF_SRC="$BASE_DIR/../configs/home-net-log.conf.example"
LOG_CONF_DST="/etc/home-net-log.conf"

DAEMON_SRC="$BASE_DIR/../scripts/podkop-service-health-daemon"
CHECK_SRC="$BASE_DIR/../scripts/podkop-service-check"
FAKEIP_SRC="$BASE_DIR/../scripts/podkop-fakeip-check"
EVENT_MONITOR_SRC="$BASE_DIR/../scripts/podkop-event-monitor"
EVENT_RUNNER_SRC="$BASE_DIR/../scripts/podkop-event-runner"
COUNTRY_LOOKUP_SRC="$BASE_DIR/../scripts/podkop-country-lookup"
INIT_SRC="$BASE_DIR/../init.d/podkop-service-health"

LOG_DAEMON_SRC="$BASE_DIR/../scripts/home-net-log-daemon"
LOG_CLI_SRC="$BASE_DIR/../scripts/home-net-log"
LOG_INIT_SRC="$BASE_DIR/../init.d/home-net-log"

STATUS_SRC="$BASE_DIR/../scripts/home-net-status"
CONTROL_SRC="$BASE_DIR/../scripts/home-net-control"
MANAGEMENT_SRC="$BASE_DIR/../scripts/home-net-management"
VERIFY_SRC="$BASE_DIR/../scripts/home-net-install-verify"
PODKOP_UPDATE_SRC="$BASE_DIR/../scripts/home-net-podkop-update"
LUCI_VIEW_SRC="$BASE_DIR/../luci/view/home-net/status.js"
LUCI_MENU_SRC="$BASE_DIR/../luci/menu.d/luci-app-home-net.json"
LUCI_ACL_SRC="$BASE_DIR/../luci/acl.d/luci-app-home-net.json"

fail() {
    echo "ERROR: $*" >&2
    exit 1
}

[ -f /etc/openwrt_release ] || fail "OpenWrt not detected"
for view in status updates logs vpn settings; do
    [ -f "$BASE_DIR/../luci/view/home-net/$view.js" ] || fail "missing LuCI view $view"
done
[ -f "$BASE_DIR/../luci/home-net/common.js" ] || fail "missing LuCI shared module"

check_file() {
    [ -f "$1" ] || fail "missing file $1"
}

for FILE in \
    "$DAEMON_SRC" \
    "$CHECK_SRC" \
    "$FAKEIP_SRC" \
    "$EVENT_MONITOR_SRC" \
    "$EVENT_RUNNER_SRC" \
    "$COUNTRY_LOOKUP_SRC" \
    "$INIT_SRC" \
    "$CONF_SRC" \
    "$LOG_DAEMON_SRC" \
    "$LOG_CLI_SRC" \
    "$LOG_INIT_SRC" \
    "$LOG_CONF_SRC" \
    "$STATUS_SRC" \
    "$CONTROL_SRC" \
    "$MANAGEMENT_SRC" \
    "$PODKOP_UPDATE_SRC" \
    "$VERIFY_SRC" \
    "$LUCI_VIEW_SRC" \
    "$LUCI_MENU_SRC" \
    "$LUCI_ACL_SRC"
do
    check_file "$FILE"
done

for FILE in \
    "$DAEMON_SRC" \
    "$CHECK_SRC" \
    "$FAKEIP_SRC" \
    "$EVENT_MONITOR_SRC" \
    "$EVENT_RUNNER_SRC" \
    "$COUNTRY_LOOKUP_SRC" \
    "$LOG_DAEMON_SRC" \
    "$LOG_CLI_SRC" \
    "$STATUS_SRC" \
    "$CONTROL_SRC" \
    "$MANAGEMENT_SRC" \
    "$PODKOP_UPDATE_SRC" \
    "$VERIFY_SRC" \
    "$INIT_SRC" \
    "$LOG_INIT_SRC"
do
    sh -n "$FILE"
done

# Refuse an inconsistent baseline before changing any installed files.
sh "$VERIFY_SRC" services
sh "$VERIFY_SRC" health
BEFORE_CHECK=$(sed -n 's/^LAST_CHECK=//p' /tmp/podkop-service-health/state)

BACKUP_DIR="/root/backup-podkop-install"
mkdir -p "$BACKUP_DIR"

for FILE in \
    /usr/bin/podkop-service-health-daemon \
    /usr/bin/podkop-service-check \
    /usr/bin/podkop-fakeip-check \
    /usr/bin/podkop-event-monitor \
    /usr/bin/podkop-event-runner \
    /usr/bin/podkop-country-lookup \
    /usr/bin/home-net-log-daemon \
    /usr/bin/home-net-log \
    /usr/bin/home-net-status \
    /usr/bin/home-net-control \
    /usr/bin/home-net-management \
    /usr/bin/home-net-podkop-update \
    /usr/bin/home-net-install-verify \
    /www/luci-static/resources/home-net/common.js \
    /www/luci-static/resources/view/home-net/updates.js \
    /www/luci-static/resources/view/home-net/logs.js \
    /www/luci-static/resources/view/home-net/vpn.js \
    /www/luci-static/resources/view/home-net/settings.js \
    /www/luci-static/resources/view/home-net/status.js \
    /usr/share/luci/menu.d/luci-app-home-net.json \
    /usr/share/rpcd/acl.d/luci-app-home-net.json \
    /etc/init.d/podkop-service-health \
    /etc/init.d/home-net-log \
    "$CONF_DST" \
    "$LOG_CONF_DST"
do
    [ -f "$FILE" ] && cp -p "$FILE" "$BACKUP_DIR/"
done

install_executable() {
    cp "$1" "$2"
    chmod 0755 "$2"
}
install_executable "$DAEMON_SRC" /usr/bin/podkop-service-health-daemon
install_executable "$CHECK_SRC" /usr/bin/podkop-service-check
install_executable "$FAKEIP_SRC" /usr/bin/podkop-fakeip-check
install_executable "$EVENT_MONITOR_SRC" /usr/bin/podkop-event-monitor
install_executable "$EVENT_RUNNER_SRC" /usr/bin/podkop-event-runner
install_executable "$COUNTRY_LOOKUP_SRC" /usr/bin/podkop-country-lookup
install_executable "$INIT_SRC" /etc/init.d/podkop-service-health

install_executable "$LOG_DAEMON_SRC" /usr/bin/home-net-log-daemon
install_executable "$LOG_CLI_SRC" /usr/bin/home-net-log
install_executable "$LOG_INIT_SRC" /etc/init.d/home-net-log

# BEGIN LUCI FILE INSTALL
install_luci_file() {
    cp "$1" "$2"
    chmod 0644 "$2"
}
# END LUCI FILE INSTALL
mkdir -p /www/luci-static/resources/view/home-net /usr/share/luci/menu.d /usr/share/rpcd/acl.d
install_executable "$STATUS_SRC" /usr/bin/home-net-status
install_executable "$CONTROL_SRC" /usr/bin/home-net-control
install_executable "$MANAGEMENT_SRC" /usr/bin/home-net-management
install_executable "$VERIFY_SRC" /usr/bin/home-net-install-verify
install_executable "$PODKOP_UPDATE_SRC" /usr/bin/home-net-podkop-update
sh /usr/bin/home-net-install-verify runtime
mkdir -p /www/luci-static/resources/home-net
install_luci_file "$BASE_DIR/../luci/home-net/common.js" /www/luci-static/resources/home-net/common.js
for view in updates logs vpn settings; do
    install_luci_file "$BASE_DIR/../luci/view/home-net/$view.js" "/www/luci-static/resources/view/home-net/$view.js"
done
install_luci_file "$LUCI_VIEW_SRC" /www/luci-static/resources/view/home-net/status.js
install_luci_file "$LUCI_MENU_SRC" /usr/share/luci/menu.d/luci-app-home-net.json
install_luci_file "$LUCI_ACL_SRC" /usr/share/rpcd/acl.d/luci-app-home-net.json

chmod 0644 /www/luci-static/resources/view/home-net/*.js /www/luci-static/resources/home-net/*.js
chmod 0755 /www/luci-static/resources/view/home-net /www/luci-static/resources/home-net /usr/share/luci/menu.d /usr/share/rpcd/acl.d
sh /usr/bin/home-net-install-verify luci

if [ ! -f "$CONF_DST" ]; then
    cp "$CONF_SRC" "$CONF_DST"
else
    OLD_FAKEIP='FAKEIP_DOMAINS="github.com unifi.ui.com claude.ai gemini.google.com"'
    if grep -Fxq "$OLD_FAKEIP" "$CONF_DST"; then
        sed -i 's|^FAKEIP_DOMAINS="github.com unifi.ui.com claude.ai gemini.google.com"$|FAKEIP_DOMAINS="github.com claude.ai gemini.google.com"|' "$CONF_DST"
        echo "Migrated legacy default FAKEIP_DOMAINS; custom values are preserved"
    fi
fi

if [ ! -f "$LOG_CONF_DST" ]; then
    cp "$LOG_CONF_SRC" "$LOG_CONF_DST"
fi

/etc/init.d/podkop-service-health enable
if /etc/init.d/podkop-service-health running; then
    /etc/init.d/podkop-service-health stop
fi
# Stop the old producer before recording the boundary, then launch the new one.
# Keep strict freshness with second-resolution timestamps: its first cycle must
# start in a later second, even when procd starts it immediately.
BEFORE_CHECK=$(sed -n 's/^LAST_CHECK=//p' /tmp/podkop-service-health/state)
MONITORING_INITIALIZED_EPOCH=$(date +%s)
sleep 1
/etc/init.d/podkop-service-health start

/etc/init.d/home-net-log enable
if /etc/init.d/home-net-log running; then
    /etc/init.d/home-net-log restart
else
    /etc/init.d/home-net-log start
fi

# LuCI executes the bundle through rpcd and inherits its output pipes. Restarting
# rpcd here closes their readers: the next progress echo fails with EPIPE (or
# SIGPIPE), aborting this set -e installer before the first health cycle.
# Reload also replaces rpcd, so neither operation is safe inside an update.
if [ "${HOME_NET_UPDATE_IN_PROGRESS:-0}" != 1 ]; then
    /etc/init.d/rpcd restart
fi
# Monitoring installation does not control Podkop or sing-box. Podkop's
# one-shot initialization may legitimately have no persistent procd process.
verified=0
waiting_reported=0
verification_deadline=$((MONITORING_INITIALIZED_EPOCH + 600))
verification_log="$BACKUP_DIR/install-verification.log"
: > "$verification_log"
chmod 0600 "$verification_log"
for attempt in $(seq 1 60); do
    now=$(date +%s)
    [ "$now" -lt "$verification_deadline" ] || break
    current_check=$(sed -n 's/^LAST_CHECK=//p' /tmp/podkop-service-health/state)
    if [ -n "$current_check" ] && [ "$current_check" != "$BEFORE_CHECK" ] &&
        HOME_NET_VERIFY_AFTER_EPOCH="$MONITORING_INITIALIZED_EPOCH" sh /usr/bin/home-net-install-verify all > "$verification_log" 2>&1; then
        cat "$verification_log"
        verified=1
        break
    fi
    if [ -z "$current_check" ] || [ "$current_check" = "$BEFORE_CHECK" ]; then
        echo 'WAIT: no new completed health cycle available' > "$verification_log"
    fi
    if [ "$waiting_reported" = 0 ]; then
        echo 'Waiting for a completed healthy cycle after initialization (timeout: 600 seconds)'
        waiting_reported=1
    fi
    remaining=$((verification_deadline - $(date +%s)))
    [ "$remaining" -gt 0 ] || break
    [ "$remaining" -le 10 ] || remaining=10
    [ "$attempt" -lt 60 ] || break
    sleep "$remaining"
done
if [ "$verified" != 1 ]; then
    cat "$verification_log" >&2
    fail "installed service/lifecycle/health verification timed out (600-second deadline / 60 attempts); retain backup: $BACKUP_DIR; diagnostics: $verification_log"
fi
rm -f /tmp/luci-indexcache 2>/dev/null || true
rm -rf /tmp/luci-modulecache 2>/dev/null || true

echo "HOME NET Podkop Monitor v1.7.2 installed"
echo "LuCI page: Services -> HOME NET"
echo "Domain capture remains disabled until explicitly enabled."
