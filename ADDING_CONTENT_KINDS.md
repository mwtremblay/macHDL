# Adding a new content kind

`GameKind` (PS2 games, PS1 games, Apps, Videos) is this app's abstraction
for "a kind of thing that can be listed/added/deleted on the PS2 drive."
Three real kinds exist beyond the original PS2 design point (PS1, then Apps
and Videos both followed the same shape). This is the checklist for the
next one, grounded in what's actually broken — or nearly broken — each time
this pattern got extended, not a hypothetical.

## The layer stack, one file per layer

1. **Model** — e.g. `InstalledApp.swift`, `VideoFile.swift`: a simple
   `Identifiable, Hashable` struct describing one item of this kind. No
   PFS/disk logic here — both existing examples are deliberately as thin as
   possible (a single identity field + a `displayName`).
2. **Destination paths** — add to `PFSDestinationPaths.swift` (or
   `FreeHDBootDestinationPaths.swift` if it's FreeHDBoot-specific): a
   `static let <kind>PartitionName` constant + `static func
   <kind>...PFSPath(...)` builder function(s), mirroring
   `oplAppPFSPath`/`smsMediaVideoPFSPath`'s existing shape.
3. **Partition-name allowlist — the most commonly forgotten step.** Add the
   new partition name to `HDLDumpHelperService.swift`'s
   `isValidPFSPartitionNameForPartitionOps` (and
   `isValidPFSPartitionNameForFileWrite` too, but only if the kind needs to
   write into `__system`/`__sysconf` — no content kind has needed that so
   far). **This is a hardcoded literal list, not derived from the path
   constant added in step 2** — adding that constant does not
   automatically satisfy this check. It's already been forgotten once
   (`SMS_Media` was missing on the first pass, breaking every video install
   with `"refused: invalid PFS partition name"` until caught). See
   `VENDORING.md`/the architecture memory for why this hasn't been
   structurally fixed (it would mean moving partition-name constants across
   the HelperTool/app target boundary — a bigger change than any single
   content-kind addition warrants on its own).
4. **Service** — e.g. `AppsService.swift`, `SMSMediaService.swift`: compose
   `PS1GameService`'s generic primitives (`partitionExists`, `listFiles`/
   `listDirectories`, `putFile`, `removeFile`/`removeTree`,
   `guardNotBootDisk`) — do not reimplement any of these. Add a
   `create<Kind>PartitionIfNeeded` wrapper *on `PS1GameService` itself*
   (it now delegates to a shared private `createPartitionIfNeeded(name:
   sizeBytes:on:)` helper — extend that, don't hand-roll another
   check-then-create block).
5. **ViewModels** — a list ViewModel (`@Published` items array,
   `pendingDelete<Kind>`, a `selected<Kind>` computed property, `refresh
   (disk:)`/`confirmDelete(...)`) and an add-flow ViewModel (`Phase` enum,
   the elapsed-timer pattern, `isValid<Kind>Name` delegating to
   `Sources/Shared/PFSPathComponentValidation.swift` — don't reimplement
   that validation inline), both modeled directly on the existing
   Apps/Videos pair.
6. **View/Sheet** — a list view and an add sheet, modeled on the existing
   ones.
7. **Wire into `ContentView.swift`** — the largest, most error-prone step;
   see below.
8. **Tests** — mirror the existing naming:
   `PFSDestinationPaths<Kind>Tests.swift` for the path builders,
   `Add<Kind>ViewModelTests.swift` for the client-side validator, plus a
   model test file if the model has any logic beyond field access.

## Wiring into ContentView.swift

Add the new `GameKind` case, then work through every one of these — Swift's
switch exhaustiveness only catches some of them, not all:

- `GameKind.hasArtwork` (or the real artwork-loading logic, if this kind
  does have cover art) — **exhaustive**, compiler-checked.
- `isDeleteButtonDisabled`, `addButtonLabel`, `deleteButtonLabel` —
  **exhaustive**, compiler-checked.
- The refresh call sites: `.task` on appear, `.onChange(of:
  driveListViewModel.selectedDiskID)`, the toolbar Refresh button, and (if
  this kind should refresh when its own tab is selected) `.onChange(of:
  selectedGameKind)`. **These are NOT exhaustive** (`.onChange(of:
  selectedGameKind)` is an `if selectedGameKind == .x` chain, not a
  `switch`) — a missed one fails silently: a stale or empty list, no
  compiler error, no crash.
- Sheet/alert wiring: **don't add a 4th+ pair to an existing chained
  modifier method.** `appsAndVideosErrorAlerts` was split out of
  `gameErrorAlerts` after a single method covering all four kinds' error
  sheet+alert pairs hit "the compiler is unable to type-check this
  expression in reasonable time" at exactly 4 pairs (see that method's own
  doc comment, which says explicitly: "Each additional GameKind's
  error-alert pair should get its own small chained method like this one,
  not grow an existing one further"). Give the new kind its own small
  chained method, same shape.
  **`deleteAlerts` is currently one method covering all 4 existing kinds
  and has not yet been split** — it's at the same pair-count where
  `gameErrorAlerts` broke. Split it preemptively when adding the next kind
  rather than waiting to hit the same compiler timeout.

## Before calling it done

- Full build + `xcodebuild test` — see `DEVELOPING.md`.
- Hardware verification per `HARDWARE_VERIFICATION.md` — this is always an
  "install onto the drive" feature.
- The standard three-pass review (`/code-review`, `/simplify`,
  `/security-review`).
