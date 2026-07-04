---
description: "Task list for HA Full Control (710) implementation"
---

# Tasks: Home Assistant Full Control (MQTT)

**Input**: Design documents in `specs/710-ha-full-control/` (plan.md, spec.md, research.md,
data-model.md, contracts/ha-mqtt-entities.md, quickstart.md)

**Tests**: REQUIRED — Constitution I (Test-First, NON-NEGOTIABLE). Every implementation task is
preceded by a red Swift Testing (host) or XCUITest task; no code before a demonstrably red test.
Two tasks (T004, T013/T025 app-wiring) are structural/integration wiring rather than new
behavior — these are regression-guarded by the existing and newly-added test suites staying
green, per the same convention used in `120-source-library`'s tasks.md.

**Organization**: by user story (US1–US4 from spec.md, in priority order P1/P1/P2/P3). Setup +
Foundational are shared prerequisites.

## Format: `[ID] [P?] [Story] Description with file path`

- **[P]**: parallelizable (different files, no dependency on an incomplete task)
- **Delegation** (per this repo's `CLAUDE.md` orchestration rules): protocol/topic/discovery/
  coordinator logic and adapter wiring (Foundational, most of US1/US2/US3/US4) are well-scoped
  implementation work suitable for a Codex briefing. **Keep inline** (Claude, not delegated):
  echo-loop/coalescing test *design* involving concurrent/timing behavior (T011, T023, T033 —
  shared/timing state per `CLAUDE.md`'s "keep inline" list), the app-entry-point wiring
  (T013, T025 — `Immich_SlideshowApp.swift`), and all SwiftUI/simulator work (T035–T038).

---

## Phase 1: Setup

- [x] T001 Establish a green host baseline: run `swift test` for `HAControlKit`, `ThemeKit`,
  `SlideshowKit`, `ImmichClient` before any change; record the passing baseline.

---

## Phase 2: Foundational (blocking — required by all stories)

**Entity/topic surface + protocol shape only. No new runtime behavior yet.**

- [x] T002 [P] Red tests for the extended `HAEntity` raw values and `HATopics` component/topic
  mapping covering every new case (select/number/switch/button/image/sensor, incl. the two
  `current_photo`/`current_photo_image` topics) in
  `Packages/HAControlKit/Tests/HAControlKitTests/HATopicsTests.swift` (NEW)
- [x] T003 Implement the `HAEntity` and `HATopics` extensions in
  `Packages/HAControlKit/Sources/HAControlKit/HAEntityState.swift` and
  `Packages/HAControlKit/Sources/HAControlKit/HATopics.swift` to green T002
- [x] T004 Refactor `RemoteControlling` into `PlaybackControlling` / `SettingsControlling` /
  `PhotoReporting` (behavior-preserving) plus the new `ThemeSettingsSnapshot` and `PhotoReport`
  value types, in `Packages/HAControlKit/Sources/HAControlKit/RemoteControlling.swift` and
  `Packages/HAControlKit/Sources/HAControlKit/PhotoReport.swift` (NEW); update
  `SlideshowRemoteControlAdapter` and `Packages/HAControlKit/Tests/HAControlKitTests/Fakes.swift`
  so the existing `HAControlCoordinatorTests`/`HADiscoveryTests` stay green throughout

**Checkpoint**: entity/topic surface and protocol shape in place; all existing tests still green.

---

## Phase 3: US1 — Read & set all display settings from HA (P1) 🎯 MVP

**Goal**: every `ThemeSettings` field is a working HA entity, live + persisted, both directions.
**Independent test**: fake transport + fake `SettingsControlling`; command round-trip; a local
settings change echoes without an inbound command; invalid payloads leave state unchanged and
re-echo the actual value.

- [x] T005 [P] [US1] Red tests for the generic command validation matrix in
  `HAControlCoordinator` (select enum membership, `duration` 3–600 range, switch ON/OFF — valid
  → apply + echo once; invalid → unchanged + re-echo actual) against a fake `SettingsControlling`;
  include an explicit assertion that every one of the 9 settings entities' echoed state publish
  has `retain == true` (FR-710-11's general rule, as distinct from the two documented exceptions
  covered in T023), in
  `Packages/HAControlKit/Tests/HAControlKitTests/HAControlCoordinatorTests.swift`
- [x] T006 [US1] Implement the generic `applySetting(entity:payload:)` path + validation matrix in
  `Packages/HAControlKit/Sources/HAControlKit/HAControlCoordinator.swift` to green T005
- [x] T007 [P] [US1] Red tests for discovery payloads of the 9 settings entities (select
  `options`, `duration`'s min/max/step/unit, switch `payload_on`/`payload_off`) in
  `Packages/HAControlKit/Tests/HAControlKitTests/HADiscoveryTests.swift`
- [x] T008 [US1] Implement the 9 settings discovery payloads in
  `Packages/HAControlKit/Sources/HAControlKit/HADiscovery.swift` to green T007
- [x] T009 [P] [US1] Red tests for `SlideshowRemoteControlAdapter`'s `SettingsControlling`
  conformance — all 9 fields map both directions through `ThemeSettingsStore`; a suppress-flag
  prevents `onSettingsChange` firing on a remote-applied change; a genuinely local
  `ThemeSettingsStore` mutation fires it normally — in
  `Immich SlideshowTests/SlideshowRemoteControlAdapterTests.swift` (NEW)
- [x] T010 [US1] Implement `SettingsControlling` on `SlideshowRemoteControlAdapter`
  (`ThemeSettingsSnapshot` ↔ `ThemeSettings` mapping, suppress-flag) in
  `Immich Slideshow/Slideshow/SlideshowRemoteControlAdapter.swift` to green T009
- [x] T011 [P] [US1] Red tests: a local settings change echoes only the changed entity (not all
  9); N rapid repeated commands on one entity coalesce to last-wins with ≤ N+1 publishes
  (SC-710-02) in `Packages/HAControlKit/Tests/HAControlKitTests/HAControlCoordinatorTests.swift`
- [x] T012 [US1] Wire `onSettingsChange` to a scoped, coalesced echo in
  `Packages/HAControlKit/Sources/HAControlKit/HAControlCoordinator.swift` to green T011
- [x] T013 [US1] Wire `Immich_SlideshowApp.makeCoordinator`: pass the adapter as
  `SettingsControlling`, expand `enabledEntities` to the 9 settings entities, in
  `Immich Slideshow/Immich_SlideshowApp.swift`
- [x] T014 [US1] Verify via XcodeBuildMCP: `swift test` green for `HAControlKit`; app builds; a
  full settings round-trip (coordinator + adapter + real `ThemeSettingsStore`) is host-testable
  end-to-end

**Checkpoint**: US1 — every `ThemeSettings` field readable/settable from HA, live effect, no
restart, persisted, no echo loop, single publish per change (SC-710-01/02).

---

## Phase 4: US2 — Current photo image + metadata in HA (P1)

**Goal**: HA shows the photo currently on the frame (image + metadata sensor), capped/optional
image publishing, with zero added delay to the visible slide transition.
**Independent test**: fake transport + fake `ImmichAPI`; advancing the slideshow publishes the
image (if enabled) and metadata; a metadata fetch failure still publishes the asset ID with
empty attributes; oversized images downscale or skip.

- [x] T015 [P] [US2] Red tests for `HAPublishOptions`/`HAPublishOptionsStore` (UserDefaults
  round-trip; default `imageEnabled == false`; in-memory fake) in
  `Packages/HAControlKit/Tests/HAControlKitTests/HAPublishOptionsTests.swift` (NEW)
- [x] T016 [US2] Implement `HAPublishOptions.swift` (value type + protocol + UserDefaults impl +
  in-memory fake) in `Packages/HAControlKit/Sources/HAControlKit/HAPublishOptions.swift` to green
  T015
- [ ] T017 [P] [US2] Red tests for `MetadataCache`'s bounded LRU (evicts least-recently-used past
  its limit; a fetch failure is never cached) in
  `Packages/HAControlKit/Tests/HAControlKitTests/MetadataCacheTests.swift` (NEW)
- [ ] T018 [US2] Implement `MetadataCache.swift` (mirrors `SlideshowKit.ImageCache`'s shape) in
  `Packages/HAControlKit/Sources/HAControlKit/MetadataCache.swift` to green T017
- [ ] T019 [P] [US2] Red tests for `SlideshowRemoteControlAdapter`'s `PhotoReporting` conformance —
  a `currentAssetID` change produces a `PhotoReport` (metadata via cache + `assetInfo`, image
  bytes via `thumbnail()` downscaled/capped when enabled, `nil` image when disabled or a fetch
  fails) in `Immich SlideshowTests/SlideshowRemoteControlAdapterTests.swift`
- [ ] T020 [US2] Implement `PhotoReporting` on `SlideshowRemoteControlAdapter` in
  `Immich Slideshow/Slideshow/SlideshowRemoteControlAdapter.swift` to green T019
- [ ] T021 [P] [US2] Red tests for discovery of `current_photo` (sensor: `value_template` +
  `json_attributes_topic` on the same topic) and `current_photo_image` (image: `content_type`, not
  retained) in `Packages/HAControlKit/Tests/HAControlKitTests/HADiscoveryTests.swift`
- [ ] T022 [US2] Implement the two discovery payloads in
  `Packages/HAControlKit/Sources/HAControlKit/HADiscovery.swift` to green T021
- [ ] T023 [P] [US2] Red tests: `HAControlCoordinator` publishes both photo topics on
  `onPhotoChange`; `phase != .playing` publishes the cleared/null form on both; the image publish
  is skipped (logged) whenever `PhotoReport.imageData == nil` — i.e. disabled, or still over cap
  after the adapter's own downscale attempt (the coordinator does not downscale itself, see T019);
  the publish runs as a detached `Task` adding no delay to the caller (SC-710-04) in
  `Packages/HAControlKit/Tests/HAControlKitTests/HAControlCoordinatorTests.swift`
- [ ] T024 [US2] Implement the photo-report publish path in
  `Packages/HAControlKit/Sources/HAControlKit/HAControlCoordinator.swift` to green T023
- [ ] T025 [US2] Wire `Immich_SlideshowApp.makeCoordinator`: pass the adapter as `PhotoReporting` +
  `HAPublishOptionsStore`, add `current_photo`/`current_photo_image` to `enabledEntities` (image
  gated by `HAPublishOptions.imageEnabled`, off by default) in
  `Immich Slideshow/Immich_SlideshowApp.swift`

**Checkpoint**: US2 — HA shows the current photo + its metadata; image capped/optional; zero
added slide-transition delay (SC-710-04/05).

---

## Phase 5: US3 — Photo navigation from HA (P2)

**Goal**: Next/Previous HA buttons behave exactly like the in-app chrome/swipe.
**Independent test**: fake transport; pressing each button runs `showNext`/`showPrevious`; works
while paused without resuming; timer resets to a full interval.

- [ ] T026 [P] [US3] Red tests for discovery of `next`/`previous` (button, `payload_press`) in
  `Packages/HAControlKit/Tests/HAControlKitTests/HADiscoveryTests.swift`
- [ ] T027 [US3] Implement button discovery in
  `Packages/HAControlKit/Sources/HAControlKit/HADiscovery.swift` to green T026
- [ ] T028 [P] [US3] Red tests: `next`/`previous` commands call `PhotoReporting.showNext()`/
  `showPrevious()`; works while paused without resuming; the auto-advance timer restarts at a
  full interval, in
  `Packages/HAControlKit/Tests/HAControlKitTests/HAControlCoordinatorTests.swift`
- [ ] T029 [US3] Wire button command handling in `HAControlCoordinator.handleIncoming` in
  `Packages/HAControlKit/Sources/HAControlKit/HAControlCoordinator.swift` to green T028
- [ ] T030 [US3] Verify via XcodeBuildMCP (host test): the button path exercises
  `SlideshowViewModel`'s existing works-while-paused/timer-reset semantics end-to-end (confirms
  wiring only — no new `SlideshowKit` behavior needed)

**Checkpoint**: US3 — Next/Previous drive the real slideshow chrome path from HA.

---

## Phase 6: US4 — Diagnostics & state on reconnect (P3)

**Goal**: diagnostic sensors (`phase`, `photo_count`, `version`) plus a full-state republish on
every reconnect, so HA never shows stale values.
**Independent test**: fake transport; diagnostics echo real values; a simulated reconnect
republishes discovery + availability + every enabled entity's state.

- [ ] T031 [P] [US4] Red tests: `phase`/`photo_count`/`version` sensors echo actual values with
  `retain == true` (FR-710-11's general rule); `photo_count` updates when the active album
  changes; discovery marks all three `entity_category: diagnostic`, in
  `Packages/HAControlKit/Tests/HAControlKitTests/HAControlCoordinatorTests.swift` and
  `Packages/HAControlKit/Tests/HAControlKitTests/HADiscoveryTests.swift`
- [ ] T032 [US4] Implement diagnostics sourcing + discovery in
  `Packages/HAControlKit/Sources/HAControlKit/HAControlCoordinator.swift`,
  `Packages/HAControlKit/Sources/HAControlKit/HADiscovery.swift`, and
  `Immich Slideshow/Slideshow/SlideshowRemoteControlAdapter.swift` (photo count/version surfaced
  through `PhotoReporting`) to green T031
- [ ] T033 [P] [US4] Red test: on reconnect, `announce()` republishes discovery + availability +
  the state of every enabled entity (all 19, incl. `current_photo`/`current_photo_image`),
  overwriting any stale retained value left by a prior connection (SC-710-03), in
  `Packages/HAControlKit/Tests/HAControlKitTests/HAControlCoordinatorTests.swift`
- [ ] T034 [US4] Extend `HAControlCoordinator.announce()`/`handleConnection(_:)` to the full
  entity set including photo republish, in
  `Packages/HAControlKit/Sources/HAControlKit/HAControlCoordinator.swift` to green T033

**Checkpoint**: US4 — diagnostics live; a reconnect leaves no stale entity anywhere.

---

## Phase 7: Polish & Cross-Cutting

- [ ] T035 [P] Add the image-publishing toggle + byte-cap control to
  `Immich Slideshow/Slideshow/BrokerSetupView.swift`, surfacing `HAPublishOptionsStore`, off by
  default (FR-710-15)
- [ ] T036 [P] Red XCUITest: the broker-setup image toggle persists across relaunch, extending
  `Immich SlideshowUITests/BrokerSetupUITests.swift`
- [ ] T037 Green T036 via XcodeBuildMCP/XCUITest; screenshot the new toggle
- [ ] T038 Run the full XCUITest suite via XcodeBuildMCP (`test_sim`) — must stay green before
  merge (screenshots alone miss UI-test regressions)
- [ ] T039 [P] README privacy note: document that photo metadata (and, if enabled, the photo
  image) are published to the broker by design
- [ ] T040 Secret grep over the new test suite + a manual log check: no broker credential, API
  key, or share-link password in any new log line, fixture, or UserDefaults key added by this
  feature
- [ ] T041 Once this feature is built and merged: move `710` from "Scheduled" to "Active" in
  `specs/700-ha-control/spec.md`'s cross-reference and in `docs/spec-overview.md` (end-of-work
  housekeeping — do not do this now)

---

## Dependencies & order

- **Setup** → **Foundational** → stories.
- **US1 (P1)** depends only on Foundational — it is the MVP.
- **US2 (P1)** depends only on Foundational; independent of US1 (different entities, different
  files after T004).
- **US3 (P2)** depends only on Foundational; independent of US1/US2.
- **US4 (P3)** depends on Foundational for the diagnostics sensors themselves, but its
  reconnect-republish test (T033) is most meaningful once US1–US3 exist (it asserts ALL enabled
  entities republish) — do it last even though it isn't a hard technical dependency.
- **Polish** last, after whichever stories are in scope for the first release slice.

## Parallel opportunities

- Within Foundational: T002 and T004 touch different files and can start together (T003 depends
  on T002; T004 is independent of both).
- US1, US2, and US3 can proceed fully in parallel once Foundational is green (different files:
  settings vs. photo/image vs. buttons all touch different slices of `HAControlCoordinator.swift`/
  `HADiscovery.swift`, so watch for merge conflicts in those two shared files rather than a real
  dependency).
- Within each story, the `[P]`-marked red-test tasks (different files) run in parallel; each
  implementation task follows its own red test.

## Implementation strategy (incremental delivery)

1. **MVP = Setup + Foundational + US1** — every display setting controllable from HA.
2. Add **US2** (photo/image) and **US3** (navigation) — independent, parallelizable.
3. Add **US4** (diagnostics + reconnect gate) — ties the full entity set together.
4. **Polish** — broker-setup UI, full XCUITest, secret check, README, spec status housekeeping.
