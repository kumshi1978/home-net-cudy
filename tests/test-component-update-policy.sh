#!/bin/sh
set -eu
ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT HUP INT TERM
# Execute the actual selection block against a sandbox config, never /etc.
sed -n '/^if \[ "${HOME_NET_AUTO_UPDATE_MODE+x}"/,/^case "$AUTO_UPDATE_MODE"/p' "$ROOT/install-all.sh" |
    sed "s|/etc/podkop-awg-update.conf|$TMP/component.conf|g" > "$TMP/policy"
printf '\nprintf "%%s\\n" "$AUTO_UPDATE_MODE"\n' >> "$TMP/policy"
cat > "$TMP/run" <<'EOF_RUN'
#!/bin/sh
set -eu
fail() { exit 1; }
DEFAULT_AUTO_UPDATE_MODE=check
. "$1"
EOF_RUN
for mode in apply check; do
    printf "AUTO_UPDATE_MODE='%s'\n" "$mode" > "$TMP/component.conf"
    actual="$(unset HOME_NET_AUTO_UPDATE_MODE; sh "$TMP/run" "$TMP/policy")"
    [ "$actual" = "$mode" ]
    echo "PASS preserve_component_$mode"
done
actual="$(HOME_NET_AUTO_UPDATE_MODE=apply sh "$TMP/run" "$TMP/policy")"
[ "$actual" = apply ]
echo 'PASS explicit_component_override'
rm "$TMP/component.conf"
actual="$(unset HOME_NET_AUTO_UPDATE_MODE; sh "$TMP/run" "$TMP/policy")"
[ "$actual" = check ]
echo 'PASS new_component_default_check'
grep -Fxq "HOME_NET_UPDATE_MODE='check'" "$ROOT/configs/home-net-update.conf.example"
grep -Fxq "HOME_NET_UPDATE_CANARY='0'" "$ROOT/configs/home-net-update.conf.example"
echo 'PASS independent_updater_defaults'
