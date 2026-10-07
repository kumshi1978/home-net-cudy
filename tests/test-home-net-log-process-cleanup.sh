#!/bin/sh
set -eu

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
DAEMON="$ROOT/scripts/home-net-log-daemon"

sh -n "$DAEMON"
grep -Fq 'mkfifo "$FIFO"' "$DAEMON"
grep -Fq 'LOGREAD_PID=$!' "$DAEMON"
grep -Fq 'trap cleanup EXIT HUP INT TERM' "$DAEMON"
grep -Fq 'kill "$LOGREAD_PID"' "$DAEMON"

if grep -Fq 'logread -f 2>/dev/null | while' "$DAEMON"; then
    echo "pipeline logread loop still present" >&2
    exit 1
fi

echo "PASS home_net_log_process_cleanup"
