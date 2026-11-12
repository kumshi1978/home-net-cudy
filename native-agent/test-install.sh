#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT HUP INT TERM
mkdir -p "$TMP/bin" "$TMP/root/etc/config" "$TMP/root/etc/init.d" "$TMP/root/usr/sbin" "$TMP/root/usr/bin" "$TMP/root/var/run" "$TMP/root/overlay" "$TMP/payload"
export FIXTURE="$TMP/root" FREE_KIB=100000
export REAL_FLOCK=$(command -v flock)
cat >"$TMP/bin/id" <<'EOF'
#!/bin/sh
echo 0
EOF
cat >"$TMP/bin/uname" <<'EOF'
#!/bin/sh
echo aarch64
EOF
cat >"$TMP/bin/flock" <<'EOF'
#!/bin/sh
if [ "${MOCK_REAL_FLOCK:-0}" = 1 ]; then exec "$REAL_FLOCK" "$@"; fi
exit 0
EOF
cat >"$TMP/bin/df" <<'EOF'
#!/bin/sh
printf 'Filesystem 1024-blocks Used Available Capacity Mounted\nfixture 999999 0 %s 0%% /\n' "$FREE_KIB"
EOF
cat >"$TMP/bin/uci" <<'EOF'
#!/bin/sh
if [ -f "$FIXTURE/prepared-fixture" ]; then
    case "$*" in
        '-q get podkop.main.connection_type') echo vpn ;;
        '-q get podkop.main.interface') echo awg_main ;;
        *) exit 1 ;;
    esac
fi
exit 0
EOF
cat >"$TMP/bin/awg" <<'EOF'
#!/bin/sh
[ "$*" = 'showconf awg_backup' ] || exit 1
printf 'synthetic prepared candidate\n'
EOF
chmod +x "$TMP/bin/"*
export PATH="$TMP/bin:$PATH"
sed -e "s@/etc/@$FIXTURE/etc/@g" -e "s@/usr/@$FIXTURE/usr/@g" -e "s@/var/run/@$FIXTURE/var/run/@g" -e "s@df -Pk /overlay@df -Pk $FIXTURE/overlay@" "$ROOT/install.sh" >"$TMP/payload/install.sh"
cat >"$TMP/payload/vpn-control-cudy" <<'EOF'
#!/bin/sh
case "$1" in
    self-test) exit 0 ;;
    identity-init) mkdir -p "$FIXTURE/etc/home-net/keys"; echo 'synthetic test identity' >"$FIXTURE/etc/home-net/keys/age-identity.txt" ;;
    *) exit 93 ;;
esac
EOF
cat >"$TMP/payload/vpn-control-cudy.init" <<'EOF'
#!/bin/sh
case "$1" in
    enable) exit 0 ;;
    start) [ "${MOCK_START_FAIL:-0}" != 1 ] || exit 1; touch "$FIXTURE/running" ;;
    running) [ -f "$FIXTURE/running" ] ;;
    stop) rm -f "$FIXTURE/running" ;;
    *) exit 1 ;;
esac
EOF
for file in home-net-vpn-router home-net-vpn-cudy-adapter home-net-vpn-manifest-validate home-net-vpn-persist; do
    printf '#!/bin/sh\nexit 0\n' >"$TMP/payload/$file"
