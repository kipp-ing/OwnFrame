//
//  HAControlRoundTripTests.swift
//  Immich SlideshowTests
//
//  US1 (710, T014): the full settings round-trip through REAL parts — an HA
//  command on the wire reaches HAControlCoordinator, is applied through the
//  real SlideshowRemoteControlAdapter into the real UserDefaultsThemeStore,
//  and exactly one echo goes back out; the suppressed observation callback
//  must not produce a second one.
//

import Foundation
import Testing
import HAControlKit
import ImmichClient
import OnboardingKit
import PhotoSourceKit
import PowerKit
import SlideshowKit
import ThemeKit
@testable import Immich_Slideshow

@MainActor
struct HAControlRoundTripTests {

    @Test func remoteOrderCommandAppliesToRealStoreAndEchoesExactlyOnce() async throws {
        let suiteName = "de.kippings.ImmichSlideshow.tests.roundtrip"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = UserDefaultsThemeStore(defaults: defaults)
        let slideshow = SlideshowViewModel(
            source: RoundTripStubAPI(),
            collectionID: "album-1",
            ticker: RoundTripStubTicker(),
            settingsStore: store
        )
        let adapter = SlideshowRemoteControlAdapter(
            slideshow: slideshow,
            powerManager: PowerManager(screen: RoundTripStubScreen()),
            themeStore: store
        )
        let transport = RecordingTransport()
        let coordinator = HAControlCoordinator(
            transport: transport,
            control: adapter,
            settings: adapter,
            configStore: StaticBrokerConfigStore(config: BrokerConfig(
                host: "broker.local",
                port: 8883,
                username: "user",
                password: "pass",
                deviceID: "dev1"
            )),
            deviceName: "Immich Slideshow",
            enabledEntities: [.order]
        )

        await coordinator.start()
        let baseline = transport.published.count
        #expect(store.settings.order == .shuffle)

        transport.inject(MQTTMessage(
            topic: HATopics.commandTopic(deviceID: "dev1", entity: .order),
            payload: Data("sequential".utf8),
            retain: false
        ))
        // Drain the stream consumer, the (suppressed) observation callback, and
        // any pending echo task.
        for _ in 0..<10 { await Task.yield() }
        try await Task.sleep(for: .milliseconds(50))

        #expect(store.settings.order == .sequential, "command must reach the real store")

        let orderTopic = HATopics.stateTopic(deviceID: "dev1", entity: .order)
        let echoes = transport.published.dropFirst(baseline).filter { $0.topic == orderTopic }
        #expect(echoes.count == 1, "exactly one echo for the applied command, got \(echoes.count)")
        #expect(echoes.first?.payload == Data("sequential".utf8))
        #expect(echoes.first?.retain == true)

        await coordinator.stop()
    }

    // 900 T031 (FR-900-11): the HA select lists the LIBRARY's sources — Photos sources
    // included — and a selection routes through the app-level switch (which owns the
    // cross-backend rebuild), not the engine's same-client album swap. Unknown options
    // still leave state unchanged (FR-700-14 semantics).
    @Test func sourceSelectListsLibrarySourcesAndRoutesToAppSwitch() async throws {
        let suiteName = "de.kippings.ImmichSlideshow.tests.sourceselect"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let slideshow = SlideshowViewModel(
            source: RoundTripStubAPI(),
            collectionID: "album-1",
            ticker: NonFiringTicker(),
            settingsStore: UserDefaultsThemeStore(defaults: defaults)
        )
        var switched: [String] = []
        let adapter = SlideshowRemoteControlAdapter(
            slideshow: slideshow,
            powerManager: PowerManager(screen: RoundTripStubScreen()),
            sources: [
                Source(id: "src-a1", label: "Wohnzimmer", kind: .album(albumID: "album-1")),
                Source(id: "src-photos", label: "Family", kind: .photoLibrary(collectionID: "pl-family")),
            ],
            activeSourceID: "src-a1",
            onSelectSource: { switched.append($0) }
        )

        #expect(adapter.albumOptions == ["Wohnzimmer", "Family"],
                "the select lists library sources of every kind")
        #expect(adapter.currentAlbum == "Wohnzimmer")

