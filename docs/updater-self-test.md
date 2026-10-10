# HOME NET updater self-test

Run `home-net-update self-test` (or `sh scripts/home-net-update self-test` from a checkout).
Exit status is zero only when all checks pass; output includes individual PASS/FAIL
results and a total. No downloads, installation, apply, reboot or service commands
are executed. Operator configuration is not sourced. Fixtures use a private
temporary directory which is removed on exit. Real updater state, health files,
rollout cache, locks and backups are not touched.

The self-test calls the same rollout policy parser, health evaluator and activation
planner as the updater. It covers manual, canary on both rings, fleet on both rings,
invalid policy, release mismatch, disabled capability, unsupported fields, unhealthy
or incomplete health, SAFE, CONTROLLED and CRITICAL decisions. CRITICAL must stage
and retain the previous active version with PENDING_APPLY. No local bundle override
or production test mode is introduced.

CONTROLLED uses the existing runtime preflight after its shared activation decision.
The offline command tests that decision and health gate; it does not claim to test
live WAN routes, VPN state, service coordination, installation or reboot recovery.
The mocked updater integration suite covers these existing execution paths.

Validation:

```sh
sh -n scripts/home-net-update
sh tests/test-home-net-update-self-test.sh
sh tests/test-home-net-update.sh
sh tests/test-install-all-safety.sh
git diff --check
```

This addition belongs to the PR candidate. It does not publish a release or change
the stable v1.5.4 tag or any router installation. The existing installer distributes
the updater as one file, so self-test needs no new installation payload.

## Verification record — 2026-10-10

On Windows using Git-for-Windows shell:

- Shell syntax checks passed for updater and new test script.
- Self-test: 36 passed, 0 failed.
- Isolation and deliberately broken SAFE gate detection: both passed.
- Existing updater suite: all 30 scenarios passed, including pending/reconcile,
  failed health, failed installation and rollout policy failures.
- Existing install-all safety suite: all 15 checks passed.
- `git diff --check` passed.

No live OpenWrt/BusyBox or router checks were performed. Runtime route/VPN/service
behavior remains subject to a separately authorized canary validation.
