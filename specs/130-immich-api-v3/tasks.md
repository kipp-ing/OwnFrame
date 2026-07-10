# Tasks: Immich API v3 Baseline (drop v2)

**Input**: Design documents from `/specs/130-immich-api-v3/` (spec.md, plan.md; research.md +
contracts/immich-v3-api.md produced by T002 below).

**Prerequisites**: `100-immich-client`, `110-shared-album-link`, `210-shared-link-onboarding`,
and **`320-disk-image-cache` (DONE, 2026-07-09)** are all on the base branch and green. The
snapshot/offline layer of 320 rides `assets(albumID:)` behind `ImmichAPI`, so this migration
must keep 320's suites green — Phase 7 proves it rather than assuming it.

**Tests**: MANDATORY — constitution principle I (Test-First, NON-NEGOTIABLE). Red before green
for every pair; "red" includes does-not-compile against the not-yet-added API. Everything is
exercised against the injected mock transport with **v3 fixtures** — no real server (FR-130-10).

**Delegation**: none — Codex disabled per Jan (2026-07-09). All inline.

**Organization**: **US1 (metadata-search asset fetch)** + **US3 (outdated-server gate)** are the
MVP — together they make the app *work* on v3 and *fail honestly* on v2. **US2 (shared-link
password in body)** restores the password-protected shared-link onboarding path. **US4 (decode
tolerance)** and **Phase 7 (cache/rotation fold-in)** complete correctness with nothing dangling.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: US1 / US2 / US3 / US4 from spec.md, or **[Research]** / **[Cache]** cross-cutting
- All package paths relative to repo root

## Path Conventions

- Client: `Packages/ImmichClient/Sources/ImmichClient/` — tests `…/Tests/ImmichClientTests/`
- Onboarding: `Packages/OnboardingKit/Sources/OnboardingKit/` — tests `…/Tests/OnboardingKitTests/`
- Engine: `Packages/SlideshowKit/Sources/SlideshowKit/` — tests `…/Tests/SlideshowKitTests/`
- App target: `Immich Slideshow/` + `Immich SlideshowUITests/` (XcodeBuildMCP only)

---

## Phase 1: Setup & Contract Pinning

- [x] T001 Create branch `130-immich-api-v3` off `main`; point `.specify/feature.json` at
      `specs/130-immich-api-v3`; confirm `swift test` is green in ImmichClient, OnboardingKit,
      **and SlideshowKit (incl. the 320 offline/cache suites)** before touching anything —
      that green baseline is the regression guard for the whole migration.
