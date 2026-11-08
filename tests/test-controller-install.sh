#!/bin/sh
set -eu
ROOT="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT
export FIXTURE="$TMP/root" PAYLOAD_ROOT="$ROOT"
mkdir -p "$FIXTURE/etc/home-net/vpn/transaction" "$FIXTURE/usr/bin" "$TMP/bin"
printf 'verified\n' > "$FIXTURE/etc/home-net/vpn/transaction/phase"
printf 'transaction baseline\n' > "$FIXTURE/etc/home-net/vpn/transaction/metadata"
printf 'unchanged network\n' > "$TMP/network"
printf "INSTALLED_VERSION='1.5.0'\n" > "$FIXTURE/etc/podkop-awg-failover.conf"
python3 - "$ROOT/control-agent/install-three-slots.sh" "$TMP/install" "$FIXTURE" "$TMP/maintenance" <<'PY'
import sys
from pathlib import Path
s=Path(sys.argv[1]).read_text()
for name in ('/etc/home-net','/usr/bin','/etc/podkop-awg-failover.conf'):
 s=s.replace(name,sys.argv[3]+name)
s=s.replace('/var/run/home-net-vpn-maintenance.lock',sys.argv[4])
Path(sys.argv[2]).write_text(s)
PY
cat > "$TMP/bin/id" <<'MOCK'
#!/bin/sh
echo 0
MOCK
cat > "$TMP/bin/wget" <<'MOCK'
#!/bin/sh
while [ "$#" -gt 0 ]; do
 case "$1" in -O) out=$2;shift 2;; -T) shift 2;; -q) shift;; *) url=$1;shift;; esac
done
case "$url" in https://raw.githubusercontent.com/kumshi1978/home-net-cudy/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/scripts/*) ;; *) exit 9;; esac
cp "$PAYLOAD_ROOT/scripts/${url##*/}" "$out"
MOCK
chmod +x "$TMP/bin/"*
run() { PATH="$TMP/bin:$PATH" HOME_NET_CONTROL_REF=aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa sh "$TMP/install"; }
run > "$TMP/output"
test -x "$FIXTURE/usr/bin/home-net-vpn-persist.py"
cmp "$ROOT/scripts/home-net-vpn-router" "$FIXTURE/usr/bin/home-net-vpn-router"
printf 'verified\n' | cmp - "$FIXTURE/etc/home-net/vpn/transaction/phase"
printf 'transaction baseline\n' | cmp - "$FIXTURE/etc/home-net/vpn/transaction/metadata"
printf 'unchanged network\n' | cmp - "$TMP/network"
grep -Fxq 1.5.0 "$FIXTURE/etc/home-net/vpn/failover-lock-version"
run > "$TMP/retry"
printf 'custom adapter\n' > "$FIXTURE/etc/home-net/vpn/adapter"
if run > "$TMP/rejected" 2>&1; then echo 'custom adapter must be preserved' >&2;exit 1;fi
printf 'custom adapter\n' | cmp - "$FIXTURE/etc/home-net/vpn/adapter"
grep -Fq 'custom adapter preserved' "$TMP/rejected"
echo 'PASS controller package integrity, upgrade fencing, repeat and private rollback record'
