#!/bin/sh
set -eu

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
DAEMON="$ROOT/scripts/podkop-service-health-daemon"
CONF="$ROOT/configs/podkop-service-check.conf.example"

sh -n "$DAEMON"

grep -Fq 'STARTUP_GRACE="${MONITORING_STARTUP_GRACE:-120}"' "$DAEMON"
grep -Fq 'STARTUP_POLL_INTERVAL="${MONITORING_STARTUP_POLL_INTERVAL:-5}"' "$DAEMON"
grep -Fq 'wait_for_startup_ready()' "$DAEMON"
grep -Fq 'startup readiness confirmed' "$DAEMON"
grep -Fq 'startup readiness timeout' "$DAEMON"
grep -Fq 'MONITORING_STARTUP_GRACE=120' "$CONF"
grep -Fq 'MONITORING_STARTUP_POLL_INTERVAL=5' "$CONF"

WAIT_LINE="$(grep -n '^wait_for_startup_ready$' "$DAEMON" | tail -1 | cut -d: -f1)"
LOOP_LINE="$(grep -n '^while true$' "$DAEMON" | tail -1 | cut -d: -f1)"
[ -n "$WAIT_LINE" ] && [ -n "$LOOP_LINE" ] && [ "$WAIT_LINE" -lt "$LOOP_LINE" ]

echo 'PASS monitoring_startup_readiness_wait'
