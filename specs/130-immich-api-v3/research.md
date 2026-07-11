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

> **M2 CORRECTION (live 3.0.2, 2026-07-10).** Two guesses in this section were **wrong**. For an
> **ALBUM** share, both `GET /shared-links/me` and `POST /shared-links/login` return **`assets: []`**
> — the assets are *not* embedded. And `POST /search/metadata` **does accept the `?key=`
> credential** (HTTP 200, full album). So a shared link lists its album exactly like an API key: the
> same `/search/metadata` pager, only authenticating with `?key=` instead of `x-api-key`. The text
> below is kept but corrected inline; the resolved architecture is in "Consequence" + "M2 —
> RESOLVED".

`GET /shared-links/me?key=<key>` (or `?slug=<slug>`) **resolves** the link → `SharedLinkResponseDto`
`{ key, album (AlbumResponseDto), expiresAt (nullable), password, slug, id, type, … }`. The resolver
reads `.key` + `.album.id` from here. (The `assets` field exists in the schema but is **empty for
album shares** — do **not** rely on it for listing.)

- Password links: `POST /shared-links/login?key=<key>` (or `?slug=`) with body
  `SharedLinkLoginDto { password }` (password **required, in the body**) → returns the same
  `SharedLinkResponseDto` (the resolver still reads `.key` from it) and sets an
  **`immich_shared_link_token`** cookie (not the `immich_access_token` originally guessed).

Consequence for architecture (**corrected**): a shared-link source lists its assets from the **same
`assets(albumID:)` choke point** as an API key. `ImmichClient.assets(albumID:)` calls the
`/search/metadata` pager for **both** auth kinds — the `?key=` query is appended for `.shareKey` by
`makeRequest`, no `x-api-key` header. The resolved `album.id` flows in via
`SharedLinkResolution.albumID` (`ActiveSourceResolver`). SlideshowKit callers and the 320 snapshot
stay transparent (still `[Asset]`).

**M2 questions — RESOLVED live (3.0.2, 2026-07-10):**
- **Password-link refresh**: neither (a) persist-cookie nor (b) re-login is needed.
  `POST /search/metadata?key=` returns the full album with the **key alone** — no cookie, no
  re-login — even for a password link. The password is spent once at `/login` to obtain the stable
  key; listing is then fully stateless. (`/me?key=` still enforces the password — "Password
  required" without the cookie — but it is no longer on the listing path.)
- **Shared image bytes** (top risk): ✅ `GET /assets/{id}/thumbnail?size=preview&key=<key>` still
  authorizes via `?key=` (HTTP 200 `image/jpeg`; no-key → 401). **Top M2 risk retired** — the 320
  disk-image path is untouched for shared links.

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
  **DONE 2026-07-10 against live 3.0.2** (bilder.kippings.de): API-key album load ✅ (456-asset
  album, paging terminates); shared-link resolve incl. password ✅; image bytes via `?key=` ✅;
  §3 **corrected** — shared-link listing moved from `/me.assets` (empty for album shares) to
  `/search/metadata?key=` (`ImmichClient.assets()` now single-path; red test flipped in
  `MetadataSearchTests`/`AuthModeTests`, host 54 + full sim 77 green).

## Fixtures to derive from this (feed the red tests)

- `search/metadata`: 2-page album (`nextPage:"2"` then `nextPage:null`), empty album
  (`items:[], nextPage:null`), mixed IMAGE/VIDEO to prove `type` decode + filter.
- `shared-links/me`: no-password link → `{key, album, assets, expiresAt}`; expired
  (`expiresAt` in the past). `shared-links/login`: password link → same DTO; wrong password → the
  error envelope the resolver's key↔slug/password discrimination reads.
- `server/version`: `{major:2,…}` (too-old), `{major:3,…}` (ok), `3.0.0-rc.2`-style, malformed.
