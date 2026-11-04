#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
IMPORT="$ROOT/scripts/home-net-vpn-import"
VERIFY="$ROOT/scripts/home-net-vpn-bundle-verify"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

mkdir -p "$TMP/bin" "$TMP/source" "$TMP/output"

cat >"$TMP/bin/age" <<'EOF'
#!/bin/sh
set -eu
out=
input=
while [ "$#" -gt 0 ]; do
  case "$1" in
    -r) shift 2 ;;
    -o) out=$2; shift 2 ;;
    *) input=$1; shift ;;
  esac
done
[ -n "$out" ]
[ -n "$input" ]
{
  echo 'age-encryption.org/v1'
  echo '-> X25519 TEST'
  echo '--- TEST'
  sha256sum "$input" | awk '{print $1}'
} >"$out"
EOF
chmod +x "$TMP/bin/age"
export PATH="$TMP/bin:$PATH"

cat >"$TMP/source/manifest.conf" <<'EOF'
FORMAT_VERSION='1'
DEPLOYMENT_ID='de-vds-test'
CREATED_AT='2026-11-04T00:00:00Z'
COUNTRY='DE'
TARGET_SLOT='awg_main'
ROUTERS='apartment-main apartment-backup dacha-main dacha-backup'
EOF

for router in apartment-main apartment-backup dacha-main dacha-backup; do
  cat >"$TMP/source/$router.conf" <<EOF
[Interface]
PrivateKey = secret-$router
EOF
done

cat >"$TMP/recipients.conf" <<'EOF'
NAS_RECIPIENT='age1nas'
RECOVERY_RECIPIENT='age1recovery'
APARTMENT_MAIN_RECIPIENT='age1am'
APARTMENT_BACKUP_RECIPIENT='age1ab'
DACHA_MAIN_RECIPIENT='age1dm'
DACHA_BACKUP_RECIPIENT='age1db'
EOF

sh "$IMPORT" --source "$TMP/source" --recipients "$TMP/recipients.conf" --output "$TMP/output" >/dev/null

for router in apartment-main apartment-backup dacha-main dacha-backup; do
  [ ! -e "$TMP/output/$router.conf" ]
  [ -s "$TMP/output/$router.conf.age" ]
done

sh "$VERIFY" "$TMP/output" >/dev/null

if grep -R 'secret-apartment-main' "$TMP/output" >/dev/null 2>&1; then
  echo 'FAIL: plaintext secret leaked into encrypted output' >&2
  exit 1
fi

reject_bundle() {
  if sh "$VERIFY" "$TMP/output" >/dev/null 2>&1; then
    echo 'FAIL: unsafe bundle accepted' >&2
    exit 1
  fi
}

cp "$TMP/output/SHA256SUMS" "$TMP/checksums"
(cd "$TMP/output" && sha256sum ../recipients.conf >>SHA256SUMS)
reject_bundle
cp "$TMP/checksums" "$TMP/output/SHA256SUMS"
mv "$TMP/output/apartment-main.conf.age" "$TMP/payload"
ln -s "$TMP/payload" "$TMP/output/apartment-main.conf.age"
reject_bundle

echo 'PASS: HOME NET VPN NAS import/encrypt controller'
