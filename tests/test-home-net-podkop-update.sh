#!/bin/sh
set -eu
ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT HUP INT TERM
mkdir -p "$TMP/bin" "$TMP/router/etc/config" "$TMP/router/etc/sing-box" "$TMP/router/etc/init.d" "$TMP/router/tmp/sing-box" "$TMP/router/tmp/podkop" "$TMP/backups"
export MOCK_ROOT="$TMP" HOME_NET_PODKOP_ROOT="$TMP/router" HOME_NET_MANAGEMENT_BACKUPS="$TMP/backups" HOME_NET_UPDATE_LOCK_DIR="$TMP/lock" HOME_NET_UPDATE_HEALTH_STATE="$TMP/health" HOME_NET_PODKOP_INIT="$TMP/bin/service"
export PATH="$TMP/bin:$PATH"
export HOME_NET_PODKOP_VERIFIER="$ROOT/scripts/home-net-install-verify"
cat > "$TMP/bin/uci" <<'EOF'
#!/bin/sh
echo /etc/sing-box/config.json
EOF
cat > "$TMP/bin/nft" <<'EOF'
#!/bin/sh
[ -f "$MOCK_ROOT/nft" ]
EOF
cat > "$TMP/bin/ip" <<'EOF'
#!/bin/sh
[ -f "$MOCK_ROOT/routing" ] || exit 1
case "$*" in *rule*) echo '105: from all fwmark 0x100000/0x100000 lookup podkop' ;; *route*) echo 'local default dev lo scope host' ;; *) exit 1 ;; esac
EOF
cat > "$TMP/router/etc/init.d/sing-box" <<'EOF'
#!/bin/sh
case "$1" in running|status) [ -f "$MOCK_ROOT/sing-box.running" ] ;; *) exit 1 ;; esac
EOF
chmod +x "$TMP/router/etc/init.d/sing-box"
cat > "$TMP/bin/podkop" <<'EOF'
#!/bin/sh
cat "$MOCK_ROOT/current"
EOF
cat > "$TMP/bin/service" <<'EOF'
#!/bin/sh
case "$1" in
 stop) rm -f "$MOCK_ROOT/sing-box.running"; exit 0 ;;
 restart) ;;
 running|status) exit 1 ;; # Podkop initialization is one-shot.
 *) exit 1 ;;
esac
touch "$MOCK_ROOT/sing-box.running" "$MOCK_ROOT/nft" "$MOCK_ROOT/routing"
status=OK fakeip=OK offset=2
if [ "$(cat "$MOCK_ROOT/current")" = 0.7.24 ]; then
 status=${MOCK_HEALTH:-OK}; fakeip=${MOCK_FAKEIP:-OK}; offset=4
 [ "${MOCK_NO_SING_BOX:-0}" = 0 ] || rm -f "$MOCK_ROOT/sing-box.running"
 [ "${MOCK_NO_CONFIG:-0}" = 0 ] || rm -f "$MOCK_ROOT/router/etc/sing-box/config.json"
else
 status=${MOCK_ROLLBACK_HEALTH:-OK}
fi
stamp=$(date -d "@$(($(date +%s)-offset))" '+%F %T')
printf 'STATUS=%s\nPODKOP=RUNNING\nSING_BOX=RUNNING\nFAKEIP=%s\nSERVICE_CHECK=OK\nLAST_CHECK=%s\n' "$status" "$fakeip" "$stamp" > "$MOCK_ROOT/health"
EOF
cat > "$TMP/bin/sleep" <<'EOF'
#!/bin/sh
# Simulate the next independent monitor cycle, preserving failures/status.
stamp=$(date -d "@$(($(date +%s)-1))" '+%F %T')
sed "s/LAST_CHECK=.*/LAST_CHECK=$stamp/" "$MOCK_ROOT/health" > "$MOCK_ROOT/health.new"
mv "$MOCK_ROOT/health.new" "$MOCK_ROOT/health"
exit 0
EOF
cat > "$TMP/bin/curl" <<'EOF'
#!/bin/sh
url='' out=''
while [ "$#" -gt 0 ]; do
 case "$1" in -o) out="$2"; shift 2 ;; --proto|--connect-timeout|--max-time) shift 2 ;; -*) shift ;; *) url="$1"; shift ;; esac
