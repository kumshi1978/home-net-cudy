#!/bin/sh
# HOME NET Cudy
# Bootstrap-установщик публичного релиза v1.4.1

set -eu

REPO="kumshi1978/home-net-cudy"
RELEASE_REF="${HOME_NET_RELEASE_REF:-v1.4.1}"
TMP_DIR="/tmp/home-net-cudy-install.$$"
ARCHIVE="$TMP_DIR/release.tar.gz"
SRC_DIR="$TMP_DIR/src"
URL="https://github.com/$REPO/archive/$RELEASE_REF.tar.gz"

fail() {
    echo "ERROR: $*" >&2
    exit 1
}

cleanup() {
    rm -rf "$TMP_DIR"
}

trap cleanup EXIT HUP INT TERM

[ -f /etc/openwrt_release ] || fail "OpenWrt not detected"
command -v tar >/dev/null 2>&1 || fail "tar not found"

mkdir -p "$SRC_DIR"

echo "HOME NET Monitoring: downloading $RELEASE_REF"

if command -v wget >/dev/null 2>&1; then
    wget -q -O "$ARCHIVE" "$URL" || fail "download failed: $URL"
elif command -v curl >/dev/null 2>&1; then
    curl -fL --connect-timeout 10 --max-time 120 -o "$ARCHIVE" "$URL" || fail "download failed: $URL"
else
    fail "wget or curl is required"
fi

[ -s "$ARCHIVE" ] || fail "downloaded archive is empty"

tar -xzf "$ARCHIVE" -C "$SRC_DIR" || fail "cannot extract release archive"

REPO_DIR="$(find "$SRC_DIR" -mindepth 1 -maxdepth 1 -type d | head -1)"
[ -n "$REPO_DIR" ] || fail "release directory not found"
[ -f "$REPO_DIR/VERSION" ] || fail "VERSION file not found"
[ -f "$REPO_DIR/install/install.sh" ] || fail "bundled installer not found"

VERSION="$(cat "$REPO_DIR/VERSION")"
echo "HOME NET Monitoring version: $VERSION"

sh -n "$REPO_DIR/install/install.sh" || fail "bundled installer syntax check failed"
sh "$REPO_DIR/install/install.sh"

echo
echo "HOME NET Monitoring installation complete"

if [ -f /tmp/podkop-service-health/state ]; then
    echo "Current state:"
    cat /tmp/podkop-service-health/state
fi
