#!/bin/sh
set -eu
REPO="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
export HOME_NET_VERIFY_ROOT="$TMP/root"
export HOME_NET_VERIFY_HEALTH="$TMP/root/tmp/podkop-service-health/state"
mkdir -p "$TMP/root/etc/init.d" "$TMP/root/usr/bin" "$TMP/root/tmp/podkop-service-health" "$TMP/root/www/luci-static/resources/view/home-net" "$TMP/root/www/luci-static/resources/home-net"
mkdir -p "$TMP/bin" "$TMP/root/etc/sing-box" "$TMP/root/etc/config"
export HOME_NET_TEST_REAL_DATE="$(command -v date)" HOME_NET_TEST_CLOCK_FILE="$TMP/clock"
export HOME_NET_TEST_REAL_SLEEP="$(command -v sleep)"
"$HOME_NET_TEST_REAL_DATE" +%s > "$TMP/clock"
cp "$REPO/tests/fixtures/podkop-date" "$TMP/bin/date"
cp "$REPO/tests/fixtures/podkop-nft" "$TMP/bin/nft"
export PATH="$TMP/bin:$PATH"
cat > "$TMP/bin/stat" <<'EOF'
#!/bin/sh
echo called > "$HOME_NET_VERIFY_ROOT/stat-called"
echo 'stat: not found' >&2
exit 127
EOF
cat > "$TMP/bin/uci" <<'EOF'
#!/bin/sh
echo /etc/sing-box/config.json
EOF
cat > "$TMP/bin/sleep" <<'EOF'
#!/bin/sh
if [ -n "${MOCK_RPC_GATE:-}" ] && [ ! -f "$MOCK_RPC_GATE/closed" ]; then
 touch "$MOCK_RPC_GATE/ready"
 for attempt in $(seq 1 500); do
  [ ! -f "$MOCK_RPC_GATE/closed" ] || break
  "$HOME_NET_TEST_REAL_SLEEP" 0.01
 done
 [ -f "$MOCK_RPC_GATE/closed" ] || exit 1
fi
epoch=$(($(date +%s)+${MOCK_WAIT_STEP:-2}))
printf '%s\n' "$epoch" > "$HOME_NET_TEST_CLOCK_FILE"
[ -f "$HOME_NET_VERIFY_ROOT/podkop-service-health.running" ] || exit 0
[ "${MOCK_NO_NEW_HEALTH:-0}" = 0 ] || exit 0
stamp=$(date '+%F %T')
sed -e "s/LAST_CHECK=.*/LAST_CHECK=$stamp/" -e "s/CHECK_STARTED=.*/CHECK_STARTED=$stamp/" "$HOME_NET_VERIFY_HEALTH" > "$HOME_NET_VERIFY_HEALTH.new"
mv "$HOME_NET_VERIFY_HEALTH.new" "$HOME_NET_VERIFY_HEALTH"
EOF
cat > "$TMP/bin/ip" <<'EOF'
#!/bin/sh
[ -f "$HOME_NET_VERIFY_ROOT/routing" ] || exit 1
case "$*" in *rule*) echo '105: from all fwmark 0x100000/0x100000 lookup podkop' ;; *route*) echo 'local default dev lo scope host' ;; *) exit 1 ;; esac
EOF
chmod +x "$TMP/bin/"*
printf '{}' > "$TMP/root/etc/sing-box/config.json"
# Real installer execution is redirected into a private filesystem fixture.
sed -e "s|/etc/|@FIXTURE@/etc/|g" -e "s|/usr/|@FIXTURE@/usr/|g" -e "s|/www/|@FIXTURE@/www/|g" -e "s|/root/|@FIXTURE@/root/|g" -e "s|/tmp/|@FIXTURE@/tmp/|g" -e "s|@FIXTURE@|$TMP/root|g" "$REPO/install/install.sh" > "$TMP/install.fixture"
# Source lookup must still use the checked-out repository, not the temporary fixture.
sed "s|^BASE_DIR=.*|BASE_DIR='$REPO/install'|" "$TMP/install.fixture" > "$TMP/install"
touch "$TMP/root/etc/openwrt_release" "$TMP/root/sing-box.running" "$TMP/root/nft" "$TMP/root/routing"
stamp=$(date -d "@$(($(date +%s)-10))" '+%F %T')
printf 'STATUS=OK\nPODKOP=RUNNING\nSING_BOX=RUNNING\nFAKEIP=OK\nSERVICE_CHECK=OK\nCHECK_STARTED=%s\nLAST_CHECK=%s\n' "$stamp" "$stamp" > "$HOME_NET_VERIFY_HEALTH"
for service in podkop sing-box podkop-service-health home-net-log rpcd; do
cat > "$TMP/root/etc/init.d/$service" <<'INIT'
#!/bin/sh
name=${0##*/}
echo "$name $1" >> "$HOME_NET_VERIFY_ROOT/calls"
case "$1" in
 running|status) [ -f "$HOME_NET_VERIFY_ROOT/$name.running" ] ;;
 stop) rm -f "$HOME_NET_VERIFY_ROOT/$name.running" ;;
 start|restart)
  touch "$HOME_NET_VERIFY_ROOT/$name.running"
  if [ "$name" = podkop-service-health ]; then
   stamp=$(date '+%F %T')
   if [ "${MOCK_FIRST_CYCLE_COMPLETE:-0}" = 1 ]; then
    sed -e "s/LAST_CHECK=.*/LAST_CHECK=$stamp/" -e "s/CHECK_STARTED=.*/CHECK_STARTED=$stamp/" "$HOME_NET_VERIFY_HEALTH" > "$HOME_NET_VERIFY_HEALTH.new"
   else
    sed "s/CHECK_STARTED=.*/CHECK_STARTED=$stamp/" "$HOME_NET_VERIFY_HEALTH" > "$HOME_NET_VERIFY_HEALTH.new"
   fi
   mv "$HOME_NET_VERIFY_HEALTH.new" "$HOME_NET_VERIFY_HEALTH"
   [ "${DROP_PODKOP:-0}" != 1 ] || rm -f "$HOME_NET_VERIFY_ROOT/podkop.running"
  fi
  if [ "$name" = rpcd ] && [ "${MOCK_RPCD_DELAY:-0}" != 0 ]; then
   printf '%s\n' "$(($(date +%s)+MOCK_RPCD_DELAY))" > "$HOME_NET_TEST_CLOCK_FILE"
  fi
  if [ "$name" = rpcd ] && [ -n "${MOCK_RPCD_READER_PID:-}" ]; then
   kill "$MOCK_RPCD_READER_PID"
   "$HOME_NET_TEST_REAL_SLEEP" 0.1
  fi ;;
 enable) exit 0 ;;
 *) exit 1 ;;
