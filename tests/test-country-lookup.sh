#!/bin/sh
set -eu

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
LOOKUP="$ROOT/scripts/podkop-country-lookup"
DAEMON="$ROOT/scripts/podkop-service-health-daemon"
CHECK="$ROOT/scripts/podkop-service-check"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT HUP INT TERM

BIN="$TMP/bin"
mkdir -p "$BIN"

cat > "$BIN/logger" <<'EOF_LOGGER'
#!/bin/sh
printf '%s\n' "$*" >> "$MOCK_LOGS"
EOF_LOGGER

cat > "$BIN/curl" <<'EOF_CURL'
#!/bin/sh
iface=direct
url=''
http=200
trap 'printf "\n%s" "$http"' EXIT
while [ "$#" -gt 0 ]; do
    case "$1" in
        --interface) iface="$2"; shift 2 ;;
        --connect-timeout|--max-time|--max-filesize|-w) shift 2 ;;
        -4|-f|-s|-S|-fsS) shift ;;
        *) url="$1"; shift ;;
    esac
done
printf '%s iface=%s\n' "$url" "$iface" >> "$MOCK_CALLS"

case "$MOCK_SCENARIO:$url" in
    ipinfo-200:https://ipinfo.io/country) printf 'DE\n' ;;
    ipinfo-429:https://ipinfo.io/country) http=429; exit 22 ;;
    ipinfo-429:https://ipapi.co/country) printf 'DE\n' ;;
    invalid-json:https://ipinfo.io/country) printf '{"error":"Rate limit hit"}\n' ;;
    invalid-json:https://ipapi.co/country) printf 'DE\n' ;;
    api-fallback:https://ipinfo.io/country|api-fallback:https://ipapi.co/country) http=429; exit 22 ;;
    api-fallback:https://api.country.is/) printf '{"ip":"159.195.225.183","country":"DE"}\n' ;;
    api-json-error:https://ipinfo.io/country|api-json-error:https://ipapi.co/country) http=429; exit 22 ;;
    api-json-error:https://api.country.is/) printf '{"error":"rate limit","country":"DE"}\n' ;;
    timeout:*) http=000; exit 28 ;;
    all-fail:*) http=429; exit 22 ;;
    direct-wan:https://ipinfo.io/country) printf 'RU\n' ;;
    malformed:https://ipinfo.io/country) printf 'DEU\n' ;;
    malformed:https://ipapi.co/country) printf 'de\n' ;;
    malformed:https://api.country.is/) printf '{"country":"DEU"}\n' ;;
    ip-primary:https://ifconfig.me/ip) printf '203.0.113.7' ;;
    ip-fallback:https://ifconfig.me/ip) http=429; exit 22 ;;
    ip-fallback:https://api.ipify.org) printf '203.0.113.8' ;;
    ip-invalid:https://ifconfig.me/ip) printf '<html>blocked</html>' ;;
    ip-invalid:https://api.ipify.org) printf '999.1.1.1' ;;
    *) http=429; exit 22 ;;
esac
EOF_CURL
chmod +x "$BIN/logger" "$BIN/curl"

run_lookup() {
    scenario="$1"
    shift
    : > "$TMP/calls"
    : > "$TMP/logs"
    rm -rf "$TMP/log-state"
    set +e
    PATH="$BIN:$PATH" \
    MOCK_SCENARIO="$scenario" \
    MOCK_CALLS="$TMP/calls" \
    MOCK_LOGS="$TMP/logs" \
    PODKOP_COUNTRY_CURL="$BIN/curl" \
    PODKOP_COUNTRY_LOG_DIR="$TMP/log-state" \
    sh "$LOOKUP" "$@" > "$TMP/output" 2> "$TMP/error"
    LOOKUP_RC=$?
    set -e
}

assert_country() {
    expected="$1"
    [ "$LOOKUP_RC" -eq 0 ] || { cat "$TMP/error" >&2; exit 1; }
    [ "$(cat "$TMP/output")" = "$expected" ] || {
        echo "expected country $expected, got $(cat "$TMP/output")" >&2
        exit 1
    }
}

run_lookup ipinfo-200 awg_main
assert_country DE
[ "$(wc -l < "$TMP/calls" | tr -d ' ')" -eq 1 ]
echo 'PASS ipinfo_200_de'

run_lookup ipinfo-429 awg_main
assert_country DE
grep -Fq 'https://ipinfo.io/country iface=awg_main' "$TMP/calls"
grep -Fq 'https://ipapi.co/country iface=awg_main' "$TMP/calls"
grep -Fq 'fallback provider ipapi used' "$TMP/logs"
echo 'PASS ipinfo_429_falls_back_to_ipapi'

run_lookup invalid-json awg_main
assert_country DE
grep -Fq 'https://ipapi.co/country iface=awg_main' "$TMP/calls"
echo 'PASS invalid_ipinfo_body_falls_back_to_ipapi'

run_lookup api-fallback awg_main
assert_country DE
grep -Fq 'https://api.country.is/ iface=awg_main' "$TMP/calls"
grep -Fq 'fallback provider country-is used' "$TMP/logs"
echo 'PASS api_country_is_fallback'

run_lookup all-fail awg_main
[ "$LOOKUP_RC" -ne 0 ]
[ ! -s "$TMP/output" ]
echo 'PASS all_providers_fail_unknown_signal'

