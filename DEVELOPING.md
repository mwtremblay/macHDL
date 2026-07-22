# Developing macHDL

The loop for iterating on changes locally: checking work compiles, passing
tests, and getting a build onto a real device for manual verification. For
cutting a release see `RELEASING.md`; for updating a vendored dependency see
`VENDORING.md`. For initial clone/`brew install` setup, see the README's
"Building" section — not repeated here.

## The edit-check-build loop

1. **Fast syntax check after editing a single file:**
   ```
   swiftc -parse Sources/Path/To/File.swift -o /dev/null
   ```
   Catches real syntax errors (mismatched braces, keyword typos) in about a
   second, before paying for a full build. It will also report a wall of
   `cannot find type 'X' in scope` errors for every cross-file symbol the
   file references — that's expected noise from parse-only mode (no
   whole-module type-checking runs), not a real problem. Only trust this
   check for syntax breakage, not type-correctness; a clean run here doesn't
   mean the project builds.

2. **Regenerate the Xcode project whenever `project.yml` changes, or a
   source file is added/removed/moved:**
   ```
   xcodegen generate
   ```
   `xcodegen` snapshots the directory listing into `project.pbxproj` at
   generation time — a new file sitting in `Sources/` (even under a
   directory `project.yml` already globs) is invisible to any real build
   until this runs. Confirmed directly: a new file added mid-session wasn't
   visible to `xcodebuild` until the next `xcodegen generate`, despite
   `Sources/` already being a globbed path in `project.yml`.

3. **Full build, to catch real compile errors:**
   ```
   xcodebuild -project mac-hdl-gui.xcodeproj -scheme mac-hdl-gui -configuration Debug build
   ```
   No `-derivedDataPath` needed for an ordinary dev build — Xcode's default
   location (`~/Library/Developer/Xcode/DerivedData/`) is already outside
   this repo, so the pfsshell/pfsutil `git apply` issue documented in
   `RELEASING.md` (Phase 2) doesn't apply here. Only pass an explicit
   `-derivedDataPath` if something needs a stable, predictable output path
   (e.g. scripting around the build) — and if you do, it must still be
   outside the repo.

4. **Run tests:**
   ```
   xcodebuild test -scheme mac-hdl-gui -destination 'platform=macOS'
   ```

## Editor/SourceKit noise while mid-edit

Live diagnostics like `Cannot find type 'X' in scope` appearing for
pre-existing, unrelated types (not just the lines just touched) are
stale-index noise, not real errors — they show up whenever the project
hasn't been reindexed since a file was added or `xcodegen generate` last
ran. Confirm with an actual build (step 3 above) rather than trusting them.

## Manual/on-device verification

Required for anything touching `HelperTool/`, or that needs a real PS2
drive to confirm end-to-end (any HDL/APA/PFS/PopStarter/FreeHDBoot work) —
unit tests and a clean build are necessary but not sufficient for this
class of change.

1. Install to a stable path — the privileged helper is registered via
   `SMAppService`, which only works reliably from a fixed location:
   ```
   cp -R ~/Library/Developer/Xcode/DerivedData/mac-hdl-gui-*/Build/Products/Debug/macHDL.app /Applications/
   open /Applications/macHDL.app
   ```
2. If `HelperTool/` changed, the already-running daemon won't pick up the
   new binary on its own — restart it:
   ```
   sudo launchctl kickstart -k system/com.michaeltremblay.machdl.helper
   ```

Both of these need a real, interactive password prompt that a non-interactive
session can't provide — ask the user to run them directly (they can use the
`!` prefix to keep the output in-session) rather than attempting either from
an automated session.
