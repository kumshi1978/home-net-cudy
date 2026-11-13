#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT HUP INT TERM
mkdir -p "$TMP/bin" "$TMP/lock" "$TMP/tx"
ID=1d40d2f70e92f42d9bfa87c2967a525a
export EVENTS="$TMP/events" URLS="$TMP/urls" MOCK_BUNDLE="$TMP/bundle" MOCK_BOOTSTRAP="$TMP/bootstrap"
printf '%s\n' prepared >"$TMP/tx/phase"
printf '%s\n' "$ID" >"$TMP/tx/deployment-id"
printf 'OpenWrt\n' >"$TMP/openwrt"
cat > "$MOCK_BOOTSTRAP" <<'EOF'
#!/bin/sh
[ "$HOME_NET_ALLOW_PREPARED_UPGRADE" = 1 ] || exit 71
[ "$HOME_NET_PREPARED_DEPLOYMENT_ID" = 1d40d2f70e92f42d9bfa87c2967a525a ] || exit 72
echo "native-$1" >>"$EVENTS"
EOF
chmod +x "$MOCK_BOOTSTRAP"
sha=$(sha256sum "$MOCK_BOOTSTRAP" | cut -d ' ' -f 1)
sed -e "s/^HOME_NET_BUNDLE_VERSION=.*/HOME_NET_BUNDLE_VERSION='1.7.19'/" \
    -e "s/^CONTROL_AGENT_INSTALL_SHA256=.*/CONTROL_AGENT_INSTALL_SHA256='$sha'/" \
    "$ROOT/bundle.conf" >"$MOCK_BUNDLE"
cat >"$TMP/bin/wget" <<'EOF'
#!/bin/sh
out= url=
while [ "$#" -gt 0 ]; do
  case "$1" in -q) shift ;; -T) shift 2 ;; -O) out=$2; shift 2 ;; *) url=$1; shift ;; esac
done
echo "$url" >>"$URLS"
case "$url" in
    */bundle.conf) cp "$MOCK_BUNDLE" "$out" ;;
    */control-agent/install-native.sh) cp "$MOCK_BOOTSTRAP" "$out" ;;
    *) exit 81 ;;
esac
EOF
cat >"$TMP/bin/curl" <<'EOF'
#!/bin/sh
out= url=
while [ "$#" -gt 0 ]; do
  case "$1" in -o) out=$2; shift 2 ;; --connect-timeout|--max-time) shift 2 ;; -*) shift ;; *) url=$1; shift ;; esac
done
[ -n "$out" ] || exit 82
exec "$(dirname "$0")/wget" -q -O "$out" "$url"
EOF
chmod +x "$TMP/bin/"*
sed -e "s@/etc/home-net/vpn/transaction@$TMP/tx@g" \
    -e "s@/var/run/home-net-vpn-maintenance.lock@$TMP/lock/maintenance@g" \
    "$ROOT/install-all.sh" >"$TMP/installer"
run() (
    export PATH="$TMP/bin:$PATH"
    export HOME_NET_BUNDLE_REF=v1.7.19 HOME_NET_OPENWRT_RELEASE="$TMP/openwrt"
    export HOME_NET_UPDATE_IN_PROGRESS=1 HOME_NET_STAGE_ONLY=0 HOME_NET_ACTION_CLASS=CONTROLLED
    export HOME_NET_UPDATE_STATE="$TMP/state" HOME_NET_AUTO_UPDATE_MODE=check
    export HOME_NET_ALLOW_PREPARED_UPGRADE="$ALLOW" HOME_NET_PREPARED_DEPLOYMENT_ID="$DEPLOYMENT"
    export HOME_NET_AUTOMATIC_CONTEXT="$AUTOMATIC" HOME_NET_MANAGEMENT_CONTEXT="$MANAGEMENT"
    export HOME_NET_UPDATER_BACKUP_ROOT="$TMP"
    sh "$TMP/installer" >"$TMP/output" 2>&1
)
ALLOW=0 DEPLOYMENT= AUTOMATIC=0 MANAGEMENT=0
reject() {
    : >"$EVENTS"; : >"$URLS"
    if run; then cat "$TMP/output"; echo "FAIL: accepted $1" >&2; exit 1; fi
    test ! -s "$EVENTS"
}
reject 'missing opt-in'
ALLOW=1 DEPLOYMENT=wrong reject 'malformed ID'
ALLOW=1 DEPLOYMENT=00000000000000000000000000000000 reject 'wrong ID'
ALLOW=1 DEPLOYMENT="$ID" AUTOMATIC=1 reject 'automatic context'
ALLOW=1 DEPLOYMENT="$ID" MANAGEMENT=1 reject 'LuCI context'
: >"$EVENTS"; : >"$URLS"
ALLOW=1 DEPLOYMENT="$ID" AUTOMATIC=0 MANAGEMENT=0 run || { cat "$TMP/output"; exit 1; }
printf '%s\n' native---preflight native---install >"$TMP/expected"
cmp "$TMP/expected" "$EVENTS"
test "$(wc -l <"$URLS")" -eq 2
grep -Fq 'prepared transaction preserved' "$TMP/output"
grep -Fxq prepared "$TMP/tx/phase"
grep -Fxq "$ID" "$TMP/tx/deployment-id"
test ! -e "$TMP/state"
echo 'PASS prepared rescue: explicit ID, manual-only, native-only, transaction untouched'
