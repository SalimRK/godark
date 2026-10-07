# GoDark — design

One click on the bar cuts every radio and network link. A second click
puts back exactly what was on before. Sibling of macarchy: same repo
shape, same "nothing runs as root" rule.

## What was verified on this machine (2026-10-07)

| Check | Result |
|---|---|
| `rfkill` | `hci0` bluetooth soft-**blocked**, `phy0` wlan unblocked, no hard blocks |
| `/dev/rfkill` | `crw-rw-r--+ root rfkill`, ACL `user:cyberbow:rw-` |
| Where that ACL comes from | `/usr/lib/udev/rules.d/70-uaccess.rules:97`: `KERNEL=="rfkill", SUBSYSTEM=="misc", TAG+="uaccess"` (stock systemd, not a local rule) |
| NM polkit defaults | `enable-disable-network`, `-wifi`, `-wwan`: `allow_active=yes`, `allow_inactive=no` (stock NM policy file; the only extra NM rule is the wheel/`settings.modify.system` one, unrelated) |
| Session | `seat0`, `Type=wayland`, `Active=yes`, `Remote=no` |
| Persistence | systemd-rfkill keeps soft-block state in `/var/lib/systemd/rfkill/` and restores it on boot; NM keeps `NetworkingEnabled` in `/var/lib/NetworkManager/NetworkManager.state` (root-only) |
| First-party Omarchy bluetooth panel | uses an rfkill soft block on purpose, because systemd-rfkill persists it (`panels/bluetooth/Panel.qml:627-630`) |

**Conclusion on privileges:** both permissions come from stock systemd and
NetworkManager defaults granted to *any active local seat user*, not from
something special on this machine. So GoDark needs **no sudo, pkexec or
polkit rule**. It fails cleanly (with a message) in sessions without them:
over ssh, or from an inactive VT.

## What "dark" cuts

1. **Every rfkill radio**: wlan, bluetooth, wwan, nfc, gps, uwb, anything
   `rfkill` lists, via `rfkill block <id>`. That covers the radios NM
   doesn't know about (bluetooth, nfc, gps).
