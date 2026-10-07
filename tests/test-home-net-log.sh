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
Tue Oct  6 01:00:00 2026 daemon.info dnsmasq[100]: query[A] api.example.com from 192.168.235.100
Tue Oct  6 01:00:00 2026 daemon.info dnsmasq[100]: reply api.example.com is 198.18.0.10
Tue Oct  6 01:00:01 2026 daemon.info dnsmasq[100]: query[A] direct.example.net from 192.168.235.101
Tue Oct  6 01:00:02 2026 user.notice podkop-service-health: HOME NET FAIL
Tue Oct  6 01:00:03 2026 user.notice podkop-awg: main check failed (1/3)
EOF

grep -Fq '|192.168.235.100|A|api.example.com' "$TMP/log/domains.log"
grep -Fq '|192.168.235.101|A|direct.example.net' "$TMP/log/domains.log"
grep -Fxq 'api.example.com' "$TMP/log/fakeip-domains.txt"
grep -Fq '|ERROR|monitoring|HOME NET FAIL' "$TMP/log/problems.log"
grep -Fq '|WARN|failover|main check failed (1/3)' "$TMP/log/problems.log"

HOME_NET_LOG_CONF="$CONF" HOME_NET_LOG_DIR="$TMP/log" sh "$CLI" report 20 > "$TMP/report"
grep -Eq '^1 FAKEIP api\.example\.com$' "$TMP/report"
grep -Eq '^1 DIRECT_OR_UNKNOWN direct\.example\.net$' "$TMP/report"

sh -n "$DAEMON"
sh -n "$CLI"

echo "PASS home_net_domain_problem_logging"
