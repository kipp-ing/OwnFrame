# 900 Handover — session 1 → session 2 (2026-07-16)

State at pause: branch `900-photo-library-source`, **T001–T017 done and committed**
(tasks.md checkboxes are current), working tree clean. Foundational phase + PhotoLibraryKit
logic layer + real PHKitGateway are in. **Next task: T018** (US1 UI). Delegation model:
Fable orchestrates, Opus subagents implement (see `docs/implementation-session-plan.md`,
memory `opus-subagent-implementation`).

## What is true now (verified, committed)

- Engine is backend-neutral: SlideshowKit imports PhotoSourceKit only; `ImmichClient` and
  `PhotoLibraryProvider` are peer `PhotoSourceProviding` conformers.
- Gates passed at d593ee9: 9 package suites + app-hosted 24/24 on sim + zero-warning build
  (494 tests). Since then: +24 PhotoLibraryKit tests (da0bc24), PHKitGateway compiles for
  sim, host suites green (b98a40e).
- Fielded-device invariants test-pinned: snapshot JSON `{id,type}` byte-compatible (legacy
  fixture test), cache keys literal `asset#preview`/`asset#original`, backoff table and
  transient/auth split unchanged.
- `SlideshowViewModel(source:collectionID:)`; public property still named `albumID`
  (keeps snapshot file keys stable — deliberate).
- `PhotoLibraryProvider(gateway:collectionID:)` — carries its collectionID because
  `ensureReady()` takes no args; `nil` = enumeration-only (picker). Authorization gates
  (full/limited/denied/notDetermined incl. selected-photos-under-limited) are ALREADY
  implemented and tested — US3 (T027/28) only needs surface, not gate logic.
- Seam guard test permanently confines `import Photos` to `PHKitGateway.swift` (which is
  `#if canImport(Photos) && canImport(UIKit)` so macOS host tests build).

## Deliberate deviations / decisions already made (don't re-litigate)

1. **Immich vanish**: client collapses 404→`.invalidResponse`→`.transient` (can't reach
   `.notFound` without exposing HTTP status — frozen client). Recorded in data-model.md.
   Vanish state is reachable from the Photos backend (its raison d'être).
2. **`.permanent` → `.unsupportedServer` reason** (terminal, manual recovery) — carries the
   130 v3-notice; decode errors land there too.
3. **No reverse geocoding** (R7, FR-900-14): Photos assets show date only; `placeName` nil.
4. **HA adapter + AlbumBrowserView still consume `ImmichAPI`** (app target — allowed by
   FR-900-01). Migrating them to `collections()` is deferred to T020/T031.
5. **T020's "no leaked timers" engine test** may ride T026's dual-fake suite instead of a
   dedicated test — orchestrator call from session 1; keep or revisit cheaply.
6. Interim `.notFound` copy exists in `SlideshowErrorView` ("This source is gone"); full
   per-cause wording (incl. iOS-27 hint) is T030.
7. `ActiveSourceResolver` **throws** for `.photoLibrary` (it's Immich-only). The T020
   factory MUST branch on `SourceKind` BEFORE the resolver: `.photoLibrary` →
   `PhotoLibraryProvider(gateway: PHKitGateway(), collectionID:)`; else resolver path.
   Today `makeSlideshow` (OwnFrameApp.swift ~line 227) resolves first — rework it.

## Recon already done for T018/T019 (saves reading)

- `AlbumPickerView` (Onboarding/AlbumPickerView.swift) is Immich-`Album`-typed; build a
  sibling `PhotoAlbumPickerView` over `[SourceCollection]` mirroring its search-field +
  row + `idPrefix` accessibility pattern (`photos.album.*`), calling
  `viewModel.addPhotoLibrarySource(collectionID:label:)` (exists, tested). Simple
  title-contains filter is fine for the slice; AlbumSearch parity is polish.
- Settings entry point: `SourceLibraryView` presents `AddSourceView` sheet
  (SourceLibraryView.swift:74-76, sheet at line ~127+ has the kind tabs) — add a "Photos
  album" tab/affordance there; onboarding entry in `SourceStepView`.
- The picker takes a `any PhotoLibraryGateway` (calls `requestAuthorization()` itself on
  choose — FR-900-04), builds `PhotoLibraryProvider(gateway:)` for `collections()`.
- UITest seam: app-target needs its own in-app fake gateway under `UITestSupport`
  (test-target fakes are inaccessible) — deterministic collections, auth state via
  `--uitest-photos-auth=full|limited|denied|notDetermined`, launch arg `--uitest-photos`;
  hermetic slideshow for a photoLibrary source currently maps to stub album "a1"
  (OwnFrameApp.swift `makeSlideshowViewModel` switch — fine for T018).
- Purpose string: pbxproj uses `GENERATE_INFOPLIST_FILE = YES` →
  `INFOPLIST_KEY_NSPhotoLibraryUsageDescription` in build settings (both configs);
  T019 explicitly scopes this pbxproj edit.
- pbxproj package IDs use synthetic scheme `3DAA01000000000000000020`–`25` were claimed
  for the two new packages (session 1); next free suffix `…26`.

## Next steps in order

1. T018 red UITest (`PhotoAlbumPickerUITests`, hermetic) → T019 implement (picker, entry
   points, seam, plist key) → green. Simulator work = Fable-inline per house rules.
2. T020 factory-by-SourceKind (see deviation 7) + rebuild-strategy check (T011 already
   proved `restartStrategy` falls through to `.rebuild` for cross-kind).
3. T021 US1 checkpoint → then US2 (T022–T026, slice E delegate; includes the SC-900-03
   dual-fake gate) ∥ US3 (T027–T030, slice D delegate) — disjoint files.
4. Polish T031–T036; T035 full XCUITest before merge (memory: broker-toggle flake — rerun
   that class isolated); T036 schedules device/beta gates (SC-900-01/02/04/07).

## Verification commands (quickstart.md has the full gate list)

```bash
swift test --package-path Packages/PhotoSourceKit     # 10
swift test --package-path Packages/PhotoLibraryKit    # 24
swift test --package-path Packages/ImmichClient       # 73
swift test --package-path Packages/OnboardingKit      # 137
swift test --package-path Packages/SlideshowKit       # 133
# XcodeBuildMCP defaults: project + scheme "OwnFrame" + sim iPad Pro 13" (26.5,
# id CA71157B-6C86-43D2-9151-543BE1984649), preferXcodebuild — re-set per session.
```
