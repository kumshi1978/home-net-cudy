#!/bin/sh
set -eu
ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
directory="$ROOT/native-agent/dist/native-agent-arm64"
mkdir -p "$directory"
cd "$ROOT/native-agent"
commit=$(git rev-parse HEAD)
CGO_ENABLED=0 GOOS=linux GOARCH=arm64 go build -trimpath -tags netgo,osusergo -ldflags "-s -w -buildid= -X main.version=0.1.0-rc1+$commit" -o "$directory/vpn-control-cudy" .
sed -e 's@home-net-vpn-persist.py@home-net-vpn-persist@g' \
    -e 's@age -d -i /etc/home-net/keys/age-identity.txt -o "$tmp/client.conf" "$tmp/$router.conf.age"@/usr/sbin/vpn-control-cudy decrypt "$tmp/$router.conf.age" "$tmp/client.conf"@' \
    "$ROOT/scripts/home-net-vpn-router" >"$directory/home-net-vpn-router"
sed 's@home-net-vpn-persist.py@home-net-vpn-persist@g' "$ROOT/scripts/home-net-vpn-cudy-adapter" >"$directory/home-net-vpn-cudy-adapter"
cp "$ROOT/scripts/home-net-vpn-manifest-validate" "$directory/"
cp "$ROOT/native-agent/home-net-vpn-persist" "$ROOT/native-agent/vpn-control-cudy.init" "$ROOT/native-agent/install.sh" "$directory/"
for name in home-net-vpn-router home-net-vpn-cudy-adapter home-net-vpn-manifest-validate home-net-vpn-persist vpn-control-cudy.init install.sh; do
    sh -n "$directory/$name"
    chmod 0700 "$directory/$name"
done
if grep -nE 'python3|home-net-vpn-persist\.py|(^|[[:space:]])age -d' "$directory/home-net-vpn-router" "$directory/home-net-vpn-cudy-adapter" "$directory/home-net-vpn-persist"; then
    echo 'ERROR: legacy runtime dependency remains' >&2; exit 1
fi
chmod 0700 "$directory/vpn-control-cudy"
cd "$directory"
sha256sum vpn-control-cudy home-net-vpn-router home-net-vpn-cudy-adapter home-net-vpn-manifest-validate home-net-vpn-persist vpn-control-cudy.init install.sh >SHA256SUMS
wc -c vpn-control-cudy
file vpn-control-cudy
printf '%s\n' "version=0.1.0-rc1" "source_commit=$commit" 'architecture=linux-arm64' >BUILD-INFO
cd ..
tar -czf home-net-native-agent-0.1.0-rc1-linux-arm64.tar.gz native-agent-arm64
sha256sum home-net-native-agent-0.1.0-rc1-linux-arm64.tar.gz >home-net-native-agent-0.1.0-rc1-linux-arm64.tar.gz.sha256