esac
INIT
chmod 755 "$TMP/root/etc/init.d/$service"
done
# Candidate Monitoring init files invoke our private rc.common mock instead of host services.
mkdir "$TMP/src"
cp -R "$REPO/install" "$REPO/scripts" "$REPO/configs" "$REPO/luci" "$REPO/init.d" "$TMP/src/"
for service in podkop-service-health home-net-log; do cp "$TMP/root/etc/init.d/$service" "$TMP/src/init.d/$service"; done
chmod 0644 "$TMP/src/scripts/"* "$TMP/src/init.d/"*
sed "s|^BASE_DIR=.*|BASE_DIR='$TMP/src/install'|" "$TMP/install" > "$TMP/install.ready"
# Reproduce an early LuCI-stage abort before the old late chmod location.
export HOME_NET_TEST_REAL_CP="$(command -v cp)"
cat > "$TMP/bin/cp" <<'EOF'
#!/bin/sh
for argument do destination="$argument"; done
if [ "${FAIL_LUCI_COPY:-0}" = 1 ] && [ "$destination" = "$HOME_NET_VERIFY_ROOT/www/luci-static/resources/home-net/common.js" ]; then
 echo 'fixture: LuCI copy failed' >&2
 exit 1
fi
exec "$HOME_NET_TEST_REAL_CP" "$@"
EOF
chmod 0755 "$TMP/bin/cp"
if [ "${HOME_NET_TEST_LUCI_UPGRADE:-0}" = 1 ]; then
 . "$REPO/tests/fixtures/luci-detached-upgrade"
 exit 0
