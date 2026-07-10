# Contract: Immich v3 endpoints the app uses

Pinned from `immich-openapi-specs.json` @ `info.version 3.0.2`. Paths omit the `/api` base. Only
the endpoints this app calls are listed. Auth column: `x-api-key` header (API-key sources),
`?key=`/`?slug=` query (shared-link sources), or public.

## Version gate

| Method | Path              | Auth   | Notes |
|--------|-------------------|--------|-------|
| GET    | `/server/version` | public | `{ major, minor, patch }`. `security: none`. Gate: `major < 3` → `serverTooOld`. |

## API-key album source — asset listing

| Method | Path               | Auth        |
|--------|--------------------|-------------|
| POST   | `/search/metadata` | `x-api-key` |

Request `MetadataSearchDto` (send only these):

```json
{ "albumIds": ["<albumID>"], "type": "IMAGE", "order": "desc", "page": 1, "size": 1000 }
```

Response `SearchResponseDto`:

```json
{ "assets": { "items": [ /* AssetResponseDto */ ], "nextPage": "2", "count": 1000, "total": 2500 } }
```

Pager: `page = 1,2,…`; stop when `assets.nextPage == null`. Concatenate `assets.items`.
`order` = the album's `AlbumResponseDto.order` (default `desc`). `AssetOrder ∈ {asc,desc}`.

## Shared-link source — asset listing + resolution

| Method | Path                  | Auth                | Body / returns |
|--------|-----------------------|---------------------|----------------|
| GET    | `/shared-links/me`    | `?key=` or `?slug=` | → `SharedLinkResponseDto` (incl. `.assets`) |
| POST   | `/shared-links/login` | `?key=` or `?slug=` | body `SharedLinkLoginDto{ password }` → `SharedLinkResponseDto` (incl. `.assets`); sets `immich_access_token` cookie |

`SharedLinkResponseDto` (fields the app reads): `key: string`, `album: AlbumResponseDto`,
`assets: AssetResponseDto[]`, `expiresAt: string|null`, `slug`, `id`. **The link's assets are in
`.assets`** — a shared-link source does NOT call `/search/metadata` (`?key=` is not accepted
there) and does NOT rely on `GET /albums/{id}.assets` (removed).

- No-password link: `GET /shared-links/me?key=`.
- Password link: `POST /shared-links/login?key=` with `{ password }` (password **in body**, never
  `?password=`). The response carries `.assets`; re-login on refresh (stateless) — cookie
  persistence is an M2 decision (see research.md).

## Image bytes (unchanged endpoints — M2-verify `?key=` still authorizes for shared links)

| Method | Path                              | Query                  |
|--------|-----------------------------------|------------------------|
| GET    | `/assets/{id}/thumbnail`          | `size=preview`\|`thumbnail` (+ `key=` for shared links) |
| GET    | `/assets/{id}/original`           | (+ `key=` for shared links) |
| GET    | `/assets/{id}`                    | photo-info; exif retained; `deviceId`/`deviceAssetId` gone |

## DTO field notes (decode tolerance)

- `AssetResponseDto`: reads `id`, `type` (`AssetTypeEnum`); `deviceId`/`deviceAssetId` removed.
- `AlbumResponseDto`: `assets`/`owner`/`ownerId` removed, `albumUsers` added; `id`/`albumName`/
  `assetCount`/`startDate`/`endDate`/`order` retained.
- `SharedLinkResponseDto`: `token` removed.

## Auth mapping in `ImmichClient.assets(albumID:)` (route by `config.auth`)

```
.apiKey(k)   → POST /search/metadata  (x-api-key: k)     — paged, §API-key
.shareKey(k) → GET  /shared-links/me?key=k               — return .assets
             (password link: POST /shared-links/login?key=k {password})
```

Keeps the method's `[Asset]` signature → SlideshowKit callers and the 320 snapshot stay
untouched.
