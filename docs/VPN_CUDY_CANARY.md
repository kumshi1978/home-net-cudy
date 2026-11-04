# Cudy lab adapter

The adapter implements the VPN transaction contract for existing netifd AmneziaWG slots on Cudy. It changes the candidate with runtime `awg syncconf` and selects the active slot through Podkop's runtime UCI setting. It does not commit network or Podkop configuration. Runtime changes can be lost on reboot or netifd reload. Verify the actual state after an interruption before using rollback.

## Prerequisites for a separately authorized backup Cudy canary

- Use a dedicated maintenance window, a wired management path and the exact candidate bundle from a reviewed commit. Record the active slot and health baseline locally. Keep all snapshots private.
- Confirm that both kernel interfaces are already provisioned as `awg_main` and `awg_backup`. The candidate must work with the existing target address and netifd routing policy. Test a replacement that requires a different interface address or routing policy separately.
- Use a single-peer AWG `syncconf` payload. Review the original export against the existing interface first. Keep Address, DNS, MTU, route settings and hooks outside this payload. Preserve the AmneziaWG peer and obfuscation settings, then encrypt on NAS using the existing three-recipient model.
- Confirm the Podkop section that owns the VPN and put its UCI section name in the root-only `/etc/home-net/vpn/podkop-section` file. Install the reviewed adapter as `/etc/home-net/vpn/adapter`. The deployment helper and validator must be installed side by side.
- Stop and disable `podkop-awg-failover`, `podkop-health` and `podkop-late-start` for the maintenance window. The adapter refuses registered procd services, enabled init scripts and detected writer processes. Also exclude concurrent LuCI, updater and manual network changes for the whole transaction. Restore the recorded service state after rollback.
- Check that `awg`, `curl`, `uci`, `ubus`, `timeout` and the Podkop init script work on the exact OpenWrt image. Ensure the clock is synchronized.

## Acceptance

1. Prepare the inactive slot using the trusted checksum-list digest. Confirm Podkop still selects the original slot and that its traffic remains healthy.
2. Verify the candidate. The adapter requires an interface-bound HTTPS IPv4 egress response, a handshake newer than staging and at most 180 seconds old, the expected country from a second interface-bound HTTPS request, and Podkop/sing-box/local DNS health. A mismatch blocks promotion.
3. Promote explicitly. Confirm the router selects the candidate and check traffic from a LAN client through Podkop. The adapter checks process and DNS health on-router. The LAN check is separate.
4. Roll back and verify the original slot, previous target fingerprint and LAN traffic. Repeat rollback to check idempotence. If rollback returns an error, keep the backup and recover with the wired management path before restoring scheduled services.

This canary exercises runtime changes only. Persistent provisioning and Failover re-enablement with a promoted candidate need separate validation.
