---
description: "Task list for Source Library (120) implementation"
---

# Tasks: Source Library (multiple switchable slideshow sources)

**Input**: Design documents in `specs/120-source-library/` (plan.md, spec.md, research.md,
data-model.md, contracts/source-library.md, quickstart.md)

**Tests**: REQUIRED — Constitution I (Test-First, NON-NEGOTIABLE). Every implementation task is
preceded by a red Swift Testing (host) or XCUITest task; no code before a demonstrably red test.

**Organization**: by user story (US1–US4 from spec.md). Setup + Foundational are shared prerequisites.

## Status (checkboxes reconciled 2026-07-19)

Ticked in this pass, against evidence rather than new work:

- **T001–T013** — the 2026-06-24 progress note below records "Done & verified: T001–T016"; only
  T014–T016 had been ticked.
- **T023–T026 (US3, HA select backed by the library)** — satisfied by later work under `900`, not
  under these IDs: `SlideshowRemoteControlAdapter` takes `sources: [Source]`, publishes source
  labels as the select's options, and resolves a picked label back to a `Source`
  (`Immich Slideshow/Slideshow/SlideshowRemoteControlAdapter.swift:31,46,142` — FR-900-11).
- **T031** — the full XCUITest suite has run green many times since 120 merged.
- **T030** — done *in* this pass: `specs/200-connection-onboarding/spec.md`'s Roadmap item
  (110 placeholder + "Settings placeholder deferred") was superseded in place, and `510` was
  added to `docs/spec-overview.md`. 700's Roadmap needed no change — its only entry is `730`,
  which is genuinely still deferred.

**Genuinely open:**

- **T027–T029 (US4 persistence + secret hygiene)** — mixed-library relaunch persistence works in
  production, but T028's specific assertion (dump the UserDefaults suite + the encoded library and
  assert no password/API key appears) has **no test in the repo**. `docs/spec-traceability.md`
  carries secret-absence only as a *manual* audit gate. This is the one real code/test gap 120 has
  left.
- **T032/T033** — secret grep + log check; changelog. Not evidenced either way.

## Progress (2026-06-24, cont.) — US2 onboarding redesign DONE

- **US2 onboarding redesign done & verified** (T017, T019, T021, T022): the onboarding flow is now
  connection → **add source** (`Immich Slideshow/Onboarding/SourceStepView.swift`: segmented album
  picker / shared-link URL+password form, reusing `SourceLibraryViewModel`) → **confirm**
  (`OnboardingConfirmStepView` lists the library, marks the active source, Start) → slideshow. The
  `.album` onboarding step was renamed `.source` and a `.confirm` step added (`OnboardingStep`).
- **Logic generalized off `selectedAlbumID`** (plan: "superseded by the library"): added
  `ConfigStore.saveBaseURL` (base URL persisted at connection so a shared-link-first install with no
  album still resolves); `StartupGate` now takes a `SourceLibraryStore` and routes `.done` on
  key+baseURL+active-source, `.source` when connected but no source, else `.connection` (legacy
  `selectedAlbumID` still migrates to `.done`); `OnboardingViewModel.submitConnection` persists the
  base URL and advances to `.source` even with zero albums; `finish()` keeps `AppConfiguration`
  populated for an album active source (HA album list / 009 re-select stay working) and needs only the
  base URL for a shared-link source. App: `resolveActiveSource`/`makeServerAPI` use `loadBaseURL`.
- **Verification**: OnboardingKit **76 host tests** green; app builds clean; **full XCUITest suite 30
  + launch runs green** including new `SourceOnboardingUITests` (album + shared-link onboarding both
  reach the running slideshow with the chosen source's photos). Fixed a continue-button race (wait for
  `onboarding.source.continue` to exist before tapping). Source step screenshotted (portrait). New
  `--uitest-onboarding-source` visual-verification seam; uitest seam reworked so onboarding + the
  slideshow share one set of in-memory stores (an onboarded source flows into the show).
- **Resume here → US3 (HA) T023–T026**, then US4 (persistence/secret gate) T027–T029, then polish
  T030–T033 (incl. moving source management/select from Roadmap to Active in 200/700 specs +
  `docs/spec-overview.md`; secret grep; real-link end-to-end). Then carried-over 300/500 items.

