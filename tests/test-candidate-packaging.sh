#!/bin/sh
set -eu

ROOT="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"

bundle_version="$(tr -d '\r\n' < "$ROOT/VERSION")"
monitoring_version="$(tr -d '\r\n' < "$ROOT/MONITORING_VERSION")"
[ "$bundle_version" = "1.7.14" ]
[ "$monitoring_version" = "1.7.9" ]

grep -Fqx "HOME_NET_BUNDLE_VERSION='1.7.14'" "$ROOT/bundle.conf"
grep -Fqx "MONITORING_VERSION='1.7.9'" "$ROOT/bundle.conf"

bootstrap_ref="$(sed -n "s/^MONITORING_BOOTSTRAP_REF='\([^']*\)'$/\1/p" "$ROOT/bundle.conf")"
printf '%s\n' "$bootstrap_ref" | grep -Eq '^[0-9a-f]{40}$'
# The released entry point and policy advance together; rollout stays manual.
grep -Fq "HOME_NET_RELEASE_REF:-v1.7.14" "$ROOT/install.sh"
grep -Fq "HOME_NET_BUNDLE_REF:-v1.7.14" "$ROOT/install-all.sh"
grep -Fq 'downloading v1.7.9' "$ROOT/install.sh"
# A new bundle must never silently bootstrap the preceding native agent.
# The immutable v1.7.14 archive pin is deliberately a release gate.
grep -Fq 'releases/download/v1.7.14/home-net-native-agent-1.7.14-linux-arm64.tar.gz' "$ROOT/control-agent/install-native.sh"
grep -Fq "grep -Fxq 'version=1.7.14'" "$ROOT/control-agent/install-native.sh"


# Policy remains mutable after release: packaging must permit the documented
# manual -> canary -> fleet stages without changing the immutable bundle.
grep -Fqx "POLICY_SCHEMA='1'" "$ROOT/rollout-policy.conf"
policy_tag="$(sed -n "s/^RELEASE_TAG='\([^']*\)'$/\1/p" "$ROOT/rollout-policy.conf")"
policy_rollout="$(sed -n "s/^ROLLOUT='\([^']*\)'$/\1/p" "$ROOT/rollout-policy.conf")"
case "$policy_tag:$policy_rollout" in
    v1.6.0:manual|v1.5.4:manual|v1.7.4:manual|v1.7.4:canary|v1.7.4:fleet|v1.7.5:manual|v1.7.5:canary|v1.7.5:fleet|v1.7.6:manual|v1.7.6:canary|v1.7.6:fleet|v1.7.9:manual|v1.7.9:canary|v1.7.9:fleet) ;;
    v1.7.11:manual|v1.7.13:manual|v1.7.14:manual) ;;
    *) echo "unexpected release rollout policy" >&2; exit 1 ;;
esac

grep -Fq 'HOME_NET_SKIP_VERSION_RECORD' "$ROOT/install-all.sh"
grep -Fq 'if [ "${HOME_NET_SKIP_VERSION_RECORD:-0}" != "1" ]; then' "$ROOT/install-all.sh"

echo "PASS candidate_packaging_1_7_13_manual"
