#!/bin/sh
set -eu

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
BOOTSTRAP="$ROOT/install.sh"

sh -n "$BOOTSTRAP"
grep -Fq 'downloading v1.5.0' "$BOOTSTRAP"
grep -Fq '[ "$VERSION" = "1.5.0" ]' "$BOOTSTRAP"

echo "PASS logging_bootstrap_version_text"
