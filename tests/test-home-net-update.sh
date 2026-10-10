#!/bin/sh
set -eu

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
UPDATER="$ROOT/scripts/home-net-update"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT HUP INT TERM

BIN="$TMP/bin"
FIXTURES="$TMP/fixtures"
mkdir -p "$BIN" "$FIXTURES" "$TMP/backups"

cat > "$BIN/logger" <<'EOF_LOGGER'
#!/bin/sh
exit 0
EOF_LOGGER

cat > "$BIN/ip" <<'EOF_IP'
#!/bin/sh
case "$*" in
    '-4 route show default') echo 'default via 192.0.2.1 dev wan' ;;
esac
exit 0
EOF_IP

cat > "$BIN/uci" <<'EOF_UCI'
#!/bin/sh
[ "$*" = '-q get podkop.main.interface' ] && echo awg_main
exit 0
EOF_UCI

cat > "$BIN/curl" <<'EOF_CURL'
#!/bin/sh
out=""
previous=""
for arg in "$@"; do
    if [ "$previous" = "-o" ]; then
        out="$arg"
        previous=""
        continue
    fi
    previous="$arg"
done

case "$*" in
    *releases/latest*) source_file="$MOCK_FIXTURES/release.json" ;;
    *rollout-policy.conf*) source_file="$MOCK_FIXTURES/rollout-policy.conf" ;;
    */VERSION*) source_file="$MOCK_FIXTURES/VERSION" ;;
    */bundle.conf*) source_file="$MOCK_FIXTURES/bundle.conf" ;;
    */install-all.sh*) source_file="$MOCK_FIXTURES/install-all.sh" ;;
    *) exit 22 ;;
esac
cp "$source_file" "$out"
EOF_CURL
chmod +x "$BIN/logger" "$BIN/ip" "$BIN/uci" "$BIN/curl"

write_config() {
    cat > "$TMP/update.conf" <<'EOF_CONF'
HOME_NET_UPDATE_MODE='apply'
HOME_NET_UPDATE_CANARY='1'
HOME_NET_UPDATE_INTERVAL='86400'
HOME_NET_UPDATE_JITTER='0'
HOME_NET_UPDATE_STARTUP_DELAY='0'
HOME_NET_UPDATE_COMMAND_TIMEOUT='5'
HOME_NET_UPDATE_HEALTH_TIMEOUT='2'
HOME_NET_UPDATE_HEALTH_RETRY_INTERVAL='1'
HOME_NET_UPDATE_HEALTH_MAX_BAD_CYCLES='2'
EOF_CONF
}

enable_new_model() {
    cat >> "$TMP/update.conf" <<'EOF_NEW'
HOME_NET_AUTO_UPDATE_CAPABLE='1'
HOME_NET_ROLLOUT_RING='stable'
HOME_NET_ROLLOUT_POLICY_URL='https://mock.invalid/rollout-policy.conf'
EOF_NEW
}

write_policy() {
    tag="$1"
    rollout="$2"
    cat > "$FIXTURES/rollout-policy.conf" <<EOF_POLICY
POLICY_SCHEMA='1'
RELEASE_TAG='$tag'
ROLLOUT='$rollout'
EOF_POLICY
}

write_release() {
    version="$1"
    draft="$2"
    prerelease="$3"
    tag="${4:-v$version}"
    class="${5:-SAFE}"
    action="${6:-none}"
    reason="${7:-none}"
    printf '{"tag_name":"%s","draft":%s,"prerelease":%s}\n' "$tag" "$draft" "$prerelease" > "$FIXTURES/release.json"
    printf '%s\n' "$version" > "$FIXTURES/VERSION"
    {
        printf "HOME_NET_BUNDLE_VERSION='%s'\n" "$version"
        printf "UPDATE_ACTION_CLASS='%s'\n" "$class"
        printf "UPDATE_PENDING_ACTION='%s'\n" "$action"
        printf "UPDATE_PENDING_REASON='%s'\n" "$reason"
    } > "$FIXTURES/bundle.conf"
    MOCK_EXPECT_CLASS="$class"
    [ "$class" = CRITICAL ] && MOCK_EXPECT_STAGE=1 || MOCK_EXPECT_STAGE=0
}

