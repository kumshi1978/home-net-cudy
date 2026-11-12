#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT HUP INT TERM
mkdir -p "$TMP/bin" "$TMP/source/native-agent-arm64" "$TMP/lock" "$TMP/backups"
export EVENTS="$TMP/events" URLS="$TMP/urls" MOCK_ARCHIVE="$TMP/archive.tar.gz"
printf '#!/bin/sh\necho 0\n' >"$TMP/bin/id"
printf '#!/bin/sh\necho "${MOCK_ARCH:-aarch64}"\n' >"$TMP/bin/uname"
cat >"$TMP/bin/wget" <<'EOF'
#!/bin/sh
while [ "$#" -gt 0 ]; do
 case "$1" in -O) out=$2;shift 2;; -T) shift 2;; -q) shift;; *) url=$1;shift;; esac
done
echo "$url" >>"$URLS"
case "$url" in
 */home-net-native-agent-1.7.17-linux-arm64.tar.gz) cp "$MOCK_ARCHIVE" "$out" ;;
 */bundle.conf) cp "$MOCK_BUNDLE" "$out" ;;
 */control-agent/install-native.sh) cp "$MOCK_BOOTSTRAP" "$out" ;;
 *) echo unexpected-component >>"$EVENTS"; exit 91 ;;
esac
EOF
cat >"$TMP/bin/curl" <<'EOF'
#!/bin/sh
out=
url=
while [ "$#" -gt 0 ]; do
 case "$1" in
  -o) out=$2; shift 2 ;;
  --connect-timeout|--max-time) shift 2 ;;
  -*) shift ;;
  *) url=$1; shift ;;
 esac
done
echo "curl:$url" >>"$URLS"
if [ "${MOCK_CURL_FAIL:-0}" = 1 ]; then
 printf 'incomplete' > "$out"
 exit 28
fi
case "$url" in
 */home-net-native-agent-1.7.17-linux-arm64.tar.gz) cp "$MOCK_ARCHIVE" "$out" ;;
 */bundle.conf) cp "$MOCK_BUNDLE" "$out" ;;
 */control-agent/install-native.sh) cp "$MOCK_BOOTSTRAP" "$out" ;;
 *) echo unexpected-component >>"$EVENTS"; exit 91 ;;
esac
EOF
chmod +x "$TMP/bin/"*
export PATH="$TMP/bin:$PATH"
cat >"$TMP/source/native-agent-arm64/install.sh" <<'EOF'
#!/bin/sh
echo "$1" >>"$EVENTS"
EOF
source_commit=$(sed -n "s/^source_commit='\([^']*\)'$/\1/p" "$ROOT/control-agent/install-native.sh")
printf 'version=1.7.17\nsource_commit=%s\narchitecture=linux-arm64\n' "$source_commit" >"$TMP/source/native-agent-arm64/BUILD-INFO"
tar -czf "$MOCK_ARCHIVE" -C "$TMP/source" native-agent-arm64
digest=$(sha256sum "$MOCK_ARCHIVE" | cut -d ' ' -f1)
sed "s/package_sha='[0-9a-f]*'/package_sha='$digest'/" "$ROOT/control-agent/install-native.sh" >"$TMP/bootstrap"
sh "$TMP/bootstrap" --preflight
sh "$TMP/bootstrap" --install
printf '%s\n' --preflight --install >"$TMP/expected"
cmp "$TMP/expected" "$EVENTS"
echo 'PASS native archive preflight and installation modes'
: >"$URLS"
MOCK_CURL_FAIL=1 sh "$TMP/bootstrap" --preflight
grep -q '^curl:' "$URLS"
test "$(wc -l <"$URLS")" = 2
echo 'PASS curl failure cleans partial archive and falls back to wget'
: >"$URLS"
HOME_NET_NATIVE_ARCHIVE="$MOCK_ARCHIVE" sh "$TMP/bootstrap" --preflight
test ! -s "$URLS"
echo 'PASS local candidate archive is checked without release publication'
: >"$EVENTS"
cp "$MOCK_ARCHIVE" "$TMP/good.tar.gz"
printf corrupt >>"$MOCK_ARCHIVE"
if sh "$TMP/bootstrap" --install >"$TMP/error" 2>&1; then exit 1; fi
grep -q 'archive integrity' "$TMP/error"
test ! -s "$EVENTS"
cp "$TMP/good.tar.gz" "$MOCK_ARCHIVE"
echo 'PASS tampered archive never reaches the installer'
sed -i "s/$source_commit/1111111111111111111111111111111111111111/" "$TMP/source/native-agent-arm64/BUILD-INFO"
tar -czf "$MOCK_ARCHIVE" -C "$TMP/source" native-agent-arm64
digest=$(sha256sum "$MOCK_ARCHIVE" | cut -d ' ' -f1)
sed "s/package_sha='[0-9a-f]*'/package_sha='$digest'/" "$ROOT/control-agent/install-native.sh" >"$TMP/bootstrap"
if sh "$TMP/bootstrap" --install >"$TMP/error" 2>&1; then exit 1; fi
grep -q 'unexpected native source' "$TMP/error"
test ! -s "$EVENTS"
echo 'PASS source provenance mismatch is rejected'
: >"$URLS"
HOME_NET_STAGE_ONLY=1 sh "$TMP/bootstrap" --install
test ! -s "$URLS"
if MOCK_ARCH=mips sh "$TMP/bootstrap" --install >"$TMP/error" 2>&1; then exit 1; fi
test ! -s "$URLS"
echo 'PASS stage-only and unsupported architecture do not download code'

