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
            api: RoundTripStubAPI(),
            albumID: "album-1",
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

private struct RoundTripStubTicker: SlideshowTicker {
    func waitForNextTick(duration: Duration) async throws {
        try await Task.sleep(for: .milliseconds(1))
    }
}

@MainActor
private final class RoundTripStubScreen: ScreenControlling {
    var brightness: Double = 0.5
    var isIdleTimerDisabled = false
}
