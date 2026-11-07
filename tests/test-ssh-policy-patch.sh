#!/bin/sh
set -eu
ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT HUP INT TERM
mkdir -p "$TMP/bin" "$TMP/dropbear"
touch "$TMP/openwrt" "$TMP/dropbear/dropbear_ed25519_host_key"
sed "s@/etc/dropbear@$TMP/dropbear@g" "$ROOT/install-all.sh" >"$TMP/install"
cat >"$TMP/bin/wget" <<'EOF'
#!/bin/sh
while [ "$#" -gt 0 ]; do
    case "$1" in
        -O) out=$2; shift 2 ;;
        -T) shift 2 ;;
        -q) shift ;;
        *) url=$1; shift ;;
    esac
done
case "$url" in */bundle.conf) cp "$FIXTURE_BUNDLE" "$out" ;; *) echo 'unexpected component fetch' >&2; exit 1 ;; esac
EOF
cat >"$TMP/bin/dropbearkey" <<'EOF'
#!/bin/sh
echo 'Fingerprint: SHA256:p50+xjUXHLUYiXACnKHQt/Q+0Cgu9DQ/3+YjYJ1d0xk'
EOF
printf '#!/bin/sh\necho 0\n' >"$TMP/bin/id"
chmod +x "$TMP/bin/"*
for version in 1.7.4 1.7.5; do
    printf "ACTIVE_VERSION='%s'\n" "$version" >"$TMP/state"
    cp "$TMP/state" "$TMP/before"
    PATH="$TMP/bin:$PATH" FIXTURE_BUNDLE="$ROOT/bundle.conf" \
        HOME_NET_OPENWRT_RELEASE="$TMP/openwrt" HOME_NET_UPDATE_STATE="$TMP/state" \
        HOME_NET_AUTO_UPDATE_MODE=apply HOME_NET_SKIP_VERSION_RECORD=1 \
        sh "$TMP/install" >"$TMP/output"
    grep -Fq 'stable SSH policy patch complete' "$TMP/output"
    cmp "$TMP/state" "$TMP/before"
done
test "$(wc -l <"$TMP/dropbear/authorized_keys")" -eq 1
mkdir "$TMP/dropbear/.home-net-ssh-enrollment"
if PATH="$TMP/bin:$PATH" FIXTURE_BUNDLE="$ROOT/bundle.conf" \
    HOME_NET_OPENWRT_RELEASE="$TMP/openwrt" HOME_NET_UPDATE_STATE="$TMP/state" \
    HOME_NET_AUTO_UPDATE_MODE=apply HOME_NET_SKIP_VERSION_RECORD=1 \
    sh "$TMP/install" >"$TMP/output" 2>&1; then
    echo 'busy enrollment must fail' >&2; exit 1
fi
cmp "$TMP/state" "$TMP/before"
echo 'PASS stable patch grants access without component downloads or state promotion'
