# Phase 0 Research — Purchase Gate & One-Time Unlocks (1100)

No open NEEDS CLARIFICATION markers existed in the spec; this document records the technology
and design decisions with rationale and rejected alternatives.

## R1 — StoreKit 2, not original StoreKit

**Decision**: StoreKit 2 exclusively (`Product`, `Product.PurchaseResult`,
`Transaction.currentEntitlements`, `Transaction.updates`, `AppStore.sync()` for restore).

**Rationale**: The deployment floor is iOS/tvOS 17 — StoreKit 2 is fully available and is the
current API. It gives async/await purchase flows, on-device JWS transaction verification
(`VerificationResult`), a queryable local entitlement set that works offline, revocation info
(`revocationDate`), and first-class Ask-to-Buy (`.pending`) — each mapping directly to an FR.

**Alternatives considered**: SK1 (`SKPaymentQueue`) — legacy, receipt-parsing burden, nothing
the floor requires; hybrid — pointless complexity.

## R2 — Product topology

**Decision**: Five to six products, ids prefixed `ing.kipp.Immich-Slideshow.`:

| Product id suffix | Type | Family Sharing |
|---|---|---|
| `unlock.pro` | Non-consumable | ON |
| `unlock.automation` | Non-consumable | ON |
| `unlock.everything` | Non-consumable (grants both tiers) | ON |
| `tip.small` / `tip.medium` / `tip.large` | Consumable | n/a (consumables can't share) |

**Rationale**: Non-consumables are the only StoreKit type matching "one-time, permanent,
restorable, family-shareable" (FR-1100-05/06/11). The bundle is its own non-consumable; StoreKit
cannot price it dynamically against part-ownership, so the client hides it once any single
unlock is owned (FR-1100-04). Tips are consumables so they can be bought repeatedly.

**Alternatives considered**: Single everything-SKU only — rejected by spec (two tiers serve two
audiences); non-renewing subscriptions — prohibited by FR-1100-05 and wrong semantics.

## R3 — Offline entitlements: layered cache, cache-first launch

**Decision**: Two layers. (1) `EntitlementSnapshotCache` in UserDefaults — written after every
successful resolve; read *synchronously* at launch to activate owned features instantly.
(2) Async refresh from `Transaction.currentEntitlements` whenever the app runs, plus a
long-lived `Transaction.updates` listener (purchases, Ask-to-Buy approvals, revocations).
Refresh **failure or unavailability never downgrades** the cached snapshot; only a successful
resolve may change it (that is when revocations take effect — FR-1100-12).

**Rationale**: FR-1100-10 demands unbounded offline operation with zero network re-validation.
StoreKit 2's local store usually answers offline, but its guarantees around cold starts,
re-installs awaiting `AppStore.sync()`, and storage pressure are not contractual — the frame
must not depend on them. A last-known-good snapshot that only moves on positive signal is the
unattended-frame-safe construction, mirroring the resilience stance of 310.

**Alternatives considered**: Rely solely on `currentEntitlements` — rejected (non-contractual
offline behavior; async at launch). Server-side receipt validation — rejected outright (the app
runs no server; violates the product's no-cloud story).

## R4 — Cache location: UserDefaults, tamper-accepted

**Decision**: The entitlement snapshot lives in UserDefaults (injected suite for testability).

**Rationale**: Entitlements are not secrets — constitution III scopes the keychain to API keys,
MQTT credentials, and shared-link passwords, and adding non-secret state to the keychain buys
nothing: the source is public (Fair Source), so any client-side lock can be compiled away
regardless of where the flag sits. The declared copy-protection model (research 2026-07-18) is
goodwill + fair one-time pricing; self-builders were never customers. Live refreshes still go
through StoreKit 2's JWS verification, so casual plist edits are corrected on the next
successful resolve.

**Alternatives considered**: Keychain — misuse of the secrets store, adds migration/sync
complexity for zero real protection; obfuscation/attestation — hostile to the open-source trust
story and explicitly rejected by the monetization research.

## R5 — Gate placement: point of effect, in app targets; settings are data

**Decision**: Nothing gates on *setting* a value; everything gates where the value takes
*effect*, and only in app-target wiring:

- Ken Burns: `effectiveKenBurns = theme.kenBurns && entitlements.contains(.pro)` computed where
  `SlideshowView`/`TVSlideshowView` apply `KenBurnsMotionModifier`.
- Clock: `ClockOverlayView` participates only when `clock enabled && .pro`.
- HA/MQTT: the `HAControlCoordinator` is never started without `.automation`
  (`SlideshowRemoteControlAdapter` / `TVRemoteControlAdapter` wiring); broker config and
  keychain credentials untouched (FR-1100-14).
- App Intents: each intent's `perform()` checks `.automation` and throws a localized
  "requires the Automation unlock" error (FR-1100-03); intents stay visible in Shortcuts.

**Rationale**: One rule resolves every cross-cutting case identically — pre-gate configs,
HA-pushed values (an Automation-only owner flipping the Ken Burns select via MQTT), retained
broker state re-applied after reinstall (known behavior), ConfigSync payloads from an entitled
iPad to an unentitled Apple TV, and post-revocation state. Settings survive byte-for-byte;
effects require entitlement. Corollary for HA state topics: they report the **stored** settings
values (data), not effective rendering — an Automation-only owner who sets the Ken Burns select
sees the stored value echoed back while rendering stays Pro-gated; HA reflects configuration,
the frame's screen reflects entitlement. It also keeps SlideshowKit/ThemeKit/HAControlKit policy-free
(constitution II): packages provide mechanism, the app applies policy.

**Alternatives considered**: Gating the settings writes — rejected: creates divergent state
across HA/sync/defaults, breaks FR-1100-14's "zero re-entry", reads as nickel-and-diming.
Gating inside the packages — rejected: leaks purchase policy into mechanism kits and forces
PurchaseKit as a dependency of everything.

## R6 — Unentitled HA semantics on the broker side

**Decision**: When unentitled, the app simply never connects. No discovery unpublish, no
config-topic cleanup. The broker's retained LWT shows the frame `offline`; retained discovery
entities appear unavailable in HA.

**Rationale**: Matches the spec's edge case ("acceptable: entities go unavailable via LWT").
Any active cleanup would require connecting — which FR-1100-03 forbids — and destroying retained
config would violate the no-data-loss stance if the user later purchases.

## R7 — Unlock screen: live demo, no trial mechanics

**Decision**: The Pro unlock screen embeds a live Ken Burns demo — `KenBurnsMotionModifier`
looping over the current photo when a source is configured, else a bundled neutral sample
image — plus a static clock-style preview row. No time-limited trials anywhere (FR-1100-05);
a demo confined to the unlock screen is presentation, not access.

**Rationale**: Motion is the pack's selling point and must be *seen* (FR-1100-09 "what do I
get"). Reusing the real modifier guarantees the demo shows the actual shipped quality (the
micro-judder work) with no duplicate implementation.

## R8 — Test strategy (three layers + device day)

**Decision**:

1. **Host/simulator Swift Testing** (`PurchaseKitTests` + existing app-adjacent suites):
   `EntitlementResolver` (bundle→both, revocation exclusion), `EntitlementStore` (cache-first
   launch, refresh-never-downgrades-on-failure, updates-stream application), snapshot cache
   round-trip, `PurchaseViewModel` states incl. store-unreachable, effective-flag gating,
   ConfigSync payload contains no entitlement keys. All against `StoreClient` fakes.
2. **StoreKitTest adapter tests** (XCTest, permitted by constitution as "only where strictly
   necessary" — `SKTestSession` requires the Xcode test environment): purchase, restore,
   refund/revocation, Ask-to-Buy deferral, interrupted-purchase recovery against a `.storekit`
   configuration file; run via XcodeBuildMCP `test_sim`.
3. **XCUITest** with launch seams (contracts/uitest-seams.md): locked rows dimmed+badged+
   tappable, unlock screen contents, no purchase UI during playback, tip jar reachable only via
   settings, broker settings visible-but-locked with values preserved.
4. **Device/ASC day** (quickstart.md checklist): real sandbox purchase, Family Sharing,
   universal purchase on the physical Apple TV, 24 h offline entitlement soak (piggybacks the
   existing soak), ASC product setup, b8-never-released verification.

**Rationale**: Mirrors the repo's established pyramid; keeps the non-hermetic surface (real
StoreKit) down to a thin adapter plus explicit device gates.

## R9 — tvOS specifics

**Decision**: `PurchaseKit` compiles for tvOS; purchase/restore run natively on the TV with
StoreKit 2's system UI; the TV settings surface gets the same locked rows and an unlock entry.
Universal purchase needs no work — both targets already share `ing.kipp.Immich-Slideshow`.
Entitlements resolve independently per device from the store account; `ConfigSyncKit` is
explicitly out of the entitlement path (spec edge case), enforced by test.

**Alternatives considered**: "Purchase on iPhone, unlock TV via ConfigSync" — rejected:
side-channel entitlement transport is the exact anti-pattern the spec prohibits; universal
purchase + Family Sharing already cover the household story.

## R10 — Release sequencing mechanics

**Decision**: The gated build ships as **version 1.1** (a new ASC version; the approved v1.0
b8 remains forever "Pending Developer Release" / superseded and is never released). Manual ASC
work — creating the IAPs, Family Sharing toggle, localized display names/descriptions ("one-time
purchase" phrasing, never "lifetime"), review notes, and the ASC listing's stale "Open source
(MIT)" line riding along — is captured as checklist items in quickstart.md, not code tasks.
Price points are entered in ASC only, per the spec's scope note.

**Rationale**: ASC does not allow adding builds to an approved version; a new version number is
the clean vehicle and satisfies FR-1100-17 verifiably (SC-1100-09 audits release history).
