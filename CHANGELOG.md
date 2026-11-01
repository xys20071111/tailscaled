## Tailscaled Change Log

## 1.105.0 (2026-10-31 / 11-01)

- Coexistence with other VPN apps (v2rayNG, Clash, ...): tailscaled now marks
  its own sockets (WireGuard UDP, DERP, control plane) the way
  `VpnService.protect` does — with the underlying physical network's netId and
  the "explicitly selected" / "protected from VPN" bits — so another VPN app
  becoming the default network no longer captures tailscaled's traffic into
  its tunnel. Verified on-device: with v2ray's VPN enabled, tailscale stays
  connected (`netns: marking sockets with fwmark 0x10030069`).
- Candidate marks are validated with a real kernel route lookup (a UDP
  connect with `SO_MARK` set) before use; if none validates, tailscaled falls
  back to unmarked sockets (the previous behavior) and logs a diagnostic.
  netId detection reads netd's policy rules and, as a fallback, the mangle
  table's incoming-packet marks.
- The Android exit-node ip rule now points at the routing table of the
  physical network instead of the "current" default route, which a foreign
  VPN app owns while it is connected. This also stops tailscaled's own
  traffic from looping back into the tunnel when using an exit node.
