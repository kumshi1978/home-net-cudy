#!/bin/sh
set -eu
umask 077
fail() { echo "HOME NET native bootstrap: $*" >&2; exit 1; }
[ "$(id -u)" = 0 ] || fail 'root required'
case "${1:---install}" in --preflight|--install) mode=${1:---install} ;; *) fail 'invalid mode' ;; esac
[ "$#" -le 1 ] || fail 'invalid invocation'
[ "${HOME_NET_STAGE_ONLY:-0}" != 1 ] || exit 0
[ "$(uname -m)" = aarch64 ] || fail 'native agent supports aarch64 only'
source_commit='755e602131a3eba76d4e513678fd2b006245c504'
package_sha='3c08ef151b0ad7113f157e329bde2607480610219f068b4b26cc0c6f10f3d80e'
url='https://github.com/kumshi1978/home-net-cudy/releases/download/v1.7.18-native/home-net-native-agent-1.7.18-linux-arm64.tar.gz'
work=$(mktemp -d /tmp/home-net-native-bootstrap.XXXXXX)
trap 'rm -rf "$work"' EXIT
trap 'exit 1' HUP INT TERM
archive=$work/native-agent.tar.gz
if [ -n "${HOME_NET_NATIVE_ARCHIVE:-}" ]; then
    [ -f "$HOME_NET_NATIVE_ARCHIVE" ] || fail 'local archive missing'
    cp "$HOME_NET_NATIVE_ARCHIVE" "$archive"
elif command -v curl >/dev/null 2>&1; then
    if ! curl -4 -fL --connect-timeout 10 --max-time 120 -o "$archive" "$url"; then
        rm -f "$archive"
        if command -v wget >/dev/null 2>&1; then
            wget -q -T 30 -O "$archive" "$url" || fail 'archive download failed with curl and wget'
        else
            fail 'archive download failed with curl'
        fi
    fi
elif command -v wget >/dev/null 2>&1; then
    wget -q -T 30 -O "$archive" "$url" || fail 'archive download failed with wget'
else
    fail 'wget or curl required'
fi
echo "$package_sha  $archive" | sha256sum -c - >/dev/null || fail 'archive integrity check failed'
tar -xzf "$archive" -C "$work" || fail 'archive extraction failed'
payload=$work/native-agent-arm64
grep -Fxq 'version=1.7.18' "$payload/BUILD-INFO" || fail 'unexpected native version'
grep -Fxq "source_commit=$source_commit" "$payload/BUILD-INFO" || fail 'unexpected native source'
grep -Fxq 'architecture=linux-arm64' "$payload/BUILD-INFO" || fail 'unexpected native architecture'
sh "$payload/install.sh" "$mode"