write_health() {
    status="$1"
    stamp="$2"
    cat > "$TMP/health.state" <<EOF_HEALTH
STATUS=$status
PODKOP=RUNNING
SING_BOX=RUNNING
FAKEIP=OK
SERVICE_CHECK=OK
CHECK_STARTED=$stamp
LAST_CHECK=$stamp
EOF_HEALTH
}

write_installer() {
    cat > "$FIXTURES/install-all.sh" <<'EOF_INSTALLER'
#!/bin/sh
[ "$HOME_NET_BUNDLE_REF" = 'v1.5.2' ] || exit 3
[ "$HOME_NET_UPDATE_IN_PROGRESS" = '1' ] || exit 3
[ "$HOME_NET_SKIP_VERSION_RECORD" = '1' ] || exit 3
[ "$HOME_NET_ACTION_CLASS" = "$MOCK_EXPECT_CLASS" ] || exit 3
[ "$HOME_NET_STAGE_ONLY" = "$MOCK_EXPECT_STAGE" ] || exit 3
if [ "${MOCK_INSTALL_FAIL:-0}" = "1" ]; then
    exit 1
fi
write_status="${MOCK_HEALTH_STATUS:-OK}"
cat > "$MOCK_HEALTH_FILE" <<EOF_HEALTH
STATUS=$write_status
PODKOP=RUNNING
SING_BOX=RUNNING
FAKEIP=OK
SERVICE_CHECK=OK
CHECK_STARTED=2099-01-01 00:00:01
LAST_CHECK=2099-01-01 00:00:02
EOF_HEALTH
exit 0
EOF_INSTALLER
    chmod +x "$FIXTURES/install-all.sh"
}

write_state() {
    version="$1"
    cat > "$TMP/installed.state" <<EOF_STATE
INSTALLED_VERSION='$version'
ACTIVE_VERSION='$version'
UPDATE_STATUS='OK'
PENDING_ACTION='none'
PENDING_REASON='none'
PENDING_VERSION='none'
PENDING_BOOT_ID='none'
LAST_UPDATE='2000-01-01 00:00:00'
LAST_HEALTH_STATUS='OK'
INSTALL_SOURCE='test'
EOF_STATE
}

state_value() {
    sed -n "s/^$1='\([^']*\)'$/\1/p" "$TMP/installed.state"
}

reset_case() {
    rm -rf "$TMP/runtime" "$TMP/lock"
    rm -f "$TMP/output" "$TMP/coordination"
    mkdir -p "$TMP/runtime"
    printf 'boot-one\n' > "$TMP/boot-id"
    write_config
    write_policy v1.5.2 manual
    write_installer
    write_health OK '2000-01-01 00:00:00'
    MOCK_EXPECT_CLASS=SAFE
    MOCK_EXPECT_STAGE=0
    MOCK_INSTALL_FAIL=0
    MOCK_HEALTH_STATUS=OK
}

run_updater() {
    set +e
    PATH="$BIN:$PATH" \
    MOCK_FIXTURES="$FIXTURES" \
    MOCK_HEALTH_FILE="$TMP/health.state" \
    MOCK_EXPECT_CLASS="$MOCK_EXPECT_CLASS" \
    MOCK_EXPECT_STAGE="$MOCK_EXPECT_STAGE" \
    MOCK_INSTALL_FAIL="$MOCK_INSTALL_FAIL" \
    MOCK_HEALTH_STATUS="$MOCK_HEALTH_STATUS" \
    HOME_NET_UPDATE_CONF="$TMP/update.conf" \
    HOME_NET_UPDATE_STATE_FILE="$TMP/installed.state" \
    HOME_NET_UPDATE_RUNTIME_DIR="$TMP/runtime" \
    HOME_NET_UPDATE_LOCK_DIR="$TMP/lock" \
    HOME_NET_UPDATE_COORDINATION_MARKER="$TMP/coordination" \
    HOME_NET_UPDATE_BOOT_ID_FILE="$TMP/boot-id" \
    HOME_NET_UPDATE_HEALTH_STATE="$TMP/health.state" \
    HOME_NET_UPDATE_BACKUP_ROOT="$TMP/backups" \
    HOME_NET_UPDATE_API_URL='https://mock.invalid/releases/latest' \
    HOME_NET_UPDATE_RAW_URL='https://mock.invalid/repo' \
    sh "$UPDATER" "$1" > "$TMP/output" 2>&1
    RUN_RC=$?
    set -e
}

