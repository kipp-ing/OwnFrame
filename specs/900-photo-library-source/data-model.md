# Data Model — Photo Library Source

Neutral types live in `PhotoSourceKit` (R1). Wire-format constraints from R2/R8.

## SourceAsset

The engine's unit of rotation and the snapshot store's persisted element.

| Field | Type | Notes |
|---|---|---|
| `id` | `String` | Backend-scoped identifier (Immich UUID / PhotoKit local identifier). Opaque to the engine; cache key stays `"\(id)#\(fidelity)"`. |
| `kind` | `MediaKind` | Raw-value string enum, **wire-compatible with fielded snapshots**: `IMAGE`, `VIDEO`, `OTHER` (unknown raw values decode to `OTHER`). |

- Codable shape: `{"id": "...", "type": "IMAGE"}` — byte-identical to the shipped `[Asset]`
  snapshot JSON (`type` is `kind`'s coding key). Existing files decode without migration.
- Validation: engine keeps only `kind == .image` in rotation (FR-300-13 + FR-900-08: Live
  Photos map to `.image` at the provider boundary, so "image" means "has a still
  representation").

## SourceCollection

| Field | Type | Notes |
|---|---|---|
| `id` | `String` | Album UUID (Immich) / collection local identifier (PhotoKit). |
| `title` | `String` | Picker display + search (210 pattern). |
| `assetCount` | `Int` | Lazy/estimated allowed (R9); picker display only. |
| `coverAssetID` | `String?` | Album-browser thumbnail; `nil` renders placeholder. |

## AssetMetadata

Info-overlay + HA metadata payload (FR-900-10/11).

| Field | Type | Notes |
|---|---|---|
| `capturedAt` | `Date?` | Overlay date line; absent → renders nothing (FR-300-24). |
| `latitude`/`longitude` | `Double?` | Carried for HA metadata parity; **no geocoding in v1** (R7) — overlay place-name line renders nothing for Photos assets. |
| `placeName` | `String?` | Populated by Immich (EXIF city/country); always `nil` from PhotoLibraryKit in this feature. |

## ImageFidelity

Neutral quality tier requested by the engine; each backend maps it (R6).

| Tier | Immich mapping | PhotoKit mapping |
|---|---|---|
| `.thumbnail` | `/thumbnail` endpoint | target size ≈ grid cell, network allowed |
| `.preview` | `/preview` endpoint | target size ≈ screen long edge, final-quality delivery |
| `.original` | `/original` endpoint | full pixel size, final-quality delivery |

ThemeKit's user-facing `ImageQuality` maps onto tiers in the engine exactly where it maps
onto endpoints today; shared-album ceiling (FR-900-15) needs no special casing — PhotoKit
simply returns ≤ 2048 px data for `.original` on legacy shared assets.

## SourceFailure (error taxonomy, R3)

| Case | Engine behavior | Immich mapping | PhotoLibrary mapping |
|---|---|---|---|
| `.transient(underlying)` | Backoff retry (FR-310) | network/5xx/timeouts | iCloud fetch errors, throttling |
| `.authentication` | Calm actionable state + slow retry | 401/403 (key revoked, link expired) | denied / downgraded-to-limited for an album source |
| `.notFound` | **Vanish state** (FR-900-16): calm unavailable, names likely cause, other sources untouched | album deleted (404) | collection missing from fetch (deleted / unshared / iOS-27-upgraded) |
| `.permanent(underlying)` | Calm error state, manual recovery | decode/contract errors | undecodable asset spills only as per-asset skip, never source-level |

`RetryPolicy.classify(SourceFailure)` replaces `classify(Error)`-over-`ImmichError`; the
backoff table itself is untouched.

## PhotoAuthorizationState (PhotoLibraryKit)

States: `notDetermined → (request) → full | limited | denied`; any state may transition to
any other via iOS Settings or the periodic re-prompt (checked at `ensureReady()` +
foreground, R5). The platform's add-only authorization grants no read access and maps to
`.denied` at the gateway (FR-900-04).

| State | Album sources | Selected-Photos source | Picker surface |
|---|---|---|---|
| `notDetermined` | request on first choice (FR-900-04) | request on first choice | "Photos album" entry visible |
| `full` | enumerable + playable | available (equals whole grant) | searchable album list (user albums + shared albums) |
| `limited` | **not enumerable** (platform), saved ones fail `.authentication` | the only offerable source | single "Selected Photos" row + manage-selection + honest note (US3-2) |
| `denied` | unavailable | unavailable | calm message + path to iOS Settings (US3-1) |

## SourceKind change (OnboardingKit)

`SourceKind` gains `.photoLibrary(collectionID: String)`; sentinel
`PhotoLibrarySource.selectedPhotosID == "selected-photos"` (R11). Persisted label = album
title ("Selected Photos" for the pool). Store change is additive; no migration of existing
saved sources. Cross-backend switch → `.rebuild` (R12).

## State: source vanish (FR-900-16)

Provider signals `.notFound` → view model enters the existing calm-unavailable presentation
with cause copy ("album deleted / no longer shared / possibly upgraded to the new iCloud
format"). Recovery = user picks a source (no auto-delete of the saved entry; HA select still
lists it until the user removes it).
