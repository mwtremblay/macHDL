# Vendored dependencies

macHDL wraps several vendored, open-source PS2-homebrew CLI tools rather than
reimplementing the HDL/APA/PFS formats itself (see the README for what each
one does and why it's vendored as a subprocess rather than linked). This
document is about *keeping them up to date* — see `RELEASING.md`'s Phase 0
for when this runs.

## Inventory

| Path | Upstream | Pinned via | Patched? |
|---|---|---|---|
| `Vendor/hdl-dump` | ps2homebrew/hdl-dump | git submodule commit | Yes — `Vendor/hdl-dump-macos.patch` |
| `Vendor/pfsshell` | ps2homebrew/pfsshell | git submodule commit | Yes — `Vendor/pfsshell-pfsutil.patch` |
| `Vendor/XADMaster` | MacPaw/XADMaster | git submodule commit | Yes — inline `sed` patches in `Scripts/build-unar.sh` |
| `Vendor/universal-detector` | MacPaw/universal-detector | git submodule commit | No |
| `Vendor/cue2pops-mac` | ErikAndren/cue2pops-mac | git submodule commit | No |
| `Vendor/psx-vcd` | leji-a/psx-vcd | git submodule commit | No |
| `Vendor/FreeMcBoot-Installer` | israpps/FreeMcBoot-Installer | git submodule commit | No (but see "forked resources" below) |
| `Vendor/ffmpeg-src` | ffmpeg.org release tarball | version + sha256 in `Scripts/build-ffmpeg.sh` | No (config-flag-patched at build time, not source-patched) |
| `Vendor/lame-src` | SourceForge release tarball | version + sha256 in `Scripts/build-ffmpeg.sh` | No |
| `Vendor/popstarter/*.ELF`/`.BIN` | NathanNeurotic/POPSLoader | **not vendored at all** — prebuilt binaries committed directly | N/A |

`popstarter`'s binaries have no update mechanism here — if POPSLoader ships a
new release, the `.ELF`/`.BIN` files under `Vendor/popstarter/` have to be
replaced by hand and re-verified on hardware; there's no source build for it
in this repo.

## What this app silently depends on the shape of

A version bump can change behavior this app relies on without touching any
patched file, so check these explicitly per dependency, not just "did the
patch still apply":

- **hdl-dump**: exit codes are mapped 1:1 into `HDLDumpError` (see that
  file's header comment referencing `retcodes.h`). An upstream retcode
  change breaks error mapping silently — no compiler error, just wrong
  error messages surfacing to the user.
- **pfsshell/pfsutil**: pfsutil is *this project's own C file*
  (`Scripts/pfsutil-src/pfsutil.c`), built against pfsshell's
  apa/pfs/iomanX libraries — a pfsshell internal API change could break the
  pfsutil build even though pfsutil.c itself didn't change. Also: pfsshell's
  own REPL output format is what `HDLDumpHelperService.swift`'s "(!) "
  error-prefix detection depends on (see that file's own doc comment on a
  past incident where this silently broke).
- **XADMaster/unar**: this app's `AppArchiveExtractor.swift` depends on
  unar's specific "always exactly one top-level output directory" wrapping
  behavior (confirmed by direct experimentation, not by unar's docs) — a
  behavior change here needs re-verifying against `AppArchiveExtractorTests`
  at minimum, ideally against a real archive too.
- **FreeMcBoot-Installer**: this app forks specific resources out of
  `installer_res/<version>/...` (see `Resources/FreeHDBoot/` and
  `FreeHDBootDestinationPaths.swift`) rather than using them in place. A
  version bump changing that directory layout, or the stock
  `FREEHDB.CNF`/menu format, needs the forked resources re-synced by hand —
  they will NOT update automatically just because the submodule commit did.
- **ffmpeg/LAME**: SMS's real decoder only accepts specific
  encoder/container/fourcc combinations (see `VideoConverter.swift`'s doc
  comments) — a version bump changing default encoder behavior needs the
  same fourcc byte-level verification (`xxd` on a real output file) done
  when this was first vendored, not just "it compiled."

## Update checklist (per dependency, one at a time)

1. **Check upstream for a newer commit/tag/release.** Read the range
   between the pinned commit and upstream's latest — changelog, commit
   log, or diff — before touching anything. Look specifically for anything
   touching what's listed above for that dependency.
2. **Bump it in its own commit**, never batched with other dependency
   bumps or with feature work. A regression has to be traceable to one
   change.
3. **For a patched dependency**, re-apply the patch against the new
   commit:
   - If it applies cleanly, still check whether upstream's own changes make
     the patch partially or fully obsolete (e.g. did they fix the same bug
     our patch works around?) — don't assume a clean `git apply` means
     nothing needs attention.
   - If it doesn't apply cleanly, read what actually changed in the
     patched region before writing a new patch — don't just force the
     context lines to match.
4. **For ffmpeg/LAME specifically**: update `FFMPEG_VERSION`/`FFMPEG_SHA256`
   or `LAME_VERSION`/`LAME_SHA256` in `Scripts/build-ffmpeg.sh`, confirm the
   new sha256 against the upstream release page directly (not a mirror),
   and bump `BUILD_SCRIPT_REVISION` — the build cache is keyed by it, and
   without bumping it a warm cache will keep serving the old binary
   regardless of what the version constants say.
5. **Build clean** (Debug is enough at this step): `xcodegen generate` +
   `xcodebuild build` + `xcodebuild test`.
6. **For ffmpeg specifically**, run `otool -L` on the built binary and
   confirm zero non-system (`/usr/lib`, `/System/Library`) dependencies —
   this is the actual regression test for portability to an end user's Mac,
   not "it built and tests passed" (see the libX11 incident this caught
   before it shipped).
7. **Hardware verification** — required for hdl-dump, pfsshell/pfsutil, and
   anything touching FreeMcBoot-Installer's payload (these all touch a real
   PS2 HDD's partition table or boot chain); use judgment for
   XADMaster/cue2pops-mac/psx-vcd/ffmpeg based on whether the update range
   touched behavior this app depends on per the list above.
8. **Run the standard three-pass review** (`/code-review`, `/simplify`,
   `/security-review`) against the patch-file/build-script diff before
   merging, same bar as any other change.
