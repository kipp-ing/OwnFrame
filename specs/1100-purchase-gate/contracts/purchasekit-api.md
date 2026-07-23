# Contract — PurchaseKit public API (1100)

The seams tasks and tests program against. Shapes may gain parameters; semantics below are
binding. Types referenced here are defined in [../data-model.md](../data-model.md).

## StoreClient (protocol — the only StoreKit touchpoint)

```swift
public protocol StoreClient: Sendable {
    /// Localized, ready-to-display products for the given ids.
    /// Throws when the store is unreachable (drives PurchasePhase.unavailable).
    func products(for ids: [ProductID]) async throws -> [DisplayProduct]

    /// Initiates purchase. `.pending` = Ask to Buy deferral (not an error).
    func purchase(_ id: ProductID) async throws -> PurchaseOutcome   // success | pending | cancelled

    /// Triggers the platform restore (AppStore.sync()); caller refreshes afterwards.
    func restore() async throws

    /// Current verified ownership. Must answer from local state when offline if the
    /// platform allows; a throw means "unknown", never "nothing owned".
    func ownedTransactions() async throws -> [OwnedTransaction]

    /// Long-lived stream of ownership changes (new purchases, Ask-to-Buy approvals,
    /// revocations). Elements are the *reason* to re-query ownedTransactions.
    var updates: AsyncStream<Void> { get }
}
```

Binding semantics:
- Only **verified** transactions are surfaced; JWS-unverified ones are dropped inside the
  adapter (never partially trusted).
- Consumable tips complete with `.success` but never appear in `ownedTransactions`.
- The adapter must `finish()` transactions after the store model has persisted the resulting
  snapshot (interrupted-purchase safety, FR-1100-15).

## EntitlementStore (observable model)

Contract points (full state machine in data-model.md):
- `current` is synchronously seeded from the snapshot cache at init — callers may branch on it
  in the first render pass with no await (FR-1100-10).
- Failed or offline refreshes never shrink `current` (last-known-good).
- A successful resolve is the only shrink path (revocation, FR-1100-12).
- `restore()` = platform sync + refresh; idempotent (FR-1100-11).

## Entitlement gating helpers (app-target usage)

There is exactly one entitlement (the Supporter Unlock), so every gate is the same check:

```swift
entitlements.contains(.supporter)    // Ken Burns effective flag, clock participation,
                                     // coordinator start, intent guards
```

- Intent guard failure message (localized key `unlock.required.supporter`):
  "Remote control requires the Supporter Unlock." — thrown as a user-visible intent error,
  never a silent no-op (spec US5, scenario 4). Intents stay listed in Shortcuts.

## Locked-row / unlock-screen UI contract (FR-1100-09)

- `LockedRow` renders the wrapped row dimmed **and** badged (lock glyph + "Supporter" badge) and
  stays tappable; tap presents the single `UnlockScreenView`.
- `UnlockScreenView` sections, in order: what-you-get list (with a live Ken Burns demo slot),
  price + purchase button (or the `unavailable` notice), Restore Purchases. There is one unlock
  screen — the Supporter Unlock — reached from any locked row.
- No view in PurchaseKit may auto-present. Presentation is always user-initiated from a
  locked row, the Unlocks settings section, or onboarding's settings surface — never from
  playback (SC-1100-02).

## Product identifiers (must match ASC exactly)

See ProductCatalog in data-model.md. Any drift between `ProductID` raw values and ASC breaks
purchases at runtime with no compile-time signal — the quickstart device checklist includes a
products-load smoke test against sandbox for exactly this reason.
