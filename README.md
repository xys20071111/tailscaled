# Magisk Tailscaled

This repository contains a Magisk and KernelSU module for running Tailscale on rooted Android devices.

## Prerequisites
- Magisk or KernelSU

## Quick Start & Installation

1. Download the latest zip file from the [Releases](https://github.com/mgksu/tailscaled/releases/latest) page.
2. Install the downloaded zip file using Magisk & reboot your phone.
3. Open the Terminal.
4. Run `tailscale up --accept-dns=false` to initiate login.
5. Run 'tailscale ip' to retrieve your Tailscale IP.

After installation, the Tailscale daemon (`tailscaled`) will run automatically on boot.

## Limitation

- This module only support `arm64` architecture.

## Using together with other VPN apps (v2rayNG, Clash, ...)

tailscaled marks its own sockets (WireGuard, DERP, control plane) the same way
`VpnService.protect` does, so another VPN app becoming the default network does
not capture its traffic: tailscale stays connected and keeps direct peer
connections while the other VPN runs.

Check it is active with `tailscaled.service log`:

- `netns: marking sockets with fwmark 0x...` — coexistence protection is on.
- `netns: no validated Android SO_MARK available` — protection is off (tailscaled
  behaves like a plain Linux daemon; a VPN app that captures all traffic will
  also capture tailscale's). The `linuxfw/android: ...` lines next to it say
  which detection stage failed; include them if you report an issue.

Switching between Wi-Fi and cellular refreshes the mark within a few seconds;
a short hiccup during the switch is normal.

## Available command

- `tailscale`: This command  execute tailscale operation.
- `tailscaled`: This command execute tailscaled daemon operation.
- `tailscaled.service`: This command for manage tailscaled service, you can start,stop,restart daemon and view live logs the tailscaled operation.

### Cannot access other tailnet devices

1. Verify that `tailscaled.service` is running. If not, restart it with `tailscaled.service restart`.
2. Check if your device is connected to tailscaled and try a ping connection with `tailscale ping <your_tailnet_ip>`.
3. Verify the port you want to access is accessible. You can do this by accessing it with another tailscale device or using the Tailscale Android App.

### Other Error & Bugs

You can explore to the issue tab, if there not exists, you can open issue, for help me resolve the problem, you can include fresh log.

1. Restart tailscaled with `tailscaled.service restart`
2. Reproduce what are you doing which has problem.
3. Get log at `tailscaled.service log`

## Notes

This module is confirmed to be supported for KernelSU

## Credits

- [ANASFANANI & AUTHORS](https://github.com/anasfanani/Magisk-Tailscaled). for the repo structure and android specific code.
