# HOME NET Cudy architecture

## Purpose

Centralized management repository for HOME NET Cudy/OpenWrt routers.

GitHub is the source of truth for:
- scripts
- configuration templates
- documentation
- version history

## Network stack

```text
Internet
   |
Cudy OpenWrt
   |
AmneziaWG (awg_main / awg_backup)
   |
Podkop
   |
sing-box
   |
LAN clients
```

## Monitoring stack

The monitoring service consists of:

- podkop-service-health-daemon
- podkop-service-check
- podkop-fakeip-check

Checks:

- active VPN interface
- AWG main and backup tunnels
- VPN exit country is not RU
- direct WAN country detection
- sing-box process
- Podkop routing
- FakeIP DNS responses
- required external services

## Deployment model

Workflow:

GitHub -> test Cudy -> rollout to remaining Cudy routers

Target devices:
- dacha Cudy routers
- apartment Cudy routers

OpenWrt 24.x and 25.x compatibility must be checked before rollout.

Local differences are documented separately and should not modify the common base configuration.
