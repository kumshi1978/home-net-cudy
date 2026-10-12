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
mkdir "$TMP/bin" "$TMP/jobs-cache"
cat > "$TMP/bin/curl" <<'EOF'
#!/bin/sh
for argument do output="$argument"; done
case "$*" in
 *releases/latest*) printf '{"tag_name":"v1.7.3","draft":false,"prerelease":false}\n' > "$output" ;;
 */bundle.conf) printf "HOME_NET_BUNDLE_VERSION='1.7.3'\nUPDATE_ACTION_CLASS='%s'\n" "${MOCK_CLASS:-SAFE}" > "$output" ;;
 *) exit 1 ;;
esac
EOF
cat > "$TMP/bin/jsonfilter" <<'EOF'
#!/bin/sh
case "$*" in *tag_name*) echo v1.7.3 ;; *draft*|*prerelease*) echo false ;; *) exit 1 ;; esac
EOF
cat > "$TMP/updater" <<'EOF'
#!/bin/sh
[ "$1" = apply ] && [ "$HOME_NET_MANAGEMENT_CONTEXT" = 1 ] && [ "$HOME_NET_CONFIRMED_RELEASE" = v1.7.3 ] || exit 99
touch "$MOCK_JOB_GATE/started"
for attempt in $(seq 1 500); do
 [ ! -f "$MOCK_JOB_GATE/released" ] || break
 sleep 0.01
done
[ -f "$MOCK_JOB_GATE/released" ] || exit 99
echo 'fixture: retained worker output'
[ "${MOCK_JOB_FAILURE:-0}" = 0 ] || { echo 'fixture: updater failed' >&2; exit 23; }
printf "INSTALLED_VERSION='1.7.3'\nACTIVE_VERSION='1.7.3'\nUPDATE_STATUS='OK'\n" > "$HOME_NET_UPDATE_STATE_FILE"
EOF
chmod 0755 "$TMP/bin/"* "$TMP/updater"
export PATH="$TMP/bin:$PATH" HOME_NET_MANAGEMENT_CACHE="$TMP/jobs-cache"
export HOME_NET_MANAGEMENT_UPDATER="$TMP/updater" HOME_NET_UPDATE_STATE_FILE="$TMP/job-state"
sh "$ROOT/scripts/home-net-management" install-status | grep -Fxq STATUS=NONE
for outcome in success failure; do
 export MOCK_JOB_GATE="$TMP/job-$outcome"
 mkdir "$MOCK_JOB_GATE"
 printf "INSTALLED_VERSION='1.6.0'\nACTIVE_VERSION='1.6.0'\nUPDATE_STATUS='OK'\n" > "$HOME_NET_UPDATE_STATE_FILE"
 [ "$outcome" != failure ] || export MOCK_JOB_FAILURE=1
 sh "$ROOT/scripts/home-net-management" install-latest v1.7.3 > "$TMP/launch-output"
 grep -q 'started in the background' "$TMP/launch-output"
 for attempt in $(seq 1 500); do [ ! -f "$MOCK_JOB_GATE/started" ] || break; sleep 0.01; done
 [ -f "$MOCK_JOB_GATE/started" ]
 sh "$ROOT/scripts/home-net-management" install-status | grep -Fxq STATUS=RUNNING
 grep -Fxq "INSTALLED_VERSION='1.6.0'" "$HOME_NET_UPDATE_STATE_FILE"
 touch "$MOCK_JOB_GATE/released"
 for attempt in $(seq 1 500); do
  sh "$ROOT/scripts/home-net-management" install-status > "$TMP/job-status"
  grep -Eq 'STATUS=(SUCCEEDED|FAILED)' "$TMP/job-status" && break
  sleep 0.01
 done
 if [ "$outcome" = success ]; then grep -Fxq STATUS=SUCCEEDED "$TMP/job-status"; else grep -Fxq STATUS=FAILED "$TMP/job-status"; grep -Fxq EXIT_CODE=23 "$TMP/job-status"; fi
 job=$(cat "$HOME_NET_MANAGEMENT_CACHE/install-job")
 grep -q 'fixture: retained worker output' "$job/output.log"
 [ "$(LC_ALL=C ls -l "$job/output.log" | awk '{print $1}')" = '-rw-------' ]
done
before=$(find "$HOME_NET_MANAGEMENT_CACHE/jobs" -mindepth 1 -maxdepth 1 -type d | wc -l)
if MOCK_CLASS=CRITICAL sh "$ROOT/scripts/home-net-management" install-latest v1.7.3; then exit 1; fi
if sh "$ROOT/scripts/home-net-management" install-latest v1.7.2; then exit 1; fi
[ "$before" = "$(find "$HOME_NET_MANAGEMENT_CACHE/jobs" -mindepth 1 -maxdepth 1 -type d | wc -l)" ]
echo 'PASS background launch returns before install finishes; private output and success/failure status retained; target/CRITICAL checks stay synchronous'
