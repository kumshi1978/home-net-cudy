# HOME NET v1.7.4: independent background Podkop updates

The operator confirmed CURRENT=0.7.22 and LATEST=0.7.24 on cudy-backup.
Podkop updates previously ran synchronously through rpcd, whose configured
30-second limit can close the request before package verification finishes.

The management backend now validates the confirmed upstream target, then
launches a private worker with stdin disconnected, output in a 0600 journal
and SIGHUP ignored using POSIX shell. No external nohup package is required.
The worker runs the existing `home-net-podkop-update update TARGET` transaction.
Checksums, exact assets, rollback-package availability, dependency preflight,
backup inventory, protected configuration checks and fresh lifecycle/health
verification remain inside that transaction. The package transaction itself is
unchanged. A completed HOME NET bundle upgrade does not upgrade Podkop.

Only exit zero plus an observed Podkop version matching the confirmed target
can mark the worker SUCCEEDED. Otherwise it records FAILED, actual version and
exit code; rollback verified/failed diagnostics stay in the job journal.
An unexpectedly dead worker reports INTERRUPTED rather than success.

An atomic launch mutex prevents a race between creating job records. Both
HOME NET and Podkop launches refuse a QUEUED/RUNNING job of either type or a
held shared update lock. The actual updater remains the owner of the mutation
lock, so direct CLI operations still cannot install packages concurrently.
The page disables both update buttons while either job is active.

Updates shows Podkop progress, observed version and an explicit log-read button.
The log endpoint reads only the recorded Podkop job, capped at 200 lines, not
arbitrary user-supplied paths or configuration backups. Job directories remain
private. ACL permissions are unchanged.

## Validation and limits

The new integration suite executes the actual management backend and Podkop
transaction in the existing isolated package/service/network fixture, for both
IPK/opkg and APK/apk branches. The RPC requester returns while a mock package
transaction is held at a gate; its real FIFO output closes. The worker survives
SIGHUP, then finishes the update or verified rollback. Package-manager actions,
service control and HTTP downloads are mocked, not hardware operations.

Cases cover success, install failure, failed health with restoration, and failed
rollback health without a false ROLLBACK VERIFIED claim. Version/configuration
readback and full worker logs are checked. Concurrent Podkop and HOME NET
launches must be rejected without creating another worker. Changed targets and
injection are rejected before a job is created. UI tests exercise progress,
cross-operation button disabling, final version and rollback-log readback.

The existing package/rollback regression suite remains required. Offline PASS
is not proof that actual APK dependencies or rollback will pass on this device.
The real updater will fail closed before package installation if assets,
digests, dependencies or protected configuration are unsupported.

Delivery requires installing HOME NET v1.7.4 first, separately verifying it,
then explicitly approving Podkop's update through LuCI on cudy-backup. Package
installation can restart Podkop and temporarily interrupt connectivity.
No router configuration, rpcd timeout, policy or AutoApply is changed by this
development task. No hardware update or reboot has been performed here.
