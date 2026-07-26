# Phase 1 Data Model — HA Full Control

Swift sketches are indicative (final names/signatures land via TDD). All new value types are
`Sendable` and `Equatable`.

## HAEntity (extended)

```swift
public enum HAEntity: String, CaseIterable, Sendable {
    // existing (unchanged topics/payloads — FR-710-08)
    case playback, brightness, album
    // settings (FR-710-01)
    case order, duration, transition, kenBurns = "ken_burns", fit, quality
    case clock, clockCorner = "clock_corner", clockDate = "clock_date"
    // navigation (FR-710-04)
    case next, previous
    // photo (FR-710-05/06)
    case currentPhoto = "current_photo"
    case currentPhotoImage = "current_photo_image"   // topic suffix differs, see contracts
    // diagnostics (FR-710-07)
    case phase, photoCount = "photo_count", version
    case frameStatus = "frame_status"   // running|inactive, explicit UI-visibility signal (FR-710-24, 2026-07-26)
}
```

`rawValue` is the topic segment and the stable `unique_id` suffix (FR-710-18) — existing three
cases keep their current raw values unchanged.

## PhotoReport

One snapshot of "what's on the frame right now," produced by the adapter on every photo change
and consumed by `HAControlCoordinator` to drive the image + `current_photo` sensor publish.

```swift
public struct PhotoReport: Sendable, Equatable {
    public var assetID: String?          // nil when phase is .empty/.failed/.loading
    public var imageData: Data?          // capped/downscaled bytes; nil if disabled or over cap
    public var takenAt: Date?
    public var city: String?
    public var state: String?
    public var country: String?
    public var albumID: String?
    public var albumName: String?
    public var phase: SlideshowPhaseReport   // mirrors SlideshowKit.SlideshowPhase, no HAControlKit
                                              // dependency on SlideshowKit (Modular Isolation)
    public var photoCount: Int
}

public enum SlideshowPhaseReport: String, Sendable, Equatable {
    case loading, playing, empty, failed
}
```

State transitions: mirrors `SlideshowViewModel.phase`. When `phase != .playing`, `assetID` /
`imageData` / metadata fields MUST be `nil` so the coordinator publishes the cleared/"unknown"
state (edge case: "Retained stale state", User Story 4 acceptance scenario 3).

Validation: `imageData` is only ever non-nil when `HAPublishOptions.imageEnabled` is true AND the
downscaled payload is at or under `byteCap`; otherwise nil (FR-710-14/15 — skip, not a broker
disconnect).

## HAPublishOptions

```swift
public struct HAPublishOptions: Sendable, Equatable {
    public var imageEnabled: Bool         // default false — FR-710-15
    public var imageSource: ImageSource   // default .thumbnail — FR-710-14
    public var byteCap: Int               // default 512_000 — FR-710-14

    public enum ImageSource: String, Sendable, Equatable, CaseIterable {
        case thumbnail, preview
    }
}

public protocol HAPublishOptionsStore: Sendable {
    var options: HAPublishOptions { get set }
}
```

- `UserDefaultsHAPublishOptionsStore`: JSON under a dedicated non-secret key, alongside
  `BrokerConfigStore` in `HAControlKit`. Never touches Keychain (research.md §3).
- In-memory fake for tests, mirroring `ThemeKitTestSupport.InMemoryThemeStore`.

## MetadataCache

Bounded LRU keyed by asset ID, same shape as `SlideshowKit.ImageCache` (`NSLock` + dictionary +
recency list), storing the `AssetInfo`-derived fields needed for a `PhotoReport` so revisiting a
photo (previous/shuffle cycle) does not re-fetch `assetInfo` (FR-710-22, bounded per the
Clarifications).

```swift
public final class MetadataCache: @unchecked Sendable {
    public init(limit: Int)                                  // small LRU cap, e.g. tens of entries
    public func metadata(for assetID: String) -> CachedMetadata?
    public func store(_ metadata: CachedMetadata, for assetID: String)
}

public struct CachedMetadata: Sendable, Equatable {
    public var takenAt: Date?
    public var city: String?
    public var state: String?
    public var country: String?
}
```

A fetch failure is NOT cached (so a transient network blip is retried on the next visit to that
asset, rather than permanently publishing empty attributes for the rest of the session).

## Protocol split (RemoteControlling → three protocols)

See research.md §1 for rationale.

```swift
@MainActor
public protocol PlaybackControlling: AnyObject {
    // unchanged from today's RemoteControlling
    var playbackState: PlaybackState { get }
    var brightness: Double { get }
    var albumOptions: [String] { get }
    var currentAlbum: String? { get }
    func pause()
    func resume()
    func setBrightness(_ value: Double) async
    func selectAlbum(_ name: String)
    var onLocalChange: (@MainActor () -> Void)? { get set }
}

@MainActor
public protocol SettingsControlling: AnyObject {
    var themeSettings: ThemeSettingsSnapshot { get }        // HAControlKit-local mirror, see below
    func apply(_ settings: ThemeSettingsSnapshot)           // validated by the coordinator first
    var onSettingsChange: (@MainActor () -> Void)? { get set }
}

@MainActor
public protocol PhotoReporting: AnyObject {
    var currentPhotoReport: PhotoReport { get }
    func showNext() async
    func showPrevious() async
    var onPhotoChange: (@MainActor (PhotoReport) -> Void)? { get set }
}
```

`ThemeSettingsSnapshot` is a `HAControlKit`-local struct with the same 9 fields as
`ThemeKit.ThemeSettings` (Modular Isolation forbids `HAControlKit` importing `ThemeKit`); the
adapter converts both directions. `SlideshowRemoteControlAdapter` implements all three protocols
plus the existing playback contract; `HAControlCoordinator` takes three separate dependencies
instead of one `RemoteControlling`.

## Command validation matrix (drives the generic apply/echo path)

| HA type | validation rule | on violation |
|---------|------------------|---------------|
| select  | payload ∈ the entity's enum raw values | ignore, re-echo actual value |
| number (`duration`) | integer, 3 ≤ v ≤ 600 | ignore, re-echo actual value |
| switch  | payload ∈ {`ON`, `OFF`} | ignore, re-echo actual value |
| button (`next`/`previous`) | payload == `PRESS` | ignore |

One generic `applySetting(entity:payload:)` in `HAControlCoordinator` looks up the rule for the
entity, validates, applies via `SettingsControlling.apply(_:)` if valid, and always echoes —
replacing the current per-entity `switch` in `handleIncoming` for the 9 settings entities (the 3
existing playback-family entities keep their existing per-entity handling unchanged).
