#!/bin/sh
set -eu
ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT HUP INT TERM
mkdir -p "$TMP/bin" "$TMP/scratch" "$TMP/runtime" "$TMP/lock" "$TMP/backups"
for tool in curl wget logger reboot ubus shutdown ip uci; do
    printf '#!/bin/sh\nprintf "called\\n" >> "$CALLS"\nexit 99\n' > "$TMP/bin/$tool"
    chmod +x "$TMP/bin/$tool"
done
printf 'printf "sourced\\n" >> "$CALLS"\nexit 99\n' > "$TMP/config"
printf "INSTALLED_VERSION='1.5.4'\nACTIVE_VERSION='1.5.4'\n" > "$TMP/state"
cp "$TMP/state" "$TMP/state.before"
printf 'STATUS=FAIL\n' > "$TMP/health"
cp "$TMP/health" "$TMP/health.before"
CALLS="$TMP/calls" PATH="$TMP/bin:$PATH" TMPDIR="$TMP/scratch" \
HOME_NET_UPDATE_CONF="$TMP/config" HOME_NET_UPDATE_STATE_FILE="$TMP/state" \
HOME_NET_UPDATE_HEALTH_STATE="$TMP/health" HOME_NET_UPDATE_RUNTIME_DIR="$TMP/runtime" \
HOME_NET_UPDATE_LOCK_DIR="$TMP/lock" HOME_NET_UPDATE_BACKUP_ROOT="$TMP/backups" \
HOME_NET_UPDATE_COORDINATION_MARKER="$TMP/coordination" \
HOME_NET_AUTO_UPDATE_CAPABLE=invalid HOME_NET_ROLLOUT_RING=invalid \
sh "$ROOT/scripts/home-net-update" self-test > "$TMP/output"
cat "$TMP/output"
grep -Eq '^Self-test: [0-9]+ passed, 0 failed$' "$TMP/output"
[ ! -e "$TMP/calls" ]
cmp "$TMP/state" "$TMP/state.before"
cmp "$TMP/health" "$TMP/health.before"
[ ! -e "$TMP/coordination" ]
for directory in scratch runtime lock backups; do
    [ -z "$(ls -A "$TMP/$directory")" ]
done
echo 'PASS: self-test leaves config, state, health, lock and runtime untouched; no external calls'

# Prove a broken shared gate makes the command fail, rather than a canned PASS.
sed 's/SAFE) ;;/SAFE) stage_only=1 ;;/' "$ROOT/scripts/home-net-update" > "$TMP/broken"
if TMPDIR="$TMP/scratch" sh "$TMP/broken" self-test > "$TMP/broken-output"; then
    echo 'FAIL: broken SAFE gate was not detected' >&2
    exit 1
fi
grep -Fq 'FAIL: SAFE stage only' "$TMP/broken-output"
echo 'PASS: self-test detects a broken shared activation gate and exits nonzero'
