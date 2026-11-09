#!/bin/sh
set -eu
umask 077
fail() { echo "HOME NET native bootstrap: $*" >&2; exit 1; }
[ "$(id -u)" = 0 ] || fail 'root required'
case "${1:---install}" in --preflight|--install) mode=${1:---install} ;; *) fail 'invalid mode' ;; esac
[ "$#" -le 1 ] || fail 'invalid invocation'
[ "${HOME_NET_STAGE_ONLY:-0}" != 1 ] || exit 0
[ "$(uname -m)" = aarch64 ] || fail 'native agent supports aarch64 only'
source_commit='482763b1c3f66796c8c06525b8d145c891297c27'
package_sha='ed754f716ece272b41487ed3a0bac31252b476a3457b00726c43f1c53f22b3bc'
url='https://github.com/kumshi1978/home-net-cudy/releases/download/v1.7.12/home-net-native-agent-1.7.12-linux-arm64.tar.gz'
work=$(mktemp -d /tmp/home-net-native-bootstrap.XXXXXX)
trap 'rm -rf "$work"' EXIT
trap 'exit 1' HUP INT TERM
archive=$work/native-agent.tar.gz
if [ -n "${HOME_NET_NATIVE_ARCHIVE:-}" ]; then
    [ -f "$HOME_NET_NATIVE_ARCHIVE" ] || fail 'local archive missing'
    cp "$HOME_NET_NATIVE_ARCHIVE" "$archive"
elif command -v wget >/dev/null 2>&1; then
    wget -q -T 120 -O "$archive" "$url" || fail 'archive download failed'
elif command -v curl >/dev/null 2>&1; then
    curl -fL --connect-timeout 10 --max-time 120 -o "$archive" "$url" || fail 'archive download failed'
else
    fail 'wget or curl required'
fi
echo "$package_sha  $archive" | sha256sum -c - >/dev/null || fail 'archive integrity check failed'
tar -xzf "$archive" -C "$work" || fail 'archive extraction failed'
payload=$work/native-agent-arm64
grep -Fxq 'version=1.7.12' "$payload/BUILD-INFO" || fail 'unexpected native version'
grep -Fxq "source_commit=$source_commit" "$payload/BUILD-INFO" || fail 'unexpected native source'
grep -Fxq 'architecture=linux-arm64' "$payload/BUILD-INFO" || fail 'unexpected native architecture'
sh "$payload/install.sh" "$mode"
