# Contract — Clock Overlay (settings, HA, seams)

**Date**: 2026-07-18. Consumer-visible surfaces of 510; see
[data-model.md](../data-model.md) for type shapes.

## Settings store contract (ThemeKit)

- Keys and raw values per data-model table. Compatibility guarantees:
  - A device that stored any of the four legacy corner raws in `theme.clock.corner`
    reads back the same place after update (no migration step, no data loss).
  - Unknown raws (e.g. a future place synced back from HA) degrade to defaults without
    blocking startup (FR-500-16).
- `ThemeSettingsStore` protocol shape is unchanged — only the `ThemeSettings` payload
  widens. All existing conformers/tests compile after the rename `corner` → `place`
  (mechanical; enforced by the compiler).

## HA/MQTT contract (HAControlKit)

- Discovery: two new select entities (`clock_style`, `clock_size`) using the exact
  existing select-config shape; `clock_corner` keeps id/topics and widens `options` to the
  seven `ClockPlace` raws; display name becomes "Slideshow Clock Place".
- State publish: raw values, as today. Inbound: enum-membership validation, applied via
  the store (FR-710-09 path).
- Retained-state rule (memory: retained MQTT survives reinstall): after this feature,
  a broker retaining `bottomTrailing` on `clock_corner` must re-apply cleanly. A broker
  retaining an unknown option (from a rollback) must be ignored gracefully.

## UITest seams (app target)

| Launch arg | Effect |
|---|---|
| `--uitest-clock` | clock on with defaults (digits · bottomTrailing · room) |
| `--uitest-clock-style=<digits\|pill\|analog>` | style override |
| `--uitest-clock-place=<ClockPlace raw>` | place override (incl. `random`) |
| `--uitest-clock-size=<room\|cozy>` | size override |
| `--uitest-clock-date` | date line on |
| `--uitest-clock-seed=<n>` | seeds the random picker (deterministic place) |

All compose with the existing `--uitest --uitest-slideshow [--uitest-chrome]` seams.

## Accessibility identifiers

- `slideshow.clock` — the ambient clock, a single combined accessibility element. It exists
  while the clock is enabled and the slideshow is playing, and it leaves the accessibility
  tree whenever the chrome is visible (this removal is the vanish signal — SC-500-07).
- The active style is exposed as the element's accessibility **value** (`digits` / `pill` /
  `analog`), so tests assert the style without per-style identifiers.
- The element's frame gives its on-screen place (used for the screen-third assertions).

## Behavioral invariants (test-facing)

1. `slideshow.chrome.*` hittable ⇒ `slideshow.clock` not visible (SC-500-07).
2. Chrome auto-hide (~4.5 s) ⇒ clock visible again without re-launch.
3. Swipe navigation does not reveal chrome and does not hide the clock.
4. Place override maps to the expected screen third (leading/center/trailing × top/bottom)
   within chrome inset bounds (FR-300-33 parity).
5. Relaunch persists style/place/size/date (FR-500-05 path).