        adapter.selectAlbum("Family")
        #expect(switched == ["src-photos"], "selection routes to the app-level source switch")
        #expect(adapter.currentAlbum == "Family")

        adapter.selectAlbum("Unknown Option")
        #expect(switched == ["src-photos"], "an unknown option changes nothing")
        #expect(adapter.currentAlbum == "Family")
    }

    // 900 T031 (FR-900-11, R7): a Photos-backed show publishes current-photo metadata
    // through the engine's neutral pass-through — the capture date flows, the place
    // fields stay empty (no geocoding), and nothing errors on the missing Immich API.
    @Test func photosSourceReportsDateOnlyMetadataThroughNeutralPath() async throws {
        let suiteName = "de.kippings.ImmichSlideshow.tests.photosmeta"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let slideshow = SlideshowViewModel(
            source: PhotosStubSource(),
            collectionID: "pl-family",
            ticker: NonFiringTicker(),
            settingsStore: UserDefaultsThemeStore(defaults: defaults)
        )
        let adapter = SlideshowRemoteControlAdapter(
            slideshow: slideshow,
            powerManager: PowerManager(screen: RoundTripStubScreen()),
            isPhotoLibrarySource: true
        )

        await slideshow.start()
        for _ in 0..<10 { await Task.yield() }
        try await Task.sleep(for: .milliseconds(50))

        let report = adapter.currentPhotoReport
        #expect(report.assetID != nil, "the report follows the running show")
        #expect(report.takenAt == PhotosStubSource.capturedAt, "the capture date publishes")
        #expect(report.city == nil, "no geocoding — place fields stay empty (R7)")
        #expect(report.state == nil)
        #expect(report.country == nil)
    }

    @Test func chromeTogglePauseEchoesPlaybackStateToHA() async throws {
        // The chrome play/pause button calls `viewModel.togglePause()` directly
        // (SlideshowChrome.swift), never `adapter.pause()/resume()`. The adapter
        // must observe the ViewModel's own `isPaused`, not rely on being called
        // through, or a genuinely local pause never reaches HA.
        let slideshow = SlideshowViewModel(
            source: RoundTripStubAPI(),
            collectionID: "album-1",
            ticker: RoundTripStubTicker(),
            settingsStore: UserDefaultsThemeStore(defaults: try #require(UserDefaults(suiteName: "de.kippings.ImmichSlideshow.tests.roundtrip.playback")))
        )
        let adapter = SlideshowRemoteControlAdapter(
            slideshow: slideshow,
            powerManager: PowerManager(screen: RoundTripStubScreen())
        )
        let transport = RecordingTransport()
        let coordinator = HAControlCoordinator(
            transport: transport,
            control: adapter,
            configStore: StaticBrokerConfigStore(config: BrokerConfig(
                host: "broker.local", port: 8883, username: "user", password: "pass", deviceID: "dev2"
            )),
            deviceName: "Immich Slideshow",
            enabledEntities: [.playback]
        )

        await coordinator.start()
        let baseline = transport.published.count

        slideshow.togglePause()
        for _ in 0..<10 { await Task.yield() }
        try await Task.sleep(for: .milliseconds(50))

        let playbackTopic = HATopics.stateTopic(deviceID: "dev2", entity: .playback)
        let echoes = transport.published.dropFirst(baseline).filter { $0.topic == playbackTopic }
        #expect(echoes.count == 1, "exactly one echo for the local pause, got \(echoes.count)")
        #expect(echoes.first?.payload == Data("OFF".utf8))

        await coordinator.stop()
    }

    // Session 2 (open bug): pressing "next" from HA left `sensor.current_photo`
    // stuck on the same asset ID live. This drives the exact HA path on the host —
    // an incoming `.next` command reaches HAControlCoordinator, is dispatched to the
    // real adapter's `showNext()`, advances the real (shuffle-ordered, multi-asset)
    // SlideshowViewModel, and the observation re-arm publishes a *new* current_photo.
    // A non-firing ticker parks auto-advance so ONLY the command moves the photo.
    // Asserts both handover branches at once: the photo advanced (b) AND the sensor
    // echoed the new id (a).
    @Test func remoteNextCommandAdvancesPhotoAndPublishesNewCurrentPhoto() async throws {
        let suiteName = "de.kippings.ImmichSlideshow.tests.roundtrip.next"
        let defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let store = UserDefaultsThemeStore(defaults: defaults)
        store.settings.order = .shuffle // the live default
        let assets = (1...6).map { Asset(id: "asset-\($0)", type: "IMAGE") }
        let slideshow = SlideshowViewModel(
            source: NextStubAPI(assets: assets),
            collectionID: "album-1",
            ticker: NonFiringTicker(),
            settingsStore: store,
            rng: SeededRNG(seed: 42)
        )
        let adapter = SlideshowRemoteControlAdapter(
            slideshow: slideshow,
            powerManager: PowerManager(screen: RoundTripStubScreen()),
            albums: [Album(id: "album-1", name: "Family")],
            themeStore: store,
            api: NextStubAPI(assets: assets)
        )

        await slideshow.start()
        for _ in 0..<50 where slideshow.phase != .playing { await Task.yield() }
        #expect(slideshow.phase == .playing, "slideshow must be playing before the command")

        let transport = RecordingTransport()
        let coordinator = HAControlCoordinator(
            transport: transport,
            control: adapter,
            photoReporter: adapter,
            configStore: StaticBrokerConfigStore(config: BrokerConfig(
                host: "broker.local", port: 8883, username: "user", password: "pass", deviceID: "devnext"
            )),
            deviceName: "Immich Slideshow",
            enabledEntities: [.next, .currentPhoto]
        )
        await coordinator.start()

        let beforeID = slideshow.currentAssetID
        let baseline = transport.published.count
        let photoTopic = HATopics.stateTopic(deviceID: "devnext", entity: .currentPhoto)

        transport.inject(MQTTMessage(
            topic: HATopics.commandTopic(deviceID: "devnext", entity: .next),
            payload: Data(),
            retain: false
        ))

        // Drain the full chain: stream consumer -> showNext -> observation re-arm
        // Task -> async rebuildPhotoReport -> onPhotoChange -> schedulePhotoPublish
        // Task -> publish. Poll until a current_photo publish appears.
        var photoEchoes: [MQTTMessage] = []
        for _ in 0..<40 {
            for _ in 0..<10 { await Task.yield() }
            try await Task.sleep(for: .milliseconds(20))
            photoEchoes = Array(transport.published.dropFirst(baseline)).filter { $0.topic == photoTopic }
            if !photoEchoes.isEmpty { break }
        }

        // Branch (b): the photo actually advanced on the view model.
        #expect(slideshow.currentAssetID != beforeID,
                "next must advance the current asset (was \(beforeID ?? "nil"))")

        // Branch (a): the current_photo sensor echoed the NEW asset id.
        let lastEcho = try #require(photoEchoes.last, "next must publish a current_photo update")
        let json = try JSONSerialization.jsonObject(with: lastEcho.payload) as? [String: Any]
        let publishedID = json?["id"] as? String
        #expect(publishedID == slideshow.currentAssetID,
                "current_photo must carry the new asset id (published=\(publishedID ?? "nil"), current=\(slideshow.currentAssetID ?? "nil"))")

        await coordinator.stop()
    }
}

