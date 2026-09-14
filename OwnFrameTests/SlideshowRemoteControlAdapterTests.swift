//
//  SlideshowRemoteControlAdapterTests.swift
//  OwnFrameTests
//
//  US1 (710, T009): SettingsControlling on SlideshowRemoteControlAdapter — all 9
//  fields map both directions through a REAL UserDefaultsThemeStore; a remote
//  apply() is suppressed and does NOT fire onSettingsChange; a genuinely local
//  store mutation fires it exactly once, including after a suppressed apply
//  (observation re-arm).
//

import Foundation
import Testing
import UIKit
import HAControlKit
import ImmichClient
import OnboardingKit
import PhotoSourceKit
import PowerKit
import SlideshowKit
import ThemeKit
@testable import OwnFrame

@MainActor
struct SlideshowRemoteControlAdapterTests {

    @Test func themeSettingsSnapshotMapsAllElevenFieldsFromStore() throws {
        let fixture = try makeAdapter(suite: "adapter.mapsFromStore")
        defer { fixture.cleanUp() }

        fixture.store.settings = ThemeSettings(
            order: .sequential,
            duration: .seconds(42),
            transition: .slide,
            kenBurns: true,
            fit: .fill,
            quality: .original,
            clock: ClockSettings(isOn: true, style: .pill, place: .topLeading, size: .cozy, showDate: true)
        )

        let snapshot = fixture.adapter.themeSettings
        #expect(snapshot.order == .sequential)
        #expect(snapshot.durationSeconds == 42)
        #expect(snapshot.transition == .slide)
        #expect(snapshot.kenBurns == true)
        #expect(snapshot.fit == .fill)
        #expect(snapshot.quality == .original)
        #expect(snapshot.clockOn == true)
        #expect(snapshot.clockPlace == .topLeading)
        #expect(snapshot.clockStyle == .pill)
        #expect(snapshot.clockSize == .cozy)
        #expect(snapshot.clockDate == true)
    }

    @Test func applyMapsAllElevenFieldsIntoStore() throws {
        let fixture = try makeAdapter(suite: "adapter.applyMaps")
        defer { fixture.cleanUp() }

        fixture.adapter.apply(ThemeSettingsSnapshot(
            order: .sequential,
            durationSeconds: 42,
            transition: .dissolve,
            kenBurns: true,
            fit: .fill,
            quality: .original,
            clockOn: true,
            clockPlace: .bottomLeading,
            clockStyle: .analog,
            clockSize: .cozy,
            clockDate: true
        ))

        let settings = fixture.store.settings
        #expect(settings.order == .sequential)
        #expect(settings.duration == .seconds(42))
        #expect(settings.transition == .dissolve)
        #expect(settings.kenBurns == true)
        #expect(settings.fit == .fill)
        #expect(settings.quality == .original)
        #expect(settings.clock.isOn == true)
        #expect(settings.clock.place == .bottomLeading)
        #expect(settings.clock.style == .analog)
        #expect(settings.clock.size == .cozy)
        #expect(settings.clock.showDate == true)
    }

    /// `newPhotosCard` (310, FR-310-14) is not part of the 11-field HA snapshot (FR-710-01
    /// predates it), so any HA-triggered `apply()` — e.g. toggling Ken Burns via Home
    /// Assistant — must not silently reset it to its default.
    @Test func applyPreservesNewPhotosCardWhichIsNotPartOfTheHASnapshot() throws {
        let fixture = try makeAdapter(suite: "adapter.preservesNewPhotosCard")
        defer { fixture.cleanUp() }

        fixture.store.settings.newPhotosCard = true

        var snapshot = fixture.adapter.themeSettings
        snapshot.kenBurns = true
        fixture.adapter.apply(snapshot)

        #expect(fixture.store.settings.newPhotosCard == true)
        #expect(fixture.store.settings.kenBurns == true)
    }

    @Test func applyDoesNotFireOnSettingsChange() async throws {
        let fixture = try makeAdapter(suite: "adapter.applySuppressed")
        defer { fixture.cleanUp() }

        var fired = 0
        fixture.adapter.onSettingsChange = { fired += 1 }

        var snapshot = fixture.adapter.themeSettings
        snapshot.kenBurns = true
        fixture.adapter.apply(snapshot)
        await drainObservation()

        #expect(fired == 0)
    }

