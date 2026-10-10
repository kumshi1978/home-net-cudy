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

# Policy remains mutable after release: packaging must permit the documented
# manual -> canary -> fleet stages without changing the immutable bundle.
grep -Fqx "POLICY_SCHEMA='1'" "$ROOT/rollout-policy.conf"
policy_tag="$(sed -n "s/^RELEASE_TAG='\([^']*\)'$/\1/p" "$ROOT/rollout-policy.conf")"
policy_rollout="$(sed -n "s/^ROLLOUT='\([^']*\)'$/\1/p" "$ROOT/rollout-policy.conf")"
case "$policy_tag:$policy_rollout" in
    v1.5.4:manual|v1.6.0:manual|v1.6.0:canary|v1.6.0:fleet) ;;
    *) echo "unexpected policy for the 1.6.0 rollout-test bundle" >&2; exit 1 ;;
esac

grep -Fq 'HOME_NET_SKIP_VERSION_RECORD' "$ROOT/install-all.sh"
grep -Fq 'if [ "${HOME_NET_SKIP_VERSION_RECORD:-0}" != "1" ]; then' "$ROOT/install-all.sh"

echo "PASS candidate_packaging_1_6_0"
