#!/bin/sh
set -eu

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
BOOTSTRAP="$ROOT/install.sh"

sh -n "$BOOTSTRAP"

grep -Fq 'v1.4.4' "$BOOTSTRAP"
grep -Fq 'HOME_NET_RELEASE_REF:-aeacc81ec1ae4e90eefe6747f02b86e70d297f45' "$BOOTSTRAP"
grep -Fq '[ "$VERSION" = "1.4.4" ]' "$BOOTSTRAP"

echo 'PASS monitoring_bootstrap_accepts_1_4_4'
