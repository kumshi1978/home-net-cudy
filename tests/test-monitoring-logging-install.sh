#!/bin/sh
set -eu

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
INSTALL="$ROOT/install/install.sh"

sh -n "$INSTALL"

for token in     'home-net-log-daemon'     'home-net-log'     'home-net-log.conf'     '/etc/init.d/home-net-log enable'     'Domain capture remains disabled'
do
    grep -Fq "$token" "$INSTALL"
done

echo "PASS monitoring_installer_includes_logging"
