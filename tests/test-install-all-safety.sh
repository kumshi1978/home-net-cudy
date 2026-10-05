#!/bin/sh
set -eu

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
INSTALLER="$ROOT/install-all.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT HUP INT TERM

BIN="$TMP/bin"
PAYLOADS="$TMP/payloads"
TARGET="$TMP/target"
mkdir -p "$BIN" "$PAYLOADS" "$TARGET/init.d" "$TARGET/backups"

cat > "$BIN/wget" <<'EOF_WGET'
#!/bin/sh
out=''
url=''
while [ "$#" -gt 0 ]; do
    case "$1" in
        -O) out="$2"; shift 2 ;;
        -T) shift 2 ;;
        -q) shift ;;
        *) url="$1"; shift ;;
    esac
done
case "$url" in
    */bundle.conf) source_file="$MOCK_PAYLOADS/bundle.conf" ;;
    */install.sh)
        [ "$url" = "https://raw.githubusercontent.com/kumshi1978/home-net-cudy/33a10d50846a7ff2672e399d933a532b752f4128/install.sh" ] || exit 96
        source_file="$MOCK_PAYLOADS/monitoring-install.sh" ;;
    */scripts/home-net-update) source_file="$MOCK_PAYLOADS/home-net-update" ;;
    */init.d/home-net-update) source_file="$MOCK_PAYLOADS/home-net-update.init" ;;
    */configs/home-net-update.conf.example) source_file="$MOCK_PAYLOADS/home-net-update.conf" ;;
    *) exit 1 ;;
esac
cp "$source_file" "$out"
EOF_WGET

cat > "$BIN/uci" <<'EOF_UCI'
#!/bin/sh
exit 0
EOF_UCI

cat > "$BIN/pgrep" <<'EOF_PGREP'
#!/bin/sh
exit 1
EOF_PGREP
chmod +x "$BIN/wget" "$BIN/uci" "$BIN/pgrep"

cat > "$PAYLOADS/bundle.conf" <<'EOF_BUNDLE'
HOME_NET_BUNDLE_VERSION='1.5.2'
FAILOVER_VERSION='1.4.1'
FAILOVER_REPO='kumshi1978/openwrt-podkop-awg-failover'
MONITORING_VERSION='1.4.3'
MONITORING_REPO='kumshi1978/home-net-cudy'
MONITORING_BOOTSTRAP_REF='33a10d50846a7ff2672e399d933a532b752f4128'
DEFAULT_AUTO_UPDATE_MODE='check'
UPDATE_ACTION_CLASS='SAFE'
UPDATE_PENDING_ACTION='none'
UPDATE_PENDING_REASON=''
EOF_BUNDLE

write_monitoring_installer() {
    cat > "$PAYLOADS/monitoring-install.sh" <<'EOF_MONITORING'
#!/bin/sh
[ "$HOME_NET_RELEASE_REF" = '33a10d50846a7ff2672e399d933a532b752f4128' ] || exit 95
case "${MOCK_HEALTH_MODE:-stale}" in
    stale) exit 0 ;;
    OK|UNKNOWN|FAIL|MISSING_SERVICE_CHECK)
        status="$MOCK_HEALTH_MODE"
        [ "$status" = MISSING_SERVICE_CHECK ] && status=OK
        {
            printf 'STATUS=%s\n' "$status"
            printf '%s\n' 'PODKOP=RUNNING'
            printf '%s\n' 'SING_BOX=RUNNING'
            printf '%s\n' 'FAKEIP=OK'
            [ "$MOCK_HEALTH_MODE" = MISSING_SERVICE_CHECK ] || printf '%s\n' 'SERVICE_CHECK=OK'
            printf '%s\n' 'CHECK_STARTED=2099-01-01 00:00:01'
            printf '%s\n' 'LAST_CHECK=2099-01-01 00:00:02'
        } > "$HOME_NET_HEALTH_STATE"
        ;;
    *) exit 2 ;;
esac
exit 0
EOF_MONITORING
}

write_old_health() {
    cat > "$TARGET/health.state" <<'EOF_HEALTH'
STATUS=OK
PODKOP=RUNNING
SING_BOX=RUNNING
FAKEIP=OK
SERVICE_CHECK=OK
CHECK_STARTED=2000-01-01 00:00:01
LAST_CHECK=2000-01-01 00:00:02
EOF_HEALTH
}

