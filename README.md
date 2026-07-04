# u4025qw-switcher

Scripts to switch the input source of a **Dell UltraSharp U4025QW** from each
machine connected to it, via DDC/CI — no OSD joystick fumbling.

The monitor acts as the hub for three machines:

| Machine | Input | VCP value |
|---|---|---|
| Linux desktop | DisplayPort | `0x0f` |
| — (spare) | HDMI | `0x11` |
| Work laptop (Lenovo) / MacBook Pro | Thunderbolt / USB-C | `0x19` |

The values were verified against the monitor's own capabilities report
(VCP feature `0x60`, Input Source). Note that the U4025QW reports `0x19` for
the Thunderbolt input — **not** `0x1b`, which many other Dell models use.

All three scripts share the same UX:

```
u4025qw <input|alias>   switch input (dp, hdmi, usbc — or aliases: tb, linux, work, mac)
u4025qw status          show the currently active input
u4025qw toggle          toggle between two configured inputs (default: dp <-> usbc)
```

Since a machine that switches the monitor *away* can no longer see it, in
practice each machine only needs its "switch to the other one" command
(e.g. `u4025qw linux` from the work laptop).

## Linux — `u4025qw`

Bash wrapper around [`ddcutil`](https://www.ddcutil.com/).

**Setup**

```sh
sudo pacman -S ddcutil   # or your distro's package
sudo modprobe i2c-dev    # ddcutil's install usually persists this
install -m755 u4025qw ~/.local/bin/
```

No sudo needed at runtime: ddcutil ships a udev rule that grants the
logged-in user ACL access to `/dev/i2c-*`.

**Gotchas found the hard way**

- `ddcutil --model` needs the *full* EDID model string `DELL U4025QW`;
  bare `U4025QW` yields "Display not found".
- `u4025qw caps` dumps what the monitor actually accepts — use it to verify
  the values if your firmware differs.

**Config**: optional overrides in `~/.config/u4025qw.conf` (sourced as bash;
can redefine `INPUTS`, `ALIASES`, `TOGGLE_A/B`, `MODEL`).

## macOS — `macos/u4025qw`

zsh wrapper around [`m1ddc`](https://github.com/waydabber/m1ddc)
(Apple Silicon; on Intel Macs use `ddcctl` instead).

```sh
brew install m1ddc
install -m755 macos/u4025qw ~/bin/
```

Notes:

- Written in **zsh** on purpose: macOS ships bash 3.2, which lacks
  associative arrays.
- `m1ddc` takes VCP values in **decimal**: dp=15, hdmi=17, usbc=25.
- With more than one external display, set `MDDC="m1ddc display 1"` (or a
  display UUID from `m1ddc display list`).
- Hotkey without extra software: Shortcuts.app "Run Shell Script", or a
  Raycast script command.

## Windows — `windows/u4025qw.ps1`

For a locked-down work machine that cannot run custom executables but allows
PowerShell 7 scripts. Uses the **Monitor Configuration API** (`dxva2.dll`),
which is built into Windows, via in-memory P/Invoke — no external binaries,
no admin rights.

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File u4025qw.ps1 linux
```

The script applies the switch to whichever monitor answers a DDC read of
VCP `0x60`, so the laptop's internal panel is skipped automatically.

**Requirement**: PowerShell must run in FullLanguage mode — check with
`$ExecutionContext.SessionState.LanguageMode`. Under Constrained Language
Mode (strict WDAC policy) `Add-Type` is blocked and this approach won't work.

**Hotkey via PowerToys**: Keyboard Manager → *Remap a shortcut* → map a key
combo to run a program:

- Program: `pwsh.exe`
- Args: `-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File C:\path\to\u4025qw.ps1 linux`

PowerToys Run / Command Palette can also launch it by name.

## Status

- Linux script: tested end-to-end, switching confirmed working.
- macOS and Windows scripts: syntax-checked and (for the PS1) compile-tested
  on Linux, but not yet run against the monitor from their target machines.
