# Phase 0 Research: Home Assistant Full Control (MQTT)

All items below were RESOLVED before this feature was specified (numbering, image retention,
cache bound, metadata retention — see spec.md's Clarifications and Open Questions). This phase
resolves the 3 remaining plan-stage decisions.

## 1. Protocol split of `RemoteControlling`

**Decision**: Split into three focused protocols, all implemented by
`SlideshowRemoteControlAdapter`:

- `PlaybackControlling` — today's `RemoteControlling` unchanged: `playbackState`, `brightness`,
  `albumOptions`, `currentAlbum`, `pause()`, `resume()`, `setBrightness(_:)`, `selectAlbum(_:)`,
  `onLocalChange`.
- `SettingsControlling` — `settings: ThemeSettings { get }`, `apply(_ settings: ThemeSettings)`
  (validates + writes through `ThemeSettingsStore`), `onLocalChange` (shared callback contract,
  see below).
- `PhotoReporting` — `currentPhotoReport: PhotoReport? { get }`, `showNext()`, `showPrevious()`,
  `onPhotoChange: (@MainActor (PhotoReport) -> Void)?`.

**Rationale**: `HAControlCoordinator` already only depends on the shape it needs (per FR-710-19);
one giant `RemoteControlling` would force every fake in every test to implement 20+ members even
when a test only exercises settings or only photo reporting. Three protocols keep
`HAControlCoordinatorTests`'s existing fakes small and let new fakes be added independently
(matches how `Fakes.swift` is already organized per concern).

**Alternatives considered**: One grown `RemoteControlling` with ~25 members — rejected, makes
every existing and new fake implement the full surface and makes it harder to see which
coordinator code path depends on which capability.

## 2. `current_photo` payload shape

**Decision**: A single JSON payload on one topic
(`immichslideshow/<deviceID>/current_photo/state`, NOT retained per the Clarifications).
Discovery for the `sensor` sets `state_topic` and `json_attributes_topic` to that same topic:
`value_template: "{{ value_json.id }}"` extracts the state (asset ID), and the whole payload is
also read as the attributes object (`taken_at`, `city`, `state`, `country`, `album_id`,
`album_name`, plus `id` again — HA ignores the extra key).

**Rationale**: One publish per photo change instead of two; HA's MQTT sensor explicitly supports
`state_topic` and `json_attributes_topic` pointing at the same topic. Matches the spec's own
"simplest" proposal.

**Alternatives considered**: Separate `json_attributes_topic` — rejected, doubles the publish
count for no behavioral difference and complicates the loop-safety/echo bookkeeping for no
benefit (this topic is never a command target).

## 3. Image-publishing enable flag / byte cap: where it lives

**Decision**: A new non-secret `HAPublishOptions` value type (`imageEnabled: Bool = false`,
`imageSource: .thumbnail`, `byteCap: Int = 512_000`) with an `HAPublishOptionsStore` protocol,
UserDefaults-backed implementation, living in `HAControlKit` next to `BrokerConfigStore`. The
toggle is surfaced as a new control in the existing `BrokerSetupView.swift` Settings screen
(alongside host/port/username/password), not in `ThemeKit`/`SlideshowSettingsView`.

**Rationale**: This is a transport/publishing concern, not a display concern — it governs what
leaves the device over MQTT, which is exactly `BrokerSetupView`'s existing job (topic 600). It
must NOT live in the Keychain-backed `BrokerSettings` (host/port/username/password) since it
isn't a secret; mirroring `ThemeKit`'s `ThemeSettingsStore`/`UserDefaultsThemeStore` split (a
protocol + a plain UserDefaults implementation + an in-memory test fake) is the established idiom
in this codebase for exactly this kind of small, non-secret, live-observed preference.

**Alternatives considered**: Folding it into `ThemeSettings`/`ThemeSettingsStore` (topic 500) —
rejected, `ThemeSettings` governs slideshow display, not what gets published to a broker; would
blur topic 500's boundary. Hardcoding it as a coordinator constructor parameter like today's
`enabledEntities` — rejected, FR-710-15 requires the user to actually toggle it, not just a
developer-set default at the call site.

## Existing surfaces this feature reuses unchanged

Confirmed by reading the current code (not assumptions):

- `ThemeSettings` (`Packages/ThemeKit/Sources/ThemeKit/ThemeSettings.swift`) already has exactly
  the 9 fields and enum raw values the Entity Map needs, including `durationRange` (3–600s) and
  `ClockSettings`.
- `SlideshowViewModel` (`Packages/SlideshowKit/Sources/SlideshowKit/SlideshowViewModel.swift`)
  already exposes `phase`, `currentAssetID`, `showNext()`, `showPrevious()`, `switchAlbum(_:)`
  with the works-while-paused/timer-reset semantics FR-710-04 requires.
- `ImmichAPI` (`Packages/ImmichClient/Sources/ImmichClient/ImmichAPI.swift`) already has
  `assetInfo(assetID:) async throws -> AssetInfo` (id/takenAt/city/state/country) and
  `thumbnail(assetID:) async throws -> Data` — the exact calls FR-710-05/06/14 need. No
  `ImmichClient` changes required.
- `SlideshowKit.ImageCache` (`Packages/SlideshowKit/Sources/SlideshowKit/ImageCache.swift`) is a
  small, lock-protected, size-bounded LRU (`NSLock` + `[String: Data]` + recency list) — the exact
  shape to mirror for the new metadata cache (FR-710-22, bounded per the Clarifications).
- `PhotoInfoView.swift` (app target) already calls `assetInfo(assetID:)` for the in-app info
  overlay, uncached (fetched fresh each time the panel opens) — confirms the API shape but is a
  separate, UI-triggered call site; the new metadata cache is dedicated to HA reporting (pushed on
  every photo change, not just when the info panel is open) and is not shared with it.