run_lookup api-json-error awg_main
[ "$LOOKUP_RC" -ne 0 ]
[ ! -s "$TMP/output" ]
echo 'PASS api_json_error_rejected'

run_lookup direct-wan
assert_country RU
grep -Fq 'https://ipinfo.io/country iface=direct' "$TMP/calls"
echo 'PASS direct_wan_ru'

run_lookup malformed awg_main
[ "$LOOKUP_RC" -ne 0 ]
[ ! -s "$TMP/output" ]
echo 'PASS malformed_country_codes_rejected'

: > "$TMP/calls"
: > "$TMP/logs"
rm -rf "$TMP/log-state"
for attempt in 1 2
do
    PATH="$BIN:$PATH" \
    MOCK_SCENARIO=ipinfo-429 \
    MOCK_CALLS="$TMP/calls" \
    MOCK_LOGS="$TMP/logs" \
    PODKOP_COUNTRY_CURL="$BIN/curl" \
    PODKOP_COUNTRY_LOG_DIR="$TMP/log-state" \
    sh "$LOOKUP" awg_main >/dev/null
done
[ "$(grep -Fc 'country provider ipinfo failed' "$TMP/logs")" -eq 1 ]
[ "$(grep -Fc 'fallback provider ipapi used' "$TMP/logs")" -eq 1 ]
echo 'PASS provider_logs_are_rate_limited'
[ "$(grep -Fc 'https://ipinfo.io/country' "$TMP/calls")" -eq 1 ]
grep -Fq 'http=429 curl=22' "$TMP/logs"
# A throttled tunnel must not suppress the direct provider.
PATH="$BIN:$PATH" MOCK_SCENARIO=ipinfo-200 MOCK_CALLS="$TMP/calls" MOCK_LOGS="$TMP/logs" PODKOP_COUNTRY_LOG_DIR="$TMP/log-state" sh "$LOOKUP" > "$TMP/output"
[ "$(cat "$TMP/output")" = DE ]
echo 'PASS cooldown_is_scoped_to_interface'
run_lookup ip-primary --ip awg_main
assert_country 203.0.113.7
[ "$(wc -l < "$TMP/calls" | tr -d ' ')" -eq 1 ]
run_lookup ip-fallback --ip awg_backup
assert_country 203.0.113.8
grep -Fq 'https://api.ipify.org iface=awg_backup' "$TMP/calls"
grep -Fq 'http=429 curl=22' "$TMP/logs"
echo 'PASS ip_fallback_preserves_interface'
run_lookup ip-invalid --ip
[ "$LOOKUP_RC" -ne 0 ] && [ ! -s "$TMP/output" ]
grep -Fq 'reason=invalid_body' "$TMP/logs"
run_lookup timeout --ip
[ "$LOOKUP_RC" -ne 0 ] && [ ! -s "$TMP/output" ]
grep -Fq 'http=000 curl=28' "$TMP/logs"
echo 'PASS malformed_ip_and_timeout_remain_unknown'


if grep -Eq '(^|[[:space:]/])(jq|python|python3)([[:space:]]|$)' "$LOOKUP"; then
    echo 'lookup must not depend on jq or python' >&2
    exit 1
fi
echo 'PASS no_jq_or_python_dependency'

grep -Fq 'ACTIVE_COUNTRY="$(get_country "$ACTIVE")"' "$DAEMON"
grep -Fq 'WAN_COUNTRY="$(get_direct_country)"' "$DAEMON"
grep -Fq 'MAIN_COUNTRY="$(get_country awg_main)"' "$DAEMON"
grep -Fq 'BACKUP_COUNTRY="$(get_country awg_backup)"' "$DAEMON"
grep -Fq 'COUNTRY=$("$COUNTRY_LOOKUP" "$IFACE"' "$CHECK"
echo 'PASS shared_lookup_is_used_for_all_country_checks'

# Execute the real state writer with isolated probes, never a live router.
sed '/^wait_for_startup_ready$/,$d' "$DAEMON" > "$TMP/daemon-lib"
(
 FIXTURE_DIR="$TMP"
 . "$TMP/daemon-lib"
 LOG_DIR="$TMP/health"; mkdir -p "$LOG_DIR"; STATE_FILE="$LOG_DIR/state"
 uci() { echo awg_main; }
 log() { printf '%s\n' "$*" >> "$FIXTURE_DIR/health.log"; }
 check_singbox() { return 0; }; check_podkop() { return 0; }; check_fakeip() { return 0; }
 get_ip() { echo 203.0.113.7; }; get_country() { echo DE; }
 get_wan_ip() { return 0; }; get_direct_country() { echo RU; }
 CHECK_STARTED_EPOCH=$(date +%s); CHECK_STARTED=fixture
 write_state
 grep -qx 'STATUS=UNKNOWN' "$STATE_FILE"
 grep -qx 'REASON=WAN IP CHECK UNKNOWN' "$STATE_FILE"
 grep -qx 'SERVICE_CHECK=SKIPPED' "$STATE_FILE"
 # The same successful IP on both paths remains a real bypass failure.
 get_wan_ip() { echo 203.0.113.7; }
 write_state
 grep -qx 'STATUS=FAIL' "$STATE_FILE"
 grep -Fq 'VPN BYPASS DETECTED' "$FIXTURE_DIR/health.log"
)
echo 'PASS unknown_probe_and_real_bypass_have_distinct_states'
echo 'All country lookup tests passed.' 
