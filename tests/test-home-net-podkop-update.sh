#!/bin/sh
set -eu
ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT HUP INT TERM
mkdir -p "$TMP/bin" "$TMP/router/etc/config" "$TMP/router/etc/sing-box" "$TMP/backups"
export MOCK_ROOT="$TMP" HOME_NET_PODKOP_ROOT="$TMP/router" HOME_NET_MANAGEMENT_BACKUPS="$TMP/backups" HOME_NET_UPDATE_LOCK_DIR="$TMP/lock" HOME_NET_UPDATE_HEALTH_STATE="$TMP/health" HOME_NET_PODKOP_INIT="$TMP/bin/service"
export PATH="$TMP/bin:$PATH"
cat > "$TMP/bin/podkop" <<'EOF'
#!/bin/sh
cat "$MOCK_ROOT/current"
EOF
cat > "$TMP/bin/service" <<'EOF'
#!/bin/sh
printf 'STATUS=%s\nPODKOP=RUNNING\nSING_BOX=RUNNING\nFAKEIP=OK\nSERVICE_CHECK=OK\nLAST_CHECK=after\n' "${MOCK_HEALTH:-OK}" > "$MOCK_ROOT/health"
EOF
cat > "$TMP/bin/sleep" <<'EOF'
#!/bin/sh
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
 *0.7.22*) printf 0.7.22 > "$MOCK_ROOT/current"; echo rollback >> "$MOCK_ROOT/mutations" ;;
 *) echo install >> "$MOCK_ROOT/mutations"; printf 0.7.24 > "$MOCK_ROOT/current"; [ "${MOCK_FAIL:-0}" = 0 ] || exit 1; [ "${MOCK_CHANGE_NETWORK:-0}" = 0 ] || printf changed > "$MOCK_ROOT/router/etc/config/network" ;;
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
 printf 'STATUS=OK\nPODKOP=RUNNING\nSING_BOX=RUNNING\nFAKEIP=OK\nSERVICE_CHECK=OK\nLAST_CHECK=before\n' > "$TMP/health"
 rm -f "$TMP/mutations"
}
reset
sh "$ROOT/scripts/home-net-podkop-update" update 0.7.24
[ "$(cat "$TMP/current")" = 0.7.24 ]
[ "$(cat "$TMP/router/etc/config/network")" = protected ]
[ ! -d "$TMP/lock" ]
echo 'PASS Podkop exact asset checksums, backup, install, fresh health and protected config'
for failure in dependency install network health target lock; do
 reset
 case "$failure" in
 dependency) export MOCK_DEPENDENCY=1 ;;
 install) export MOCK_FAIL=1 ;;
 network) export MOCK_CHANGE_NETWORK=1 ;;
 health) export MOCK_HEALTH=FAIL ;;
 lock) mkdir "$TMP/lock"; printf '%s\n' "$$" > "$TMP/lock/pid" ;;
 esac
 target=0.7.24; [ "$failure" != target ] || target=0.7.25
 if sh "$ROOT/scripts/home-net-podkop-update" update "$target" > "$TMP/result" 2>&1; then cat "$TMP/result"; exit 1; fi
 [ "$(cat "$TMP/current")" = 0.7.22 ]
 [ "$(cat "$TMP/router/etc/config/network")" = protected ]
 case "$failure" in install|network|health) grep -q rollback "$TMP/mutations" ;; *) [ ! -e "$TMP/mutations" ] ;; esac
 unset MOCK_DEPENDENCY MOCK_FAIL MOCK_CHANGE_NETWORK MOCK_HEALTH
 [ "$failure" != lock ] || { rm "$TMP/lock/pid"; rmdir "$TMP/lock"; }
 echo "PASS Podkop fail-closed/rollback $failure"
done
