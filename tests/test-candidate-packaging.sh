#!/bin/sh
set -eu

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"

bundle_version="$(tr -d '\r\n' < "$ROOT/VERSION")"
monitoring_version="$(tr -d '\r\n' < "$ROOT/MONITORING_VERSION")"
[ "$bundle_version" = "1.8.0" ]
[ "$monitoring_version" = "1.8.0" ]

grep -Fqx "HOME_NET_BUNDLE_VERSION='1.8.0'" "$ROOT/bundle.conf"
grep -Fqx "MONITORING_VERSION='1.8.0'" "$ROOT/bundle.conf"
grep -Fqx "FAILOVER_VERSION='1.4.2'" "$ROOT/bundle.conf"

bootstrap_ref="$(sed -n "s/^MONITORING_BOOTSTRAP_REF='\([^']*\)'$/\1/p" "$ROOT/bundle.conf")"
updater_ref="$(sed -n "s/^HOME_NET_UPDATER_REF='\([^']*\)'$/\1/p" "$ROOT/bundle.conf")"
failover_ref="$(sed -n "s/^FAILOVER_REF='\([^']*\)'$/\1/p" "$ROOT/bundle.conf")"
for ref in "$bootstrap_ref" "$updater_ref" "$failover_ref"; do
    printf '%s\n' "$ref" | grep -Eq '^[0-9a-f]{40}$'
done

grep -Fq "HOME_NET_RELEASE_REF:-v1.8.0" "$ROOT/install.sh"
grep -Fq 'downloading v1.8.0' "$ROOT/install.sh"
grep -Fq 'HOME_NET_BUNDLE_REF:-v1.8.0' "$ROOT/install-all.sh"
grep -Fq 'FAILOVER_REF must be a full commit SHA' "$ROOT/install-all.sh"

# Policy is deliberately not advanced before hardware canary. Preserve the
# current stable/manual policy while permitting the documented future stages.
grep -Fqx "POLICY_SCHEMA='1'" "$ROOT/rollout-policy.conf"
policy_tag="$(sed -n "s/^RELEASE_TAG='\([^']*\)'$/\1/p" "$ROOT/rollout-policy.conf")"
policy_rollout="$(sed -n "s/^ROLLOUT='\([^']*\)'$/\1/p" "$ROOT/rollout-policy.conf")"
case "$policy_tag:$policy_rollout" in
    v1.6.0:manual|v1.5.4:manual|v1.7.4:manual|v1.8.0:manual|v1.8.0:canary|v1.8.0:fleet) ;;
    *) echo "unexpected policy for the v1.8.0 candidate" >&2; exit 1 ;;
esac

grep -Fq 'HOME_NET_SKIP_VERSION_RECORD' "$ROOT/install-all.sh"
grep -Fq 'if [ "${HOME_NET_SKIP_VERSION_RECORD:-0}" != "1" ]; then' "$ROOT/install-all.sh"

echo "PASS candidate_packaging_1_8_0"