fi
if (umask 077; FAIL_LUCI_COPY=1 sh "$TMP/install.ready") > "$TMP/partial-output" 2>&1; then exit 1; fi
grep -q 'fixture: LuCI copy failed' "$TMP/partial-output"
sh "$REPO/scripts/home-net-install-verify" runtime
echo 'PASS early LuCI failure leaves every copied runtime helper/init executable'
(umask 077; sh "$TMP/install.ready") > "$TMP/output"
[ "$(grep -c '^Waiting for a completed healthy cycle' "$TMP/output")" = 1 ]
if grep -q 'FAIL: health cycle predates initialization' "$TMP/output"; then exit 1; fi
echo 'PASS health retries report waiting once and suppress intermediate FAIL noise'
sh "$REPO/scripts/home-net-install-verify" all
[ "$(LC_ALL=C ls -ld "$TMP/root/www/luci-static/resources/view/home-net/status.js" | awk '{print $1}')" = '-rw-r--r--' ]
[ ! -e "$TMP/root/stat-called" ]
echo 'PASS actual installer and verifier do not call unavailable stat'
if grep -Eq '^(podkop|sing-box) (start|stop|restart)$' "$TMP/root/calls"; then exit 1; fi
[ ! -e "$TMP/root/podkop.running" ]
echo 'PASS actual installer under umask 077; one-shot Podkop accepted without service control'
# Upgrade from 1.6.0: the first new cycle completes before a slow rpcd restart.
# No later cycle is available; capturing the boundary after rpcd must fail.
printf "INSTALLED_VERSION='1.6.0'\nACTIVE_VERSION='1.6.0'\n" > "$TMP/root/etc/home-net-update.state"
cp "$TMP/root/etc/home-net-update.state" "$TMP/version.before"
MOCK_FIRST_CYCLE_COMPLETE=1 MOCK_NO_NEW_HEALTH=1 MOCK_RPCD_DELAY=5 sh "$TMP/install.ready" > "$TMP/race-output" 2>&1
grep -q 'HOME NET Podkop Monitor v1.7.3 installed' "$TMP/race-output"
if grep -q '^Waiting for a completed healthy cycle' "$TMP/race-output"; then exit 1; fi
cmp -s "$TMP/version.before" "$TMP/root/etc/home-net-update.state"
echo 'PASS upgrade 1.6.0: first post-restart cycle accepted before delayed rpcd; baseline record preserved'
# Reproduce rpcd's disappearing output reader with a real FIFO. rpcd ignores
# SIGPIPE; shell builtins then report EPIPE and set -e aborts on progress echo.
# The legacy installer restarted rpcd regardless of the in-progress flag.
sed 's/if \[ "${HOME_NET_UPDATE_IN_PROGRESS:-0}" != 1 \]; then/if true; then/' "$TMP/install.ready" > "$TMP/install.legacy"
mkfifo "$TMP/rpc-output"
cat "$TMP/rpc-output" > "$TMP/legacy-rpc-output" &
reader=$!
legacy_rc=0
(trap '' PIPE; HOME_NET_UPDATE_IN_PROGRESS=1 MOCK_RPCD_READER_PID="$reader" sh "$TMP/install.legacy" > "$TMP/rpc-output" 2> "$TMP/legacy-rpc-error") || legacy_rc=$?
wait "$reader" 2>/dev/null || true
[ "$legacy_rc" != 0 ]
cat "$TMP/legacy-rpc-error"
grep -q 'WAIT: no new completed health cycle available' "$TMP/root/root/backup-podkop-install/install-verification.log"
grep -qi 'write error\|broken pipe\|I/O error' "$TMP/legacy-rpc-error"
echo 'PASS legacy rpcd restart closes LuCI output and aborts on waiting progress echo'
# The interrupted installer left the mock producer mid-cycle. Complete that
# independent cycle before attempting the next installation's strict preflight.
sh "$TMP/bin/sleep"
: > "$TMP/root/calls"
cat "$TMP/rpc-output" > "$TMP/fixed-rpc-output" &
reader=$!
fixed_rc=0
(trap '' PIPE; HOME_NET_UPDATE_IN_PROGRESS=1 MOCK_RPCD_READER_PID="$reader" sh "$TMP/install.ready" > "$TMP/rpc-output" 2> "$TMP/fixed-rpc-error") || fixed_rc=$?
wait "$reader" || true
[ "$fixed_rc" = 0 ]
if grep -Eq '^rpcd (restart|reload)$' "$TMP/root/calls"; then exit 1; fi
grep -q 'PASS: ' "$TMP/root/root/backup-podkop-install/install-verification.log"
cmp -s "$TMP/version.before" "$TMP/root/etc/home-net-update.state"
echo 'PASS LuCI update keeps rpcd reader alive, completes fresh verification and preserves version ownership'
if MOCK_NO_NEW_HEALTH=1 MOCK_WAIT_STEP=300 sh "$TMP/install.ready" > "$TMP/timeout-output" 2>&1; then exit 1; fi
grep -q 'verification timed out (600-second deadline' "$TMP/timeout-output"
[ "$(grep -c '^Waiting for a completed healthy cycle' "$TMP/timeout-output")" = 1 ]
grep -q 'WAIT: no new completed health cycle available' "$TMP/timeout-output"
[ -f "$TMP/root/root/backup-podkop-install/install-verification.log" ]
# Restore the fixture's independently completed cycle for later checks.
sh "$TMP/bin/sleep"
echo 'PASS bounded timeout rejects an old cycle, displays diagnostics and retains backup'
sh "$REPO/scripts/home-net-install-verify" runtime
for helper in podkop-service-health-daemon podkop-fakeip-check home-net-status home-net-podkop-update; do
 chmod 0600 "$TMP/root/usr/bin/$helper"
 if sh "$REPO/scripts/home-net-install-verify" runtime; then exit 1; fi
 chmod 0755 "$TMP/root/usr/bin/$helper"