    @Test func localStoreMutationFiresOnSettingsChangeOnce() async throws {
        let fixture = try makeAdapter(suite: "adapter.localFires")
        defer { fixture.cleanUp() }

        var fired = 0
        fixture.adapter.onSettingsChange = { fired += 1 }

        fixture.store.settings.kenBurns = true
        await drainObservation()

        #expect(fired == 1)
    }

    @Test func localMutationAfterSuppressedApplyStillFires() async throws {
        let fixture = try makeAdapter(suite: "adapter.rearmAfterApply")
        defer { fixture.cleanUp() }

        var fired = 0
        fixture.adapter.onSettingsChange = { fired += 1 }

        var snapshot = fixture.adapter.themeSettings
        snapshot.quality = .original
        fixture.adapter.apply(snapshot)
        await drainObservation()
        #expect(fired == 0)

        fixture.store.settings.kenBurns = true
        await drainObservation()
        #expect(fired == 1)
    }

    // MARK: - PhotoReporting (US2)

    @Test func currentAssetChangeReportsMetadataFromAssetInfo() async throws {
        let taken = Date(timeIntervalSince1970: 1_600_000_000)
        let fixture = try makePhotoFixture(
            suite: "photo.metadata",
            info: ["asset-1": AssetInfo(id: "asset-1", takenAt: taken, city: "Berlin", state: "BE", country: "DE")],
            image: makeJPEG()
        )
        defer { fixture.slideshow.pause(); fixture.cleanUp() }

        var reports: [PhotoReport] = []
        fixture.adapter.onPhotoChange = { reports.append($0) }

        await fixture.slideshow.start()
        await settle()

        #expect(!reports.isEmpty)
        let report = fixture.adapter.currentPhotoReport
        #expect(report.assetID == "asset-1")
        #expect(report.phase == .playing)
        #expect(report.takenAt == taken)
        #expect(report.city == "Berlin")
        #expect(report.state == "BE")
        #expect(report.country == "DE")
        #expect(report.albumID == "album-1")
        #expect(report.albumName == "Family")
    }

    @Test func metadataFetchFailureStillReportsAssetIDWithNilMetadata() async throws {
        let fixture = try makePhotoFixture(suite: "photo.metaFail", failAdapterInfo: true, image: makeJPEG())
        defer { fixture.slideshow.pause(); fixture.cleanUp() }

        var reports: [PhotoReport] = []
        fixture.adapter.onPhotoChange = { reports.append($0) }

        await fixture.slideshow.start()
        await settle()

        #expect(!reports.isEmpty)
        let report = fixture.adapter.currentPhotoReport
        #expect(report.assetID == "asset-1")
        #expect(report.takenAt == nil)
        #expect(report.city == nil)
        #expect(report.state == nil)
        #expect(report.country == nil)
    }

    @Test func imageDisabledYieldsNilImageData() async throws {
        let fixture = try makePhotoFixture(
            suite: "photo.imgOff",
            options: HAPublishOptions(imageEnabled: false),
            image: makeJPEG()
        )
        defer { fixture.slideshow.pause(); fixture.cleanUp() }
        fixture.adapter.onPhotoChange = { _ in }

        await fixture.slideshow.start()
        await settle()

        #expect(fixture.adapter.currentPhotoReport.imageData == nil)
    }

    @Test func imageEnabledYieldsDownscaledJPEGUnderCap() async throws {
        let cap = 20_000
        let fixture = try makePhotoFixture(
            suite: "photo.imgOn",
            options: HAPublishOptions(imageEnabled: true, imageSource: .preview, byteCap: cap),
            image: makeJPEG(size: CGSize(width: 512, height: 512))
        )
        defer { fixture.slideshow.pause(); fixture.cleanUp() }
        fixture.adapter.onPhotoChange = { _ in }

        await fixture.slideshow.start()
        await settle()

        let data = try #require(fixture.adapter.currentPhotoReport.imageData)
        #expect(data.count <= cap)
        #expect(UIImage(data: data) != nil)
    }