done
chmod +x "$TMP/payload/"*
printf '%s\n' baseline-network >"$FIXTURE/etc/config/network"
printf '%s\n' baseline-podkop >"$FIXTURE/etc/config/podkop"
printf "INSTALLED_VERSION='1.5.0'\nPODKOP_SECTION='main'\n" >"$FIXTURE/etc/podkop-awg-failover.conf"
cp "$FIXTURE/etc/config/network" "$TMP/network.before"
cp "$FIXTURE/etc/config/podkop" "$TMP/podkop.before"
(cd "$TMP/payload"; sha256sum --text vpn-control-cudy home-net-vpn-router home-net-vpn-cudy-adapter home-net-vpn-manifest-validate home-net-vpn-persist vpn-control-cudy.init install.sh >SHA256SUMS)
run() { if sh "$TMP/payload/install.sh" "$1" >"$TMP/output" 2>&1; then return 0; else rc=$?; cat "$TMP/output"; return "$rc"; fi; }
run --preflight
test ! -e "$FIXTURE/etc/home-net/keys/age-identity.txt"
test ! -e "$FIXTURE/usr/sbin/vpn-control-cudy"
echo 'PASS preflight is not an installation'
(
    export MOCK_REAL_FLOCK=1
    exec 9>>"$FIXTURE/var/run/home-net-vpn-maintenance.lock"
    "$REAL_FLOCK" -n 9
    run --preflight
)
echo 'PASS installer reuses the inherited bundle maintenance lock'
(
    export MOCK_REAL_FLOCK=1
    exec 8>>"$FIXTURE/var/run/home-net-vpn-maintenance.lock"
    "$REAL_FLOCK" -n 8
    if run --preflight; then echo 'independent lock ignored' >&2; exit 1; fi
    grep -q 'VPN maintenance busy' "$TMP/output"
)
echo 'PASS independent maintenance lock prevents installation'
if FREE_KIB=0 run --install; then echo 'space gate failed' >&2; exit 1; fi
grep -q 'not enough space' "$TMP/output"
test ! -e "$FIXTURE/usr/sbin/vpn-control-cudy"
echo 'PASS current-install space gate precedes target writes'
printf '%s\n' custom-controller >"$FIXTURE/usr/bin/home-net-vpn-router"
if run --install; then echo 'custom-code gate failed' >&2; exit 1; fi
grep -q 'custom target preserved' "$TMP/output"
grep -Fxq custom-controller "$FIXTURE/usr/bin/home-net-vpn-router"
rm "$FIXTURE/usr/bin/home-net-vpn-router"
echo 'PASS unreviewed local code is preserved'
if MOCK_START_FAIL=1 run --install; then echo 'service-start failure ignored' >&2; exit 1; fi
test ! -e "$FIXTURE/usr/sbin/vpn-control-cudy"
test ! -e "$FIXTURE/usr/bin/home-net-vpn-router"
cmp "$TMP/network.before" "$FIXTURE/etc/config/network"
cmp "$TMP/podkop.before" "$FIXTURE/etc/config/podkop"
echo 'PASS failed activation restores absent managed code and preserves network'
run --install
test -x "$FIXTURE/usr/sbin/vpn-control-cudy"
test -x "$FIXTURE/usr/bin/home-net-vpn-persist"
test -f "$FIXTURE/etc/home-net/native-agent-files.sha256"
test -f "$FIXTURE/running"
cmp "$TMP/network.before" "$FIXTURE/etc/config/network"
cmp "$TMP/podkop.before" "$FIXTURE/etc/config/podkop"
echo 'PASS installation preserves protected configuration and starts only the agent'

# Prepared-transaction rescue is explicitly bound to one same-boot deployment.
tx="$FIXTURE/etc/home-net/vpn/transaction"
mkdir -p "$tx/backup"
printf '%s\n' prepared >"$tx/phase"
printf '%s\n' 1d40d2f70e92f42d9bfa87c2967a525a >"$tx/deployment-id"
cat /proc/sys/kernel/random/boot_id >"$tx/boot-id"
printf 'awg_main\nawg_backup\nUS\n' >"$tx/metadata"
printf 'main\n' >"$FIXTURE/etc/home-net/vpn/podkop-section"
printf 'synthetic prepared candidate\n' | sha256sum | cut -d ' ' -f 1 >"$tx/backup/candidate.sha256"
touch "$FIXTURE/prepared-fixture"
if run --preflight; then echo 'prepared without opt-in allowed' >&2; exit 1; fi
if HOME_NET_ALLOW_PREPARED_UPGRADE=1 HOME_NET_PREPARED_DEPLOYMENT_ID=00000000000000000000000000000000 run --preflight; then
    echo 'wrong deployment accepted' >&2; exit 1
