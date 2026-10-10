#!/bin/sh
set -eu

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
BOOTSTRAP="$ROOT/install.sh"

sh -n "$BOOTSTRAP"
grep -Fq 'v1.6.0' "$BOOTSTRAP"
grep -Fq 'HOME_NET_RELEASE_REF:-736798dbb673d76e220e6a5b9aa47dfdfa8f01f1' "$BOOTSTRAP"
grep -Fq '[ "$VERSION" = "1.6.0" ]' "$BOOTSTRAP"

echo 'PASS monitoring_bootstrap_accepts_1_6_0'
