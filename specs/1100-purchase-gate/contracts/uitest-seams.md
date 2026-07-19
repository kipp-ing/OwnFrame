# Contract — UI-test launch seams & accessibility identifiers (1100)

Follows the repo's established hermetic `--uitest-*` pattern (no MCP tap tools; XCUITest
drives everything through launch arguments; see memory `uitest-launch-seams`).

## Launch arguments

| Argument | Effect |
|---|---|
| `--uitest-entitlements=<list>` | Seeds a stub `EntitlementStore` with the given set. `<list>` ∈ `none`, `pro`, `automation`, `all` (comma-separated combos allowed). Bypasses StoreKit entirely. |
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
| `unlock.screen.pro` / `unlock.screen.automation` | Unlock screens |
| `unlock.demo.kenburns` | Live demo slot on the Pro screen |
| `unlock.price.<pro|automation|everything>` | Price labels |
| `unlock.buy.<pro|automation|everything>` | Purchase buttons |
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
3. `pro` (only): Ken Burns/clock rows unlocked; broker row still locked; Automation unlock
   screen offers only Automation (FR-1100-04 visibility rule with part-ownership).
4. `all`: no locked rows, no `unlock.` entry points except Restore + tips in settings.
5. `--uitest-store=unavailable`: unlock screen shows `unlock.unavailable`, zero price labels
   (FR-1100-16).
6. Broker settings under `none` with seeded config: fields show stored values (masked as
   usual), locked banner present, nothing cleared (FR-1100-14 / SC-1100-06 UI leg).
7. tvOS variants of 1, 3, 4 on the TV target's settings surface — NOT via XCUITest (decision
   2026-07-19: no TV UI-test target in this feature; the tvOS harness stays a 1000 leftover).
   Verified instead by host tests of the TV wiring + `snapshot_ui`/screenshot review on the
   Apple TV simulator under the same launch seams + the device-day checklist.
