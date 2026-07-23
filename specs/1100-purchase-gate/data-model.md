# Phase 1 Data Model — Purchase Gate & One-Time Unlocks (1100)

All types live in `PurchaseKit` unless noted. Names are contracts for tasks/tests; exact
access levels and conformances are implementation detail.

## Entitlement

> **Amended 2026-07-23 (single unlock).** The two tiers (`.pro`, `.automation`) and the
> everything-bundle were collapsed into one purchase, the **Supporter Unlock**, which grants
> every gated capability at once (spec.md FR-1100-02/04, amended 2026-07-22). The entitlement
> enum now holds one case; there is no bundle and no partial ownership.

```
Entitlement: enum { supporter }              // CaseIterable, Sendable, Codable, RawRepresentable<String>
EntitlementSet: Set<Entitlement>             // convenience: .none, .all == [.supporter], contains(_:)
```

- Derived, never stored per-feature: every gated feature asks `contains(.supporter)` at its
  point of effect.
- There is exactly one entitlement, granted by the single Supporter Unlock product. No tiers,
  no bundle — `EntitlementSet.all == [.supporter]` (FR-1100-02/04).

## ProductID / ProductCatalog

```
ProductID: enum, RawRepresentable<String> {
  supporter  = "ing.kipp.Immich-Slideshow.unlock.supporter"
  tipSmall   = "ing.kipp.Immich-Slideshow.tip.small"
  tipMedium  = "ing.kipp.Immich-Slideshow.tip.medium"
  tipLarge   = "ing.kipp.Immich-Slideshow.tip.large"
}
ProductCatalog:
  unlocks: [supporter]
  tips:    [tipSmall, tipMedium, tipLarge]
  grants(_ id: ProductID) -> EntitlementSet   // supporter→{supporter} (== .all), tips→{}
```

- Single source of truth for id strings and the entitlement mapping; ASC must be configured to
  match (checklist). Validation rule: unknown ids resolve to `{}` and are ignored, never fatal
  (forward compatibility with future SKUs).

## OwnedTransaction (adapter output)

```
OwnedTransaction: { productID: String, isRevoked: Bool }
```

- The `StoreClient` adapter reduces verified StoreKit transactions to this minimal shape so
  the resolver stays pure and host-testable. Unverified (failed JWS) transactions are dropped
  by the adapter and never reach the resolver.

## EntitlementResolver (pure function)

```
resolve([OwnedTransaction]) -> EntitlementSet
```

Rules (each is a test):
1. Non-revoked owned product → union of `ProductCatalog.grants`.
2. `isRevoked == true` contributes nothing (FR-1100-12).
3. Tips contribute nothing (FR-1100-08).
4. Unknown product ids contribute nothing.
5. Empty input → `{}`.

## EntitlementSnapshot (persisted)

```
EntitlementSnapshot: Codable { entitlements: EntitlementSet, savedAt: Date }
```

- Persisted by `EntitlementSnapshotCache` into an injected `UserDefaults` suite under a single
  versioned key (`purchase.entitlements.v1`).
- `savedAt` is diagnostic only — **the snapshot never expires** (FR-1100-10: unbounded offline).
- State transitions: written after every *successful* resolve (purchase, restore, refresh,
  update event). Never written on failure; never cleared except by successful resolve to a
  smaller set (revocation) — uninstall clears it naturally, restore repopulates (FR-1100-11).

## EntitlementStore (@Observable, app-wide)

```
EntitlementStore:
  current: EntitlementSet                     // synchronously cache-seeded at init
  init(client: StoreClient, cache: EntitlementSnapshotCache)
  func refresh() async                        // resolve currentEntitlements; on success → apply + persist
  func listenForUpdates()                     // Transaction.updates → apply + persist
  func restore() async throws                 // AppStore.sync() then refresh()
```

States and transitions:
- **Launch**: `current = cache.load()?.entitlements ?? []` (no await, FR-1100-10).
- **Refresh success** → `current = resolved`; persist. This is the only path that can shrink
  the set (revocation takes effect here — FR-1100-12 "next entitlement refresh").
- **Refresh failure / offline** → `current` unchanged (last-known-good).
- **Update event** (purchase completed elsewhere, Ask-to-Buy approved, revocation pushed) →
  re-resolve and persist (FR-1100-15).

## PurchaseViewModel (unlock screen)

```
PurchasePhase: enum { loading, ready([DisplayProduct]), unavailable,     // store unreachable
                      purchasing(ProductID), pending(ProductID),         // Ask to Buy
                      completed(EntitlementSet), failed(message) }
DisplayProduct: { id: ProductID, displayName, displayPrice }             // localized from store
```

Rules (each is a test):
- Offer computation (FR-1100-04): owns nothing → [supporter]; owns the Supporter Unlock →
  screen shows the "owned" state, no products. There is exactly one product, so partial
  ownership cannot occur and the screen never presents a choice between products.
- `unavailable` shows no prices and no placeholder values (FR-1100-16).
- `pending` is terminal for the session; entitlement arrives later via the updates stream.
- **Cancel** returns to `ready` — the user chose to stop, so there is nothing to explain
  (FR-1100-15).
- **Failure** surfaces `failed(message)` so the user learns *why* the purchase did not complete.
  Amended 2026-07-19: this rule previously read "Cancel/failure returns to `ready`", which
  contradicted the `failed(message)` case in the enum above and would have left it dead. The
  distinction is deliberate — cancel is a choice, failure is an error — and both remain passive:
  FR-1100-15 forbids a follow-up *prompt*, not an explanation the user can read and dismiss.

## Gated feature mapping (app targets, not persisted)

| Feature | Requires | Point of effect |
|---|---|---|
| Ken Burns motion | `.supporter` | `SlideshowView` / `TVSlideshowView` — `effectiveKenBurns` |
| Clock overlay | `.supporter` | `SlideshowView` clock branch (`ClockOverlayView` participation) |
| HA/MQTT remote control | `.supporter` | coordinator start in `SlideshowRemoteControlAdapter` / `TVRemoteControlAdapter` |
| App Intents | `.supporter` | each intent `perform()` guard |

Invariants:
- `ThemeSettings`, `ClockSettings`, broker config, and keychain items are **never** read,
  written, masked, or migrated by PurchaseKit (FR-1100-14).
- Entitlement types never appear in `ConfigSyncKit` payload models (negative test).

## Relationships

```
StoreKit 2 ──(verified txns)──> StoreKitClient ──[OwnedTransaction]──> EntitlementResolver
                                                                            │ EntitlementSet
              EntitlementSnapshotCache <──persist/seed──> EntitlementStore ─┘
                                                              │ @Observable
                     app targets: effective flags, coordinator gate, intent guards,
                     locked rows, unlock screens (PurchaseViewModel)
```
