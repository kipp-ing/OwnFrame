# Implementation Plan: Immich API v3 Baseline (drop v2)

**Branch**: `130-immich-api-v3` (branch off `main`) | **Date**: 2026-07-10 | **Spec**:
[spec.md](./spec.md)

**Input**: Feature specification from `specs/130-immich-api-v3/spec.md`

## Summary

Move `ImmichClient` to a v3-only baseline via three surgical changes plus one new gate, all
behind the existing `ImmichAPI` protocol and injected transport, so the app target, onboarding,
and slideshow engine keep their current seams:

1. **Album assets → metadata search.** Reimplement `ImmichClient.assets(albumID:)` to page
   `POST /api/search/metadata` (album filter, `page`/`size`, follow the next-page signal until
   exhausted) instead of decoding an `assets` array from `GET /api/albums/{id}` (removed in v3).
   New request/response DTOs live in `Models.swift`. The method signature (`[Asset]`) is
   unchanged, so every caller (SlideshowKit, OnboardingKit) is untouched.
2. **Shared-link password → request body.** Change `SharedLinkResolver` to carry the password in
   a `POST /api/shared-links/login` body rather than a `?password=` query item; keep the
   key↔slug fallback and the no-password GET path. Exact endpoint sequence pinned in `research.md`.
3. **Version gate.** `serverVersion()` already returns `major.minor.patch`; add a parsed
   supported-major check and a new terminal `ImmichError.serverTooOld(version:)`. OnboardingKit
   runs the gate at connect and maps the error to an upgrade-notice state; `RetryPolicy`
   classifies `serverTooOld` as terminal so topic 310's refresh surfaces the notice without a
   retry storm.
4. **Decode tolerance.** Ensure the removed v3 fields (`owner`/`ownerId`, `deviceId`/
   `deviceAssetId`, `token`) are never required and the simplified error envelope still yields a
   message where the client reads one — mostly already true (the app decodes narrow models), so
   this is a fixture-driven verification, not a rewrite.

Everything is exercised on the host against the mock transport with v3 fixtures; no v2
compatibility code is added anywhere.

## Technical Context

**Language/Version**: Swift 6

**Primary Dependencies**: Foundation (URLSession/JSON), Swift Testing; existing packages
ImmichClient (all wire changes), OnboardingKit (connect-time gate + notice), SlideshowKit
(`RetryPolicy` terminal classification + refresh surface). No new external dependencies.

**Storage**: None new. No UserDefaults keys, no cache changes. The shared-link password remains
transient/keychain-scoped per constitution III — only its transport location changes (query →
body).

**Testing**: Swift Testing on the host (`swift test` in `Packages/ImmichClient`,
`Packages/OnboardingKit`, `Packages/SlideshowKit`) against the injected mock transport with v3
JSON fixtures: multi-page metadata-search, empty album, shared-link login (with/without
password, wrong password, key↔slug fallback), version endpoint (major 2 / 3 / RC suffix /
malformed / unreachable), and decode-tolerance payloads. XcodeBuildMCP `test_sim` (whole
classes) for the app target; onboarding upgrade-notice verified by SwiftUI preview + one
XCUITest per house rules. This is the primary verification gate (owned by Claude).

**Target Platform**: iPadOS 26+ (iPhone optional); no API newer than the current floor is used —
same posture as the rest of the client.

**Project Type**: Mobile app (SwiftUI, MVVM with `@Observable`), Swift Package Manager modules.

**Performance Goals**: album-asset paging adds network round-trips only for large albums and runs
off the display path (fetch happens before/around playback, never blocking a slide transition —
SC-300-03 continues to hold). The version gate is one cheap public GET at connect and folds into
the existing refresh cycle.

**Constraints**: no v2 fallback (FR-130-01); album order must be stable and documented
(FR-130-02 + Assumptions — resolved in `research.md`); password never in a query/URL/log
(FR-130-03/11); the gate fires only on a confidently parsed major < 3 (FR-130-09); every path
mock-testable with no real server (FR-130-10); `x-api-key`/`?key=` auth unchanged.

