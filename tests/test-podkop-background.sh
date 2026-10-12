#!/bin/sh
set -eu
ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
for manager in opkg apk; do
 MOCK_PKG_MANAGER="$manager" HOME_NET_TEST_PODKOP_BACKGROUND=1 sh "$ROOT/tests/test-home-net-podkop-update.sh"
 echo "PASS background Podkop package format $manager"
done
