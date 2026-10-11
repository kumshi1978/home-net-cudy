# HOME NET v1.7.0 — LuCI Management Dashboard & Operations Center

Candidate only. This PR does not merge, publish a release, change existing tags/releases,
modify central production policy, or install anything on a router.

## Scope and navigation

Services → HOME NET opens Overview. Updates, Logs, VPN and Settings are children.
The old HOME NET entry and existing limited controls remain available.
This is the same local management application on each of the four Cudy, not a remote
RPC aggregator. It never guesses another router's state or exposes its credentials.
A single cross-router dashboard requires a separate authenticated remote API design.

Overview shows System, VPN, Podkop, Sing-box, FakeIP, Monitoring and Updates cards,
last monitoring timestamp, known problem description and a details link.
Missing fields remain unknown. The system card reflects a readable uptime signal;
it is not a full system health assessment. Historical problems are displayed separately
from the current monitoring result. Historical events retain their original timestamp,
component and message; a historical failure is not presented as an active outage.

VPN displays active interface, public IP/country, tunnel countries and handshake ages.
Connected means an active known AWG interface has a handshake no older than 180 seconds;
it is not proof that every destination is reachable. Backup activation is labelled
Failover active. A missing handshake is unknown. FakeIP cache size is bytes in the
known runtime cache.db path when available, otherwise unknown. Error details unavailable
in the existing health snapshot remain unknown rather than being fabricated.
Health Score is intentionally not calculated until a measurable model exists.

## Visual status layer

Green: OK, RUNNING, healthy, Connected, AUTO APPLY ALLOWED.
Yellow: unknown, warnings, WAITING FOR CANARY / FLEET, historical events.
Red: failed health/update, invalid or blocked policy, unavailable VPN.
Blue: INSTALLING, VERIFYING, pending operations and manual intervention.
Colors and labels are presentation only. No backend authorization uses a color.

## Decision model

Git policy at main/rollout-policy.conf remains separate from immutable release payloads.
It must be valid and match the discovered release tag. Missing/malformed/mismatched
policy denies automatic installation. Manual denies both rings (WAITING FOR CANARY);
canary allows only canary (stable: WAITING FOR FLEET); fleet allows both.
AUTO_UPDATE_CAPABLE=0 always denies. Local enabled/mode/time/window can only add vetoes.
CRITICAL is denied in the automatic path, including legacy daemon apply.
The discovered manifest class is displayed and an unknown class fails closed.
A second class guard immediately before installation protects against metadata races.

Local settings cannot write capability, permanent ring or central policy URL.
The read ACL permits only the status backend; write ACL separately permits the strict
management/control backends. No general shell execution or arbitrary file write is granted.

## Local settings

Settings writes only these keys to /etc/home-net-update.conf:

- HOME_NET_AUTO_UPDATE_ENABLED: 0/1
- HOME_NET_UPDATE_MODE: check/apply
- HOME_NET_UPDATE_TIME: local HH:MM daily scheduling anchor
- HOME_NET_UPDATE_WINDOW_START / END: HH:MM, inclusive start and exclusive end
- HOME_NET_UPDATE_JITTER: seconds in the file, minutes in the UI (0–1440)

An overnight window is supported. Equal endpoints mean all day; automatic eligibility
then starts at UPDATE_TIME. For a bounded window the daily anchor and jitter should fall
inside that window. Scheduling outside it results in a veto, never a bypass.
The scheduler recalculates daily delay with the router's local clock and deterministic
cohort jitter. A schedule already passed runs the next day. Existing v1.6.0 configs
without the new enabled key preserve their rollout behavior until Settings is saved;
the UI labels this compatibility mode. Fresh v1.7.0 configs default disabled/check-only.
Saving is serialized with the updater lock, creates a private backup, validates syntax
and atomically replaces the config. The daemon reloads gates in child commands and timing
at its next scheduling decision; a sleeping daemon is not forcibly interrupted.