**Scale/Scope**: one package does the wire work (ImmichClient: ~3 files touched + DTOs), two
packages consume the gate (OnboardingKit connect + notice UI, SlideshowKit `RetryPolicy` +
refresh surface), plus app-target stub updates; ~4 host test suites extended/added.

## Constitution Check

*GATE: Must pass before Phase 0 research. Re-check after Phase 1 design.*

- **I. Test-First (NON-NEGOTIABLE)**: PASS — every slice is red-first on the host with v3
  fixtures: metadata-search paging (multi-page + empty), shared-link login (body password, no
  query password, wrong password, key↔slug fallback), version gate (major 2/3/RC/malformed/
  unreachable), decode tolerance for removed fields. Onboarding notice verified by preview +
  UITest.
- **II. Modular Isolation**: PASS — all wire changes sit behind `ImmichAPI` + the injected
  `HTTPTransport`; the version gate is a pure function over a parsed version plus a new error
  case. No real server, no hidden singletons.
- **III. No Secrets in Plaintext (NON-NEGOTIABLE)**: PASS — moving the shared-link password from
  the URL query into a POST body **reduces** leak surface (no secret in a URL that could be
  logged or cached); the password still never touches logs or UserDefaults, and the keychain
  store is unchanged.
- **IV. Transport-Layer Security**: PASS — no transport/TLS change; still standard HTTPS
  validation, no TLS-disable path. Same URLSession posture.
- **V. Respect Platform Boundaries**: PASS — no platform-behavior change; purely API-shape work.
- **VI. Verifiable Acceptance Criteria**: PASS — SC-130-01…06 map to deterministic mock-transport
  tests (captured requests, decoded lists, error categories) plus one onboarding UITest.
- **VII. Plain and Light by Default**: PASS — v3 users see no new behavior; the only added
  surface is one calm "needs Immich v3+" notice on the rare too-old server. No v2 clutter, no
  toggles.

**Result**: PASS — no violations; Complexity Tracking left empty.

## Project Structure

### Documentation (this feature)

```text
specs/130-immich-api-v3/
├── spec.md                       # This feature's spec
├── plan.md                       # This file
├── research.md                   # Phase 0 — v3 wire unknowns (below): metadata-search shape +
│                                  #   album-order preservation, shared-link login/`me` sequence,
│                                  #   public version endpoint, removed-field inventory
├── data-model.md                 # Phase 1 — MetadataSearch req/resp DTOs, version gate value,
│                                  #   shared-link login DTOs, serverTooOld error
├── quickstart.md                 # Phase 1 — validation scenarios mapped to FR/SC
├── contracts/
│   └── immich-v3-api.md          # Phase 1 — exact endpoints, bodies, auth, paging contract
└── tasks.md                      # Phase 2 (/speckit-tasks)
```

### Source Code (repository root)

