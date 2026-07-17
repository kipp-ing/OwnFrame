# Spec Traceability

Generated for the active topic specs on 2026-06-23. This maps functional requirements to existing tests and flags gaps/drift only; no code or spec changes were made.

> **Reconciliation outcome (2026-06-23).** The gaps/drift below were resolved during the spec
> overhaul. The per-FR tables remain a useful FR→test index, but the "Gaps" and "Drift" sections
> at the bottom are a *historical snapshot* — they have since been addressed:
> - **Code drift fixed:** FR-200-02 (startup now resumes at album selection when URL+key exist but
>   the album is missing — `StartupGate.loadBaseURL` path).
> - **Spec corrected:** FR-700-08 (pause/play uses HA `ON`/`OFF` switch payloads); HA brightness +
>   album-select moved from deferred `710`/`720` to **Active** (FR-700-13/14) since they are built.
> - **Host-unit tests added** for built behavior: FR-200-07, FR-400-12, FR-600-08/10/13, FR-700-12,
>   FR-300-04/500-04 (host-testable parts). Render-layer options (Ken Burns, Fit) and other UI
>   behaviors are covered by the XCUITest suite, not host tests.
> - **Deferred to Roadmap** (not built; now recorded in each spec's `Roadmap / Deferred`):
>   FR-300-08 disk cache + Clear, FR-300-11 auto-retry backoff, FR-300-12 periodic refresh,
>   FR-300-29 clock renderer, and the Settings shared-link placeholder part of FR-200-25.
>
> The live source of truth is each `specs/Nxx-*/spec.md`; this file is a point-in-time aid.

Status values: `covered` means existing tests exercise the requirement directly enough for the current scope, `partial` means tests cover only part of the requirement or the code path is split across app UI and package logic, and `missing` means no existing test was found or the behavior is not implemented.

## 100 - ImmichClient

| FR | Requirement (short) | Covering test(s) | Status | Testability |
|---|---|---|---|---|
| FR-100-01 | Accept HTTPS base URL and API key config | `Packages/ImmichClient/Tests/ImmichClientTests/FoundationTypesTests.swift` `serverConfigStoresBaseURLAndAPIKey` | covered | host-unit |
| FR-100-02 | Send `x-api-key` on requests | `AlbumTests.swift` `albumsSendsGetRequestWithAPIKeyHeader`; `AssetTests.swift` `assetsFetchesImagesViaMetadataSearchWithAPIKeyHeader`; `PreviewTests.swift` `previewSendsGetRequestWithPreviewSizeQueryAndReturnsRawData`, `thumbnailSendsGetRequestWithThumbnailSizeQueryAndReturnsRawData`; `OriginalEndpointTests.swift` `originalSendsGetRequestWithoutSizeQueryAndReturnsRawData`; `AssetInfoTests.swift` `assetInfoSendsGetRequestWithAPIKeyHeaderAndReturnsDecodedInfo`; `ServerVersionTests.swift` `serverVersionReturnsVersionStringAndSendsGetRequest` | covered | host-unit |
| FR-100-03 | Fetch album list with ID/name | `AlbumTests.swift` `albumJSONDecodesAlbumNameAsName`, `albumsSendsGetRequestWithAPIKeyHeader` | covered | host-unit |
| FR-100-04 | Fetch album image assets with display metadata | `AssetTests.swift` `assetsFetchesImagesViaMetadataSearchWithAPIKeyHeader` (v3 metadata-search, 130); `AssetInfoTests.swift` `assetInfoSendsGetRequestWithAPIKeyHeaderAndReturnsDecodedInfo` | covered | host-unit |
| FR-100-05 | Fetch preview by default | `PreviewTests.swift` `previewSendsGetRequestWithPreviewSizeQueryAndReturnsRawData`; `OriginalEndpointTests.swift` `originalProtocolDefaultDelegatesToPreview`; `SlideshowKit/QualitySelectionTests.swift` `previewQualityLoadsPreviewBytesWithoutOriginalFetch` | covered | host-unit |
| FR-100-06 | Map HTTP 401 to unauthorized | `ErrorTests.swift` `albumsMapsUnauthorizedStatusToUnauthorizedError`; `OriginalEndpointTests.swift` `originalMapsUnauthorizedStatusToUnauthorizedError` | covered | host-unit |
| FR-100-07 | Map network failure to unreachable | `ErrorTests.swift` `albumsMapsURLErrorToUnreachableError`; `ServerVersionTests.swift` `serverVersionMapsURLErrorToUnreachable` | covered | host-unit |
| FR-100-08 | Empty album returns empty list | `AssetTests.swift` `assetsReturnsEmptyArrayForAlbumWithoutAssets` | covered | host-unit |
| FR-100-09 | Preserve album IDs/names | `AlbumTests.swift` `albumJSONDecodesAlbumNameAsName`; app-hosted `Immich_SlideshowTests.swift` `albumsDecodeAlbumNameAsName` | covered | host-unit |
| FR-100-10 | Malformed response is invalid-response, not crash | `ErrorTests.swift` `albumsMapsNonSuccessStatusToInvalidResponseError`, `albumsMapsUndecodableBodyToInvalidResponseError`; `ServerVersionTests.swift` `serverVersionMapsInvalidResponseToInvalidResponse` | covered | host-unit |
| FR-100-11 | Fully mock-transport testable | `FoundationTypesTests.swift` `mockTransportReturnsConfiguredResponseAndRecordsRequest`, `mockTransportThrowsConfiguredErrorAndRecordsRequest` plus all `MockTransport` client tests | covered | host-unit |
| FR-100-12 | Normal HTTPS/TLS validation, no TLS-disable path | — | missing | manual |
| FR-100-13 | Explicit original-quality fetch | `OriginalEndpointTests.swift` `originalSendsGetRequestWithoutSizeQueryAndReturnsRawData`; `SlideshowKit/QualitySelectionTests.swift` `originalQualityLoadsOriginalBytesWithoutPreviewFetch` | covered | host-unit |
| FR-100-14 | Cheap thumbnail fetch | `PreviewTests.swift` `thumbnailSendsGetRequestWithThumbnailSizeQueryAndReturnsRawData` | covered | host-unit |

## 200 - Connection & Onboarding

| FR | Requirement (short) | Covering test(s) | Status | Testability |
|---|---|---|---|---|
| FR-200-01 | Startup detects complete config before skipping onboarding | `Packages/OnboardingKit/Tests/OnboardingKitTests/StartupGateTests.swift` `startupGateReturnsDoneForConnectionAndActiveSource`, `startupGateReturnsConnectionWithoutAPIKey`, `startupGateMigratesLegacySelectedAlbumIDToDone`; `ConfigStoreTests.swift` load/partial URL tests | covered | host-unit |
| FR-200-02 | Resume first missing step; do not unlock partial setup | `StartupGateTests.swift` `startupGateReturnsConnectionWithoutConfigAndWithoutAPIKey`, `startupGateReturnsConnectionWithoutBaseURL`, `startupGateReturnsSourceWhenConnectedButLibraryEmpty` | covered | host-unit |
| FR-200-03 | Combined URL/API-key screen with one Continue | `Immich SlideshowUITests/Immich_SlideshowUITests.swift` `testFreshLaunchShowsConnectionStep`, `testOnboardingHappyPathReachesSlideshow` | covered | ui-sim |
| FR-200-04 | Continue disabled until URL and key non-empty | — | missing | ui-sim |
| FR-200-05 | Validate well-formed HTTPS before network | `OnboardingViewModelTests.swift` `rejectsNonHTTPSURL`; `ConnectionSettingsViewModelTests.swift` `connectionSettingsRejectsMalformedURL` | covered | host-unit |
| FR-200-06 | Validate reachability/auth in one action | `OnboardingViewModelTests.swift` `advancesToSourceWhenReachableAndAuthorized` | covered | host-unit |
| FR-200-07 | Preserve values and classify validation failures | `OnboardingViewModelTests.swift` `staysWhenServerUnreachable`, `staysWhenUnauthorized`, `staysWhenKeychainSaveFails`; invalid-response classification not directly covered | partial | host-unit |
| FR-200-08 | API key only in Keychain, never plaintext | `Immich SlideshowTests/OnboardingKeychainTests.swift` `keychainStoreRoundTripsSaveReadDelete`; `ConnectionSettingsViewModelTests.swift` `connectionSettingsPrefillsStoredConnectionWithoutExposingStoredKey` | partial | manual |
| FR-200-09 | Persist server URL (and album source) in non-secret storage | `ConfigStoreTests.swift` `userDefaultsConfigStoreLoadsSavedConfiguration`, `userDefaultsConfigStoreSaveBaseURLPersistsBaseURLWithoutSelectedAlbum`; `OnboardingViewModelTests.swift` `finishWithActiveAlbumSourcePersistsConfigurationAndCompletes` | covered | host-unit |
| FR-200-10 | Load live albums; require one source (album or shared link, 120) | `OnboardingViewModelTests.swift` `advancesToSourceWhenReachableAndAuthorized`, `finishWithActiveAlbumSourcePersistsConfigurationAndCompletes`; `Immich_SlideshowUITests.swift` `testOnboardingHappyPathReachesSlideshow` | covered | host-unit |
| FR-200-11 | Empty album list is clear, not dead end (now advances to add-source, 120) | `OnboardingViewModelTests.swift` `advancesToSourceEvenWhenAlbumListEmpty` | covered | host-unit |
| FR-200-12 | Settings shows URL and key-set indicator without key | `ConnectionSettingsViewModelTests.swift` `connectionSettingsPrefillsStoredConnectionWithoutExposingStoredKey` | covered | ui-sim |
| FR-200-13 | Settings edits URL/key independently with secure key entry | `ConnectionSettingsViewModelTests.swift` `connectionSettingsURLOnlyChangeUsesStoredKeyAndDoesNotWriteKeychain`, `connectionSettingsPersistsNewURLAndKeyWhenSelectedAlbumStillExists` | partial | ui-sim |
| FR-200-14 | Save validates before persistence; malformed URL client-side | `ConnectionSettingsViewModelTests.swift` `connectionSettingsRejectsMalformedURL`, `connectionSettingsDoesNotPersistUnauthorizedConnection`, `connectionSettingsDoesNotPersistUnreachableConnection` | covered | host-unit |
| FR-200-15 | Failed edit persists nothing; prior connection active | `ConnectionSettingsViewModelTests.swift` `connectionSettingsDoesNotPersistUnauthorizedConnection`, `connectionSettingsDoesNotPersistUnreachableConnection`, `connectionSettingsDoesNotPersistConfigWhenKeychainSaveFails` | covered | host-unit |
| FR-200-16 | Successful edit persists atomically and running slideshow adopts | `ConnectionSettingsViewModelTests.swift` `connectionSettingsPersistsNewURLAndKeyWhenSelectedAlbumStillExists`; app adoption callback has no direct UI test | partial | ui-sim |
| FR-200-17 | Cancel/dismiss editor has no side effects | — | missing | ui-sim |
| FR-200-18 | Connection editor reachable from Settings and error recovery | Settings reachability covered by `SettingsUITests.swift` `testConnectionAndMqttAppearAsCollapsedSections`; error recovery path not directly tested | partial | ui-sim |
| FR-200-19 | Missing selected album prompts reselection, not onboarding | `ConnectionSettingsViewModelTests.swift` `connectionSettingsReturnsAlbumMissingAfterPersistingWhenSelectedAlbumIsAbsent` | covered | host-unit |
| FR-200-20 | Broker section surfaced from Settings only | `Immich SlideshowUITests/SettingsUITests.swift` `testConnectionAndMqttAppearAsCollapsedSections`; `BrokerSetupUITests.swift` broker editor tests | covered | ui-sim |
| FR-200-21 | Connection/Broker collapsed by default; display/brightness remain owned elsewhere | `SettingsUITests.swift` `testConnectionAndMqttAppearAsCollapsedSections`, `testSettingsShowsBrightnessAndPlannedOptionsAndDismisses`; `SettingsDisplayOptionsUITests.swift` display option tests | covered | ui-sim |
| FR-200-22 | All Settings sections reachable by scrolling | `SettingsUITests.swift` `testBottomSettingsSectionReachableInBothOrientations`; missing reduced-width and keyboard-open variants | partial | ui-sim |
| FR-200-23 | Reset dialog only reset/cancel, no broker setup | — | missing | ui-sim |
| FR-200-24 | Reset clears URL, album, key and returns connection step | `OnboardingViewModelTests.swift` `resetReturnsToConnectionAndClearsLibrary`; app-hosted `OnboardingResetTests.swift` `resetClearsRealConfigAndKeychainAndReturnsToConnection` | covered | host-unit |
| FR-200-25 | Shared-link source in onboarding and Settings (placeholder replaced by the real feature in 120) | `Immich SlideshowUITests/SourceOnboardingUITests.swift` `testOnboardingAddSharedLinkSourceReachesSlideshow`; Settings via `SourceLibraryUITests.swift` | covered | ui-sim |
| FR-200-26 | No new Immich backend behavior/endpoints | — | missing | manual |
| FR-200-27 | Dependencies injected behind protocols | `OnboardingViewModelTests.swift`, `ConnectionSettingsViewModelTests.swift`, `StartupGateTests.swift`, and `ConfigStoreTests.swift` all use fakes/injected stores | covered | host-unit |

## 300 - Slideshow

| FR | Requirement (short) | Covering test(s) | Status | Testability |
|---|---|---|---|---|
| FR-300-01 | Start fullscreen with only image visible | `Immich SlideshowUITests/SlideshowChromeUITests.swift` `testChromeHiddenByDefaultAndRevealsOnTap` | covered | ui-sim |
| FR-300-02 | Load configured single album through topic 100 | `Packages/SlideshowKit/Tests/SlideshowKitTests/SlideshowViewModelTests.swift` `startShowsFirstImageAssetAndFiltersVideos`, `switchAlbumLoadsNewAlbumAndExposesCurrentAlbumID` | covered | host-unit |
| FR-300-03 | One image, timed advance, transition, loop | `SlideshowViewModelTests.swift` `manualTickAdvancesExactlyOneImageAndWraps`, `singleImageAlbumRemainsStableOnTick`; `TransitionMappingTests.swift` transition tests | covered | host-unit |
| FR-300-04 | Consume topic 500 options live | `PlayOrderTests.swift` order tests; `DurationTickerTests.swift` `tickerWaitsCurrentDurationAndReArmsWhenDurationChangesMidShow`; `QualitySelectionTests.swift` quality tests; fit/Ken Burns/clock live rendering only partially covered by UI tests | partial | host-unit |
| FR-300-05 | Shuffle cycle and sequential order | `PlayOrderTests.swift` `sequentialOrderVisitsAlbumOrderAndWraps`, `shuffleShowsEveryPhotoOncePerCycleThenReshuffles`, `switchingOrderMidShowKeepsCurrentPhotoAsAnchor` | covered | host-unit |
| FR-300-06 | Prefetch next one to two images | `SlideshowViewModelTests.swift` `startPrefetchesNextImageWithoutBlockingDisplay`, `advanceUsesPrefetchedImageWithoutAdditionalPreviewCall`, `prefetchWrapsAndRespectsCacheLimitAcrossTicks` | covered | host-unit |
| FR-300-07 | Bounded in-memory cache oldest-first | `ImageCacheTests.swift` `storeEvictsLeastRecentlyStoredEntryWhenLimitIsExceeded`, `dataLookupRefreshesLRUPosition`, `containsDoesNotRefreshLRUPosition` | covered | host-unit |
| FR-300-08 | Disk cache survives relaunch/offline, size limit, clear action | — | missing | host-unit |
| FR-300-09 | Skip one broken image | `SlideshowViewModelTests.swift` `startSkipsInitialPreviewErrorsAndShowsFirstLoadableImage`, `advanceSkipsPreviewErrorAndShowsNextLoadableImage`; total-exhaustion case superseded by 310 (`SlideshowResilienceTests.swift` `imageExhaustionKeepsCurrentImageAndAutoRecovers`) | covered | host-unit |
| FR-300-10 | Empty/fetch failed states with retry | `SlideshowViewModelTests.swift` `emptyAndVideoOnlyAlbumsEnterEmptyPhase`, `assetsErrorFailsAndRetryStartsAgainWhenAssetsRecover`; UI views are not fully simulator-tested | partial | ui-sim |
| FR-300-11 | Auto-retry with backoff | promoted to spec 310 (FR-310-01…05) — see the 310 section below | covered | host-unit |
| FR-300-12 | Periodic source refresh | promoted to spec 310 (FR-310-06…10) — see the 310 section below | covered | host-unit |
| FR-300-13 | Skip videos/Live Photos/non-images | `SlideshowViewModelTests.swift` `startShowsFirstImageAssetAndFiltersVideos`, `emptyAndVideoOnlyAlbumsEnterEmptyPhase` | covered | host-unit |
| FR-300-14 | Foreground-only timer and user pause respected | `SlideshowViewModelTests.swift` `slideshowDoesNotAdvanceWithoutTickAndPauseStopsTickerUntilResume`, `togglePauseStopsTickerAndSurvivesForegroundResume`; no app lifecycle simulator test | partial | ui-sim |
| FR-300-15 | Tap reveals/hides Liquid Glass chrome and controls | `SlideshowChromeUITests.swift` `testChromeHiddenByDefaultAndRevealsOnTap`; second-tap hide not directly tested | partial | ui-sim |
| FR-300-16 | Chrome auto-hides after about 4.5s; interactions reset | `SlideshowChromeUITests.swift` `testChromeAutoHidesWhenIdle`; reset-on-control not directly tested | partial | ui-sim |
| FR-300-17 | Swipes navigate without revealing chrome | `SlideshowChromeUITests.swift` `testSwipeAdvancesWithoutRevealingChrome` | covered | ui-sim |
| FR-300-18 | Play/pause controls auto-advance only | `SlideshowChromeUITests.swift` `testTransportAndPlayPauseToggle`; `SlideshowViewModelTests.swift` `togglePauseStopsTickerAndSurvivesForegroundResume` | covered | host-unit |
| FR-300-19 | Auto-advance forward-only | `SlideshowViewModelTests.swift` `manualTickAdvancesExactlyOneImageAndWraps`, `showPreviousStepsBackwardAndWraps`, `showNextStepsForwardAndResetsTicker` | covered | host-unit |
| FR-300-20 | Album browser sheet with album/photo grids | `Immich SlideshowUITests/AlbumBrowserUITests.swift` `testAlbumBrowserOpensDrillsInAndSelectionReturnsToSlideshow` | covered | ui-sim |
| FR-300-21 | Album browser uses thumbnail endpoint | `Packages/ImmichClient/Tests/ImmichClientTests/PreviewTests.swift` `thumbnailSendsGetRequestWithThumbnailSizeQueryAndReturnsRawData`; no direct album-browser transport assertion | partial | ui-sim |
| FR-300-22 | Thumbnail selection jumps and can switch album | `AlbumBrowserUITests.swift` `testAlbumBrowserOpensDrillsInAndSelectionReturnsToSlideshow`; `SlideshowViewModelTests.swift` `switchAlbumLoadsNewAlbumAndExposesCurrentAlbumID`, `jumpGoesToRequestedAssetAndIgnoresUnknown` | covered | ui-sim |
| FR-300-23 | Unknown asset jump is no-op | `SlideshowViewModelTests.swift` `jumpGoesToRequestedAssetAndIgnoresUnknown` | covered | host-unit |
| FR-300-24 | Info overlay date/location only, updates, empty when absent | `Immich SlideshowUITests/PhotoInfoUITests.swift` `testInfoButtonTogglesDateAndLocationOverlay`; `ImmichClient/AssetInfoTests.swift` `assetInfoWithoutExifFallsBackToLocalDateTimeAndNilLocation`; update/empty overlay not directly tested | partial | ui-sim |
| FR-300-25 | Info overlay excludes filenames, album names, secrets | — | missing | ui-sim |
| FR-300-26 | Settings reachable with live brightness slider | `SettingsUITests.swift` `testSettingsShowsBrightnessAndPlannedOptionsAndDismisses`; `PowerKit/PowerManagerTests.swift` and `BrightnessRampTests.swift` cover owner behavior | covered | ui-sim |
| FR-300-27 | Settings surface display options and disk-cache controls | `SettingsDisplayOptionsUITests.swift` `testOrderAndDurationPersistAcrossRelaunch`, `testTransitionAndKenBurnsPersistAcrossRelaunch`; disk-cache size/clear via `SettingsStorageUITests.swift` (320, 2026-07-09) | covered | ui-sim |
| FR-300-28 | Reset reachable through chrome exit | — | missing | ui-sim |
| FR-300-29 | Clock overlay renders by settings, off by default | `ThemeSettingsDefaultsTests.swift` `themeSettingsDefaultsMatchDisplayOptionsSpec`; settings UI still shows clock as planned placeholder | missing | ui-sim |
| FR-300-30 | English/German localizable UI strings | — | missing | ui-sim |
| FR-300-31 | Slideshow logic injected/testable | SlideshowKit tests use `StubImmichAPI`, `ManualTicker`, `ImageCache`, and injected `ThemeSettingsStore` throughout | covered | host-unit |
| FR-300-32 | UI never reveals/logs secrets | — | missing | manual |

## 310 - Slideshow Resilience *(added 2026-07-09, implemented)*

All host-unit tests live in `Packages/SlideshowKit/Tests/SlideshowKitTests/` —
`RetryPolicyTests.swift`, `RotationReconcilerTests.swift`, and `SlideshowResilienceTests.swift`
(TestClock-driven, no real timers per FR-310-12).

| FR | Requirement (short) | Covering test(s) | Status | Testability |
|---|---|---|---|---|
| FR-310-01 | Auto-retry transient failures with backoff | `SlideshowResilienceTests` `deadServerAtLaunchShowsCalmStateAndAutoRecovers`, `retryWaitsOutTheBackoffDelayBeforeRefetching`, `imageExhaustionKeepsCurrentImageAndAutoRecovers` | covered | host-unit |
| FR-310-02 | 1 s → ×2 → 300 s cap, ±20 % jitter, reset on success | `RetryPolicyTests` (sequence, cap, jitter bounds, reset); `SlideshowResilienceTests` `recoveryResetsTheBackoff` | covered | host-unit |
| FR-310-03 | Keep current image while retrying; calm state only when nothing to show | `imageExhaustionKeepsCurrentImageAndAutoRecovers`, `refreshFailureKeepsStalePlayingAndHandsToRetry` | covered | host-unit |
| FR-310-04 | Manual retry immediate + backoff reset | `manualRetryFiresImmediatelyAndResetsBackoff` | covered | host-unit |
| FR-310-05 | Auth failures: actionable message + cap-only retry | `RetryPolicyTests` `authFailuresRetryAtTheCapFromTheFirstAttempt`, `classifyMaps…`; `authFailureSurfacesActionableReasonAndRetriesAtCapOnly`; UI variant in `SlideshowErrorView` (previews) | covered | host-unit + preview |
| FR-310-06 | Hourly foreground refresh | `hourlyRefreshRefetchesWithoutDisturbingPlayback` | covered | host-unit |
| FR-310-07 | Refresh never interrupts photo/timer/cycle | `hourlyRefreshRefetchesWithoutDisturbingPlayback` (tick wait not re-armed); `RotationReconcilerTests` (no-op, cycle preservation) | covered | host-unit |
| FR-310-08 | Additions per order; removals leave; removed current finishes slot | `sequentialAdditionEntersAtItsAlbumPosition`, `shuffleAdditionJoinsTheCurrentCycle`, `removedAssetLeavesTheRotation`, `removedCurrentPhotoFinishesItsSlotThenIsSkipped`; `RotationReconcilerTests` | covered | host-unit |
| FR-310-09 | Failed refresh keeps stale rotation playing | `refreshFailureKeepsStalePlayingAndHandsToRetry` | covered | host-unit |
| FR-310-10 | Background: no timers; foreground return: stale refresh + overdue retry fire | `backgroundStopsAllTimers`, `staleForegroundReturnRefreshesImmediately`, `freshForegroundReturnKeepsTheOriginalSchedule`, `overduePendingRetryFiresImmediatelyOnForegroundReturn`, `pendingRetryResumesWithItsRemainingDelay`, `userPausedFrameStillRefreshesOnForegroundReturn` | covered | host-unit |
| FR-310-11 | Both source kinds; timers rebind on source switch | `sourceSwitchMidRetryRebindsAllTimers`; source kinds resolve upstream to `api`+`albumID` (by construction) | covered | host-unit |
| FR-310-12 | Injected clock/scheduler, no real timers in tests | `TestClockTests` + the entire resilience suite | covered | host-unit |
| FR-310-13 | No secrets in failure paths | 310 diff carries no logging at all; failure state is typed (`SlideshowFailureReason`) — audit 2026-07-09 | covered | static audit |
| SC-310-01…06 | Measurable outcomes | SC-01 `deadServerAtLaunch…`; SC-02 `sequentialAddition…`/`shuffleAddition…`; SC-03 `removedCurrentPhoto…`; SC-04 `RetryPolicyTests`; SC-05 `hourlyRefresh…`; SC-06 `longRunSoakSurvivesFlapsAndChurn` | covered | host-unit |

## 320 - Disk Image Cache *(added 2026-07-09, implemented)*

Host-unit tests live in `Packages/SlideshowKit/Tests/SlideshowKitTests/` —
`DiskImageCacheTests.swift`, `SourceSnapshotStoreTests.swift`, and `SlideshowOfflineTests.swift`
(real file-backed stores in per-test temp dirs, injected `now`, TestClock-driven engine scenarios).
UI coverage in `Immich SlideshowUITests/SettingsStorageUITests.swift` (hermetic `--uitest` build
with real stores under the sandbox tmp dir).

| FR | Requirement (short) | Covering test(s) | Status | Testability |
|---|---|---|---|---|
| FR-320-01 | Displayed/prefetched photos persist per quality variant | `SlideshowOfflineTests` `shownAndPrefetchedPhotosAreWrittenThroughToDisk`; `DiskImageCacheTests` `roundTripReturnsIdenticalBytesForDistinctQualityKeys` | covered | host-unit |
| FR-320-02 | RAM → disk → network; disk hit repopulates RAM, no network | `diskHitMakesNoNetworkRequestAndRepopulatesRAM` | covered | host-unit |
| FR-320-03 | Byte budget with LRU eviction; usage ≤ budget after store | `usageNeverExceedsBudgetAfterAnyStore`, `fillingPastBudgetEvictsLeastRecentlyStampedFirst`, `readRestampsRecencySoTheOtherEntryIsEvicted`, `usageAccountingMatchesTheFileByteSum` | covered | host-unit |
| FR-320-04 | 500 MB default, fixed steps, smaller budget prunes immediately | `CacheBudgetTests` (steps/default/round-trip); `loweringTheBudgetPrunesImmediately`; picker in `SettingsStorageUITests` `testBudgetSelectionPersistsAcrossRelaunch` | covered | host-unit + ui-sim |
| FR-320-05 | Usage + Clear in Settings; Clear never interrupts the shown photo | `ClearCacheSemanticsTests` `clearingBothStoresMidShowKeepsPlayingAndRefills`; `clearRemovesEveryEntryAndZeroesUsage`; `SettingsStorageUITests` `testClearResetsTheUsageLabelAfterConfirmation` | covered | host-unit + ui-sim |
| FR-320-06 | Snapshot saved on every successful fetch (ids + type only) | `OfflineRelaunchTests` `offlineRelaunchPlaysFromTheRememberedList` (save assert), `launchWithoutASnapshotKeeps310BehaviorVerbatim` (replace assert); `SourceSnapshotStoreTests` round-trip/replace | covered | host-unit |
| FR-320-07 | Launch-fetch failure + snapshot ⇒ play remembered list; 310 recovers | `offlineRelaunchPlaysFromTheRememberedList`, `recoveryAfterSnapshotStartMergesTheLiveList` | covered | host-unit |
| FR-320-08 | Offline rotation across all stored photos (not just RAM) | `wholeAlbumKeepsRotatingOfflineAfterOnePass` | covered | host-unit |
| FR-320-09 | Corrupt ⇒ miss+delete; write failure ⇒ silent degrade | `unreadableEntryIsAMissAndGetsDeleted`, `writeFailureIsSwallowedAndPlaybackNeverNotices`; `SourceSnapshotStoreTests` `corruptSnapshotFileLoadsAsNilAndNeverThrows` | covered | host-unit |
| FR-320-10 | App-private, backup-excluded, no secrets, purge tolerated | `aCreatedRootIsExcludedFromBackup`, `snapshotFileContainsOnlyIdsAndTypes`, `purgedPhotosDegradeToTheCalmErrorState`; 320 diff carries no logging — audit 2026-07-09 | covered | host-unit + static audit |
| FR-320-11 | Disk work off the display path | Write-through is fire-and-forget (`persistToDisk`); `waitForDiskEntry` polling in tests exists *because* stores are async — design-level; no direct latency assertion | covered | host-unit (by construction) |
| FR-320-12 | Injectable root/budget/time; host-testable | Entire `DiskImageCacheTests`/`SourceSnapshotStoreTests`/`SlideshowOfflineTests` run against temp dirs + injected `now`/TestClock | covered | host-unit |
| SC-320-01…06 | Measurable outcomes | SC-01 `wholeAlbumKeepsRotatingOfflineAfterOnePass`; SC-02 `offlineRelaunchPlaysFromTheRememberedList`; SC-03 `usageNeverExceedsBudgetAfterAnyStore`/`fillingPastBudget…`; SC-04 `clearingBothStoresMidShow…`/`loweringTheBudgetPrunesImmediately`; SC-05 `diskHitMakesNoNetworkRequest…`; SC-06 `purgedPhotosDegradeToTheCalmErrorState` | covered | host-unit |

## 130 - Immich API v3 *(added 2026-07-10, implemented)*

v3-only baseline (drops v2). Host-unit unless noted.

| Req | Statement | Test evidence | Status | Kind |
|-----|-----------|---------------|--------|------|
| FR-130-01 | v3-only; no v2 compatibility path | All 130 tests below run against v3 fixtures; the v2 album `assets` decode path was removed | covered | host-unit |
| FR-130-02 | Album assets via `POST /search/metadata`, paged | `ImmichClient/MetadataSearchTests.swift` `searchResponseDecodesItemsTypeAndNextPageToken`, `assetsPageThroughMetadataSearchUntilNextPageIsNil`, `metadataSearchRequestEncodesAlbumFilterPagingAndImageType`; `AssetTests.swift` `assetsFetchesImagesViaMetadataSearchWithAPIKeyHeader`, `assetsReturnsEmptyArrayForAlbumWithoutAssets`; app `Immich_SlideshowTests.swift` `assetsFetchImagesViaMetadataSearchWithAPIKey`, `assetsReturnsEmptyArrayForEmptyAlbum` | covered | host-unit + app |
| FR-130-03 | Shared-link password in login body, never query | `SharedLinkResolverTests.swift` `resolverLogsInWithPasswordInBodyNotQueryAndReturnsResolution`, `resolverFallsBackToSlugWhenKeyIsInvalid` (no-password GET `/me`) | covered | host-unit |
| FR-130-12 | Shared-link source lists assets from `/shared-links/me` | `MetadataSearchTests.swift` `sharedLinkSourceListsAssetsFromSharedLinksMe` | covered | host-unit |
| FR-130-04/09 | Detect major<3; unknown never blocks | `ServerVersionTests.swift` `serverVersionGateClassifiesMajorVersions`, `ensureServerSupportedThrowsServerTooOldForMajorBelowThree`, `ensureServerSupportedPassesForMajorThreePlus`, `ensureServerSupportedPropagatesUnreachableRatherThanTooOld` | covered | host-unit |
| FR-130-05 | Connect (onboarding + Settings) blocks pre-v3 with notice | `OnboardingViewModelTests.swift` `submitConnectionBlocksPreV3ServerWithUpgradeNotice`; `ConnectionSettingsViewModelTests.swift` `connectionSettingsRejectsPreV3Server` | covered | host-unit |
| FR-130-06 | Refresh treats too-old as terminal (no backoff) | `RetryPolicyTests.swift` `classifyMapsServerTooOldToUnsupportedServerAndIsTerminal`; `SlideshowResilienceTests.swift` `tooOldServerAtLaunchShowsUnsupportedNoticeAndDoesNotRetry` | covered | host-unit |
| FR-130-07 | Distinct `serverTooOld` error category | `ErrorTests.swift` `serverTooOldCarriesVersionAndIsDistinctFromOtherCases` | covered | host-unit |
| FR-130-08 | Decode tolerance for removed v3 fields | `V3DecodeToleranceTests.swift` `albumDecodesV3ShapeWithoutOwnerOrAssets`, `assetDecodesV3ShapeIgnoringRemovedDeviceFields`, `assetInfoDecodesV3AssetWithoutDeviceFields`, `resolverReadsSimplifiedV3ErrorEnvelopeForInvalidIdentifier` | covered | host-unit |
| FR-130-11 | Password never in URL/log | `SharedLinkResolverTests.swift` password-in-body assertion (no `password` query) | covered | host-unit |

SC-130-01…06 map to the same tests (paging/order, no-query-password, connect notice, terminal-no-retry, decode tolerance, mock-transport-only). Notice rendering (`SlideshowErrorView` `.unsupportedServer`; onboarding/Settings `errorMessage`) exercised by the full sim suite without regression; a **dedicated too-old onboarding UITest is deferred** (see spec Status).

## 400 - PowerManager

| FR | Requirement (short) | Covering test(s) | Status | Testability |
|---|---|---|---|---|
| FR-400-01 | Suppress idle while active foreground slideshow | `Packages/PowerKit/Tests/PowerKitTests/PowerManagerTests.swift` `activateKeepsScreenAwake` | covered | host-unit |
| FR-400-02 | Restore idle/lock on exit | `PowerManagerTests.swift` `deactivateReleasesScreenAwake`, `repeatedActivationAndSceneTransitionsEndReleased` | covered | host-unit |
| FR-400-03 | Wake suppression foreground-only | `PowerManagerTests.swift` `backgroundReleasesAwakeWithoutBrightnessWriteAndForegroundRestoresAwake` | covered | host-unit |
| FR-400-04 | Re-arm on foreground return | `PowerManagerTests.swift` `backgroundReleasesAwakeWithoutBrightnessWriteAndForegroundRestoresAwake` | covered | host-unit |
| FR-400-05 | Set target brightness 0...1 | `BrightnessRampTests.swift` `immediateBrightnessWritesTargetInForeground` | covered | host-unit |
| FR-400-06 | Clamp out-of-range brightness | `BrightnessRampTests.swift` `immediateBrightnessClampsTarget` | covered | host-unit |
| FR-400-07 | Soft dim gradually to target | `BrightnessRampTests.swift` `animatedBrightnessRampsThroughIntermediateValuesAndEndsAtTarget` | covered | host-unit |
| FR-400-08 | Near-zero dim as display-off substitute | `BrightnessRampTests.swift` `animatedBrightnessRampsThroughIntermediateValuesAndEndsAtTarget`; no hardware assertion that display remains technically on | partial | manual |
| FR-400-09 | No brightness writes in background | `BrightnessRampTests.swift` `brightnessSetInBackgroundIsNoOp`; `PowerManagerTests.swift` `backgroundReleasesAwakeWithoutBrightnessWriteAndForegroundRestoresAwake` | covered | host-unit |
| FR-400-10 | Capture baseline before first brightness change | `PowerManagerTests.swift` `deactivateRestoresBaselineAfterBrightnessChange` | covered | host-unit |
| FR-400-11 | Restore baseline only if changed | `PowerManagerTests.swift` `deactivateRestoresBaselineAfterBrightnessChange`, `deactivateDoesNotWriteBrightnessWhenUnchanged` | covered | host-unit |
| FR-400-12 | New soft target preempts; background stops dim | `BrightnessRampTests.swift` covers background no-op after background, but no test for preempting an in-flight ramp | partial | host-unit |
| FR-400-13 | Injectable screen interface | PowerKit tests use `FakeScreenController` and `ManualClock` | covered | host-unit |
| FR-400-14 | Respect iPadOS foreground platform boundaries | Host fakes cover foreground gating; real platform behavior still needs simulator/device verification | partial | manual |

## 500 - Display Options

| FR | Requirement (short) | Covering test(s) | Status | Testability |
|---|---|---|---|---|
| FR-500-01 | Persistent injectable settings store | `Packages/ThemeKit/Tests/ThemeKitTests/UserDefaultsThemeStoreTests.swift` `userDefaultsThemeStoreRoundTripsEveryFieldAcrossRelaunch`; `SlideshowKit` tests inject stores | covered | host-unit |
| FR-500-02 | Non-secret storage; no secrets | — | missing | manual |
| FR-500-03 | Defaults: shuffle, 15s, crossfade, Ken Burns off, Fit, Preview, clock off | `ThemeSettingsDefaultsTests.swift` `themeSettingsDefaultsMatchDisplayOptionsSpec`; `SettingsDisplayOptionsUITests.swift` default assertions | covered | host-unit |
| FR-500-04 | Changes apply live to running slideshow | `DurationTickerTests.swift` `tickerWaitsCurrentDurationAndReArmsWhenDurationChangesMidShow`; `PlayOrderTests.swift` `switchingOrderMidShowKeepsCurrentPhotoAsAnchor`; `QualitySelectionTests.swift`; not all render options covered live | partial | host-unit |
| FR-500-05 | Changes persist across launches | `UserDefaultsThemeStoreTests.swift` `userDefaultsThemeStoreRoundTripsEveryFieldAcrossRelaunch`; `SettingsDisplayOptionsUITests.swift` persistence tests | covered | host-unit |
| FR-500-06 | Shuffle/sequential order semantics | `SlideshowKit/PlayOrderTests.swift` `sequentialOrderVisitsAlbumOrderAndWraps`, `shuffleShowsEveryPhotoOncePerCycleThenReshuffles` | covered | host-unit |
| FR-500-07 | Configurable duration with clamp | `ThemeSettingsDefaultsTests.swift` `themeSettingsDurationRangeMatchesDisplayOptionsSpec`; `UserDefaultsThemeStoreTests.swift` `userDefaultsThemeStoreClampsDurationImmediatelyAndAcrossRelaunch` | covered | host-unit |
| FR-500-08 | Transition options crossfade/slide/dissolve/none | `ThemeSettingsDefaultsTests.swift` `themeSettingsDefaultsMatchDisplayOptionsSpec`; `SlideshowKit/TransitionMappingTests.swift` `transitionDescriptorMapsStyleForEachCase`, `onlyNoneDisablesAnimation` | covered | host-unit |
| FR-500-09 | Ken Burns toggle default off | `ThemeSettingsDefaultsTests.swift` `themeSettingsDefaultsMatchDisplayOptionsSpec`; `SettingsDisplayOptionsUITests.swift` `testTransitionAndKenBurnsPersistAcrossRelaunch` | covered | ui-sim |
| FR-500-10 | Fit/Fill options | `ThemeSettingsDefaultsTests.swift`; `UserDefaultsThemeStoreTests.swift` `userDefaultsThemeStoreRoundTripsEveryFieldAcrossRelaunch`; no visual fill/crop UI assertion | partial | ui-sim |
| FR-500-11 | Preview/Original quality | `UserDefaultsThemeStoreTests.swift` `userDefaultsThemeStoreRoundTripsEveryFieldAcrossRelaunch`; `SlideshowKit/QualitySelectionTests.swift` `originalQualityLoadsOriginalBytesWithoutPreviewFetch`, `previewQualityLoadsPreviewBytesWithoutOriginalFetch` | covered | host-unit |
| FR-500-12 | Optional clock corner/date | `ThemeSettingsDefaultsTests.swift`; `UserDefaultsThemeStoreTests.swift` round-trip clock fields; no rendered overlay test | partial | ui-sim |
| FR-500-13 | Replace placeholder rows with live controls | `SettingsDisplayOptionsUITests.swift` order/duration/transition/Ken Burns tests; fit/quality not UI-tested | partial | ui-sim |
| FR-500-14 | Brightness still works | `Immich SlideshowUITests/SettingsUITests.swift` `testSettingsShowsBrightnessAndPlannedOptionsAndDismisses`; `PowerKit` tests cover owner behavior | covered | ui-sim |
| FR-500-15 | Calm default overlay-free | `ThemeSettingsDefaultsTests.swift` `themeSettingsDefaultsMatchDisplayOptionsSpec`; `SlideshowChromeUITests.swift` hidden/default UI tests | covered | ui-sim |
| FR-500-16 | Invalid/corrupt settings fall back to defaults | `UserDefaultsThemeStoreTests.swift` `userDefaultsThemeStoreFallsBackPerFieldForCorruptValues`, `userDefaultsThemeStoreUsesDefaultsForEmptySuite` | covered | host-unit |

## 600 - Broker Setup

| FR | Requirement (short) | Covering test(s) | Status | Testability |
|---|---|---|---|---|
| FR-600-01 | Enter host, port, username, password | `Packages/BrokerSetupKit/Tests/BrokerSetupKitTests/BrokerSetupViewModelTests.swift` `saveNewBrokerPersists`; `Immich SlideshowUITests/BrokerSetupUITests.swift` broker field tests | covered | ui-sim |
| FR-600-02 | Validate host/port/username/password | `BrokerSettingsTests.swift` `validationAcceptsCompleteSettings`, `validationReturnsFirstErrorInContractOrder`, `validationAcceptsBoundaryPorts`, `validationRejectsPortsOutsideTCPRange`; `BrokerSetupViewModelTests.swift` invalid tests | covered | host-unit |
| FR-600-03 | Invalid input prevents save and shows hint | `BrokerSettingsTests.swift` `inMemoryStoreRejectsInvalidSettingsWithoutWriting`; `BrokerSetupViewModelTests.swift` `saveInvalidPortReportsError`, `saveEmptyHostReportsError`; no UI assertion for every hint | partial | ui-sim |
| FR-600-04 | Username/password only in Keychain, never elsewhere | `BrokerSetupUITests.swift` `testExistingBrokerPrefillsFieldsMasksPasswordAndRemoves` covers no cleartext UI; storage audit not covered by package tests | partial | manual |
| FR-600-05 | Host/port may be non-secret settings | `BrokerSetupViewModelTests.swift` `saveNewBrokerPersists`; `BrokerConfigProviderTests.swift` `providerBuildsBrokerConfigFromSettingsAndDeviceID` | covered | host-unit |
| FR-600-06 | Atomic save, no partial broker config | `BrokerSettingsTests.swift` `inMemoryStoreRejectsInvalidSettingsWithoutWriting` | covered | host-unit |
| FR-600-07 | Provision complete config with stable device ID | `BrokerConfigProviderTests.swift` `providerBuildsBrokerConfigFromSettingsAndDeviceID` | covered | host-unit |
| FR-600-08 | Provision nil when required detail missing/invalid | `BrokerConfigProviderTests.swift` `providerReturnsNilWithoutSettings`; invalid persisted detail path not directly covered | partial | host-unit |
| FR-600-09 | Broker details persist across restart | `BrokerSettingsTests.swift` `inMemoryStoreRoundTripsCompleteSettings`; no real Keychain restart-style package test | partial | host-unit |
| FR-600-10 | Edit existing details; changed password overwrites | `BrokerSetupViewModelTests.swift` `saveEmptyPasswordKeepsExisting`; no changed-password overwrite test | partial | host-unit |
| FR-600-11 | Fully remove broker details | `BrokerSettingsTests.swift` `inMemoryStoreClearRemovesSettings`; `BrokerSetupViewModelTests.swift` `removeClearsStoreAndForm`; `BrokerSetupUITests.swift` remove test | covered | host-unit |
| FR-600-12 | Existing password not redisplayed in plaintext | `BrokerSetupViewModelTests.swift` `loadPrefillsWithoutSecret`; `BrokerSetupUITests.swift` `testExistingBrokerPrefillsFieldsMasksPasswordAndRemoves` | covered | ui-sim |
| FR-600-13 | Stable device ID app-derived and stable | `BrokerConfigProviderTests.swift` `providerBuildsBrokerConfigFromSettingsAndDeviceID` | partial | host-unit |

## 700 - Home Assistant Control

| FR | Requirement (short) | Covering test(s) | Status | Testability |
|---|---|---|---|---|
| FR-700-01 | Connect to MQTT broker over TLS with validation | `Packages/HAControlKit/Tests/HAControlMQTTTests/NIOMQTTTransportIntegrationTests.swift` integration test; TLS validation specifics not asserted in host tests | partial | manual |
| FR-700-02 | Credentials from Keychain-backed config only; no leaks | `HAControlCoordinatorTests.swift` uses `BrokerConfigStore`; no Keychain or log audit | partial | manual |
| FR-700-03 | Missing/invalid/connect failure does not block slideshow | `HAControlCoordinatorTests.swift` `startWithoutConfigDoesNotConnectOrPublish`, `failedConnectLeavesCoordinatorDisconnected` | covered | host-unit |
| FR-700-04 | Publish online availability and LWT offline | `HAControlCoordinatorTests.swift` `startConnectsAnnouncesSubscribesAndEchoesPlaybackState` | covered | host-unit |
| FR-700-05 | Reconnect and reannounce availability/state | `HAControlCoordinatorTests.swift` `reconnectReAnnouncesDiscoveryAndState` | covered | host-unit |
| FR-700-06 | HA discovery with stable duplicate-free IDs | `HADiscoveryTests.swift` discovery payload/topic tests; `HAControlCoordinatorTests.swift` discovery publication tests | covered | host-unit |
| FR-700-07 | Pause/play switch entity availability | `HADiscoveryTests.swift` switch config tests; `HAControlCoordinatorTests.swift` `startConnectsAnnouncesSubscribesAndEchoesPlaybackState` | covered | host-unit |
| FR-700-08 | Inbound pause/play commands pause/resume | `HAControlCoordinatorTests.swift` `playbackCommandsPauseResumeAndEchoActualState` covers `OFF`/`ON`, not literal `pause`/`play` | partial | host-unit |
| FR-700-09 | Echo state after remote and local changes | `HAControlCoordinatorTests.swift` `playbackCommandsPauseResumeAndEchoActualState`, `localChangeEchoesActualPlaybackState` | covered | host-unit |
| FR-700-10 | Injectable MQTT transport | `HAControlCoordinatorTests.swift` fake transport tests; `HADiscoveryTests.swift` | covered | host-unit |
| FR-700-11 | Unknown commands ignored safely | `HAControlCoordinatorTests.swift` `invalidPlaybackPayloadDoesNotChangeStateButEchoesCurrentState` | covered | host-unit |
| FR-700-12 | Latest valid rapid command wins; echo actual state | `HAControlCoordinatorTests.swift` `playbackCommandsPauseResumeAndEchoActualState`; rapid/conflicting sequence not directly tested | partial | host-unit |

## 900 - Photo Library Source *(added 2026-07-16, implemented — device/beta gates pending)*

Host-unit tests live in `Packages/PhotoLibraryKit/Tests/PhotoLibraryKitTests/`
(`PhotoLibraryProviderTests`, `AuthorizationTests`, `ImageDeliveryTests`,
`ChangeObservationTests`, `SeamTests`) and `Packages/SlideshowKit/Tests/SlideshowKitTests/`
(`DualBackendScenarioTests`, additions to the offline/resilience/view-model suites). UI-sim
coverage is `PhotoAlbumPickerUITests` (hermetic `--uitest-photos*` seams) plus round-trip
additions in `Immich SlideshowTests/HAControlRoundTripTests`.

| FR | Requirement (short) | Covering test(s) | Status | Testability |
|---|---|---|---|---|
| FR-900-01 | Backend-neutral source protocol; engine unchanged | Phase-1 gate (all SlideshowKit suites through `PhotoSourceProviding`); `DualBackendScenarioTests` (SC-900-03) | covered | host-unit |
| FR-900-03 | User albums + iCloud Shared Albums enumerable (full access) | `PHKitGateway.fetchCollections` (adapter, sim-verified); picker UITests `testAddPhotosAlbumFromSettingsPlaysSlideshow` | covered | UI-sim + device gate |
| FR-900-04 | Access requested at choice, `.readWrite` level API, purpose string | `AuthorizationTests` (matrix + transitions); `testOnboardingPhotosAlbumTabAddsFirstSource` (first-run request path); purpose string in build settings (verified in built Info.plist) | covered | host-unit + UI-sim |
| FR-900-06 | iCloud originals on demand, no-blank rules hold | `ImageDeliveryTests` (opaque error → `.transient`); `PhotosDeliveryTests` slow-load no-blank | covered | host-unit |
| FR-900-07 | Never show degraded deliveries | `ImageDeliveryTests` decision table over `ImageDeliveryRules` (extracted from the gateway callbacks) | covered | host-unit |
| FR-900-08 | Live Photos as stills; non-stills skipped | `ImageDeliveryTests` kind pass-through (provider filters nothing); engine `.image` filter tests | covered | host-unit |
| FR-900-09 | Change observation → rotation; foreground refetch | `ChangeObservationTests`; `refreshNow` engine tests; app hooks (change handler + scenePhase, T025) | covered | host-unit + wiring review |
| FR-900-10 | Info overlay: date; place only when the source has one | `metadataPassesThroughFromTheSource`; `testPhotosSourceInfoOverlayShowsDateOnly`; Immich path pinned by `PhotoInfoUITests` | covered | host-unit + UI-sim |
| FR-900-11 | HA: source select + metadata parity | `sourceSelectListsLibrarySourcesAndRoutesToAppSwitch`, `photosSourceReportsDateOnlyMetadataThroughNeutralPath` | covered | app-hosted |
| FR-900-12 | Image publishing under the global opt-in, copy covers all sources | engine `imageDataPassesThroughFromTheSource`; adapter neutral image path; `broker.imagePublishScope` copy | covered | host-unit + UI copy |
| FR-900-13 | Host-testable behind the protocol; PhotoKit stays a thin adapter | `SeamTests` (import confined to `PHKitGateway.swift`); all suites host-green | covered | host-unit |
| FR-900-14 | Nothing leaves the device beyond HA opt-ins | egress grep (T035): no network API in PhotoLibraryKit; `placeName` nil (no geocoding) | covered | static audit |
| FR-900-15 | Never imply better quality than the source ceiling | `testPhotosSourceShowsQualityCeilingNote` (Display footer) | covered | UI-sim |
| FR-900-16 | Vanish → calm terminal state with cause copy | `ChangeObservationTests` vanish mapping; `refreshNow` `.notFound` terminal test; `testVanishedAlbumShowsCauseCopyIncludingUpgradeHint`, `testDowngradeMakesActiveAlbumSourceCalmlyUnavailable` | covered | host-unit + UI-sim |
| SC-900-03 | Same engine tests over both backends | `DualBackendScenarioTests` (5 scenarios × 2 backends) | covered | host-unit |
| SC-900-05 | Authorization surfaces honest | `testLimitedAccessOffersSelectedPhotosOnly`, `testDeniedAccessShowsCalmMessageWithSettingsPath` | covered | UI-sim |
| SC-900-06 | Cross-backend switching, no leaked timers | `droppedViewModelDeallocatesAndStopsItsTickerLoop`; switch-both-directions UITests | covered | host-unit + UI-sim |
| SC-900-01/02/04/07 | Device/beta release gates | scheduled checklist in `specs/900-photo-library-source/quickstart.md` (T036) | scheduled | manual |

Additional 900 engine rule: `SlideshowConfig.snapshotMasksAuthenticationFailures` — a
photo-access revocation is never masked by remembered snapshots
(`revokedAccessAtLaunchIsNotMaskedBySnapshotWhenConfigured`); the Immich stale-beats-broken
default is pinned unchanged (`expiredCredentialsAtLaunchStillPlayFromSnapshotByDefault`).

## 220 - Onboarding Welcome *(added 2026-07-17, implemented on branch — camera device gate pending)*

*(Sub-spec of 200.)* Welcome-screen overhaul: iCloud album at the top, a camera QR-scan
accelerator on the shared-link path, and a light-decorated three friction-ordered options.
Host-unit tests live in `Packages/OnboardingKit/Tests/OnboardingKitTests/`
(`OnboardingWelcomePathTests`, `ScannedShareLinkTests`, `StartupGatePhotoLibraryTests`,
`ScannedLinkRoutingTests`). UI-sim coverage is `Immich SlideshowUITests/`
(`WelcomeICloudUITests`, and the extended `OnboardingDescriptionsUITests` /
`OnboardingBackUITests`), with the shared-link/source/Share-Sheet regression classes staying
green. The live camera QR decode + permission prompt is a manual **device gate** (SC-220-07).

| FR | Requirement (short) | Covering test(s) | Status | Testability |
|---|---|---|---|---|
| FR-220-01 | Three friction-ordered welcome paths (iCloud, shared link, server) | `OnboardingWelcomePathTests` (`choosePath(.photoLibrary)` → `.photoLibrarySetup`); `OnboardingDescriptionsUITests.testChoiceScreenShowsThreeFrictionOrderedOptions` (three options, order, helper text) | covered | host-unit + ui-sim |
| FR-220-02 | iCloud path reaches slideshow with no server/API key | `WelcomeICloudUITests.testICloudAlbumIsTopChoiceAndReachesSlideshow` (Photos-backed `slideshow.image`, no connection) | covered | ui-sim |
| FR-220-03 | Reuse 900 photoLibrary behaviour unchanged (add only the welcome entry) | reuses `PhotoAlbumPickerView` + `addPhotoLibrarySource` (900 `PhotoAlbumPickerUITests`/`AuthorizationTests`); welcome entry via `WelcomeICloudUITests` | covered | ui-sim (reuse) |
| FR-220-04 | Scanned code handled identically to a typed link | `ScannedLinkRoutingTests` (scanned valid link triggers the same `resolveSharedLink` call); Scan-QR affordance present (`snapshot_ui`, `onboarding.sharedLink.scan`) | covered | host-unit + ui-sim |
| FR-220-05 | Camera purpose string; denied/unavailable keeps manual entry | `QRScannerView` `.permissionDenied`/`.noCamera` fallback keeping manual entry; `INFOPLIST_KEY_NSCameraUsageDescription` in build settings; live prompt = device gate | partial | ui-sim + device gate |
| FR-220-06 | Invalid scanned code rejected client-side, no network, nothing persisted | `ScannedShareLinkTests` (`.notAURL`/`.notHTTPS`/`.notAShareLink`); `ScannedLinkRoutingTests` (resolver call count 0, `.error`, nothing persisted) | covered | host-unit |
| FR-220-07 | Server path + downstream steps unchanged | `SourceOnboardingUITests`; `OnboardingBackUITests`; `OnboardingDescriptionsUITests` (connection/source/confirm descriptions) | covered | ui-sim |
| FR-220-08 | Concise non-technical helper copy per option | `OnboardingDescriptionsUITests.testChoiceScreenShowsThreeFrictionOrderedOptions` (per-option helper text) | covered | ui-sim |
| FR-220-09 | Welcome contract preserved (no Back; shared-link no key; helper text; Share Sheet) | `OnboardingBackUITests.testChoiceScreenHasNoBack`; `SharedLinkOnboardingUITests` (reaches slideshow, no API key); `ShareSheetIncomingUITests` | covered | ui-sim |
| FR-220-10 | Sources land in one library (downstream/HA/App-Intent unchanged) | reuses `SourceLibrary`/`addPhotoLibrarySource`/`resolveSharedLink` (120/900 round-trip; `Immich SlideshowTests/HAControlRoundTripTests`) | covered | host-unit (reuse) |
| FR-220-11 | No secrets; a scanned URL carries none (password still prompted) | `ScannedLinkRoutingTests` (nothing persisted on invalid; `.needsPassword` still prompts); `QRScannerView` logs no decoded URL — audit 2026-07-17 | covered | host-unit + static audit |
| FR-220-12 | Scan feeds a host-testable seam (no camera in unit tests) | `ScannedShareLinkTests` + `ScannedLinkRoutingTests` drive a fake `CodeScanning` (no `AVFoundation`) | covered | host-unit |
| FR-220-13 | New user-facing strings are English-only | repo localization hook enforces English; new strings audited | covered | static |

| SC | Outcome (short) | Evidence | Status |
|---|---|---|---|
| SC-220-01 | New user starts from an iCloud album on the first screen; relaunch straight to slideshow | `WelcomeICloudUITests` + `StartupGatePhotoLibraryTests` (relaunch → `.done`); full first-run E2E also on the device gate | covered + device gate |
| SC-220-02 | Start from a shared album by scanning its QR (password only if needed) | `ScannedLinkRoutingTests` (host parity incl. `.needsPassword`); live camera scan = device gate | scheduled (device) |
| SC-220-03 | Exactly three friction-ordered options, each with one plain-language line | `OnboardingDescriptionsUITests.testChoiceScreenShowsThreeFrictionOrderedOptions` | covered |
| SC-220-04 | Invalid/non-Immich scanned code never plays and never persists | `ScannedShareLinkTests` + `ScannedLinkRoutingTests` | covered |
| SC-220-05 | Denied/unavailable camera never blocks setup — manual entry remains | `QRScannerView` fallback + `snapshot_ui` (Scan-QR + manual field co-present); denied prompt = device gate | partial + device gate |
| SC-220-06 | Every pre-existing onboarding behaviour still passes | full XCUITest suite (T020): `SharedLinkOnboardingUITests`, `SourceOnboardingUITests`, `OnboardingBackUITests`, `ShareSheetIncomingUITests` | covered |
| SC-220-07 | QR parse/validate/route host-tested; camera end-to-end on device | `ScannedShareLinkTests`/`ScannedLinkRoutingTests` (host); manual device gate in `specs/220-onboarding-welcome/quickstart.md` | covered (host) + scheduled (device) |

## Gaps to close (host-unit)

- FR-200-02: startup cannot resume at album selection when URL and key exist but selected album is missing.
- FR-200-07: add invalid-response classification coverage for first-run connection validation.
- FR-300-04: extend live option coverage beyond order/duration/quality into transition, Ken Burns, fit, and clock consumption where package-testable.
- FR-300-08: add disk image cache, relaunch/offline behavior, size eviction, and clear-cache tests.
- FR-300-11: add automatic retry with backoff tests.
- FR-300-12: add periodic source refresh tests.
- FR-400-12: add preemption coverage for an in-flight soft dim target.
- FR-500-04: add live-apply coverage for remaining render options.
- FR-600-08: add invalid/missing-detail provisioning tests, not just absent-settings tests.
- FR-600-09: add persistence/reload coverage for the production broker settings store boundary where feasible.
- FR-600-10: add changed-password overwrite coverage.
- FR-600-13: add explicit stability test for the app-derived device ID across provider/store reloads.
- FR-700-08: either add literal `pause`/`play` command support/tests or align the spec to HA switch `OFF`/`ON`.
- FR-700-12: add rapid/conflicting command sequence coverage.

## UI-sim / manual - orchestrator-owned

- UI-sim partial/missing: FR-200-04, FR-200-13, FR-200-16, FR-200-17, FR-200-18, FR-200-22, FR-200-23, FR-300-10, FR-300-14, FR-300-15, FR-300-16, FR-300-21, FR-300-24, FR-300-25, FR-300-27, FR-300-28, FR-300-29, FR-300-30, FR-500-10, FR-500-12, FR-500-13, FR-600-03.
- Manual/static audit gaps: FR-100-12, FR-200-08, FR-200-26, FR-300-32, FR-400-08, FR-400-14, FR-500-02, FR-600-04, FR-700-01, FR-700-02.

## Drift

- FR-200-25 (200 spec FR text): superseded by 120 — the inert shared-link *placeholder* was replaced by a real add-source step (album or shared link) in onboarding and the Settings Sources manager. Spec 200 FR text still to be reconciled Roadmap→Active under task 120/T030.
- FR-300-08 / FR-300-27: the spec requires a disk image cache with size limit and Clear cache action surfaced in Settings. Current `ImageCache` is memory-only, and Settings does not expose disk-cache size or clear controls.
- FR-300-11 / FR-300-12: the spec requires auto-retry with backoff and periodic source refresh. `SlideshowViewModel` exposes manual `retry()` and `start()`, but no backoff loop or periodic refresh path was found.
- FR-300-29 / FR-500-12: the spec requires a rendered optional clock overlay. Theme settings store clock fields exist, but Settings still labels the clock overlay as a planned/placeholder row and no renderer was found.
- FR-700-08: the spec says inbound `"pause"` and `"play"` commands. `HAControlCoordinator` handles HA switch payloads `"OFF"` and `"ON"` for playback; tests assert `"OFF"`/`"ON"`, not literal `"pause"`/`"play"`.
- Topic 700 roadmap drift: active spec 700 defers brightness and album entities to sub-specs 710/720, but `Immich_SlideshowApp.swift` enables `[.playback, .brightness, .album]` and `HAControlCoordinatorTests.swift` covers brightness and album commands.
