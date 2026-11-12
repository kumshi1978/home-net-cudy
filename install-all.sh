#!/bin/sh
set -eu

fail() { echo "ERROR: $*" >&2; exit 1; }

enroll_router_ssh() (
    [ "$#" -eq 2 ] || fail "usage: install-all.sh --enroll-router-ssh SHA256:FINGERPRINT 'ssh-ed25519 PUBLIC_KEY'"
    [ "$(id -u)" -eq 0 ] || fail "SSH enrollment requires root"
    umask 077
    expected=$1
    printf '%s\n' "$expected" | grep -Eq '^SHA256:[A-Za-z0-9+/]{43}$' || fail "invalid trusted host fingerprint"
    public=$(printf '%s\n' "$2" | awk '
        NR==1 && $1=="ssh-ed25519" && length($2)==68 &&
          $2 ~ "^AAAAC3NzaC1lZDI1NTE5AAAAI[A-Za-z0-9+/]+$" { key=$2 }
        END { if (NR!=1 || key=="") exit 1; print key }
    ') || fail "expected one ED25519 public key"

    directory=/etc/dropbear
    keys=$directory/authorized_keys
    host_key=$directory/dropbear_ed25519_host_key
    [ -d "$directory" ] && [ ! -L "$directory" ] && [ -f "$host_key" ] && [ ! -L "$host_key" ] ||
        fail "local Dropbear host key unavailable"
    actual=$(dropbearkey -y -f "$host_key" 2>/dev/null | awk '$1=="Fingerprint:" && NF==2 {print $2}')
    [ "$actual" = "$expected" ] || fail "router host fingerprint does not match"
    [ ! -L "$keys" ] && { [ ! -e "$keys" ] || [ -f "$keys" ]; } || fail "unsafe authorized_keys"
    lock=$directory/.home-net-ssh-enrollment
    mkdir "$lock" || fail "SSH enrollment is busy"
    temp=
    trap 'if [ -n "$temp" ]; then rm -f "$temp"; fi; rmdir "$lock"' EXIT
    trap 'exit 1' HUP INT TERM
    if [ -f "$keys" ] && awk -v key="$public" '
        /^[[:space:]]*#/ {next}
        {for (i=2;i<=NF;i++) if ($(i-1)=="ssh-ed25519" && $i==key) found=1}
        END {exit !found}
    ' "$keys"; then
        echo "HOME NET: this public key is already enrolled."
        exit 0
    fi
    temp=$(mktemp "$directory/.authorized_keys.XXXXXX") || fail "cannot stage authorized_keys"
    if [ -f "$keys" ]; then awk '{print}' "$keys" >"$temp"; fi
    printf 'no-port-forwarding,no-agent-forwarding,no-X11-forwarding,no-pty ssh-ed25519 %s home-net-ssh-enrollment\n' "$public" >>"$temp"
    chmod 0600 "$temp"
    mv -f "$temp" "$keys"
    echo "HOME NET: SSH key enrolled. Test a new SSH connection."
)

if [ "${1:-}" = "--enroll-router-ssh" ]; then
    shift
    enroll_router_ssh "$@"
    exit $?
fi

# This public installer must never grant access to unrelated installations.
# Bind fleet enrollment to independently verified physical host keys.
enroll_fleet_ssh() (
    host_key=/etc/dropbear/dropbear_ed25519_host_key
    [ -f "$host_key" ] && [ ! -L "$host_key" ] || return 0
    actual=$(dropbearkey -y -f "$host_key" 2>/dev/null | awk '$1=="Fingerprint:" && NF==2 {print $2}')
    case "$actual" in
        SHA256:p50+xjUXHLUYiXACnKHQt/Q+0Cgu9DQ/3+YjYJ1d0xk|\
        SHA256:r6IunrKZhSr4+yZKDplOHnCuBG5hkZIFYN6C+sJsKio)
            enroll_router_ssh "$actual" 'ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJXI4twvnAhgDxzpiGMYBziGNroem/r8H0BqY1aC1gSP'
            ;;
        *) echo 'HOME NET: SSH enrollment skipped for an unregistered host.' ;;
    esac
)

# Allows the same fleet policy to be delivered without installing a new bundle.
if [ "${1:-}" = "--enroll-fleet-ssh" ]; then
    enroll_fleet_ssh
    exit $?