assert_rc() {
    expected="$1"
    [ "$RUN_RC" -eq "$expected" ] || {
        cat "$TMP/output" >&2
        echo "expected rc=$expected, got rc=$RUN_RC" >&2
        exit 1
    }
}

assert_output() {
    grep -Fq "$1" "$TMP/output" || {
        cat "$TMP/output" >&2
        echo "missing output: $1" >&2
        exit 1
    }
}

assert_state() {
    actual="$(state_value "$1")"
    [ "$actual" = "$2" ] || {
        cat "$TMP/installed.state" >&2
        echo "$1 expected $2, got $actual" >&2
        exit 1
    }
}

assert_gate() {
    grep -Fqx "AUTO_APPLY_STATE='$1'" "$TMP/runtime/rollout.state"
    grep -Fqx "AUTO_APPLY_ALLOWED='$2'" "$TMP/runtime/rollout.state"
    run_updater status; assert_rc 0
    assert_output "Gate:      $1"
    assert_output "AutoApply: $2"
}

case_no_update() {
    reset_case; write_release 1.5.2 false false; write_state 1.5.2
    run_updater check; assert_rc 0; assert_output 'latest stable release'
}

case_update_available() {
    reset_case; write_release 1.5.2 false false; write_state 1.5.1
    run_updater check; assert_rc 0
    assert_state UPDATE_STATUS UPDATE_AVAILABLE
    assert_state INSTALLED_VERSION 1.5.1
}

case_no_downgrade() {
    reset_case; write_release 1.5.1 false false; write_state 1.5.2
    run_updater check; assert_rc 0; assert_output 'no downgrade'
}

case_invalid_tag() {
    reset_case; write_release 1.5.2 false false latest; write_state 1.5.1
    run_updater check; [ "$RUN_RC" -ne 0 ] || exit 1; assert_output 'tag is missing or invalid'
}

case_draft_rejected() {
    reset_case; write_release 1.5.2 true false; write_state 1.5.1
    run_updater check; [ "$RUN_RC" -ne 0 ] || exit 1; assert_output 'draft or metadata is invalid'
}

case_prerelease_rejected() {
    reset_case; write_release 1.5.2 false true; write_state 1.5.1
    run_updater check; [ "$RUN_RC" -ne 0 ] || exit 1; assert_output 'prerelease or metadata is invalid'
}

case_non_canary_rejected() {
    reset_case; write_release 1.5.2 false false; write_state 1.5.1
    sed -i "s/HOME_NET_UPDATE_CANARY='1'/HOME_NET_UPDATE_CANARY='0'/" "$TMP/update.conf"
    run_updater apply; [ "$RUN_RC" -ne 0 ] || exit 1
    assert_output "apply is allowed only when HOME_NET_UPDATE_CANARY='1'"
}

case_check_mode_apply_rejected() {
    reset_case; write_release 1.5.2 false false; write_state 1.5.1
    sed -i "s/HOME_NET_UPDATE_MODE='apply'/HOME_NET_UPDATE_MODE='check'/" "$TMP/update.conf"
    run_updater apply; [ "$RUN_RC" -ne 0 ] || exit 1
    assert_output "apply is allowed only when HOME_NET_UPDATE_MODE='apply'"
    assert_state INSTALLED_VERSION 1.5.1
}

case_safe_update() {
    reset_case; write_release 1.5.2 false false; write_state 1.5.1
    run_updater apply; assert_rc 0
    assert_state INSTALLED_VERSION 1.5.2
    assert_state ACTIVE_VERSION 1.5.2
    assert_state UPDATE_STATUS OK
}

