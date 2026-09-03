# HOME NET Architecture

## Monitoring stack

`podkop-service-health` init service launches:

- podkop-service-health-daemon
- podkop-service-check
- podkop-fakeip-check

## Checks

- Active VPN interface
- AWG main/backup availability
- External IP and country
- sing-box state
- Podkop routing
- FakeIP DNS responses

## Deployment model

The same base configuration should be used across Cudy routers. Local differences must be documented.