## Progress (2026-06-24) — branch `feat/120-source-library`

- **Done & verified**: T001–T016 (Setup + all Foundational + **US1 complete**). OnboardingKit 54
  tests + ImmichClient 34 tests green on host; app builds clean via XcodeBuildMCP; SlideshowChrome
  XCUITests (4) green. US1 wiring: `Immich_SlideshowApp` builds slideshow/API from the **active
  source** via `ActiveSourceResolver`; `switchActiveSource` + `RootView.switchSource` persist + restart
  (`switchAlbum` for album→album, full rebuild for album↔link, via `SourceLibrary.restartStrategy`);
  `saveSelectedAlbum` reconciles the library (`updateActiveAlbumID`) so the 009 album re-select stays
  in sync.
- **T016 note**: switch *decision* host-tested (restartStrategy/updateActiveAlbumID); app build + chrome
  XCUITest green. The UI-*driven* 2-source switch in the running slideshow is deferred to T018/T022
  (Settings Sources manager) and T026 (HA) where a tappable switch control exists — no throwaway
  debug-switch seam built.
- **US2 order decided** (user): Settings manager first (T018/T020), then onboarding (T017/T019/T021),
  then T022. Onboarding keeps working via the existing album step → 1-entry library migration.
- **US2 backbone done & host-green** (T020 logic): `SharedLinkURL.parse` (`https://<host>/s/<slug>`) +
  `SourceLibraryViewModel` (load/add-album/add-shared-link[validate+secret]/remove[delete secret]/
  rename/move/setActive→delegates to US1 `switchActiveSource`) in OnboardingKit. OnboardingKit now 72
  tests green; ImmichClient 34 green.
- **US2 Settings manager done & verified** (T018, T020, T022-partial): `SourceLibraryView` (list +
  set-active + swipe rename/delete + reorder + add album/shared-link) surfaced via a NavigationLink in
  `SlideshowSettingsView`; `makeServerAPI` + `makeSourceLibraryViewModel` factories wired
  RootView→SlideshowView→Settings (`onSwitchActive` → `RootView.switchSource`). UITest seam reworked to
  a hermetic in-memory source library (per-album stub photos a1→asset-1..3 / a2→asset-4..6);
  `slideshow.image` now exposes the current asset id as its a11y value. `SourceLibraryUITests` (add /
  switch-swaps-slideshow / remove) green; **full UITest suite 19 green** (fixed a scroll-fragility in
  `BrokerSetupUITests` exposed by the new Settings section — now scrolls to the password hint).
  Sources manager screenshotted portrait + landscape. New `--uitest-sources` auto-open seam.
- **Resume here → T017/T019/T021** (US2 onboarding redesign, inline SwiftUI): onboarding add-source step
  (album picker / shared-link form) + confirmation listing the library; then T017 red XCUITest closes
  out T022.
- Remaining: T017/T019/T021 (onboarding UI), T023–T026 (US3 HA, Codex+wiring), T027–T029 (US4
  persistence/secret gate, Codex), T030–T033 (polish). Then the carried-over 300/500 items
  (clock-overlay renderer, disk cache, auto-retry, periodic refresh).

## Format: `[ID] [P?] [Story] Description with file path`

- **[P]**: parallelizable (different files, no dependency on an incomplete task)
- Delegation: logic phases (Setup/Foundational/US1/US3/US4 logic) → **Codex** (host `swift test`).
  SwiftUI/onboarding/Settings (US2) and all simulator/XCUITest verification → **Claude inline**.

---

## Phase 1: Setup

- [X] T001 Establish a green host baseline: run `swift test` for `ImmichClient`, `OnboardingKit`,
  `HAControlKit` before any change; record the passing baseline.

---

## Phase 2: Foundational (blocking — required by all stories)

**Source model + persistence + secrets + auth/transport. Complete before US1–US4.**

- [X] T002 [P] Red tests for `Source`/`SourceKind` + `SourceLibrary` operations (add → first becomes
  active; `setActive`; `remove(active)` promotes next else nil; `move`; `rename`; unique-label
  enforcement; single-active invariant) in `Packages/OnboardingKit/Tests/OnboardingKitTests/SourceLibraryTests.swift`
