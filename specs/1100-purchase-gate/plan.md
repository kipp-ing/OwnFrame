# Implementation Plan: Purchase Gate & One-Time Unlocks

**Branch**: `1100-purchase-gate` | **Date**: 2026-07-19 | **Spec**: [spec.md](spec.md)

**Input**: Feature specification from `/specs/1100-purchase-gate/spec.md`

## Summary

> **Amended 2026-07-23 (single unlock).** The two paid tiers (**Pro** = ambience, **Automation**
> = remote control) and the optional everything-bundle were collapsed into **one** one-time
> non-consumable purchase, the **Supporter Unlock**, which grants every gated capability at once
> (spec.md FR-1100-02/04, amended 2026-07-22). Rationale: for a niche self-hosted audience a
> single "support the project, unlock everything" purchase is lower-friction than a tier ladder,
> and it deletes the whole class of bundle-vs-single-unlock overlap edge cases. The free tier is
> unchanged, so nothing is clawed back. Everywhere below that names "Pro", "Automation", or
> "bundle", read "the Supporter Unlock"; the gated *capabilities* are unchanged, they are simply
> all granted by the one product. The architecture (point-of-effect gates, cache-first offline,
> settings-are-data) is otherwise as described.

Add a StoreKit 2 purchase gate as a new `PurchaseKit` package plus thin wiring in both app
targets. One one-time non-consumable unlock — the **Supporter Unlock**, granting every gated
capability (Ken Burns motion, clock overlay, HA/MQTT remote control, and App Intents) — plus
consumable tips. Entitlements resolve from StoreKit 2 transactions, are cached in UserDefaults
for offline/unattended operation, and gate features **at the point of effect** in the app
targets (rendering, coordinator start, intent execution) — settings remain untouched data, so
pre-gate configs, HA-pushed values, ConfigSync payloads, and revocations all degrade the same
graceful way. Release sequencing is part of the deliverable: the gated build ships as the first
public version; v1.0 b8 stays unreleased.

## Technical Context

**Language/Version**: Swift 6 (strict concurrency), SwiftUI

**Primary Dependencies**: StoreKit 2 (`Product`, `Transaction`, `Transaction.currentEntitlements`,
`Transaction.updates`, `AppStore.sync()`), StoreKitTest (test-only, `SKTestSession` +
`.storekit` configuration). No third-party dependencies.

**Storage**: UserDefaults for the entitlement snapshot cache (entitlements are not secrets —
constitution III scope untouched; keychain contents unchanged). StoreKit's own on-device
transaction store is the source of truth when reachable.

**Testing**: Swift Testing on host/simulator for all pure logic (resolver, store model, cache,
gating flags) against protocol fakes; XCTest only for `SKTestSession` adapter tests (StoreKitTest
requires the Xcode test environment); XCUITest via the existing `--uitest-*` launch-seam pattern
for locked/unlocked UI; real sandbox purchases on device for the SC device gates.

**Target Platform**: iPadOS/iOS 17+ and tvOS 17+ (both app targets: `OwnFrame`,
`OwnFrameTV`; shared bundle id `ing.kipp.Immich-Slideshow` → universal purchase is
already structurally in place).

**Project Type**: Mobile app — new local SPM package `Packages/PurchaseKit` + app-target wiring.

**Performance Goals**: Entitlement read at launch is synchronous from cache — zero added launch
latency and zero network dependence (FR-1100-10). No per-frame cost in the slideshow loop
(entitlement is a stored flag, not a per-frame query).

**Constraints**: Offline-indefinitely operation of owned features; no purchase UI during
playback without user action; no subscriptions/time-based states; settings/secrets preserved
byte-for-byte when unentitled (FR-1100-14); entitlement state never enters ConfigSync payloads.

**Scale/Scope**: 1 unlock SKU + 2–3 tip SKUs; ~1 new package, ~6 app-target files touched per
platform, 1 new settings section, 1 unlock screen, 1 tip screen.

## Constitution Check

*GATE: evaluated against constitution v1.1.1 — re-checked after Phase 1 design (below).*

| Principle | Status | Notes |
|---|---|---|
| I. Test-First (NON-NEGOTIABLE) | PASS | Every task red-first; pure resolver/store logic is host-testable by design; StoreKit adapter kept thin so the untestable surface is minimal. |
| II. Modular Isolation | PASS | StoreKit behind a `StoreClient` protocol; persistence behind the injected defaults seam; no hidden singletons (static `Transaction.*` APIs are wrapped by the adapter). Feature packages (SlideshowKit, ThemeKit, HAControlKit) stay policy-free — gating lives in app wiring. |
| III. No Secrets in Plaintext (NON-NEGOTIABLE) | PASS | No secrets involved. Entitlement flags are not secrets; broker credentials remain in the keychain untouched (FR-1100-14). Nothing purchase-related syncs via KVS/CloudKit. |
| IV. Transport-Layer Security | PASS | StoreKit owns its transport; no URLSession changes, no TLS surface added. |
| V. Respect Platform Boundaries | PASS | Offline entitlements ride StoreKit's on-device transaction store + our cache — no receipt hacks, no fighting review/sandbox mechanics; Ask-to-Buy pending and revocation use the platform's own flows. |
| VI. Verifiable Acceptance Criteria | PASS | SC-1100-01…09 map to host tests, XCUITests, and an explicit device/ASC checklist (quickstart.md). |
| VII. Plain and Light by Default | PASS | Defaults unchanged: the calm default frame is identical free/paid; gated features were opt-in already. |

