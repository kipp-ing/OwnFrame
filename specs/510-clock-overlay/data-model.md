# Data Model — 510 Clock Overlay Renderer

**Date**: 2026-07-18. All types non-secret, `Sendable`, `Equatable`. Storage stays in
`UserDefaultsThemeStore` (no keychain involvement).

## ThemeKit

### `ClockStyle` (new)

```swift
public enum ClockStyle: String, Sendable, Equatable, CaseIterable {
    case digits   // default — bare rounded numerals on a soft halo
    case pill     // compact glass capsule (today's design language)
    case analog   // round glass face, hour + minute hands, no date line
}
```

### `ClockPlace` (new — supersedes `ClockCorner`)

```swift
public enum ClockPlace: String, Sendable, Equatable, CaseIterable {
    case topLeading      // raw values of the four corners are identical to the
    case topCenter       //   old ClockCorner raws → stored values + HA retained
    case topTrailing     //   states decode unchanged (FR-510-05)
    case bottomLeading
    case bottomCenter
    case bottomTrailing  // default
    case random          // relocates per RandomPlacePicking (FR-510-03)
}
```

`fixedPlaces` helper: `allCases` minus `.random` (the set Random draws from).

### `ClockSize` (new)

```swift
public enum ClockSize: String, Sendable, Equatable, CaseIterable {
    case room   // default — readable from ~1.5 m (SC-500-08 floor)
    case cozy   // arm's-reach placement
}
```

### `ClockSettings` (widened)

```swift
public struct ClockSettings: Sendable, Equatable {
    public var isOn: Bool          // default false        (FR-500-03)
    public var style: ClockStyle   // default .digits
    public var place: ClockPlace   // default .bottomTrailing   (was `corner`)
    public var size: ClockSize     // default .room
    public var showDate: Bool      // default false; digits/pill only (FR-500-17)
    public static let off = ClockSettings()
}
```

State/validation rules:
- Unknown raw in any stored field → that field's default (FR-500-16 pattern), never a
  startup failure.
- `showDate` is persisted independently of style; the **renderer** ignores it for
  `.analog` (no date line) — the setting survives style switches.

### Storage keys (`UserDefaultsThemeStore.Keys`)

| Key | Holds | Notes |
|---|---|---|
| `theme.clock.isOn` | Bool | unchanged |
| `theme.clock.corner` | `ClockPlace` raw | **key name kept**; legacy corner raws are a subset |
| `theme.clock.showDate` | Bool | unchanged |
| `theme.clock.style` | `ClockStyle` raw | new |
| `theme.clock.size` | `ClockSize` raw | new |

### `RandomPlacePicking` (new protocol, ThemeKit `ClockPlacement.swift`)

```swift
public protocol RandomPlacePicking: Sendable {
    /// Returns a new place iff `now` is ≥ cadence past the last relocation,
    /// never `current`, never a member of `occupied`; else returns `current`.
    mutating func place(now: Duration, current: ClockPlace?, occupied: Set<ClockPlace>) -> ClockPlace
}
```

- Production impl: 6-minute cadence, seedable RNG (`RandomNumberGenerator` injected).
- Called only on photo-advance boundaries (FR-510-03); time via `SlideshowClock` monotonic
  now — no wall-clock dependence.
- `occupied` is empty in 510 (research D7); populated by the future ambient-caption work.

### Size constants table (injected into the renderer; host-tested against the floor)

| | Digits Room | Digits Cozy | Analog Ø Room | Analog Ø Cozy |
|---|---|---|---|---|
| iPhone | 92 pt | 64 pt | 210 pt | 150 pt |
| iPad | 76 pt | 52 pt | 250 pt | 180 pt |

Floor test (SC-500-08): Room digits ≥ 74 pt iPhone / ≥ 62 pt iPad (~12 mm).

## HAControlKit

| Entity id | Type | Options / payload | Change |
|---|---|---|---|
| `clock` | switch | on/off | unchanged |
| `clock_corner` | select | `ClockPlace.allCases` raws (7) | **id kept**, options widened; display name → "Slideshow Clock Place" |
| `clock_style` | select | `ClockStyle` raws (3) | new |
| `clock_size` | select | `ClockSize` raws (2) | new |
| `clock_date` | switch | on/off | unchanged |

`ThemeSettingsSnapshot` gains `clockStyle`, `clockSize`; `clockCorner` field renamed
`clockPlace` (wire raw values unchanged). Inbound commands validate enum membership and
apply via `ThemeSettingsStore` (FR-710-09 path, unchanged).

## App target

### `ClockOverlayView` (new)

Inputs: `ClockSettings`, resolved place (post-Random), size-constants table, `chromeVisible`.
- Renders one of three style subviews inside a `TimelineView(.everyMinute)`.
- Materials via existing `glassCard`/`glassPill` compat shims only (FR-510-06).
- `.allowsHitTesting(false)`; opacity 0 whenever `chromeVisible` (0.3 s ease, FR-510-02).
- A11y: container `slideshow.clock`; style child ids `slideshow.clock.digits|pill|analog`.

### `SlideshowView` (touched)

- Ambient-layer slot (sibling of chrome, research D8); passes photo-advance events to the
  place picker when `place == .random`.
- New launch seams: `--uitest-clock`, `--uitest-clock-style/place/size=<raw>`,
  `--uitest-clock-date`, `--uitest-clock-seed=<n>`.

### `SlideshowSettingsView` (touched)

Display section rows (FR-500-13): Clock (toggle) · Clock style · Clock place · Clock size ·
Date line (toggle, disabled-looking hint when style is Analog is NOT required — setting
stays enabled and persists; renderer ignores it for analog).

### `SlideshowRemoteControlAdapter` (touched)

Raw-value bridges for the widened fields, same both-directions mapping pattern as today.