    @Test func imageFetchFailureYieldsNilImageData() async throws {
        let fixture = try makePhotoFixture(
            suite: "photo.imgFail",
            options: HAPublishOptions(imageEnabled: true, imageSource: .thumbnail, byteCap: 512_000),
            failAdapterImage: true,
            image: makeJPEG()
        )
        defer { fixture.slideshow.pause(); fixture.cleanUp() }
        fixture.adapter.onPhotoChange = { _ in }

        await fixture.slideshow.start()
        await settle()

        #expect(fixture.adapter.currentPhotoReport.imageData == nil)
        #expect(fixture.adapter.currentPhotoReport.assetID == "asset-1")
    }

    @Test func imageOverCapAfterDownscaleYieldsNil() async throws {
        let fixture = try makePhotoFixture(
            suite: "photo.overCap",
            options: HAPublishOptions(imageEnabled: true, imageSource: .preview, byteCap: 10),
            image: makeJPEG(size: CGSize(width: 256, height: 256))
        )
        defer { fixture.slideshow.pause(); fixture.cleanUp() }
        fixture.adapter.onPhotoChange = { _ in }

        await fixture.slideshow.start()
        await settle()

        #expect(fixture.adapter.currentPhotoReport.imageData == nil)
    }

    @Test func revisitingAssetUsesCachedMetadata() async throws {
        let fixture = try makePhotoFixture(
            suite: "photo.cache",
            info: ["asset-1": AssetInfo(id: "asset-1", takenAt: nil, city: "Berlin", state: nil, country: nil)],
            image: makeJPEG()
        )
        defer { fixture.slideshow.pause(); fixture.cleanUp() }
        fixture.adapter.onPhotoChange = { _ in }

        await fixture.slideshow.start()      // shows asset-1
        await settle()
        await fixture.adapter.showNext()     // -> asset-2
        await settle()
        await fixture.adapter.showPrevious() // back to asset-1 (cached)
        await settle()

        let calls = await fixture.haAPI.assetInfoCalls
        #expect(calls["asset-1"] == 1)
        #expect(calls["asset-2"] == 1)
    }

    // MARK: - updateAlbums (800, T006)

    // The 800 hoist builds the adapter synchronously; the HA coordinator's async
    // best-effort album fetch lands post-init via updateAlbums(_:). These pin the
    // late-arrival semantics: legacy fallback options appear, a stored album ID
    // backfills currentAlbum, and a source library keeps owning both.

    @Test func updateAlbumsFeedsLegacyAlbumOptionsPostInit() throws {
        let fixture = try makeAdapter(suite: "adapter.updateAlbums.options")
        defer { fixture.cleanUp() }

        #expect(fixture.adapter.albumOptions.isEmpty)
        fixture.adapter.updateAlbums([Album(id: "album-1", name: "Family")])
        #expect(fixture.adapter.albumOptions == ["Family"])
    }

    @Test func updateAlbumsBackfillsCurrentAlbumFromStoredID() throws {
        let fixture = try makeAdapter(
            suite: "adapter.updateAlbums.backfill",
            currentAlbumID: "album-1"
        )
        defer { fixture.cleanUp() }

        #expect(fixture.adapter.currentAlbum == nil)
        fixture.adapter.updateAlbums([Album(id: "album-1", name: "Family")])
        #expect(fixture.adapter.currentAlbum == "Family")
    }

    @Test func updateAlbumsDoesNotOverrideSourceLibraryOptions() throws {
        let fixture = try makeAdapter(
            suite: "adapter.updateAlbums.sources",
            sources: [Source(id: "s1", label: "Iceland", kind: .album(albumID: "album-1"))],
            activeSourceID: "s1"
        )
        defer { fixture.cleanUp() }

        fixture.adapter.updateAlbums([Album(id: "album-1", name: "Family")])
        #expect(fixture.adapter.albumOptions == ["Iceland"])
        #expect(fixture.adapter.currentAlbum == "Iceland")
    }

    // MARK: - Display name for Get Frame State (800, FR-800-07 via 120, FR-120-13; #61)

    private nonisolated static let linkBaseURL = URL(string: "https://bilder.example.org")!

