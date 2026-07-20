# Tasks: Purchase Gate & One-Time Unlocks

**Input**: Design documents from `/specs/1100-purchase-gate/`

**Prerequisites**: plan.md, spec.md, research.md, data-model.md, contracts/, quickstart.md

**Tests**: Included and non-optional — constitution I (Test-First) is NON-NEGOTIABLE. Every
implementation task is preceded by a task that lands a demonstrably red test.

**Organization**: Grouped by user story (US1–US6 from spec.md). Paths are repo-relative.
House rules apply throughout: Swift Testing on host where possible, XCTest only for
StoreKitTest/XCUITest; new app-target files need no pbxproj edit (synchronized groups); the
full XCUITest suite runs before merge.

## Format: `[ID] [P?] [Story] Description`

---

## Phase 1: Setup (Shared Infrastructure)

**Purpose**: The new package and test scaffolding exist and build on both platforms.

- [x] T001 Create `Packages/PurchaseKit` skeleton: `Package.swift` (platforms `.iOS(.v17)`,
      `.tvOS(.v17)`, zero dependencies), empty `Sources/PurchaseKit/` + `Tests/PurchaseKitTests/`
      with one placeholder test; `swift build`/`swift test` green on host.
- [x] T002 Add PurchaseKit as a local package dependency of both app targets (`Immich Slideshow`,
      `Immich SlideshowTV`) in `Immich Slideshow.xcodeproj/project.pbxproj` via the `xcodeproj`
      gem script pattern from 1000 (pbxproj explicitly in scope); verify both schemes build via
      XcodeBuildMCP.
- [x] T003 [P] Add StoreKit test configuration `Immich SlideshowTests/Configuration.storekit`
      defining the six products with the exact ids from data-model.md (3 non-consumables with
      Family Sharing, 3 consumable tips), wired into the iOS test scheme.

**Checkpoint**: both apps build with an empty PurchaseKit linked; `.storekit` file loads in the
test scheme.

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: Entitlement model, resolver, cache, store protocol/model, and app injection —
every user story depends on these.

- [x] T004 [P] RED: `Packages/PurchaseKit/Tests/PurchaseKitTests/ProductCatalogTests.swift` —
      `Entitlement`/`EntitlementSet` basics and `ProductCatalog.grants` mapping (pro→{pro},
      automation→{automation}, everything→{pro,automation}, tips→{}, unknown→{}).
- [x] T005 Implement `Packages/PurchaseKit/Sources/PurchaseKit/Entitlement.swift` and
      `ProductCatalog.swift` (ids per data-model.md) until T004 is green.
- [x] T006 [P] RED: `.../PurchaseKitTests/EntitlementResolverTests.swift` — the five resolver
      rules from data-model.md (union of grants, revoked excluded, tips nothing, unknown
      nothing, empty→{}).
- [x] T007 Implement `.../Sources/PurchaseKit/EntitlementResolver.swift` (pure function over
      `OwnedTransaction`) until T006 is green.
- [x] T008 [P] RED: `.../PurchaseKitTests/EntitlementSnapshotCacheTests.swift` — round-trip via
      injected `UserDefaults` suite, versioned key `purchase.entitlements.v1`, snapshot never
      expires, corrupt/absent data → nil (not crash).
- [x] T009 Implement `.../Sources/PurchaseKit/EntitlementSnapshotCache.swift` until T008 green.
- [x] T010 Define `.../Sources/PurchaseKit/StoreClient.swift` protocol per
      contracts/purchasekit-api.md (`products/purchase/restore/ownedTransactions/updates`,
      `OwnedTransaction`, `PurchaseOutcome`, `DisplayProduct`) plus a scripted
      `StoreClientFake` under `Tests/PurchaseKitTests/Fakes/` (queueable results, failure
      injection, updates continuation).
- [x] T011 RED: `.../PurchaseKitTests/EntitlementStoreTests.swift` — `current` seeded
      synchronously from cache at init (client never awaited); successful `refresh()` applies
      + persists; `restore()` = client restore then refresh.
- [x] T012 Implement `.../Sources/PurchaseKit/EntitlementStore.swift` (@Observable) until T011
      is green.
