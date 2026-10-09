# HOME NET v1.6.0 candidate — hardware canary test

This procedure is for the apartment backup Cudy only. Stable v1.5.4 remains the
production state during the pre-release test.

## Candidate rules

- install only from an exact PR commit;
- use `HOME_NET_SKIP_VERSION_RECORD=1`;
- do not create or modify tag/release v1.5.4;
- local permanent role after the test:
  `HOME_NET_AUTO_UPDATE_CAPABLE='1'`,
  `HOME_NET_ROLLOUT_RING='canary'`;
- pre-release rollout-policy tests may use a local HTTP fixture;
- restore the production policy URL after the fixture tests.

## Expected pre-release behavior

Latest stable is still v1.5.4 and the device production state is v1.5.4.
Therefore the test validates candidate installation, rollout decisions,
fail-closed behavior and LuCI. It cannot validate automatic installation of a
newer release until v1.6.0 is actually published.

Expected gates for a canary router:

| rollout | AutoApply | gate |
| --- | ---: | --- |
| manual | 0 | WAITING FOR CANARY |
| canary | 1 | AUTO APPLY ALLOWED |
| fleet | 1 | AUTO APPLY ALLOWED |
| unavailable/invalid/mismatch | 0 | POLICY BLOCKED |

The rollout policy never bypasses update lock, backup, preflight, action-class
handling or post-update health. CRITICAL keeps disruptive activation pending.
