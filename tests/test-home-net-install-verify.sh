#!/bin/sh
set -eu
REPO="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
export HOME_NET_VERIFY_ROOT="$TMP/root"
export HOME_NET_VERIFY_HEALTH="$TMP/root/tmp/podkop-service-health/state"
mkdir -p "$TMP/root/etc/init.d" "$TMP/root/usr/bin" "$TMP/root/tmp/podkop-service-health" "$TMP/root/www/luci-static/resources/view/home-net" "$TMP/root/www/luci-static/resources/home-net"
mkdir -p "$TMP/bin" "$TMP/root/etc/sing-box" "$TMP/root/etc/config"
export PATH="$TMP/bin:$PATH"
cat > "$TMP/bin/uci" <<'EOF'
#!/bin/sh
echo /etc/sing-box/config.json
EOF
cat > "$TMP/bin/nft" <<'EOF'
#!/bin/sh
[ -f "$HOME_NET_VERIFY_ROOT/nft" ]
EOF
cat > "$TMP/bin/ip" <<'EOF'
#!/bin/sh
[ -f "$HOME_NET_VERIFY_ROOT/routing" ] || exit 1
case "$*" in *rule*) echo '105: from all fwmark 0x100000/0x100000 lookup podkop' ;; *route*) echo 'local default dev lo scope host' ;; *) exit 1 ;; esac
EOF
chmod +x "$TMP/bin/"*
printf '{}' > "$TMP/root/etc/sing-box/config.json"
# Real installer execution is redirected into a private filesystem fixture.
sed -e "s|/etc/|@FIXTURE@/etc/|g" -e "s|/usr/|@FIXTURE@/usr/|g" -e "s|/www/|@FIXTURE@/www/|g" -e "s|/root/|@FIXTURE@/root/|g" -e "s|/tmp/|@FIXTURE@/tmp/|g" -e "s|@FIXTURE@|$TMP/root|g" "$REPO/install/install.sh" > "$TMP/install.fixture"
# Source lookup must still use the checked-out repository, not the temporary fixture.
sed "s|^BASE_DIR=.*|BASE_DIR='$REPO/install'|" "$TMP/install.fixture" > "$TMP/install"
touch "$TMP/root/etc/openwrt_release" "$TMP/root/sing-box.running" "$TMP/root/nft" "$TMP/root/routing"
stamp=$(date -d "@$(($(date +%s)-10))" '+%F %T')
printf 'STATUS=OK\nPODKOP=RUNNING\nSING_BOX=RUNNING\nFAKEIP=OK\nSERVICE_CHECK=OK\nLAST_CHECK=%s\n' "$stamp" > "$HOME_NET_VERIFY_HEALTH"
for service in podkop sing-box podkop-service-health home-net-log rpcd; do
cat > "$TMP/root/etc/init.d/$service" <<'INIT'
#!/bin/sh
name=${0##*/}
echo "$name $1" >> "$HOME_NET_VERIFY_ROOT/calls"
case "$1" in
 running|status) [ -f "$HOME_NET_VERIFY_ROOT/$name.running" ] ;;
 start|restart)
  touch "$HOME_NET_VERIFY_ROOT/$name.running"
  if [ "$name" = podkop-service-health ]; then
   stamp=$(date -d "@$(($(date +%s)-2))" '+%F %T')
   sed "s/LAST_CHECK=.*/LAST_CHECK=$stamp/" "$HOME_NET_VERIFY_HEALTH" > "$HOME_NET_VERIFY_HEALTH.new"
   mv "$HOME_NET_VERIFY_HEALTH.new" "$HOME_NET_VERIFY_HEALTH"
   [ "${DROP_PODKOP:-0}" != 1 ] || rm -f "$HOME_NET_VERIFY_ROOT/podkop.running"
  fi ;;
 enable) exit 0 ;;
 *) exit 1 ;;
esac
INIT
chmod 755 "$TMP/root/etc/init.d/$service"
done
# Candidate Monitoring init files invoke our private rc.common mock instead of host services.
mkdir "$TMP/src"
cp -R "$REPO/install" "$REPO/scripts" "$REPO/configs" "$REPO/luci" "$REPO/init.d" "$TMP/src/"
for service in podkop-service-health home-net-log; do cp "$TMP/root/etc/init.d/$service" "$TMP/src/init.d/$service"; done
sed "s|^BASE_DIR=.*|BASE_DIR='$TMP/src/install'|" "$TMP/install" > "$TMP/install.ready"
(umask 077; sh "$TMP/install.ready") > "$TMP/output"
sh "$REPO/scripts/home-net-install-verify" all
[ "$(stat -c '%a' "$TMP/root/www/luci-static/resources/view/home-net/status.js")" = 644 ]
if grep -Eq '^(podkop|sing-box) (start|stop|restart)$' "$TMP/root/calls"; then exit 1; fi
[ ! -e "$TMP/root/podkop.running" ]
echo 'PASS actual installer under umask 077; one-shot Podkop accepted without service control'
chmod 600 "$TMP/root/www/luci-static/resources/view/home-net/status.js"
if sh "$REPO/scripts/home-net-install-verify" luci; then exit 1; fi
chmod 644 "$TMP/root/www/luci-static/resources/view/home-net/status.js"
rm "$TMP/root/www/luci-static/resources/view/home-net/vpn.js"
if sh "$REPO/scripts/home-net-install-verify" luci; then exit 1; fi
for missing in sing-box.running nft routing; do
 rm "$TMP/root/$missing"
 if sh "$REPO/scripts/home-net-install-verify" lifecycle; then exit 1; fi
 touch "$TMP/root/$missing"
 echo "PASS lifecycle independently rejects missing $missing"
done
mv "$TMP/root/etc/sing-box/config.json" "$TMP/config.saved"
if sh "$REPO/scripts/home-net-install-verify" lifecycle; then exit 1; fi
mv "$TMP/config.saved" "$TMP/root/etc/sing-box/config.json"
cp "$HOME_NET_VERIFY_HEALTH" "$TMP/health.saved"
sed 's/FAKEIP=OK/FAKEIP=FAIL/' "$TMP/health.saved" > "$HOME_NET_VERIFY_HEALTH"
if sh "$REPO/scripts/home-net-install-verify" lifecycle; then exit 1; fi
sed 's/LAST_CHECK=.*/LAST_CHECK=2000-01-01 00:00:00/' "$TMP/health.saved" > "$HOME_NET_VERIFY_HEALTH"
if sh "$REPO/scripts/home-net-install-verify" lifecycle; then exit 1; fi
cp "$TMP/health.saved" "$HOME_NET_VERIFY_HEALTH"
# Healthy cached monitoring alone cannot allow installation with a dead proxy.
rm "$TMP/root/sing-box.running"
before=$(sha256sum "$TMP/root/usr/bin/home-net-status")
if sh "$TMP/install.ready" > "$TMP/stopped-output" 2>&1; then exit 1; fi
[ "$before" = "$(sha256sum "$TMP/root/usr/bin/home-net-status")" ]
echo 'PASS missing/0600 LuCI, FakeIP/stale health and dead proxy fail closed'