done
case "$url" in
 */releases/latest) cp "$MOCK_ROOT/latest.json" "$out" ;;
 */releases/tags/0.7.22) cp "$MOCK_ROOT/old.json" "$out" ;;
 */releases/download/0.7.22/*) printf old > "$out" ;;
 */releases/download/0.7.24/*) printf new > "$out" ;;
 *) exit 99 ;;
esac
EOF
cat > "$TMP/bin/opkg" <<'EOF'
#!/bin/sh
case "$*" in
 *--noaction*) echo 'Upgrading podkop on root'; echo 'Upgrading luci-app-podkop on root'; [ "${MOCK_DEPENDENCY:-0}" = 0 ] || echo 'Upgrading sing-box on root'; exit 0 ;;
 *0.7.22*)
  if [ "$(cat "$MOCK_ROOT/current")" = 0.7.24 ]; then
   case "$*" in *--force-downgrade*) ;; *) echo 'downgrade refused' >&2; exit 1 ;; esac
  fi
  printf 0.7.22 > "$MOCK_ROOT/current"; echo rollback >> "$MOCK_ROOT/mutations" ;;
 *)
  echo install >> "$MOCK_ROOT/mutations"; printf 0.7.24 > "$MOCK_ROOT/current"
  printf changed > "$MOCK_ROOT/router/etc/sing-box/config.json"
  printf added > "$MOCK_ROOT/router/etc/sing-box/added.json"
  printf changed > "$MOCK_ROOT/router/tmp/sing-box/cache.db"
  printf added > "$MOCK_ROOT/router/tmp/sing-box/new.cache"
  printf changed > "$MOCK_ROOT/router/tmp/podkop/state"
  printf changed > "$MOCK_ROOT/router/etc/config/dhcp"
  printf added > "$MOCK_ROOT/router/etc/config/sing-box"
  [ "${MOCK_FAIL:-0}" = 0 ] || exit 1
  [ "${MOCK_CHANGE_NETWORK:-0}" = 0 ] || printf changed > "$MOCK_ROOT/router/etc/config/network" ;;
esac
EOF
cat > "$TMP/jsonfilter.cjs" <<'EOF'
const fs=require('fs');const args=process.argv.slice(2),data=JSON.parse(fs.readFileSync(args[args.indexOf('-i')+1],'utf8')),query=args[args.indexOf('-e')+1];
if(query==='@.assets[*].name') console.log(data.assets.map(x=>x.name).join('\n'));
else if(query.startsWith('@.assets[')){const m=query.match(/name='([^']+)'\]\.([a-z_]+)/);const asset=data.assets.find(x=>x.name===m[1]);if(asset)console.log(asset[m[2]]);}
else console.log(data[query.slice(2)]);
EOF
cat > "$TMP/bin/jsonfilter" <<'EOF'
#!/bin/sh
node "$MOCK_ROOT/jsonfilter.cjs" "$@"
EOF
chmod +x "$TMP/bin/"*
node - "$TMP" <<'EOF'
const fs=require('fs'),crypto=require('crypto'),root=process.argv[2];
for(const [tag,contents,file] of [['0.7.22','old','old'],['0.7.24','new','latest']]){
 const digest='sha256:'+crypto.createHash('sha256').update(contents).digest('hex');
 fs.writeFileSync(root+'/'+file+'.json',JSON.stringify({tag_name:tag,draft:false,prerelease:false,assets:['podkop','luci-app-podkop'].map(p=>({name:p+'-v'+tag+'-r1-all.ipk',digest,browser_download_url:'https://github.com/itdoginfo/podkop/releases/download/'+tag+'/'+p+'-v'+tag+'-r1-all.ipk'}))}));
}
EOF
reset() {
 printf 0.7.22 > "$TMP/current"
 printf protected > "$TMP/router/etc/config/network"
 printf routing > "$TMP/router/etc/config/podkop"
 printf config > "$TMP/router/etc/sing-box/config.json"
 printf cache > "$TMP/router/tmp/sing-box/cache.db"
 printf runtime > "$TMP/router/tmp/podkop/state"
 printf dhcp > "$TMP/router/etc/config/dhcp"
 touch "$TMP/sing-box.running" "$TMP/nft" "$TMP/routing"
 stamp=$(date -d "@$(($(date +%s)-10))" '+%F %T')
 printf 'STATUS=OK\nPODKOP=RUNNING\nSING_BOX=RUNNING\nFAKEIP=OK\nSERVICE_CHECK=OK\nLAST_CHECK=%s\n' "$stamp" > "$TMP/health"
 rm -f "$TMP/router/etc/sing-box/added.json" "$TMP/router/tmp/sing-box/new.cache" "$TMP/router/etc/config/sing-box"
 rm -f "$TMP/mutations"
}
reset
sh "$ROOT/scripts/home-net-podkop-update" update 0.7.24
[ "$(cat "$TMP/current")" = 0.7.24 ]
[ "$(cat "$TMP/router/etc/config/network")" = protected ]
[ ! -d "$TMP/lock" ]
echo 'PASS Podkop exact asset checksums, backup, install, fresh health and protected config'
# The mock must reject ordinary installation of an older version.
if opkg install podkop-v0.7.22-r1-all.ipk >/dev/null 2>&1; then exit 1; fi
[ "$(cat "$TMP/current")" = 0.7.24 ]
echo 'PASS ordinary opkg install cannot perform rollback downgrade'
for failure in dependency install network health fakeip singbox config target lock; do
 reset
 case "$failure" in
 dependency) export MOCK_DEPENDENCY=1 ;;
 install) export MOCK_FAIL=1 ;;
 network) export MOCK_CHANGE_NETWORK=1 ;;
 health) export MOCK_HEALTH=FAIL ;;
 fakeip) export MOCK_FAKEIP=FAIL ;;
 singbox) export MOCK_NO_SING_BOX=1 ;;
 config) export MOCK_NO_CONFIG=1 ;;
 lock) mkdir "$TMP/lock"; printf '%s\n' "$$" > "$TMP/lock/pid" ;;
 esac
 target=0.7.24; [ "$failure" != target ] || target=0.7.25
 if sh "$ROOT/scripts/home-net-podkop-update" update "$target" > "$TMP/result" 2>&1; then cat "$TMP/result"; exit 1; fi
 [ "$(cat "$TMP/current")" = 0.7.22 ]
 [ "$(cat "$TMP/router/etc/config/network")" = protected ]
 case "$failure" in install|network|health|fakeip|singbox|config)
  grep -q rollback "$TMP/mutations"
  grep -q 'ROLLBACK VERIFIED' "$TMP/result"
  [ "$(cat "$TMP/router/etc/sing-box/config.json")" = config ]
  [ "$(cat "$TMP/router/tmp/sing-box/cache.db")" = cache ]
  [ "$(cat "$TMP/router/tmp/podkop/state")" = runtime ]
  [ "$(cat "$TMP/router/etc/config/dhcp")" = dhcp ]
  [ ! -e "$TMP/router/etc/config/sing-box" ]
  [ ! -e "$TMP/router/etc/sing-box/added.json" ]
  [ ! -e "$TMP/router/tmp/sing-box/new.cache" ]
  HOME_NET_VERIFY_ROOT="$TMP/router" HOME_NET_VERIFY_HEALTH="$TMP/health" sh "$ROOT/scripts/home-net-install-verify" lifecycle
  ;; *) [ ! -e "$TMP/mutations" ] ;; esac
 unset MOCK_DEPENDENCY MOCK_FAIL MOCK_CHANGE_NETWORK MOCK_HEALTH MOCK_FAKEIP MOCK_NO_SING_BOX MOCK_NO_CONFIG
 [ "$failure" != lock ] || { rm "$TMP/lock/pid"; rmdir "$TMP/lock"; }
 echo "PASS Podkop fail-closed/rollback $failure"
done
reset
export MOCK_FAIL=1 MOCK_ROLLBACK_HEALTH=FAIL
if sh "$ROOT/scripts/home-net-podkop-update" update 0.7.24 > "$TMP/result" 2>&1; then exit 1; fi
grep -q 'ROLLBACK FAILED' "$TMP/result"
! grep -q 'ROLLBACK VERIFIED' "$TMP/result"
[ "$(cat "$TMP/current")" = 0.7.22 ]
[ "$(grep -c '^rollback$' "$TMP/mutations")" = 1 ]
[ ! -d "$TMP/lock" ]
echo 'PASS unhealthy rollback is reported as failure, not restoration success'
