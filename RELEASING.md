# Releasing macHDL

The standing process for cutting a release. Phase 0 + four phases, in order;
don't skip a phase or reorder them.

## Phase 0 — Check for vendored dependency updates

Check whether any of the vendored dependencies listed in `VENDORING.md` have
a newer upstream version worth pulling in. This is a judgment call, not an
unconditional requirement — an upstream security fix or a bug this app has
hit is worth pulling in now; unrelated upstream churn can wait for a release
where it's actually needed. If updating anything, follow `VENDORING.md`'s
per-dependency checklist (one dependency per commit, patches re-verified not
just re-applied, hardware verification where that dependency touches the
PS2's partition table/boot chain) before moving on — any dependency bump
becomes part of the diff Phase 1 reviews next.

## Phase 1 — Code quality review

Run three review passes against the pending diff (everything changed since
the last release, committed or not), fixing findings as they're found:

1. `/code-review` — correctness bugs.
2. `/simplify` — reuse, simplification, efficiency, altitude cleanups.
3. `/security-review` — security issues.

Report what was found/fixed (and what was deliberately skipped, with why) and
get explicit sign-off before moving on. If new issues turn up after sign-off
(e.g. a regression-test failure in Phase 3), fix them and repeat this phase
before continuing — don't patch ad hoc mid-release.

## Phase 2 — Version bump + build

1. Decide the version number (semver: patch for fixes only, minor for added
   functionality, matching this project's existing tag history).
2. In `project.yml`, update both:
   - `MARKETING_VERSION` — the version string.
   - `CURRENT_PROJECT_VERSION` — increment by 1. (This drifted for a while —
     v1.0.0 through v1.0.3 all shipped with `CURRENT_PROJECT_VERSION: "1"` —
     keep bumping it going forward.)
3. `xcodegen generate` to regenerate `mac-hdl-gui.xcodeproj/project.pbxproj`
   from `project.yml`.
4. Build Release to confirm everything compiles:
   ```
   xcodebuild -project mac-hdl-gui.xcodeproj -scheme mac-hdl-gui \
     -configuration Release -derivedDataPath <somewhere-outside-this-repo> build
   ```
   **The `-derivedDataPath` must be outside this repository.** The vendored
   pfsshell/pfsutil build (`Scripts/build-pfsshell.sh`) patches a scratch
   copy of `meson.build` via `git apply`, and `git apply` silently no-ops
   ("Skipped patch") when that scratch copy sits under a path this repo's
   own `.gitignore` excludes (e.g. `./build`) — discovered directly during
   this project's first CLI Release build. The build doesn't fail at the
   patch step; it fails much later with a confusing
   `Can't invoke target 'pfsutil': target not found` meson error that gives
   no hint the derived-data path was the cause. `Scripts/package-release.sh`
   (Phase 4) already does this correctly — prefer it over a raw
   `xcodebuild` invocation.

## Phase 3 — Regression tests

```
xcodebuild test -scheme mac-hdl-gui -destination 'platform=macOS'
```

Any failure means the diff isn't clean yet — fix it and go back to Phase 1
(re-review the fix) rather than patching around the test.

## Phase 4 — Commit, tag, package, publish

1. **Commit + tag.** One commit for the release, message format
   `vX.Y.Z: <short summary>` (matches every prior release commit — see
   `git log`). Then:
   ```
   git tag vX.Y.Z
   git push origin main vX.Y.Z
   ```
   Confirm the exact commit and tag before pushing — this is visible to
   others and not easily undone once pushed.

2. **Package.**
   ```
   ./Scripts/package-release.sh          # reads MARKETING_VERSION from project.yml
   ./Scripts/package-release.sh 1.2.3    # or pass the version explicitly
   ```
   Builds Release (with a correct out-of-repo derived-data path — see
   Phase 2's note), verifies the built app's `CFBundleShortVersionString`
   matches, and zips it via `ditto` (not `zip` — `ditto` preserves the
   resource forks/xattrs/code signature a plain zip of a signed `.app`
   would mangle) into `dist/macHDL-X.Y.Z.zip`. `dist/` is gitignored.

3. **Publish.** Draft release notes matching the existing template (see any
   prior release, e.g. `gh release view v1.0.3 --json body -q .body`):
   a "## What's new" bullet list, a link to
   `https://github.com/mwtremblay/macHDL/compare/vPREV...vX.Y.Z`, and the
   standing "## Download" section explaining the zip is signed with a
   personal Apple Development identity (not notarized) and needs
   `xattr -cr` after moving to `/Applications`, or building from source to
   avoid quarantine entirely. Then:
   ```
   gh release create vX.Y.Z dist/macHDL-X.Y.Z.zip --title "macHDL vX.Y.Z" --notes-file <notes-file>
   ```
   Show the drafted notes for a quick confirmation before actually
   publishing.
