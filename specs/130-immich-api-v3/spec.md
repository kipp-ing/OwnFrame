# Feature Specification: Immich API v3 Baseline (drop v2)

**Feature Branch**: `130-immich-api-v3`

**Created**: 2026-07-10

**Status**: Implemented (2026-07-10) — client (metadata-search pager, shared-link `/me` asset
listing, password-in-body login), the version gate (onboarding connect + Settings re-connect +
slideshow refresh, terminal/no-retry), and decode tolerance are built and gated: host suites
(ImmichClient 54, OnboardingKit 129, SlideshowKit 119) + app integration + full sim suite green,
app scheme builds clean. The dedicated too-old onboarding UITest is deferred (the logic is
covered by unit + app-integration tests and the notice renders through the existing error
surfaces, which the full XCUITest suite exercised without regression). Release timed so Immich
v3+ is the norm on the target audience's servers.

**Input**: Sub-spec of `specs/100-immich-client`. Immich **v3.0.0** shipped 2026-07-01 with
breaking API changes. Rather than maintain a v2/v3 compatibility layer, this app moves to a
**v3-only** baseline: the client speaks the v3 API, and any server reporting a major version
below 3 is detected and surfaced as an *outdated-server* notice instead of failing cryptically.
Three v3 changes actually touch this app: (1) the album response no longer carries an `assets`
array — album assets are read via `POST /api/search/metadata`; (2) shared-link password
authentication no longer accepts `query.password` — the password moves into the request body
(`POST /api/shared-links/login`); (3) several DTO fields were removed (`owner`/`ownerId` on
albums, `deviceId`/`deviceAssetId` on assets, `token` on shared links) and error envelopes were
simplified. Out of scope: any v2 compatibility path or dual-mode client; adopting new,
unrelated v3 features (mobile editor, Workflows, HLS transcode, Recently-Added); changing the
`x-api-key` / `?key=` auth model, which v3 keeps.

## User Scenarios & Testing *(mandatory)*

This sub-spec covers the v3 data-access delta only. It reuses topic 100's data-access
guarantees (album list, image bytes, error categories) and topic 210's shared-link onboarding;
it adds no new source kind and no new user-facing feature beyond the outdated-server notice.

### User Story 1 - Album photos load on a v3 server (Priority: P1)

A user points the app at an Immich v3 server and picks an album. Every photo of that album
loads and plays, exactly as before — even though v3 no longer returns the album's `assets`
inline and the client now pages the assets from the metadata-search endpoint.

**Why this priority**: This is the change that, if unhandled, makes the slideshow load **zero
photos** on every v3 server. It is the whole reason for the spec.

**Independent Test**: Against a mock transport returning v3 `POST /api/search/metadata` pages for
an album (multi-page, then an exhausted page), the client returns the full asset list — all IDs,
in a stable order — with no reliance on an `assets` property on the album response; an empty
album returns an empty valid list.

**Acceptance Scenarios**:

1. **Given** a v3 server and a selected album with more assets than one page, **When** the
   album's assets are fetched, **Then** all pages are retrieved and concatenated into the full
   asset list with every asset ID preserved.
2. **Given** a v3 server and an empty album, **When** the album's assets are fetched, **Then** an
   empty valid list is returned with no error and no crash (preserves FR-100-08).
3. **Given** the album-assets fetch, **When** the request is inspected, **Then** it targets the
   metadata-search endpoint (not an album `assets` array) and carries the album filter and the
   active auth (`x-api-key` header or `?key=` for a shared link).
4. **Given** a chosen playback order (topic 500), **When** assets are fetched, **Then** the
   client returns them in a **stable, documented base order** that the slideshow's order option
   can reorder deterministically (see Assumptions — album order preservation is a research item).

---

### User Story 2 - A password-protected shared link still works on v3 (Priority: P1)

A user accepts a password-protected Immich shared link (the low-friction onboarding path). The
app resolves it and plays it — with the password sent in the request body, because v3 rejects a
password supplied as a URL query parameter.

**Why this priority**: Shared-link-only setup is the app's primary, lowest-friction onboarding.
On v3 the current `?password=` query would be rejected, breaking password-protected links.