write_previous_state() {
    cat > "$TARGET/home-net-update.state" <<'EOF_STATE'
INSTALLED_VERSION='1.5.1'
ACTIVE_VERSION='1.5.1'
UPDATE_STATUS='OK'
LAST_HEALTH_STATUS='OK'
EOF_STATE
}

state_value() {
    sed -n "s/^$1='\([^']*\)'$/\1/p" "$TARGET/home-net-update.state"
}

scan_payload() {
    payload="$1"
    set +e
    HOME_NET_OPENWRT_RELEASE="$TARGET/openwrt_release" \
        sh "$INSTALLER" --scan-payload "$payload" test-payload > "$TMP/scan-output" 2>&1
    SCAN_RC=$?
    set -e
}

write_monitoring_installer

cat > "$PAYLOADS/home-net-update" <<'EOF_UPDATER'
#!/bin/sh
echo new-updater
EOF_UPDATER

write_updater_init() {
    cat > "$PAYLOADS/home-net-update.init" <<'EOF_INIT'
#!/bin/sh
action="${1:-}"
printf '%s\n' "$action" >> "$MOCK_INIT_LOG"
case "$action" in
    enable) exit 0 ;;
    running) [ -f "$MOCK_INIT_STATE" ] ;;
    start) : > "$MOCK_INIT_STATE"; exit 0 ;;
    restart)
        if [ ! -f "$MOCK_INIT_STATE" ]; then
            echo 'Command failed: Not found' >&2
        fi
        : > "$MOCK_INIT_STATE"
        exit 0
        ;;
    *) exit 2 ;;
esac
EOF_INIT
}

write_updater_init

printf "HOME_NET_UPDATE_MODE='check'\n" > "$PAYLOADS/home-net-update.conf"
printf "DISTRIB_ID='OpenWrt'\n" > "$TARGET/openwrt_release"
printf "INSTALLED_VERSION='1.4.1'\n" > "$TARGET/failover.conf"
cat > "$TARGET/home-net-update" <<'EOF_RUNNING'
#!/bin/sh
echo running-updater
EOF_RUNNING
cp "$TARGET/home-net-update" "$TARGET/original-updater"

run_installer() {
    set +e
    PATH="$BIN:$PATH" \
    MOCK_PAYLOADS="$PAYLOADS" \
    MOCK_HEALTH_MODE="$TEST_HEALTH_MODE" \
    HOME_NET_BUNDLE_REF='test-ref' \
    HOME_NET_UPDATE_IN_PROGRESS="$TEST_UPDATE_IN_PROGRESS" \
    HOME_NET_SKIP_VERSION_RECORD="$TEST_SKIP_VERSION_RECORD" \
    HOME_NET_OPENWRT_RELEASE="$TARGET/openwrt_release" \
    HOME_NET_FAILOVER_CONF="$TARGET/failover.conf" \
    HOME_NET_UPDATE_BIN="$TARGET/home-net-update" \
    HOME_NET_UPDATE_INIT="$TARGET/init.d/home-net-update" \
    HOME_NET_UPDATE_CONF="$TARGET/home-net-update.conf" \
    HOME_NET_UPDATE_STATE="$TARGET/home-net-update.state" \
    HOME_NET_UPDATER_BACKUP_ROOT="$TARGET/backups" \
    HOME_NET_HEALTH_STATE="$TARGET/health.state" \
    HOME_NET_BOOTSTRAP_HEALTH_TIMEOUT='1' \
    HOME_NET_BOOTSTRAP_HEALTH_RETRY_INTERVAL='1' \
    HOME_NET_BOOTSTRAP_HEALTH_MAX_BAD_CYCLES='1' \
    MOCK_INIT_LOG="$TMP/init-actions" \
    MOCK_INIT_STATE="$TMP/init-running" \
    sh "$INSTALLER" > "$TMP/output" 2>&1
    RUN_RC=$?
    set -e
}

