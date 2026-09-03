#!/bin/sh
# HOME NET Cudy
# Установщик мониторинга Podkop
# Версия: 1.4.0-dev

set -e

BASE_DIR="$(dirname "$0")"

check_file() {
    [ -f "$1" ] || {
        echo "Ошибка: отсутствует файл $1"
        exit 1
    }
}

check_file "$BASE_DIR/../scripts/podkop-service-health-daemon"
check_file "$BASE_DIR/../scripts/podkop-service-check"

mkdir -p /root/backup-podkop-install

cp -p /usr/bin/podkop-service-health-daemon /root/backup-podkop-install/ 2>/dev/null || true
cp -p /usr/bin/podkop-service-check /root/backup-podkop-install/ 2>/dev/null || true

cp "$BASE_DIR/../scripts/"* /usr/bin/
cp "$BASE_DIR/../init.d/podkop-service-health" /etc/init.d/

chmod +x /usr/bin/podkop-*
chmod +x /etc/init.d/podkop-service-health

/etc/init.d/podkop-service-health enable
/etc/init.d/podkop-service-health restart

echo "HOME NET Podkop Monitor installed"
