# Research: Immich API v3 Baseline (drop v2)

**Phase 0 output for T002.** Pinned against the **published** Immich OpenAPI —
`open-api/immich-openapi-specs.json` on `main`, `info.version = 3.0.2` (fetched 2026-07-10). No
running v3 server required to freeze the contract; a live server is only needed for the two
end-to-end validation milestones (M1/M2 in tasks.md). Paths below omit the `/api` base.

## Decision log (the five T002 unknowns)

### 1. Album-source asset fetch → `POST /search/metadata` (CONFIRMED)

`GET /albums/{id}` returns `AlbumResponseDto` with **no `assets` property** (props:
`albumName, albumThumbnailAssetId, albumUsers, assetCount, order, startDate, endDate, id, …`).
Album assets are fetched from `POST /search/metadata`:

- **Request** `MetadataSearchDto` (all fields optional): `albumIds: string[]` is the album
  filter; `page: integer` (1-based); `size: integer`; `type: AssetTypeEnum` (`IMAGE` — filter to
  images server-side); `order: AssetOrder` (`asc` | `desc`); `withExif: boolean`.
- **Response** `SearchResponseDto.assets` = `SearchAssetResponseDto { items: AssetResponseDto[],
  nextPage: string|null, count, total }`.
- **Paging**: request `page = 1, 2, …`; stop when `nextPage` is `null`. `nextPage` is a **string
  token** (the next page number as a string), not a cursor object.
- **Auth**: security `[bearer, cookie, api_key]` → the **`x-api-key` header works**. This is the
  API-key album path.

### 2. Album-order decision → date order, `order: desc` default (RESOLVED, low risk)

`AssetOrder` is only `asc | desc` (by date) — there is **no "album order" primitive** to
reproduce. But the album's own ordering is itself just `AlbumResponseDto.order` (`asc`/`desc` by
date), so passing the album's `order` (default `desc`) into the metadata search **reproduces the
album's previous ordering**. Practical upshot: the "Sequential is album order" contract becomes
"Sequential is capture-date order (album's `order`, default newest-first)". This is a **doc/
wording tweak** (T018), not a behavior change — confirm the exact match on M2. If a specific
album's order ever diverges, Sequential is defined against date-desc and topic 500 is amended.

### 3. Shared-link source → assets come from `/shared-links/me` (NEW — plan gap closed)

A shared link **cannot** use `/search/metadata`: the `?key=` shared-link credential is not among
that endpoint's accepted schemes (`[bearer, cookie, api_key]`), and there is no `key`/`shareKey`
security scheme at all. Instead the shared-link endpoints return the assets **inline**:

- `GET /shared-links/me?key=<key>` (or `?slug=<slug>`) → `SharedLinkResponseDto` with
  `{ key, album (AlbumResponseDto), assets: AssetResponseDto[], expiresAt (nullable), password,
  slug, id, … }`. **The link's assets are in `.assets`** — no separate album call.
- Password links: `POST /shared-links/login?key=<key>` with body
  `SharedLinkLoginDto { password }` (password **required, in the body**) → returns the same
  `SharedLinkResponseDto` (so the login response *also* yields `.assets`) and sets the
  `immich_access_token` **cookie**.

Consequence for architecture: a **shared-link source lists its assets from the shared-link
resolution response, not from `assets(albumID:)`**. Cleanest fit for the existing single choke
point: make `ImmichClient.assets(albumID:)` branch on `config.auth` —
`.apiKey` → metadata-search pager (§1); `.shareKey` → `/shared-links/me?key=` and return
`.assets`. That keeps the SlideshowKit callers and the 320 snapshot transparent (still
`[Asset]`).

**Open M2 questions (need the live rc2/v3 server — do not guess):**
- **Password-link refresh**: `/me?key=` for a password link relies on the `immich_access_token`
  cookie set by `/login`. Does a stateless client need to (a) persist that cookie for the
  session, or (b) re-`POST /login` (password from the keychain) on every 310 refresh? Prefer
  **(b) re-login, stateless** unless M2 shows the cookie is required elsewhere.
- **Shared image bytes**: does `GET /assets/{id}/thumbnail?key=<key>&size=preview` still authorize
  via `?key=` in v3 (as public shared albums require), or does it now need the login cookie? This
  gates whether the 320 disk-image path is untouched for shared links. **Top M2 risk.**

### 4. Version endpoint is public (CONFIRMED)

`GET /server/version` has `security: none` → reachable without any auth. The outdated-server
gate therefore works for **shared-link-only onboarding** (no API key) as well as API-key
onboarding. Returns `{ major, minor, patch }` (existing `ServerVersion` decode is correct).

### 5. Removed-field inventory (CONFIRMED — decode tolerance is safe)

- `AssetResponseDto`: has `id` + `type` (`AssetTypeEnum`); **`deviceId`/`deviceAssetId` removed**.
  The app decodes only `id`/`type` (+ exif on the detail model) → unaffected.
- `AlbumResponseDto`: **`assets`, `owner`, `ownerId` removed**; `albumUsers` added; `id`,
  `albumName`, `assetCount`, `startDate`, `endDate`, `order` retained → the `Album` model
  (`id`, `albumName`, `assetCount`, dates) still decodes.
- `SharedLinkResponseDto`: `token` removed (app never read it); `key`, `album`, `assets`,
  `expiresAt`, `slug` present → resolver decode holds and now also reads `.assets`.

## Named security schemes (reference)

`bearer` (HTTP header), `cookie` (`immich_access_token` cookie), `api_key` (`x-api-key` header).
No shared-link-`key` scheme is declared — `?key=`/`?slug=` are plain query params the
shared-link endpoints accept explicitly. `x-api-key` and `?key=` remain the app's two auth
modes; the "rename API key schemas" v3 change touches key-management endpoints the app never
calls.

## Validation milestones (the build loop)

- **M1 — live v2 server** (current): build, point at v2 → `GET /server/version` reports major 2
  → `serverTooOld` → onboarding shows the upgrade notice, no advance. This is **US3's
  acceptance test end-to-end**; failing to load is the *expected pass*. It does **not** exercise
  US1/US2 wire (those stay on mock fixtures).
- **M2 — after upgrade to rc2/v3**: real album load (§1), real shared-link resolve incl.
  password (§3), and the two open shared-link questions above. rc2 passes the gate — the parser
  keys on the numeric major and tolerates the `-rc.2` suffix (spec edge case).

## Fixtures to derive from this (feed the red tests)

- `search/metadata`: 2-page album (`nextPage:"2"` then `nextPage:null`), empty album
  (`items:[], nextPage:null`), mixed IMAGE/VIDEO to prove `type` decode + filter.
- `shared-links/me`: no-password link → `{key, album, assets, expiresAt}`; expired
  (`expiresAt` in the past). `shared-links/login`: password link → same DTO; wrong password → the
  error envelope the resolver's key↔slug/password discrimination reads.
- `server/version`: `{major:2,…}` (too-old), `{major:3,…}` (ok), `3.0.0-rc.2`-style, malformed.