- [X] T003 Implement `Source.swift` + `SourceLibrary.swift` in
  `Packages/OnboardingKit/Sources/OnboardingKit/` to green T002
- [X] T004 [P] Red tests for `UserDefaultsSourceLibraryStore`: round-trip save/load of a mixed
  library; migration from legacy `immich.selectedAlbumID` (absent library → one-entry album library,
  active) in `Packages/OnboardingKit/Tests/OnboardingKitTests/SourceLibraryStoreTests.swift`
- [X] T005 Implement `SourceLibraryStore.swift` (protocol + `UserDefaultsSourceLibraryStore` + migration
  + in-memory fake) in `Packages/OnboardingKit/Sources/OnboardingKit/` to green T004
- [X] T006 [P] Red tests for `SharedLinkSecretStore` (per-source password save/read/delete; deleting a
  source deletes its password) in `Packages/OnboardingKit/Tests/OnboardingKitTests/SharedLinkSecretStoreTests.swift`
- [X] T007 Implement `SharedLinkSecretStore.swift` (protocol + Keychain impl + in-memory fake) in
  `Packages/OnboardingKit/Sources/OnboardingKit/` to green T006
- [X] T008 [P] Red tests for `ServerConfig.Auth`: `ImmichClient` sets the `x-api-key` header (no
  `key=` query) for `.apiKey`, and appends `key=<token>` (no header) for `.shareKey`, on album/asset
  requests, in `Packages/ImmichClient/Tests/ImmichClientTests/AuthModeTests.swift`
- [X] T009 Implement `ServerConfig.Auth` (`.apiKey`/`.shareKey`, keep an `apiKey:` convenience init)
  + request-building branch in `Packages/ImmichClient/Sources/ImmichClient/ServerConfig.swift` and
  `ImmichClient.swift` to green T008
- [X] T010 [P] Red tests for shared-link resolve mapping (200 → `(key, albumID, expiresAt)`; 401+pw →
  `wrongPassword`; 401 no-pw → `passwordRequired`; unknown/expired → `invalidShareLink`/
  `shareLinkExpired`; transport fail → `unreachable`; `me` response never logged) with a stub
  transport in `Packages/ImmichClient/Tests/ImmichClientTests/SharedLinkResolverTests.swift`
- [X] T011 Implement `SharedLinkResolver.swift` + new `ImmichError` cases in
  `Packages/ImmichClient/Sources/ImmichClient/` to green T010

**Checkpoint**: model, store+migration, secret store, dual-auth client, and resolver are green on host.

---

## Phase 3: US1 — Save several sources and switch the active one (P1) 🎯 MVP

**Goal**: the active source (album or shared link) feeds the engine; switching swaps the show.
**Independent test**: seed a 2-source library (album + shared link via stubs); only the active
source's photos show; switching active swaps to the other source's photos.

- [X] T012 [P] [US1] Red tests for `ActiveSourceResolver`: `.album` → `(ServerConfig.apiKey, albumID)`;
  `.sharedLink` → resolve (stub) → `(ServerConfig.shareKey(key), resolvedAlbumID)`; resolve failure
  surfaces the typed error, in `Packages/OnboardingKit/Tests/OnboardingKitTests/ActiveSourceResolverTests.swift`
- [X] T013 [US1] Implement `ActiveSourceResolver` (Source + Keychain API key + `SharedLinkSecretStore`
  + `SharedLinkResolving` → `ServerConfig` + albumID) in `Packages/OnboardingKit/Sources/OnboardingKit/`
  to green T012
- [X] T014 [US1] Wire `Immich_SlideshowApp` factories (`makeSlideshow`, `makeAPI`) to build the
  `ImmichClient` + albumID from the **active source** via `ActiveSourceResolver` instead of
  `selectedAlbumID`, in `Immich Slideshow/Immich_SlideshowApp.swift`
- [X] T015 [US1] Implement source switching at the app level: switching the active source persists it
  and restarts the slideshow from it — `switchAlbum(albumID)` when only the album changes, full
  slideshow rebuild (existing `connectionGeneration` path) when the client/auth changes (album↔link),
  in `Immich Slideshow/Immich_SlideshowApp.swift` (+ `RootView`)
