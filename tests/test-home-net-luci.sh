#!/bin/sh
set -eu

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"

sh -n "$ROOT/scripts/home-net-status"
sh -n "$ROOT/scripts/home-net-control"
sh -n "$ROOT/install/install.sh"

grep -Fq '/usr/bin/home-net-status' "$ROOT/luci/acl.d/luci-app-home-net.json"
grep -Fq '/usr/bin/home-net-control' "$ROOT/luci/acl.d/luci-app-home-net.json"
grep -Fq '"admin/services/home-net"' "$ROOT/luci/menu.d/luci-app-home-net.json"
grep -Fq "switch-main" "$ROOT/scripts/home-net-control"
grep -Fq "switch-backup" "$ROOT/scripts/home-net-control"
grep -Fq "Update ring" "$ROOT/luci/view/home-net/status.js"
grep -Fq "Release rollout" "$ROOT/luci/view/home-net/status.js"
grep -Fq "AUTO_APPLY_STATE" "$ROOT/scripts/home-net-status"

if grep -Eq '(^|[[:space:]])(reboot|shutdown)([[:space:]]|$)|/etc/init\.d/network[[:space:]]+(restart|reload)' "$ROOT/scripts/home-net-control"; then
    echo "forbidden disruptive control found" >&2
    exit 1
fi

echo "HOME NET LuCI static tests: PASS"