case_controlled_success() {
    reset_case; write_release 1.5.2 false false v1.5.2 CONTROLLED controlled_bundle_activation none; write_state 1.5.1
    run_updater apply; assert_rc 0
    assert_state INSTALLED_VERSION 1.5.2
    assert_state ACTIVE_VERSION 1.5.2
    assert_state UPDATE_STATUS OK
    [ ! -e "$TMP/coordination" ]
}

case_controlled_health_fail() {
    reset_case; write_release 1.5.2 false false v1.5.2 CONTROLLED controlled_bundle_activation none; write_state 1.5.1
    MOCK_HEALTH_STATUS=FAIL
    run_updater apply; [ "$RUN_RC" -ne 0 ] || exit 1
    assert_state INSTALLED_VERSION 1.5.2
    assert_state ACTIVE_VERSION 1.5.1
    assert_state UPDATE_STATUS FAILED
    assert_state LAST_HEALTH_STATUS FAIL
}

case_controlled_health_unknown() {
    reset_case; write_release 1.5.2 false false v1.5.2 CONTROLLED controlled_bundle_activation none; write_state 1.5.1
    MOCK_HEALTH_STATUS=UNKNOWN
    run_updater apply; [ "$RUN_RC" -ne 0 ] || exit 1
    assert_state INSTALLED_VERSION 1.5.2
    assert_state ACTIVE_VERSION 1.5.1
    assert_state UPDATE_STATUS FAILED
    assert_state LAST_HEALTH_STATUS UNKNOWN
}

case_critical_pending() {
    reset_case; write_release 1.5.2 false false v1.5.2 CRITICAL network_restart 'network activation required'; write_state 1.5.1
    run_updater apply; assert_rc 0
    assert_state INSTALLED_VERSION 1.5.2
    assert_state ACTIVE_VERSION 1.5.1
    assert_state UPDATE_STATUS PENDING_APPLY
    assert_state PENDING_ACTION network_restart
}

case_reboot_pending_and_promoted() {
    reset_case; write_release 1.5.2 false false v1.5.2 CRITICAL reboot 'reboot activation required'; write_state 1.5.1
    run_updater apply; assert_rc 0
    assert_state INSTALLED_VERSION 1.5.2
    assert_state ACTIVE_VERSION 1.5.1
    assert_state PENDING_ACTION reboot
    printf 'boot-two\n' > "$TMP/boot-id"
    run_updater reconcile; assert_rc 0
    assert_state ACTIVE_VERSION 1.5.2
    assert_state UPDATE_STATUS OK
}

case_pending_survives_restart() {
    reset_case; write_release 1.5.2 false false v1.5.2 CRITICAL network_restart 'manual activation required'; write_state 1.5.1
    run_updater apply; assert_rc 0
    run_updater status; assert_rc 0
    assert_output 'Status:    PENDING_APPLY'
    assert_output 'Pending:   network_restart'
}

case_installer_failure() {
    reset_case; write_release 1.5.2 false false; write_state 1.5.1
    MOCK_INSTALL_FAIL=1
    run_updater apply; [ "$RUN_RC" -ne 0 ] || exit 1
    assert_state INSTALLED_VERSION 1.5.1
    assert_state ACTIVE_VERSION 1.5.1
    assert_state UPDATE_STATUS FAILED
}

case_diagnostic_installer_text() {
    reset_case; write_release 1.5.2 false false; write_state 1.5.1
    printf '\necho "reboot /etc/init.d/network restart"\n# reboot\n' >> "$FIXTURES/install-all.sh"
    run_updater apply; assert_rc 0
    assert_state ACTIVE_VERSION 1.5.2
}

case_real_installer_scanner() {
    reset_case; write_release 1.5.2 false false; write_state 1.5.1
    cp "$ROOT/install-all.sh" "$FIXTURES/install-all.sh"
    # Reach payload validation, but stop before running the actual installer.
    printf "UPDATE_ACTION_CLASS='INVALID'\n" >> "$FIXTURES/bundle.conf"
    run_updater apply
    [ "$RUN_RC" -ne 0 ] || exit 1
    assert_output 'invalid or missing UPDATE_ACTION_CLASS'
}