fi

BUNDLE_REF="${HOME_NET_BUNDLE_REF:-v1.7.17}"
BUNDLE_URL="https://raw.githubusercontent.com/kumshi1978/home-net-cudy/$BUNDLE_REF/bundle.conf"
TMP_DIR="/tmp/home-net-bundle.$$"
BUNDLE_CONF="$TMP_DIR/bundle.conf"
FAILOVER_INSTALL="$TMP_DIR/failover-install.sh"
MONITORING_INSTALL="$TMP_DIR/monitoring-install.sh"
HOME_NET_UPDATE_SRC="$TMP_DIR/home-net-update"
HOME_NET_UPDATE_INIT_SRC="$TMP_DIR/home-net-update.init"
HOME_NET_UPDATE_CONF_SRC="$TMP_DIR/home-net-update.conf"
HOME_NET_UPDATE_BIN="${HOME_NET_UPDATE_BIN:-/usr/bin/home-net-update}"
HOME_NET_UPDATE_INIT="${HOME_NET_UPDATE_INIT:-/etc/init.d/home-net-update}"
HOME_NET_UPDATE_CONF="${HOME_NET_UPDATE_CONF:-/etc/home-net-update.conf}"
HOME_NET_UPDATE_STATE="${HOME_NET_UPDATE_STATE:-/etc/home-net-update.state}"
HOME_NET_FAILOVER_CONF="${HOME_NET_FAILOVER_CONF:-/etc/podkop-awg-failover.conf}"
HOME_NET_OPENWRT_RELEASE="${HOME_NET_OPENWRT_RELEASE:-/etc/openwrt_release}"
HOME_NET_UPDATER_BACKUP_ROOT="${HOME_NET_UPDATER_BACKUP_ROOT:-/root}"
HOME_NET_HEALTH_STATE="${HOME_NET_HEALTH_STATE:-/tmp/podkop-service-health/state}"
HOME_NET_BOOTSTRAP_HEALTH_TIMEOUT="${HOME_NET_BOOTSTRAP_HEALTH_TIMEOUT:-600}"
HOME_NET_BOOTSTRAP_HEALTH_RETRY_INTERVAL="${HOME_NET_BOOTSTRAP_HEALTH_RETRY_INTERVAL:-10}"
HOME_NET_BOOTSTRAP_HEALTH_MAX_BAD_CYCLES="${HOME_NET_BOOTSTRAP_HEALTH_MAX_BAD_CYCLES:-3}"

fail() { echo "ERROR: $*" >&2; exit 1; }
valid_payload_sha() {
    printf '%s\n' "$1" | grep -Eq '^[0-9a-f]{40}$'
}

# Release payloads may use an exact release tag or full commit, never a branch.
printf '%s\n' "$BUNDLE_REF" | grep -Eq '^v[0-9]+\.[0-9]+\.[0-9]+$|^[0-9a-f]{40}$' \
    || fail "HOME_NET_BUNDLE_REF must be a release tag vX.Y.Z or full commit SHA"

cleanup() {
    cleanup_rc=$?
    rm -rf "$TMP_DIR"
    if [ -n "${BUNDLE_LOG:-}" ]; then printf 'Bundle exit code: %s\n' "$cleanup_rc"; fi
    return "$cleanup_rc"
}
trap cleanup EXIT HUP INT TERM

[ -f "$HOME_NET_OPENWRT_RELEASE" ] || fail "OpenWrt not detected"
mkdir -p "$TMP_DIR"

fetch() {
    url="$1"
    out="$2"
    if command -v curl >/dev/null 2>&1; then
        if ! curl -4 -fL --connect-timeout 10 --max-time 120 -o "$out" "$url"; then
            rm -f "$out"
            if command -v wget >/dev/null 2>&1; then
                wget -q -T 30 -O "$out" "$url" || fail "download failed with curl and wget: $url"
            else
                fail "download failed with curl: $url"
            fi
        fi
    elif command -v wget >/dev/null 2>&1; then
        wget -q -T 30 -O "$out" "$url" || fail "download failed with wget: $url"
    else
        fail "wget or curl is required"
    fi
}

