# Phase 0 Research — Photo Library Source

Most platform research was completed 2026-07-16 (three-agent pass: PhotoKit/iCloud web
research, tvOS research, portability audit) and is encoded in the spec's Assumptions and in
`docs/implementation-session-plan.md`. This file records the *design decisions* that turn
those findings into an implementation shape. No NEEDS CLARIFICATION items remain.

## R1 — Protocol placement: new `PhotoSourceKit` package

- **Decision**: The backend-neutral contract (`PhotoSourceProviding` + neutral models) lives
  in a new Foundation-only package `PhotoSourceKit` with a `PhotoSourceTestSupport` product
  (the shared `StubPhotoSource`). SlideshowKit, ImmichClient, and PhotoLibraryKit all depend
  on it; it depends on nothing.
- **Rationale**: FR-900-01 demands peer implementations. The protocol can't live in
  ImmichClient (PhotoLibraryKit would depend on Immich code) nor in SlideshowKit
  (ImmichClient would depend on the UI-facing engine package — inverted layering). A
  dependency-free floor package is the only shape where both backends are true peers.
- **Alternatives considered**: protocol in SlideshowKit with app-target adapters conforming
  (keeps package count down, but every backend conformance would live in the app target —
  untestable in package isolation, violates constitution II's spirit); typealias-shim over
  the existing `ImmichAPI` (leaves Immich vocabulary in the engine — fails FR-900-01).

## R2 — Snapshot wire format: keep `{id, type}` exactly

- **Decision**: `SourceSnapshotStoring` persists `[SourceAsset]`, and `SourceAsset` encodes
  to the *identical* JSON the fielded `[Asset]` snapshots already use: `{id: String,
  type: String}` with the Immich type strings ("IMAGE"/"VIDEO"/…) as `MediaKind` raw values.
- **Rationale**: Frames in the field have snapshot files on disk (320 shipped in v1.0). A
  byte-compatible format means zero migration code, zero migration tests, zero risk — the
  new type simply decodes old files.
- **Alternatives considered**: versioned envelope + migration (machinery without a payoff —
  the old format already carries exactly the two fields the engine needs); re-fetch-on-
  upgrade instead of decoding old snapshots (breaks 320's offline-relaunch guarantee for
  the first post-update launch).

## R3 — Error taxonomy: `SourceFailure` enum, mapped per backend

- **Decision**: `PhotoSourceKit` defines `SourceFailure: Error { transient(underlying),
  authentication, notFound, permanent(underlying) }`. `RetryPolicy.classify` operates on
  `SourceFailure` (transient → backoff; authentication → calm actionable state + slow
  retry, FR-310 semantics; notFound → vanish state FR-900-16). ImmichClient maps
  `ImmichError` (401/403 → authentication, network → transient, …); PhotoLibraryKit maps
  authorization denial/downgrade → authentication, missing collection → notFound, iCloud
  fetch errors → transient.
- **Rationale**: The engine currently pattern-matches `ImmichError` in four places (audit);
  a closed neutral taxonomy keeps retry semantics identical while deleting the backend
  reference. The vanish case gets its own arm because FR-900-16 makes it a first-class
  state, not a retry loop.
- **Alternatives considered**: per-backend `isTransient`-style protocol on errors (open
  taxonomy, engine can't exhaustively switch, vanish case has no natural home); keeping
  `ImmichError` as the lingua franca (PhotoKit faking Immich HTTP codes — absurd on its
  face).

## R4 — PhotoKit seam: `PhotoLibraryGateway`, one adapter file

- **Decision**: `PhotoLibraryProvider` (the `PhotoSourceProviding` conformance, pure logic)
  talks to a `PhotoLibraryGateway` protocol: fetch collections (user albums +
  `.albumCloudShared`), fetch asset descriptors for a collection (windowed), request image
  data (network-allowed, final-quality), current/request authorization (access-level-aware),
  register/unregister change observer, fetch granted-assets pool. Exactly one file —
  `PHKitGateway.swift` — imports Photos and implements it.
- **Rationale**: FR-900-13 (no PhotoKit in unit tests) + the house pattern already proven by
  `ScreenControlling`/`UIScreenController` and `MQTTTransport`/`NIOMQTTTransport`.
- **Alternatives considered**: conforming PhotoKit types directly (host tests impossible);
  spreading `import Photos` across provider files (seam erosion — the audit shows how clean
  the codebase has stayed by refusing exactly this).

## R5 — Authorization reads: access-level API only, re-checked at the edges

- **Decision**: Authorization state comes exclusively from
  `authorizationStatus(for: .readWrite)` / `requestAuthorization(for: .readWrite)` (behind
  the gateway). The provider re-evaluates on every `ensureReady()` (engine start/refresh)
  and the app re-checks on foreground; a downgrade (full → limited via the iOS periodic
  re-prompt) surfaces as `SourceFailure.authentication` for album sources while the
  Selected-Photos source keeps working.
- **Rationale**: Spec FR-900-04 (the legacy no-argument API reports limited as authorized —
  research-verified trap); US3-4 makes the mid-life downgrade an acceptance scenario.
- **Alternatives considered**: caching the status for the session (misses the re-prompt
  downgrade, fails US3-4); observing only the change observer for auth changes (PhotoKit
  does not reliably signal authorization transitions — belt and suspenders at the edges
  instead).

## R6 — Image delivery: single final-quality delivery, degraded guard kept

- **Decision**: Gateway image requests use network-access-allowed with high-quality-format
  delivery (one callback, final quality). A defensive check still drops any delivery flagged
  degraded before it reaches the engine.
- **Rationale**: FR-900-07 (no blurry frames). Opting out of opportunistic delivery is the
  platform-sanctioned way to get exactly one final image; the guard costs one line and makes
  the invariant test-assertable.
- **Alternatives considered**: opportunistic delivery + filtering (more callbacks to reason
  about, zero user-visible gain — prefetch already hides latency per US2).

## R7 — Location in the info overlay: coordinates stay on-device, no geocoding in v1

- **Decision**: `AssetMetadata` carries capture date and (when present) coordinates.
  For Photos-backend assets the overlay renders the **date only** in this feature; place-name
  reverse geocoding is Roadmap.
- **Rationale**: FR-900-14 says nothing from the library leaves the device except the HA
  opt-ins. Reverse geocoding ships coordinates to the system geocoding service — arguably
  benign (Apple, platform-standard), but it is a network egress derived from library
  content, and FR-900-10 already covers the honest fallback: "where a field is absent the
  overlay renders nothing." PhotoKit provides no place names natively, so the field is
  absent. If Jan wants place names later, that lands as an explicit FR-900-14 amendment
  (documented egress), not a silent call.
- **Alternatives considered**: CLGeocoder with caching (best UX, but silently contradicts
  FR-900-14's letter — needs a spec ruling first, deliberately deferred); shipping an
  offline geocoding dataset (absurd footprint for a nicety).

## R8 — Media kinds and Live Photos

- **Decision**: `MediaKind` raw values reuse the Immich strings ("IMAGE"/"VIDEO"/"OTHER" —
  wire compat per R2). PhotoKit mapping: still image → IMAGE; Live Photo → IMAGE (its still
  representation renders via the normal image request — FR-900-08); video → VIDEO (skipped,
  FR-300-13); anything else → OTHER (skipped).
- **Rationale**: FR-900-08 amends "skip" to "media without a still representation"; Live
  Photos have one and PhotoKit serves it through the standard image path — no special
  rendering code.
- **Alternatives considered**: a `stillCapable` boolean alongside kind (redundant — kind
  IMAGE *means* still-capable after the mapping above).

## R9 — Collections: lazy counts, cover asset optional

- **Decision**: `SourceCollection { id, title, assetCount, coverAssetID? }`. PhotoKit counts
  come from the collection's estimated count where available, else a count-only fetch;
  asset materialization stays windowed/lazy (10k-album edge case). Immich maps its album
  DTO onto the same shape.
- **Rationale**: The picker (210 pattern) needs title + count for search ranking; the album
  browser needs a cover. Nothing else from Immich's richer `Album` is consumed by shared
  UI (audit), so the neutral type stays minimal.
- **Alternatives considered**: carrying a metadata dictionary for backend extras (YAGNI —
  the two consumers are known and small).

## R10 — Readiness check on the protocol

- **Decision**: `ensureReady()` on `PhotoSourceProviding`: ImmichClient implements it as the
  existing `ensureServerSupported()` version gate; PhotoLibraryKit as the authorization
  check (R5). The engine calls it exactly where it calls the version gate today.
- **Rationale**: Both backends have a "can I even serve you" precondition; giving it one
  name removes the engine's last Immich-specific call without inventing new engine flow.
- **Alternatives considered**: folding readiness into the first fetch (loses the calm
  distinct error before playback starts — the engine's current UX separates these).

## R11 — SourceKind representation

- **Decision**: `SourceKind.photoLibrary(collectionID: String)` with the well-known sentinel
  `PhotoLibrarySource.selectedPhotosID = "selected-photos"` for the limited-mode pool
  (label "Selected Photos"). Persisted by the existing source-library store; label = album
  title at save time (existing pattern).
- **Rationale**: Spec Key Entities (collection-less variant as the same kind, stable
  well-known identifier). A sentinel keeps the enum payload uniform and the store codable
  change purely additive.
- **Alternatives considered**: separate `selectedPhotos` enum case (two cases to switch on
  everywhere for one behavioral difference the provider already hides); optional
  collectionID (nil-means-magic — worse than a named constant).

## R12 — Cross-backend switching

- **Decision**: The existing rebuild restart strategy is extended so any switch where the
  backend kind differs resolves to `.rebuild` (fresh provider, fresh caches keyed by new
  IDs, no reuse of in-flight state). Same-backend switches keep their current strategy.
- **Rationale**: Spec US1-5; SC-900-06 (no leaked timers/stale data). Asset-ID namespaces
  differ per backend, so cache keys never collide (`assetID#tier` with backend-scoped IDs —
  PhotoKit local identifiers vs Immich UUIDs).
- **Alternatives considered**: soft handover keeping the outgoing image on screen across
  backends (the rebuild path already keeps the current photo visible until the new source's
  first image is displayable — the engine's no-blank rule covers it without new machinery).
