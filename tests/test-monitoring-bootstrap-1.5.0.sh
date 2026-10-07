#!/bin/sh
set -eu

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
BOOTSTRAP="$ROOT/install.sh"

sh -n "$BOOTSTRAP"
grep -Fq 'v1.5.0' "$BOOTSTRAP"
grep -Fq 'HOME_NET_RELEASE_REF:-af71a5a027e902d95ee2a307e90e0aac34c7a12d' "$BOOTSTRAP"
grep -Fq '[ "$VERSION" = "1.5.0" ]' "$BOOTSTRAP"

echo "PASS monitoring_1_5_0_bootstrap"