done
chmod 0644 "$TMP/root/etc/init.d/podkop-service-health"
if sh "$REPO/scripts/home-net-install-verify" runtime; then exit 1; fi
chmod 0755 "$TMP/root/etc/init.d/podkop-service-health"
echo 'PASS non-executable sources and umask 077 yield all helpers/init 755; regressions rejected'
for output in valid numeric standby; do
 MOCK_NFT_CASE="$output" sh "$REPO/scripts/home-net-install-verify" lifecycle > "$TMP/counters-output" 2>&1
 grep -q 'WARN: Podkop mangle has zero traffic counters' "$TMP/counters-output"
 grep -q 'PASS: Podkop initialized' "$TMP/counters-output"
 echo "PASS $output protocols: existing rules with zero counters WARN only"
done
for structure in empty nohook norules nomarking notproxy; do
 if MOCK_NFT_CASE="$structure" sh "$REPO/scripts/home-net-install-verify" lifecycle; then exit 1; fi
 echo "PASS nft rejects $structure"
done
boundary=$(date +%s)
if HOME_NET_VERIFY_AFTER_EPOCH="$boundary" sh "$REPO/scripts/home-net-install-verify" lifecycle; then exit 1; fi
echo 'PASS health cycle at/before initialization boundary rejected'
cp "$HOME_NET_VERIFY_HEALTH" "$TMP/old-cycle"
started=$(date -d "@$((boundary-20))" '+%F %T')
sed "s/CHECK_STARTED=.*/CHECK_STARTED=$started/" "$TMP/old-cycle" > "$HOME_NET_VERIFY_HEALTH"
if HOME_NET_VERIFY_AFTER_EPOCH="$((boundary-1))" sh "$REPO/scripts/home-net-install-verify" lifecycle; then exit 1; fi
echo 'PASS new LAST_CHECK with pre-initialization CHECK_STARTED rejected'
cp "$TMP/old-cycle" "$HOME_NET_VERIFY_HEALTH"
chmod 600 "$TMP/root/www/luci-static/resources/view/home-net/status.js"
if sh "$REPO/scripts/home-net-install-verify" luci; then exit 1; fi
chmod 644 "$TMP/root/www/luci-static/resources/view/home-net/status.js"
chmod 700 "$TMP/root/www/luci-static/resources/home-net"
if sh "$REPO/scripts/home-net-install-verify" luci; then exit 1; fi
chmod 755 "$TMP/root/www/luci-static/resources/home-net"
sh "$REPO/scripts/home-net-install-verify" luci
[ ! -e "$TMP/root/stat-called" ]
rm "$TMP/root/www/luci-static/resources/view/home-net/vpn.js"
if sh "$REPO/scripts/home-net-install-verify" luci; then exit 1; fi
for missing in sing-box.running nft routing; do
 rm "$TMP/root/$missing"
 if sh "$REPO/scripts/home-net-install-verify" lifecycle; then exit 1; fi
 touch "$TMP/root/$missing"
 echo "PASS lifecycle independently rejects missing $missing"
done
mv "$TMP/root/etc/sing-box/config.json" "$TMP/config.saved"
if sh "$REPO/scripts/home-net-install-verify" lifecycle; then exit 1; fi
mv "$TMP/config.saved" "$TMP/root/etc/sing-box/config.json"
cp "$HOME_NET_VERIFY_HEALTH" "$TMP/health.saved"
sed 's/FAKEIP=OK/FAKEIP=FAIL/' "$TMP/health.saved" > "$HOME_NET_VERIFY_HEALTH"
if sh "$REPO/scripts/home-net-install-verify" lifecycle; then exit 1; fi
sed 's/LAST_CHECK=.*/LAST_CHECK=2000-01-01 00:00:00/' "$TMP/health.saved" > "$HOME_NET_VERIFY_HEALTH"
if sh "$REPO/scripts/home-net-install-verify" lifecycle; then exit 1; fi
cp "$TMP/health.saved" "$HOME_NET_VERIFY_HEALTH"
# Healthy cached monitoring alone cannot allow installation with a dead proxy.
rm "$TMP/root/sing-box.running"
before=$(sha256sum "$TMP/root/usr/bin/home-net-status")
if sh "$TMP/install.ready" > "$TMP/stopped-output" 2>&1; then exit 1; fi
[ "$before" = "$(sha256sum "$TMP/root/usr/bin/home-net-status")" ]
echo 'PASS missing/0600 LuCI, FakeIP/stale health and dead proxy fail closed'