- [x] T013 Create compile-only skeleton `.../Sources/PurchaseKit/StoreKitClient.swift`
      (conforms to `StoreClient`, trivial bodies, NO behavioral logic — constitution I: the
      adapter's behavior is implemented in T030 only after its StoreKitTest cases are red).
- [x] T014 Wire injection + hermetic seams in both apps: create `EntitlementStore` at startup
      in `Immich Slideshow/Immich_SlideshowApp.swift` and the TV entry (`Immich
      SlideshowTV/TVRootView.swift`), honoring `--uitest-entitlements=<none|pro|automation|all>`
      and `--uitest-store=<stub|unavailable|pending>` per contracts/uitest-seams.md (stub
      client lives in PurchaseKit, guarded by the uitest flag).

**Checkpoint**: PurchaseKit host suite green; both apps launch with a seeded stub entitlement
store under `--uitest`.

---

## Phase 3: User Story 1 — The free frame stays whole (P1) 🎯 MVP

**Goal**: All four gates exist at the point of effect; free tier is untouched; gated features
are visible as dimmed+badged+tappable locked rows; playback never shows purchase UI.

**Independent test**: launch with `--uitest-entitlements=none`: every onboarding path and the
whole free feature set work; locked rows present and hittable; sustained stub playback shows
zero `unlock.`-prefixed elements.

- [x] T015 [US1] RED: gating-flag tests (host, app test target or PurchaseKitTests where the
      helper lands): `effective(kenBurns:entitlements:)` and clock-participation truth tables —
      setting on + no `.pro` → off; setting preserved regardless. Include the relock-boundary
      rule (spec edge case / FR-1100-12): an entitlement loss during playback never alters the
      in-flight photo's motion — the effective flag is latched per photo and applies at the
      next photo advance (or next foreground), never mid-photo.
- [x] T016 [US1] Gate Ken Burns + clock at point of effect in
      `Immich Slideshow/Slideshow/SlideshowView.swift` (effective flags feeding
      `KenBurnsMotionModifier` and the `ClockOverlayView` branch) until T015 is green,
      including the per-photo latch (T015's boundary rule);
      `ThemeSettings`/`ClockSettings` reads/writes unchanged.
- [x] T017 [P] [US1] Same Ken Burns gate in `Immich SlideshowTV/TVSlideshowView.swift`
      (tvOS clock rendering doesn't exist yet — 1000 leftover; nothing to gate there).
- [x] T018 [US1] RED then implement: coordinator-gate tests — `.automation` absent →
      `HAControlCoordinator` never constructed/started; present → started. Gate in
      `Immich Slideshow/Slideshow/SlideshowRemoteControlAdapter.swift` and
      `Immich SlideshowTV/TVRemoteControlAdapter.swift`. Broker config and keychain untouched
      (asserted by test). Also assert the R5 state-topic rule: MQTT state topics report the
      STORED settings values (data), not effective rendering — an Automation-only owner setting
      the Ken Burns/clock selects sees the stored value echoed while rendering stays Pro-gated.
- [x] T019 [US1] RED then implement: intent guards in
      `Immich Slideshow/Intents/FrameIntents.swift` — every remote-control intent's
      `perform()` throws the localized `unlock.required.automation` error without
      `.automation`; error message asserted in test; intents remain listed in Shortcuts.
- [x] T020 [US1] RED: XCUITest `Immich SlideshowUITests/PurchaseGateUITests.swift` — seam
      assertions 1 + 2 from contracts/uitest-seams.md (locked rows
      `settings.row.kenburns.locked` / `.clock.locked` / `.broker.locked` exist, are hittable;
      a stub playback window of ≥ 3 photo advances surfaces no `unlock.`-prefixed element),
      plus one onboarding-path assertion under `--uitest-entitlements=none` (SC-1100-01: the
      stub shared-link onboarding flow completes with zero `unlock.`-prefixed elements).
- [x] T021 [US1] Implement `LockedRow` (dimmed + lock glyph + tier badge + tappable) in
      `Packages/PurchaseKit/Sources/PurchaseKit/UI/LockedRow.swift` with the contract
      accessibility identifiers; SwiftUI preview renders on iOS + tvOS.
- [x] T022 [US1] Apply locked treatment + "Unlocks" section skeleton in
      `Immich Slideshow/Slideshow/SlideshowSettingsView.swift` (Ken Burns row, clock rows,
      broker/remote-control entry; free rows untouched) until T020 is green.

**Checkpoint**: MVP — the gate exists and bites; a free frame is indistinguishable from
today's default experience. US1 acceptance scenarios pass hermetically.

---

## Phase 4: User Story 2 — Unlock a paid tier (P1)

**Goal**: Tapping a locked row leads to one unlock screen; buying activates immediately.

**Independent test**: `--uitest-entitlements=none --uitest-store=stub`: tap Ken Burns row →
unlock screen → buy → row unlocks with no relaunch; `unavailable`/`pending` stubs drive their
states.

- [x] T023 [US2] RED: `.../PurchaseKitTests/PurchaseViewModelTests.swift` — offer computation
      (none→3 products; one owned→missing single only, FR-1100-04; all→owned state), store
      throw → `.unavailable` (no prices), `.pending` terminal until update event, cancel/fail →
      back to `.ready` with no side effects.
- [x] T024 [US2] Implement `.../Sources/PurchaseKit/PurchaseViewModel.swift` until T023 green.
- [x] T025 [US2] RED: extend `PurchaseGateUITests.swift` with seam assertions 3 + 5 and the
      stub purchase end-to-end (buy on unlock screen → locked row gone without relaunch —
      SC-1100-03 mechanism).
- [x] T026 [US2] Implement `.../Sources/PurchaseKit/UI/UnlockScreenView.swift` — what-you-get
      list, live Ken Burns demo slot (reuses `KenBurnsMotionModifier` on current photo, bundled
      neutral sample as fallback per research R7), localized price, buy, Restore, `unavailable`
      + `pending` states; accessibility ids per contract.
- [x] T027 [US2] Present unlock screens from every locked row and the Unlocks section in
      `Immich Slideshow/Slideshow/SlideshowSettingsView.swift`; no auto-presentation anywhere;
      T025 green.

**Checkpoint**: purchase loop works end to end against the stub store; US2 scenarios 1–3 pass
hermetically (scenario 4 lands with T030).

---

## Phase 5: User Story 3 — Unattended frame never loses purchases (P1)

**Goal**: Cache-first offline operation, last-known-good on failure, revocation relocks
gracefully, adapter edge states proven against StoreKitTest.

**Independent test**: entitled snapshot + a `StoreClient` that always fails → features active
at first render across relaunches; StoreKitTest session drives refund/deferral flows.

- [x] T028 [US3] RED: extend `EntitlementStoreTests.swift` — refresh failure/offline never
      shrinks `current` (last-known-good); `updates` event triggers re-resolve + persist
      (Ask-to-Buy approval arrives late); successful resolve to a smaller set (revocation)
      shrinks + persists (FR-1100-12); snapshot age is irrelevant (no expiry path exists).
- [x] T029 [US3] Implement `listenForUpdates()` + never-downgrade refinement in
      `EntitlementStore.swift` until T028 is green.
- [x] T030 [US3] RED then implement: StoreKitTest adapter tests (XCTest — strictly-necessary
      exception) in `Immich SlideshowTests/StoreKitClientTests.swift` against T003's
      `.storekit` config — purchase→owned, restore, refund→excluded from owned, Ask-to-Buy
      deferral then approval, interrupted purchase completes on next launch, unverified
      transaction dropped. Each case red first (observed: notImplemented → productUnavailable),
      then `StoreKitClient.swift` implemented to satisfy them: JWS-verify only, finish after
      delivery, ownership from `Transaction.currentEntitlements`, tips never owned, `updates`
      off `Transaction.updates`. **Runtime caveat:** `SKTestSession` serves 0 products under the
      headless `xcodebuild test` path (XcodeBuildMCP) — reproduced across every init style and
      on iOS 18.6 + 26.x, so it is the runner, not the runtime. A `setUp` skip-guard turns that
      into an honest **skip** (never a false pass/red); the cases run for real from the Xcode IDE
      runner or on device (folds into T042). Adapter otherwise held by review + the pure host
      tests above the seam. Launch `refresh()` + `listenForUpdates()` now wired on both apps'
      production entry points. Full iOS suite green on iOS 18.6 (153/0/9); tvOS builds.
- [x] T031 [US3] Launch-path integration test (host, fakes): entitled snapshot in defaults +
      never-responding client → gating flags active in the first render pass with no await
      (FR-1100-10); document the invariant in `EntitlementStore.swift` header.

**Checkpoint**: all three P1 stories complete — the gate is sellable and unattended-safe.

---

## Phase 6: User Story 4 — Purchases follow the household (P2)

**Goal**: Restore everywhere, tvOS purchase/restore natively, device gates enumerated.

**Independent test**: stub-store restore repopulates entitlements on a wiped install; TV
target shows the same locked/unlock surfaces; real family/universal checks are device-day.

- [x] T032 [US4] RED then implement: Restore action in settings (`SlideshowSettingsView.swift`
      Unlocks section) calling `EntitlementStore.restore()`; host test: restore triggers
      client sync + refresh + persist; XCUITest: `unlock.restore` present on unlock screens
      and in settings.
- [x] T033 [P] [US4] tvOS unlock surface: new `TVSettingsView` (the gear destination) with the
      Ambience/Pro locked row, the Home-Assistant row (broker editor when entitled, else
      `TVLockedBrokerView` — a tvOS-native equivalent of the iOS `LockedBrokerView`, since
      NavigationStack/navigationBarTitleDisplayMode don't exist on tvOS), and an Unlocks section
      (Restore + tip). Reuses PurchaseKit `UnlockScreenView`/`TipJarView`/`LockedRow` via
      `fullScreenCover`; fail-closed; nothing auto-presents (SC-1100-02). Fixed the shared
      unlock/tip screens to carry an opaque backing on tvOS (a cover, unlike an iOS sheet, supplies
      none). Verified on the Apple TV simulator under DEBUG `--uitest-tv-settings` /
      `--uitest-tv-present=` seams: `=none` shows both locked rows, `=all` shows none, and the
      locked-broker / unlock / tip screens all render focus-navigable. (Decision 2026-07-19: no TV
      UI-test target in this feature — verification is screenshot review; TV gating/view-model host
      tests still have no home target, which stays a 1000 leftover.) Real family/universal checks
      → T034 device day.
- [x] T034 [US4] Extend `docs/manual-verification.md` FINAL DEVICE DAY with the 1100 items
      from quickstart.md §5 (ASC product setup + id-drift smoke test, sandbox purchase/cancel/
      Ask-to-Buy, restore on second device, Family Sharing member, Apple TV universal purchase,
      24 h offline entitlement soak piggyback, the ≥ 4 h free-tier wall-clock playback run with
      zero purchase UI (SC-1100-02), b8-never-released + v1.1-first-release check).

**Checkpoint**: household flows work against stubs/sandbox-config; physical checks queued on
the existing device day.

---

## Phase 7: User Story 5 — Pre-gate configuration degrades gracefully (P2)

**Goal**: Unentitled devices keep every stored value; locked banner instead of empty screens;
purchase resumes with zero re-entry.

**Independent test**: seed broker config, launch `--uitest-entitlements=none` → values
visible (masked as usual) behind a locked banner, no connect attempt; stub-purchase
Automation → coordinator starts with stored config.

- [x] T035 [US5] RED then implement: locked-banner state in
      `Immich Slideshow/Slideshow/BrokerSetupView.swift` and
      `Immich SlideshowTV/TVBrokerSetupView.swift` — stored config shown (secrets masked as
      today), `settings.row.broker.locked` banner, no clearing/migration of any stored value
      (host tests assert keychain/defaults untouched by the gate path).
- [x] T036 [P] [US5] Negative test in `Packages/ConfigSyncKit/Tests/ConfigSyncKitTests/`:
      encoded sync payloads contain no entitlement/purchase keys (spec edge case "entitlement
      state vs. config sync"); assert against the payload's coding keys.
- [x] T037 [US5] Purchase-resumes test: host integration (fakes) — seeded broker config +
      stub purchase of Automation → coordinator starts with the previously stored settings,
      zero re-entry (FR-1100-14); plus XCUITest seam assertion 6 (seeded config, `none`:
      fields populated + locked banner + nothing cleared).

**Checkpoint**: Jan's long-running frames survive the gated update with nothing lost.

---

## Phase 8: User Story 6 — Tip jar (P3)

**Goal**: Optional tips, settings-only, zero functional effect, never solicited.

**Independent test**: tip via stub store → thank-you state; no entitlement change; no tip UI
outside settings.

- [x] T038 [US6] RED then implement: `.../Sources/PurchaseKit/UI/TipJarView.swift` + a
      `settings.tipjar` row in `SlideshowSettingsView.swift`; host test: consumable purchase
      leaves `EntitlementSet` unchanged; XCUITest: tip flow reaches `tipjar.thanks`, tip row
      absent everywhere outside settings, no unprompted tip UI during playback window.

---

## Phase 9: Polish & Cross-Cutting

- [x] T039 [P] Copy audit (SC-1100-07): sweep `Immich Slideshow/Localizable.xcstrings`, all
      PurchaseKit UI strings, `docs/app-store-listing.md`, `README.md`, and user-facing pages
      under `docs/` for "lifetime"/subscription terminology on the unlocks (FR-1100-05 covers
      any user-facing document); sanctioned phrasing "one-time purchase"; note the audit
      command + result in specs/1100-purchase-gate/tasks.md Status.
- [x] T040 Full verification gate (2026-07-20): iOS build ✓ + tvOS build ✓; PurchaseKit host
      suite **110/110** (`swift test`); full XCUITest suite on the default iPad sim (iOS 26.5)
      **153 passed / 0 failed / 9 skipped** — the 9 skips are the ASC-screenshot capture +
      live-demo smoke (both intentional) and the 7 SKTestSession cases (skip-guarded under headless
      `xcodebuild`; their real run folds into T042). Same result on iOS 18.6. tvOS unlock surface
      screenshot-verified on the Apple TV simulator under `--uitest-entitlements`. One benign
      pre-existing warning (AppIntentsKit module-scan noting a HAControlKit dependency); no errors.
- [x] T041 [P] Docs sync (2026-07-20): status lines flipped in `docs/spec-overview.md` (1100 row)
      and the CLAUDE.md active-feature block; spec/tasks checkboxes checked; quickstart.md §5 kept
      in step with `docs/manual-verification.md` §D (both now name the Xcode-IDE/device
      StoreKitTest run as a device-day item).
- [ ] T042 Sequencing guard (manual, with Jan): confirm in ASC that v1.0 b8 remains
      unreleased and version 1.1 is the gated first-release vehicle (FR-1100-17); prices
      entered in ASC only. Blocked on Jan's ASC access — not automatable.

---

## Phase 10: Free HA telemetry — control-only gate (US5 amendment, 2026-07-20)

Amendment: HA telemetry is free, only *control* is gated (FR-1100-03 / FR-1100-03a). Folded into
1100 before first public release (widens the free tier — never a claw-back). Inline/TDD (Codex off).

- [ ] T043 [US5] RED then implement: partition the entity model — mark each `HAEntity` as
      read-only sensor vs controllable (command-bearing) in `Packages/HAControlKit/.../
      HAEntityState.swift`. Test asserts sensors = {currentPhoto, currentPhotoImage, phase,
      photoCount, version}; controls = {playback, brightness, album, the settings entities, next,
      previous}.
- [ ] T044 [US5] RED: coordinator-mode tests in HAControlKit — in `.telemetryOnly`, `announce()`
      publishes sensor discovery + availability only and subscribes to **zero** command topics
      (`handleIncoming` never wired); in `.full`, behaviour is unchanged. 
- [ ] T045 [US5] Implement the mode in `HAControlCoordinator`: add `mode` (`.telemetryOnly` /
      `.full`); split `announce()`'s per-entity publish vs subscribe; gate control-entity
      discovery + `subscribe` + `startConsumers`/`handleIncoming` behind `.full`. GREEN T043/T044.
- [ ] T046 [US5] App wiring (iOS `Immich_SlideshowApp.swift`): replace the all-or-nothing
      `AutomationCoordinatorGate` with mode selection — `.telemetryOnly` when a broker is
      configured but Automation is unentitled, `.full` when entitled; keychain broker read is now
      free-tier telemetry (FR-1100-14 restated).
- [ ] T047 [US5] App wiring (tvOS `TVRootView.swift`): mirror T046 (inlined gate).
- [ ] T048 [US5] Settings UI (iOS `SlideshowSettingsView.swift` + `BrokerSetupView.swift`): broker
      connection section goes live/free; narrow the locked surface to a *control-locked* banner;
      repurpose `LockedBrokerView` from "mask everything" → "connection live, control locked".
- [ ] T049 [US5] Settings UI (tvOS `TVSettingsView.swift` + `TVLockedBrokerView`): mirror T048.
- [ ] T050 [US5] Restate US5 tests: update the host integration test(s) + any XCUITest asserting the
      old "no connection / fully-masked" behaviour to the telemetry-free contract (SC-1100-06).
- [ ] T051 Verification gate: PurchaseKit + HAControlKit host green; iOS + tvOS build; iOS XCUITest
      green; add an unentitled-telemetry item to the 710 checklist in `docs/manual-verification.md`.

## Phase 11: Transparency statement ("Where your money goes", 2026-07-20)

- [x] T052 [P] `docs/where-the-money-goes.md` — English reference pledge (statement only, no
      transparency log). Done 2026-07-20.
- [ ] T053 Add the short in-app pledge string to the Unlocks settings footer (iOS
      `SlideshowSettingsView.swift` + tvOS `TVSettingsView.swift`) → new key in
      `Immich Slideshow/Localizable.xcstrings`.
- [ ] T054 [translate-later] Translate the pledge string into the separate localized file.
- [ ] T055 [P] Optional: one pledge line in `docs/app-store-listing.md`.

**Status (2026-07-20):** T043–T053 done and verified. Spec 1100/710 amended; HAControlKit
`.telemetryOnly`/`.full` mode + `HAEntity` sensor/control partition (94 host tests green, incl. 5
new mode tests + all prior coordinator tests); iOS (`Immich_SlideshowApp` + `AutomationCoordinatorGate`)
and tvOS (`TVRootView`) wiring select the mode by entitlement; iOS + tvOS settings UI restructured —
the broker editor is live/free with an Automation "Remote control" control-locked banner above it
(old `LockedBrokerView`/`TVLockedBrokerView` masked screens removed); `PurchaseGateCoordinatorTests`
restated to the telemetry-free contract (13 green) and `PurchaseGateUITests`/`BrokerSetupUITests`
updated (green); pledge footer added on both platforms; `docs/manual-verification.md` 710 checklist
updated for free telemetry. **T051 gate:** iOS + tvOS build clean (0 warnings); targeted iOS suite
22/0/0 + HAControlKit host 94/0; iOS settings screenshot-verified (control-locked banner over the
prefilled live editor).

**Regression found + fixed during the full-suite gate:** the first iOS HA-section design used an
always-present `DisclosureGroup` for the unentitled broker editor, which starved the Storage
section's async `.task` (usage stuck at "0 bytes" — `SettingsStorageUITests/testClearResets…`).
Root-caused by stash/bisect (see the `disclosuregroup-starves-sibling-task` memo); fixed by showing
the editor **inline** (plain Section, no DisclosureGroup) in the unentitled path while keeping the
committed collapsible group for entitled. PurchaseGate + BrokerSetup + Storage re-verified 12/0/0 on
the unmodified tests; iOS + tvOS build clean.

**Remaining: T054** (translate the pledge string — deferred) and **T055** (optional listing line).

---

## Dependencies & Execution Order

- **Phase 1 → Phase 2 → Phase 3**: strictly sequential (package → model/injection → gates).
- **US1 (Phase 3)** blocks US2 (locked rows are the entry point) and is the MVP.
- **US2 (Phase 4)** blocks the purchase legs of US5/US6 (stub purchase path) and T032's UI.
- **US3 (Phase 5)** is independent of US2 after Phase 2 (T028/T029/T031 touch only
  PurchaseKit; T030 only needs T003 + T013) — it can run in parallel with Phase 4.
- **US4/US5/US6** are mutually independent after their prerequisites; T033, T036, T039, T041
  are parallel-friendly ([P]).
- **T040** last before merge; **T042** rides the device/ASC day.

```
Setup ─→ Foundational ─→ US1 (MVP) ─→ US2 ─→ US4 ─→ US6 ─→ Polish (T039–T041) ─→ T040
                              └────────→ US3 ∥        └─→ US5 ─┘         (T042 device/ASC day)
```

## Parallel opportunities

- Phase 2: T004/T006/T008 (red tests, different files) in parallel; T005/T007/T009 pair-wise.
- After Phase 3: US3 (PurchaseKit-internal) parallel to US2 (UI).
- T017 (TV gate), T033 (TV surface), T036 (ConfigSync test), T039/T041 (docs/audit) all [P].

## Implementation strategy

MVP = Phases 1–3 (gate exists, free tier provably whole) — this alone satisfies the
release-blocking property of FR-1100-17 in spirit: nothing ungated can ship by accident once
US1 is merged. Then US2+US3 complete the P1 set (sellable + unattended-safe) — that trio is
the minimum for the 1.1 submission. US4–US6 and polish follow before the release build; T042
and the quickstart §5 checklist gate the actual App Store release, not the merge.

## Status (updated 2026-07-20)

Implementation on branch `1100-purchase-gate` is **code-complete: T001–T041 done + committed**;
only **T042** (the manual ASC/device day) remains, and it is blocked on Jan's ASC access. Every
user story's logic + UI is in — US1–US6 gates, US5 broker degradation on iOS, the real StoreKit
adapter, and the tvOS unlock surface. Final gate (T040, 2026-07-20): PurchaseKit host **110/110**;
full iOS XCUITest suite **153/0/9** on the default iPad sim (iOS 26.5), same on 18.6 — the 9 skips
are the App Store screenshot + live-demo smoke (both intentional) plus the 7 StoreKitClientTests,
which skip-guard out under headless `xcodebuild` (see T030); iOS + tvOS both build; the tvOS unlock
surface is Apple-TV-simulator screenshot-verified under the `--uitest-entitlements` seams (T033).

**T030 done** with a runtime caveat: the real `StoreKitClient` adapter + its 7 SKTestSession cases
are in, and launch `refresh()` + `listenForUpdates()` are wired on both apps' production entry
points. `SKTestSession` serves 0 products under the headless `xcodebuild test` path used here, so
the cases skip honestly (never a false pass/red) and must be run once from the Xcode IDE runner or
on device — that verification folds into **T042**. The adapter is otherwise held by review + the
pure PurchaseKit host tests above the seam.

**T040 + T041 done 2026-07-20**: full verification gate recorded above; docs synced
(`docs/spec-overview.md`, CLAUDE.md, quickstart §5 ↔ manual-verification §D).

Remaining: **T042** only — the manual ASC/device day (blocked on Jan's ASC access): create the
IAPs, run the sandbox purchase/restore/Family-Sharing/universal-purchase checks, the one
Xcode-IDE/device StoreKitTest run (the SKTestSession cases skip under headless `xcodebuild`), and
the release sequencing guard (v1.0 b8 stays unreleased; v1.1 gated build is the first public
release, FR-1100-17). See `docs/manual-verification.md` §D + quickstart §5.

- **T039 copy audit — PASS.** `grep -rin "lifetime"` over PurchaseKit UI, Localizable.xcstrings,
  app-store-listing.md, README.md, and docs/: zero user-facing hits (only the doc-comment stating
  the ban and the device-day item enforcing it). Subscription/recurring language: none beyond the
  sanctioned "No subscription, no recurring charge." No price points in the repo (StubStoreClient's
  `$1.00` is a labelled DEBUG fixture). License already FSL-1.1-MIT in README + listing.

Remaining: **T042 only** (the manual ASC/device day — also hosts the one-off Xcode-IDE/device
StoreKitTest run). T001–T041 all landed by 2026-07-20; T030 (StoreKit adapter + SKTestSession +
launch wiring), T033 (tvOS unlock surface), and T040/T041 (gate + docs) closed this session.