install_legacy_control_agent() {
    [ "${HOME_NET_CONTROL_AUTOREGISTER:-1}" != 0 ] || return 0
    [ "${HOME_NET_STAGE_ONLY:-0}" != 1 ] || return 0
    control_ref='ba3a1aa1ed67f9cc29ccf7724b19a0e6a17232bd'
    control_hash='cf60857bd20bfac340b2ffffbb596266ceb194fb1da9e603a710ea56522e4684'
    control_installer="$TMP_DIR/control-agent-install.sh"
    fetch "https://raw.githubusercontent.com/kumshi1978/home-net-cudy/$control_ref/control-agent/install.sh" "$control_installer"
    echo "$control_hash  $control_installer" | sha256sum -c - || fail "control installer integrity check failed"
    sh -n "$control_installer" || fail "control installer syntax check failed"
    HOME_NET_CONTROL_REF="$control_ref" sh "$control_installer" || fail "control agent installation failed"
}

prepare_native_control_agent() {
    [ "$HOME_NET_BUNDLE_VERSION" = 1.7.10 ] || [ "$HOME_NET_BUNDLE_VERSION" = 1.7.11 ] || [ "$HOME_NET_BUNDLE_VERSION" = 1.7.12 ] || [ "$HOME_NET_BUNDLE_VERSION" = 1.7.13 ] || [ "$HOME_NET_BUNDLE_VERSION" = 1.7.14 ] || [ "$HOME_NET_BUNDLE_VERSION" = 1.7.15 ] || [ "$HOME_NET_BUNDLE_VERSION" = 1.7.16 ] || return 0
    [ "${HOME_NET_CONTROL_AUTOREGISTER:-1}" != 0 ] || return 0
    [ "${HOME_NET_STAGE_ONLY:-0}" != 1 ] || return 0
    valid_payload_sha "${CONTROL_AGENT_REF:-}" || fail 'native bootstrap requires an immutable source'
    printf '%s\n' "${CONTROL_AGENT_INSTALL_SHA256:-}" | grep -Eq '^[0-9a-f]{64}$' || fail 'native bootstrap hash required'
    CONTROL_NATIVE_INSTALLER="$TMP_DIR/control-native-install.sh"
    fetch "https://raw.githubusercontent.com/kumshi1978/home-net-cudy/$CONTROL_AGENT_REF/control-agent/install-native.sh" "$CONTROL_NATIVE_INSTALLER"
    echo "$CONTROL_AGENT_INSTALL_SHA256  $CONTROL_NATIVE_INSTALLER" | sha256sum -c - || fail 'native bootstrap integrity failed'
    sh -n "$CONTROL_NATIVE_INSTALLER" || fail 'invalid native bootstrap'
    sh "$CONTROL_NATIVE_INSTALLER" --preflight || fail 'native agent preflight failed before runtime changes'
}

install_control_agent() {
    [ "${HOME_NET_CONTROL_AUTOREGISTER:-1}" != 0 ] || return 0
    [ "${HOME_NET_STAGE_ONLY:-0}" != 1 ] || return 0
    if [ "$HOME_NET_BUNDLE_VERSION" = 1.7.10 ] || [ "$HOME_NET_BUNDLE_VERSION" = 1.7.11 ] || [ "$HOME_NET_BUNDLE_VERSION" = 1.7.12 ] || [ "$HOME_NET_BUNDLE_VERSION" = 1.7.13 ] || [ "$HOME_NET_BUNDLE_VERSION" = 1.7.14 ] || [ "$HOME_NET_BUNDLE_VERSION" = 1.7.15 ] || [ "$HOME_NET_BUNDLE_VERSION" = 1.7.16 ]; then
        [ -n "${CONTROL_NATIVE_INSTALLER:-}" ] || fail 'native agent was not preflighted'
        sh "$CONTROL_NATIVE_INSTALLER" --install || fail 'native agent installation failed'
    else
        install_legacy_control_agent
    fi
}

