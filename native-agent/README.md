# Native router agent (candidate)

This is a Go replacement for the router-side Python agent, slot preparer,
persistence helper and slot rebinder. It preserves the existing HTTPS endpoints,
Python-compatible canonical HMAC messages, age X25519 identity/envelopes,
controller transactions, receipts and UCI option names. The official
`filippo.io/age` library is linked into the binary: no router-side Python,
`age` executable or `age-keygen` executable is needed.

The panel protocol is unchanged. Existing identities/credentials are retained.
The native package installs a modified copy of the reviewed shell controller
and Cudy adapter, changing only the persistence-helper executable name and the
decryption invocation. It does not replace Failover, Monitoring or firmware.

## Candidate status

Release candidate 0.1.0-rc1, not installed on hardware. Linux race-enabled tests,
installer fault tests, go vet and the static ARM64 build passed at source commit
8450719c9b5433a04febef61a6d5dbe02612a9cb. The binary measured 6,881,404 bytes;
each new candidate must pass CI again. Existing Python files remain in
the repository as regression oracles, but are not deployed by the native package.
Do not infer installation success from compilation or from synthetic crypto tests.

## Build and review

Go 1.27.3; age v1.3.2; versions and sums are pinned in go.mod/go.sum.

```
cd native-agent
go test -race -count=1 ./...
go vet ./...
sh build-package.sh
```

The workflow builds Linux ARM64 with CGO disabled and stripped debug information.
`dist/native-agent-arm64` contains fixed runtime files and SHA256SUMS. No device
configurations, user keys, tokens, profiles or local reports enter the artifact.

## CLI and boundaries

- `version`, `self-test`: no device state or network access.
- `identity-init`, `recipient`: generate once/read the existing local identity;
  only the public recipient may be printed.
- `agent`, `agent --loop`: existing register/poll/result protocol, fixed panel
  certificate hostname, physical-WAN socket binding and direct configured IP.
  Proxy and HTTP redirects are disabled. Errors never print command output,
  credentials or decrypted profiles.
- `prepare-slots [ROLE [--backup2]]`: disabled-slot preparation under the shared
  maintenance lock, with private baseline, conflict/transaction checks and no
  network reload or route selection.
- `persist ...`: existing persistence/restore/order interface, requiring the
  inherited controller FD 9 to reference the shared maintenance lock.
- `rebind JSON`: fixed snapshot-bound permutations under the maintenance lock,
  with backups, rollback records, post-change identity/egress verification and
  preservation of unrelated concurrent configuration edits.
- `decrypt INPUT OUTPUT`: only private temporary paths beneath /tmp, bounded
  ciphertext/plaintext, authenticated age decryption, exclusive 0600 output.

Root is required except for version/self-test. Production CLI has no test-root,
arbitrary command, server URL or shell-execution option. Unit tests inject
filesystem roots and command runners directly in Go; those controls are not
exposed through config, environment variables or the network protocol.

## Installation

The separate installer requires `--preflight` or `--install`, verifies the fixed
manifest, synthetic crypto self-test, architecture, known prior file hashes,
transaction state, maintenance lock and space for staging plus backups. Its
512 KiB allowance is for completing the current install, not a promise of future
update capacity; the user explicitly waived a future-update reserve.

It backs up old managed code, preserves private identities and configuration,
stages code before stopping an old agent, and can restore old code on failure.
The installed agent can execute existing panel jobs; review assignment/plan and
transaction state before enabling it on a real router. Installer startup itself
does not change LAN/WAN or restart Podkop/sing-box/network.

This candidate still requires hardware validation of enrollment, polling,
resource use and rollback before a stable release. No change to the published v1.7.9 tag/assets or fleet rollout policy
is part of this work.