**Independent Test**: Against a mock transport, resolving a password-protected link succeeds when
the password is carried in the request body; the captured request(s) contain **no** `password`
query item. A non-password link resolves through the unchanged path.

**Acceptance Scenarios**:

1. **Given** a password-protected shared link on v3, **When** it is resolved, **Then** the
   password is sent in the request body and the link resolves to its key + album + expiry.
2. **Given** any resolution request, **When** it is inspected, **Then** no request carries the
   password as a URL query parameter.
3. **Given** a shared link with no password, **When** it is resolved, **Then** the existing
   no-password path is used (no login body step) and resolution is unchanged.
4. **Given** a wrong password, **When** resolution is attempted, **Then** a wrong-password error
   is reported (distinct from password-required and from not-found), preserving 110/210 behavior.

---

### User Story 3 - An outdated server tells the user to upgrade (Priority: P1)

A user connects to a server still on Immich v2. Instead of an empty slideshow or a cryptic
parse failure, the app clearly states it needs Immich v3 or newer and shows the detected
version — and does not proceed to the slideshow.

**Why this priority**: With v2 support dropped, a v2 server cannot work. An honest, specific
"your server is too old" beats a silent black screen; it is the difference between a support
ticket and a self-service upgrade.

**Independent Test**: With a mock transport reporting server major version 2, connecting yields a
distinct *server-too-old* outcome carrying the detected version; onboarding presents the upgrade
notice and never advances to album selection / slideshow. A periodic refresh that observes
major 2 surfaces the same notice and is treated as terminal (no retry storm).

**Acceptance Scenarios**:

1. **Given** a server reporting major version < 3, **When** the app connects, **Then** a
   *server-too-old* result is produced, distinguishable from unauthorized / unreachable /
   invalid-response.
2. **Given** the server-too-old result at connect, **When** onboarding handles it, **Then** a
   clear "needs Immich v3 or newer" notice is shown with the detected version, and the flow does
   **not** proceed to album selection or the slideshow.
3. **Given** a running slideshow whose periodic source refresh (topic 310) observes major < 3,
   **When** the refresh completes, **Then** the outdated-server notice is surfaced and the result
   is treated as **terminal** — it does not enter the auto-retry backoff loop.
4. **Given** a server reporting major version ≥ 3, **When** the app connects, **Then** the gate
   passes silently and the normal flow continues with no notice.

---

### User Story 4 - v3 responses decode cleanly despite removed fields (Priority: P2)

The app keeps working across v3's slimmed-down payloads: albums without `owner`/`ownerId`,
assets without `deviceId`/`deviceAssetId`, shared links without `token`, and the simplified
error envelope.

**Why this priority**: A single non-optional field that v3 removed would turn every affected
response into an invalid-response error. Decode tolerance is what keeps US1–US3 green.

**Independent Test**: v3 fixtures with `owner`/`deviceId`/`token` **absent** decode without error
across the album model, asset model, photo-info model, and shared-link resolution; a v3 error
body still yields a usable message everywhere the client reads one.

**Acceptance Scenarios**:

1. **Given** a v3 album/asset/shared-link JSON with the removed fields absent, **When** it is
   decoded, **Then** decoding succeeds and no removed field is treated as required.
2. **Given** a v3 error response (simplified envelope), **When** the client reads an error
   message (e.g. the shared-link "invalid key/slug" discrimination), **Then** the message is
   still extracted correctly, preserving 110's key↔slug fallback behavior.

### Edge Cases

- **Version endpoint unreachable or malformed**: treated as the existing *unreachable* /
  *invalid-response* category — **not** as "too old". The gate only fires on a confidently
  parsed major version < 3, so a network blip never blocks a v3 user.
- **Pre-release / RC version strings** (e.g. `3.0.0-rc.1`): only the numeric **major** decides
  the gate; the parser tolerates suffixes.
- **Exactly v3.0.0**: supported (gate passes).
- **Large album (many pages)**: every page is fetched until the endpoint reports exhaustion; no
  arbitrary asset cap is introduced.
- **v2 server reached via a shared link (no API key)**: the version endpoint is public, so the
  gate still fires and shows the upgrade notice (see Assumptions).
