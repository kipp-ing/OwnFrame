# Feature Specification: Shared Album Link

**Feature Branch**: `110-shared-album-link`

**Created**: 2026-06-23

**Updated**: 2026-06-24

**Status**: Active — built and merged with `120`/`210`. Both the unprotected and the
password-protected paths are verified against the running server (Immich 2.7.5).

**Input**: Reserved sub-spec distilled from `specs/011-shared-album-link/spec.md`: Immich
shared/public album link support as an alternative slideshow source, with optional password and
verified API paths. Now consumed by `120-source-library` as one source kind among several.

## Verified mechanics (Immich 2.7.5)

Verified live against a real unprotected shared link (`/api/server/version` → `2.7.5`). A shared
link maps onto the existing albums → assets → preview/original contract using `?key=` query auth
instead of the `x-api-key` header:

1. **Parse** the pasted URL `https://<host>/s/<slug>` into base URL + slug (e.g. slug `geo2026`).
2. **Resolve** `GET /api/shared-links/me?slug=<slug>` → 200 with the shared-link object:
   the real `key` token, `type` (`ALBUM`), `album.id`, `album.albumName`, `album.assetCount`,
   `password` (null when unprotected), `expiresAt` (null = no expiry), `allowDownload`, `showMetadata`,
   `slug`. The `me` response does **not** inline the album's asset list for an ALBUM link.
   (`?key=<slug>` is rejected with 401 "Invalid share key" — `geo2026` is a slug, not a key.)
3. **Enumerate** `GET /api/albums/{album.id}?key=<key>` → 200 with the full `assets[]`
   (id, type IMAGE/VIDEO, originalFileName).
4. **Images** `GET /api/assets/{id}/thumbnail?key=<key>&size=preview` → `image/jpeg`;
   `GET /api/assets/{id}/original?key=<key>` → original bytes (HEIC in the sample). The same requests
   **without** `?key=` return 401, confirming the key is the bearer for unauthenticated shared access.

**Password-protected links** (verified against a protected link with an `expiresAt` set): without the
password, `GET /api/shared-links/me?slug=<slug>` returns 401. Supplying the password as a query
parameter — `GET /api/shared-links/me?slug=<slug>&password=<pw>` — returns 200 with the same shape
including the real `key` (the server also sets an `immich_shared_link_token` cookie, which the app
does not need). The password is required **only** at this resolve step; every later
`albums/{id}?key=` and `assets/{id}/...?key=` call uses the key alone — no password or cookie. A
wrong or missing password yields 401, distinct from an unreachable server. The 200 `me` response
echoes the submitted password back in its body, so the whole `me` response is sensitive and MUST NOT
be logged.

Implications for the source/transport abstraction (topic 100): `ImmichClient` needs a share-key auth
mode (`?key=` query) alongside the existing API-key header mode; the shared-link source stores the
base URL + slug (non-secret, from the pasted URL) and re-resolves to the key, and any password is a
Keychain secret supplied only at the resolve step. Links may carry an `expiresAt`, so an expired link
must surface a distinct error. Originals can be HEIC, so prefer the `preview` (JPEG) path for display.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Use a shared album link as the slideshow source (Priority: P1)

A user who has an Immich shared or public album link can paste that link, optionally provide its password, and use the linked album as the slideshow source without configuring a personal API key and album.

**Why this priority**: This is the whole deferred capability: a simpler source path for guests or family-shared albums.

**Independent Test**: With a mocked shared-link transport, submit a valid unprotected link and verify the linked album photos load; submit a protected link with the correct password and verify photos load; submit a wrong password and verify a clear error with nothing persisted.

**Acceptance Scenarios**:

1. **Given** a valid shared link with no password, **When** the user submits it, **Then** the linked album's photos load as the slideshow source.
2. **Given** a valid password-protected shared link, **When** the user submits the link with the correct password, **Then** the album loads as the slideshow source.
3. **Given** a password-protected shared link, **When** the password is missing or incorrect, **Then** a clear password error is shown and nothing is persisted.
4. **Given** a shared-link source is in use, **When** the app relaunches, **Then** the source is restored and any password remains secret.

### User Story 2 - Manage shared-link source from onboarding and Settings (Priority: P2)

The future shared-link entry becomes functional from both the combined onboarding screen and Settings, using the seam reserved by topic 200 and the source abstraction reserved by topic 100.

**Why this priority**: The feature must work both for first-run setup and later source changes, but it depends on the data-source work from the first story.

