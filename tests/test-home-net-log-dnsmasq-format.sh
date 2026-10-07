#!/bin/sh
set -eu

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
DAEMON="$ROOT/scripts/home-net-log-daemon"
CLI="$ROOT/scripts/home-net-log"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT HUP INT TERM

CONF="$TMP/home-net-log.conf"
cat > "$CONF" <<'EOF'
DOMAIN_CAPTURE=1
MAX_DOMAIN_LINES=100
MAX_PROBLEM_LINES=100
MAX_FAKEIP_DOMAINS=100
REPORT_LIMIT=20
INCIDENT_CONTEXT_LINES=20
EOF

cat <<'EOF' | HOME_NET_LOG_CONF="$CONF" HOME_NET_LOG_DIR="$TMP/log" sh "$DAEMON" --stdin
Thu Oct  8 02:10:39 2026 daemon.info dnsmasq[1]: 973 127.0.0.1/49517 query[A] github.com from 127.0.0.1
Thu Oct  8 02:10:39 2026 daemon.info dnsmasq[1]: 974 ::1/49517 query[AAAA] github.com from ::1
Thu Oct  8 02:10:39 2026 daemon.info dnsmasq[1]: 973 127.0.0.1/49517 reply github.com is 198.18.0.5
Thu Oct  8 02:10:39 2026 daemon.info dnsmasq[1]: 975 127.0.0.1/51188 query[A] example.com from 127.0.0.1
Thu Oct  8 02:10:39 2026 daemon.info dnsmasq[1]: 975 127.0.0.1/51188 reply example.com is 8.47.69.5
Thu Oct  8 02:10:44 2026 daemon.info dnsmasq[1]: 979 192.168.236.163/44520 query[A] www.microsoft.com from 192.168.236.163
Thu Oct  8 02:10:44 2026 user.notice podkop-service-health: HOME NET FAIL
EOF

grep -Fq '|127.0.0.1|A|github.com' "$TMP/log/domains.log"
grep -Fq '|::1|AAAA|github.com' "$TMP/log/domains.log"
grep -Fq '|192.168.236.163|A|www.microsoft.com' "$TMP/log/domains.log"
grep -Fxq 'github.com' "$TMP/log/fakeip-domains.txt"
grep -Fq '|ERROR|monitoring|HOME NET FAIL' "$TMP/log/problems.log"

HOME_NET_LOG_CONF="$CONF" HOME_NET_LOG_DIR="$TMP/log" sh "$CLI" report 20 > "$TMP/report"
grep -Eq '^2 FAKEIP github\.com$' "$TMP/report"
grep -Eq '^1 DIRECT_OR_UNKNOWN example\.com$' "$TMP/report"
grep -Eq '^1 DIRECT_OR_UNKNOWN www\.microsoft\.com$' "$TMP/report"

echo "PASS home_net_dnsmasq_openwrt_format"
