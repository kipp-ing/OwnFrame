# Feature Specification: Photo Library Source (Apple Photos / iCloud Albums)

**Feature Branch**: `900-photo-library-source`

**Created**: 2026-07-09

**Status**: Deferred — planned for v1.x, after release and after `800-app-intents`. Specced now
because it drives the source-abstraction decision and the app's identity ("Photo Frame for
Immich & iCloud").

**Input**: New module (new source backend → new hundreds-block; the source *library* mechanics
stay with topic 120). Albums from the device's Apple Photos library — including iCloud Photos
albums and iCloud Shared Albums — become a third source kind alongside Immich albums and shared
links. The architectural core is a **source-agnostic data-access abstraction**: the slideshow
engine stops assuming `ImmichAPI` and consumes a protocol that Immich and PhotoKit both
implement. Out of scope: videos, editing, uploading, Memories/featured collections, smart
albums (Roadmap), multi-source pooling (topic 100 roadmap, unchanged), any Immich behavior
change.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Add a Photos album as a source (Priority: P1)

From onboarding or Settings, the user picks "Photos album" as a source type, grants photo
access, selects one of their albums (local or iCloud), and the slideshow plays it — exactly like
an Immich source: same transitions, same options, same chrome.

**Why this priority**: This is the feature. Everything else is plumbing for it.

**Independent Test**: With a fake photo-library provider behind the new source protocol: verify
the album list is enumerated, a selected album plays through the existing engine unchanged, and
the source is persisted in the topic-120 library and survives relaunch.

**Acceptance Scenarios**:

1. **Given** the source picker, **When** the user chooses "Photos album", **Then** photo access
   is requested at that moment (not at app launch) with a purpose string that says why.
2. **Given** access is granted, **Then** the user's albums (user collections and iCloud Shared
   Albums) are listed with title and count in the same searchable picker pattern the Immich
   album picker uses (topic 210).
3. **Given** an album is selected, **Then** it is saved as a source in the topic-120 library,
   becomes active, and the slideshow plays it with all topic-500 options applying live.
4. **Given** a saved Photos source, **When** the app relaunches, **Then** it resumes directly
   into that slideshow (startup parity with Immich sources).
5. **Given** the source library holds Immich and Photos sources, **When** the user switches
   between them (app UI, HA select, or intent), **Then** switching works with the rebuild
   restart strategy (`SourceRestartStrategy` extended for cross-backend switches).

### User Story 2 - iCloud originals arrive gracefully (Priority: P1)

Albums whose originals live in iCloud (device set to "Optimize Storage") play without blank
frames: images download on demand, the current photo stays up while the next one loads, and a
photo that cannot be fetched is skipped like any broken image.

**Why this priority**: On real devices most iCloud photos are *not* local. If this path is
weak, the feature is weak.

**Independent Test**: With a fake provider that delays or fails image delivery: verify the
engine's existing slow-connection behavior holds (current image stays, no blank transition —
topic 300 edge case), failed downloads are skipped (FR-300-09 semantics), and prefetch requests
the next 1–2 images ahead through the abstraction.

**Acceptance Scenarios**:

1. **Given** the next photo's original is in iCloud, **When** the advance is due but the image
   is not ready, **Then** the current photo stays until the next image is displayable (existing
   very-slow-connection rule) — never a blank or a spinner-on-black.
2. **Given** a photo fails to download (offline, iCloud error), **Then** it is skipped without
   stopping playback, consistent with FR-300-09; retry/refresh behavior follows topic 310.
3. **Given** progressive/degraded previews are offered by the system before the full image,
   **Then** the frame shows only the final-quality image (no visibly blurry frame), relying on
   prefetch to hide latency.
4. **Given** Live Photos in the album, **Then** their still key frame displays as a normal
   photo (they are NOT skipped — unlike videos; amends FR-300-13 for this backend).

### User Story 3 - Permissions and limited access handled honestly (Priority: P2)

Denied or limited photo access never dead-ends the app: the user sees what the frame can and
cannot show and where to change it.

**Independent Test**: With a fake authorization state: verify denied → calm message with a
path to iOS Settings; limited → the picker shows only authorized assets plus a hint to expand
selection; revoked-while-active → the source errors calmly like a failed Immich source.

**Acceptance Scenarios**:

1. **Given** access is denied, **Then** a calm message explains the frame cannot see photos and
   links to iOS Settings; other source kinds keep working untouched.
2. **Given** limited-library access, **Then** the album/photo list reflects exactly the granted
   subset and offers the system's "manage selection" affordance; no pretending the library is
   complete.
3. **Given** access is revoked while a Photos source is active, **Then** playback fails to the
   calm error state (FR-300-10) with an actionable message — no crash, no infinite spinner.
4. **Given** photo access exists, **Then** library content is used strictly for display (and
   the existing opt-in HA photo publishing, see FR-900-12) — nothing else leaves the device.

### Edge Cases

- **Album emptied or deleted in Photos**: existing empty-source behavior; the library change
  observer (FR-900-09) picks it up without waiting for a poll.
- **Asset deleted while being displayed**: finishes its slot, skipped afterwards (same rule as
  topic 310 removal handling).
- **Huge albums (10k+ assets)**: enumeration stays lazy/windowed; memory stays within existing
  cache bounds; startup does not block on full enumeration.
- **HEIC/HDR/panorama formats**: anything the platform can decode displays; undecodable assets
  are skipped like broken images.
- **iCloud throttling or no network with optimized storage**: behaves like a slow/offline Immich
  server — current photo persists, skips accumulate calmly, topic-310 retry applies.
