# Router VPN deployment transaction

Install the router helper and manifest validator side by side for lab use. This PR provides the transaction runner and a test adapter. A Cudy adapter for the actual netifd, AmneziaWG, Failover and Podkop configuration is required before hardware use. The helper refuses to operate without the adapter.

Use a root-owned, mode 0700 /etc/home-net/vpn directory. Provision router-id, a mode 0600 age-identity.txt for this router, and an executable adapter. The NAS encrypts each payload for this router, NAS and offline recovery. Only the router's payload is decrypted in a private /tmp directory. The persistent backup may contain VPN secrets. Keep it on the router and out of Git.

## Adapter contract

All verbs run synchronously and return nonzero on failure. Only active writes to stdout. The adapter must coordinate with other network writers, including Failover, and fail closed if it cannot guarantee isolation.

| Verb and arguments | Required behavior |
| --- | --- |
| active | Print exactly awg_main or awg_backup |
| validate TARGET PLAINTEXT | Parse and validate the complete AWG config, reject hooks and unsupported directives, and make no network changes |
| snapshot PREVIOUS TARGET BACKUP_DIR | Capture restorable target config and previous routing policy in the private backup directory |
| stage PREVIOUS TARGET PLAINTEXT | Recheck active slot, apply only the candidate with isolated routing and no default-route or Podkop changes |
| verify PREVIOUS TARGET COUNTRY | Verify the staged configuration has not drifted, a fresh candidate handshake and interface-bound HTTPS/egress/country checks pass, and Podkop/sing-box are healthy |
| promote PREVIOUS TARGET | Switch traffic to the verified target, preserving the previous slot and checking for drift before changing policy |
| check-promoted TARGET COUNTRY | Verify active routing, handshake, HTTPS/egress/country and Podkop/sing-box health |
| restore PREVIOUS TARGET BACKUP_DIR | Idempotently restore previous traffic and the target's baseline config, even after partial stage or promotion |
| check-restored PREVIOUS TARGET BACKUP_DIR | Confirm previous traffic health and restored target config |

## Operator flow

Take SHA256 of SHA256SUMS from an independently authenticated immutable Git commit. Pass the digest to `home-net-vpn-router prepare BUNDLE DIGEST`. The helper verifies the manifest and selected ciphertext, then checks the manifest slot is inactive. Run `verify` before explicit `promote`. Promotion repeats verification and attempts rollback on failed promotion or failed post-check. Run `rollback` to restore from the persistent record.

One transaction is retained for recovery. After a successful rollback, archive the root-only transaction directory outside Git before starting another. An interrupted operation can leave a lock. Confirm no operation remains in flight before removing the stale lock and running rollback. Inspect the backup and phase locally. No boot-time recovery, automatic promotion, installer wiring or rollout is enabled by this PR.
