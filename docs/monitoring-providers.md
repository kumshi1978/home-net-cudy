# Monitoring provider failures

IP checks use ifconfig.me, then api.ipify.org, always on the same requested interface. Only valid IPv4 values from HTTP 200 responses are accepted. Both failures keep the check UNKNOWN; the active route is not modified. Matching successfully observed WAN and VPN IPs still report FAIL.

Country lookup retains IPinfo, IPAPI, Country.is fallback. A provider HTTP 429 enables a 15-minute cooldown scoped to provider and interface, without reusing a stale country or IP. Requests retain bounded timeouts and a 4096-byte response limit. Diagnostics record provider, interface, HTTP status, curl exit code or invalid_body; response bodies and IP addresses are not logged. Log suppression remains hourly.

The health state now includes REASON for UNKNOWN checks. LuCI explains external-check failures separately from actual loss of connectivity. No service restart, network reload or repair action is triggered by these diagnostics.

Validation: tests/test-country-lookup.sh covers primary success, fallback, interface preservation, cooldown isolation, malformed data, timeout, UNKNOWN state and real bypass FAIL. Existing startup and LuCI tests remain required.
