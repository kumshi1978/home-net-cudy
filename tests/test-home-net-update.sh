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
    */VERSION*) source_file="$MOCK_FIXTURES/VERSION" ;;
    */bundle.conf*) source_file="$MOCK_FIXTURES/bundle.conf" ;;
    */install-all.sh*) source_file="$MOCK_FIXTURES/install-all.sh" ;;
    *) exit 22 ;;
esac

cp "$source_file" "$out"
EOF_CURL
chmod +x "$BIN/logger" "$BIN/curl"

write_config() {
    cat > "$TMP/update.conf" <<'EOF_CONF'
HOME_NET_UPDATE_MODE='check'
HOME_NET_UPDATE_CANARY='1'
HOME_NET_UPDATE_INTERVAL='86400'
HOME_NET_UPDATE_JITTER='0'
HOME_NET_UPDATE_STARTUP_DELAY='0'
HOME_NET_UPDATE_COMMAND_TIMEOUT='5'
HOME_NET_UPDATE_HEALTH_TIMEOUT='2'
HOME_NET_UPDATE_HEALTH_RETRY_INTERVAL='1'
EOF_CONF
}

write_release() {
    version="$1"
    draft="$2"
    prerelease="$3"
    tag="${4:-v$version}"
    printf '{"tag_name":"%s","draft":%s,"prerelease":%s}\n' "$tag" "$draft" "$prerelease" > "$FIXTURES/release.json"
    printf '%s\n' "$version" > "$FIXTURES/VERSION"
    printf "HOME_NET_BUNDLE_VERSION='%s'\n" "$version" > "$FIXTURES/bundle.conf"
}

write_installer() {
    cat > "$FIXTURES/install-all.sh" <<'EOF_INSTALLER'
#!/bin/sh
[ "$HOME_NET_BUNDLE_REF" = 'v1.5.2' ] || exit 3
[ "$HOME_NET_UPDATE_IN_PROGRESS" = '1' ] || exit 3
[ "$HOME_NET_SKIP_VERSION_RECORD" = '1' ] || exit 3
if [ "${MOCK_INSTALL_FAIL:-0}" = "1" ]; then
    exit 1
fi

status="${MOCK_HEALTH_STATUS:-OK}"
cat > "$MOCK_HEALTH_FILE" <<EOF_HEALTH
STATUS=$status
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
    printf "INSTALLED_BUNDLE_VERSION='%s'\n" "$1" > "$TMP/installed.state"
}

reset_case() {
    rm -rf "$TMP/runtime" "$TMP/lock"
    rm -f "$TMP/health.state" "$TMP/output"
    mkdir -p "$TMP/runtime"
    write_config
    write_installer
}

run_updater() {
    set +e
    PATH="$BIN:$PATH" \
    MOCK_FIXTURES="$FIXTURES" \
    MOCK_HEALTH_FILE="$TMP/health.state" \
    HOME_NET_UPDATE_CONF="$TMP/update.conf" \
    HOME_NET_UPDATE_STATE_FILE="$TMP/installed.state" \
    HOME_NET_UPDATE_RUNTIME_DIR="$TMP/runtime" \
    HOME_NET_UPDATE_LOCK_DIR="$TMP/lock" \
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

case_no_update() {
    reset_case; write_release 1.5.2 false false; write_state 1.5.2
    run_updater check; assert_rc 0; assert_output 'latest stable release'
}

case_update_available() {
    reset_case; write_release 1.5.2 false false; write_state 1.5.1
    run_updater check; assert_rc 0; assert_output 'update available: 1.5.1 -> 1.5.2'
}

case_no_downgrade() {
    reset_case; write_release 1.5.2 false false; write_state 1.6.0
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

case_installer_failure() {
    reset_case; write_release 1.5.2 false false; write_state 1.5.1
    MOCK_INSTALL_FAIL=1 run_updater apply; [ "$RUN_RC" -ne 0 ] || exit 1
    grep -Fq "INSTALLED_BUNDLE_VERSION='1.5.1'" "$TMP/installed.state"
}

case_non_canary_rejected() {
    reset_case; write_release 1.5.2 false false; write_state 1.5.1
    sed -i "s/HOME_NET_UPDATE_CANARY='1'/HOME_NET_UPDATE_CANARY='0'/" "$TMP/update.conf"
    run_updater apply; [ "$RUN_RC" -ne 0 ] || exit 1
    assert_output "apply is allowed only when HOME_NET_UPDATE_CANARY='1'"
}

case_health_unknown() {
    reset_case; write_release 1.5.2 false false; write_state 1.5.1
    MOCK_HEALTH_STATUS=UNKNOWN run_updater apply; [ "$RUN_RC" -ne 0 ] || exit 1
    assert_output 'STATUS=UNKNOWN'
    grep -Fq "INSTALLED_BUNDLE_VERSION='1.5.1'" "$TMP/installed.state"
}

case_health_fail() {
    reset_case; write_release 1.5.2 false false; write_state 1.5.1
    MOCK_HEALTH_STATUS=FAIL run_updater apply; [ "$RUN_RC" -ne 0 ] || exit 1
    assert_output 'STATUS=FAIL'
    grep -Fq "INSTALLED_BUNDLE_VERSION='1.5.1'" "$TMP/installed.state"
}

case_health_ok() {
    reset_case; write_release 1.5.2 false false; write_state 1.5.1
    MOCK_HEALTH_STATUS=OK run_updater apply; assert_rc 0
    grep -Fq "INSTALLED_BUNDLE_VERSION='1.5.2'" "$TMP/installed.state"
    assert_output 'applied and recorded successfully'
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
    case_installer_failure \
    case_health_unknown \
    case_health_fail \
    case_health_ok \
    case_stale_lock
do
    "$test_case"
    echo "PASS $test_case"
done

echo 'All home-net-update tests passed.'