fi
cp "$tx/boot-id" "$TMP/boot-good"
printf 'stale-boot\n' >"$tx/boot-id"
if HOME_NET_ALLOW_PREPARED_UPGRADE=1 HOME_NET_PREPARED_DEPLOYMENT_ID=1d40d2f70e92f42d9bfa87c2967a525a run --preflight; then
    echo 'stale boot accepted' >&2; exit 1
fi
cp "$TMP/boot-good" "$tx/boot-id"
printf '%s\n' 0000000000000000000000000000000000000000000000000000000000000000 >"$tx/backup/candidate.sha256"
if HOME_NET_ALLOW_PREPARED_UPGRADE=1 HOME_NET_PREPARED_DEPLOYMENT_ID=1d40d2f70e92f42d9bfa87c2967a525a run --preflight; then
    echo 'wrong candidate fingerprint accepted' >&2; exit 1
fi
printf 'synthetic prepared candidate\n' | sha256sum | cut -d ' ' -f 1 >"$tx/backup/candidate.sha256"
HOME_NET_ALLOW_PREPARED_UPGRADE=1 HOME_NET_PREPARED_DEPLOYMENT_ID=1d40d2f70e92f42d9bfa87c2967a525a run --preflight
HOME_NET_ALLOW_PREPARED_UPGRADE=1 HOME_NET_PREPARED_DEPLOYMENT_ID=1d40d2f70e92f42d9bfa87c2967a525a run --install
grep -Fxq prepared "$tx/phase"
cmp "$TMP/network.before" "$FIXTURE/etc/config/network"
cmp "$TMP/podkop.before" "$FIXTURE/etc/config/podkop"
echo 'PASS explicit same-boot prepared rescue preserves transaction and network'
rm -rf "$tx" "$FIXTURE/prepared-fixture"

# Simulate a large already-installed native agent. Its immutable old inode must
# be retained without reserving another binary-sized flash allocation.
dd if=/dev/zero bs=1024 count=1024 2>/dev/null | tr '\000' '#' >>"$FIXTURE/usr/sbin/vpn-control-cudy"
cp "$FIXTURE/usr/sbin/vpn-control-cudy" "$TMP/old-native"
for file in "$FIXTURE/usr/sbin/vpn-control-cudy" "$FIXTURE/usr/bin/home-net-vpn-router" "$FIXTURE/etc/home-net/vpn/adapter" "$FIXTURE/usr/bin/home-net-vpn-manifest-validate" "$FIXTURE/usr/bin/home-net-vpn-persist" "$FIXTURE/etc/init.d/vpn-control-cudy"; do sha256sum --text "$file"; done >"$FIXTURE/etc/home-net/native-agent-files.sha256"
if FREE_KIB=1024 MOCK_START_FAIL=1 run --install; then echo 'upgrade start failure ignored' >&2; exit 1; fi
cmp "$TMP/old-native" "$FIXTURE/usr/sbin/vpn-control-cudy"
cmp "$TMP/network.before" "$FIXTURE/etc/config/network"
echo 'PASS failed native upgrade restores existing code'
before_inode=$(ls -i "$FIXTURE/usr/sbin/vpn-control-cudy" | awk '{print $1}')
FREE_KIB=1024 run --install
backup=$(sed -n 's/.*backup: \([^;]*\);.*/\1/p' "$TMP/output")
test -n "$backup"
after_inode=$(ls -i "$backup/files/${FIXTURE#/}/usr/sbin/vpn-control-cudy" | awk '{print $1}')
test "$before_inode" = "$after_inode"
cmp "$TMP/old-native" "$backup/files/${FIXTURE#/}/usr/sbin/vpn-control-cudy"
echo 'PASS native upgrade keeps a hard-linked rollback copy within the current-install budget'
kept=$(find "$FIXTURE/etc/home-net/native-agent-backups" -mindepth 1 -maxdepth 1 -type d -name 'install.*' | wc -l)
test "$kept" -eq 1
test -f "$backup/files/${FIXTURE#/}/usr/sbin/vpn-control-cudy"
echo 'PASS successful upgrade prunes older native snapshots but retains rollback'