# Exercise the actual bundle: preflight failure must occur before downloading
# or installing Failover, Monitoring, updater, SSH enrollment or native runtime.
export MOCK_BOOTSTRAP="$TMP/failing-bootstrap" MOCK_BUNDLE="$TMP/bundle"
printf '#!/bin/sh\necho "native-$1" >>"$EVENTS"\nexit 42\n' >"$MOCK_BOOTSTRAP"
digest=$(sha256sum "$MOCK_BOOTSTRAP" | cut -d ' ' -f1)
sed "s/^CONTROL_AGENT_INSTALL_SHA256=.*/CONTROL_AGENT_INSTALL_SHA256='$digest'/" "$ROOT/bundle.conf" >"$MOCK_BUNDLE"
sed -e "s@/var/run/home-net-vpn-maintenance.lock@$TMP/lock/maintenance@g" -e "s@/etc/dropbear@$TMP/nonexistent@g" "$ROOT/install-all.sh" >"$TMP/bundle-install"
touch "$TMP/openwrt"
: >"$EVENTS"
: >"$URLS"
if HOME_NET_CONTROL_AUTOREGISTER=1 HOME_NET_STAGE_ONLY=0 HOME_NET_OPENWRT_RELEASE="$TMP/openwrt" HOME_NET_UPDATE_STATE="$TMP/state" HOME_NET_AUTO_UPDATE_MODE=check HOME_NET_SKIP_VERSION_RECORD=1 sh "$TMP/bundle-install" >"$TMP/error" 2>&1; then exit 1; fi
grep -q 'native agent preflight failed before runtime changes' "$TMP/error"
printf '%s\n' native---preflight >"$TMP/expected"
cmp "$TMP/expected" "$EVENTS"
test "$(wc -l <"$URLS")" = 2
echo 'PASS bundle aborts before runtime changes when native preflight fails'

ref=$(sed -n "s/^CONTROL_AGENT_REF='\([^']*\)'$/\1/p" "$ROOT/bundle.conf")
printf '%s\n' "$ref" | grep -Eq '^[0-9a-f]{40}$'
expected=$(sed -n "s/^CONTROL_AGENT_INSTALL_SHA256='\([^']*\)'$/\1/p" "$ROOT/bundle.conf")
sha256sum "$ROOT/control-agent/install-native.sh"
echo "$expected  $ROOT/control-agent/install-native.sh" | sha256sum -c -
! grep -Eq 'python3|apk add|opkg install|age-keygen' "$ROOT/control-agent/install-native.sh"
echo 'PASS release manifest pins a dependency-free native bootstrap'
