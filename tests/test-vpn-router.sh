#!/bin/sh
set -eu
root=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
mkdir "$tmp/config" "$tmp/bundle"
export TEST_CONFIG="$tmp/config"
if [ -n "${HOME_NET_TEST_FAILOVER_INSTALLER:-}" ]; then
    for section in WATCH LATE HEALTH; do
        awk -v marker="EOF_$section" '
            $0 == marker { exit }
            inside { print }
            index($0, "<<\047" marker "\047") { inside=1 }
        ' "$HOME_NET_TEST_FAILOVER_INSTALLER" |
            sed -n '/^maintenance_lock() {/,/^}/p' |
            sed 's@/var/run/home-net-vpn-maintenance.lock@$TEST_MAINTENANCE@g' \
            >"$TEST_CONFIG/$section.lock"
        test -s "$TEST_CONFIG/$section.lock"
    done
fi

export TEST_MAINTENANCE="$tmp/maintenance.lock"
sed 's@^maintenance=/var/run/home-net-vpn-maintenance.lock$@maintenance=$TEST_MAINTENANCE@; s@^config=/etc/home-net/vpn$@config=$TEST_CONFIG@; /root required/d' \
    "$root/scripts/home-net-vpn-router" >"$tmp/router"
cp "$root/scripts/home-net-vpn-manifest-validate" "$tmp/"
chmod +x "$tmp/home-net-vpn-manifest-validate"
cat >"$tmp/config/adapter" <<'EOF'
#!/bin/sh
set -eu
cd "$TEST_CONFIG"
case "$1" in
    stage|verify|promote|restore)
        for candidate in WATCH.lock LATE.lock HEALTH.lock; do
            [ -f "$candidate" ] || continue
            if sh -c '. "./$1"; maintenance_lock' sh "$candidate" 9>&-; then
                touch conflict
                exit 1
            fi
        done
        ;;
esac
case "$1" in
    active) cat active ;;
    validate) test -s "$3" ;;
    snapshot) cp candidate "$4/candidate" ;;
    stage) cp "$4" candidate; test ! -e fail-stage ;;
    verify) test "$(cat active)" = "$2" && test "$4" = DE && test ! -e fail-verify ;;
    promote) echo "$3" >active ;;
    check-promoted) test ! -e fail-promote ;;
    restore) cp "$4/candidate" candidate; echo "$2" >active ;;
    check-restored) cmp "$4/candidate" candidate ;;
    *) exit 1 ;;
