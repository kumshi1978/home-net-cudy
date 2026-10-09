#!/bin/sh
set -eu

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"

bundle_version="$(tr -d '\r\n' < "$ROOT/VERSION")"
monitoring_version="$(tr -d '\r\n' < "$ROOT/MONITORING_VERSION")"
[ "$bundle_version" = "1.6.0" ]
[ "$monitoring_version" = "1.6.0" ]

grep -Fqx "HOME_NET_BUNDLE_VERSION='1.6.0'" "$ROOT/bundle.conf"
grep -Fqx "MONITORING_VERSION='1.6.0'" "$ROOT/bundle.conf"

bootstrap_ref="$(sed -n "s/^MONITORING_BOOTSTRAP_REF='\([^']*\)'$/\1/p" "$ROOT/bundle.conf")"
[ "$bootstrap_ref" = "736798dbb673d76e220e6a5b9aa47dfdfa8f01f1" ]
grep -Fq "HOME_NET_RELEASE_REF:-$bootstrap_ref" "$ROOT/install.sh"
grep -Fq 'downloading v1.6.0' "$ROOT/install.sh"

grep -Fqx "RELEASE_TAG='v1.5.4'" "$ROOT/rollout-policy.conf"
grep -Fqx "ROLLOUT='manual'" "$ROOT/rollout-policy.conf"

grep -Fq 'HOME_NET_SKIP_VERSION_RECORD' "$ROOT/install-all.sh"
grep -Fq 'if [ "${HOME_NET_SKIP_VERSION_RECORD:-0}" != "1" ]; then' "$ROOT/install-all.sh"

echo "PASS candidate_packaging_1_6_0"
