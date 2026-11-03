# HOME NET v1.8.0 — Central VPN Deployment

## Goal

Replace a blocked AmneziaWG VDS without editing four Cudy routers by hand.

The design uses two replaceable slots on each router:

- `awg_main`
- `awg_backup`

A new server is always installed into the non-active slot first. Promotion is a separate action.

## Trust model

Encrypted VPN payloads may be stored in a private GitHub repository, but plaintext client configs and private keys must never be committed.

Each router has its own age identity. Every router-specific VPN config is encrypted to three recipients:

1. NAS deployment recipient
2. that router's recipient
3. offline recovery recipient kept in a password manager

Compromise of one router must not reveal configs for the other routers.

## Storage roles

### Private GitHub repository

Recommended name: `home-net-vpn-secrets`.

It stores only encrypted payloads and non-secret metadata.

Example:

```
deployments/de-vds-20261103/
  manifest.conf
  apartment-main.conf.age
  apartment-backup.conf.age
  dacha-main.conf.age
  dacha-backup.conf.age
```

### NAS

The NAS is the orchestrator and local backup location.

Recommended layout:

```
/volume1/docker/home-net-vpn/
  repo/
  keys/
  staging/
  backups/
  state/
  logs/
```

The NAS age identity is stored outside Git and protected with mode 0600.

### Routers

Each router stores only:

- its own age identity
- active AmneziaWG configuration
- inactive slot configuration
- local rollback backup

Recommended identity path:

```
/etc/home-net/keys/age-identity.txt
```

mode 0600.

## Router IDs

Canonical IDs:

- `apartment-main`
- `apartment-backup`
- `dacha-main`
- `dacha-backup`

## Deployment lifecycle

```
import -> validate -> encrypt -> backup -> prepare -> verify -> promote
                                           \-> rollback
```

### prepare

- detect active slot
- choose inactive slot
- save local backup
- install only the target router's encrypted payload
- decrypt locally or via NAS
- apply the inactive interface
- verify handshake
- verify egress IP
- verify country
- verify HTTPS connectivity
- verify Podkop/sing-box compatibility
- do not change active traffic

### promote

Promotion is explicit in the first release.

It is allowed only when the target deployment is READY for the router.

The current active slot is not destroyed. It becomes rollback material.

### rollback

Restore previous slot/configuration and rerun health checks.

## Safety rules

- Never store plaintext VPN configs in Git.
- Never store age private identities in Git.
- Never reuse one AmneziaWG peer across multiple routers.
- Never overwrite both VPN slots in one operation.
- Never promote before prepare/verify succeeds.
- An offline router is PENDING, not a global deployment failure.
- Automatic promotion is out of scope for the first implementation.
- Current HOME NET rollout policy and updater policy remain independent.

## Manifest v1

The initial machine-readable format is POSIX-shell-compatible `manifest.conf` so it can be parsed on OpenWrt without Python/YAML dependencies.

Required keys:

```
FORMAT_VERSION='1'
DEPLOYMENT_ID='de-vds-20261103'
CREATED_AT='2026-11-03T20:00:00Z'
COUNTRY='DE'
TARGET_SLOT='awg_main'
ROUTERS='apartment-main apartment-backup dacha-main dacha-backup'
```

Optional non-secret keys:

```
PROVIDER='example'
SERVER_LABEL='de-primary-20261103'
REASON='provider_block'
PREVIOUS_DEPLOYMENT='de-vds-20261001'
```

No private key, preshared key, password or raw Amnezia config is allowed in the manifest.

## Phase plan

Phase 1:
- manifest contract
- validator
- tests
- encryption/storage contract

Phase 2:
- NAS import/encrypt controller
- GitHub private repo integration
- per-router recipient registry

Phase 3:
- router prepare/verify/rollback helper
- detached deployment operations

Phase 4:
- LuCI VPN deployment page
- READY/PENDING/FAILED status
- Promote and Rollback controls

Phase 5:
- hardware validation on apartment backup Cudy
- then staged validation on remaining routers
