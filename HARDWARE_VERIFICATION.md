# Hardware verification

A build succeeding and tests passing are necessary but not sufficient for
anything that touches a real PS2 HDD's partition table, PFS filesystem, or
boot chain — this class of change needs to be confirmed against real
hardware before it's done. See `DEVELOPING.md` for getting a build onto a
real device first; this doc is what to actually check once it's there.

A Claude Code session has no interactive sudo and no direct raw-disk access
(no TTY for a password prompt, and reading/writing `/dev/rdiskN` needs
root). Every command below is run **by the user**, not the agent — the
agent's job is to hand over the exact command and interpret the output that
comes back, not to attempt it directly.

## When this applies

- Any change under `HelperTool/` (the privileged helper).
- Any change to `Scripts/pfsutil-src/pfsutil.c`, or to the vendored
  `hdl-dump`/`pfsshell` patches.
- Any change to `PFSDestinationPaths.swift`/`FreeHDBootDestinationPaths.swift`
  (where files land on the drive).
- Any change to boot-chain logic (`FreeHDBootService.swift`, MBR/FreeHDBoot
  injection).
- Any new "install onto the drive" feature, following the Apps/Video
  precedent.

## Before touching a real drive

1. **Never guess at a partition/PFS operation's behavior against a real
   drive — verify it against the tool's own docs/help/source first.** A
   guess here already corrupted a real PS2 HDD's partition table once on
   this project.
2. **Confirm the target disk out loud before anything destructive.** Ask
   the user to run `diskutil list` and confirm which `/dev/diskN` is
   actually the PS2 drive, not their Mac's own boot disk. The app's
   independent boot-disk guard is defense-in-depth, not a substitute for
   confirming the right disk first.
3. **Capture a "before" state for anything destructive** (partition
   create/delete, an APA wipe, boot-chain injection) — a read-only listing
   (see below) taken before the change, to compare against after.

## Deploying a build for testing

1. Build + install per `DEVELOPING.md`'s "Manual/on-device verification"
   section — ask the user to run the `cp`/`open`, and the
   `sudo launchctl kickstart -k system/com.michaeltremblay.machdl.helper`
   if `HelperTool/` changed.
2. **Confirm the daemon actually picked up the new binary before trusting
   any test run against it** — the daemon does not auto-reload on its own.
   Ask the user to check the running daemon's PID/binary timestamp (e.g.
   `ps aux | grep machdl.helper`, and compare the on-disk helper binary's
   modification time to when the app was just rebuilt) rather than assuming
   the restart worked. A hardware test against a stale daemon silently
   validates nothing.

## Verifying the result

Both vendored tools take the drive's raw/character device path
(`/dev/rdiskN`, not `/dev/diskN` — see `Disk.swift`'s `devicePath`), and
both are read-only for `list`/`toc` — ask the user to run these directly and
report back the raw output:

- **File/directory placement**: `sudo pfsutil list /dev/rdiskN <partition> <path>`
  (e.g. `sudo pfsutil list /dev/rdisk4 +OPL APPS` to confirm an installed
  app's folder landed where expected).
- **Partition table state**: `sudo hdl_dump toc /dev/rdiskN` (raw APA
  listing — confirms a partition was actually created/removed, and that
  nothing else on the drive got disturbed).

Both binaries are inside the built app bundle at
`macHDL.app/Contents/Resources/{pfsshell-bin,hdl-dump-bin}/`, so the exact
version under test is the one just built, not some other copy on the user's
Mac.

For boot-chain changes (FreeHDBoot install, PopStarter setup), a Mac-side
listing is not sufficient — the drive needs to actually boot on a real PS2
console before the change is considered verified.

## Reporting

State plainly whether hardware verification actually happened, not just
whether the build/tests passed — e.g. "build and tests pass; this still
needs hardware verification before I'd call it done" is the honest status
for this class of change. Don't imply hardware coverage that didn't happen.