    /// Stored labels that must never leave the app as a source name: the link's host, the old
    /// `host N` collision suffix, and an unnamed album's id.
    private nonisolated static let leakingSources: [Source] = [
        Source(id: "s1", label: "bilder.example.org", kind: .sharedLink(baseURL: linkBaseURL, slug: "family")),
        Source(id: "s1", label: "bilder.example.org 2", kind: .sharedLink(baseURL: linkBaseURL, slug: "family")),
        Source(id: "s1", label: "album-7f3", kind: .album(albumID: "album-7f3"))
    ]

    // @covers FR-800-07, FR-120-13, FR-120-07
    @Test(arguments: leakingSources)
    func displayNameMapsALeakingStoredLabelWhileTheSelectKeepsIt(_ source: Source) throws {
        let fixture = try makeAdapter(suite: "adapter.displayName.leak", sources: [source], activeSourceID: "s1")
        defer { fixture.cleanUp() }

        let shown = try #require(fixture.adapter.currentSourceDisplayName)
        #expect(shown == SourceLibraryViewModel.displayName(for: source))
        #expect(!shown.localizedCaseInsensitiveContains("bilder.example.org"))
        #expect(!shown.contains("album-7f3"))
        // The HA select still names the saved source by its stored label (FR-120-07).
        #expect(fixture.adapter.currentAlbum == source.label)
        #expect(fixture.adapter.albumOptions == [source.label])
    }

    // @covers FR-800-07, FR-120-13
    @Test func displayNamePassesATypedLabelThroughAndFollowsASwitch() throws {
        let typed = Source(id: "s1", label: "Iceland 2021", kind: .sharedLink(baseURL: Self.linkBaseURL, slug: "iceland"))
        let unlabeled = Source(id: "s2", label: "bilder.example.org", kind: .sharedLink(baseURL: Self.linkBaseURL, slug: "family"))
        let fixture = try makeAdapter(suite: "adapter.displayName.switch", sources: [typed, unlabeled], activeSourceID: "s1")
        defer { fixture.cleanUp() }

        #expect(fixture.adapter.currentSourceDisplayName == "Iceland 2021")

        fixture.adapter.selectAlbum("bilder.example.org")

        #expect(fixture.adapter.currentAlbum == "bilder.example.org")
        #expect(fixture.adapter.currentSourceDisplayName == SourceLibraryViewModel.displayName(for: unlabeled))
    }

    /// A switch that doesn't go through `selectAlbum` (Settings → Sources, album → album keeps the
    /// adapter) must still move both the select state and the display name.
    // @covers FR-800-07, FR-120-13, FR-120-07
    @Test func activeSourceChangeMovesTheSelectStateAndTheDisplayName() throws {
        let iceland = Source(id: "s1", label: "Iceland", kind: .album(albumID: "album-1"))
        let unnamed = Source(id: "s2", label: "album-7f3", kind: .album(albumID: "album-7f3"))
        let fixture = try makeAdapter(suite: "adapter.displayName.external", sources: [iceland, unnamed], activeSourceID: "s1")
        defer { fixture.cleanUp() }
        var localChanges = 0
        fixture.adapter.onLocalChange = { localChanges += 1 }

        fixture.adapter.activeSourceChanged(to: unnamed)

        #expect(fixture.adapter.currentAlbum == "album-7f3")
        #expect(fixture.adapter.currentSourceDisplayName == SourceLibraryViewModel.displayName(for: unnamed))
        #expect(localChanges == 1)
    }

    // @covers FR-800-07
    @Test func displayNameWithoutALibraryFallsBackToTheLegacyAlbumName() throws {
        let fixture = try makeAdapter(suite: "adapter.displayName.legacy", currentAlbumID: "album-1")
        defer { fixture.cleanUp() }

        fixture.adapter.updateAlbums([Album(id: "album-1", name: "Family")])

        #expect(fixture.adapter.currentSourceDisplayName == "Family")
    }

    @Test func updateAlbumsEnrichesSubsequentPhotoReports() async throws {
        let fixture = try makePhotoFixture(
            suite: "photo.updateAlbums",
            albumsAtInit: false,
            image: makeJPEG()
        )
        defer { fixture.slideshow.pause(); fixture.cleanUp() }
        fixture.adapter.onPhotoChange = { _ in }

        fixture.adapter.updateAlbums([Album(id: "album-1", name: "Family")])
        await fixture.slideshow.start()
        await settle()

        #expect(fixture.adapter.currentPhotoReport.albumName == "Family")
    }

