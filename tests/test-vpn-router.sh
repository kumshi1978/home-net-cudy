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
    prepared-address) test "$2:$3" = awg_backup2:10.8.1.210/32 ;;
    snapshot) cp candidate "$4/candidate" ;;
    stage) cp "$4" candidate; test ! -e fail-stage ;;
    verify) test "$(cat active)" = "$2" && test "$4" = DE && test ! -e fail-verify ;;
    persist) touch persisted ;;
    capabilities) echo "awg_main awg_backup awg_backup2" ;;
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
cat >"$tmp/ip" <<'EOF'
#!/bin/sh
if [ "$1" = link ]; then [ ! -f "$TEST_CONFIG/down-third" ] || [ "$4" != awg_backup2 ]; exit $?; fi
case "$6" in
    awg_backup2) address=10.8.1.210/32 ;;
    awg_backup) address=10.8.1.13/32 ;;
    awg_main)
        [ ! -e "$TEST_CONFIG/no-active-address" ] || exit 0
        address=10.8.1.2/32
        if [ -e "$TEST_CONFIG/duplicate-address" ]; then address=10.8.1.13/24; fi
        ;;
    *) exit 1 ;;
esac
printf '7: %s    inet %s scope global\n' "$6" "$address"
EOF
chmod +x "$tmp/ip"
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
printf 'age-encryption.org/v1\n' >"$tmp/upload"
reject prepare-upload-target canary DE awg_main 10.8.1.13/32 <"$tmp/upload"
reject prepare-upload-target canary DE awg_backup 10.8.1.14/32 <"$tmp/upload"
touch "$TEST_CONFIG/duplicate-address"
reject prepare-upload-target canary DE awg_backup 10.8.1.13/32 <"$tmp/upload"
rm "$TEST_CONFIG/duplicate-address"
touch "$TEST_CONFIG/no-active-address"
reject prepare-upload-target canary DE awg_backup 10.8.1.13/32 <"$tmp/upload"
rm "$TEST_CONFIG/no-active-address"
test ! -e "$tmp/config/transaction"
run prepare-upload-target canary DE awg_backup 10.8.1.13/32 <"$tmp/upload"
run rollback
mv "$tmp/config/transaction" "$tmp/targeted"
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
run status | grep -qx "TRANSACTION_LOCK='idle'"
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
# A verified third reserve is accepted without switching the active path.
mv "$TEST_CONFIG/transaction" "$tmp/previous-upload"
echo awg_main > "$TEST_CONFIG/active"
touch "$TEST_CONFIG/down-third"
reject prepare-upload-target unsafe DE awg_backup2 10.8.1.211/32 < "$tmp/upload"
run prepare-upload-target third-reserve DE awg_backup2 10.8.1.210/32 < "$tmp/upload"
reject accept
run verify
reject accept-id 00000000000000000000000000000000
run accept
test "$(cat "$TEST_CONFIG/active")" = awg_main
test ! -e "$TEST_CONFIG/transaction"
test -f "$TEST_CONFIG/persisted"
test "$(cat "$TEST_CONFIG/completed/third-reserve/phase")" = accepted
test "$(cat "$TEST_CONFIG/completed/third-reserve/payload.sha256")" = "$(sha256sum < "$tmp/upload" | cut -d ' ' -f 1)"
run status | grep -Fq "TRANSACTION_STATE='idle'"
echo 'PASS: third-slot verification and acceptance preserve active VPN and archive rollback'

echo 'PASS: router lifecycle, maintenance contention and reboot fencing'