```text
Packages/ImmichClient/Sources/ImmichClient/
├── ImmichClient.swift            # assets(albumID:): replace GET /api/albums/{id}.assets with a
│                                  #   POST /api/search/metadata pager (album filter, page/size,
│                                  #   follow next-page). Add a parsed supported-version check on
│                                  #   top of serverVersion(). makeRequest gains a JSON-body POST
│                                  #   path (auth header/?key= preserved).
├── Models.swift                  # NEW DTOs: MetadataSearchRequest (albumIds, page, size),
│                                  #   SearchResponse (assets.items: [Asset], nextPage). Confirm
│                                  #   Album/Asset/AssetDetail stay tolerant of removed fields
│                                  #   (owner/deviceId/token) — they already decode narrow models.
├── SharedLinkResolver.swift      # password → POST /api/shared-links/login body (never query);
│                                  #   keep key↔slug fallback + no-password GET path; adapt to the
│                                  #   v3 login/me sequence pinned in research/contracts.
├── ImmichError.swift             # + case serverTooOld(version: String)  (stays Equatable)
├── ImmichAPI.swift               # UNCHANGED signatures (assets still -> [Asset]); optionally a
│                                  #   small supported-version helper if surfaced to callers.
└── ServerConfig.swift            # UNCHANGED (apiKey/shareKey auth kinds persist in v3)

Packages/ImmichClient/Tests/ImmichClientTests/
├── ImmichClientTests.swift       # + metadata-search paging (multi-page + empty), version-gate
│                                  #   parse/classify (2/3/RC/malformed/unreachable), decode
│                                  #   tolerance for removed fields; v3 fixtures.
└── SharedLinkResolverTests.swift # + password-in-body, no-query-password assertion, wrong
                                   #   password, key↔slug fallback on v3.

Packages/OnboardingKit/Sources/OnboardingKit/
├── OnboardingViewModel.swift     # run the version gate at connect; map serverTooOld -> the
│                                  #   upgrade-notice state; do not advance on too-old.
└── <connection step view>.swift  # render the "needs Immich v3+ (detected vX)" notice (calm,
                                   #   dead-ends playback). Exact view identified during Phase 1.

Packages/SlideshowKit/Sources/SlideshowKit/
└── RetryPolicy.swift             # classify ImmichError.serverTooOld as terminal (non-retryable),
                                   #   alongside unauthorized/shareLinkExpired/wrong/required.
                                   #   Refresh path surfaces the notice instead of looping.

OwnFrame/
└── OwnFrameApp.swift     # update the preview/stub serverVersion() (currently "1.0.0")
                                   #   and any share-link stub to the v3 shapes so previews/UITests
                                   #   don't trip the new gate.

OwnFrameUITests/
└── <onboarding suite>.swift      # + one flow: too-old server -> upgrade notice shown, no advance
                                   #   (hermetic --uitest seams).
```

**Structure Decision**: All v3 wire work stays inside `ImmichClient`, behind the `ImmichAPI`
protocol and the injected `HTTPTransport`, so no consumer signature changes — `assets(albumID:)`
still returns `[Asset]`, and the new `serverTooOld` error travels the same channel the existing
categories already use. The version gate is deliberately split: **detection** lives in
ImmichClient (a pure function over the parsed version), **policy** lives where the decision
matters — OnboardingKit blocks the connect flow, and SlideshowKit's `RetryPolicy` marks it
terminal so topic 310's refresh loop surfaces the notice instead of hammering a server it can
never satisfy. This mirrors how the client already reports `unauthorized`/`shareLinkExpired` and
lets those two consumers decide UX, keeping ImmichClient free of view concerns.

## Phase 0 — Research (open v3 wire questions)

These MUST be answered against the running v3 server's OpenAPI (per topic 100's standing
assumption) before the red tests are frozen, because the fixtures encode them:

1. **Metadata-search shape & album filter** — exact body field for the album filter
   (`albumIds: [UUID]` vs `albumId`), `page`/`size` semantics, and the next-page signal
   (`assets.nextPage` value/null). Fixtures depend on this.
2. **Album-order preservation** (the sharp one) — can `POST /api/search/metadata` return an
   album's assets in **album order**, or only by capture date? If not album order, define the
   stable base order (date-descending) and reconcile topic 500's "Sequential" option against it
   (spec amendment recorded, not a silent change).
3. **Shared-link v3 auth sequence** — does `/api/shared-links/me` survive the "remove my shared
   link dto" refactor? Is the flow `POST /shared-links/login` (body: key/slug + password) →
   cookie/token → resolve, or does login return the link directly? Pin the exact request/response
   and how the key↔slug fallback maps onto it.
4. **Public version endpoint** — confirm `GET /api/server/version` needs no auth, so the gate
   fires for shared-link-only onboarding.
5. **Removed-field inventory** — confirm the full set of dropped/renamed fields on the DTOs the
   app decodes (Album, Asset, AssetDetail/exif, shared-link) so decode-tolerance fixtures are
   complete and no field the app actually reads was removed.

## Complexity Tracking

> No constitution violations — section intentionally empty.
