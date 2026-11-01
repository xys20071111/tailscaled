# Android Patch Documentation

This document records every modification this module makes to upstream
[tailscale](https://github.com/tailscale/tailscale), where those modifications
came from, and how to regenerate the patch when upstream changes break it.

The Android support here was ported from
[anasfanani/tailscale-android-cli](https://github.com/anasfanani/tailscale-android-cli)
(commit "feat: android modifications", based on tailscale v1.98.8) and adapted
to current mainline.

## Files in this repo

- `.github/workflows/build.yml` — CI build; applies `tailscale-android.patch`, builds for android/arm64.
- `tailscale-android.patch` — unified diff applied to the upstream tailscale source (`patch -p1`).
- `tailscale/settings.ini` — runtime flags passed to `tailscaled`.
- `tailscale/scripts/tailscaled.service` — boot/runtime service script.
- `build_local.sh` — local build helper (same patch + tags as CI).

## What the fork changes, and why

`anasfanani/tailscale-android-cli` is upstream v1.98.8 with a single squashed
"android modifications" commit. Diffing it against its upstream base shows ~30
source files touched. The changes fall into these groups:

| Area | Fork change | Needed for this module? |
| --- | --- | --- |
| Build constraints | `//go:build !android` removed / relaxed on netns, netmon (linux impl), osrouter, ssh, localapi, taildrop, DNS | Partly. Only the files the daemon actually uses are relaxed: `wgengine/router/osrouter/router_linux.go`, `feature/taildrop/fileops_fs.go`, `net/dns/*`. Android keeps polling netmon; `netns_android.go` keeps the JNI hooks but additionally marks sockets with `SO_MARK` for the standalone daemon (see below). |
| Tun default | `defaultTunName()` returns `tailscale0,userspace-networking` | Yes — try a real TUN, fall back to netstack when the ROM refuses the device. |
| Combined binary | Create a `tailscale` symlink next to `tailscaled` at startup | Yes — the module ships one combined binary. |
| Firewall marks | `tsconst` mask/subnet/bypass marks moved to bits 25:28, bypass mark also sets bit 17 (ProtectedFromVPN) | Yes — netd already owns bits 0-20, so the Linux defaults collide with Android's routing. This module goes further than the fork and also marks tailscaled's own sockets with the physical network's netId + protect bits (see the socket marking section below). |
| Policy routing | `getAndroidIPRules()` in the Linux router (CGNAT rule at 12500, subnet/mark rules at 13001, exit-node rule via the current default table) + `getAndroidDefaultTable()` | Yes — this is what makes TUN mode work next to netd and other VPNs. |
| IP forwarding | Enable `/proc/sys/net/ipv4/ip_forward` on Android when advertising routes | Yes — there is no init script on a rooted phone. |
| mangle marking | Divert `mangle/PREROUTING` to `ts-prerouting` and mark packets arriving on the tunnel there | Yes — Android's routing decision for forwarded traffic happens before `filter/FORWARD`, where upstream sets the mark. |
| MASQUERADE rules | Extra `-i tun ! -o tun` and `-o tun` MASQUERADE in `nat/ts-postrouting`, plus fixed MSS 1200 rules | No — upstream now has `AddSNATRule` (masked MASQUERADE) and `ClampMSSToPMTU`, which cover the same cases. |
| DNS | `manager_android.go` (DNAT port 53 to the Tailscale service IP), `resolvconfpath_android.go`, default manager excluded on Android | Yes. Android has no writable `resolv.conf`; when `--accept-dns=true` this is the only way to serve DNS. With the module default `--accept-dns=false` it stays inert. |
| DNS hijack in netstack | Rewrite queries to arbitrary resolvers in `wgengine/netstack` | No — redundant with the DNAT above, and it changes packet handling for every platform. |
| Paths | Sockets/state/logs/certs under `/data/adb/tailscale` (with `$PREFIX` and `$TMPDIR` fallbacks) | Yes. Paths are adapted to this module's layout (`run/tailscaled.sock`, `run/tailscaled.state`). |
| Hostinfo | Fill hostname/OS version/device model from `getprop` | Yes — otherwise the node is called "localhost". |
| os/user | `user_android.go` (lookup via `id`), `GetGroupIds` fallback | Yes — there is no getent/NSS on Android, and `tailscale serve`/taildrop need a user. |
| Taildrop | Drop `!android` from `fileops_fs.go`; default receive dir `/sdcard/Download/Taildrop` | Yes. |
| `ipn/ipnserver` | Add "android" to the peer-credential branch | Yes — lets the daemon resolve the CLI user over the unix socket. |
| CLI flags | `--snat-subnet-routes`, `--stateful-filtering`, `--netfilter-mode` available on Android | Yes. |
| SSH | Relax `!android` in `feature/ssh` and `ssh/tailssh`, add Android user/group handling | No — this module builds with `ts_omit_ssh`. |
| `clientupdate` | `updateAndroid()` that downloads releases from the fork's own GitHub repo | No — module updates are handled by Magisk/KernelSU. |
| `ipn/localapi` | ACME/cert endpoint enabled on Android | No — `tailscale cert` is not supported by the daemon here, and the fork's build tags broke non-Android builds. |
| tap device | Allow `tap:` on Android | No — module builds with `ts_omit_tap`. |
| netmon | Switch Android to the Linux netmon and the `wlynxg/anet` package | No — polling netmon works without a new dependency; the router only needs the `netmon.RuleDeleted` type to exist. |
| Fork build tooling | `.github/workflows/build_android.yml`, `scripts/android.sh` | No — this repo has its own build flow. |

## tailscale-android.patch contents

New files:

- `hostinfo/hostinfo_android.go` — `getprop` based hostname/model/OS version.
- `net/dns/manager_android.go` — DNS configurator that DNATs port 53 to `100.100.100.100` / `fd7a:115c:a1e0::53`.
- `net/dns/resolvconfpath_android.go` — resolv.conf/backup paths under `/data/adb/tailscale/etc`.
- `net/netmon/ruledeleted_android.go` — `netmon.RuleDeleted` for the polling netmon (only used by the router event subscription).
- `tsconst/linuxfw_android.go` — Android fwmark bits; `tsconst/linuxfw.go` is now `//go:build !android` so Linux keeps the upstream marks.
- `util/linuxfw/android_net.go` — netId/physical-table detection plus mark candidate validation (`AndroidSocketMark()` / `AndroidDefaultPhysicalNetwork()`), 3s cache, diagnostic logging.
- `util/linuxfw/android_net_stub.go` — `linux && !android` stub returning zeroes, so callers compile on plain Linux.
- `util/osuser/user_android.go` — user lookup via `id`.

Modified files:

1. `cmd/tailscaled/tailscaled.go`
   - `defaultTunName()`: `case "android": return "tailscale0,userspace-networking"`.
   - `createTailscaleSymlink()` called from `main()` so the combined binary also answers to `tailscale`.
2. `cmd/tailscale/cli/set.go`, `up.go` — `case "linux", "android"` for the netfilter flags.
3. `paths/paths.go`, `paths/paths_unix.go` — socket `/data/adb/tailscale/run/tailscaled.sock`, state `/data/adb/tailscale/run/tailscaled.state`, `MakeAutomaticStateDir` true on Android.
4. `tsconst/linuxfw.go` — build tag `!android` (constants unchanged for Linux).
5. `util/linuxfw/iptables.go`, `iptables_runner.go` — `mangle/PREROUTING` hook, `ts-prerouting` chain, mark rule for tunnel packets, and cleanup in `DelHooks`/`DelChains`/`clearRules`.
6. `wgengine/router/osrouter/router_linux.go`
   - build tag `!android` → `linux` (Android now uses the real router).
   - enable IP forwarding on Android when advertising routes.
   - `ipRules()` returns `getAndroidIPRules()` on Android; added `detectAndroidDefaultTable()` and `getAndroidIPRules()`.
   - `detectAndroidDefaultTable()` uses `AndroidDefaultPhysicalNetwork()` (physical network), not a plain route lookup: while a VPN app is connected it owns the default route, and a plain lookup would return the VPN's table.
7. `net/dns/manager_default.go`, `resolvconfpath_default.go` — excluded on Android (replaced by the two new files).
8. `feature/taildrop/fileops_fs.go` — `!android` build tag dropped (prevents a nil `fileOps` panic).
9. `feature/taildrop/paths.go` — default receive dir `/sdcard/Download/Taildrop`.
10. `logpolicy/logpolicy.go`, `tsweb/tsweb.go` — log/cert dirs under `/data/adb/tailscale`.
11. `ipn/ipnserver/actor.go` — peer-credential username lookup on Android.
12. `util/osuser/user.go`, `group_ids.go` — hook for `user_android.go`; group IDs from `id -Gz`, falling back to `0`.
13. `net/netns/netns_android.go` — socket protection for the standalone daemon, see below.

## Socket marking for coexistence with other VPN apps (2026-10-31)

Status: working, verified on-device. With the marking active
(`netns: marking sockets with fwmark 0x10030069` in the log), enabling a
v2rayNG/Clash-style VPN app no longer disconnects tailscaled: its WireGuard
UDP, DERP and control-plane traffic rides netd's explicit per-network rules
straight out of the physical interface, while the VPN app keeps carrying
whatever the user routes into it. It also fixes exit-node mode, where
tailscaled's own traffic previously looped back into the tunnel.

Upstream Android builds never set `SO_MARK`: `netns_linux.go` (which marks
sockets with the Tailscale bypass fwmark) is excluded on Android, and
`netns_android.go` only supports the JNI `VpnService.protect`/bind callbacks
that the official app registers. A standalone root tailscaled therefore sends
its WireGuard UDP, DERP and control-plane traffic unmarked.

That breaks as soon as another VPN app (v2rayNG, Clash, ...) connects: netd's
rule at priority 31000 (`RULE_PRIORITY_DEFAULT_NETWORK`) sends every packet
whose netId mark bits are zero into the *default network*, which is the VPN
app's tunnel while it is connected. tailscaled loses connectivity ("starting
the v2ray VPN breaks tailscale"), and any exit-node traffic would be routed
into the VPN's table as well.

The fix marks tailscaled's own sockets in `netns_android.go` `controlC` the
same way `VpnService.protect` does (confirmed against
`system/netd/server/RouteController.{h,cpp}`):

```
mark = netId                      (bits 0-15, physical network)
     | 0x10000                    (explicitly selected, bit 16)
     | 0x20000                    (protected from VPN, bit 17)
     | 0xc0000                    (netd permission bits, 18-19, optional)
     | 0x10000000                 (Tailscale bypass bit, bit 28)
```

With such a mark, netd's per-network explicit rules at priority 16000 (or the
implicit rules at 23000) route tailscaled's packets straight out of the
physical interface; the secure/bypassable VPN per-UID rules (13000/24000/27000)
skip protected packets; and the router's "not bypass-marked → lookup table 52"
rule (13001) skips its own traffic so exit-node mode does not loop.

**Every candidate mark is validated before it is used**: the first version of
this fix applied the mark unconditionally, and on at least one device the
detected netId did not match any of netd's rules — the marked packets then
fell through all rules to netd's final `unreachable` rule (32000) and every
tailscaled dial failed with "network is unreachable". Detection now
(`util/linuxfw/android_net.go`):

1. dumps all routing tables (netlink `RouteListFiltered` with the wildcard
   table; plain `RouteList` only returns the main table) and finds the
   default routes whose interface is not a tunnel (`tun*`, `tailscale0`,
   `wg*`, `dummy*`, ...);
2. maps the chosen table to netd's netId by scanning the policy rules for
   rules that point at that table and carry the netId in their fwmark match
   (this validates that the table really is a netd-managed network); if that
   yields nothing, it falls back to parsing netd's incoming-packet marks in
   the mangle table (`-i <ifname> -j MARK --set-xmark 0x...`), an
   independent source for the same netId;
3. tries candidate marks (`netId|0x30000|bit28`, then with the permission
   bits, then `netId|0x20000|bit28` for the implicit rules) and only accepts
   one that a real kernel route lookup accepts — a datagram `connect()` with
   `SO_MARK` set, which performs exactly the policy-routing walk of a real
   dial but sends no packet;
4. gives up (mark 0, unmarked sockets = the pre-fix behavior) if no candidate
   validates, logging what it found at most once every 30s
   (`linuxfw/android: table ... no validated netId among [...]`).

The result is cached for 3s; netIds change when the phone switches between
Wi-Fi and cellular, and magicsock rebinds its sockets on netmon events anyway.
State changes are logged (`netns: marking sockets with fwmark 0x...` /
`netns: no validated Android SO_MARK available`).

`UseSocketMark()` now returns true on Android so that `net/udprelay` and the
raw-disco listener use the same marking path. The JNI protect/bind callbacks
still take precedence when the official app registers them.

If the log shows "no validated Android SO_MARK available", the coexistence
protection is inactive (tailscaled behaves like before, i.e. a foreign VPN
still captures its traffic). The `linuxfw/android: ...` diagnostic lines
logged alongside it say which stage failed (route/rule dump, netId lookup,
mark validation). In that case collect `ip rule show` and
`ip route show table all | grep -w default` from a root shell to adjust the
detection.

Traffic owned by other apps to tailnet IPs keeps working while a foreign VPN
is connected, because the router's dst-CGNAT rules (12500) sit above netd's
secure-VPN UID rules (13000); that part does not depend on the socket marks.


Notes:

- The current patch was generated against upstream main (commit `3a38840`,
  2026-10-27, post-1.105.0) and is verified to apply cleanly to that tree; the
  upstream files it touches had no later changes at the time of writing. When
  regenerating against a new tag, re-check the files listed above.
- The socket-marking change touches `net/netns/netns_android.go`, which
  upstream had not modified since 2026-03, and `tsconst/linuxfw_android.go` /
  `util/linuxfw/android_net*.go`, which are module-owned files.
- Because the fwmark change is isolated in `tsconst/linuxfw_android.go`, Linux
  unit tests (`go test ./util/linuxfw/...`) still pass with the patch applied.

## Runtime (settings.ini)

`tailscaled` is invoked with:

```
-verbose=0 -tun=tailscale0,userspace-networking -statedir=.../run -state=.../run/tailscaled.state -socket=.../run/tailscaled.sock
```

With the router enabled on Android, tailscaled programs the Tailscale routes,
policy rules and netfilter chains itself. The extra `ip route`/`ip rule`/iptables
lines in `tailscale/scripts/tailscaled.service` are a leftover manual fallback
for userspace-networking mode and are harmless, but they are no longer required
for TUN mode.

`--accept-dns=false` (as recommended in the README) keeps the DNS hijack off.
Without it, the Android DNS manager adds DNAT rules for port 53.

## Build integration

`.github/workflows/build.yml`:

1. checkout the latest tailscale release tag into `tailscale-build`;
2. `patch -p1 --no-backup-if-mismatch < ../tailscale-android.patch`;
3. build `./cmd/tailscaled` with the module's `ts_omit_*` tags (including
   `ts_include_cli`, `ts_omit_ssh`, `ts_omit_tap`).