## Manual HOME NET update

Check for update refreshes updater status and loads target/class from the release.
Install latest release shows current, target and class before confirmation.
SAFE and CONTROLLED use the actual updater apply path, not a separate installer.
Target is checked again after discovery. CONTROLLED retains additional WAN/VPN/recovery
preflight requirements. CRITICAL has no LuCI install path: Manual intervention required.
The privileged CLI retains explicit CRITICAL staging for operator recovery; it does not
activate automatically. This preserves pending/reboot reconciliation compatibility.
An explicit manual SAFE/CONTROLLED operation is independent of automatic rollout permission,
as in v1.6.0, but cannot bypass live lock, pre-install health, backup failure, disruptive
payload checks, CONTROLLED preflight or fresh post-install health. There is no force API.

## Independent Podkop operation

Podkop is not upgraded as part of the HOME NET bundle UI action.
Check uses official itdoginfo/podkop release metadata. Update requires a confirmed exact
tag, stable metadata, SHA256 digests for both podkop and luci-app-podkop assets, installed
Podkop version, rollback assets with digests, complete current health and the shared lock.
IPK/APK package managers are supported with a dry-run plan. A plan that changes dependencies
or cannot be understood is rejected. No feed refresh, VPN/AWG installer, network restart
or routing-policy command is issued. APK local assets require allow-untrusted because
upstream release packages are outside repository signatures; exact GitHub digests are
mandatory instead. This does not alter APK's global trust configuration.

Before replacement, private backups contain /etc/config/podkop, /etc/config/network,
/etc/sing-box/config.json, the sing-box directory, known runtime state, health snapshot,
old exact packages and the package plan. Missing config/rollback assets cause refusal.
An upstream package that changes protected podkop/network inputs triggers rollback.
Fresh health and actual version are checked after restart. Installation/health failures
attempt package and configuration rollback. Interruptions after mutation also attempt
rollback. A rollback failure is reported for operator intervention and keeps the backup;
it must not be described as successful recovery. Package scripts remain upstream code:
mock tests do not prove hardware compatibility or absence of transient side effects.
Hardware canary validation is mandatory before enabling this feature in production.

## Logs and diagnosis

Newest first by default; switch to oldest first. Component/severity filters, bounded
50/100/250/500 rows, Refresh, and auto refresh off/5/30/60 seconds.
Clear view only clears the DOM; it never deletes logs. Background polling is registered
through LuCI poll so it is cleaned up with the view. Read errors are displayed.
Known password/token/private-key fields are redacted; this is not a general secret scanner.
Review logs before exporting/sharing. Backup files must never be returned by the status API.

## Rollback and hardware validation

Settings: inspect its private backup, restore the original config as an operator and
reload the updater at an approved maintenance time. Do not restore keys from the UI.
Bundle rollback remains an operator procedure using the updater's recorded backup;
failed activation does not silently advance Active. No downgrade button is added.
Podkop: use the recorded old packages and config backups if automatic rollback fails.

Before merge test the candidate on the backup Cudy only, with production gates disabled
and a recoverable snapshot. Verify all views, read/write ACL separation, local disabled
+ Git canary, enabled + manual, canary/stable/fleet, overnight window, unchanged ring/URL,
manual confirmation/changed target, backup/health/lock failure, automatic CRITICAL denial,
logs order/filter/clear/polling, VPN unknown states, and independent Podkop rollback.
Use a local candidate/install ref containing this PR; do not install from stable v1.6.0.
No router tests have been run by this PR preparation.
## PR #24 hardware-canary corrections

Static LuCI JS, menu and ACL files are installed with explicit 0644 permissions;
LuCI directories use 0755, independent of the caller's umask. The installed updater
self-test also invokes the read-only LuCI filesystem verifier. Offline self-test
keeps its 36 isolated gate checks and does not read installed router configuration.