**Post-design re-check (Phase 1)**: unchanged — PASS on all seven. The one deliberate judgment
call (UserDefaults for the entitlement cache, tamper-acceptable) is documented in research.md
R4 and does not touch principle III's scope.

## Project Structure

### Documentation (this feature)

```text
specs/1100-purchase-gate/
├── spec.md              # Feature spec (amended 2026-07-22: single Supporter Unlock — all gated caps)
├── plan.md              # This file
├── research.md          # Phase 0 — decisions R1–R10
├── data-model.md        # Phase 1 — entitlement/product/state model
├── quickstart.md        # Phase 1 — validation guide incl. device/ASC checklist
├── contracts/
│   ├── purchasekit-api.md   # StoreClient / EntitlementStore / resolver contracts + product ids
│   └── uitest-seams.md      # launch args + accessibility identifiers
├── checklists/requirements.md
└── tasks.md             # Phase 2 (/speckit-tasks)
```

### Source Code (repository root)

```text
Packages/PurchaseKit/                          # NEW package, platforms .iOS(.v17) + .tvOS(.v17)
├── Package.swift
├── Sources/PurchaseKit/
│   ├── Entitlement.swift                      # Entitlement, EntitlementSet
│   ├── ProductCatalog.swift                   # ProductID + entitlement mapping (single source of truth)
│   ├── EntitlementResolver.swift              # pure: owned/revoked transactions → EntitlementSet
│   ├── StoreClient.swift                      # protocol (products/purchase/restore/updates)
│   ├── StoreKitClient.swift                   # thin StoreKit 2 adapter (conforms StoreClient)
│   ├── EntitlementStore.swift                 # @Observable; cache-first load, refresh, updates
│   ├── EntitlementSnapshotCache.swift         # UserDefaults-backed snapshot (injected suite)
│   ├── PurchaseViewModel.swift                # unlock-screen state machine (incl. unavailable)
│   └── UI/
│       ├── LockedRow.swift                    # dimmed + lock/tier badge + tappable (FR-1100-09)
│       ├── UnlockScreenView.swift             # contents, live demo slot, price, buy, restore
│       └── TipJarView.swift
└── Tests/PurchaseKitTests/                    # Swift Testing, protocol fakes (host-runnable)

OwnFrame/                              # iOS app target — wiring only
├── Slideshow/SlideshowView.swift              # effective Ken Burns/clock flags (point-of-effect gate)
├── Slideshow/ClockOverlayView.swift           # (rendered only when entitled; no internal change expected)
├── Slideshow/SlideshowSettingsView.swift      # locked rows, Unlocks section, tip jar, Restore
├── Slideshow/BrokerSetupView.swift            # locked banner when unentitled (config preserved)
├── Slideshow/SlideshowRemoteControlAdapter.swift  # HA coordinator start gated on .supporter
├── Intents/FrameIntents.swift                 # entitlement check → localized needsUnlock error
└── OwnFrameApp.swift                  # EntitlementStore injection + --uitest seams

OwnFrameTV/                            # tvOS app target — same gates, TV idioms
├── TVSlideshowView.swift                      # effective Ken Burns flag
├── TVRootView.swift / TVOnboardingView.swift  # EntitlementStore injection + unlock surface entry
├── TVBrokerSetupView.swift                    # locked banner when unentitled
└── TVRemoteControlAdapter.swift               # coordinator start gated on .supporter

OwnFrameUITests/                       # XCUITest: gating UI, seams per contracts/uitest-seams.md
OwnFrameTests/                         # SKTestSession adapter tests (XCTest) + .storekit config
```

**Structure Decision**: One new policy package (`PurchaseKit`) holding all purchase/entitlement
logic and reusable locked/unlock UI; every *gate* is applied in the two app targets at the point
of effect, because that is where SlideshowView/ClockOverlayView/Settings/Intents/coordinator
wiring already live — feature packages remain mechanism-only (constitution II), and the
HA-sets-a-gated-setting case resolves itself (the setting applies, the effect stays
gated). Adding the package to the Xcode project requires a `project.pbxproj` edit — explicitly
in scope for this feature, done via the `xcodeproj` gem script pattern established by 1000.

## Complexity Tracking

No constitution violations to justify. The single notable trade-off (UserDefaults entitlement
cache = technically user-editable) is a deliberate product decision documented in research.md R4,
not a principle violation: entitlements are not secrets, and the copy-protection stance for a
public-source app is goodwill + fair pricing, not client-side hardening.