# The destination must remain untouched until the final same-filesystem rename.
# A cp wrapper rejects any attempt to copy directly onto the running updater path.
REAL_CP="$(command -v cp)"
cat > "$BIN/cp" <<EOF_CP
#!/bin/sh
last=''
for arg in "\$@"; do last="\$arg"; done
if [ "\$last" = '$TARGET/home-net-update' ]; then
    echo 'direct overwrite of running updater path' >&2
    exit 97
fi
exec '$REAL_CP' "\$@"
EOF_CP
chmod +x "$BIN/cp"

TEST_SKIP_VERSION_RECORD=1
TEST_HEALTH_MODE=stale
TEST_UPDATE_IN_PROGRESS=1
: > "$TMP/init-actions"
rm -f "$TMP/init-running"
run_installer
[ "$RUN_RC" -eq 0 ] || { cat "$TMP/output" >&2; exit 1; }
grep -Fq 'new-updater' "$TARGET/home-net-update"
[ -x "$TARGET/home-net-update" ]
echo 'PASS atomic_self_update'

# Reproduce the old first-install lifecycle exactly: restart performs a stop
# against an unregistered procd service, prints the hardware-only message, and
# then starts successfully. The fixed installer must select start instead.
: > "$TMP/init-actions"
rm -f "$TMP/init-running"
MOCK_INIT_LOG="$TMP/init-actions" MOCK_INIT_STATE="$TMP/init-running" \
    sh "$PAYLOADS/home-net-update.init" enable > "$TMP/old-lifecycle" 2>&1
MOCK_INIT_LOG="$TMP/init-actions" MOCK_INIT_STATE="$TMP/init-running" \
    sh "$PAYLOADS/home-net-update.init" restart >> "$TMP/old-lifecycle" 2>&1
grep -Fq 'Command failed: Not found' "$TMP/old-lifecycle"
echo 'PASS old_first_install_restart_reproduces_message'

: > "$TMP/init-actions"
rm -f "$TMP/init-running" "$TARGET/init.d/home-net-update"
TEST_SKIP_VERSION_RECORD=1
TEST_HEALTH_MODE=stale
TEST_UPDATE_IN_PROGRESS=0
write_updater_init
run_installer
[ "$RUN_RC" -eq 0 ] || { cat "$TMP/output" >&2; exit 1; }
[ "$(sed -n '1p' "$TMP/init-actions")" = enable ]
[ "$(sed -n '2p' "$TMP/init-actions")" = running ]
[ "$(sed -n '3p' "$TMP/init-actions")" = start ]
[ "$(wc -l < "$TMP/init-actions" | tr -d ' ')" -eq 3 ]
! grep -Fq 'Command failed: Not found' "$TMP/output"
echo 'PASS first_install_uses_enable_running_start'

: > "$TMP/init-actions"
: > "$TMP/init-running"
TEST_UPDATE_IN_PROGRESS=0
run_installer
[ "$RUN_RC" -eq 0 ] || { cat "$TMP/output" >&2; exit 1; }
[ "$(sed -n '1p' "$TMP/init-actions")" = enable ]
[ "$(sed -n '2p' "$TMP/init-actions")" = running ]
[ "$(sed -n '3p' "$TMP/init-actions")" = restart ]
[ "$(wc -l < "$TMP/init-actions" | tr -d ' ')" -eq 3 ]
echo 'PASS running_upgrade_uses_enable_running_restart'

TEST_UPDATE_IN_PROGRESS=1

run_bootstrap_case() {
    expected_rc="$1"
    health_mode="$2"
    expected_active="$3"
    expected_status="$4"
    expected_health="$5"
    TEST_SKIP_VERSION_RECORD=0
    TEST_HEALTH_MODE="$health_mode"
    write_monitoring_installer
    write_old_health
    write_previous_state
    run_installer
    [ "$RUN_RC" -eq "$expected_rc" ] || { cat "$TMP/output" >&2; exit 1; }
    [ "$(state_value INSTALLED_VERSION)" = 1.5.2 ]
    [ "$(state_value ACTIVE_VERSION)" = "$expected_active" ]
    [ "$(state_value UPDATE_STATUS)" = "$expected_status" ]
    [ "$(state_value LAST_HEALTH_STATUS)" = "$expected_health" ]
}

run_bootstrap_case 0 OK 1.5.2 OK OK
echo 'PASS bootstrap_fresh_health_ok'

