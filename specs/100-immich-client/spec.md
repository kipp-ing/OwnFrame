# Feature Specification: ImmichClient (Immich data access)

**Feature Branch**: `100-immich-client`

**Created**: 2026-06-23

**Status**: Active

**Input**: Consolidated from `specs/001-immich-client/spec.md`: data access for connecting to an Immich server, reading albums and assets, fetching displayable image data, and surfacing testable error categories.

## User Scenarios & Testing *(mandatory)*

This feature covers data access only. It does not include UI, onboarding, persistence of the API key, or slideshow presentation.

### User Story 1 - Fetch the user's albums (Priority: P1)

With a valid server URL and API key, the app can fetch the user's Immich albums so a later workflow can choose an album for the slideshow.

**Why this priority**: Without the album list there is nothing to choose and no content source for the rest of the app.

**Independent Test**: Against a mock transport returning valid album JSON, the client returns albums with ID and name and sends the expected authentication header, without requiring a real server.

**Acceptance Scenarios**:

1. **Given** a valid server URL and API key, **When** the album list is fetched, **Then** a list of albums is returned with each album's ID and name.
2. **Given** a valid album JSON response from the server, **When** it is processed, **Then** it is translated into album models without losing any ID or name.
3. **Given** any client request, **When** the request is sent to the server, **Then** it carries the API key in the `x-api-key` header.

---

### User Story 2 - Fetch image assets for an album (Priority: P1)

After an album is selected, the app can fetch that album's image assets, including IDs and display metadata needed by the slideshow.

**Why this priority**: The slideshow needs a valid asset list before it can display any photos.

**Independent Test**: Against a mock transport returning an album-assets response, the client returns image assets with IDs and display metadata; an empty album returns an empty valid list.

**Acceptance Scenarios**:

1. **Given** a selected album with images, **When** the album's assets are fetched, **Then** a list of assets is returned with IDs and the metadata needed for display.
2. **Given** a selected album without assets, **When** the album's assets are fetched, **Then** an empty valid list is returned with no error and no crash.

---

### User Story 3 - Fetch a downscaled preview image (Priority: P2)

For a known asset, the app can fetch downscaled preview image data suitable for display instead of transferring the original file by default.

**Why this priority**: Preview images allow the later slideshow to show photos efficiently without downloading full originals for every frame.

**Independent Test**: Against a mock transport returning image bytes for an asset ID, the client returns those preview bytes and uses the preview endpoint/variant rather than an original-quality fetch.

**Acceptance Scenarios**:

1. **Given** a valid asset ID, **When** the preview image is fetched, **Then** downscaled preview image data is returned and the original file is not fetched.
2. **Given** a valid asset ID, **When** original-quality image data is explicitly requested, **Then** the asset's original endpoint is used and the raw original bytes are returned.

---

### User Story 4 - Report actionable data-access errors (Priority: P2)

When Immich cannot be reached, rejects credentials, or returns malformed data, callers receive distinct errors that can drive user-facing recovery.

**Why this priority**: Later onboarding and slideshow flows must tell the difference between bad credentials, network problems, and invalid server responses.

**Independent Test**: A mock transport can simulate HTTP 401, network timeout/unreachable failures, and malformed JSON, and the client reports the expected category for each case.

**Acceptance Scenarios**:

1. **Given** the server returns HTTP 401, **When** any protected resource is fetched, **Then** the client reports an unauthorized error distinguishable from a generic failure.
2. **Given** the server is unreachable or times out, **When** a request is made, **Then** the client reports an unreachable error distinguishable from an authorization error.
3. **Given** the server returns unexpected or malformed JSON, **When** the response is decoded, **Then** the client reports an invalid-response or parsing error and does not crash.

### Edge Cases

