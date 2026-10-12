#!/bin/sh
set -eu
ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
HOME_NET_TEST_LUCI_UPGRADE=1 sh "$ROOT/tests/test-home-net-install-verify.sh"