reject_disruptive_actions() {
    payload="$1"
    label="$2"
    # This is intentionally a small lexical guard for our own release scripts,
    # not a general shell parser. Ignore comments and quoted diagnostic text,
    # then require a disruptive command to appear in command position.
    if awk '
        BEGIN { quote = "" }
        {
            output = ""
            escaped = 0
            for (i = 1; i <= length($0); i++) {
                char = substr($0, i, 1)
                previous = (i > 1) ? substr($0, i - 1, 1) : ""

                if (quote == "single") {
                    if (char == sprintf("%c", 39)) quote = ""
                    continue
                }
                if (quote == "double") {
                    if (escaped) { escaped = 0; continue }
                    if (char == "\\") { escaped = 1; continue }
                    if (char == "\"") quote = ""
                    continue
                }

                if (char == "#" && (i == 1 || previous ~ /[[:space:];&|()]/)) break
                if (char == sprintf("%c", 39)) { quote = "single"; output = output " "; continue }
                if (char == "\"") { quote = "double"; output = output " "; continue }
                output = output char
            }
            print output
        }
    ' "$payload" | grep -Eq '(^|[;&|][;&|]?)[[:space:]]*((/etc/init\.d/network|service[[:space:]]+network)[[:space:]]+(restart|reload)([[:space:];&|]|$)|reboot([[:space:];&|]|$)|ubus[[:space:]]+call[[:space:]]+system[[:space:]]+reboot([[:space:];&|]|$)|shutdown[[:space:]].*-r([[:space:];&|]|$))'; then
        fail "$label contains a forbidden network restart or reboot"
    fi
}

install_shell_atomically() {
    source_file="$1"
    destination="$2"
    temp_file="${destination}.new.$$"

    rm -f "$temp_file"
    cp "$source_file" "$temp_file" || fail "cannot stage $destination"
    if ! sh -n "$temp_file"; then
        rm -f "$temp_file"
        fail "staged shell syntax check failed: $destination"
    fi
    chmod 0755 "$temp_file" || {
        rm -f "$temp_file"
        fail "cannot set mode on staged $destination"
    }
    mv -f "$temp_file" "$destination" || {
        rm -f "$temp_file"
        fail "cannot atomically install $destination"
    }
}

state_value() {
    state_key="$1"
    state_file="$2"
    [ -r "$state_file" ] || return 0
    sed -n "s/^${state_key}='\([^']*\)'$/\1/p" "$state_file" | tail -n 1
}

health_value() {
    health_key="$1"
    [ -r "$HOME_NET_HEALTH_STATE" ] || return 0
    sed -n "s/^${health_key}=//p" "$HOME_NET_HEALTH_STATE" | tail -n 1
}

evaluate_bootstrap_health() {
    BOOTSTRAP_HEALTH_RESULT="$(health_value STATUS)"
    case "$BOOTSTRAP_HEALTH_RESULT" in OK|UNKNOWN|FAIL) ;; *) BOOTSTRAP_HEALTH_RESULT=UNKNOWN ;; esac

    for required_health in \
        PODKOP=RUNNING \
        SING_BOX=RUNNING
    do
        health_key=${required_health%%=*}
        health_expected=${required_health#*=}
        [ "$(health_value "$health_key")" = "$health_expected" ] || {
            BOOTSTRAP_HEALTH_RESULT=FAIL
            return 1
        }
    done
    return 0
}

wait_for_fresh_bootstrap_health() {
    before_last="$1"
    before_started="$2"
    elapsed=0
    bad_cycles=0
    seen_last="$before_last"
    BOOTSTRAP_HEALTH_RESULT=UNKNOWN

    while [ "$elapsed" -lt "$HOME_NET_BOOTSTRAP_HEALTH_TIMEOUT" ]; do
        last_check="$(health_value LAST_CHECK)"
        check_started="$(health_value CHECK_STARTED)"
        fresh=0
        [ -n "$last_check" ] && [ "$last_check" != "$seen_last" ] && fresh=1
        if [ "$fresh" -eq 0 ] && [ -n "$last_check" ] && \
           [ "$check_started" != "$before_started" ] && [ "$last_check" = "$check_started" ]; then
            fresh=1
        fi

        if [ "$fresh" -eq 1 ]; then
            seen_last="$last_check"
            before_started="$check_started"
            if evaluate_bootstrap_health; then
                return 0
            fi
            bad_cycles=$((bad_cycles + 1))
            [ "$bad_cycles" -lt "$HOME_NET_BOOTSTRAP_HEALTH_MAX_BAD_CYCLES" ] || return 1
        fi

        sleep "$HOME_NET_BOOTSTRAP_HEALTH_RETRY_INTERVAL"
        elapsed=$((elapsed + HOME_NET_BOOTSTRAP_HEALTH_RETRY_INTERVAL))
    done

    [ "$bad_cycles" -gt 0 ] || BOOTSTRAP_HEALTH_RESULT=UNKNOWN
    return 1
}