run_bootstrap_case 1 stale 1.5.1 FAILED UNKNOWN
echo 'PASS bootstrap_stale_health_rejected'

run_bootstrap_case 1 UNKNOWN 1.5.1 FAILED UNKNOWN
echo 'PASS bootstrap_fresh_health_unknown'

run_bootstrap_case 1 FAIL 1.5.1 FAILED FAIL
echo 'PASS bootstrap_fresh_health_fail'

run_bootstrap_case 1 MISSING_SERVICE_CHECK 1.5.1 FAILED FAIL
echo 'PASS bootstrap_missing_service_check'

TEST_SKIP_VERSION_RECORD=0
TEST_HEALTH_MODE=UNKNOWN
write_monitoring_installer
write_old_health
rm -f "$TARGET/home-net-update.state"
run_installer
[ "$RUN_RC" -ne 0 ] || exit 1
[ "$(state_value INSTALLED_VERSION)" = 1.5.2 ]
[ "$(state_value ACTIVE_VERSION)" = unknown ]
[ "$(state_value UPDATE_STATUS)" = FAILED ]
echo 'PASS bootstrap_unknown_previous_active_is_explicit'

TEST_SKIP_VERSION_RECORD=1
TEST_HEALTH_MODE=OK
write_monitoring_installer
write_old_health
printf '%s\n' "SENTINEL='preserve-me'" > "$TARGET/home-net-update.state"
run_installer
[ "$RUN_RC" -eq 0 ] || { cat "$TMP/output" >&2; exit 1; }
grep -Fqx "SENTINEL='preserve-me'" "$TARGET/home-net-update.state"
echo 'PASS skip_version_record_preserves_state'

cat > "$TARGET/allowed-payload.sh" <<'EOF_ALLOWED'
#!/bin/sh
echo "reboot"
printf '%s\n' "network restart"
log "automatic network restart or reboot"
die "reboot is forbidden"
# reboot
reason='network restart required'
EOF_ALLOWED
scan_payload "$TARGET/allowed-payload.sh"
[ "$SCAN_RC" -eq 0 ] || { cat "$TMP/scan-output" >&2; exit 1; }
echo 'PASS diagnostic_text_is_not_disruptive'

scan_payload "$ROOT/scripts/home-net-update"
[ "$SCAN_RC" -eq 0 ] || { cat "$TMP/scan-output" >&2; exit 1; }
echo 'PASS real_home_net_update_payload_is_safe'

for disruptive_action in \
    'reboot' \
    'reboot &' \
    '/etc/init.d/network restart' \
    '/etc/init.d/network reload' \
    'service network restart' \
    'service network reload' \
    'ubus call system reboot' \
    'shutdown -r now'
do
    {
        printf '%s\n' '#!/bin/sh'
        printf '%s\n' "$disruptive_action"
    } > "$TARGET/disruptive-payload.sh"
    scan_payload "$TARGET/disruptive-payload.sh"
    [ "$SCAN_RC" -ne 0 ] || {
        echo "scanner accepted disruptive command: $disruptive_action" >&2
        exit 1
    }
done
echo 'PASS executable_disruptive_commands_are_rejected'

# The Monitoring installer is executable payload, so every guarded disruptive
# command form must be rejected before it or the updater installation runs.
for disruptive_action in \
    '/etc/init.d/network restart' \
    '/etc/init.d/network reload' \
    'service network restart' \
    'service network reload' \
    'reboot' \
    'ubus call system reboot' \
    'shutdown -r now'
do
    {
        printf '%s\n' '#!/bin/sh'
        printf '%s\n' "$disruptive_action"
    } > "$PAYLOADS/monitoring-install.sh"
    "$REAL_CP" "$TARGET/original-updater" "$TARGET/home-net-update"
    TEST_SKIP_VERSION_RECORD=1
    TEST_HEALTH_MODE=stale
    run_installer
    [ "$RUN_RC" -ne 0 ] || exit 1
    grep -Fq 'monitoring installer contains a forbidden network restart or reboot' "$TMP/output"
    cmp -s "$TARGET/original-updater" "$TARGET/home-net-update"
done
echo 'PASS monitoring_disruptive_action_scan'

echo 'All install-all safety tests passed.'