- **401 vs too-old**: an unauthorized response stays *unauthorized*; *server-too-old* is decided
  by the version number only, never conflated with an auth failure.
- **A v3 server later downgraded to v2**: the periodic-refresh gate (US3 scenario 3) catches it
  and surfaces the notice without a crash or a silent empty loop.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-130-01**: The client MUST target the Immich **v3** API. v2-only endpoints/DTO shapes are
  unsupported; NO v2 compatibility path or dual-mode client is provided.
- **FR-130-02**: The client MUST fetch an album's image assets via the v3 metadata-search
  endpoint (`POST /api/search/metadata`), filtered by album and paged until the server reports
  no further page, and MUST NOT depend on an `assets` array on the album response (removed in
  v3). The result preserves every asset ID and returns an empty valid list for an empty album
  (preserves FR-100-04 and FR-100-08).
- **FR-130-03**: The client MUST authenticate a password-protected shared link by sending the
  password in the **request body** (`POST /api/shared-links/login`, `SharedLinkLoginDto.password`,
  with the link identifier as `?key=`/`?slug=`), and MUST NOT send the password as a URL query
  parameter (rejected in v3). Non-password links MUST resolve through the unchanged no-body
  `GET /api/shared-links/me` path.
- **FR-130-12**: A **shared-link source** MUST list its image assets from the shared-link
  resolution response (`SharedLinkResponseDto.assets` from `GET /api/shared-links/me` or
  `POST /api/shared-links/login`), NOT from `GET /api/albums/{id}` (removed in v3) and NOT from
  `POST /api/search/metadata` (which does not accept the `?key=` shared-link credential). An
  API-key album source uses the metadata-search pager (FR-130-02); a shared-link source uses its
  `.assets`. Both MUST surface through the existing `assets(albumID:)` choke point (`[Asset]`), so
  SlideshowKit callers and the 320 source snapshot stay transparent (route by `config.auth`).
- **FR-130-04**: The client MUST determine the server's major version from
  `GET /api/server/version` (already available) and classify any server reporting major **< 3**
  as unsupported.
- **FR-130-05**: On connect (onboarding), the app MUST run the version gate and, when the server
  is unsupported, present a clear "needs Immich v3 or newer" notice that shows the detected
  version, and MUST NOT proceed to album selection or the slideshow.
- **FR-130-06**: During periodic source refresh (topic 310), an unsupported-version result MUST
  surface the same outdated-server notice and MUST be treated as a **terminal** condition — it
  does not enter the auto-retry backoff loop — until the server or the active source changes.
- **FR-130-07**: A distinct terminal error category (e.g. `serverTooOld`, carrying the detected
  version) MUST be reported for major < 3, distinguishable from `unauthorized`, `unreachable`,
  and `invalidResponse`, so callers can drive the upgrade notice specifically.