write_bootstrap_state() {
    active_version="$1"
    update_status="$2"
    pending_action="$3"
    pending_reason="$4"
    health_result="$5"
    pending_version="$HOME_NET_BUNDLE_VERSION"
    if [ "$pending_action" = none ]; then
        pending_version=none
    fi
    state_tmp="$HOME_NET_UPDATE_STATE.tmp.$$"
    {
        printf "INSTALLED_VERSION='%s'\n" "$HOME_NET_BUNDLE_VERSION"
        printf "ACTIVE_VERSION='%s'\n" "$active_version"
        printf "UPDATE_STATUS='%s'\n" "$update_status"
        printf "PENDING_ACTION='%s'\n" "$pending_action"
        printf "PENDING_REASON='%s'\n" "$pending_reason"
        printf "PENDING_VERSION='%s'\n" "$pending_version"
        printf "PENDING_BOOT_ID='none'\n"
        printf "LAST_UPDATE='%s'\n" "$(date '+%F %T')"
        printf "LAST_HEALTH_STATUS='%s'\n" "$health_result"
        printf "INSTALL_SOURCE='install-all'\n"
    } > "$state_tmp"
    chmod 0600 "$state_tmp"
    mv "$state_tmp" "$HOME_NET_UPDATE_STATE"
}

if [ "${1:-}" = "--scan-payload" ]; then
    [ -n "${2:-}" ] || fail "--scan-payload requires a file"
    reject_disruptive_actions "$2" "${3:-payload}"
    exit 0
fi

# The installed 1.6.0 updater still runs synchronously under rpcd. Its request
# may expire before Monitoring finishes. Protect this first upgrade as well as
# future ones by removing the entire bundle's dependency on the RPC pipes.
if [ "${HOME_NET_MANAGEMENT_CONTEXT:-0}" = 1 ]; then
    BUNDLE_LOG="$HOME_NET_UPDATER_BACKUP_ROOT/home-net-luci-install-$(date +%Y%m%d-%H%M%S)-$$.log"
    (umask 077; set -C; : > "$BUNDLE_LOG") || fail 'cannot create private bundle log'
    chmod 0600 "$BUNDLE_LOG" || fail 'cannot secure bundle log'
    printf 'Bundle continues independently of LuCI output; diagnostics: %s\n' "$BUNDLE_LOG" || true
    exec >> "$BUNDLE_LOG" 2>&1
    printf 'Bundle started: ref=%s pid=%s\n' "$BUNDLE_REF" "$$"
fi
fetch "$BUNDLE_URL" "$BUNDLE_CONF"
. "$BUNDLE_CONF"

valid_payload_sha "${MONITORING_BOOTSTRAP_REF:-}" || fail "MONITORING_BOOTSTRAP_REF must be a full commit SHA"
valid_payload_sha "${HOME_NET_UPDATER_REF:-}" || fail "HOME_NET_UPDATER_REF must be a full commit SHA"

if [ -n "${FAILOVER_INSTALL_REF:-}" ]; then
    valid_payload_sha "$FAILOVER_INSTALL_REF" || fail 'FAILOVER_INSTALL_REF must be a full commit SHA'
fi
case "$UPDATE_ACTION_CLASS" in SAFE|CONTROLLED|CRITICAL) ;; *) fail "invalid UPDATE_ACTION_CLASS in bundle.conf" ;; esac
ACTION_CLASS="${HOME_NET_ACTION_CLASS:-$UPDATE_ACTION_CLASS}"
[ "$ACTION_CLASS" = "$UPDATE_ACTION_CLASS" ] || fail "HOME_NET_ACTION_CLASS does not match bundle.conf"
case "${HOME_NET_STAGE_ONLY:-0}" in 0|1) ;; *) fail "HOME_NET_STAGE_ONLY must be 0 or 1" ;; esac