    // MARK: - Active-source metadata (710 T053, FR-710-25, #64)

    // Current-photo metadata and image follow the ACTIVE source. The engine plays a real
    // shared-link `ImmichClient` over a path-routing transport, so a place or image in the
    // report can only have come through the link.

    @Test func linkSourceReportsDateAndPlaceThroughTheLink() async throws {
        let fixture = try makeLinkFixture(suite: "photo.link.meta")
        defer { fixture.slideshow.pause(); fixture.cleanUp() }
        fixture.adapter.onPhotoChange = { _ in }

        await fixture.slideshow.start()
        await settle { fixture.adapter.currentPhotoReport.city != nil }

        let report = fixture.adapter.currentPhotoReport
        #expect(report.assetID == "link-asset-1")
        #expect(report.takenAt == LinkRoutingTransport.takenAt)
        #expect(report.city == "Reykjavik")
        #expect(report.state == "Capital Region")
        #expect(report.country == "Iceland")
    }

    @Test func linkOnlySetupPublishesTheImageWhenEnabled() async throws {
        let cap = 512_000
        let fixture = try makeLinkFixture(
            suite: "photo.link.image",
            options: HAPublishOptions(imageEnabled: true, imageSource: .thumbnail, byteCap: cap)
        )
        defer { fixture.slideshow.pause(); fixture.cleanUp() }
        fixture.adapter.onPhotoChange = { _ in }

        await fixture.slideshow.start()
        await settle { fixture.adapter.currentPhotoReport.imageData != nil }

        let data = try #require(fixture.adapter.currentPhotoReport.imageData, "no API key, still an image")
        #expect(data.count <= cap)
        #expect(UIImage(data: data) != nil)
    }

