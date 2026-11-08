#!/bin/sh
set -eu
ROOT="$(CDPATH= cd -- "$(dirname "$0")/.." && pwd)"
sh -n "$ROOT/control-agent/install-three-slots.sh"
python3 -m unittest discover -s "$ROOT/tests" -p test_vpn_persist.py
sh "$ROOT/tests/test-controller-install.sh"