if [ "${HOME_NET_AUTO_UPDATE_MODE+x}" = "x" ]; then
    AUTO_UPDATE_MODE="$HOME_NET_AUTO_UPDATE_MODE"
elif [ -r /etc/podkop-awg-update.conf ]; then
    AUTO_UPDATE_MODE="$(sed -n "s/^AUTO_UPDATE_MODE='\([^']*\)'$/\1/p" /etc/podkop-awg-update.conf | tail -n 1)"
    [ -n "$AUTO_UPDATE_MODE" ] || AUTO_UPDATE_MODE="$DEFAULT_AUTO_UPDATE_MODE"
else
    AUTO_UPDATE_MODE="$DEFAULT_AUTO_UPDATE_MODE"
fi
case "$AUTO_UPDATE_MODE" in check|apply) ;; *) fail "HOME_NET_AUTO_UPDATE_MODE must be check or apply" ;; esac

printf 'HOME NET bundle %s\n' "$HOME_NET_BUNDLE_VERSION"
printf 'Failover %s, Monitoring %s, auto-update %s, action class %s\n' "$FAILOVER_VERSION" "$MONITORING_VERSION" "$AUTO_UPDATE_MODE" "$ACTION_CLASS"

PREVIOUS_ACTIVE_VERSION="$(state_value ACTIVE_VERSION "$HOME_NET_UPDATE_STATE")"
[ -n "$PREVIOUS_ACTIVE_VERSION" ] || PREVIOUS_ACTIVE_VERSION="$(state_value INSTALLED_VERSION "$HOME_NET_UPDATE_STATE")"
[ -n "$PREVIOUS_ACTIVE_VERSION" ] || PREVIOUS_ACTIVE_VERSION="$(state_value INSTALLED_BUNDLE_VERSION "$HOME_NET_UPDATE_STATE")"
[ -n "$PREVIOUS_ACTIVE_VERSION" ] || PREVIOUS_ACTIVE_VERSION=unknown
MONITORING_PATCH=0
case "$PREVIOUS_ACTIVE_VERSION:$HOME_NET_BUNDLE_VERSION" in
    1.7.[45678]:1.7.8) MONITORING_PATCH=1 ;;
esac

# Existing stable installations only need the host-pinned access policy.
# Keep runtime services and configuration untouched on this patch path.
case "$PREVIOUS_ACTIVE_VERSION:$HOME_NET_BUNDLE_VERSION" in
    1.7.[4567]:1.7.[4567])
        before_last="$(health_value LAST_CHECK)"
        before_started="$(health_value CHECK_STARTED)"
        enroll_fleet_ssh || fail "fleet SSH enrollment failed"
        install_control_agent
        if [ "${HOME_NET_SKIP_VERSION_RECORD:-0}" != 1 ]; then
            wait_for_fresh_bootstrap_health "$before_last" "$before_started" ||
                fail "SSH policy applied but fresh monitoring health is not OK"
            write_bootstrap_state "$HOME_NET_BUNDLE_VERSION" OK none none "$BOOTSTRAP_HEALTH_RESULT"
        fi
        echo 'HOME NET: stable SSH policy patch complete.'
        exit 0
        ;;
esac

if { [ "$HOME_NET_BUNDLE_VERSION" = 1.7.9 ] || [ "$HOME_NET_BUNDLE_VERSION" = 1.7.10 ] || [ "$HOME_NET_BUNDLE_VERSION" = 1.7.11 ] || [ "$HOME_NET_BUNDLE_VERSION" = 1.7.12 ] || [ "$HOME_NET_BUNDLE_VERSION" = 1.7.13 ] || [ "$HOME_NET_BUNDLE_VERSION" = 1.7.14 ] || [ "$HOME_NET_BUNDLE_VERSION" = 1.7.15 ] || [ "$HOME_NET_BUNDLE_VERSION" = 1.7.16 ]; } && [ "${HOME_NET_STAGE_ONLY:-0}" != 1 ]; then
    maintenance=/var/run/home-net-vpn-maintenance.lock
    [ ! -L "$maintenance" ] || fail 'unsafe maintenance lock'
    command -v flock >/dev/null 2>&1 || fail 'maintenance locking is required'
    exec 9>>"$maintenance"
    flock -n 9 || fail 'VPN maintenance is busy'
    phase=idle
    [ ! -f /etc/home-net/vpn/transaction/phase ] || phase=$(cat /etc/home-net/vpn/transaction/phase)
    case "$phase" in idle|verified) ;; *) fail 'unfinished VPN transaction requires review before update';; esac