- [x] T002 **[Research]** Pin `research.md` + `contracts/immich-v3-api.md` — **DONE** against the
      **published** OpenAPI (`immich-openapi-specs.json` @ `info.version 3.0.2`), no live server
      needed. Resolved: (1) `POST /api/search/metadata` body = `MetadataSearchDto{ albumIds:[..],
      type:IMAGE, order, page, size }`, page-token loop on `assets.nextPage` (string|null);
      (2) **album order = date order** — `AssetOrder` is only asc/desc and equals the album's own
      `order`, so it reproduces album ordering → T018 is a doc tweak, not a behavior change;
      (3) **shared-link fetch changed** — `/shared-links/me` + `/shared-links/login` both return
      `SharedLinkResponseDto.assets`, so a shared-link source lists from there, NOT search/metadata
      (`?key=` isn't accepted there) → **new task T008a**; (4) `/api/server/version` is public
      (`security: none`); (5) removed fields = `deviceId`/`deviceAssetId` (asset), `owner`/`ownerId`/
      `assets` (album), `token` (shared link) — all safe. Two items deferred to **M2** (live rc2):
      password-link refresh cookie-vs-relogin, and whether `?key=` still authorizes shared image
      bytes (top M2 risk). See research.md §3.

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: the new error, the version classifier, and the v3 DTOs — the pieces every story
leans on.

- [x] T003 [P] Red+Green: add `case serverTooOld(version: String)` to
      `Packages/ImmichClient/Sources/ImmichClient/ImmichError.swift` (stays `Equatable`);
      assert in `…/ImmichClientTests/ErrorTests.swift` that it is distinct from
      `unauthorized`/`unreachable`/`invalidResponse` (FR-130-07).
- [x] T004 [P] Red: `…/ImmichClientTests/ServerVersionTests.swift` — supported-version
      classifier: major ≥ 3 → supported; major 2 → too-old; `3.0.0-rc.1` parses on the numeric
      major → supported; malformed/absent → **unknown**, never too-old (FR-130-04/09, SC-130-03).
- [x] T005 Green: parsed supported-version helper in
      `Packages/ImmichClient/Sources/ImmichClient/ImmichClient.swift` on top of the existing
      `serverVersion()` — returns supported/too-old/unknown and throws
      `serverTooOld(version:)` only on a confidently parsed major < 3 (never on parse/reach
      failure, which stays `unreachable`/`invalidResponse`) (depends on T004).
- [x] T006 [P] Red+Green: v3 DTOs in
      `Packages/ImmichClient/Sources/ImmichClient/Models.swift` per contracts — new
      `…/ImmichClientTests/MetadataSearchTests.swift` red first: `MetadataSearchRequest`
      (album filter + `page`/`size`) and `SearchResponse{ assets: { items: [Asset], nextPage } }`
      decode `Asset{ id, type }` **including `type`** (IMAGE/VIDEO — the slideshow's image filter
      and the 320 snapshot depend on it); plus the shared-link login request/response DTOs
      (FR-130-02/08).

**Checkpoint**: `swift test` green — error, gate, and DTOs proven standalone.

---

## Phase 3: User Story 1 — Album assets via metadata search (Priority: P1) 🎯 MVP

**Goal**: `assets(albumID:)` returns the full album, paged from `POST /api/search/metadata`,
with no dependency on the removed album `assets` array.

**Independent Test**: mock multi-page metadata-search fixtures → full ordered asset list;
empty album → `[]`.

- [x] T007 [US1] Red: `…/ImmichClientTests/MetadataSearchTests.swift` — the pager: multi-page
      responses concatenate in the **pinned base order** preserving every ID; final/empty page
      terminates; empty album → `[]` (FR-100-08 preserved); the request is a `POST` to the
      metadata endpoint carrying the album filter, the JSON body, and the active auth
      (`x-api-key` header for API key, `?key=` for a shared link); `type` is decoded so
      IMAGE/VIDEO is distinguishable (FR-130-02, SC-130-01).
- [x] T008 [US1] Green: reimplement the **API-key branch** of `assets(albumID:)` in
      `Packages/ImmichClient/Sources/ImmichClient/ImmichClient.swift` as the metadata-search
      pager (`.apiKey` → `POST /api/search/metadata`, page-token loop); add a JSON-body `POST`
      path to `makeRequest`; **remove** the `GET /api/albums/{id}` → `AlbumDetail.assets` decode
      path. Signature stays `[Asset]`, so SlideshowKit/OnboardingKit callers are untouched
      (depends on T006, T007).
- [x] T008a [US1] Red+Green: the **shared-link branch** of `assets(albumID:)` — route by
      `config.auth` (contracts §"Auth mapping"): `.shareKey(key)` → `GET /api/shared-links/me?key=`
      and return `SharedLinkResponseDto.assets` (v3: shared links can't use search/metadata; the
      `.assets` array is on the `/me` response, FR-130-12). No-password links fully covered here;
      **password-link refresh** (re-`POST /shared-links/login` with the keychain password vs.
      persisting the `immich_access_token` cookie) is wired per the **M2** decision — until then
      the no-password path is green and the password path is guarded/TODO'd against the M2
      finding, not guessed (research.md §3). Red first in `MetadataSearchTests.swift` /
      `SharedLinkResolverTests.swift` (depends on T006; password path relates to T010).

**Checkpoint**: album photos load on a v3 fixture for **both** an API-key album (search/metadata)
and a shared-link source (`/me.assets`); all existing client callers compile unchanged.

---

## Phase 4: User Story 2 — Shared-link password in the body (Priority: P1)

**Goal**: password-protected shared links resolve with the password in the request body; no
password ever rides the URL query.

**Independent Test**: mock login+resolve → resolution; assert no request carries a `password`
query item; no-password links use the unchanged path.

- [x] T009 [US2] Red: extend `…/ImmichClientTests/SharedLinkResolverTests.swift` — password
      carried in the `POST /api/shared-links/login` body; **assert no request has a `password`
      query item** (SC-130-02); wrong password → `wrongPassword` (distinct from
      `passwordRequired`/not-found); no-password link uses the unchanged GET path; key↔slug
      fallback intact on v3 (FR-130-03/08).
- [x] T010 [US2] Green: `Packages/ImmichClient/Sources/ImmichClient/SharedLinkResolver.swift` —
      move the password into the login body per the T002 contract; preserve the key↔slug
      fallback and the no-password path; adapt the `/me` resolution to the pinned v3 sequence
      (depends on T002, T009).

---

## Phase 5: User Story 3 — Outdated-server gate (Priority: P1) 🎯 MVP

**Goal**: a server on major < 3 yields the terminal `serverTooOld`; onboarding shows the
upgrade notice and blocks; the 310 refresh surfaces it terminally without a retry storm.

**Independent Test**: mock version major 2 → `serverTooOld`; onboarding shows notice, no
advance; refresh classifies terminal.

- [x] T011 [US3] Red: `…/SlideshowKitTests/RetryPolicyTests.swift` — `ImmichError.serverTooOld`
      is terminal (non-retryable), alongside `unauthorized`/`shareLinkExpired`/`wrongPassword`/
      `passwordRequired` (FR-130-06, SC-130-04).
- [x] T012 [US3] Green: add `serverTooOld` to the terminal set in
      `Packages/SlideshowKit/Sources/SlideshowKit/RetryPolicy.swift` (depends on T003, T011).
- [x] T013 [US3] Red: `…/OnboardingKitTests/OnboardingViewModelTests.swift` (+ a
      `ConnectionValidationOutcome`/`ConnectionError` case) — connect runs the version gate;
      major 2 → a too-old outcome carrying the detected version; the flow does **not** advance
      to album selection (FR-130-05, SC-130-03).
- [x] T014 [US3] Green: wire the gate into
      `Packages/OnboardingKit/Sources/OnboardingKit/OnboardingViewModel.swift` connect path;
      add the too-old case to `ConnectionValidationOutcome.swift`/`ConnectionError.swift`
      carrying the version; block advancement (depends on T005, T013).
- [x] T015 [US3] Red: refresh-time gate in `…/SlideshowKitTests/SlideshowResilienceTests.swift`
      — a periodic refresh observing major < 3 raises `serverTooOld`, surfaces the notice
      state, and does **not** enter the backoff loop (terminal via T012). **Timer/refresh
      concurrency design — inline** (CLAUDE.md).
- [x] T016 [US3] Green: version guard in the refresh path of
      `Packages/SlideshowKit/Sources/SlideshowKit/SlideshowViewModel.swift` via the client's
      supported-check helper (T005); `serverTooOld` flows into `handleFailure` and is held
      terminal (no retry) so the notice shows (depends on T005, T012, T015).

**Checkpoint**: v2 server → clear "needs Immich v3+" notice at connect and on refresh; v3 → silent.

---

## Phase 6: User Story 4 — Decode tolerance (Priority: P2)

**Goal**: v3's slimmed payloads decode without error.

- [x] T017 [US4] Red+Green (verification): fixtures with the removed fields **absent** across
      `…/ImmichClientTests/AlbumTests.swift`, `AssetTests.swift`, `AssetInfoTests.swift`, and
      `SharedLinkResolverTests.swift` (owner/ownerId, deviceId/deviceAssetId, token per the
      T002 inventory); the simplified v3 error envelope still yields a usable message where the
      client reads one (110's key↔slug discrimination). Mostly proves the narrow models already
      tolerate it — fix whatever red reveals (FR-130-08, SC-130-05).

---

## Phase 7: Cache & Rotation Fold-in (no dangling) 🧩

**Purpose**: close every way v3 touches the 320 cache/snapshot layer — explicitly, with tests —
so nothing is left implied. Depends on the T008 pager and the T002 order decision.

- [x] T018 [Cache] **Apply the T002 order decision (resolved: date order).** Pass the album's
      `order` (default `desc`) into the metadata search so ordering matches the album's prior
      display order (research.md §2). Update the "Sequential is album order" wording — the comment
      at `SlideshowViewModel.swift:49`, the `.sequential` wording in `RotationReconciler.swift`,
      and the **"Sequential" definition in `specs/500-display-options/spec.md`** — to "capture-date
      order (album's `order`, default newest-first)". Doc/wording tweak, not a behavior change;
      confirm the exact match on M2. Shared-link sources keep whatever order `/me.assets` returns.
- [x] T019 [Cache] Red+Green: offline/snapshot fold-in in
      `…/SlideshowKitTests/SlideshowOfflineTests.swift` — drive playback through the **v3
      metadata-search pager** (StubImmichAPI returns v3-shaped assets incl. `type`): the
      snapshot saved via `markRefreshSucceeded` round-trips, an offline relaunch plays from
      disk in the pinned base order, and the `type == "IMAGE"` filter + snapshot survive the v3
      asset shape. Proves FR-320-06/07/08 stay green through the new fetch. **Engine — inline.**
- [x] T020 [Cache] Confirm-only (no production code): the disk **image-byte** cache is
      v3-agnostic — thumbnail/preview/original endpoints are unchanged and `DiskImageCache` is
      keyed by asset id + variant. Close the loop by running `DiskImageCacheTests` +
      `ImageCacheTests` green post-migration; note the confirmation in `research.md` so the
      cache question is *answered*, not assumed.

**Checkpoint**: `swift test` green across all three packages — 320's offline/cache guarantees
hold through the v3 fetch, and rotation order is documented, not accidental.

---

## Phase 8: Polish & Verification Gate

- [x] T021 [P] Privacy/robustness (FR-130-11): grep the 130 diff — the shared-link password
      never appears in a URL/query/log; no secrets; the version string is non-secret.
- [x] T022 App wiring in `Immich Slideshow/Immich_SlideshowApp.swift` — update the stub
      `serverVersion()` (currently `"1.0.0"`) and the share-link stub to v3 shapes so previews/
      UITests don't trip the new gate; add the calm **"needs Immich v3 or newer (detected vX)"**
      notice to the app's connection/onboarding surface (dead-ends playback) with accessibility
      IDs (depends on T014).
- [ ] T023 **DEFERRED** — dedicated onboarding too-old UITest (`Immich SlideshowUITests/`, stubbed
      v2 server via `--uitest` seam → upgrade notice, no advance). Logic is covered by unit
      (`submitConnectionBlocksPreV3ServerWithUpgradeNotice`, `connectionSettingsRejectsPreV3Server`)
      + app-integration tests, and the notice renders through existing error surfaces which the
      full XCUITest suite exercised without regression. Follow-up only.
- [x] T024 Verification gate (Claude-owned): XcodeBuildMCP `build_sim` + `test_sim` **whole
      classes** on the app scheme (memory `xcodebuildmcp-single-test-false-green`,
      `sim-build-destination`); **full XCUITest** before merge — SwiftUI touched (memory
      `run-full-xcuitest-before-merge`).
- [x] T025 [P] Docs: add 130 to `docs/spec-traceability.md` (FR/SC → tests); flip
      `specs/130-immich-api-v3/spec.md` Status → Implemented; flip the 130 row in
      `docs/spec-overview.md` → Active; reflect the T018 order amendment in the 500 spec if one
      was made; check off this file's boxes.

---

## Dependencies & Execution Order

### Phase Dependencies

- **Phase 1** first; **T002 blocks all red tests** (fixtures encode the pinned contract).
- **Phase 2** after T002: T004→T005; T003, T006 parallel to each other and to T004.
- **Phase 3 (US1)** after T006 (+T007 red first).
- **Phase 4 (US2)** after T002 (contract) + red T009.
- **Phase 5 (US3)** after T005 (gate) and T003 (error): T011→T012; T013→T014; T015→T016.
  T012 must land before T016 (refresh relies on terminal classification).
- **Phase 6 (US4)** after T002's removed-field inventory; independent of US1–US3 code.
- **Phase 7 (Cache)** after T008 (pager) **and** T002's order decision (T018 applies it).
- **Phase 8** after Phases 3–7; T023 after T022; T024 last before merge.

### Parallel Opportunities

- T003 ∥ T004 ∥ T006 (different files). T021 ∥ T025 in polish.
- US2 (Phase 4) is independent of US1/US3 and can proceed in parallel once T002 lands.
- No Codex delegation (disabled) — parallelism is within-session only.

---

## Implementation Strategy

### MVP first (US1 + US3)

The minimum that makes the app a correct v3 citizen: **US1** (photos actually load on v3) +
**US3** (a v2 server says "upgrade" instead of showing a black screen). Ship-blocking pair.
**STOP and VALIDATE** on the host suites before US2/US4.

### Incremental delivery

US1 (asset fetch) + US3 (gate) → US2 (password shared links) → US4 (decode tolerance) →
**Phase 7 cache/rotation fold-in** (the "nothing dangling" gate: order semantics applied,
snapshot/offline proven through the v3 pager, image cache confirmed untouched) → Phase 8 gates
→ merge. Release timed so v3 is the norm (spec Status).

### Live validation (the build loop) — two checkpoints, not one

Fixtures are frozen from the published v3.0.2 spec (T002 done), so the host suites are the
correctness gate and **no live server is needed to build**. Live runs then confirm the wire:

- **M1 — point the built app at the live v2 server**: `GET /server/version` → major 2 →
  `serverTooOld` → onboarding shows the upgrade notice, no advance. This *is* US3's end-to-end
  acceptance test — **failing to load is the expected pass.** It exercises the gate only, **not**
  US1/US2 wire (mock fixtures cover those meanwhile).
- **M2 — after upgrading the server to rc2/v3**: validate US1 (real album load via search/metadata),
  US2/T008a (real shared-link resolve incl. password + `/me.assets`), and settle the two deferred
  shared-link questions (password-refresh cookie-vs-relogin; whether `?key=` still authorizes
  shared image bytes — the 320 disk-image path depends on it). rc2 passes the gate (numeric-major
  parse tolerates the `-rc.2` suffix).

---

## Notes

- Commit after each red+green pair; stage with explicit paths, never `-A`.
- **No v2 fallback anywhere** — if a task tempts a compatibility branch, stop: the baseline is
  v3-only (FR-130-01).
- The 320 offline/cache suites are the regression guard — if any of them needs modification
  beyond the intended order-semantics update (T018), that is a design smell: stop and re-check
  (the snapshot is meant to ride `assets(albumID:)` transparently).
- Whenever a wire detail is uncertain, it belongs in T002's contract against the running v3
  server's OpenAPI — never guessed from tutorials (topic 100 standing rule).
