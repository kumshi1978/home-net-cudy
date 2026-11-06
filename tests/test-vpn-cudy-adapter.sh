#!/bin/sh
set -eu
root=$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
export TEST="$tmp"
mkdir -p "$tmp/bin" "$tmp/init" "$tmp/transaction/backup"
sed 's@/etc/home-net/vpn@$TEST@g; s@/etc/init.d@$TEST/init@g; s@/etc/podkop-awg-failover.conf@$TEST/failover.conf@g; s@/var/run/home-net-vpn-maintenance.lock@$TEST/maintenance.lock@g' \
    "$root/scripts/home-net-vpn-cudy-adapter" >"$tmp/adapter"
cat >"$tmp/bin/mock" <<'EOF'
#!/bin/sh
set -eu
case "${0##*/}:$1" in
    ubus:call)
        if [ -e "$TEST/conflict" ]; then echo '{"podkop-awg-failover":{}}'; else echo '{}'; fi ;;
    uci:-q)
        case "$3" in *.interface) cat "$TEST/active" ;; *) echo vpn ;; esac ;;
    uci:set) printf '%s\n' "${2#*=}" >"$TEST/active" ;;
    awg:showconf) cat "$TEST/$2" ;;
    awg:syncconf) cp "$3" "$TEST/$2" ;;
    awg:show) printf 'fixture %s\n' "$(($(date +%s) - 1))" ;;
    curl:-q)
        case "$*" in *'if!awg_'* ) ;; *) exit 1 ;; esac
        case "$*" in *'/country') echo DE ;; *) echo 203.0.113.1 ;; esac ;;
    pidof:sing-box) exit 0 ;;
    pidof:*) exit 1 ;;
    timeout:10) exit 0 ;;
    timeout:45)
        echo restart >>"$TEST/restarts"
        if [ -e "$TEST/fail-restart" ]; then rm "$TEST/fail-restart"; exit 1; fi ;;
    home-net-install-verify:services) [ ! -e "$TEST/unhealthy" ] ;;
    *) exit 1 ;;
esac
EOF
chmod +x "$tmp/bin/mock"
for cmd in ubus uci awg curl pidof timeout home-net-install-verify; do
    cp "$tmp/bin/mock" "$tmp/bin/$cmd"
done
export PATH="$tmp/bin:$PATH"
echo main >"$tmp/podkop-section"
echo awg_main >"$tmp/active"
printf 'baseline\n\n' >"$tmp/awg_backup"
cat >"$tmp/candidate" <<'EOF'
[Interface]
ListenPort = 51820
PrivateKey = fixture
[Peer]
PublicKey = fixture
AdvancedSecurity = on
AllowedIPs = 0.0.0.0/0
Endpoint = 192.0.2.1:1234
EOF
backup="$tmp/transaction/backup"
run() { sh "$tmp/adapter" "$@"; }
reject() { if run "$@"; then echo "unexpected success: $1" >&2; exit 1; fi; }
touch "$tmp/conflict"
reject snapshot awg_main awg_backup "$backup"
test ! -e "$backup/target.conf"
printf "%s\n" "INSTALLED_VERSION='1.4.2'" >"$tmp/failover.conf"
(
    exec 9>"$tmp/maintenance.lock"
    flock -n 9
    reject snapshot awg_main awg_backup "$backup"
)
echo 1.4.2 >"$tmp/failover-lock-version"
reject snapshot awg_main awg_backup "$backup"
(
    exec 9>"$tmp/unrelated.lock"
    reject snapshot awg_main awg_backup "$backup"
)
(
    exec 9>"$tmp/maintenance.lock"
    flock -n 9
    run snapshot awg_main awg_backup "$backup"
)
test -s "$backup/target.conf"
rm "$tmp/failover.conf"
rm "$tmp/conflict"
cp "$tmp/candidate" "$tmp/unsafe"
echo 'PostUp = fixture' >>"$tmp/unsafe"
reject validate awg_backup "$tmp/unsafe"
run snapshot awg_main awg_backup "$backup"
run stage awg_main awg_backup "$tmp/candidate"
run restore awg_main awg_backup "$backup"
test ! -e "$tmp/restarts"
run stage awg_main awg_backup "$tmp/candidate"
test "$(cat "$tmp/active")" = awg_main
echo "$(($(date +%s) + 60))" >"$backup/staged-at"
reject verify awg_main awg_backup DE
echo "$(($(date +%s) - 30))" >"$backup/staged-at"
reject verify awg_main awg_backup FR
touch "$tmp/unhealthy"
reject verify awg_main awg_backup DE
rm "$tmp/unhealthy"
run verify awg_main awg_backup DE
printf 'drift\n' >>"$tmp/awg_backup"
reject promote awg_main awg_backup
cp "$tmp/candidate" "$tmp/awg_backup"
touch "$tmp/conflict"
reject promote awg_main awg_backup
test "$(cat "$tmp/active")" = awg_main
rm "$tmp/conflict"
touch "$tmp/fail-restart"
reject promote awg_main awg_backup
test "$(cat "$tmp/active")" = awg_backup
touch "$tmp/fail-restart"
reject restore awg_main awg_backup "$backup"
test "$(cat "$tmp/active")" = awg_main
run restore awg_main awg_backup "$backup"
run check-restored awg_main awg_backup "$backup"
test "$(wc -l <"$tmp/restarts")" -eq 3
echo 'PASS: Cudy adapter isolation and retry'