esac
EOF
cat >"$tmp/age" <<'EOF'
#!/bin/sh
printf 'synthetic fixture\n' >"$5"
EOF
chmod +x "$tmp/config/adapter" "$tmp/age"
PATH="$tmp:$PATH"
printf 'apartment-backup\n' >"$tmp/config/router-id"
printf 'awg_main\n' >"$tmp/config/active"
printf 'baseline\n' >"$tmp/config/candidate"
cat >"$tmp/bundle/manifest.conf" <<'EOF'
FORMAT_VERSION='1'
DEPLOYMENT_ID='test'
CREATED_AT='2026-11-04T00:00:00Z'
COUNTRY='DE'
TARGET_SLOT='awg_backup'
ROUTERS='apartment-main apartment-backup dacha-main dacha-backup'
EOF
echo 'synthetic ciphertext fixture' >"$tmp/bundle/apartment-backup.conf.age"
(cd "$tmp/bundle" && sha256sum manifest.conf apartment-backup.conf.age >SHA256SUMS)
digest=$(sha256sum <"$tmp/bundle/SHA256SUMS" | cut -d ' ' -f 1)
run() { sh "$tmp/router" "$@"; }
reject() {
    if run "$@" 2>/dev/null; then echo "unexpected success: $1" >&2; exit 1; fi
}
reject prepare "$tmp/bundle" "0$digest"
test ! -e "$tmp/config/transaction"
echo awg_backup >"$tmp/config/active"
reject prepare "$tmp/bundle" "$digest"
echo awg_main >"$tmp/config/active"
touch "$tmp/config/fail-stage"
reject prepare "$tmp/bundle" "$digest"
test "$(cat "$tmp/config/candidate")" = baseline
test "$(cat "$tmp/config/transaction/phase")" = rolled-back
mv "$tmp/config/transaction" "$tmp/failed-stage"
rm "$tmp/config/fail-stage"
run prepare "$tmp/bundle" "$digest"
reject promote
test "$(cat "$tmp/config/active")" = awg_main
run verify
touch "$tmp/config/fail-verify"
reject promote
reject promote
rm "$tmp/config/fail-verify"
run verify
touch "$tmp/config/fail-promote"
reject promote
test "$(cat "$tmp/config/active")" = awg_main
test "$(cat "$tmp/config/candidate")" = baseline
test "$(cat "$tmp/config/transaction/phase")" = rolled-back
mv "$tmp/config/transaction" "$tmp/failed-promotion"
rm "$tmp/config/fail-promote"
run prepare "$tmp/bundle" "$digest"
run verify
run promote
test "$(cat "$tmp/config/active")" = awg_backup
run rollback
run rollback
test "$(cat "$tmp/config/active")" = awg_main
test "$(cat "$tmp/config/candidate")" = baseline
mv "$tmp/config/transaction" "$tmp/completed"
run status | grep -qx "TRANSACTION_STATE='idle'"
run prepare "$tmp/bundle" "$digest"
run verify
printf '%s\n' previous-boot >"$tmp/config/transaction/boot-id"
run status | grep -qx "TRANSACTION_STATE='recovery-required'"
reject verify
reject promote
test "$(cat "$tmp/config/active")" = awg_main
(
    flock -n 9
    run status | grep -qx "TRANSACTION_LOCK='busy'"
    reject rollback
) 9>>"$TEST_MAINTENANCE"
test -f "$TEST_MAINTENANCE"
if run status | grep -q TRANSACTION_LOCK; then exit 1; fi
run rollback
test "$(cat "$tmp/config/active")" = awg_main
run status | grep -qx "TRANSACTION_STATE='rolled-back'"
mv "$tmp/config/transaction" "$tmp/rebooted"
run prepare "$tmp/bundle" "$digest"
run verify
echo awg_backup >"$tmp/config/active"
reject promote
run status | grep -qx "TRANSACTION_STATE='recovery-required'"
test "$(cat "$tmp/config/active")" = awg_backup
mv "$TEST_CONFIG/transaction" "$tmp/changed-active"
printf 'plaintext fixture\n' >"$tmp/upload"
reject prepare-upload candidate DE <"$tmp/upload"
test ! -e "$TEST_CONFIG/transaction"
{
    printf 'age-encryption.org/v1\n'
    dd if=/dev/zero bs=1024 count=65 2>/dev/null
} >"$tmp/upload"
reject prepare-upload candidate DE <"$tmp/upload"
test ! -e "$TEST_CONFIG/transaction"
printf 'age-encryption.org/v1\nsynthetic encrypted fixture\n' >"$tmp/upload"
reject prepare-upload '../outside' DE <"$tmp/upload"
run prepare-upload candidate DE <"$tmp/upload"
test "$(cat "$TEST_CONFIG/transaction/deployment-id")" = candidate
test "$(cat "$TEST_CONFIG/active")" = awg_backup
test "$(sed -n '2p' "$TEST_CONFIG/transaction/metadata")" = awg_main
test ! -e "$TEST_CONFIG/conflict"
if [ -f "$TEST_CONFIG/WATCH.lock" ]; then
    for candidate in WATCH.lock LATE.lock HEALTH.lock; do
        sh -c '. "$1"; maintenance_lock' sh "$TEST_CONFIG/$candidate"
        (
            . "$TEST_CONFIG/$candidate"
            maintenance_lock
            reject rollback
        )
    done
    echo 'PASS: failover 1.4.2 and HOME NET share exclusive maintenance'
fi
echo 'PASS: router lifecycle, maintenance contention and reboot fencing'
