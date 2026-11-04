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
    -o) [ ! -e "$2" ] && printf 'private fixture %s\n' "${TEST_GENERATION:-0}" >"$2" ;;
    -y)
        case "$(cat "$2")" in
            'private fixture 0') printf 'age1%058d\n' 0 ;;
            'private fixture 2') printf 'age1%058d\n' 2 ;;
            *) exit 1 ;;
        esac
        ;;
    *) exit 1 ;;
esac
EOF
printf '%s\n' '#!/bin/sh' 'exit 1' >"$tmp/bin/age"
chmod +x "$tmp/bin/age-keygen" "$tmp/bin/age"
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
recipient="$TEST_HOME_NET/keys/age-recipient.txt"
chmod 0644 "$key"
sh "$tmp/identity" status | grep -qx "IDENTITY_STATUS='ERROR'"
sh "$tmp/identity" initialize
rm "$recipient"
sh "$tmp/identity" status | grep -qx "IDENTITY_STATUS='ERROR'"
sh "$tmp/identity" initialize
printf '%s\n' mismatch >"$recipient"
sh "$tmp/identity" status | grep -qx "IDENTITY_STATUS='ERROR'"
sh "$tmp/identity" initialize
mv "$key" "$tmp/saved"
ln -s "$tmp/saved" "$key"
if sh "$tmp/identity" initialize; then exit 1; fi
sh "$tmp/identity" status | grep -qx "IDENTITY_STATUS='ERROR'"
rm "$key"
printf '%s\n' corrupt >"$key"
if sh "$tmp/identity" initialize; then exit 1; fi
grep -qx corrupt "$key"
rm "$key"
sh "$tmp/identity" initialize &
first=$!
sh "$tmp/identity" initialize &
second=$!
wait "$first"
wait "$second"
sh "$tmp/identity" status | grep -qx "IDENTITY_STATUS='READY'"
set -- "$TEST_HOME_NET/keys"/.identity.*
[ ! -e "$1" ]
if sh "$tmp/identity" regenerate; then exit 1; fi
old=$(sha256sum "$key")
old_public=$(cat "$recipient")
if sh "$tmp/identity" rotation-promote; then exit 1; fi
candidate=$(TEST_GENERATION=2 sh "$tmp/identity" rotation-stage)
[ "$candidate" != "$old_public" ]
[ "$(sha256sum "$key")" = "$old" ]
sh "$tmp/identity" rotation-promote
[ "$(cat "$recipient")" = "$candidate" ]
[ "$(sha256sum "$key")" != "$old" ]
sh "$tmp/identity" rotation-rollback
[ "$(sha256sum "$key")" = "$old" ]
[ "$(cat "$recipient")" = "$old_public" ]
printf '%s\n' 'VPN identity regression passed'