    // The adapter no longer accepts an API-key client at all (that was the #64 leak, which
    // sent a link's asset ids to the API-key server), so the remaining proof is on the wire:
    // every request carrying a link asset id goes to the link's host with its key.
    @Test func linkAssetIDsOnlyEverReachTheLinkHost() async throws {
        let fixture = try makeLinkFixture(
            suite: "photo.link.isolation",
            options: HAPublishOptions(imageEnabled: true, imageSource: .thumbnail, byteCap: 512_000)
        )
        defer { fixture.slideshow.pause(); fixture.cleanUp() }
        fixture.adapter.onPhotoChange = { _ in }

        await fixture.slideshow.start()
        await settle {
            fixture.adapter.currentPhotoReport.city != nil && fixture.adapter.currentPhotoReport.imageData != nil
        }

        let linkRequests = fixture.linkTransport.requests
        #expect(linkRequests.contains { $0.url?.path == "/api/assets/link-asset-1" },
                "the metadata lookup goes to the link")
        for request in linkRequests where request.url?.absoluteString.contains("link-asset-") == true {
            let url = try #require(request.url)
            #expect(url.host == "link.example")
            let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
            #expect(items.contains(URLQueryItem(name: "key", value: "link-key")))
            #expect(request.value(forHTTPHeaderField: "x-api-key") == nil)
        }
    }

    // MARK: - Fixture

    private struct Fixture {
        let adapter: SlideshowRemoteControlAdapter
        let store: UserDefaultsThemeStore
        let defaults: UserDefaults
        let suiteName: String

        func cleanUp() {
            defaults.removePersistentDomain(forName: suiteName)
        }
    }

    private func makeAdapter(
        suite: String,
        currentAlbumID: String? = nil,
        sources: [Source] = [],
        activeSourceID: String? = nil
    ) throws -> Fixture {
        let suiteName = "de.kippings.ImmichSlideshow.tests.\(suite)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)

        let store = UserDefaultsThemeStore(defaults: defaults)
        let slideshow = SlideshowViewModel(
            source: StubAPI(),
            collectionID: "album-1",
            ticker: StubTicker(),
            settingsStore: store
        )
        let powerManager = PowerManager(screen: StubScreen())
        let adapter = SlideshowRemoteControlAdapter(
            slideshow: slideshow,
            powerManager: powerManager,
            currentAlbumID: currentAlbumID,
            sources: sources,
            activeSourceID: activeSourceID,
            themeStore: store
        )
        return Fixture(adapter: adapter, store: store, defaults: defaults, suiteName: suiteName)
    }

    /// Observation onChange re-dispatches onto the main actor; give those tasks
    /// a few runloop turns to settle before asserting.
    private func drainObservation() async {
        for _ in 0..<10 {
            await Task.yield()
        }
    }

    // MARK: - Photo fixture

    private struct PhotoFixture {
        let adapter: SlideshowRemoteControlAdapter
        let slideshow: SlideshowViewModel
        let haAPI: FakeAPI
        let store: UserDefaultsThemeStore
        let defaults: UserDefaults
        let suiteName: String

        func cleanUp() {
            defaults.removePersistentDomain(forName: suiteName)
        }
    }

    /// Builds an adapter wired for photo reporting over a *real* running
    /// `SlideshowViewModel`. Since FR-710-25 the adapter reports through the engine's own
    /// source, so one `FakeAPI` (`haAPI`) both plays and reports. Its image failure hits only
    /// `thumbnail` (playback loads `preview`), so an HA image failure never stops playback. A
    /// blocking ticker keeps the auto-advance parked, making manual
    /// `showNext()`/`showPrevious()` steps deterministic.
    private func makePhotoFixture(
        suite: String,
        assets: [Asset] = [Asset(id: "asset-1", type: "IMAGE"), Asset(id: "asset-2", type: "IMAGE")],
        info: [String: AssetInfo] = [:],
        options: HAPublishOptions = HAPublishOptions(),
        failAdapterImage: Bool = false,
        failAdapterInfo: Bool = false,
        albumsAtInit: Bool = true,
        image: Data
    ) throws -> PhotoFixture {
        let suiteName = "de.kippings.ImmichSlideshow.tests.\(suite)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)

        let store = UserDefaultsThemeStore(defaults: defaults)
        store.settings.order = .sequential
        store.settings.quality = .preview

        let haAPI = FakeAPI(
            assets: assets, info: info, image: image,
            failImage: failAdapterImage, failInfo: failAdapterInfo
        )

        let slideshow = SlideshowViewModel(
            source: haAPI,
            collectionID: "album-1",
            ticker: BlockingTicker(),
            settingsStore: store
        )
        let powerManager = PowerManager(screen: StubScreen())
        let optionsStore = InMemoryHAPublishOptionsStore()
        optionsStore.options = options

        let adapter = SlideshowRemoteControlAdapter(
            slideshow: slideshow,
            powerManager: powerManager,
            albums: albumsAtInit ? [Album(id: "album-1", name: "Family")] : [],
            themeStore: store,
            metadataCache: MetadataCache(limit: 64),
            publishOptions: optionsStore
        )
        return PhotoFixture(
            adapter: adapter, slideshow: slideshow, haAPI: haAPI,
            store: store, defaults: defaults, suiteName: suiteName
        )
    }

    private struct LinkFixture {
        let adapter: SlideshowRemoteControlAdapter
        let slideshow: SlideshowViewModel
        let linkTransport: LinkRoutingTransport
        let defaults: UserDefaults
        let suiteName: String

        func cleanUp() {
            defaults.removePersistentDomain(forName: suiteName)
        }
    }

    /// An adapter over an engine that plays a shared link on `link.example` (key `link-key`).
    private func makeLinkFixture(
        suite: String,
        options: HAPublishOptions = HAPublishOptions()
    ) throws -> LinkFixture {
        let suiteName = "de.kippings.ImmichSlideshow.tests.\(suite)"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)

        let store = UserDefaultsThemeStore(defaults: defaults)
        store.settings.order = .sequential
        store.settings.quality = .preview

        let linkTransport = LinkRoutingTransport(host: "link.example", image: makeJPEG())
        let linkClient = ImmichClient(
            config: ServerConfig(baseURL: URL(string: "https://link.example")!, auth: .shareKey("link-key")),
            transport: linkTransport
        )
        let slideshow = SlideshowViewModel(
            source: linkClient,
            collectionID: LinkRoutingTransport.albumID,
            ticker: BlockingTicker(),
            settingsStore: store
        )
        let optionsStore = InMemoryHAPublishOptionsStore()
        optionsStore.options = options

        let adapter = SlideshowRemoteControlAdapter(
            slideshow: slideshow,
            powerManager: PowerManager(screen: StubScreen()),
            themeStore: store,
            metadataCache: MetadataCache(limit: 64),
            publishOptions: optionsStore
        )
        return LinkFixture(
            adapter: adapter, slideshow: slideshow, linkTransport: linkTransport,
            defaults: defaults, suiteName: suiteName
        )
    }

    /// The photo-report build is deferred to a main-actor task chain (observe
    /// re-arm → async metadata/image fetch); yield generously so it completes.
    private func settle() async {
        for _ in 0..<50 {
            await Task.yield()
        }
    }

    /// Like `settle()`, but for a chain through a real `ImmichClient`: polls until `condition`
    /// holds or about a second has passed, so a red test fails on its expectations, not a hang.
    private func settle(until condition: () -> Bool) async {
        for _ in 0..<200 {
            if condition() { return }
            await Task.yield()
            try? await Task.sleep(for: .milliseconds(5))
        }
    }

    private func makeJPEG(size: CGSize = CGSize(width: 64, height: 64)) -> Data {
        let renderer = UIGraphicsImageRenderer(size: size)
        let image = renderer.image { ctx in
            UIColor.systemBlue.setFill()
            ctx.fill(CGRect(origin: .zero, size: size))
        }
        return image.jpegData(compressionQuality: 0.9) ?? Data()
    }
}