2. **All NetworkManager networking**, via `nmcli networking off`. This is
   what takes down Ethernet (rfkill doesn't touch wired links), plus USB
   tethering, NM-managed VPNs and anything else NM runs.

**Proposal: Ethernet is always included, with no setting.** A "go dark"
that leaves a cable live isn't dark, and an option makes the icon lie when
it's set wrong.

**Limit, reported and not hidden:** interfaces NM doesn't manage (shown as
`unmanaged` in `nmcli device`, for example a hand-configured link, or a
docker bridge, which doesn't matter) aren't touched, because taking them
down would need root. `status` lists any *physical* unmanaged interface
that is still up as `uncovered`, and the panel shows it as a warning. This
machine currently has none.

## Restoring exactly the previous state

Before cutting anything, `dark` writes a snapshot:

```
$XDG_STATE_HOME/godark/state    (default ~/.local/state/godark/state)

version=1
saved=2026-10-07T23:40:00+03:00
networking=enabled
radio=wlan phy0 unblocked
radio=bluetooth hci0 blocked
```

- Written atomically (`mktemp` in the same dir, then `mv`), mode 600, under
  an `flock` so two clicks can't interleave.
- Saved **before** any change. If the write fails, `dark` aborts and
  nothing is cut.
- `light` unblocks **only** the radios saved as `unblocked`, and turns
  networking on only if it was `enabled`. Never `rfkill unblock all`. In
  this example, bluetooth stays off.
- Radios are matched by **type + device name**. rfkill IDs aren't stable
  across reboots or hotplug (this machine's `/var/lib/systemd/rfkill/`
  already holds 8 entries for 2 radios, from USB re-enumeration). A saved
  radio that no longer exists is skipped and named in the output.
- `light` removes the state file only after everything was restored.

**Why `~/.local/state` and not `/run`:** dark *survives a reboot*. Both
systemd-rfkill and NM persist their state, so after a reboot the machine
comes back dark, and the snapshot has to come back with it. I think
that's the right behaviour for a privacy switch: a reboot shouldn't
quietly reconnect you.

**If the state file is missing while the machine is dark** (deleted, a new
home directory, a crash between the two steps): `light` falls back to a
conservative default: networking on, unblock **wlan and wwan only**,
leave bluetooth/nfc/gps/uwb blocked, and say exactly that in its output.
**Decided:** this fallback, not a refusal.

**Running `dark` while already dark** is a no-op that keeps the existing
snapshot. It must never overwrite a good snapshot with an all-blocked one.

## Hard blocks

A physical switch (`HARD blocked`) can't be undone in software.

- `status` reports each radio as `blocked`, `unblocked` or `hard-blocked`.
- `dark` treats a hard-blocked radio as already dark and still records its
  soft state, so `light` puts the soft state back.
- `light` with a radio that is hard-blocked: it restores the soft state,
  then warns `wlan phy0 is held off by a hardware switch`. The exit code is
  still 0, since GoDark did its part.
- The panel shows a hard-blocked radio with a lock marker. The bar icon
  counts it as dark.

## State model (what the icon reports)

Computed live from `rfkill` + `nmcli`, never from the snapshot alone:

| State | Meaning | Bar icon |
|---|---|---|
| `dark` | networking off **and** every radio soft- or hard-blocked | lit (`urgent` color) |
| `partial` | a snapshot exists (GoDark went dark) but something has come back, e.g. wifi switched on by hand, or a new USB radio plugged in | lit, warning color |
| `light` | no snapshot, normal operation | dim |

In `partial`, clicking again runs `dark` (re-cut). The panel says what
leaked.

## CLI surface

Same single script, dispatched by subcommand. Refuses to run as root.

| Command | |
|---|---|
| `godark status [--json]` | state, per-radio soft/hard, networking, uncovered interfaces, snapshot time |
| `godark dark` | snapshot, then cut |
| `godark light` | restore the snapshot |
| `godark toggle` | `dark` if light or partial, otherwise `light` |
| `godark help` | |

Order inside `dark`: snapshot → `nmcli networking off` → `rfkill block`
each radio. Order inside `light` is the reverse: radios first, then
networking, so NM finds wifi available when it comes up and reconnects
right away.

## Interaction with tormarchy and macarchy (to TEST, not assume)

- **tormarchy**: its kill switch is nftables DROP rules (`tormarchy:484`,
  `:557`), which a link drop doesn't flush. Expected: after `light`, Tor
  traffic is still forced through Tor and Tor reconnects. To check live:
  `tormarchy status` before/after a dark→light cycle, plus a leak check.
- **macarchy**: on NM interfaces the randomized MAC lives on the connection
  profile's `cloned-mac-address`. Expected: it survives `networking off/on`
  and reconnects with the same random MAC. To check live:
  `macarchy status` before/after.

## Bar icon and panel

- Glyph by codepoint, confirmed present in JetBrainsMono Nerd Font:
  **U+F001D** (`nf-md-airplane`), with U+F001E (`airplane_off`) as the
  alternative. I'll confirm the rendering in the bar before committing.
- The panel shows a big Go Dark / Restore button; one row per radio
  (type, device, soft/hard state); a networking row; uncovered-interface
  warnings; "dark since <time>" from the snapshot.
- `Service.qml` polls `godark status --json` at `refreshIntervalSec`
  (default 3; lower than macarchy's 5, since this switch matters more),
  using the same busy/pending pattern as macarchy.

## Manifest

`id: oniomarchy.godark`, name `GoDark`, `kinds: ["bar-widget"]`,
`entryPoints.barWidget: Panel.qml`, `defaultSection: center`, category
`Network`.

## Decisions (2026-10-07)

- id `oniomarchy.godark`, to match `oniomarchy.macarchy`.
- No `panic` alias: tormarchy's `panic` means "get the network back", the
  opposite of going dark, and a shared word with opposite meanings in
  sibling tools invites the wrong click.
- Missing-snapshot fallback: networking + wlan + wwan on, everything else
  stays off.
- Glyph U+F001D (`nf-md-airplane`).
- Middle-click on the bar icon toggles directly; left-click opens the
  panel.

## Live-test plan (each step announced before it runs)

1. Unit checks with no side effects: `status`, snapshot parse/write into a
   temp `XDG_STATE_HOME`.
2. **Prove `light` first:** with only bluetooth (already off, nothing lost)
   → block wlan for about 5 s → `light` → confirm wifi reconnects and
   bluetooth is still blocked.
3. Full `dark` for about 10 s → `light` → compare `rfkill`/`nmcli` output
   against the pre-test capture.
4. tormarchy and macarchy interaction checks.
5. Reboot while dark (only with your go-ahead).
