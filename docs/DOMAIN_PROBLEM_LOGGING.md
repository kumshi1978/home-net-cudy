# HOME NET domain and problem logging

## Goal

Collect enough evidence to decide which hostnames may need to be added to Podkop domain policy and to preserve concise diagnostics around failures.

This subsystem is observational. It never adds domains to Podkop, changes VPN/DIRECT policy, restarts network interfaces, or performs recovery actions.

## Logs

Detailed runtime data is stored in tmpfs:

- `/tmp/home-net-log/domains.log` — normalized DNS queries;
- `/tmp/home-net-log/fakeip-domains.txt` — domains observed with a FakeIP reply;
- `/tmp/home-net-log/problems.log` — normalized warnings/errors;
- `/tmp/home-net-log/incident-*.txt` — manual incident snapshots.

Logs disappear on reboot by design. Long-term collection should be handled by the NAS/aggregator rather than frequent flash writes on Cudy.

## Domain capture

Domain capture is disabled by default. The logger service still collects problem events.

Enable explicitly:

```sh
/usr/bin/home-net-log enable
```

This changes only `dhcp.@dnsmasq[0].logqueries`, saves its previous value, commits the dnsmasq setting, reloads dnsmasq, and enables HOME NET domain parsing.

Disable and restore the previous dnsmasq setting:

```sh
/usr/bin/home-net-log disable
```

Because dnsmasq query logging can be noisy and includes client IP addresses and requested hostnames, it must never be enabled automatically by a bundle update.

## Candidate report

```sh
/usr/bin/home-net-log report 50
```

Output classes:

- `FAKEIP` — a FakeIP reply was observed during the capture window, so the domain is already being handled by FakeIP at least for that observation;
- `DIRECT_OR_UNKNOWN` — no FakeIP reply was observed. This is only a candidate for investigation, not an instruction to add the domain.

A domain must never be added automatically based only on this report.

## Problem log

```sh
/usr/bin/home-net-log problems 100
```

The daemon records selected HOME NET, Podkop, failover, updater, dnsmasq and sing-box failure/unknown signals as normalized ERROR/WARN events.

## Manual incident marker

When a site/app is visibly broken:

```sh
/usr/bin/home-net-log mark app-name
```

The snapshot includes current health plus recent problem and domain context. This is the preferred evidence for deciding whether a new hostname belongs in a domain list.

## Interpretation rule

Do not auto-edit Podkop policy. For a candidate hostname, correlate:

1. the time of the user-visible problem;
2. recent DNS queries for the affected client;
3. whether FakeIP was observed;
4. HOME NET/Podkop/sing-box problem events;
5. repeated occurrence across incidents.

Only after this evidence should a domain be proposed for the shared apartment baseline or a documented local exception.
