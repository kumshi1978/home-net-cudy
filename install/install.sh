#!/bin/sh
# HOME NET Cudy
# Установщик мониторинга Podkop
# Версия: 1.4.1-dev

set -e

BASE_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"
CONF_SRC="$BASE_DIR/../configs/podkop-service-check.conf.example"
CONF_DST="/etc/podkop-service-check.conf"

fail() {
    echo "Ошибка: $*"
    exit 1
}

[ -f /etc/openwrt_release ] || fail "Не обнаружен OpenWrt"

check_file() {
    [ -f "$1" ] || fail "отсутствует файл $1"
}

for FILE in \
    "$BASE_DIR/../scripts/podkop-service-health-daemon" \
    "$BASE_DIR/../scripts/podkop-service-check" \
    "$BASE_DIR/../scripts/podkop-fakeip-check" \
    "$BASE_DIR/../scripts/podkop-event-monitor" \
    "$BASE_DIR/../scripts/podkop-event-runner" \
    "$BASE_DIR/../init.d/podkop-service-health" \
    "$CONF_SRC"
do
    check_file "$FILE"
done

mkdir -p /root/backup-podkop-install

for FILE in \
    /usr/bin/podkop-service-health-daemon \
    /usr/bin/podkop-service-check \
    /usr/bin/podkop-fakeip-check \
    /usr/bin/podkop-event-monitor \
    /usr/bin/podkop-event-runner \
    /etc/init.d/podkop-service-health \
    "$CONF_DST"
do
    [ -f "$FILE" ] && cp -p "$FILE" /root/backup-podkop-install/
done

cp "$BASE_DIR/../scripts/"* /usr/bin/
cp "$BASE_DIR/../init.d/podkop-service-health" /etc/init.d/

if [ ! -f "$CONF_DST" ]; then
    cp "$CONF_SRC" "$CONF_DST"
fi

chmod +x /usr/bin/podkop-*
chmod +x /etc/init.d/podkop-service-health

for FILE in \
    /usr/bin/podkop-service-health-daemon \
    /usr/bin/podkop-service-check \
    /usr/bin/podkop-fakeip-check \
    /usr/bin/podkop-event-monitor \
    /usr/bin/podkop-event-runner
do
    sh -n "$FILE"
done

/etc/init.d/podkop-service-health enable
/etc/init.d/podkop-service-health restart

echo "HOME NET Podkop Monitor v1.4.1-dev installed"