case_forbidden_network_restart() {
    reset_case; write_release 1.5.2 false false v1.5.2 CONTROLLED controlled_bundle_activation none; write_state 1.5.1
    printf '\n/etc/init.d/network restart\n' >> "$FIXTURES/install-all.sh"
    run_updater apply; [ "$RUN_RC" -ne 0 ] || exit 1
    assert_output 'automatic network restart or reboot'
    assert_state INSTALLED_VERSION 1.5.1
}

case_forbidden_reboot() {
    reset_case; write_release 1.5.2 false false v1.5.2 CRITICAL reboot required; write_state 1.5.1
    printf '\nreboot\n' >> "$FIXTURES/install-all.sh"
    run_updater apply; [ "$RUN_RC" -ne 0 ] || exit 1
    assert_output 'automatic network restart or reboot'
    assert_state ACTIVE_VERSION 1.5.1
}

case_rollout_manual_blocks_auto() {
    reset_case; enable_new_model; write_release 1.5.2 false false; write_policy v1.5.2 manual; write_state 1.5.1
    run_updater auto; assert_rc 0
    assert_state INSTALLED_VERSION 1.5.1
    assert_gate 'WAITING FOR CANARY' 0
}

case_rollout_canary_blocks_stable() {
    reset_case; enable_new_model; write_release 1.5.2 false false; write_policy v1.5.2 canary; write_state 1.5.1
    run_updater auto; assert_rc 0
    assert_state INSTALLED_VERSION 1.5.1
    assert_gate 'WAITING FOR FLEET' 0
}

case_rollout_canary_allows_canary() {
    reset_case; enable_new_model
    sed -i "s/HOME_NET_ROLLOUT_RING='stable'/HOME_NET_ROLLOUT_RING='canary'/" "$TMP/update.conf"
    write_release 1.5.2 false false; write_policy v1.5.2 canary; write_state 1.5.1
    run_updater auto; assert_rc 0
    assert_state INSTALLED_VERSION 1.5.2
    assert_state ACTIVE_VERSION 1.5.2
    grep -Fq "AUTO_APPLY_ALLOWED='1'" "$TMP/runtime/rollout.state"
    assert_gate 'AUTO APPLY ALLOWED' 1
}

case_rollout_fleet_allows_stable() {
    reset_case; enable_new_model; write_release 1.5.2 false false; write_policy v1.5.2 fleet; write_state 1.5.1
    run_updater auto; assert_rc 0
    assert_state INSTALLED_VERSION 1.5.2
    assert_state ACTIVE_VERSION 1.5.2
    assert_gate 'AUTO APPLY ALLOWED' 1
}

case_rollout_policy_mismatch_fails_closed() {
    reset_case; enable_new_model; write_release 1.5.2 false false; write_policy v1.5.1 fleet; write_state 1.5.1
    run_updater auto; assert_rc 0
    assert_state INSTALLED_VERSION 1.5.1
    grep -Fq "POLICY_STATUS='MISMATCH'" "$TMP/runtime/rollout.state"
    grep -Fq "AUTO_APPLY_ALLOWED='0'" "$TMP/runtime/rollout.state"
    assert_gate 'POLICY BLOCKED' 0
}

case_rollout_policy_invalid_fails_closed() {
    reset_case; enable_new_model; write_release 1.5.2 false false; write_state 1.5.1
    cat > "$FIXTURES/rollout-policy.conf" <<'EOF_BAD'
POLICY_SCHEMA='1'
RELEASE_TAG='v1.5.2'
ROLLOUT='fleet'
EVIL='1'
EOF_BAD
    run_updater auto; assert_rc 0
    assert_state INSTALLED_VERSION 1.5.1
    grep -Fq "POLICY_STATUS='INVALID'" "$TMP/runtime/rollout.state"
    assert_gate 'POLICY BLOCKED' 0
}