// MARK: - Stubs

private struct StubAPI: ImmichAPI {
    func serverVersion() async throws -> String { "test" }
    func albums() async throws -> [Album] { [] }
    func assets(albumID: String) async throws -> [Asset] { [] }
    func preview(assetID: String) async throws -> Data { Data() }
}

// 900 (T012): the engine consumes the neutral protocol; the adapter still takes ImmichAPI.
extension StubAPI: PhotoSourceProviding {
    func ensureReady() async throws {}
    func collections() async throws -> [SourceCollection] { [] }
    func assets(in collectionID: String) async throws -> [SourceAsset] { [] }
    func imageData(for assetID: String, fidelity: ImageFidelity) async throws -> Data { Data() }
    func metadata(for assetID: String) async throws -> AssetMetadata {
        AssetMetadata(capturedAt: nil, latitude: nil, longitude: nil, placeName: nil)
    }
}

private struct StubTicker: SlideshowTicker {
    func waitForNextTick(duration: Duration) async throws {
        try await Task.sleep(for: .milliseconds(1))
    }
}

/// A ticker that never fires (until cancelled), parking the view model's
/// auto-advance so photo-report tests step the current asset deterministically.
private struct BlockingTicker: SlideshowTicker {
    func waitForNextTick(duration: Duration) async throws {
        try await Task.sleep(for: .seconds(3_600))
    }
}

private enum FakeError: Error { case boom }

/// Configurable, call-counting `ImmichAPI` that both plays and reports. Playback loads via
/// `preview`/`original` and never fetches `assetInfo`, so `assetInfoCalls` isolates the
/// adapter's own metadata fetches. `failImage` fails only `thumbnail`, the HA image path,
/// so playback keeps running.
private actor FakeAPI: ImmichAPI {
    private let assetList: [Asset]
    private let info: [String: AssetInfo]
    private let image: Data
    private let failImage: Bool
    private let failInfo: Bool
    private(set) var assetInfoCalls: [String: Int] = [:]
    private(set) var thumbnailCalls = 0
    private(set) var previewCalls = 0

    init(assets: [Asset], info: [String: AssetInfo], image: Data, failImage: Bool = false, failInfo: Bool = false) {
        self.assetList = assets
        self.info = info
        self.image = image
        self.failImage = failImage
        self.failInfo = failInfo
    }

    func serverVersion() async throws -> String { "test" }
    func albums() async throws -> [Album] { [] }
    func assets(albumID: String) async throws -> [Asset] { assetList }

    func assetInfo(assetID: String) async throws -> AssetInfo {
        assetInfoCalls[assetID, default: 0] += 1
        if failInfo { throw FakeError.boom }
        return info[assetID] ?? AssetInfo(id: assetID, takenAt: nil, city: nil, state: nil, country: nil)
    }

    func preview(assetID: String) async throws -> Data {
        previewCalls += 1
        return image
    }

    func thumbnail(assetID: String) async throws -> Data {
        thumbnailCalls += 1
        if failImage { throw FakeError.boom }
        return image
    }

    func original(assetID: String) async throws -> Data { image }
}

