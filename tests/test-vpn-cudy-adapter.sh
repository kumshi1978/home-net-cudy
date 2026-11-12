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
        case "$3" in
          network.awg_backup2.proto) echo amneziawg ;;
          network.awg_backup2.home_net_prepared) echo 1 ;;
          network.awg_backup2.auto|network.awg_backup2.defaultroute|network.awg_backup2.peerdns) echo 0 ;;
          network.awg_backup2.addresses) echo 10.8.1.210/32 ;;
          network) echo network.awg_backup2=interface ;;
          *.interface) cat "$TEST/active" ;; *) echo vpn ;; esac ;;
    uci:set) printf '%s\n' "${2#*=}" >"$TEST/active" ;;
    podkop-country-lookup:*) echo DE ;;
    ip:link) [ ! -f "$TEST/down-third" ] ;;
    awg:showconf)
        if [ "$2" = awg_backup2 ] && [ -e "$TEST/down-third" ]; then exit 1; fi
        cat "$TEST/$2" ;;
    timeout:15)
        if [ "$2" = ifup ]; then touch "$TEST/starting-third"
        elif [ "$2" = ifdown ]; then touch "$TEST/down-third"; echo down >>"$TEST/down-events"
        else exit 1; fi ;;
    awg:syncconf) cp "$3" "$TEST/$2" ;;
    awg:show)
        if [ "$3" = endpoints ]; then printf 'fixture 192.0.2.2:1234\n'
        else printf 'fixture %s\n' "$(($(date +%s) - 1))"; fi ;;
    curl:-q)
        case "$*" in *'if!awg_'* ) ;; *) exit 1 ;; esac
        case "$*" in *'/country') echo DE ;; *) echo "${TEST_EXIT_IP:-192.0.2.2}" ;; esac ;;
    pidof:sing-box) exit 0 ;;
    pidof:*) exit 1 ;;
    timeout:10) exit 0 ;;
    timeout:45)
        echo restart >>"$TEST/restarts"
        if [ -e "$TEST/fail-restart" ]; then rm "$TEST/fail-restart"; exit 1; fi
        if [ -e "$TEST/slow-restart" ]; then touch "$TEST/warming-up"; fi ;;
    home-net-install-verify:services)
        if [ -e "$TEST/warming-up" ]; then
            rm "$TEST/warming-up"
            echo retry >>"$TEST/readiness"
            exit 1
        fi
        [ ! -e "$TEST/unhealthy" ] ;;
    sleep:1)
        if [ -e "$TEST/starting-third" ]; then
            echo wait >>"$TEST/device-waits"
            if [ ! -e "$TEST/never-ready" ]; then
                rm "$TEST/starting-third" "$TEST/down-third"
                printf 'baseline\n' >"$TEST/awg_backup2"
            fi
        fi ;;
    *) exit 1 ;;
esac
EOF
chmod +x "$tmp/bin/mock"
for cmd in ubus uci awg curl pidof timeout home-net-install-verify sleep ip podkop-country-lookup; do
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
sed 's/192.0.2.1:1234/192.0.2.2:9999/' "$tmp/candidate" >"$tmp/same-server"
reject stage awg_main awg_backup "$tmp/same-server"
test "$(cat "$tmp/awg_backup")" = baseline
run stage awg_main awg_backup "$tmp/candidate"
run restore awg_main awg_backup "$backup"
test ! -e "$tmp/restarts"
run stage awg_main awg_backup "$tmp/candidate"
test "$(cat "$tmp/active")" = awg_main
echo "$(($(date +%s) + 60))" >"$backup/staged-at"
reject verify awg_main awg_backup DE
echo "$(($(date +%s) - 30))" >"$backup/staged-at"
# GeoIP mismatch is advisory: the expected country no longer gates acceptance.
run verify awg_main awg_backup FR
# The tunnel must still exit through its assigned VDS, not WAN/another VPN.
TEST_EXIT_IP=198.51.100.9
export TEST_EXIT_IP
reject verify awg_main awg_backup DE
unset TEST_EXIT_IP
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
touch "$tmp/slow-restart"
run restore awg_main awg_backup "$backup"
run check-restored awg_main awg_backup "$backup"
test "$(cat "$tmp/readiness")" = retry
test "$(wc -l <"$tmp/restarts")" -eq 3
echo 'PASS: Cudy adapter isolation and retry'

# New disabled slot: validate reserved UCI address without starting the device.
touch "$TEST/down-third"
run prepared-address awg_backup2 10.8.1.210/32
reject prepared-address awg_backup2 10.8.1.211/32
rm "$TEST/down-third"
reject prepared-address awg_backup2 10.8.1.210/32

# ifup returns before netifd creates the device: wait without touching active VPN.
touch "$TEST/down-third"
run snapshot awg_main awg_backup2 "$backup"
test -f "$backup/target-was-down"
test -s "$TEST/device-waits"
test "$(cat "$TEST/active")" = awg_main
# A device which never becomes ready is brought down and rejected in bounded time.
touch "$TEST/down-third" "$TEST/never-ready"
reject snapshot awg_main awg_backup2 "$backup"
test -s "$TEST/down-events"
test "$(wc -l <"$TEST/device-waits")" -eq 15
echo 'PASS: asynchronous prepared-slot startup and timeout cleanup'