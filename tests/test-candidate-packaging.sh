#!/bin/sh
set -eu

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"

bundle_version="$(tr -d '\r\n' < "$ROOT/VERSION")"
monitoring_version="$(tr -d '\r\n' < "$ROOT/MONITORING_VERSION")"
[ "$bundle_version" = "1.7.1" ]
[ "$monitoring_version" = "1.7.1" ]

grep -Fqx "HOME_NET_BUNDLE_VERSION='1.7.1'" "$ROOT/bundle.conf"
grep -Fqx "MONITORING_VERSION='1.7.1'" "$ROOT/bundle.conf"

bootstrap_ref="$(sed -n "s/^MONITORING_BOOTSTRAP_REF='\([^']*\)'$/\1/p" "$ROOT/bundle.conf")"
printf '%s\n' "$bootstrap_ref" | grep -Eq '^[0-9a-f]{40}$'
grep -Fq "HOME_NET_RELEASE_REF:-v1.7.1" "$ROOT/install.sh"
grep -Fq 'downloading v1.7.1' "$ROOT/install.sh"

# Policy remains mutable after release: packaging must permit the documented
# manual -> canary -> fleet stages without changing the immutable bundle.
grep -Fqx "POLICY_SCHEMA='1'" "$ROOT/rollout-policy.conf"
policy_tag="$(sed -n "s/^RELEASE_TAG='\([^']*\)'$/\1/p" "$ROOT/rollout-policy.conf")"
policy_rollout="$(sed -n "s/^ROLLOUT='\([^']*\)'$/\1/p" "$ROOT/rollout-policy.conf")"
case "$policy_tag:$policy_rollout" in
    v1.6.0:manual|v1.5.4:manual|v1.7.1:manual|v1.7.1:canary|v1.7.1:fleet) ;;
    *) echo "unexpected policy for the 1.7.1 rollout-test bundle" >&2; exit 1 ;;
esac

grep -Fq 'HOME_NET_SKIP_VERSION_RECORD' "$ROOT/install-all.sh"
grep -Fq 'if [ "${HOME_NET_SKIP_VERSION_RECORD:-0}" != "1" ]; then' "$ROOT/install-all.sh"

echo "PASS candidate_packaging_1_7_1"
