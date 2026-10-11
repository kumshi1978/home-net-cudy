#!/bin/sh
set -eu
ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT HUP INT TERM
mkdir "$TMP/backups"
export HOME_NET_UPDATE_CONF="$TMP/config" HOME_NET_UPDATE_LOCK_DIR="$TMP/lock" HOME_NET_MANAGEMENT_BACKUPS="$TMP/backups"
cat > "$TMP/config" <<'EOF'
HOME_NET_AUTO_UPDATE_CAPABLE='1'
HOME_NET_ROLLOUT_RING='stable'
HOME_NET_ROLLOUT_POLICY_URL='https://raw.githubusercontent.com/kumshi1978/home-net-cudy/main/rollout-policy.conf'
HOME_NET_UPDATE_MODE='apply'
EOF
sh "$ROOT/scripts/home-net-management" save-settings 0 check 01:30 22:00 06:00 8
sh -n "$TMP/config"
grep -Fxq "HOME_NET_ROLLOUT_RING='stable'" "$TMP/config"
grep -Fxq "HOME_NET_AUTO_UPDATE_CAPABLE='1'" "$TMP/config"
grep -Fxq "HOME_NET_UPDATE_JITTER='480'" "$TMP/config"
[ -f "$(find "$TMP/backups" -type f | head -n 1)" ]
cp "$TMP/config" "$TMP/before"
if sh "$ROOT/scripts/home-net-management" save-settings 1 apply '01:30;touch /tmp/invalid' 00:00 00:00 1; then exit 1; fi
cmp "$TMP/config" "$TMP/before"
mkdir "$TMP/lock"; printf '%s\n' "$$" > "$TMP/lock/pid"
if sh "$ROOT/scripts/home-net-management" save-settings 1 apply 01:30 00:00 00:00 1; then exit 1; fi
cmp "$TMP/config" "$TMP/before"
rm "$TMP/lock/pid"; rmdir "$TMP/lock"
# Shared production functions; deterministic clock, no updater initialization or config sourcing.
sed -n '/^valid_clock()/,/^set_rollout_wait_state()/p' "$ROOT/scripts/home-net-update" | sed '$d' > "$TMP/gates"
cat > "$TMP/gate-test" <<'EOF'
set -eu
. "$1"
date() { echo "$NOW"; }
MODE=apply HOME_NET_AUTO_UPDATE_ENABLED=1 HOME_NET_UPDATE_TIME=00:00
HOME_NET_UPDATE_WINDOW_START=22:00 HOME_NET_UPDATE_WINDOW_END=06:00
for NOW in 22:00 23:59 00:00 05:59; do local_update_gate; done
for NOW in 06:00 12:00 21:59; do if local_update_gate; then exit 1; fi; done
HOME_NET_UPDATE_WINDOW_START=00:00 HOME_NET_UPDATE_WINDOW_END=00:00 HOME_NET_UPDATE_TIME=03:00
NOW=02:59; if local_update_gate; then exit 1; fi
NOW=03:00; local_update_gate
HOME_NET_AUTO_UPDATE_ENABLED=0; if local_update_gate; then exit 1; fi
HOME_NET_AUTO_UPDATE_ENABLED=1 MODE=check; if local_update_gate; then exit 1; fi
MODE=apply HOME_NET_UPDATE_WINDOW_START=bad; if local_update_gate; then exit 1; fi
EOF
sh "$TMP/gate-test" "$TMP/gates"
sh -n "$ROOT/scripts/home-net-management"
sh -n "$ROOT/scripts/home-net-podkop-update"
node "$ROOT/tests/test-luci-management.cjs"
echo 'PASS local settings validation/preservation/backup/lock and cross-midnight time gates'