New configs default to automatic updates disabled, check only, daily time 02:00,
window 02:00–04:00, jitter 60 minutes. Existing configuration is preserved.
Any time window is represented by equal 00:00 endpoints. It removes only the
window veto: daily time, Git rollout, capability, health and CRITICAL protection
still apply. Explicit manual Install is independent of automatic settings.
Logs add display-only ERROR red, WARN orange, INFO/OK green and DEBUG gray lines;
unknown severity remains neutral and text is rendered without HTML interpretation.

Podkop 0.7.22 initializes configuration, nft/routing and sing-box, then its start
process exits. Absence of a persistent Podkop process (including procd not-running)
is expected and does not trigger a restart or failure. Monitoring installation never
starts/stops/restarts Podkop or sing-box. The read-only lifecycle verifier requires:
the nonempty generated config selected by Podkop UCI, matching sing-box conffile,
PodkopTable, the FakeIP-mark routing rule and local route, sing-box running/status,
and all health gates OK with LAST_CHECK no older than 600 seconds. Missing/future
timestamps fail closed. Installation additionally waits for a new healthy cycle.

The separate, explicitly confirmed Podkop update validates the installed target
version, initializes Podkop, then checks the complete lifecycle and a new health
cycle. A cached STATUS=OK alone cannot accept a stopped proxy or missing config.
IPK rollback uses opkg --force-downgrade with the previously verified local assets;
ordinary install of an older version is rejected by the regression mock. Original,
target, observed update/failure and restored versions are recorded in versions.

The rollback inventory preserves contents, modes and original absence for:
etc/config/{podkop,network,dhcp,sing-box}, etc/sing-box, tmp/sing-box, tmp/podkop,
etc/crontabs/root and etc/iproute2/rt_tables. Generated configs outside the backed
sing-box directories are rejected before update. After restoring packages, Podkop
is stopped, the full inventory restored, then initialized with the old inputs;
nft/routing and workers are regenerated. Old PID files are not replayed. The saved
health state is evidence only: success requires the original version and a new
healthy lifecycle cycle. Failed restoration is reported as ROLLBACK FAILED with
the retained private backup; it is not silently retried or reported as success.
Offline fixtures cover one-shot Podkop, missing proxy/config/rules, FakeIP failure,
real downgrade semantics, partial update/full file restoration and unhealthy rollback.
Hardware lifecycle and rollback still require a backup-only canary test.

Round 2 validation requires mangle/prerouting (-150), mangle_output/output
(-150) and proxy/prerouting (-100), TCP/UDP subnet-set marking, TCP/UDP
TPROXY to 127.0.0.1:1602, and a nonempty interfaces set. Empty tables, missing
hooks or missing interception rules fail. This is configuration inspection only;
the verifier does not generate test traffic.
Counters are diagnostics only: zero packets/bytes produces WARN, never FAIL.
Standby Cudy can legitimately have zero prerouting counters. Symbolic tcp/udp
and numeric 6/17 protocols are accepted. Separate literal FakeIP-range marking
rules are not mandatory when the installed variant uses subnet-set marking.
Device role is not inferred from counters; no authoritative role input is added.

After restart, update/rollback first wait for the initialized nft/routing/proxy
structure, then record an epoch boundary. The completed monitoring cycle must
have CHECK_STARTED strictly newer than that boundary, LAST_CHECK at or after
CHECK_STARTED, and fresh full health. Publishing a new CHECK_STARTED while the
previous LAST_CHECK is retained is not a completed cycle. Monitoring installation
also requires a cycle beginning after its initialization boundary. Structure and
health waits each have a 600-second limit.

Cache handling uses fail-safe denial: UCI cache_path (default
/tmp/sing-box/cache.db) must be inside the fully backed /tmp/sing-box or
/etc/sing-box directories. Paths containing traversal or config/cache symlink
components are rejected before package mutation. Custom cache locations outside
this inventory receive an explicit error; configuration is not rewritten.
