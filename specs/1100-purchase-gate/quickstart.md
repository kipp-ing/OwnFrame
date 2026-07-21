# Quickstart — Validating the Purchase Gate (1100)

How to prove the feature works, layer by layer. Contracts:
[purchasekit-api.md](contracts/purchasekit-api.md), [uitest-seams.md](contracts/uitest-seams.md).
Model: [data-model.md](data-model.md).

## 1. Host unit tests (fast loop)

```
swift test --package-path Packages/PurchaseKit
```

Green means: resolver rules (bundle→both, revocation, tips/unknown ignored), snapshot cache
round-trip + never-expires, store model cache-first launch + refresh-never-downgrades +
updates application, view-model offer computation and `unavailable`/`pending` states.

## 2. Full suites via XcodeBuildMCP (primary gate)

Run `test_sim` on the iOS scheme (and the TV scheme for tvOS wiring):

- **Unit**: everything from layer 1 plus app-target gating tests (effective Ken Burns/clock
  flags, coordinator-not-started, intent guard error) and the ConfigSync negative test (no
  entitlement keys in payloads).
- **StoreKitTest adapter tests** (XCTest + `Configuration.storekit` in `Immich SlideshowTests`):
  sandbox-free purchase, restore, refund/revocation, Ask-to-Buy deferral,
  interrupted-transaction recovery.
- **XCUITest**: the seven binding assertions in uitest-seams.md. Repo rule applies: run the
  full XCUITest suite before merge, not single classes.

## 3. Interactive simulator check

Boot the pinned simulator, launch with seams, eyeball the states:

```
--uitest --uitest-entitlements=none --uitest-store=stub      # locked frame: dimmed+badged rows
--uitest --uitest-entitlements=none --uitest-store=unavailable  # store-down unlock screen
--uitest --uitest-entitlements=all                            # fully unlocked, no lock chrome
```

Then a stub purchase end-to-end: entitlements=none + store=stub → tap Ken Burns row → buy on
the unlock screen → row unlocks without relaunch (SC-1100-03's mechanism, stubbed).

Screenshots don't catch regressions here (memory: `run-full-xcuitest-before-merge`) — the
XCUITest layer is the gate; this step is for the human eye only.

## 4. Expected outcomes summary

| Check | Expect |
|---|---|
| Fresh launch, no purchases, airplane mode | Free tier fully works; zero purchase UI (SC-1100-01) |
| Stubbed purchase | Feature active < 10 s, no restart (SC-1100-03) |
| Kill + relaunch offline after purchase | Owned features active at first render (FR-1100-10) |
| Refund via StoreKitTest session | Relock on next refresh; settings intact (FR-1100-12) |
| Seeded broker config, entitlements=none | Values visible/masked, locked banner, no connect attempt (SC-1100-06) |
| String audit (`grep -ri lifetime` over strings/listing) | Zero hits for the unlocks (SC-1100-07) |

## 5. Device & App Store Connect checklist (manual — extends the FINAL DEVICE DAY list)

Code-complete is not ship-ready until these are ticked (tracked in
`docs/manual-verification.md` alongside the existing device gates):

- [ ] ASC: create IAPs exactly matching `ProductID` raw values; Family Sharing ON for the three
      unlocks; localized names/descriptions using "one-time purchase" phrasing (never
      "lifetime"); attach to the 1.1 submission (IAPs reviewed with the build).
- [x] ~~Run `StoreKitClientTests` from the Xcode IDE (Cmd-U) or on device.~~ **Done 2026-07-21 —
      not a device-day item.** The suite skipped because of two setup bugs in the test, not because
      headless `xcodebuild` can't serve products; both fixed. All 7 cases now pass under plain
      `xcodebuild` (verified on iOS 18.6 sim, Framepad 17.7.10, FramePhone 26.0.1), so the StoreKit
      adapter (T030) is proven at runtime in CI. See `docs/testing.md`; issue #16 closed.
- [ ] Sandbox on device: products load (id-drift smoke test), real purchase of each unlock,
      tips, cancel mid-flow, Ask-to-Buy with a child test account.
- [ ] Restore on a second device with the same sandbox account (SC-1100-05).
- [ ] Family Sharing: second family member sees unlocks free (SC-1100-08).
- [ ] Apple TV: universal purchase active + native purchase/restore on the TV (spec US4).
- [ ] 24 h offline entitlement soak — piggyback the existing 1000-series soak (SC-1100-04).
- [ ] ≥ 4 h free-tier wall-clock playback with zero purchase UI (SC-1100-02; the XCUITest
      window is only the hermetic proxy).
- [ ] Broker device: pre-gate config survives update-to-gated-build byte-for-byte; no broker
      connection while unentitled (verify at the broker); purchase → resumes with zero re-entry
      (SC-1100-06).
- [ ] ASC sequencing: v1.0 b8 set to never release; version 1.1 (gated) submitted and released
      as the first public version (FR-1100-17 / SC-1100-09). Listing metadata rides along:
      replace the stale "Open source (MIT)" line (license is FSL-1.1-MIT).
- [ ] Prices: set in ASC at submission; per the spec's scope note they are never committed to
      this repository.