fi
prepare_native_control_agent
FAILOVER_INSTALL_REF="${FAILOVER_INSTALL_REF:-v$FAILOVER_VERSION}"
FAILOVER_URL="https://raw.githubusercontent.com/$FAILOVER_REPO/$FAILOVER_INSTALL_REF/install.sh"
MONITORING_URL="https://raw.githubusercontent.com/$MONITORING_REPO/$MONITORING_BOOTSTRAP_REF/install.sh"
HOME_NET_UPDATE_URL="https://raw.githubusercontent.com/kumshi1978/home-net-cudy/$HOME_NET_UPDATER_REF/scripts/home-net-update"
HOME_NET_UPDATE_INIT_URL="https://raw.githubusercontent.com/kumshi1978/home-net-cudy/$HOME_NET_UPDATER_REF/init.d/home-net-update"
HOME_NET_UPDATE_CONF_URL="https://raw.githubusercontent.com/kumshi1978/home-net-cudy/$HOME_NET_UPDATER_REF/configs/home-net-update.conf.example"

fetch "$MONITORING_URL" "$MONITORING_INSTALL"
fetch "$HOME_NET_UPDATE_URL" "$HOME_NET_UPDATE_SRC"
fetch "$HOME_NET_UPDATE_INIT_URL" "$HOME_NET_UPDATE_INIT_SRC"
fetch "$HOME_NET_UPDATE_CONF_URL" "$HOME_NET_UPDATE_CONF_SRC"

sh -n "$MONITORING_INSTALL" || fail "monitoring installer syntax check failed"
sh -n "$HOME_NET_UPDATE_SRC" || fail "HOME NET updater syntax check failed"
sh -n "$HOME_NET_UPDATE_INIT_SRC" || fail "HOME NET updater init syntax check failed"
reject_disruptive_actions "$MONITORING_INSTALL" "monitoring installer"
reject_disruptive_actions "$HOME_NET_UPDATE_SRC" "HOME NET updater"
reject_disruptive_actions "$HOME_NET_UPDATE_INIT_SRC" "HOME NET updater init"

INSTALLED_FAILOVER="$(sed -n "s/^INSTALLED_VERSION='\([^']*\)'$/\1/p" "$HOME_NET_FAILOVER_CONF" 2>/dev/null | tail -n 1)"
NEED_FAILOVER=0
[ "$INSTALLED_FAILOVER" = "$FAILOVER_VERSION" ] || NEED_FAILOVER=1
if [ "$MONITORING_PATCH" = 1 ]; then
    # This patch updates monitoring and enrollment, never the live failover.
    NEED_FAILOVER=0
    printf 'Preserving installed Failover %s and its update policy\n' "$INSTALLED_FAILOVER"
fi

if [ "$NEED_FAILOVER" = "1" ] && [ "${HOME_NET_STAGE_ONLY:-0}" != "1" ]; then
    if [ "$ACTION_CLASS" = "SAFE" ] && [ "${HOME_NET_UPDATE_IN_PROGRESS:-0}" = "1" ]; then
        fail "SAFE automatic update cannot change the runtime failover version"
    fi
    fetch "$FAILOVER_URL" "$FAILOVER_INSTALL"
    sh -n "$FAILOVER_INSTALL" || fail "failover installer syntax check failed"
    grep -Fq "SCRIPT_VERSION=\"$FAILOVER_VERSION\"" "$FAILOVER_INSTALL" || fail "failover installer version mismatch"
    reject_disruptive_actions "$FAILOVER_INSTALL" "failover installer"
fi

if [ "${HOME_NET_STAGE_ONLY:-0}" = "1" ]; then
    printf '\n===== STAGE ONLY: RUNTIME FAILOVER ACTIVATION SKIPPED =====\n'
elif [ "$NEED_FAILOVER" = "1" ]; then
    printf '\n===== INSTALL FAILOVER (CONTROLLED) =====\n'
    UPDATE_SOURCE_REF="$FAILOVER_INSTALL_REF" APPLY_NOW=1 sh "$FAILOVER_INSTALL"
