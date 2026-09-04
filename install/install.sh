#!/bin/sh
# HOME NET Cudy
# Установщик мониторинга Podkop
# Версия: 1.4.1

set -e

BASE_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
CONF_SRC="$BASE_DIR/../configs/podkop-service-check.conf.example"
CONF_DST="/etc/podkop-service-check.conf"

DAEMON_SRC="$BASE_DIR/../scripts/podkop-service-health-daemon"
CHECK_SRC="$BASE_DIR/../scripts/podkop-service-check"
FAKEIP_SRC="$BASE_DIR/../scripts/podkop-fakeip-check"
EVENT_MONITOR_SRC="$BASE_DIR/../scripts/podkop-event-monitor"
EVENT_RUNNER_SRC="$BASE_DIR/../scripts/podkop-event-runner"
INIT_SRC="$BASE_DIR/../init.d/podkop-service-health"

fail() {
    echo "Ошибка: $*"
    exit 1
}

[ -f /etc/openwrt_release ] || fail "Не обнаружен OpenWrt"

check_file() {
    [ -f "$1" ] || fail "отсутствует файл $1"
}

for FILE in \
    "$DAEMON_SRC" \
    "$CHECK_SRC" \
    "$FAKEIP_SRC" \
    "$EVENT_MONITOR_SRC" \
    "$EVENT_RUNNER_SRC" \
    "$INIT_SRC" \
    "$CONF_SRC"
do
    check_file "$FILE"
done

for FILE in \
    "$DAEMON_SRC" \
    "$CHECK_SRC" \
    "$FAKEIP_SRC" \
    "$EVENT_MONITOR_SRC" \
    "$EVENT_RUNNER_SRC"
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
    /etc/init.d/podkop-service-health \
    "$CONF_DST"
do
    [ -f "$FILE" ] && cp -p "$FILE" "$BACKUP_DIR/"
done

cp "$DAEMON_SRC" /usr/bin/podkop-service-health-daemon
cp "$CHECK_SRC" /usr/bin/podkop-service-check
cp "$FAKEIP_SRC" /usr/bin/podkop-fakeip-check
cp "$EVENT_MONITOR_SRC" /usr/bin/podkop-event-monitor
cp "$EVENT_RUNNER_SRC" /usr/bin/podkop-event-runner
cp "$INIT_SRC" /etc/init.d/podkop-service-health

if [ ! -f "$CONF_DST" ]; then
    cp "$CONF_SRC" "$CONF_DST"
fi

chmod 0755 \
    /usr/bin/podkop-service-health-daemon \
    /usr/bin/podkop-service-check \
    /usr/bin/podkop-fakeip-check \
    /usr/bin/podkop-event-monitor \
    /usr/bin/podkop-event-runner \
    /etc/init.d/podkop-service-health

/etc/init.d/podkop-service-health enable
/etc/init.d/podkop-service-health restart

echo "HOME NET Podkop Monitor v1.4.1 installed"
