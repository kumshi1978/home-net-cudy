#!/bin/sh
# HOME NET Cudy
# Установщик мониторинга Podkop
# Версия: 1.4.0-dev

set -e

BASE_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"

fail() {
    echo "Ошибка: $*"
    exit 1
}

[ -d /etc/openwrt_release ] || fail "Не обнаружен OpenWrt"

check_file() {
    [ -f "$1" ] || fail "отсутствует файл $1"
}

check_file "$BASE_DIR/../scripts/podkop-service-health-daemon"
check_file "$BASE_DIR/../scripts/podkop-service-check"
check_file "$BASE_DIR/../scripts/podkop-fakeip-check"
check_file "$BASE_DIR/../init.d/podkop-service-health"

mkdir -p /root/backup-podkop-install

for FILE in \
    /usr/bin/podkop-service-health-daemon \
    /usr/bin/podkop-service-check \
    /usr/bin/podkop-fakeip-check \
    /etc/init.d/podkop-service-health
 do
    [ -f "$FILE" ] && cp -p "$FILE" /root/backup-podkop-install/
done

cp "$BASE_DIR/../scripts/"* /usr/bin/
cp "$BASE_DIR/../init.d/podkop-service-health" /etc/init.d/

chmod +x /usr/bin/podkop-*
chmod +x /etc/init.d/podkop-service-health

sh -n /usr/bin/podkop-service-health-daemon
sh -n /usr/bin/podkop-service-check
sh -n /usr/bin/podkop-fakeip-check

/etc/init.d/podkop-service-health enable
/etc/init.d/podkop-service-health restart

echo "HOME NET Podkop Monitor v1.4.0-dev installed"
