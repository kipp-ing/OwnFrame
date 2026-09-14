---
description: "Task list for Shared-Link Onboarding & iOS Share Sheet (210) implementation"
---

# Tasks: Shared-Link Onboarding & iOS Share Sheet

**Input**: Design documents in `specs/210-shared-link-onboarding/` (plan.md, spec.md, research.md,
data-model.md, contracts/shared-link-onboarding.md, quickstart.md)

**Tests**: REQUIRED — Constitution I (Test-First, NON-NEGOTIABLE). Every implementation task is
preceded by a red Swift Testing (host) or XCUITest task; no code before a demonstrably red test.

**Organization**: by user story (US1–US5 from spec.md). Setup + Foundational are shared prerequisites.

**Orchestration note**: per `CLAUDE.md`, pure/host logic (gate, resolve state machine, search
predicate, router, stores, URL extraction) is Codex-delegable; SwiftUI surfaces, the app entry point,
onboarding wiring, the Share Extension target + App Group entitlement, and signing are **keep-inline**.

## Path Conventions

- Packages: `Packages/<Pkg>/Sources/...`, host tests `Packages/<Pkg>/Tests/...` (`swift test`).
- App: `OwnFrame/...`; UI tests `OwnFrameUITests/...` (XcodeBuildMCP + XCUITest).
- New extension target: `OwnFrameShareExtension/...`.

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: Album metadata needed by US2 (default labels) and US3 (search).

- [X] T001 [P] Red test: `Album` decodes `assetCount`/`startDate`/`endDate` from `GET /api/albums` and tolerates their absence (older servers / shared-link album ref) in `Packages/ImmichClient/Tests/ImmichClientTests/AlbumMetadataTests.swift`
- [X] T002 [P] Implement back-compatible `Album` metadata (`assetCount: Int?`, `startDate`/`endDate: Date?`, retain `init(id:name:)` + add CodingKeys) in `Packages/ImmichClient/Sources/ImmichClient/Models.swift`
- [ ] T003 Confirm `assetCount`/`startDate`/`endDate`/`createdAt` field names against the running server's OpenAPI (`/api/server/version`) and adjust decode keys (FR-210-25) — **blocked: needs live server**; implemented against the documented Immich `AlbumResponseDto` (`assetCount`, ISO8601 `startDate`/`endDate`)

**Checkpoint**: Album list carries metadata; existing `albums()` callers unchanged.

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: The shared entry-routing + the resolve-first/ask-password-only-when-needed engine reused
by US1, US2, and US4.

**⚠️ CRITICAL**: US1/US2/US4 cannot begin until this phase is complete. (US3/US5 are independent.)

- [X] T004 Red test: `OnboardingStep.choice` exists and `StartupGate` routes shared-link active ⇒ `.done` (no API key), album active ⇒ `.done` only with key+baseURL else `.connection`, no source+key+baseURL ⇒ `.source`, empty ⇒ `.choice`, legacy `selectedAlbumID` still ⇒ `.done`, in `Packages/OnboardingKit/Tests/OnboardingKitTests/StartupGateTests.swift`
- [X] T005 Implement `OnboardingStep.choice` + relaxed `StartupGate.initialStep()` in `Packages/OnboardingKit/Sources/OnboardingKit/OnboardingStep.swift` and `StartupGate.swift`
- [X] T006 Red test: two-phase resolve state machine — `resolveSharedLink` (HTTPS-only guard; no network on malformed) → `.resolved` (200) / `.needsPassword` (401 no-pw) / `.error` (else, nothing persisted); `confirmSharedLinkPassword` → saved + password to Keychain (200) / `.error(wrongPassword)` (401, nothing persisted); dedup by `(baseURL,slug)`, in `Packages/OnboardingKit/Tests/OnboardingKitTests/SourceLibraryViewModelTests.swift`
- [X] T007 Implement `SharedLinkAddState` + `resolveSharedLink`/`confirmSharedLinkPassword` + `(baseURL,slug)` dedup in `Packages/OnboardingKit/Sources/OnboardingKit/SourceLibraryViewModel.swift` (added alongside `addSharedLinkSource`; the password-upfront method is removed in US4/T031–T032 once its callers migrate)

**Checkpoint**: Entry routing + the shared resolve engine are green on the host.

---

## Phase 3: User Story 1 - Shared-link-only onboarding (Priority: P1) 🎯 MVP

**Goal**: A user with only a shared link reaches the slideshow with no API key; password asked only if required.

**Independent Test**: From no config, choose the shared-link path, enter a link, and reach the slideshow with no API key stored; a protected link prompts once; an invalid link errors with nothing persisted.