**Independent Test**: Enable the shared-link path from onboarding and Settings with a mock source, switch between an API-key album source and a shared-link source, and verify only validated source changes persist.

**Acceptance Scenarios**:

1. **Given** the combined onboarding screen, **When** shared-link mode is selected and a valid link is submitted, **Then** onboarding can complete using the shared-link source instead of API key plus album.
2. **Given** Settings, **When** the user changes or removes a shared-link source, **Then** the change is validated before persistence and the running slideshow adopts the valid result.

### Edge Cases

- **Expired or revoked link**: The app shows an invalid or expired link error distinct from password and reachability failures.
- **Wrong or missing password**: The app shows a password-specific error and persists nothing.
- **Unreachable server**: The app shows an unreachable error and persists nothing.
- **Empty linked album**: The slideshow uses the existing empty-source hint.
- **Embedded key versus separate password**: Both forms need clarification against the running Immich OpenAPI before planning.
- **Switching source types**: Behavior for coexistence of API-key album source and shared-link source remains an open question.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-110-01**: The app MUST accept an Immich shared or public album link as an alternative slideshow source to API-key plus album.
- **FR-110-02**: The app MUST accept an optional password for protected shared links.
- **FR-110-03**: A shared-link password, if present, MUST be treated as a secret and stored only in the Keychain; it MUST never appear in UserDefaults, logs, source code, committed files, cache, or plaintext UI. Open question: confirm whether the password is a true secret or shareable token.
- **FR-110-04**: Shared-link access MUST keep normal TLS validation enabled; plaintext access and TLS bypass are out of scope.
- **FR-110-05**: The app MUST validate the link and password before persisting and MUST distinguish invalid or expired link, wrong or missing password, and unreachable server where the underlying result allows.
- **FR-110-06**: The shared-link entry MUST be reachable from both the combined onboarding screen and Settings through the placement reserved by topic 200.
- **FR-110-07**: Shared-link API paths and authentication mechanics MUST be verified against the running server's OpenAPI spec and `/api/server/version`, not assumed from tutorials.
- **FR-110-08**: Shared-link source support MUST plug into the transport and source abstraction reserved by topic 100 without requiring slideshow engine rewrites.

### Key Entities *(include if feature involves data)*

- **Shared Link Source**: The shared/public album URL or share key and optional password, used as one slideshow source alternative to an API-key album.
- **Shared Link Validation Result**: A candidate source outcome classified as valid, invalid or expired link, missing or incorrect password, unreachable, or unexpected response.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-110-01**: A user with only a valid shared link and any required password can start a slideshow without creating or entering a personal API key.
- **SC-110-02**: Wrong or missing passwords, expired links, and unreachable servers produce distinct understandable errors and persist no source changes.
- **SC-110-03**: A saved shared-link source survives relaunch, and any password is absent from plaintext UI, UserDefaults, logs, source files, and committed files.

## Open Questions

1. **Immich mechanism**: RESOLVED for both unprotected and protected links (see Verified mechanics).
   Unprotected: slug resolves via `me?slug=`, assets via `albums/{id}?key=`, images via `?key=`.
   Protected: the password is supplied once as `me?slug=<slug>&password=<pw>` to obtain the key; all
   later calls use the key alone. Verified against the running server.
2. **Secret classification**: RESOLVED — when present, the shared-link password is a true secret and
   is stored in the Keychain. The slug is non-secret (it is in the pasted URL); the resolved key token
   is a sensitive bearer and MUST never be logged.
3. **Coexistence**: RESOLVED via `120` — a shared-link source and API-key album sources coexist in one
   library; exactly one source is active at a time.
4. **Onboarding path**: RESOLVED via `120` — a shared link is an additional source kind added to the
   library alongside albums, not a separate mode that skips the API-key path.

## Assumptions

- Topic 200 provides only the reserved UI placement until this deferred spec is scheduled.
- Topic 100 provides or reserves the source and transport abstraction this feature will plug into.
- Topic 300 consumes the resulting source once it presents the same image-asset contract as other slideshow sources.
- The future UI must keep the current calm default: the shared-link entry is explicit user choice, not a new overlay or startup interruption.
- The feature adds no background behavior; slideshow foreground-only timing and power boundaries remain owned by topics 300 and 400.
- Network and persistence dependencies must stay injected behind protocols so validation is testable without a real server or real Keychain.
- This is not scheduled for implementation until clarified and planned through the normal Spec Kit and test-first workflow.
