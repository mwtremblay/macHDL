# macHDL

A native macOS SwiftUI app for managing a PS2 hard drive formatted in HDL
(APA) format over a USB-SATA/IDE enclosure — view, add, and delete PS2 games,
and (optionally) set up PopStarter to run PS1 games from the same drive.

macHDL wraps several vendored, open-source PS2-homebrew CLI tools rather than
reimplementing the HDL/APA/PFS formats itself:

- [`hdl-dump`](https://github.com/ps2homebrew/hdl-dump) — reads/writes the
  HDL partition table and injects PS2 CD/DVD images.
- [`pfsshell`](https://github.com/ps2homebrew/pfsshell) — creates the PFS
  partitions PopStarter needs (`__common`, `__.POPS`).
- `pfsutil` — a small CLI (`Scripts/pfsutil-src/pfsutil.c`), written for this
  project, that transfers files into/out of those PFS partitions.
- [`cue2pops-mac`](https://github.com/ErikAndren/cue2pops-mac) — converts a
  PS1 `.bin`/`.cue` image to the `.VCD` format PopStarter expects.
- [`POPSLoader`](https://github.com/NathanNeurotic/POPSLoader) — provides
  `POPSTARTER.ELF`/`POPSLOADER.ELF`/`PATCH_5.BIN`, the loader that actually
  boots a PS1 game on the console.

## Requirements

- macOS 14 or later.
- A PS2 hard drive (already HDL/APA-formatted) connected via a USB-SATA or
  USB-IDE enclosure.
- **Full Disk Access** granted to the app's privileged helper (the app will
  prompt and walk you through this on first use).
- For PS1/PopStarter support only: your own legally-extracted copies of
  `POPS.ELF` and `IOPRP252.IMG` from your own PS2 console. **macHDL never
  bundles, fetches, or embeds these** — they're Sony's copyrighted PS2 system
  software. (`POPS.PAK`/`POPS_IOX.PAK` are the same — also user-supplied, but
  optional; a game launches fine without them in testing.)

## Features

- Lists all PS2 games on the drive, with per-game info.
- Adds a new PS2 game from a CD/DVD image, with live install progress.
- Deletes a PS2 game.
- One-time PopStarter setup: creates the `__common` PFS partition and
  installs the required system files (prompting for the two Sony-copyrighted
  ones, auto-installing the rest).
- Adds a PS1 game from a `.bin`/`.cue` pair: converts it to `.VCD` via
  `cue2pops`, creates the `__.POPS` PFS partition if needed, and copies it
  onto the drive.
- Refuses to operate on your Mac's own boot disk, checked independently by
  the privileged helper (not just a UI-level confirmation).

## Building

```bash
git clone --recurse-submodules <this-repo-url>
cd mac-hdl-gui
brew install xcodegen meson ninja
xcodegen generate
open mac-hdl-gui.xcodeproj
```

Build the `mac-hdl-gui` scheme in Xcode (or `xcodebuild -scheme mac-hdl-gui
build`). The vendored `hdl-dump`, `pfsshell`/`pfsutil`, and `cue2pops`
binaries are built and code-signed automatically as part of the app build
(see `Scripts/build-*.sh`).

### Development install

The app's privileged helper is registered via `SMAppService`, which only
works reliably when the app runs from a stable path:

```bash
cp -R ~/Library/Developer/Xcode/DerivedData/mac-hdl-gui-*/Build/Products/Debug/macHDL.app /Applications/
open /Applications/macHDL.app
```

If you've changed anything under `HelperTool/`, the already-running daemon
won't pick up the new binary on its own — restart it after reinstalling:

```bash
sudo launchctl kickstart -k system/com.michaeltremblay.machdl.helper
```

## Usage

1. Connect your PS2 drive's enclosure and launch macHDL. Select the drive
   from the sidebar.
2. Approve the privileged helper and grant Full Disk Access when prompted
   (one-time setup).
3. Use **Add Game** to install a PS2 game from a CD/DVD image, or select a
   game and delete it from the list.
4. For PS1 support: run **PopStarter Setup** once (supplying your own
   `POPS.ELF`/`IOPRP252.IMG`), then use **Add PS1 Game** to install games
   from `.bin`/`.cue` pairs.

## Distribution note

The app cannot be sandboxed — it shells out to bundled CLI tools, opens raw
disk devices, and talks to a privileged XPC helper daemon, none of which are
permitted under the App Sandbox. This means Developer ID distribution only;
it cannot be distributed via the Mac App Store.
