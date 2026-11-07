#!/bin/sh
set -eu
ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT HUP INT TERM
mkdir "$TMP/bin"
touch "$TMP/openwrt"
printf "ACTIVE_VERSION='1.7.5'\n" >"$TMP/state"
cp "$TMP/state" "$TMP/before"
cat >"$TMP/control" <<'EOF'
#!/bin/sh
set -eu
test "$HOME_NET_CONTROL_REF" = 088bb5ee7589858bdd5c99314836e6b9292bd02f
test "${CONTROL_FAIL:-0}" = 0
echo installed >"$CONTROL_MARKER"
EOF
digest=$(sha256sum "$TMP/control" | cut -d ' ' -f1)
sed -e "s@/etc/dropbear@$TMP/nonexistent-dropbear@g" \
    -e "s/control_hash='[0-9a-f]*'/control_hash='$digest'/" "$ROOT/install-all.sh" >"$TMP/install"
cat >"$TMP/bin/wget" <<'EOF'
#!/bin/sh
while [ "$#" -gt 0 ]; do
    case "$1" in -O) out=$2; shift 2 ;; -T) shift 2 ;; -q) shift ;; *) url=$1; shift ;; esac
done
case "$url" in
    */bundle.conf) cp "$CONTROL_ROOT/bundle.conf" "$out" ;;
    https://raw.githubusercontent.com/kumshi1978/home-net-cudy/088bb5ee7589858bdd5c99314836e6b9292bd02f/control-agent/install.sh)
        cp "$CONTROL_FIXTURE" "$out" ;;
    *) echo 'unexpected component download' >&2; exit 1 ;;
esac
EOF
chmod +x "$TMP/bin/wget"
run() {
    PATH="$TMP/bin:$PATH" CONTROL_ROOT="$ROOT" CONTROL_FIXTURE="$TMP/control" CONTROL_MARKER="$TMP/marker" \
        HOME_NET_CONTROL_AUTOREGISTER=1 HOME_NET_OPENWRT_RELEASE="$TMP/openwrt" HOME_NET_UPDATE_STATE="$TMP/state" \
        HOME_NET_AUTO_UPDATE_MODE=apply HOME_NET_SKIP_VERSION_RECORD=1 sh "$TMP/install"
}
run >"$TMP/output"
test -f "$TMP/marker"
cmp "$TMP/before" "$TMP/state"
rm "$TMP/marker"
if CONTROL_FAIL=1 run >"$TMP/output" 2>&1; then echo 'installation error must propagate' >&2; exit 1; fi
test ! -f "$TMP/marker"
cmp "$TMP/before" "$TMP/state"
echo 'PASS normal stable upgrade installs the pinned control agent and preserves version on failure'
