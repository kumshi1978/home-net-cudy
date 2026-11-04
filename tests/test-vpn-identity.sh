#!/bin/sh
set -eu
root=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
mkdir "$tmp/bin"
export TEST_HOME_NET="$tmp/home-net"
sed 's@/etc/home-net@$TEST_HOME_NET@g; /id -u/d' \
    "$root/scripts/home-net-vpn-identity" >"$tmp/identity"
cat >"$tmp/bin/age-keygen" <<'EOF'
#!/bin/sh
case "$1" in
    -o) [ ! -e "$2" ] && printf '%s\n' 'private fixture' >"$2" ;;
    -y) grep -qx 'private fixture' "$2" && printf 'age1%058d\n' 0 ;;
    *) exit 1 ;;
esac
EOF
chmod +x "$tmp/bin/age-keygen"
PATH="$tmp/bin:$PATH"
export PATH
sh "$tmp/identity" status | grep -q "IDENTITY_STATUS='NOT INITIALIZED'"
sh "$tmp/identity" initialize
key="$TEST_HOME_NET/keys/age-identity.txt"
before=$(ls -i "$key")
sh "$tmp/identity" initialize
[ "$(ls -i "$key")" = "$before" ]
[ "$(ls -ld "$TEST_HOME_NET/keys" | cut -c 1-10)" = drwx------ ]
[ "$(ls -l "$key" | cut -c 1-10)" = -rw------- ]
status=$(sh "$tmp/identity" status)
printf '%s\n' "$status" | grep -qx "IDENTITY_STATUS='READY'"
printf '%s\n' "$status" | grep -q "^PUBLIC_RECIPIENT='age1"
case "$status" in *'private fixture'*) exit 1 ;; esac
if sh "$tmp/identity" regenerate; then exit 1; fi
printf '%s\n' 'VPN identity regression passed'
