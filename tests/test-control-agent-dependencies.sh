#!/bin/sh
set -eu
ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT HUP INT TERM
mkdir -p "$TMP/bin" "$TMP/index"
sed -e "s@/var/opkg-lists/@$TMP/index/@g" \
    -e "s@lock=/var/run/home-net-control-install.lock@lock=$TMP/install.lock@" \
    -e 's@df -Pk /overlay@df -Pk /@' \
    "$ROOT/control-agent/install.sh" >"$TMP/install"
cat >"$TMP/bin/id" <<'EOF'
#!/bin/sh
echo 0
EOF
cat >"$TMP/bin/python3" <<'EOF'
#!/bin/sh
[ "${PYTHON_READY:-0}" = 1 ] || [ -f "$FIXTURE/python-installed" ]
EOF
cat >"$TMP/bin/df" <<'EOF'
#!/bin/sh
printf 'Filesystem 1024-blocks Used Available Capacity Mounted\nfixture 999999 0 %s 0%% /\n' "$FREE_KIB"
EOF
cat >"$TMP/bin/opkg" <<'EOF'
#!/bin/sh
echo "$*" >>"$FIXTURE/calls"
case "$1" in
    update) exit "${UPDATE_RC:-0}" ;;
    status) cat "$FIXTURE/status" ;;
    install) touch "$FIXTURE/python-installed" ;;
    *) exit 91 ;;
esac
EOF
chmod +x "$TMP/bin/"*
export FIXTURE="$TMP" FREE_KIB=100000
export PATH="$TMP/bin:$PATH"
cat >"$TMP/status" <<'EOF'
Package: libc
Status: install ok installed

Package: zlib
Status: install ok installed

Package: ca-bundle
Status: install ok installed
Provides: ca-certs

EOF
metadata() {
    : >"$TMP/metadata"
    for p in python3-light python3-openssl python3-email python3-urllib; do
        printf 'Package: %s\nInstalled-Size: 1048576\nDepends: libc, common (>= 1), ca-certs\n\n' "$p" >>"$TMP/metadata"
    done
    printf 'Package: common\nInstalled-Size: 1048576\nDepends: zlib\n\n' >>"$TMP/metadata"
    [ "${WITH_AGE:-1}" = 0 ] || printf 'Package: age\nInstalled-Size: 2097152\nDepends: libc\n\n' >>"$TMP/metadata"
    gzip -c "$TMP/metadata" >"$TMP/index/packages"
}
run() {
    HOME_NET_CONTROL_REF=1111111111111111111111111111111111111111 sh "$TMP/install" "$@" >"$TMP/output" 2>&1
}
expect_fail() {
    if run "$@"; then cat "$TMP/output"; echo 'unexpected success' >&2; exit 1; fi
    ! grep -q '^install ' "$TMP/calls"
    [ ! -d "$TMP/install.lock" ]
}
metadata
# 4 roots + one shared dependency + age = 7 MiB, plus 4 MiB reserve.
run --preflight
grep -q 'requires 11264 KiB' "$TMP/output"
! grep -q '^install ' "$TMP/calls"
echo 'PASS complete closure, shared dependency counted once, installed Provides, no installation in preflight'
FREE_KIB=11263 expect_fail --prepare-dependencies
grep -q 'insufficient flash' "$TMP/output"
echo 'PASS insufficient total space refuses before package installation'
WITH_AGE=0 metadata
expect_fail --prepare-dependencies
grep -q 'unavailable package: age' "$TMP/output"
echo 'PASS missing age refuses before any Python installation'
metadata
UPDATE_RC=1 expect_fail --preflight
grep -q 'index refresh failed' "$TMP/output"
echo 'PASS index failure is closed'
sed 's/Installed-Size: 1048576/Installed-Size: unknown/' "$TMP/metadata" | gzip -c >"$TMP/index/packages"
expect_fail --preflight
grep -q 'unknown installed size' "$TMP/output"
echo 'PASS unknown size is closed'
metadata
# Dependencies already supplied by a reviewed installation: only reserve needed.
for p in age age-keygen; do
    printf '#!/bin/sh\nexit 0\n' >"$TMP/bin/$p"
    chmod +x "$TMP/bin/$p"
done
: >"$TMP/calls"
PYTHON_READY=1 FREE_KIB=4096 run --preflight
grep -q 'requires 4096 KiB' "$TMP/output"
test ! -s "$TMP/calls"
echo 'PASS existing working dependencies do not contact package manager'
PYTHON_READY=1 FREE_KIB=4095 expect_fail --preflight
echo 'PASS reserve also enforced for existing dependencies'
run --prepare-dependencies
grep -q '^install python3-light python3-openssl python3-email python3-urllib$' "$TMP/calls"
! grep -Eq '^install (python3 |.*python3-ssl)' "$TMP/calls"
test ! -d "$TMP/install.lock"
echo 'PASS compact package installation and import verification'
rm "$TMP/python-installed"
: >"$TMP/calls"
cat >"$TMP/bin/apk" <<'EOF'
#!/bin/sh
echo "apk $*" >>"$FIXTURE/calls"
[ "${APK_FAIL:-0}" = 0 ]
EOF
chmod +x "$TMP/bin/apk"
FREE_KIB=36864 run --preflight
grep -q '^apk add --simulate python3-light python3-openssl python3-email python3-urllib$' "$TMP/calls"
FREE_KIB=36863 expect_fail --preflight
APK_FAIL=1 expect_fail --preflight
echo 'PASS apk resolver failure and conservative space gate before installation'
