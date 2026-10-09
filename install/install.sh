#!/bin/sh
# HOME NET Cudy
# Monitoring installer
# Version: 1.6.0

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
LUCI_VIEW_SRC="$BASE_DIR/../luci/view/home-net/status.js"
LUCI_MENU_SRC="$BASE_DIR/../luci/menu.d/luci-app-home-net.json"
LUCI_ACL_SRC="$BASE_DIR/../luci/acl.d/luci-app-home-net.json"

fail() {
    echo "ERROR: $*" >&2
    exit 1
}

[ -f /etc/openwrt_release ] || fail "OpenWrt not detected"

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
    "$INIT_SRC" \
    "$LOG_INIT_SRC"
do
    sh -n "$FILE"
done

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

cp "$DAEMON_SRC" /usr/bin/podkop-service-health-daemon
cp "$CHECK_SRC" /usr/bin/podkop-service-check
cp "$FAKEIP_SRC" /usr/bin/podkop-fakeip-check
cp "$EVENT_MONITOR_SRC" /usr/bin/podkop-event-monitor
cp "$EVENT_RUNNER_SRC" /usr/bin/podkop-event-runner
cp "$COUNTRY_LOOKUP_SRC" /usr/bin/podkop-country-lookup
cp "$INIT_SRC" /etc/init.d/podkop-service-health

cp "$LOG_DAEMON_SRC" /usr/bin/home-net-log-daemon
cp "$LOG_CLI_SRC" /usr/bin/home-net-log
cp "$LOG_INIT_SRC" /etc/init.d/home-net-log

mkdir -p /www/luci-static/resources/view/home-net /usr/share/luci/menu.d /usr/share/rpcd/acl.d
cp "$STATUS_SRC" /usr/bin/home-net-status
cp "$CONTROL_SRC" /usr/bin/home-net-control
cp "$LUCI_VIEW_SRC" /www/luci-static/resources/view/home-net/status.js
cp "$LUCI_MENU_SRC" /usr/share/luci/menu.d/luci-app-home-net.json
cp "$LUCI_ACL_SRC" /usr/share/rpcd/acl.d/luci-app-home-net.json

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

chmod 0755 \
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
    /etc/init.d/podkop-service-health \
    /etc/init.d/home-net-log

/etc/init.d/podkop-service-health enable
/etc/init.d/podkop-service-health restart

/etc/init.d/home-net-log enable
if /etc/init.d/home-net-log running; then
    /etc/init.d/home-net-log restart
else
    /etc/init.d/home-net-log start
fi

/etc/init.d/rpcd restart >/dev/null 2>&1 || true
rm -f /tmp/luci-indexcache 2>/dev/null || true
rm -rf /tmp/luci-modulecache 2>/dev/null || true

echo "HOME NET Podkop Monitor v1.6.0 installed"
echo "LuCI page: Services -> HOME NET"
echo "Domain capture remains disabled until explicitly enabled."