- [X] T016 [US1] Verify via XcodeBuildMCP/XCUITest (`--uitest`): hermetic 2-source library switches in
  the running slideshow (extend the UI-test seam + `SlideshowChromeUITests`/a new test)
  — switch decision host-tested + app build + chrome XCUITest green; UI-driven switch deferred to
  T018/T022/T026 (see Progress note)

**Checkpoint**: MVP — sources switchable in-app, only the active source plays.

---

## Phase 4: US2 — Add the first source in onboarding, manage in Settings (P1)

**Goal**: add/manage sources from onboarding + Settings (the `200` surface). **Claude inline (SwiftUI)**.
**Independent test**: onboarding adds a first source and completes; Settings adds a second, switches,
removes; confirmation lists the library with the active one marked.

- [X] T017 [P] [US2] Red XCUITest: onboarding "add source" (album pick or shared-link form) → confirm
  → slideshow runs the chosen source, in `Immich SlideshowUITests/SourceOnboardingUITests.swift`
- [X] T018 [P] [US2] Red XCUITest: Settings → Sources manager adds a second source, switches active,
  removes one; running slideshow swaps on switch, in `Immich SlideshowUITests/SourceLibraryUITests.swift`
- [X] T019 [US2] Build the onboarding add-source step (album picker / shared-link URL+password form)
  in `Immich Slideshow/Onboarding/SourceStepView.swift` (+ wire into `OnboardingFlowView`)
- [X] T020 [US2] Build the Settings **Sources** manager (list + add/remove/reorder/rename/set-active,
  unique-label enforced) in `Immich Slideshow/Slideshow/SourceLibraryView.swift` and surface it in
  `Immich Slideshow/Slideshow/SlideshowSettingsView.swift`
- [X] T021 [US2] Make the onboarding confirmation list the library and mark the active source
  (`OnboardingConfirmStepView` in `SourceStepView.swift`)
- [X] T022 [US2] Green T017/T018 via XcodeBuildMCP/XCUITest; screenshot portrait + landscape
  — full XCUITest suite 30 + launch runs green (incl. `SourceOnboardingUITests`); Sources manager +
  onboarding source step screenshotted (Settings manager portrait+landscape earlier; source step
  portrait). Landscape Form reachability guarded by `SettingsUITests`.

**Checkpoint**: full source management from onboarding + Settings.

---

## Phase 5: US3 — Switch the active source from Home Assistant (P2)

**Goal**: the existing HA select lists the saved sources; selecting switches the active source.
**Independent test (mock transport)**: discovery `options` == source labels; known label switches +
echoes; unknown label = no-op echo.

- [X] T023 [P] [US3] Red tests: `SlideshowRemoteControlAdapter` backed by a 2-source `SourceLibrary`
  → `albumOptions` == labels; `selectAlbum(label)` switches active + `currentAlbum` echoes; unknown
  label no-op, in `Immich SlideshowUITests`/a host test, or `Packages/HAControlKit/Tests/HAControlKitTests/`
  (adapter lives in the app target — place the adapter test where it compiles, mirroring the existing
  adapter tests)
- [X] T024 [US3] Back `SlideshowRemoteControlAdapter` with the `SourceLibrary` + `ActiveSourceResolver`
  (options/current/select over source labels; select switches active source) in
  `Immich Slideshow/Slideshow/SlideshowRemoteControlAdapter.swift`
- [X] T025 [US3] Wire `Immich_SlideshowApp.makeCoordinator` to pass the library to the adapter instead
  of the server album list, in `Immich Slideshow/Immich_SlideshowApp.swift` (HA entity key `album`
  stays stable; options now = source labels — research D5)
- [X] T026 [US3] Verify HA select round-trip with the mock transport (extend the coordinator tests in
  `Packages/HAControlKit/Tests/HAControlKitTests/`)

**Checkpoint**: HA switches the active source.

---

## Phase 6: US4 — Migrate and persist transparently (P2)

**Goal**: legacy single-album installs migrate; library + active survive relaunch; secrets stay in
Keychain. (Migration logic is built in T004/T005; this phase is the end-to-end + secret-hygiene gate.)
**Independent test**: legacy `selectedAlbumID` → one-entry active library; relaunch restores; no
password/bearer key in UserDefaults/logs.

