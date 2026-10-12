# v1.7.3: LuCI request lifetime and first-upgrade compatibility

The installed rpcd was confirmed on 2026-10-13 with timeout 30 and runtime
`/sbin/rpcd ... -t 30`. The operator's v1.7.2 attempt took longer than one minute.
Read-only SSH found all Monitoring verification checks PASS, while the version
record remained 1.6.0/FAILED and no new updater backup appeared. Historical
stderr was not retained, so an exact failing command for this attempt is not
proven. A 30-second RPC deadline is a confirmed additional transport limit.

rpcd file.c kills its immediate command process on timeout and then closes
stdout/stderr readers. Its descendants can survive; later output through those
pipes fails. v1.7.2 prevented a restart of rpcd but did not protect the installed
1.6.0 updater's synchronous first-upgrade path from request expiration.
Source: https://github.com/openwrt/rpcd/blob/master/file.c.

## Two compatibility layers

1. In management context the bundle opens a unique root-owned 0600 journal
   before any downloads or installation and redirects its stdout/stderr there.
   This works under the existing installed updater; it does not require replacing
   that updater first. The full Monitoring/bootstrap output and bundle exit
   status survive RPC expiration. Journal: `/root/home-net-luci-install-*.log`.
2. The new management backend validates the confirmed target and CRITICAL
   restriction, then starts a nohup worker with stdin disconnected and output
   redirected to a private job log. It returns immediately. The worker invokes
   the actual updater, which remains the sole owner of locking, preflight,
   backup, rollout/class restrictions, health and Installed/Active records.

The Updates page polls both authoritative version state and worker status.
QUEUED/RUNNING are distinct from SUCCEEDED/FAILED; a zero process exit alone
cannot mark success unless Installed/Active match the confirmed target and
UPDATE_STATUS is OK. Dead workers report INTERRUPTED. A failed updater retains
its exit code and output. Pending CRITICAL actions are not enabled by this UI.

On the first 1.6.0 -> 1.7.3 upgrade the already-loaded older LuCI request may
still time out: updating server files cannot replace a request already running.
Refresh Updates to read the final Installed/Active and health state. Do not
retry solely because the old request timed out. Future launches use the new
background worker and progress view. No rpcd timeout or production policy
change is required.

## Validation boundary

`installed-updater-1.6.0` is the allowed read-only snapshot of the updater actually
present on the target before these upgrades. It contains source only, not config,
credentials or live state. Its logical version record was 1.6.0; its source may
include previously staged canary code. It is used verbatim in the regression.

The integration fixture executes that snapshot -> real bundle -> real archive
bootstrap -> real Monitoring installer in an isolated filesystem. Downloads,
service control and networking are fixture replacements. A deterministic gate
models expiration of the 30-second request: kill only the immediate management
process and close an actual FIFO reader while the updater child is active.
It checks both final successful 1.7.3/OK records and failed health leaving
1.6.0/FAILED, with complete private logs. This models the timeout process
boundary rather than waiting 30 real seconds in each test.

Worker tests check prompt return while an updater is still blocked, success and
failure readback, exit 23 retained, log permissions, and unchanged target and
CRITICAL refusal. These are offline tests. Hardware acceptance still requires
an operator-triggered LuCI installation on cudy-backup, fresh health OK and a
separately authorized reboot check. Main-router installation remains prohibited.