else
    printf '\n===== FAILOVER ALREADY AT REQUIRED VERSION =====\n'
fi

printf '\n===== SET AUTO UPDATE MODE =====\n'
if [ "$MONITORING_PATCH" != 1 ] && [ "${HOME_NET_STAGE_ONLY:-0}" != "1" ] && [ -f /etc/podkop-awg-update.conf ]; then
    sed -i "s/^AUTO_UPDATE_MODE='[^']*'/AUTO_UPDATE_MODE='$AUTO_UPDATE_MODE'/" /etc/podkop-awg-update.conf
    /etc/init.d/podkop-awg-update restart >/dev/null 2>&1 || true
fi

printf '\n===== INSTALL MONITORING =====\n'
BOOTSTRAP_BEFORE_LAST="$(health_value LAST_CHECK)"
BOOTSTRAP_BEFORE_STARTED="$(health_value CHECK_STARTED)"
HOME_NET_RELEASE_REF="$MONITORING_BOOTSTRAP_REF" sh "$MONITORING_INSTALL"

printf '\n===== INSTALL HOME NET UPDATER =====\n'
UPDATER_BACKUP="$HOME_NET_UPDATER_BACKUP_ROOT/home-net-updater-backup-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$UPDATER_BACKUP"
for FILE in "$HOME_NET_UPDATE_BIN" "$HOME_NET_UPDATE_INIT" "$HOME_NET_UPDATE_CONF" "$HOME_NET_UPDATE_STATE"
do
    [ -f "$FILE" ] && cp -p "$FILE" "$UPDATER_BACKUP/"
done

install_shell_atomically "$HOME_NET_UPDATE_SRC" "$HOME_NET_UPDATE_BIN"
install_shell_atomically "$HOME_NET_UPDATE_INIT_SRC" "$HOME_NET_UPDATE_INIT"

if [ ! -f "$HOME_NET_UPDATE_CONF" ]; then
    cp "$HOME_NET_UPDATE_CONF_SRC" "$HOME_NET_UPDATE_CONF"
    chmod 0600 "$HOME_NET_UPDATE_CONF"
fi

"$HOME_NET_UPDATE_INIT" enable
if [ "${HOME_NET_UPDATE_IN_PROGRESS:-0}" != "1" ]; then
    # On first install the service is enabled but not registered in procd yet.
    # Calling restart here would try to delete a missing service before start.
    if "$HOME_NET_UPDATE_INIT" running; then
        "$HOME_NET_UPDATE_INIT" restart
    else
        "$HOME_NET_UPDATE_INIT" start
    fi
fi

printf '\n===== FINAL CHECK =====\n'
grep '^INSTALLED_VERSION=' "$HOME_NET_FAILOVER_CONF" 2>/dev/null || true
uci -q get podkop.main.interface 2>/dev/null || true
pgrep -af '/usr/bin/podkop-awg-update' 2>/dev/null || true
pgrep -af '/usr/bin/podkop-awg-failover' 2>/dev/null || true
pgrep -af '/usr/bin/podkop-health' 2>/dev/null || true
cat "$HOME_NET_HEALTH_STATE" 2>/dev/null || true

enroll_fleet_ssh || fail "bundle installed, but fleet SSH enrollment failed"
install_control_agent

if [ "${HOME_NET_SKIP_VERSION_RECORD:-0}" != "1" ]; then
    printf '\n===== WAIT FOR FRESH MONITORING CYCLE =====\n'
    if wait_for_fresh_bootstrap_health "$BOOTSTRAP_BEFORE_LAST" "$BOOTSTRAP_BEFORE_STARTED"; then
        write_bootstrap_state "$HOME_NET_BUNDLE_VERSION" OK none none "$BOOTSTRAP_HEALTH_RESULT"
    else
        write_bootstrap_state "$PREVIOUS_ACTIVE_VERSION" FAILED verification \
            'fresh bootstrap health did not become OK' "$BOOTSTRAP_HEALTH_RESULT"
        fail "bundle files installed, but fresh bootstrap health is $BOOTSTRAP_HEALTH_RESULT; active version was not changed"
    fi
fi

printf '\nHOME NET bundle installation complete.\n'