// MARK: - Local fakes (app test target has no access to HAControlKit's test fakes)

private final class RecordingTransport: MQTTTransport, @unchecked Sendable {
    private(set) var published: [MQTTMessage] = []
    private var incomingContinuation: AsyncStream<MQTTMessage>.Continuation?

    lazy var incoming: AsyncStream<MQTTMessage> = AsyncStream { continuation in
        self.incomingContinuation = continuation
    }
    lazy var connectionEvents: AsyncStream<Bool> = AsyncStream { _ in }

    func connect(will: MQTTMessage) async throws {}
    func disconnect() async {}
    func publish(_ message: MQTTMessage) async throws { published.append(message) }
    func subscribe(_ topicFilter: String) async throws {}

    func inject(_ message: MQTTMessage) {
        incomingContinuation?.yield(message)
    }
}

private struct StaticBrokerConfigStore: BrokerConfigStore {
    var config: BrokerConfig?
    func load() -> BrokerConfig? { config }
}

private struct RoundTripStubAPI: ImmichAPI {
    func serverVersion() async throws -> String { "test" }
    func albums() async throws -> [Album] { [] }
    func assets(albumID: String) async throws -> [Asset] { [] }
    func preview(assetID: String) async throws -> Data { Data() }
}

// 900 (T012): the engine consumes the neutral protocol; the adapter still takes ImmichAPI,
// so the stubs conform to both.
extension RoundTripStubAPI: PhotoSourceProviding {
    func ensureReady() async throws {}
    func collections() async throws -> [SourceCollection] { [] }
    func assets(in collectionID: String) async throws -> [SourceAsset] { [] }
    func imageData(for assetID: String, fidelity: ImageFidelity) async throws -> Data { Data() }
    func metadata(for assetID: String) async throws -> AssetMetadata {
        AssetMetadata(capturedAt: nil, latitude: nil, longitude: nil, placeName: nil)
    }
}