- [X] T008 [P] [US1] Red test: `OnboardingViewModel` choice routing (shared-link choice → shared-link path; server choice → `.connection`) and shared-link `finish` makes a shared-link the active source with no API key, in `Packages/OnboardingKit/Tests/OnboardingKitTests/OnboardingViewModelTests.swift`
- [X] T009 [US1] Implement choice routing + shared-link-only completion in `Packages/OnboardingKit/Sources/OnboardingKit/OnboardingViewModel.swift`
- [X] T010 [US1] Build `OnboardingChoiceView` (two labeled options + one-line descriptions) in `OwnFrame/Onboarding/OnboardingChoiceView.swift`
- [X] T011 [US1] Build `SharedLinkSetupView` (link field → resolve → password sheet only on `.needsPassword` → start) using the Phase-2 engine, in `OwnFrame/Onboarding/SharedLinkSetupView.swift`
- [X] T012 [US1] Wire `.choice` into `OnboardingFlowView` and app routing; add `--uitest-onboarding-choice` + `--uitest-shared-link-only` seams in `OwnFrame/Onboarding/OnboardingFlowView.swift` and `OwnFrame/OwnFrameApp.swift`
- [X] T013 [US1] XCUITest: choice → non-protected link → slideshow (no API key); protected link → one prompt → slideshow; malformed/invalid link → classified error, nothing persisted, in `OwnFrameUITests/SharedLinkOnboardingUITests.swift` — 3 tests green
- [X] T014 [US1] Screenshot-verify choice + shared-link setup screens (portrait + landscape) via XcodeBuildMCP — **portrait screenshots captured & verified (both screens on-spec)**; landscape verified via the `XCUIDevice.orientation` test (`testSharedLinkOnlyChoiceReachesSlideshowInLandscape`, **green**) since MCP menu-rotate didn't re-layout the app

**Checkpoint**: US1 fully functional and independently testable — the MVP.

---

## Phase 4: User Story 2 - iOS Share Sheet (Priority: P1)

**Goal**: Share an Immich link into the app; it pre-fills setup (unconfigured) or adds+activates (configured), asking for a password only if needed.

**Independent Test**: Inject a pending link via the App-Group fake; unconfigured pre-fills setup, configured adds+activates, a duplicate switches, an invalid link errors — all without the system Share Sheet.

