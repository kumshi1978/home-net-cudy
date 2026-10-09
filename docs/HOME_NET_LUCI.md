# HOME NET LuCI dashboard

Monitoring v1.6.0 adds a local LuCI page at **Services → HOME NET**.

## Goals

The page is an operator view over the existing HOME NET state. It does not
replace Podkop, sing-box, AmneziaWG or their configuration files.

It shows:

- overall HOME NET health;
- active VPN, public IP and country;
- WAN public IP and country;
- awg_main / awg_backup handshake age and country;
- Podkop, sing-box, FakeIP and service-check state;
- HOME NET bundle, Monitoring and failover versions;
- recent problems, failover/health events and health history.

The status backend is:

```text
/usr/bin/home-net-status
```

Supported read-only commands:

```sh
home-net-status status
home-net-status problems [N]
home-net-status events [N]
home-net-status healthlog [N]
```

## Limited controls

The page exposes only a small allow-list through:

```text
/usr/bin/home-net-control
```

Actions:

- refresh health;
- check for a HOME NET update;
- switch Podkop to awg_main;
- switch Podkop to awg_backup;
- restart Podkop;
- restart sing-box.

Switch and restart actions require browser confirmation.

The dashboard intentionally does **not** expose reboot, network restart/reload,
WAN/LAN changes, firewall changes, package installation or arbitrary shell
execution.

## Logs

The LuCI page keeps the standard Podkop UI untouched and displays HOME NET logs:

- `/tmp/home-net-log/problems.log`;
- recent `podkop-awg` / `podkop-service-health` events from system log;
- the current `/tmp/podkop-service-health/service-YYYY-MM-DD.log`.

Detailed logs remain in tmpfs to avoid flash wear.

## Future integration

The local status backend is intentionally separate from the UI. A later phase can
export the same structured state to Home Assistant and MCP so the apartment and
country-house Cudy routers can be viewed together without duplicating health
logic.