`build_local.sh` does the same for local builds. Earlier revisions used `sed`
one-liners for `paths.go` and `resolvconfpath_*.go`; those edits are now part of
the patch.

## Regenerating the patch

1. Clone the release tag the workflow will use:

   ```
   git clone --depth 1 --branch vX.Y.Z https://github.com/tailscale/tailscale.git ts
   ```

2. Apply the changes above there (or cherry-pick from a tree that has them).

3. Produce the diff, including new files:

   ```
   git -C ts add -A
   git -C ts diff --cached > tailscale-android.patch
   ```

4. Verify it applies to a pristine checkout and that the binary builds:

   ```
   git clone --depth 1 --branch vX.Y.Z https://github.com/tailscale/tailscale.git check
   (cd check && patch -p1 --no-backup-if-mismatch < ../tailscale-android.patch)
   (cd check && CGO_ENABLED=1 GOOS=android GOARCH=arm64 \
      CC=$NDK/toolchains/llvm/prebuilt/linux-x86_64/bin/aarch64-linux-android21-clang \
      go build -tags "ts_include_cli ts_omit_aws ts_omit_bird ts_omit_tap ts_omit_kube ts_omit_completion ts_omit_completion_scripts ts_omit_wakeonlan ts_omit_capture ts_omit_systray ts_omit_syspolicy ts_omit_appconnectors ts_omit_identityfederation ts_omit_usermetrics ts_omit_logtail ts_omit_netlog ts_omit_linuxdnsfight ts_omit_tpm ts_omit_ssh" \
      ./cmd/tailscaled)
   ```

5. If upstream is fine but a hunk fails to apply, check whether the touched
   code moved; re-generate the patch against the new tag instead of adding
   fallback `sed` hacks.

Key pitfalls:

- The fork is based on v1.98.8; do not copy its files verbatim onto a newer
  upstream. Its `ipn/localapi` build tags and `netmon`/`anet` changes do not
  compile against current main and are intentionally not part of the patch.
- Keep `util/linuxfw`'s chain creation, hook insertion and cleanup in sync: a
  missing `mangle/PREROUTING` hook or `ts-prerouting` chain makes `tailscaled`
  fail to start on Android.
- `service.sh` and every script under `tailscale/scripts/` must be executable in
  git (`git update-index --chmod=+x`), otherwise Magisk will not run them.
