# HOME NET VPN NAS controller

The NAS is the deployment orchestrator and local backup point.

## Recommended layout

```
/volume1/docker/home-net-vpn/
  config/recipients.conf
  keys/
  incoming/
  repo/
  backups/
  state/
  logs/
```

`recipients.conf` contains public age recipients only.
Private age identities belong in `keys/`, mode 0600, and must never be committed.

## Incoming package

Place these files in a NAS-local temporary directory:

```
manifest.conf
apartment-main.conf
apartment-backup.conf
dacha-main.conf
dacha-backup.conf
```

Each router must have a separate AmneziaWG client/peer.

## Prepare encrypted Git-ready package

```
home-net-vpn-import \
  --source /volume1/docker/home-net-vpn/incoming/de-vds-20261104 \
  --recipients /volume1/docker/home-net-vpn/config/recipients.conf \
  --output /volume1/docker/home-net-vpn/repo/deployments/de-vds-20261104
```

Then verify:

```
home-net-vpn-bundle-verify /volume1/docker/home-net-vpn/repo/deployments/de-vds-20261104
```

Only after PASS may the output directory be committed to the private secrets repository.

The output contains only:

- non-secret `manifest.conf`;
- four `.conf.age` files;
- `SHA256SUMS`.

Plaintext router configs are never copied into the Git-ready output.

## Recipient model

Each router config is encrypted for exactly these trust roles:

1. NAS deployment recipient;
2. that router's own recipient;
3. offline recovery recipient stored in the password manager.

This lets the NAS deploy any router, lets a router recover only its own config, and preserves an offline recovery path.

## Current scope

This phase does not connect to routers and does not modify `awg_main`, `awg_backup`, Podkop, rollout policy or AutoApply.
Router prepare/verify/promote/rollback is a later phase.
