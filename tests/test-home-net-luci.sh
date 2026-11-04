#!/bin/sh
set -eu

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"

sh -n "$ROOT/scripts/home-net-status"
sh -n "$ROOT/scripts/home-net-control"
sh -n "$ROOT/install/install.sh"

grep -Fq '/usr/bin/home-net-status' "$ROOT/luci/acl.d/luci-app-home-net.json"
grep -Fq '/usr/bin/home-net-control' "$ROOT/luci/acl.d/luci-app-home-net.json"
grep -Fq '"admin/services/home-net"' "$ROOT/luci/menu.d/luci-app-home-net.json"
grep -Fq "switch-main" "$ROOT/scripts/home-net-control"
grep -Fq "switch-backup" "$ROOT/scripts/home-net-control"
grep -Fq "Roll out ring" "$ROOT/luci/home-net/common.js"
grep -Fq "Release rollout" "$ROOT/luci/home-net/common.js"
grep -Fq "AUTO_APPLY_STATE" "$ROOT/scripts/home-net-status"

if grep -Eq '(^|[[:space:]])(reboot|shutdown)([[:space:]]|$)|/etc/init\.d/network[[:space:]]+(restart|reload)' "$ROOT/scripts/home-net-control"; then
    echo "forbidden disruptive control found" >&2
    exit 1
fi

echo "HOME NET LuCI static tests: PASS"

node "$ROOT/tests/test-luci-management.cjs"


# Exercise the rpcd upload boundary independently from LuCI rendering.
RPC_TMP="$(mktemp -d)"
trap 'rm -rf "$RPC_TMP"' EXIT HUP INT TERM
mkdir "$RPC_TMP/bin"
cat >"$RPC_TMP/bin/jsonfilter" <<'EOF'
#!/bin/sh
file=
expr=
while [ "$#" -gt 0 ]; do
    case "$1" in
        -i) file="$2"; shift 2 ;;
        -e) expr="$2"; shift 2 ;;
        *) shift ;;
    esac
done
node - "$file" "$expr" <<'NODE'
const fs=require('fs');
const [file,expr]=process.argv.slice(2);
const data=JSON.parse(fs.readFileSync(file,'utf8'));
const key=expr.replace(/^@\./,'');
if (!(key in data) || typeof data[key] !== 'string') process.exit(1);
process.stdout.write(data[key]);
NODE
EOF
cat >"$RPC_TMP/router" <<'EOF'
#!/bin/sh
[ "$1" = prepare-upload ] || exit 91
[ "$2" = candidate-1 ] || exit 92
[ "$3" = DE ] || exit 93
IFS= read -r header
[ "$header" = age-encryption.org/v1 ] || exit 94
cat >/dev/null
EOF
chmod 0755 "$RPC_TMP/bin/jsonfilter" "$RPC_TMP/router"
sed -e "s@/usr/bin/home-net-vpn-router@$RPC_TMP/router@g" \
    -e "s@/tmp/home-net-vpn-rpc\.@$RPC_TMP/rpc.@g" \
    "$ROOT/luci/rpcd/home-net-vpn" >"$RPC_TMP/rpcd"
chmod 0755 "$RPC_TMP/rpcd"
PATH="$RPC_TMP/bin:$PATH"
export PATH
"$RPC_TMP/rpcd" list >"$RPC_TMP/list"
grep -Fq '"prepare"' "$RPC_TMP/list"
if grep -Fqi 'filename' "$RPC_TMP/list"; then exit 1; fi
cipher="$(printf 'age-encryption.org/v1\nfixture\n' | base64 -w0)"
printf '{"deployment":"candidate-1","country":"DE","ciphertext":"%s"}' "$cipher" |
    "$RPC_TMP/rpcd" call prepare | grep -Fqx '{"status":"prepared"}'
printf '{"deployment":"../bad","country":"DE","ciphertext":"%s"}' "$cipher" |
    "$RPC_TMP/rpcd" call prepare | grep -Fqx '{"status":"invalid"}'
printf '{"deployment":"candidate-1","country":"DE","ciphertext":"%%%"}' |
    "$RPC_TMP/rpcd" call prepare | grep -Fqx '{"status":"invalid"}'
oversize="$(head -c 65537 /dev/zero | base64 -w0)"
printf '{"deployment":"candidate-1","country":"DE","ciphertext":"%s"}' "$oversize" |
    "$RPC_TMP/rpcd" call prepare | grep -Fqx '{"status":"invalid"}'
echo 'PASS secure VPN rpcd upload wrapper'