- **Wrong or expired API key (401)**: The error is clearly unauthorized and distinguishable from a generic failure.
- **Server unreachable or timeout**: The error is clearly unreachable and distinguishable from an authorization failure.
- **Empty album**: The result is an empty valid list, not an error.
- **Unexpected or malformed JSON response**: The response is treated as a parsing or invalid-response error, not as a crash.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-100-01**: The client MUST accept an HTTPS server base URL and API key as configuration.
- **FR-100-02**: The client MUST authenticate every outgoing request with the API key in the `x-api-key` header.
- **FR-100-03**: The client MUST fetch the user's album list with at least each album's ID and name.
- **FR-100-04**: The client MUST fetch image assets for a selected album, including asset IDs and display metadata needed by the slideshow.
- **FR-100-05**: The client MUST fetch a downscaled preview image for an asset by default, not the original file.
- **FR-100-06**: The client MUST report HTTP 401 responses as unauthorized errors distinguishable from generic failures.
- **FR-100-07**: The client MUST report timeouts or network failures as unreachable errors distinguishable from authorization errors.
- **FR-100-08**: The client MUST return an empty valid list for an album with no assets.
- **FR-100-09**: The client MUST translate valid album JSON into album models without losing album IDs or names.
- **FR-100-10**: The client MUST report malformed or unexpected server responses as invalid-response or parsing errors, not crashes.
- **FR-100-11**: The client MUST be fully testable through an injected mock transport, with no real Immich server required, in alignment with Modular Isolation.
- **FR-100-12**: The client MUST use normal HTTPS/TLS validation and MUST NOT provide a TLS-disable path.
- **FR-100-13**: The client MUST be able to fetch an asset's original-quality image data on explicit request (via the asset's `original` endpoint), so the Display Options "Original" quality option (topic 500) can opt out of previews. Preview remains the default per FR-100-05.
- **FR-100-14**: The client MUST be able to fetch a small thumbnail variant for an asset (a cheaper, smaller request than the preview) for grid/browser use by the slideshow album browser (topic 300).

### Key Entities *(include if feature involves data)*

- **ServerConfig**: The connection configuration supplied to the client: HTTPS base URL and API key. The API key is consumed by this feature but secure persistence belongs to onboarding/keychain features.
- **Album**: A user album returned by Immich. Key attributes: unique ID and name.
- **Asset**: A displayable image asset in an album. Key attributes: unique ID and display metadata needed by the slideshow.
- **Preview Image Data**: Downscaled image bytes for an asset, used by the slideshow as the default image quality.
- **Error Category**: A testable failure classification: unauthorized, unreachable, or invalid response.

### Roadmap / Deferred (not yet built)

- Sub-spec `130-immich-api-v3` (**Draft**): v3-only baseline. Album assets move to
  `POST /api/search/metadata` (the album `assets` array was removed in v3), the shared-link
  password moves into the request body (v3 rejects `query.password`), and a server reporting
  major version < 3 is detected via `GET /api/server/version` and surfaced as an outdated-server
  notice at connect + refresh. No v2 compatibility path. Amends FR-100-04 (asset fetch mechanism)
  and 110's shared-link auth; see `specs/130-immich-api-v3/spec.md`.
- Sub-spec `110-shared-album-link` (now **scheduled**, feeding `120`): auth is abstracted behind the
  transport so a shared-link key (`?key=` query) and optional password replace `x-api-key` without
  changing call sites; unprotected mechanics are verified against Immich 2.7.5 (see `110`), and
  secrets must never leak to code, storage, or logs.
- Sub-spec `120-source-library` (**scheduled**): persist several switchable sources (albums + shared
  links) with exactly one active at a time; generalizes the single `selectedAlbumID`.
- Pool assets across multiple albums into one list (still deferred — `120` switches between sources,
  it does not pool). Acceptance preserved from the source: given multiple album IDs, when their assets
  are requested, then a single pooled asset list is returned.
- Fetch Memories as an asset source. Acceptance preserved from the source: given a Memories request, when it is made, then a valid list of memory assets is returned, or an empty list if none exist.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-100-01**: 100% of protected requests carry the `x-api-key` header, verifiable through the mock transport.
- **SC-100-02**: A valid album JSON response preserves 100% of album IDs and names in the returned models.
- **SC-100-03**: 100% of HTTP 401 responses produce an unauthorized error category, not a generic failure.
- **SC-100-04**: 100% of timeout or network-failure simulations produce an unreachable error category.
- **SC-100-05**: 100% of empty-album responses return an empty list without error.
- **SC-100-06**: All acceptance scenarios run against a mock transport with no real server.

## Assumptions

- The Immich server has a valid TLS certificate; self-signed certificates and plaintext local connections are out of scope.
- The API key is provided to this feature by another module. Storing it in the Keychain is handled outside this client feature.
- Concrete Immich API paths are checked against the OpenAPI spec of the running server version, including `/api/server/version`, not copied from old tutorials.
- Display metadata means the minimal fields required by the slideshow; the exact field set is finalized against the current Immich response shape during implementation.