// 900 (T012): neutral-protocol face of the same fake — image requests route through the
// counted preview/thumbnail/original methods so the call-isolation assertions keep meaning.
extension FakeAPI: PhotoSourceProviding {
    func ensureReady() async throws {}
    func collections() async throws -> [SourceCollection] { [] }
    func assets(in collectionID: String) async throws -> [SourceAsset] {
        try await assets(albumID: collectionID).map {
            SourceAsset(id: $0.id, kind: MediaKind(rawValue: $0.type) ?? .other)
        }
    }
    func imageData(for assetID: String, fidelity: ImageFidelity) async throws -> Data {
        switch fidelity {
        case .thumbnail: return try await thumbnail(assetID: assetID)
        case .preview: return try await preview(assetID: assetID)
        case .original: return try await original(assetID: assetID)
        }
    }
    func metadata(for assetID: String) async throws -> AssetMetadata {
        let info = try await assetInfo(assetID: assetID)
        let parts = [info.city, info.country].compactMap { $0 }.filter { !$0.isEmpty }
        return AssetMetadata(
            capturedAt: info.takenAt,
            latitude: nil,
            longitude: nil,
            placeName: parts.isEmpty ? nil : parts.joined(separator: ", "),
            city: info.city,
            state: info.state,
            country: info.country
        )
    }
}

/// 710 T053 (FR-710-25): one Immich host that answers by path and records every request, so a
/// test can prove which host a link's asset ids reached. `serves: false` answers 404 to
/// everything. Internal, not private: `HAControlRoundTripTests` reuses it.
final class LinkRoutingTransport: HTTPTransport, @unchecked Sendable {
    static let albumID = "link-album"
    /// `2020-09-13T12:26:40Z`, the EXIF capture date every link asset reports.
    static let takenAt = Date(timeIntervalSince1970: 1_600_000_000)

    let host: String
    private let image: Data
    private let serves: Bool
    private let lock = NSLock()
    private var recorded: [URLRequest] = []

    init(host: String, image: Data = Data(), serves: Bool = true) {
        self.host = host
        self.image = image
        self.serves = serves
    }

    var requests: [URLRequest] { lock.withLock { recorded } }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        lock.withLock { recorded.append(request) }
        guard let url = request.url else { throw URLError(.badURL) }
        let body = serves ? route(url.path) : nil
        let response = HTTPURLResponse(url: url, statusCode: body == nil ? 404 : 200, httpVersion: nil, headerFields: nil)!
        return (body ?? Data(), response)
    }

    private func route(_ path: String) -> Data? {
        if path == "/api/server/version" {
            return Data(#"{"major":3,"minor":1,"patch":0}"#.utf8)
        }
        if path == "/api/albums/\(Self.albumID)" {
            return Data(#"{"id":"\#(Self.albumID)","albumName":"Iceland","order":"asc"}"#.utf8)
        }
        if path == "/api/search/metadata" {
            return Data(#"{"assets":{"items":[{"id":"link-asset-1","type":"IMAGE"},{"id":"link-asset-2","type":"IMAGE"}],"nextPage":null}}"#.utf8)
        }
        if path.hasSuffix("/thumbnail") {
            return image
        }
        if path.hasPrefix("/api/assets/") {
            let id = String(path.dropFirst("/api/assets/".count))
            return Data(#"{"id":"\#(id)","exifInfo":{"dateTimeOriginal":"2020-09-13T12:26:40.000Z","city":"Reykjavik","state":"Capital Region","country":"Iceland"}}"#.utf8)
        }
        return nil
    }
}

@MainActor
private final class StubScreen: ScreenControlling {
    var brightness: Double = 0.5
    var isIdleTimerDisabled = false
}