- **Shared-album assets with restricted originals**: display at best available quality; if
  nothing displayable is provided, skip.
- **Device with no photo library content**: picker states it plainly; not an error.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-900-01**: The slideshow engine MUST consume a source-agnostic data-access protocol
  (enumerate assets, fetch image data at a quality tier, fetch display metadata/EXIF
  date+location) with `ImmichAPI` and the photo-library provider as peer implementations; no
  engine code may reference a concrete backend.
- **FR-900-02**: A new source kind (`photoLibrary`, identified by collection ID) MUST join
  topic 120's `SourceKind`, persist across relaunch, and participate in source switching with a
  rebuild restart strategy for cross-backend switches.
- **FR-900-03**: The source picker MUST list the user's albums and iCloud Shared Albums via the
  same searchable picker pattern as topic 210's album picker; smart albums are Roadmap.
- **FR-900-04**: Photo-library authorization MUST be requested only when the user chooses a
  Photos source (never at launch), with an accurate purpose string; the app MUST fully support
  the limited-library mode (show the granted subset, offer the system selection UI).
- **FR-900-05**: Denied/revoked access MUST produce calm, actionable states and MUST NOT affect
  non-Photos sources.
- **FR-900-06**: iCloud-resident originals MUST be fetched on demand with network access
  allowed, through the existing prefetch pipeline (FR-300-06); the engine's no-blank-frame rules
  (slow-connection edge case, FR-300-09 skip) apply unchanged.
- **FR-900-07**: Only final-quality images are displayed — degraded progressive previews are
  never shown on the frame.
- **FR-900-08**: Live Photos MUST display their still representation; videos and other
  non-still media remain skipped (FR-300-13 amended: "skip" applies to media without a still
  image representation).
- **FR-900-09**: Library changes (assets added/removed, album deleted) MUST reflect in the
  rotation via the platform change-observation API — event-driven where PhotoKit provides it,
  with topic 310's reconciliation rules (current photo finishes its slot, no visible restart);
  the 310 polling interval is the fallback, not the primary mechanism, for this backend.
- **FR-900-10**: The info overlay MUST show the same fields as for Immich assets (date,
  location when available) sourced from asset metadata; the FR-300-25 exclusions (no filename,
  no album name, no secrets) hold.
- **FR-900-11**: HA integration (topic 700/710) MUST treat a Photos source like any source:
  it appears in the source select, current-photo *metadata* publishes the same fields.
- **FR-900-12**: Publishing photo *images* from a Photos source to MQTT follows the existing
  global opt-in (off by default, not retained); the setting's copy MUST make clear it covers
  all sources, including the device photo library.
- **FR-900-13**: All new logic MUST be host-unit-testable behind the source protocol with a
  fake provider (no PhotoKit in unit tests); PhotoKit-touching code stays a thin adapter.
- **FR-900-14**: Nothing from the photo library leaves the device except through the existing,
  explicit HA publishing opt-ins; no analytics, no uploads (constitution III).

### Key Entities

- **Photo Source Protocol**: The backend-neutral contract (asset enumeration, image data by
  quality tier, metadata) that Immich and PhotoKit implement — the load-bearing refactor of
  this spec.
- **Photo Library Provider**: The PhotoKit-backed implementation (collections, on-demand iCloud
  fetch, change observation, authorization state).
- **Photos Source Kind**: `SourceKind.photoLibrary(collectionID)` in the topic-120 library with
  label = album title.
- **Authorization State**: full / limited / denied / revoked, driving picker content and calm
  states.

### Roadmap / Deferred (not yet built)

- **Smart albums** (Favorites, Recents) and **Memories-style collections** as pickable sources.
- **Multi-source pooling** across backends — stays topic 100/120 roadmap; the source protocol
  here is a prerequisite, not the delivery.
- **Naming/positioning follow-through**: store subtitle becomes "Photo Frame for Immich &
  iCloud" when this ships (listing text: `docs/app-store-listing.md`).

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-900-01**: A user can go from the source picker to a playing iCloud album slideshow in
  under a minute on a device with photos, without reading documentation.
- **SC-900-02**: With optimized storage and a cold cache, a full album cycle completes with zero
  blank frames and zero crashes; unfetchable assets are skipped silently (verified with a fake
  provider in CI, spot-verified on a real device with iCloud content before release of the
  feature).
- **SC-900-03**: All engine unit tests pass against both the Immich fake and the photo-library
  fake through the same protocol — proof the abstraction holds.
- **SC-900-04**: Adding/removing a photo in the Photos app reflects on the frame without
  restart (event-driven, not only via the hourly refresh).
- **SC-900-05**: Denied and limited authorization paths show their calm states and never crash
  or hang (UI-tested).
- **SC-900-06**: Switching Immich ↔ Photos sources via app UI, HA select, and (once built)
  intents works with no leaked timers or stale data from the previous backend.

## Assumptions

- PhotoKit's asset model (creation date, location, pixel size, media type/subtype) covers the
  info-overlay and HA-metadata needs; where a field is absent the overlay renders nothing
  (existing FR-300-24 behavior).
- The existing bounded in-memory cache and prefetch sizes are adequate for iCloud latency;
  tuning, if needed, is an implementation detail, not new spec surface.
- Topic 310 (retry/refresh) ships first; this spec leans on its reconciliation rules instead of
  redefining them.
- The iOS 17 deployment floor is unaffected (PhotoKit APIs used here predate iOS 17).