- [X] T015 [P] [US2] Red test: `PendingSharedLinkStore` save → take-once → `nil`; only the URL is stored; missing App Group degrades to `nil`, in `Packages/OnboardingKit/Tests/OnboardingKitTests/PendingSharedLinkStoreTests.swift`
- [X] T016 [US2] Implement `PendingSharedLinkStore` protocol + App-Group `UserDefaults` impl + in-memory fake in `Packages/OnboardingKit/Sources/OnboardingKit/PendingSharedLinkStore.swift`
- [X] T017 [P] [US2] Red test: `IncomingSharedLink.route` — unconfigured → `.prefillOnboarding`; configured+existing `(baseURL,slug)` → `.switchToExisting`; configured+new → `.addAndActivate`; unparseable → `.invalid`, in `Packages/OnboardingKit/Tests/OnboardingKitTests/IncomingSharedLinkTests.swift`
- [X] T018 [US2] Implement pure `IncomingSharedLink` router in `Packages/OnboardingKit/Sources/OnboardingKit/IncomingSharedLink.swift`
- [X] T019 [P] [US2] Red test: `ShareLinkExtraction.url(from:)` extracts a URL from synthetic extension item providers (and returns `nil` for non-URL content), in `Packages/OnboardingKit/Tests/OnboardingKitTests/ShareLinkExtractionTests.swift`
- [X] T020 [US2] Implement pure `ShareLinkExtraction` helper (in OnboardingKit so it stays host-testable; the extension links it) in `Packages/OnboardingKit/Sources/OnboardingKit/ShareLinkExtraction.swift`
- [X] T021 [US2] Add the Share Extension target + App Group entitlement (host + extension), `NSExtensionActivationRule` accepting exactly one `public.url`, and the `immichslideshow://` hand-off scheme in `OwnFrame.xcodeproj/project.pbxproj`, `OwnFrameShareExtension/Info.plist`, and entitlement files **(keep-inline: signing/pbxproj)** — hand-edited pbxproj: new `app-extension` target (`ing.kipp.Immich-Slideshow.ShareExtension`), synchronized group + exception-set excluding `Info.plist`, Embed-App-Extensions phase + target dependency, App Group `group.ing.kipp.Immich-Slideshow` entitlement on host + extension (`CODE_SIGN_ENTITLEMENTS`, automatic signing, `REGISTER_APP_GROUPS`), activation rule = one web URL. Builds + embeds in the sim; 7 XCUITests still green. **OBSOLETE (2026-09-14, FR-210-31, #65): the scheme is never to be registered — iOS ignores `extensionContext.open` for Share extensions, so registering it would not help; the host picks the link up when it next becomes active, and the extension says so (Phase 10).** ~~**NOTE: host-side `immichslideshow://` URL-scheme registration deferred**~~ (CFBundleURLTypes can't be set via the generated-plist setup without risking the host's launch keys; one-line Xcode-GUI add). Until then the host consumes the App-Group link on next foreground (already wired) instead of auto-opening.
- [X] T022 [US2] Implement `ShareViewController` (extract URL via `ShareLinkExtraction` → `savePendingURL` → open the host scheme → complete) in `OwnFrameShareExtension/ShareViewController.swift` — thin, self-contained (URL extraction + App-Group write duplicated from OnboardingKit constants rather than linking the module, to keep the extension thin and avoid app-extension link constraints; best-effort `extensionContext.open` host wake) — **the host wake is a no-op for Share extensions and is removed by T059 (FR-210-31, #65)**
- [X] T023 [US2] Host: consume the pending link on launch/`scenePhase == .active` (and `onOpenURL`) → `IncomingSharedLink` → resolve+add/activate or prefill onboarding (password only if required); add `--uitest-pending-link` seam, in `OwnFrame/OwnFrameApp.swift` **(keep-inline: app entry + onboarding wiring)** — added `IncomingLinkSheet` (configured-app resolve+activate, reusing the two-phase engine), prefill plumbing through `OnboardingFlowView`/`SharedLinkSetupView`, and `Factories.takePendingLink`/`loadLibrary` (prod `AppGroupPendingSharedLinkStore`, uitest `InMemoryPendingSharedLinkStore`)
- [X] T024 [US2] XCUITest: seeded pending link → unconfigured prefills setup; configured adds+activates and playback switches; invalid errors, in `OwnFrameUITests/ShareSheetIncomingUITests.swift` — 3 tests green. Duplicate-switch (`(baseURL,slug)` dedup → `.switchToExisting`) is covered by the `IncomingSharedLink`/`resolveSharedLink` host unit tests; not re-driven via XCUITest (no shared-link seed seam, and a take-once pending store consumes one link per launch)
- [ ] T025 [US2] Manual human-test: real iOS Share Sheet round trip on device (system sheet not XCUITest-drivable); record in `specs/210-shared-link-onboarding/human-test-findings.md`

**Checkpoint**: US1 and US2 both work independently; the easiest path (share → watch) is live.

---

## Phase 5: User Story 3 - Searchable + subscrollable album picker (Priority: P2)

**Goal**: With 50+ albums, search by name/date/count and keep the primary action pinned.

**Independent Test**: Seed 50+ stub albums; typing narrows by name/date/count; no-match shows an empty state; Continue/Add stays visible while the list scrolls in portrait + landscape.

- [X] T026 [P] [US3] Red test: `AlbumSearch.filter` — empty query → all (stable order); name/date/count substring match (case/diacritic-insensitive); `nil` date/count tolerated, in `Packages/OnboardingKit/Tests/OnboardingKitTests/AlbumSearchTests.swift`
- [X] T027 [US3] Implement pure `AlbumSearch.filter` predicate in `Packages/OnboardingKit/Sources/OnboardingKit/AlbumSearch.swift`
- [X] T028 [US3] Redesign the onboarding album picker: search field + independently scrollable list + pinned Continue/Add (`safeAreaInset(edge: .bottom)`) + name/date·count subtitle + no-results state, in `OwnFrame/Onboarding/SourceStepView.swift` — `AlbumPickerView` (search field → `AlbumSearch.filter` → `List` + `ContentUnavailableView.search` no-results) + `AddedSourcesBar` pinned via `safeAreaInset(.bottom)`; year·count subtitle (UTC years, matching `AlbumSearch`)
- [X] T029 [US3] Ensure the picker receives album metadata (count/date) and add the `--uitest-albums-many` seam (50+ stub albums with date/count) in `OwnFrame/OwnFrameApp.swift` — `UITestSupport.manyAlbums()` (60 albums incl. diacritic "München Trip", varied years/counts); `StubImmichAPI.albums()` returns it under the flag
- [X] T030 [US3] XCUITest + screenshot: 50+ albums — search narrows, no-results state shows, action stays pinned (portrait + landscape), in `OwnFrameUITests/AlbumSearchUITests.swift` — 2 tests green (portrait + landscape), screenshots attached; SourceOnboardingUITests (120) still green (no regression)

**Checkpoint**: Album selection is usable at 50+ albums.

---

## Phase 6: User Story 4 - Ask-password-only-when-needed everywhere (Priority: P2)

**Goal**: Remove the always-on optional-password field; resolve first and prompt only when required, in onboarding and Settings.

**Independent Test**: In both the onboarding source step and Settings → Sources, a non-protected link saves with no password field; a protected link prompts once; a wrong password is a distinct error with nothing persisted.

- [X] T031 [US4] Replace the always-on optional-password field in the onboarding source step's shared-link section with the Phase-2 two-phase flow, in `OwnFrame/Onboarding/SourceStepView.swift` — extracted a shared `SharedLinkAddForm` (URL + optional name + Add → resolve-first → on-demand password sheet → inline error), reused here (`idPrefix: onboarding.sharedLink`, submit id `add`); ids `onboarding.sharedLink.url/.label/.add` preserved, the always-on `onboarding.sharedLink.password` is gone (now only inside the on-demand sheet). Top-level `onboarding.source.error` scoped to the album tab.
- [X] T032 [US4] Replace the always-on optional-password field in Settings → Sources add-shared-link with the same flow, in `OwnFrame/Slideshow/SourceLibraryView.swift` — reuses `SharedLinkAddForm` (`idPrefix: sources.add`, submit id `submit`); removed the always-on `sources.add.password`. **Migrated the whole file's German strings to English** ([[language-english-always]]; `SourceLibraryUITests` "Quellen"→"Sources", "Löschen"→"Delete" updated). Deleted the now-unused `addSharedLinkSource` + `isBusy` from `SourceLibraryViewModel` (4 superseded unit tests removed, the remove-deletes-password test converted to the two-phase API; 106 OnboardingKit tests green).
- [X] T033 [US4] XCUITest: both surfaces — non-protected saves with no password field; protected prompts once; wrong password distinct error, nothing persisted, in `OwnFrameUITests/SharedLinkPasswordUITests.swift` — 4 tests green (onboarding + Settings × non-protected / protected-wrong-then-correct). NOTE: the password sheet anchors on the URL `TextField` leaf, not the enclosing `Section` (Form/List drop `.sheet`/`.onAppear` modifiers placed on a `Section`).

**Checkpoint**: One consistent, low-friction add-link behavior across the app.

---

## Phase 7: User Story 5 - Onboarding step descriptions (Priority: P3)

**Goal**: Every onboarding screen shows concise helper text.

**Independent Test**: Each onboarding screen (choice, shared-link setup, connection, album, confirm) shows a short, accurate description.

- [X] T034 [US5] Add concise helper text to each onboarding screen in `OwnFrame/Onboarding/OnboardingChoiceView.swift`, `SharedLinkSetupView.swift`, `ConnectionStepView.swift`, `SourceStepView.swift`, and the confirm step — choice already carried `onboarding.choice.intro` + per-row descriptions (US1); added an identified step description to the four remaining screens (`onboarding.sharedLink.description`, `onboarding.connection.description`, `onboarding.source.description` above the segmented picker, `onboarding.confirm.description`). Field-level footers kept as complementary helper text. **NOTE:** ConnectionStepView's older 200/010 labels still render German on a German-locale device (legacy `Localizable.xcstrings`); new 210 strings are English-only, consistent with the [[language-english-always]] migration — finishing the catalog migration is topic-200 scope.
- [X] T035 [US5] XCUITest/screenshot: each onboarding screen shows description text, in `OwnFrameUITests/OnboardingDescriptionsUITests.swift` — 4 tests green (choice / shared-link / connection assert their description ids; source + confirm reached via `--uitest-onboarding-source` → add album → continue). Screenshots captured & verified (portrait) for shared-link, connection, and source steps; confirm verified by the navigating test; choice verified earlier in T014.

**Checkpoint**: First-time users are guided on every screen.

---

## Phase 8: Polish & Cross-Cutting Concerns

- [X] T036 [P] Secret-hygiene check — grep audit **clean** (2026-06-26): no API key/password/token in UserDefaults; the Share Extension writes only `url.absoluteString` to the App Group; `SourceKind.sharedLink` persists only `(baseURL, slug)`; `ConfigStore` holds only baseURL/albumID; secrets live in `KeychainStore` / `KeychainSharedLinkSecretStore` (`SecItem*`); no `print`/`os_log`/`Logger` of secrets; resolved bearer key never persisted. Recorded in `human-test-findings.md` (SC-210-06, Constitution III).
- [X] T037 [P] Update `docs/spec-overview.md` — added the `210` topic row (sub-spec of 200, Active), a "How they connect" cross-ref (210 evolves 200 onboarding; reuses 120 + 100/110, no new backend), and refreshed the source-management roadmap bullet (now built by 120 + 210).
- [X] T038 Run the full XCUITest suite green via XcodeBuildMCP — **52 passed / 0 failed** (2026-06-26, pinned iOS 26.5 iPad sim). Re-run at final merge per project rule ([[run-full-xcuitest-before-merge]]).
- [X] T039 Run `quickstart.md` scenarios A–F — A–F mapped to their green host/XCUITest coverage + the T036 audit in `human-test-findings.md`; F1/F2/F3 manual fixes recorded. **Device-gated items flagged pending: T025** real Share-Sheet round trip (system sheet not XCUITest-drivable) and **T003** live-OpenAPI field check.

---

## Phase 9: Manual-Test Findings (2026-06-26)

**Source**: live walkthrough against a real Immich 2.7.5 server. Three findings; F1 is a defect
against existing FR-210-06/07, F2/F3 are encoded as FR-210-26/27/28 (spec updated 2026-06-26).

**Orchestration note**: F1 (resolver) and F3's model logic (`back()`) are pure host logic →
Codex-delegable; the picker extraction, Settings rewire, and the Back affordance are SwiftUI/onboarding
wiring → keep-inline.

### Finding 1 — false password prompt: `/share/<key>` resolved as a slug (FR-210-06/07)

The segment after `/share/<X>` is the share **key**; the resolver always queries `?slug=<X>`, the
server returns `401 "Invalid share key/slug"`, and `SharedLinkResolver` maps any 401 (no password) to
`passwordRequired` — so a non-protected link wrongly prompts for a password.

- [X] T040 [P] [F1] Red test: `SharedLinkResolver` resolves a `/share/<key>` identifier via `key=` → `.resolved` (no `passwordRequired`); an `"Invalid share key"`/`"Invalid share slug"` 401 maps to `invalidShareLink` (not `passwordRequired`); a `/s/<slug>` identifier resolves via the `slug=` fallback; a genuine password 401 still maps to `passwordRequired` (no password) / `wrongPassword` (with password), in `Packages/ImmichClient/Tests/ImmichClientTests/SharedLinkResolverTests.swift` — added 3 tests + a sequenced `MockTransport(sequence:)`; updated the resolution test to assert `key=` first. Confirmed RED (invalid-key 401 → `passwordRequired`).
- [X] T041 [F1] Implement key-first / slug-fallback resolution + message-aware 401 classification in `Packages/ImmichClient/Sources/ImmichClient/SharedLinkResolver.swift` — key-first; an `"Invalid share key/slug"` 401 (or 404) → internal `IdentifierNotFound` → retry as `slug=`, then `invalidShareLink`; every other 401 → `passwordRequired`/`wrongPassword` (robust to the server's exact password wording). **41 ImmichClient + 106 OnboardingKit tests green.** Live-verified earlier: `?key=<key>` → 200 `"password":null`, `?slug=<key>` → 401 `"Invalid share key"`.

### Finding 2 — one reusable album/source picker in onboarding and Settings (FR-210-27/28)

Onboarding's `SourceStepView` already has the target design (Album/Shared-link tabs, search,
internally-scrollable list, pinned confirm). Settings → Sources (`AddSourceView`/`AddAlbumSection`) is
a divergent, unsearchable `Form` list that adds-and-dismisses on tap. Unify on one component;
Settings uses select-then-confirm.

- [X] T042 [F2] Extract the onboarding searchable album picker (search field + internally-scrollable list + pinned select-then-confirm + no-results state) into a reusable component shared by both surfaces — new `OwnFrame/Onboarding/AlbumPickerView.swift` (`AlbumPickerView(albums:sourceLibrary:idPrefix:)`); onboarding ids preserved via `idPrefix: "onboarding.album"`. `SourceStepView` consumes it; behavior unchanged (AlbumSearchUITests green).
- [X] T043 [F2] Replace Settings → Sources `AddAlbumSection` with the reusable picker (`idPrefix: "sources.album"`) inside a restructured `AddSourceView` (VStack + `AddAlbumPicker` loader + pinned `AddAlbumDoneBar` = `sources.add.done`); Album/Shared-link tabs and the resolve-first shared-link form kept, in `OwnFrame/Slideshow/SourceLibraryView.swift`.
- [X] T044 [F2] XCUITest: Settings → Sources add — Album tab search narrows (diacritic-insensitive), no-results state shows, select-then-confirm (tap → Done) commits; updated the `addAlbum` helper to tap `sources.add.done`. `OwnFrameUITests/SourceLibraryUITests.swift`. **Full XCUITest suite green: 52 passed / 0 failed (satisfies T038 for now).**

### Finding 3 — no back navigation in onboarding (FR-210-26)

`OnboardingViewModel` has no generic `back()` and `OnboardingFlowView` swaps the `NavigationStack`
root per step, so the shared-link / connection / source steps have no Back — the only way back to the
choice screen is to kill the app.

- [X] T045 [P] [F3] Red test: `OnboardingViewModel.back()` maps `.sharedLinkSetup` → `.choice`, `.connection` → `.choice`, `.source` → `.connection`, `.confirm` → `.source`; `.choice` is a no-op; `canGoBack` is false only on `.choice`/`.done`; entered config (serverURL/apiKey inputs, added sources) is preserved across back, in `Packages/OnboardingKit/Tests/OnboardingKitTests/OnboardingViewModelTests.swift` — 7 tests added.
- [X] T046 [F3] Implement `back()` + `canGoBack` in `Packages/OnboardingKit/Sources/OnboardingKit/OnboardingViewModel.swift` — **113 OnboardingKit tests green.**
- [X] T047 [F3] Add a leading Back toolbar affordance in `OwnFrame/Onboarding/OnboardingFlowView.swift`, shown when `viewModel.canGoBack`, calling `back()`, with accessibility id `onboarding.back` — built + visually confirmed on the shared-link step (chevron top-left).
- [X] T048 [F3] XCUITest: choice → shared-link setup → Back → choice; choice → server connection → Back → choice; choice screen has no Back; no app restart, in `OwnFrameUITests/OnboardingBackUITests.swift` — 3 tests green.

### Finding 4 — shared-link-only setup is a black screen on device (FR-210-03/04)

Device-only (the `--uitest` slideshow path is stubbed and bypasses real source resolution): the
app's `resolveActiveSource` guarded on `config.loadBaseURL()` **and** `keychain.read()` (API key)
before resolving *any* active source — but a shared-link-only setup has neither, so the guard
returned `nil` → `makeSlideshow` → `nil` → `Color.black`. Affects protected **and** non-protected
shared-link-only setups. (Asset access itself is fine: verified live that a protected link's
album/thumbnail/preview/original all return 200 with `?key=` alone — no password/cookie needed.)

- [X] T049 [P] [F4] Red test: `ActiveSourceResolver` resolves a `.sharedLink` source with `nil`
  albumBaseURL/apiKey; an `.album` source with `nil` creds throws, in `ActiveSourceResolverTests.swift` — 2 tests, **115 OnboardingKit green**.
- [X] T050 [F4] Make `ActiveSourceResolver` album creds optional (`URL?`/`String?`; album branch
  throws `.unauthorized` when missing) and drop the API-key/base-URL requirement from
  `resolveActiveSource` in `OwnFrame/OwnFrameApp.swift` (keep-inline; app entry).
- [ ] T051 [F4] **Device re-test**: real shared-link-only onboarding (protected + non-protected) reaches the running slideshow on the iPad — pending hardware confirmation.

**Checkpoint**: non-protected `/share/<key>` links resolve with no password prompt; the album picker
is one searchable, subscrollable, pinned-confirm screen in both onboarding and Settings; every
onboarding step after the choice has a working Back; a shared-link-only setup reaches the slideshow
(no API key) instead of a black screen.

### Finding 5 — harmonize the connection editor; make the server editable after onboarding (FR-210-29)

Three divergent connection UIs today: onboarding `ConnectionStepView`, the inline Settings
`ConnectionSettingsSection` (collapsed DisclosureGroup), and the full-screen `ConnectionSettingsView`
(slideshow error recovery). The server connection *is* editable in Settings, but it's a different,
easily-missed inline form. Unify on one editor; Settings → Connection opens the full editor (user
choice: max harmony). NB: the "couldn't load albums" report was a stale API key — re-saving it in the
connection editor fixed it; no deeper bug.

- [X] T052 [F5] Extract a shared `OwnFrame/Onboarding/ConnectionFieldsView.swift` (server URL + API key + "key is set" + error, Section-based; ids/copy passed in) (keep-inline, SwiftUI).
- [X] T053 [F5] `ConnectionSettingsView` uses `ConnectionFieldsView`, drops its internal `NavigationStack` (becomes a `Form` + title + toolbar; adds `showsCancelButton`); wrap the error-recovery sheet in `NavigationStack`, in `OwnFrame/Slideshow/ConnectionSettingsView.swift` + `SlideshowView.swift`.
- [X] T054 [F5] Onboarding `ConnectionStepView` uses `ConnectionFieldsView` (ids `onboarding.serverURL`/`onboarding.apiKey`; Continue button kept), in `OwnFrame/Onboarding/ConnectionStepView.swift`.
- [X] T055 [F5] Settings: replace the Connection `DisclosureGroup` with a `NavigationLink` (`settings.connection`) showing the current server → pushes `ConnectionSettingsView` (`showsCancelButton: false`); delete `ConnectionSettingsSection` + the `connectionExpanded`/`--uitest-connection` seam, in `OwnFrame/Slideshow/SlideshowSettingsView.swift`.
- [X] T056 [F5] Update `SettingsUITests` (Connection is now a push row, not a collapsed section: tap `settings.connection` → `connection.url` appears; MQTT stays collapsed). Full XCUITest green.

---

## Phase 10: Amendment 2026-09-14 — Share extension confirms instead of opening the host (FR-210-31, SC-210-02, #65)

**Goal**: A Share extension cannot bring its host forward on iOS. The extension stops trying (no `extensionContext.open`) and shows a short localized (EN + DE) confirmation, "Open OwnFrame to start", before it closes, without implying playback has started. The host picks the link up whenever it next becomes active, from a cold start (FR-210-18) or a return to the foreground (SC-210-02: at most two taps after opening OwnFrame).

**Independent Test**: the host-side contract scan goes red on the dead open call and the missing confirmation key; simulator share round trip shows the confirmation, then OwnFrame picks the link up on activation.

**Orchestration note**: the extension target, its String Catalog and `OwnFrame.xcodeproj/project.pbxproj` (**explicitly in scope for this phase**) plus the app entry point are **keep-inline (Claude)**. Only the OnboardingKit contract test is host work.

- [ ] T057 [US2] Red: extend `Packages/OnboardingKit/Tests/OnboardingKitTests/ShareExtensionContractTests.swift` (text scan of the extension source) — the source MUST NOT contain `extensionContext?.open`, `extensionContext.open`, `openHost` or `immichslideshow://`; the confirmation string key ("Open OwnFrame to start") MUST appear in the extension source **and** in `OwnFrameShareExtension/Localizable.xcstrings` with a translated `de` entry. `@covers FR-210-31`. If the confirmation lands in its own file, widen the scan helper to every `.swift` file in `OwnFrameShareExtension/`, so the existing one-`.set(` / no-`URLSession` / no-`SecItem` guards (FR-210-13) keep covering all extension code. Red today: the open call exists, and so do the scheme and the missing catalog.
- [ ] T058 [US2] **Claude inline**: create `OwnFrameShareExtension/Localizable.xcstrings` (EN source "Open OwnFrame to start" + a `Done` label if T059 uses a button; DE draft e.g. "Öffne OwnFrame, um zu starten") and wire it in `OwnFrame.xcodeproj/project.pbxproj`. The folder is a synchronized group (exception set excludes only `Info.plist`, ~:91-126), so first confirm the catalog is compiled into the appex's resources, and edit the pbxproj only where it is not. Check `knownRegions` includes `de` and the extension target's build settings (~:870) emit localized strings.
- [ ] T059 [US2] Green, **Claude inline**: `OwnFrameShareExtension/ShareViewController.swift` — delete `hostScheme` (:24-26) and `openHost()` (:67-70). After the single App-Group write, present a minimal confirmation (UIKit label or a `UIHostingController` view; no network, no secret) with the localized text. Move `completeRequest` out of the `defer` in `handleShare()`, so the extension closes only after the confirmation is dismissed (a Done button, accessibility id `share.confirmation.done`, or a short auto-dismiss; record the choice here). With no URL, complete immediately. Rewrite the header comment (:5-9: "best-effort wake the host", "no UI"). Green T057.
- [ ] T060 [US2] **Claude inline**: fix the stale comments — `OwnFrame/Onboarding/IncomingLinkSheet.swift:5-6` (drop "the `immichslideshow://` hand-off"; the link is picked up when OwnFrame next becomes active) and `OwnFrame/OwnFrameApp.swift:652-661` (drop "when the Share Extension opens the host scheme"). Keep `.onOpenURL` (:663) unless it has no other use: check for a `CFBundleURLTypes` entry and an associated-domains entitlement. On 2026-09-14 grep found no other caller and no registered scheme, so remove it only after that check, and say so in the commit.
- [ ] T061 [US2] UITest, **Claude (simulator)**: in `OwnFrameUITests/ShareSheetIncomingUITests.swift`, add a warm-return case. OwnFrame is running, a pending link arrives while it is backgrounded (`--uitest-pending-link` seam, or the App-Group store if the in-memory seam cannot be seeded after launch), and the link is consumed after `app.activate()` (SC-210-02). Then drive a real share round trip on the simulator (Safari → Share → OwnFrame): the confirmation text is visible, Done closes it, and activating OwnFrame picks the link up. If the system share sheet is not drivable from XCUITest, run it by hand on the simulator, record screenshots in `specs/210-shared-link-onboarding/human-test-findings.md`, and leave T025 (device round trip) open.
- [ ] T062 Verification gate (**Claude**): XcodeBuildMCP `build_sim` of the app scheme (embeds the appex), `test_sim` whole class `ShareSheetIncomingUITests`, `swift test` in OnboardingKit; screenshot the confirmation in EN and DE (downscale with `sips -Z 900` before reading).
- [ ] T063 Facts, **same commit as T059**: `product-facts.yaml` **SRC-07** → `implementation: verified`; remove `mismatch`/`candidate_issue`; add `FR-210-31` to `intent`; refresh `evidence` (new `ShareViewController.swift` lines, `OwnFrameShareExtension/Localizable.xcstrings`, `OwnFrameApp.swift` consume lines, `IncomingLinkSheet.swift`); add a limit that the extension tells the person to open OwnFrame. Run `.claude/scripts/check-facts.py`.
- [ ] T064 Queue the new German string(s) for Jan's review in `docs/hitl.md`; commit with explicit paths; close #65 with the commit reference (`gh` account `kipp-ing`). T025 stays the device item and now also checks the confirmation.

**Checkpoint**: sharing a link shows "Open OwnFrame to start" and never pretends to open the app; opening OwnFrame (warm or cold) starts that link.

---

## Phase 11: Amendment 2026-09-14 — Album picker select-then-confirm (FR-210-28, #71)

**Goal**: FR-210-28 as written. In onboarding and in Settings → Sources, tapping albums **marks** them; the pinned Continue/Done **commits** exactly the marked albums in one pass; Cancel (or leaving) discards them. **Today** a tap persists at once (`OwnFrame/Onboarding/AlbumPickerView.swift:81-83` → `SourceLibraryViewModel.addAlbumSource`, `Packages/OnboardingKit/Sources/OnboardingKit/SourceLibraryViewModel.swift:48-58`). Done only leaves, and Cancel in Settings (`OwnFrame/Slideshow/SourceLibraryView.swift:202`) keeps what was tapped. The UI tests tap-then-Done, so they cannot tell the two apart (fact SRC-09). The Settings "Add a server" prompt (`SourceLibraryView.swift:244-253`, FR-210-30 case a) has no test.

**Independent Test**: host tests on a pending-selection model with fakes (nothing persists until commit); XCUITest for Cancel, multi-select + Done, and the no-server prompt.

**Orchestration note**: the selection model is OnboardingKit host work, subagent-eligible. It runs **after** the WP2 ImmichClient + OnboardingKit pass (130 Phase 9, 310 T024–T027, 120 T037–T042), never concurrently. The picker and both hosts are SwiftUI, and all UI tests are **Claude inline**. Scope is the Immich album picker. `PhotoAlbumPickerView` also adds on tap (`PhotoAlbumPickerView.swift:131,155,200,219`) under the same pinned Done; whether FR-210-28 covers it was open. **Jan decided 2026-09-14: yes, both pickers behave the same.** The Photos picker gets the same mark-then-Done rework in this package (recorded on #71); its tasks are still to be written before any code.

- [ ] T065 [P] [US3] Red: new `Packages/OnboardingKit/Tests/OnboardingKitTests/AlbumSelectionTests.swift` — a pending-selection model (e.g. an `AlbumSelection` value type):
  - `toggle(album)` marks and unmarks.
  - An album already in the library (matched by **album id**, not label) cannot be marked.
  - Commit adds exactly the marked albums, in the picker's list order, through one library persist; labels come from the album name, and an unnamed album keeps today's stored fallback (120 T039).
  - It reports the added count.
  - Discard adds nothing, and marking alone never writes the store (save count 0).
  - A mark survives a search-filter change.
- [ ] T066 [US3] Green: `Packages/OnboardingKit/Sources/OnboardingKit/AlbumSelection.swift` (new) plus a batch `addAlbumSources(_:)` on `SourceLibraryViewModel.swift` (one persist) that the commit uses; `addAlbumSource` stays for other callers. `swift test` green in OnboardingKit. Depends on T065.
- [ ] T067 [US3] Red XCUITest (**Claude**), in `OwnFrameUITests/SourceLibraryUITests.swift`:
  - Settings → + → Album: mark two albums → `sources.add.cancel` → the library is unchanged.
  - Mark two → `sources.add.done` → exactly those two are added.
  - Mark then unmark one → Done → only the other is added.
  - With no server stored (a shared-link-only seed), the Album tab shows the "Add a server" prompt (`sources.add.addServer`).

  In `OwnFrameUITests/AlbumSearchUITests.swift` (onboarding): marking alone adds nothing until Continue, and `onboarding.back` after marking adds nothing. Red today: Cancel keeps tapped albums.
- [ ] T068 [US3] Green (**Claude inline**):
  - `AlbumPickerView.swift:77-100`: a row tap toggles a mark. The checkmark shows marked *or* already-added, already-added rows are disabled matched by album id, and the picker never persists. The row text for an unnamed album follows 120 T039.
  - Hosts own the selection. `SourceLibraryView.swift` `AddSourceView`: Done commits, Cancel discards, the `AddAlbumDoneBar` count is the marked count, and the stale comment at :206-207 goes.
  - `OwnFrame/Onboarding/SourceStepView.swift:64-85`: `AddedSourcesBar` Continue commits, then continues, and its count includes marked albums.
  - Update the header comment at `AlbumPickerView.swift:9-10`.

  Green T067.
- [ ] T069 [US3] Update the existing tap-then-confirm UI tests so they assert nothing is added before confirm: `AlbumSearchUITests.swift` (:58, :88), `SourceLibraryUITests.swift` `testSettingsAlbumPickerSearchesAndSelectThenConfirm` and its `addAlbum` helper, and any album-row taps in `SourceOnboardingUITests.swift`, `OnboardingDescriptionsUITests.swift`, `SharedLinkPasswordUITests.swift`, `GermanScreenshotSweepUITests.swift`, `OwnFrameUITests.swift` (grep `.album.`) (**Claude**)
- [ ] T070 Verification gate (**Claude**): XcodeBuildMCP `build_sim` + `test_sim` whole classes `AlbumSearchUITests`, `SourceLibraryUITests`, `SourceOnboardingUITests`, `OnboardingDescriptionsUITests`; the **full XCUITest suite** before commit (the picker sits on the main onboarding path); screenshot the marked state in portrait and landscape (downscale before reading).
- [ ] T071 Facts, **same commit as T066/T068**: `product-facts.yaml` **SRC-09** → `implementation: verified`; remove `mismatch`/`candidate_issue`; refresh `evidence` (`AlbumSelection.swift`, `AlbumPickerView.swift`, `SourceLibraryView.swift`, the new UI tests incl. the no-server prompt); run `.claude/scripts/check-facts.py`.
- [ ] T072 Commit with explicit paths; close #71 with the commit reference (`gh` account `kipp-ing`), noting the Photos-picker answer from Jan.

**Checkpoint**: in both surfaces, tapping only marks; Continue/Done adds exactly the marked albums; Cancel adds nothing; the no-server prompt is under test.

---

## Dependencies & Execution Order

### Phase Dependencies

- **Setup (Phase 1)**: no dependencies.
- **Foundational (Phase 2)**: depends on Setup (Album metadata used by labels); BLOCKS US1/US2/US4.
- **US1 (Phase 3)**: after Foundational. MVP.
- **US2 (Phase 4)**: after Foundational; reuses US1's `SharedLinkSetupView` for the unconfigured prefill (T023 → T011).
- **US3 (Phase 5)**: after Setup only (needs Album metadata); independent of the resolve engine.
- **US4 (Phase 6)**: after Foundational; UI wiring over the Phase-2 engine.
- **US5 (Phase 7)**: after the screens it annotates exist (US1 screens; ConnectionStep/SourceStep already exist).
- **Polish (Phase 8)**: after the desired stories are complete.

### Within Each Story

- Red test before implementation (Constitution I). Models/types before view models before views.
- Host logic (Codex-delegable) before SwiftUI wiring (keep-inline).

### Parallel Opportunities

- T001/T002 (Album) in parallel with T004/T005 (gate) — different files.
- Within US2, the pure pieces T015/T017/T019 (tests) and T016/T018/T020 (impls) parallelize before the
  target/UI work (T021–T024) which is sequential and inline.
- US3 (T026–T030) can run in parallel with US1/US2 once Setup is done (separate files).

---

## Implementation Strategy

### MVP First (US1)

1. Phase 1 Setup → 2. Phase 2 Foundational → 3. Phase 3 US1 → **STOP & validate** (shared-link-only
   onboarding reaches the slideshow with no API key). Demo.

### Incremental Delivery

1. Setup + Foundational → foundation ready.
2. US1 (shared-link-only onboarding) → MVP.
3. US2 (Share Sheet) → the "share → watch" easiest path.
4. US3 (searchable picker) → scales the server path.
5. US4 (ask-pw-when-needed) → consistency polish.
6. US5 (descriptions) → guidance polish.
7. Polish → secret grep, docs, full UITest, human-test.

### Notes

- Commit after each task or logical group; keep the Share Extension thin (URL only — Constitution III).
- The Share Extension target + App Group + signing (T021) and the host consumption wiring (T023) are
  keep-inline per `CLAUDE.md`; the pure logic around them is Codex-delegable.
- A real-device Share Sheet pass (T025) and the full XCUITest run (T038) gate the merge.