- [ ] T027 [P] [US4] Red test: end-to-end relaunch — save a mixed library (incl. a password-protected
  shared link), reload via a fresh store instance → sources + active restored; password only via the
  secret store, in `Packages/OnboardingKit/Tests/OnboardingKitTests/SourceLibraryPersistenceTests.swift`
- [ ] T028 [P] [US4] Red test: secret hygiene — dump the UserDefaults suite + the encoded library JSON
  and assert no password and no bearer key appear, in the same persistence test file
- [ ] T029 [US4] Make T027/T028 green (adjust store/secret handling as needed); confirm migration leaves
  the legacy key harmless and unread once a library exists

**Checkpoint**: persistence + migration + secret hygiene proven.

---

## Phase 7: Polish & Cross-Cutting

- [X] T030 [P] Update `specs/200-connection-onboarding/spec.md` and `specs/700-ha-control/spec.md`:
  move the now-built source management / source-select from Roadmap to Active (FR IDs), and reconcile
  `docs/spec-overview.md`
- [X] T031 Run the **full XCUITest** suite via XcodeBuildMCP (`test_sim`) — green before merge
- [ ] T032 Secret grep over the test suite + a manual log check (no password/bearer key in logs);
  manual end-to-end with the real links (`geo2026`, `korsika2026`/`12345678`)
- [ ] T033 [P] Update `CHANGELOG`/engineering notes if applicable; ensure new files build in the app
  target (synchronized groups — no pbxproj edit)

---

## Phase 8: QR on the shared add-source form (FR-120-12, added 2026-07-19)

**Goal**: the scan affordance exists wherever a shared link can be added, not only on the
first-run path — Settings → Sources and the onboarding add-source step both use
`SharedLinkAddForm`, so one change serves both. No new scanning code: `QRScanner`,
`CodeScanning`, `ScannedShareLink` and `SourceLibraryViewModel.addScannedSharedLink` already
shipped with 220.

- [X] T034 Host pins in
      `Packages/OnboardingKit/Tests/OnboardingKitTests/ScannedLinkRoutingTests.swift`: a scanned
      link keeps the name typed alongside it, and an empty name still derives one. **Green on
      write** — the view model already threaded `label` through `resolveSharedLink`; only the UI
      discarded it. Recorded as regression pins, not as a red-then-green cycle (same pattern as
      220/T006).
- [X] T035 Red XCUITest in `Immich SlideshowUITests/SourceLibraryUITests.swift`:
      `testAddSharedLinkFormOffersQRScanAlongsideManualEntry` — Settings → Sources → + → Shared
      link exposes `sources.add.scan`, and the URL + name fields stay present so a denied or
      missing camera can never strand the user (FR-220-05 parity). Verified RED first (button
      absent), then green.
- [X] T036 Implement in `Immich Slideshow/Onboarding/SharedLinkAddForm.swift`: `Scan QR` button
      (`\(idPrefix).scan`), `.fullScreenCover` anchored on the URL field's always-present leaf
      (Form/List drops `Section` modifiers — same reason the password sheet hangs there), and
      `startScan()` passing `labelText` to `addScannedSharedLink(using:label:)` rather than the
      first-run path's `""`. tvOS is unaffected: its target compiles only `Immich SlideshowTV/`.

## Dependencies & order

- **Setup (P1)** → **Foundational (P2)** → stories.
- **US1 (P3)** depends on Foundational; it is the MVP.
- **US2 (P4)** depends on US1 (needs the active-source wiring + switch).
- **US3 (P5)** depends on Foundational (library + resolver); independent of US2.
- **US4 (P6)** depends on Foundational (store + migration + secrets); independent of US2/US3.
- **Polish (P7)** last.

## Parallel opportunities

- Within Foundational: T002/T004/T006/T008/T010 (red tests, different files) run in parallel; each
  impl task follows its own red test.
- US3 and US4 can proceed in parallel once Foundational is green.
- US2 is the only inline (SwiftUI) story; it can be built while US3/US4 logic is delegated to Codex.

## Implementation strategy (incremental delivery)

1. **MVP = Setup + Foundational + US1** — sources switchable in-app, only the active source plays.
2. Add **US2** (UI) so users can actually add/manage sources.
3. Add **US3** (HA) and **US4** (migration/persistence gate) — parallelizable.
4. **Polish** — spec reconciliation, full XCUITest, secret check, real-link end-to-end.
