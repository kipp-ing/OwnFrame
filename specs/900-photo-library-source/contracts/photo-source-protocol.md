# Contracts — PhotoSourceKit / PhotoLibraryKit / consumer deltas

The load-bearing public API. Signatures are the contract; bodies are implementation.

## PhotoSourceKit (new package, Foundation-only)

```swift
public protocol PhotoSourceProviding: Sendable {
    /// Precondition gate (R10): Immich = server-version gate; Photos = authorization.
    /// Throws SourceFailure.authentication / .transient.
    func ensureReady() async throws

    /// All pickable collections (R9). Immich: albums. Photos: user albums + iCloud
    /// Shared Albums (full access only — throws .authentication under limited).
    func collections() async throws -> [SourceCollection]

    /// Rotation content for one collection. `PhotoLibrarySource.selectedPhotosID`
    /// resolves to the granted-assets pool. Throws .notFound on vanish (FR-900-16).
    func assets(in collectionID: String) async throws -> [SourceAsset]

    /// Final-quality image bytes (FR-900-07 — never degraded). Network allowed (FR-900-06).
    func imageData(for assetID: String, fidelity: ImageFidelity) async throws -> Data

    /// Overlay/HA metadata (FR-900-10/11). Absent fields are nil, never faked.
    func metadata(for assetID: String) async throws -> AssetMetadata
}

public struct SourceAsset: Sendable, Codable, Equatable { public let id: String; public let kind: MediaKind }
public enum MediaKind: String, Sendable, Codable { case image = "IMAGE", video = "VIDEO", other = "OTHER" }   // unknown → .other via init(rawValue:) fallback in Codable path
public struct SourceCollection: Sendable, Equatable { public let id: String; public let title: String; public let assetCount: Int; public let coverAssetID: String? }
public struct AssetMetadata: Sendable, Equatable { public let capturedAt: Date?; public let latitude: Double?; public let longitude: Double?; public let placeName: String? }
public enum ImageFidelity: String, Sendable { case thumbnail, preview, original }
public enum SourceFailure: Error, Sendable { case transient(underlying: Error), authentication, notFound, permanent(underlying: Error) }
public enum PhotoLibrarySource { public static let selectedPhotosID = "selected-photos" }
```

`PhotoSourceTestSupport` product: `StubPhotoSource` (scriptable conformance — per-call
results/delays/errors), replacing `StubImmichAPI` as the engine suites' fake.

## ImmichClient (conformance, new file `ImmichPhotoSource.swift`)

```swift
extension ImmichClient: PhotoSourceProviding { }   // or a wrapper struct if the actor's
                                                   // existing API surface makes retro-
                                                   // conformance awkward — subagent decides,
                                                   // wrapper preferred if any signature clashes
// ensureReady()  → existing ensureServerSupported()
// collections()  → albums().map(SourceCollection.init)
// assets(in:)    → assets(albumID:).map(SourceAsset.init)   // type string passthrough
// imageData      → thumbnail/preview/original by fidelity
// metadata       → assetInfo(assetID:) mapped (EXIF date, lat/lon, city+country → placeName)
// Error mapping: ImmichError → SourceFailure (401/403 → .authentication, 404 on album →
//   .notFound, URLError/5xx → .transient, else .permanent)
```

## SlideshowKit (refactor deltas)

```swift
// SlideshowViewModel
public init(source: any PhotoSourceProviding, collectionID: String, ...)   // was: api: any ImmichAPI, albumID:
// internal: imageAssets: [SourceAsset]; filter kind == .image (was type == "IMAGE")
// error paths: catch SourceFailure; RetryPolicy.classify(_: SourceFailure)
// readiness: try await source.ensureReady()  (was api.ensureServerSupported())

// SourceSnapshotStoring
func save(_ assets: [SourceAsset], for key: String) throws   // was [Asset]; wire format unchanged
func load(for key: String) throws -> [SourceAsset]?

// Package.swift: dependency ImmichClient REMOVED, PhotoSourceKit added.
```

Album browser / HA adapter (app target) consume `[SourceCollection]` from the active
provider instead of `[Album]`.

## PhotoLibraryKit (new package)

```swift
public protocol PhotoLibraryGateway: Sendable {          // implemented ONLY by PHKitGateway
    func authorizationStatus() -> PhotoAuthorizationState               // .readWrite level (R5)
    func requestAuthorization() async -> PhotoAuthorizationState
    func fetchCollections() throws -> [SourceCollection]                // user albums + cloud-shared
    func fetchAssets(in collectionID: String) throws -> [SourceAsset]   // windowed internally
    func fetchGrantedAssets() throws -> [SourceAsset]                   // limited-mode pool
    func requestImageData(assetID: String, fidelity: ImageFidelity) async throws -> Data  // final-quality only (R6)
    func fetchMetadata(assetID: String) throws -> AssetMetadata         // date + coords, placeName nil (R7)
    func setChangeHandler(_ handler: (@Sendable () -> Void)?)           // library change observation
}

public enum PhotoAuthorizationState: Sendable { case notDetermined, full, limited, denied }

public final class PhotoLibraryProvider: PhotoSourceProviding {
    public init(gateway: any PhotoLibraryGateway)
    // ensureReady(): full → ok; limited → ok only for selectedPhotosID sources (else
    //   .authentication); denied/notDetermined → .authentication
    // change handler + foreground refetch feed the engine's existing refresh path (FR-900-09)
}
```

Unit tests: `FakePhotoLibraryGateway` scripts every call; zero `import Photos` outside
`PHKitGateway.swift` (enforced by a test greping the package sources — cheap and binding).

## OnboardingKit delta

```swift
public enum SourceKind: Codable, Equatable {
    case immichAlbum(albumID: String)          // existing (names per current code)
    case sharedLink(...)                       // existing
    case photoLibrary(collectionID: String)    // NEW (R11)
}
// SourceLibrary/ViewModel: additive handling; cross-backend activation → .rebuild (R12)
```

## App target wiring

- Provider factory: active source's kind → `ImmichClient` (existing config) or
  `PhotoLibraryProvider(gateway: PHKitGateway())`.
- `PhotoAlbumPickerView`: authorization request on entry (FR-900-04), full → searchable
  collection list (210 component), limited → Selected-Photos row + manage-selection +
  honest note, denied → calm message + Settings link.
- Foreground re-check hook (R5) in the existing scenePhase observer.