- **FR-130-08**: Response decoding MUST tolerate v3 shapes: the removed fields `owner`/`ownerId`
  (album), `deviceId`/`deviceAssetId` (asset), and `token` (shared link) MUST NOT be required,
  and the client MUST still extract an error message from the simplified v3 error envelope
  wherever it reads one (preserves 110's key↔slug discrimination).
- **FR-130-09**: The gate only fires on a confidently parsed major version < 3; a missing,
  unreachable, or unparseable version response MUST fall back to the existing `unreachable` /
  `invalidResponse` categories, never to `serverTooOld`.
- **FR-130-10**: All new behavior MUST be fully testable through the injected mock transport with
  no real server — v3 fixtures for metadata-search pages, shared-link login, and the version
  endpoint — in alignment with Modular Isolation (constitution II).
- **FR-130-11**: The shared-link password MUST NOT appear in logs, in stored URLs, or in
  UserDefaults; moving it from the query into the request body MUST NOT introduce a new leak
  surface (constitution III).

### Key Entities *(include if feature involves data)*

- **Server Version Gate**: the parsed `major.minor.patch` plus the supported-major policy
  (`major ≥ 3`); the decision function that maps a version to *supported* / *too-old* / *unknown*.
- **Metadata Asset Query**: the paged `POST /api/search/metadata` request (album filter +
  page/size) and its response shape (`assets.items` + a next-page signal) — the v3 replacement
  for the album `assets` array.
- **Shared-Link Login**: the `POST /api/shared-links/login` request carrying the link
  identifier (key or slug) and the password in its body, and the authenticated resolution to a
  key + album + expiry that follows.
- **Outdated-Server Notice**: the connect/refresh user-facing state shown when the server major
  version is < 3 — the detected version plus an upgrade prompt; a dead end for playback.

### Roadmap / Deferred (not yet built)

- **Adopt new v3 capabilities** (Workflows, HLS/HLS-preview streaming, Recently-Added as a
  source, mobile-edit-derived variants) — out of scope here; each is a separate future topic if
  it earns its place.
- **A minimum-version floor above 3.0** (e.g. requiring a later v3.x for a specific endpoint) —
  only if a needed endpoint lands mid-v3; the gate is deliberately "major ≥ 3" today.
- **Surface server version / v3-ok as an HA diagnostic** (topic 710 family) — intentionally left
  out of this spec (decision: hint at connect + refresh only, not over MQTT).

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-130-01**: Against a multi-page v3 metadata-search fixture, the client returns 100% of the
  album's asset IDs in the documented base order with zero reliance on an album `assets`
  property; an empty album returns an empty list without error.
- **SC-130-02**: A password-protected shared link resolves with the password carried in the
  request body, and 0 of the captured requests contain a `password` query parameter.
- **SC-130-03**: A server reporting major version 2 produces the `serverTooOld` category at
  connect; onboarding shows the upgrade notice with the reported version and does not reach album
  selection or the slideshow.
- **SC-130-04**: A refresh cycle that observes major version 2 surfaces the notice and does
  **not** enter the retry-backoff loop (terminal classification), verifiable via the retry
  policy.
- **SC-130-05**: v3 JSON with `owner` / `deviceId` / `token` absent decodes without error across
  the album, asset, photo-info, and shared-link-resolution models.
- **SC-130-06**: 100% of the above run against the mock transport with no real server, in line
  with Modular Isolation.

## Assumptions

- **v3 is the floor by release time.** The app ships late enough that its target users run
  Immich v3+; v2 servers are the rare exception the notice exists to catch. No telemetry decides
  this — it is a product/timing choice.
- **`GET /api/server/version` is public** (reachable without an API key), so the gate works for
  shared-link-only onboarding as well as API-key onboarding. Confirmed against the running v3
  server during research if in doubt.
- **Album order is date order (RESOLVED, see `research.md`/`contracts/`).** Pinned against v3.0.2:
  `AssetOrder` is only `asc|desc` (by date) — there is no "album order" primitive. But an Immich
  album's own ordering *is* `AlbumResponseDto.order` (`asc`/`desc` by date), so passing the
  album's `order` (default `desc`) into `POST /api/search/metadata` reproduces the album's prior
  ordering. "Sequential is album order" becomes "Sequential is capture-date order (album's
  `order`, default newest-first)" — a doc/wording tweak (T018), confirmed on M2, not a silent
  behavior change.
- **The v3 shared-link path is pinned (`research.md`/`contracts/`).** Both
  `GET /api/shared-links/me` and `POST /api/shared-links/login` survive and return
  `SharedLinkResponseDto` **including `.assets`** — so a shared-link source reads its assets from
  the resolution response (FR-130-12). Two items are M2 live-verify (not guessed): whether a
  password link's refresh needs the `immich_access_token` cookie or a re-login, and whether
  `GET /api/assets/{id}/thumbnail?key=` still authorizes shared image bytes (the top M2 risk for
  the 320 disk-image path).
- **Metadata-search field names are pinned** against v3.0.2 (`albumIds: string[]`, `page`,
  `size`, `type: IMAGE`, `order`, `nextPage` string token) — see `contracts/immich-v3-api.md`.
- **`x-api-key` and `?key=` auth are unchanged in v3**; the "rename API key schemas" change
  concerns key-management endpoints the app does not call, and `GET /api/assets/{id}` still backs
  the photo-info fetch (only `deviceId`/`deviceAssetId` were dropped, which the app never read).
- **310 is the refresh host** for FR-130-06: the periodic-refresh and terminal-vs-retryable
  classification machinery this spec leans on shipped with `310-slideshow-resilience`.
