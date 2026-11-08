# Control agent dependency preflight

The agent needs `python3-light`, `python3-openssl`, `python3-email` and
`python3-urllib`, plus working `age` and `age-keygen`. Do not install the full
`python3` metapackage. `python3-ssl` is not the SSL package in the reviewed
OpenWrt 24.10 feed. Check all imports used by the agent, slot preparation and
controller before runtime installation, including `ast`, `http.client`,
`email.parser`, `urllib.parse`, `ssl` and `fcntl`.

The pinned control installer supports:

- `--preflight`: refresh/resolve package metadata and check space; do not install
  packages, generate identities, install controller files or restart services.
- `--prepare-dependencies`: perform that preflight, install missing dependencies,
  and verify imports/tools. Do not change runtime components or enroll devices.
- No arguments: prepare dependencies, then run the existing agent installation.

The bundle invokes `--prepare-dependencies` before Failover, Monitoring, updater
installation or SSH enrollment. A missing dependency aborts at this boundary.
Successfully installed dependencies are not automatically removed if a later
step fails. This is not an atomic package transaction or runtime rollback.

For opkg, the preflight reads installed state and current repository records,
resolves transitive dependencies and Provides, counts each new package once,
and requires the sum of Installed-Size plus 4096 KiB of writable-flash reserve.
Missing packages, unknown sizes, invalid dependencies and failed index refresh
abort before package installation. Archive download sizes are not treated as
installed space. Package indices and plans are temporary files in RAM.

For apk, resolve using `apk add --simulate` first. Until exact installed-size
planning is supported for the relevant APK metadata generations, require a
conservative 32 MiB dependency budget plus the same 4 MiB reserve when any
dependencies are missing. Already working dependencies need only the reserve.

No alternative package feeds, unpinned binaries, cryptographic implementations
or automatic storage cleanup are introduced. If the official feed lacks age,
the installer stops and requires an independently reviewed provisioning path.

## Main Cudy finding, 9 November 2026

OpenWrt 24.10.4, aarch64_cortex-a53: current official indices lack `age`. The
compact Python closure is 16,711,680 bytes Installed-Size before age and agent
files. The main router has 17,682,432 bytes free after the authorized cleanup.
It cannot pass the 4 MiB reserve gate with that missing dependency set. The
fixed installer must refuse this device before touching runtime; it does not
claim that dependency renaming alone makes 1.7.9 fit.

The published v1.7.9 tag/assets stay immutable. This change is a candidate for
a subsequent reviewed release; hardware installation has not been performed.
