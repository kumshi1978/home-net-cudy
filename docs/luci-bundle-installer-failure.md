# LuCI bundle upgrade failure, v1.7.0 / v1.7.1

## Evidence and scope

Read-only SSH diagnostics on cudy-backup (OpenWrt 25.12.5), 2026-10-12,
confirmed Installed/Active 1.6.0 with a FAILED v1.7.1 attempt. The target manifest
pins Monitoring to 04787c2bc2fd0e5be2efcb561f08c56130c3a480. The saved Monitoring
verification log contains only `WAIT: no new completed health cycle available`.
The installer failed in the same second that Monitoring/logging started, well
before its 600-second verification deadline. No installation, rollback, service
restart, reboot or policy change was performed during this investigation.

## Failure mechanism

LuCI `fs.exec` calls `home-net-management install-latest`, which synchronously
calls `home-net-update apply`, `install-all.sh`, the archive bootstrap, and the
Monitoring installer. These descendants inherit rpcd's output pipes.

Monitoring unconditionally restarted `/etc/init.d/rpcd` before verification.
The old rpcd process owns the read ends of these pipes. Its restart closes them;
the next installer output cannot be delivered. In the observed waiting path,
the next stdout command is:

```sh
echo 'Waiting for a completed healthy cycle after initialization (timeout: 600 seconds)'
```

The local fixture reproduces this boundary with a real FIFO and a reader stopped
by the mock rpcd restart. Ignored SIGPIPE models rpcd's signal disposition:
the echo returns a write error and `set -e` exits. The device did not retain the
original exit code/stderr, so the historical exact signal/code is inferred from
the matching failure boundary, not directly recorded on the router.

rpcd `main.c` ignores SIGPIPE and uses SIGHUP to exec itself; changing restart
to reload would also replace the process and would not solve the active request.
Sources: https://github.com/openwrt/rpcd/blob/master/main.c and
https://github.com/openwrt/rpcd/blob/master/exec.c.

The prior hardware canary ran the bundle from SSH with stage-only and
skip-version-record flags, then performed separate checks. Its output reader
was SSH, not rpcd. Offline fixtures redirected output to a regular file and
mocked rpcd without closing the reader. Neither covered this failure path.

## Fix and limits

During `HOME_NET_UPDATE_IN_PROGRESS=1`, Monitoring leaves rpcd running. Both the
old installed updater and the new updater already propagate this flag through
the complete installer chain, so the fix applies on the first upgrade from 1.6.0.
Direct SSH/bootstrap installation retains its existing rpcd restart behavior.
Installed root LuCI sessions can continue using the existing management ACL;
updated session permissions are read on a new login. Health, lifecycle, runtime
permissions and LuCI file checks remain mandatory.

The new updater saves child stdout/stderr to a 0600 `bundle-install.log` in its
existing backup and reports the actual nonzero exit code and log path. This
additional diagnostics behavior becomes available after that updater is installed;
the current 1.6.0 updater is not modified manually.

No rollback claim about installed component files follows from the unchanged
version record: Monitoring files may already have been copied before failure.
Current read-only health reported UNKNOWN for service checks, while Podkop,
sing-box and FakeIP remained RUNNING/RUNNING/OK. This does not establish a
network defect; it can independently block the next install's health gate.

Hardware acceptance still requires an operator-triggered install through LuCI,
Installed/Active matching the target, a fresh complete OK cycle and separately
authorized reboot verification. Offline PASS is not hardware PASS. The main
router remains outside this task's installation scope.
