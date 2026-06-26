# Human-Test & Validation Findings — 210 Shared-Link Onboarding

Records the `quickstart.md` A–F validation pass and the cross-cutting checks (T036/T039), plus the
items that remain device-gated. Automated rows are covered by host (`swift test`) or XCUITest suites
run via XcodeBuildMCP; **full XCUITest suite: 52 passed / 0 failed** (2026-06-26, pinned iOS 26.5 iPad
sim).

## Quickstart A–F coverage

| Group | Covered by | Status |
|-------|-----------|--------|
| **A** Shared-link-only onboarding (US1) | `SharedLinkOnboardingUITests` (choice → non-protected/protected/invalid), `StartupGateTests`, `OnboardingViewModelTests` | ✅ green |
| **B** iOS Share Sheet (US2) | `ShareSheetIncomingUITests` (prefill / add+activate / invalid), `PendingSharedLinkStoreTests`, `IncomingSharedLinkTests`, `ShareLinkExtractionTests` | ✅ green (host + UI); real system-sheet round trip is device-gated → see below |
| **C** Searchable + subscrollable picker (US3) | `AlbumSearchTests` (predicate), `AlbumSearchUITests` (portrait + landscape, no-results, pinned action) | ✅ green |
| **D** Ask-password-only-when-needed (US4) | `SharedLinkPasswordUITests` (onboarding + Settings × non-protected / protected-wrong-then-correct), `SourceLibraryViewModelTests` | ✅ green |
| **E** Onboarding descriptions (US5) | `OnboardingDescriptionsUITests` (choice / shared-link / connection / source+confirm) | ✅ green |
| **F1** No secret in UserDefaults / App Group / logs | T036 audit (below) | ✅ verified |
| **F2** New flows run against fakes | host tests use injected protocols + in-memory fakes (`InMemory*Store`, `MockTransport`) | ✅ green |
| **F3** Album metadata vs running-server OpenAPI | T003 — **device/live-server-gated**, pending | ⏳ pending |

## Manual-test findings (2026-06-26) — fixed this pass

| # | Finding | Fix | Verification |
|---|---------|-----|--------------|
| F1 | Non-protected `/share/<key>` links wrongly prompted for a password | Resolver resolves **key-first, slug-fallback** + message-aware 401 classification | `SharedLinkResolverTests` (41 green) + **live** Immich 2.7.5: `?key=<key>` → 200 `"password":null`, `?slug=<key>` → 401 `"Invalid share key"`, password on non-protected → 400 |
| F2 | Album picker differed between onboarding and Settings | One shared `AlbumPickerView`; Settings rewired to select-then-confirm | `AlbumSearchUITests` + `SourceLibraryUITests.testSettingsAlbumPickerSearchesAndSelectThenConfirm` |
| F3 | No Back in onboarding (had to kill the app) | `OnboardingViewModel.back()`/`canGoBack` + Back affordance | `OnboardingViewModelTests` (7) + `OnboardingBackUITests` (3) |

## T036 — secret-hygiene audit (SC-210-06, Constitution III)

Grep-audited 2026-06-26; **clean**:
- No `UserDefaults` write of an API key / password / token anywhere in the app, extension, or packages.
- Share Extension (`ShareViewController`) writes **only** `url.absoluteString` to the App Group
  (`group.ing.kipp.Immich-Slideshow`, key `pendingSharedLinkURL`); the host consumes once and removes it.
- `SourceKind.sharedLink` persists only `(baseURL, slug)` — no password in the source library JSON.
- `ConfigStore` persists only base URL / album id; the API key lives in `KeychainStore`, shared-link
  passwords in `KeychainSharedLinkSecretStore` (`SecItem*`, service `de.kippings.ImmichSlideshow.sharedLinkPassword`).
- No `print`/`NSLog`/`os_log`/`Logger` of any secret. The resolved bearer key is re-resolved per launch,
  never persisted.

## Device-gated — still pending (need hardware / live server)

- **T025** — real iOS **Share Sheet** round trip on a device: share an Immich link from Safari/Photos
  into ImmichSlideshow, confirm it pre-fills (unconfigured) or adds+activates (configured). The system
  Share Sheet cannot be driven by XCUITest; the App-Group hand-off and routing are host-tested, the
  end-to-end sheet is not. **Not yet run on device.**
- **T003 / F3** — confirm `assetCount` / `startDate` / `endDate` field names against the running
  server's OpenAPI (`/api/server/version`). Implemented against the documented Immich `AlbumResponseDto`;
  **not yet re-checked live.**
