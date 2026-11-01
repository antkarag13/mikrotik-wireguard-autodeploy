# Changelog

All notable changes to this project are documented here.
The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and the project uses [Semantic Versioning](https://semver.org/).

## [1.1.0] - 2026-11-01

### Changed
- Management Wi-Fi is now optional: set `mgmtWifi false` to skip section 2 entirely
  (no `wlan1` config and no WLAN input rule), so boards without Wi-Fi deploy cleanly

## [1.0.0] - 2026-11-01

### Added
- `deploy.rsc`: one-paste WireGuard site-to-site client for RouterOS v7+
- DHCP client on `ether1` whose lease script detects the LAN subnet and patches firewall/NAT rules
- `/32` bypass route to the VPN endpoint via the upstream gateway
- NETMAP from a per-site mask subnet to the real LAN, for overlapping subnets
- Masquerade for inbound peers and for outbound tunnel traffic
- Hidden management Wi-Fi on `wlan1` with its own DHCP pool
- Netwatch-driven tunnel status LED
- README with setup, verification and troubleshooting (including MSS clamping)
- Topology diagram (`docs/topology.md`)
