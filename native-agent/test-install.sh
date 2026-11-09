#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT HUP INT TERM
mkdir -p "$TMP/bin" "$TMP/root/etc/config" "$TMP/root/etc/init.d" "$TMP/root/usr/sbin" "$TMP/root/usr/bin" "$TMP/root/var/run" "$TMP/root/overlay" "$TMP/payload"
export FIXTURE="$TMP/root" FREE_KIB=100000
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
exit 0
EOF
cat >"$TMP/bin/df" <<'EOF'
#!/bin/sh
printf 'Filesystem 1024-blocks Used Available Capacity Mounted\nfixture 999999 0 %s 0%% /\n' "$FREE_KIB"
EOF
cat >"$TMP/bin/uci" <<'EOF'
#!/bin/sh
exit 0
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
