# Contract — UI-test launch seams & accessibility identifiers (1100)

Follows the repo's established hermetic `--uitest-*` pattern (no MCP tap tools; XCUITest
drives everything through launch arguments; see memory `uitest-launch-seams`).

## Launch arguments

| Argument | Effect |
|---|---|
| `--uitest-entitlements=<list>` | Seeds a stub `EntitlementStore` with the given set. `<list>` ∈ `none`, `supporter`, `all` — `supporter` and `all` are equivalent (there is one unlock). `pro`/`automation` were removed 2026-07-23 and are no longer parsed; unrecognised words are ignored (a typo degrades to "free"). Bypasses StoreKit entirely. |
| `--uitest-store=stub` | `StoreClient` stub: canned products with fixed display prices, purchases succeed instantly (entitlement applied via the normal store path). |
| `--uitest-store=unavailable` | `StoreClient` stub whose `products(for:)` throws → drives the `unavailable` unlock-screen state (FR-1100-16). |
| `--uitest-store=pending` | Purchases return `.pending` → drives the Ask-to-Buy UI state (FR-1100-15). |

Seams compose with the existing `--uitest` stub-slideshow seams (clock/Ken Burns scenarios run
against the stub source, hermetic, no server).

## Accessibility identifiers

| Identifier | Element |
|---|---|
| `settings.row.kenburns.locked` | Ken Burns locked row (dimmed + badge, tappable) |
| `settings.row.clock.locked` | Clock locked row |
| `settings.row.broker.locked` | Broker/remote-control locked banner row |
| `settings.section.unlocks` | Unlocks section header in settings |
| `unlock.screen.supporter` | The single unlock screen |
| `unlock.demo.kenburns` | Live Ken Burns demo slot on the unlock screen |
| `unlock.price.supporter` | Price label |
| `unlock.buy.supporter` | Purchase button |
| `unlock.restore` | Restore Purchases action |
| `unlock.unavailable` | Store-unreachable notice |
| `unlock.pending` | Ask-to-Buy pending notice |
| `settings.tipjar` | Tip jar row (settings only) |
| `tipjar.thanks` | Post-tip thank-you state |

## Binding UI-test assertions (map to SC/FRs)

1. `none`: locked rows exist, are hittable, and open their unlock screen (FR-1100-09 — the
   dimmed-but-tappable rule is what this proves).
2. `none` + stub playback for a sustained window: no element with an `unlock.` prefix ever
   appears without a tap (SC-1100-02 hermetic proxy; the 4 h wall-clock run is a device item).
3. `none`: tapping any locked row (Ken Burns, clock, or the broker control banner) opens the same
   `unlock.screen.supporter` — there is never a second product or screen to choose (FR-1100-04).
   Under `supporter`/`all` those same rows are unlocked and the screen is unreachable — partial
   ownership cannot occur, so there is no per-tier visibility state left to exercise.
   (`unlock.price.supporter` / `unlock.buy.supporter` exist on that screen but are not
   independently asserted by any XCUITest today — `ProductID.uiSlug` itself is untested.)
4. `all` (== `supporter`): no locked rows, no `unlock.` entry points except Restore + tips in
   settings.
5. `--uitest-store=unavailable`: unlock screen shows `unlock.unavailable`, zero price labels
   (FR-1100-16).
6. Broker settings under `none` with seeded config: fields show stored values (masked as
   usual), locked banner present, nothing cleared (FR-1100-14 / SC-1100-06 UI leg).
7. tvOS variants of 1, 3, 4 on the TV target's settings surface — NOT via XCUITest (decision
   2026-07-19: no TV UI-test target in this feature; the tvOS harness stays a 1000 leftover).
   Verified instead by host tests of the TV wiring + `snapshot_ui`/screenshot review on the
   Apple TV simulator under the same launch seams + the device-day checklist.