case_rollout_policy_unavailable_fails_closed() {
    reset_case; enable_new_model; write_release 1.5.2 false false; write_state 1.5.1
    rm -f "$FIXTURES/rollout-policy.conf"
    run_updater auto; assert_rc 0
    assert_state INSTALLED_VERSION 1.5.1
    grep -Fq "POLICY_STATUS='UNAVAILABLE'" "$TMP/runtime/rollout.state"
    grep -Fq "AUTO_APPLY_ALLOWED='0'" "$TMP/runtime/rollout.state"
    assert_gate 'POLICY BLOCKED' 0
}

case_rollout_disabled_and_blocked_precedence() {
    reset_case; enable_new_model; write_release 1.5.2 false false; write_policy v1.5.2 fleet; write_state 1.5.1
    sed -i "s/HOME_NET_AUTO_UPDATE_CAPABLE='1'/HOME_NET_AUTO_UPDATE_CAPABLE='0'/" "$TMP/update.conf"
    run_updater auto; assert_rc 0
    assert_state INSTALLED_VERSION 1.5.1
    assert_gate 'AUTO UPDATE DISABLED' 0
    write_policy v1.5.1 fleet
    run_updater auto; assert_rc 0
    assert_state INSTALLED_VERSION 1.5.1
    assert_gate 'POLICY BLOCKED' 0
}

case_rollout_status_without_cache() {
    reset_case; enable_new_model; write_state 1.5.1
    run_updater status; assert_rc 0
    assert_output 'Gate:      POLICY UNKNOWN'
    assert_output 'AutoApply: 0'
    assert_output 'Latest:    unknown'
    [ ! -e "$TMP/runtime/rollout.state" ]
}

case_check_refreshes_rollout_cache() {
    reset_case; enable_new_model; write_release 1.5.2 false false; write_policy v1.5.2 canary; write_state 1.5.1
    run_updater check; assert_rc 0
    grep -Fq "LATEST_RELEASE='v1.5.2'" "$TMP/runtime/rollout.state"
    grep -Fq "RELEASE_ROLLOUT='canary'" "$TMP/runtime/rollout.state"
}

case_new_model_manual_apply_ignores_rollout() {
    reset_case; enable_new_model
    sed -i "s/HOME_NET_UPDATE_MODE='apply'/HOME_NET_UPDATE_MODE='check'/" "$TMP/update.conf"
    sed -i "s/HOME_NET_UPDATE_CANARY='1'/HOME_NET_UPDATE_CANARY='0'/" "$TMP/update.conf"
    write_release 1.5.2 false false; write_policy v1.5.2 manual; write_state 1.5.1
    run_updater apply; assert_rc 0
    assert_state INSTALLED_VERSION 1.5.2
}

case_stale_lock() {
    reset_case; write_release 1.5.2 false false; write_state 1.5.2
    mkdir -p "$TMP/lock"
    printf '99999999\n' > "$TMP/lock/pid"
    run_updater check; assert_rc 0; assert_output 'recovering stale update lock'
}

for test_case in \
    case_no_update \
    case_update_available \
    case_no_downgrade \
    case_invalid_tag \
    case_draft_rejected \
    case_prerelease_rejected \
    case_non_canary_rejected \
    case_check_mode_apply_rejected \
    case_safe_update \
    case_controlled_success \
    case_controlled_health_fail \
    case_controlled_health_unknown \
    case_critical_pending \
    case_reboot_pending_and_promoted \
    case_pending_survives_restart \
    case_installer_failure \
    case_diagnostic_installer_text \
    case_real_installer_scanner \
    case_forbidden_network_restart \
    case_forbidden_reboot \
    case_rollout_manual_blocks_auto \
    case_rollout_canary_blocks_stable \
    case_rollout_canary_allows_canary \
    case_rollout_fleet_allows_stable \
    case_rollout_policy_mismatch_fails_closed \
    case_rollout_policy_invalid_fails_closed \
    case_rollout_policy_unavailable_fails_closed \
    case_rollout_disabled_and_blocked_precedence \
    case_rollout_status_without_cache \
    case_check_refreshes_rollout_cache \
    case_new_model_manual_apply_ignores_rollout \
    case_stale_lock
do
    "$test_case"
    echo "PASS $test_case"
done

echo 'All home-net-update tests passed.'
