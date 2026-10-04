#!/bin/sh
set -eu

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
INSTALLER="$ROOT/install-all.sh"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT HUP INT TERM

BIN="$TMP/bin"
PAYLOADS="$TMP/payloads"
TARGET="$TMP/target"
mkdir -p "$BIN" "$PAYLOADS" "$TARGET/init.d" "$TARGET/backups"

cat > "$BIN/wget" <<'EOF_WGET'
#!/bin/sh
out=''
url=''
while [ "$#" -gt 0 ]; do
    case "$1" in
        -O) out="$2"; shift 2 ;;
        -T) shift 2 ;;
        -q) shift ;;
        *) url="$1"; shift ;;
    esac
done
case "$url" in
    */bundle.conf) source_file="$MOCK_PAYLOADS/bundle.conf" ;;
    */install.sh) source_file="$MOCK_PAYLOADS/monitoring-install.sh" ;;
    */scripts/home-net-update) source_file="$MOCK_PAYLOADS/home-net-update" ;;
    */init.d/home-net-update) source_file="$MOCK_PAYLOADS/home-net-update.init" ;;
    */configs/home-net-update.conf.example) source_file="$MOCK_PAYLOADS/home-net-update.conf" ;;
    *) exit 1 ;;
esac
cp "$source_file" "$out"
EOF_WGET

cat > "$BIN/uci" <<'EOF_UCI'
#!/bin/sh
exit 0
EOF_UCI

cat > "$BIN/pgrep" <<'EOF_PGREP'
#!/bin/sh
exit 1
EOF_PGREP
chmod +x "$BIN/wget" "$BIN/uci" "$BIN/pgrep"

cat > "$PAYLOADS/bundle.conf" <<'EOF_BUNDLE'
HOME_NET_BUNDLE_VERSION='1.5.2'
FAILOVER_VERSION='1.4.1'
FAILOVER_REPO='kumshi1978/openwrt-podkop-awg-failover'
MONITORING_VERSION='1.4.2'
MONITORING_REPO='kumshi1978/home-net-cudy'
MONITORING_BOOTSTRAP_REF='test'
DEFAULT_AUTO_UPDATE_MODE='check'
UPDATE_ACTION_CLASS='SAFE'
UPDATE_PENDING_ACTION='none'
UPDATE_PENDING_REASON=''
EOF_BUNDLE

cat > "$PAYLOADS/monitoring-install.sh" <<'EOF_MONITORING'
#!/bin/sh
exit 0
EOF_MONITORING

cat > "$PAYLOADS/home-net-update" <<'EOF_UPDATER'
#!/bin/sh
echo new-updater
EOF_UPDATER

cat > "$PAYLOADS/home-net-update.init" <<'EOF_INIT'
#!/bin/sh
exit 0
EOF_INIT

printf "HOME_NET_UPDATE_MODE='check'\n" > "$PAYLOADS/home-net-update.conf"
printf "DISTRIB_ID='OpenWrt'\n" > "$TARGET/openwrt_release"
printf "INSTALLED_VERSION='1.4.1'\n" > "$TARGET/failover.conf"
cat > "$TARGET/home-net-update" <<'EOF_RUNNING'
#!/bin/sh
echo running-updater
EOF_RUNNING
cp "$TARGET/home-net-update" "$TARGET/original-updater"

run_installer() {
    set +e
    PATH="$BIN:$PATH" \
    MOCK_PAYLOADS="$PAYLOADS" \
    HOME_NET_BUNDLE_REF='test-ref' \
    HOME_NET_UPDATE_IN_PROGRESS='1' \
    HOME_NET_SKIP_VERSION_RECORD='1' \
    HOME_NET_OPENWRT_RELEASE="$TARGET/openwrt_release" \
    HOME_NET_FAILOVER_CONF="$TARGET/failover.conf" \
    HOME_NET_UPDATE_BIN="$TARGET/home-net-update" \
    HOME_NET_UPDATE_INIT="$TARGET/init.d/home-net-update" \
    HOME_NET_UPDATE_CONF="$TARGET/home-net-update.conf" \
    HOME_NET_UPDATE_STATE="$TARGET/home-net-update.state" \
    HOME_NET_UPDATER_BACKUP_ROOT="$TARGET/backups" \
    sh "$INSTALLER" > "$TMP/output" 2>&1
    RUN_RC=$?
    set -e
}

# The destination must remain untouched until the final same-filesystem rename.
# A cp wrapper rejects any attempt to copy directly onto the running updater path.
REAL_CP="$(command -v cp)"
cat > "$BIN/cp" <<EOF_CP
#!/bin/sh
last=''
for arg in "\$@"; do last="\$arg"; done
if [ "\$last" = '$TARGET/home-net-update' ]; then
    echo 'direct overwrite of running updater path' >&2
    exit 97
fi
exec '$REAL_CP' "\$@"
EOF_CP
chmod +x "$BIN/cp"

run_installer
[ "$RUN_RC" -eq 0 ] || { cat "$TMP/output" >&2; exit 1; }
grep -Fq 'new-updater' "$TARGET/home-net-update"
[ -x "$TARGET/home-net-update" ]
echo 'PASS atomic_self_update'

# The Monitoring installer is executable payload, so every guarded disruptive
# command form must be rejected before it or the updater installation runs.
for disruptive_action in \
    '/etc/init.d/network restart' \
    '/etc/init.d/network reload' \
    'service network restart' \
    'service network reload' \
    'reboot' \
    'ubus call system reboot' \
    'shutdown -r now'
do
    {
        printf '%s\n' '#!/bin/sh'
        printf '%s\n' "$disruptive_action"
    } > "$PAYLOADS/monitoring-install.sh"
    "$REAL_CP" "$TARGET/original-updater" "$TARGET/home-net-update"
    run_installer
    [ "$RUN_RC" -ne 0 ] || exit 1
    grep -Fq 'monitoring installer contains a forbidden network restart or reboot' "$TMP/output"
    cmp -s "$TARGET/original-updater" "$TARGET/home-net-update"
done
echo 'PASS monitoring_disruptive_action_scan'

echo 'All install-all safety tests passed.'