/// Photos-shaped source: playable images whose neutral metadata carries a capture date
/// (and coordinates) but no place name — exactly what a PhotoLibraryProvider-backed
/// show reports (R7, no geocoding).
private struct PhotosStubSource: PhotoSourceProviding {
    static let capturedAt = Date(timeIntervalSince1970: 1_718_462_400)

    func ensureReady() async throws {}
    func collections() async throws -> [SourceCollection] { [] }
    func assets(in collectionID: String) async throws -> [SourceAsset] {
        [SourceAsset(id: "pl-1", kind: .image), SourceAsset(id: "pl-2", kind: .image)]
    }
    func imageData(for assetID: String, fidelity: ImageFidelity) async throws -> Data { Data([9]) }
    func metadata(for assetID: String) async throws -> AssetMetadata {
        AssetMetadata(capturedAt: Self.capturedAt, latitude: 52.5, longitude: 13.4, placeName: nil)
    }
}

private struct RoundTripStubTicker: SlideshowTicker {
    func waitForNextTick(duration: Duration) async throws {
        try await Task.sleep(for: .milliseconds(1))
    }
}

/// Never fires (until cancelled), so the auto-advance ticker is parked and only an
/// explicit `showNext()` moves the photo — makes the `.next` command deterministic.
private struct NonFiringTicker: SlideshowTicker {
    func waitForNextTick(duration: Duration) async throws {
        try await Task.sleep(for: .seconds(3_600))
    }
}

/// Playable album stub: N image assets, empty preview bytes (enough for the view
/// model to advance the current asset id without decoding real images).
private struct NextStubAPI: ImmichAPI {
    let assets: [Asset]
    func serverVersion() async throws -> String { "test" }
    func albums() async throws -> [Album] { [] }
    func assets(albumID: String) async throws -> [Asset] { assets }
    func preview(assetID: String) async throws -> Data { Data() }
}

extension NextStubAPI: PhotoSourceProviding {
    func ensureReady() async throws {}
    func collections() async throws -> [SourceCollection] { [] }
    func assets(in collectionID: String) async throws -> [SourceAsset] {
        assets.map { SourceAsset(id: $0.id, kind: MediaKind(rawValue: $0.type) ?? .other) }
    }
    func imageData(for assetID: String, fidelity: ImageFidelity) async throws -> Data { Data() }
    func metadata(for assetID: String) async throws -> AssetMetadata {
        AssetMetadata(capturedAt: nil, latitude: nil, longitude: nil, placeName: nil)
    }
}

/// Deterministic RNG (SplitMix64) so the shuffle order is reproducible in tests.
private struct SeededRNG: RandomNumberGenerator {
    private var state: UInt64
    init(seed: UInt64) { state = seed }
    mutating func next() -> UInt64 {
        state &+= 0x9E3779B97F4A7C15
        var z = state
        z = (z ^ (z >> 30)) &* 0xBF58476D1CE4E5B9
        z = (z ^ (z >> 27)) &* 0x94D049BB133111EB
        return z ^ (z >> 31)
    }
}

@MainActor
private final class RoundTripStubScreen: ScreenControlling {
    var brightness: Double = 0.5
    var isIdleTimerDisabled = false
}
