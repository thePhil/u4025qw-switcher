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

All scripts share the same UX:

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

## Windows (FullLanguage) — `windows/u4025qw.ps1`

For a machine that allows PowerShell 7 scripts in FullLanguage mode. Uses the
**Monitor Configuration API** (`dxva2.dll`), built into Windows, via in-memory
P/Invoke — no external binaries, no admin rights.

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File u4025qw.ps1 linux
```

The script applies the switch to whichever monitor answers a DDC read of
VCP `0x60`, so the laptop's internal panel is skipped automatically.

**Requirement**: PowerShell must run in FullLanguage mode — check with
`$ExecutionContext.SessionState.LanguageMode`. Under Constrained Language
Mode (strict WDAC policy) `Add-Type` is blocked and this approach won't work;
use the precompiled binary below instead.

**Hotkey via PowerToys**: Keyboard Manager → *Remap a shortcut* → map a key
combo to run a program:

- Program: `pwsh.exe`
- Args: `-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File C:\path\to\u4025qw.ps1 linux`

PowerToys Run / Command Palette can also launch it by name.

## Windows under WDAC / Constrained Language Mode — `windows/exe/`

When WDAC enforces script rules, PowerShell drops to Constrained Language Mode
and `Add-Type` is blocked, so the `.ps1` above cannot compile its P/Invoke
shim. The backup route is a **precompiled `u4025qw.exe`** — same `dxva2.dll`
Monitor Configuration API and the same "act on whichever monitor answers DDC"
logic, but as a fixed binary that compiles nothing at runtime. No admin
rights, no PowerShell.

It is written in Go and cross-compiled to a Windows PE from any platform, with
**no cgo, no external modules, and no C toolchain** — the stdlib `syscall`
package reaches `dxva2.dll` directly.

### Build (reproducible)

On Linux/macOS:

```sh
cd windows/exe
./build.sh          # CGO_ENABLED=0 GOOS=windows GOARCH=amd64, deterministic flags
```

On Windows with PowerShell 7 (`build.ps1` mirrors `build.sh` exactly):

```powershell
cd windows\exe
pwsh -NoProfile -File .\build.ps1
```

The build is **byte-for-byte reproducible across build hosts** (Linux, macOS,
Windows) and directories. Both scripts pin the exact upstream Go release with
`GOTOOLCHAIN=go1.26.4`, then pass `-trimpath` (drop source paths),
`-buildvcs=false` (no git stamping), and `-ldflags "-s -w -buildid="` (clear
build id and debug info). Verified: `build.sh` on Linux and `build.ps1` on
Windows both yield the hash below.

Reference hash (Go `go1.26.4`):

```
sha256  609b4d60f6184f8a7c384b251edb06aa942b67af21fe1441a4e7b13a08d88305
```

**Why the toolchain is pinned, not just the version number.** Go embeds its
version string into every binary, and `-trimpath` cannot strip it — so the
hash depends on the *precise* toolchain, not merely "1.26.4". A custom
`GOEXPERIMENT` build such as `go1.26.4-X:nodwarf5` embeds a different string
and produces a *different* hash than stock `go1.26.4`. `GOTOOLCHAIN=go1.26.4`
forces the stock release (Go downloads it if absent), which is why the host OS
doesn't matter. The trust model is still that **IT rebuilds and allowlists the
hash they produce**; the value above is the cross-check, and any stock
`go1.26.4` build — on any OS — should reproduce it exactly.

### Verifying the hash (PowerShell 7)

`build.ps1` prints the hash on completion, but to check any copy of the binary:

```powershell
Get-FileHash -Algorithm SHA256 u4025qw.exe          # -Algorithm SHA256 is the default; shown for clarity

# Compare against the reference (case-insensitive) and get a clear pass/fail:
$expected = '609b4d60f6184f8a7c384b251edb06aa942b67af21fe1441a4e7b13a08d88305'
$actual   = (Get-FileHash -Algorithm SHA256 u4025qw.exe).Hash
if ($actual -ieq $expected) { 'MATCH' } else { "MISMATCH: got $actual" }
```

`Get-FileHash` returns uppercase hex; the comparison above is case-insensitive
(`-ieq`), so it matches the lowercase reference. This is the exact SHA-256 to
hand to the WDAC hash rule below.

### Allowlisting it in WDAC (hash rule — Option B)

Because the binary compiles nothing at runtime, a single WDAC **hash rule** on
the exact file is sufficient — the narrowest possible exception. Install it to
an admin-only-writable path (e.g. `C:\Program Files\u4025qw\`), then:

```powershell
New-CIPolicy -FilePath .\u4025qw.xml -Level Hash -Fallback None `
  -ScanPath 'C:\Program Files\u4025qw' -UserPEs -NoScript
Merge-CIPolicy -PolicyPaths $BasePolicy,.\u4025qw.xml -OutputFilePath .\Merged.xml
ConvertFrom-CIPolicy .\Merged.xml .\Merged.cip   # deploy via Intune / CiTool
```

This authorizes that one byte-for-byte binary and nothing else. Every rebuild
changes the hash, so the rule must be re-issued per version — fine for a tool
that rarely changes. (For a version-durable exception, sign the binary and use
a Publisher rule instead.)

### Ticket text for IT

> Please allow a single utility `u4025qw.exe` (installed to
> `C:\Program Files\u4025qw\`) via one **hash-level WDAC allow rule**
> (fallback: none) on the SHA-256 of the build we provide. It switches the
> external monitor's input through the built-in `dxva2.dll` API; no other path
> or capability is requested. Source and a reproducible build live in
> `windows/exe/` so you can rebuild and confirm the hash yourself.

## Status

- Linux script: tested end-to-end, switching confirmed working.
- macOS, Windows PowerShell, and Windows Go binary: syntax-/vet-/compile-
  checked and (for the exe) reproducibility-verified on Linux, but not yet run
  against the monitor from their target machines.
