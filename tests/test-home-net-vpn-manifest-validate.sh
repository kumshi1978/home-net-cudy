#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
VALIDATOR="$ROOT/scripts/home-net-vpn-manifest-validate"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

cat >"$TMP/good.conf" <<'EOF'
FORMAT_VERSION='1'
DEPLOYMENT_ID='de-vds-20261103'
CREATED_AT='2026-11-03T20:00:00Z'
COUNTRY='DE'
TARGET_SLOT='awg_main'
ROUTERS='apartment-main apartment-backup dacha-main dacha-backup'
PROVIDER='example'
REASON='provider_block'
EOF

sh "$VALIDATOR" "$TMP/good.conf" >/dev/null

cat >"$TMP/secret.conf" <<'EOF'
FORMAT_VERSION='1'
DEPLOYMENT_ID='bad'
CREATED_AT='2026-11-03T20:00:00Z'
COUNTRY='DE'
TARGET_SLOT='awg_main'
ROUTERS='apartment-main apartment-backup dacha-main dacha-backup'
PRIVATE_KEY='must-not-be-here'
EOF

if sh "$VALIDATOR" "$TMP/secret.conf" >/dev/null 2>&1; then
    echo "FAIL: secret-bearing manifest was accepted" >&2
    exit 1
fi

cat >"$TMP/missing-router.conf" <<'EOF'
FORMAT_VERSION='1'
DEPLOYMENT_ID='bad2'
CREATED_AT='2026-11-03T20:00:00Z'
COUNTRY='DE'
TARGET_SLOT='awg_backup'
ROUTERS='apartment-main apartment-backup dacha-main'
EOF

if sh "$VALIDATOR" "$TMP/missing-router.conf" >/dev/null 2>&1; then
    echo "FAIL: incomplete router set was accepted" >&2
    exit 1
fi

echo "PASS: HOME NET VPN manifest validator"
