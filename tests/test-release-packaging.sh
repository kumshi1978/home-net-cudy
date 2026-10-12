#!/bin/sh
set -eu
ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT HUP INT TERM
mkdir -p "$TMP/bin" "$TMP/payloads" "$TMP/target" "$TMP/backups"
MONITORING_REF=$(sed -n "s/^MONITORING_BOOTSTRAP_REF='\([^']*\)'$/\1/p" "$ROOT/bundle.conf")
UPDATER_REF=$(sed -n "s/^HOME_NET_UPDATER_REF='\([^']*\)'$/\1/p" "$ROOT/bundle.conf")
cp "$ROOT/bundle.conf" "$TMP/payloads/bundle.conf"
printf 'OpenWrt\n' > "$TMP/openwrt"
printf "INSTALLED_VERSION='1.4.1'\n" > "$TMP/failover"
cat > "$TMP/bin/wget" <<'EOF'
#!/bin/sh
out='' url=''
while [ "$#" -gt 0 ]; do
    case "$1" in
        -O) out="$2"; shift 2 ;;
        -T) shift 2 ;;
        -q) shift ;;
        *) url="$1"; shift ;;
    esac
done
printf '%s\n' "$url" >> "$MOCK_URL_LOG"
case "$url" in
    */bundle.conf) cp "$MOCK_PAYLOADS/bundle.conf" "$out" ;;
    */install.sh) cp "$MOCK_PAYLOADS/monitoring" "$out" ;;
    */scripts/home-net-update|*/init.d/home-net-update)
        printf '#!/bin/sh\nexit 0\n' > "$out" ;;
    */configs/home-net-update.conf.example)
        printf "HOME_NET_UPDATE_MODE='check'\n" > "$out" ;;
    *) exit 99 ;;
esac
EOF
cat > "$TMP/payloads/monitoring" <<'EOF'
#!/bin/sh
[ "$HOME_NET_RELEASE_REF" = "$MOCK_MONITORING_REF" ] || exit 99
EOF
for tool in curl uci pgrep; do
    printf '#!/bin/sh\nexit 0\n' > "$TMP/bin/$tool"
done
chmod +x "$TMP/bin/"*

run_installer() (
    export MOCK_MONITORING_REF="$MONITORING_REF"
    export PATH="$TMP/bin:$PATH" MOCK_URL_LOG="$TMP/urls" MOCK_PAYLOADS="$TMP/payloads"
    export HOME_NET_OPENWRT_RELEASE="$TMP/openwrt" HOME_NET_FAILOVER_CONF="$TMP/failover"
    export HOME_NET_UPDATE_BIN="$TMP/target/updater" HOME_NET_UPDATE_INIT="$TMP/target/init"
    export HOME_NET_UPDATE_CONF="$TMP/target/config" HOME_NET_UPDATE_STATE="$TMP/target/state"
    export HOME_NET_UPDATER_BACKUP_ROOT="$TMP/backups" HOME_NET_HEALTH_STATE="$TMP/health"
    export HOME_NET_UPDATE_IN_PROGRESS=1 HOME_NET_SKIP_VERSION_RECORD=1 HOME_NET_STAGE_ONLY=1
    # No runtime components run; only sandbox payloads are installed.
    if [ "$1" = unset ]; then
        unset HOME_NET_BUNDLE_REF
    else
        export HOME_NET_BUNDLE_REF="$1"
    fi
    sh "$ROOT/install-all.sh" > "$TMP/output" 2>&1
)

assert_urls() (
    ref="$1"
    cat > "$TMP/expected" <<EOF
https://raw.githubusercontent.com/kumshi1978/home-net-cudy/$ref/bundle.conf
https://raw.githubusercontent.com/kumshi1978/home-net-cudy/$MONITORING_REF/install.sh
https://raw.githubusercontent.com/kumshi1978/home-net-cudy/$UPDATER_REF/scripts/home-net-update
https://raw.githubusercontent.com/kumshi1978/home-net-cudy/$UPDATER_REF/init.d/home-net-update
https://raw.githubusercontent.com/kumshi1978/home-net-cudy/$UPDATER_REF/configs/home-net-update.conf.example
EOF
    diff -u "$TMP/expected" "$TMP/urls"
)

# Guard the default in CI even before exercising actual downloads.
if grep -Eq 'HOME_NET_BUNDLE_REF:-main|/main/' "$ROOT/install-all.sh"; then
    echo 'FAIL: moving main in release installer' >&2
    exit 1
fi
for ref in unset v1.7.3 "$UPDATER_REF"; do
    : > "$TMP/urls"
    run_installer "$ref" || { cat "$TMP/output" >&2; exit 1; }
    expected="$ref"
    [ "$ref" != unset ] || expected=v1.7.3
    assert_urls "$expected"
    echo "PASS release_ref_$ref"
done

for ref in main master feature/example refs/heads/main; do
    : > "$TMP/urls"
    if run_installer "$ref"; then
        echo "FAIL: accepted moving ref $ref" >&2; exit 1
    fi
    [ ! -s "$TMP/urls" ]
    grep -Fq 'must be a release tag' "$TMP/output"
done
echo 'PASS moving_bundle_refs_rejected_before_download'

for key in MONITORING_BOOTSTRAP_REF HOME_NET_UPDATER_REF; do
    cp "$ROOT/bundle.conf" "$TMP/payloads/bundle.conf"
    sed -i "s/^$key='[^']*'/$key='main'/" "$TMP/payloads/bundle.conf"
    : > "$TMP/urls"
    if run_installer v1.7.3; then
        echo "FAIL: accepted moving $key" >&2; exit 1
    fi
    [ "$(wc -l < "$TMP/urls")" -eq 1 ]
    grep -Fq "$key must be a full commit SHA" "$TMP/output"
    echo "PASS moving_$key rejected"
done

grep -Fq "HOME_NET_RELEASE_REF:-v1.7.3" "$ROOT/install.sh"
grep -Fq "LUCI_VIEW_SRC=\"\$BASE_DIR/../luci/view/home-net/status.js\"" "$ROOT/install/install.sh"
grep -Fq '/main/rollout-policy.conf' "$ROOT/scripts/home-net-update"
echo 'PASS Monitoring/LuCI use pinned archive; only rollout policy remains mutable'
