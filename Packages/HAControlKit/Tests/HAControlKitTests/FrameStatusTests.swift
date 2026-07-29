import Foundation
import Testing
@testable import HAControlKit

/// The `frame_status` diagnostic sensor (FR-710-24, added 2026-07-26 alongside the 700
/// amendment FR-700-23): exactly two values, `running`/`inactive`, driven by an explicit
/// UI-visibility signal from the presenting layer — never inferred from view lifecycle.
/// Orthogonal to `phase`/`playback`/availability; free-tier telemetry (FR-1100-03a).
@MainActor
@Suite
struct FrameStatusTests {

    // MARK: - Discovery shape

    // @covers FR-710-24
    @Test
    func frameStatusDiscoveryIsDiagnosticSensorWithAvailabilityBindingAndNoCommandTopic() throws {
        let data = HADiscovery.config(for: .frameStatus, deviceID: "dev1", deviceName: "Slideshow", albumOptions: [])
        let json = try object(from: data)
        #expect(json["unique_id"] as? String == "dev1_frame_status")
        #expect(json["state_topic"] as? String == HATopics.stateTopic(deviceID: "dev1", entity: .frameStatus))
        #expect(json["availability_topic"] as? String == HATopics.availability(deviceID: "dev1"))
        #expect(json["entity_category"] as? String == "diagnostic")
        #expect(json["command_topic"] == nil)
        #expect(json["name"] as? String == "Slideshow Frame Status")
    }

    // @covers FR-710-24
    @Test
    func frameStatusIsAnHASensorComponent() {
        #expect(HATopics.discoveryConfigTopic(deviceID: "dev1", entity: .frameStatus)
            == "homeassistant/sensor/dev1/frame_status/config")
        #expect(HAEntity.frameStatus.rawValue == "frame_status")
    }

    // MARK: - Tiering (free read-only telemetry, FR-1100-03a)

    // @covers FR-710-24
    @Test
    func frameStatusIsAFreeTierReadOnlySensorAndEnabledByDefault() {
        #expect(HAEntity.frameStatus.isReadOnlySensor)
        #expect(!HAEntity.frameStatus.isControllable)
        #expect(!HAEntity.frameStatus.isBatteryEntity)
        #expect(HAEntity.defaultEnabled.contains(.frameStatus))
    }

    // @covers FR-710-24
    @Test
    func telemetryOnlyModeStillDiscoversAndPublishesFrameStatus() async throws {
        let transport = FakeMQTTTransport()
        let coordinator = makeCoordinator(
            transport: transport, mode: .telemetryOnly, entities: [.playback, .frameStatus])

        await coordinator.start()

        #expect(transport.published.contains {
            $0.topic == HATopics.discoveryConfigTopic(deviceID: "dev1", entity: .frameStatus)
                && !$0.payload.isEmpty && $0.retain
        }, "telemetry mode must publish frame_status discovery — it is free telemetry")
        #expect(transport.published.contains {
            $0.topic == HATopics.stateTopic(deviceID: "dev1", entity: .frameStatus)
                && $0.payload == Data("running".utf8) && $0.retain
        }, "telemetry mode must publish the frame_status state")
        #expect(transport.subscriptions.isEmpty,
                "frame_status carries no command topic — nothing to subscribe")

        await coordinator.stop()
    }

    // MARK: - The explicit visibility signal

    // @covers FR-710-24, SC-710-08
    @Test
    func hidingTheSurfacePublishesRetainedInactiveAndShowingPublishesRunning() async throws {
        let transport = FakeMQTTTransport()
        let coordinator = makeCoordinator(transport: transport, entities: [.playback, .frameStatus])
        await coordinator.start()
        transport.published.removeAll()

        await coordinator.setSurfaceVisible(false)
        #expect(transport.published.contains {
            $0.topic == HATopics.stateTopic(deviceID: "dev1", entity: .frameStatus)
                && $0.payload == Data("inactive".utf8) && $0.retain
        }, "a covered surface must publish retained `inactive`")

        transport.published.removeAll()
        await coordinator.setSurfaceVisible(true)
        #expect(transport.published.contains {
            $0.topic == HATopics.stateTopic(deviceID: "dev1", entity: .frameStatus)
                && $0.payload == Data("running".utf8) && $0.retain
        }, "dismissing the cover must publish retained `running`")

        await coordinator.stop()
    }

    // @covers SC-700-15, SC-710-08
    @Test
    func visibilityChangeTouchesNothingButTheFrameStatusTopic() async throws {
        let transport = FakeMQTTTransport()
        let reporter = FakePhotoReporting(report: PhotoReport(
            assetID: "a1", imageData: nil, takenAt: nil, city: nil, state: nil, country: nil,
            albumID: "alb", albumName: "Album", phase: .playing, photoCount: 3))
        let coordinator = makeCoordinator(
            transport: transport, photoReporter: reporter,
            entities: [.playback, .phase, .frameStatus])
        await coordinator.start()
        let connects = transport.connectCount
        let disconnects = transport.disconnectCount
        transport.published.removeAll()

        await coordinator.setSurfaceVisible(false)
        await coordinator.setSurfaceVisible(true)

        let statusTopic = HATopics.stateTopic(deviceID: "dev1", entity: .frameStatus)
        #expect(transport.published.allSatisfy { $0.topic == statusTopic },
                "a visibility change must publish on the frame_status topic only, got \(transport.published.map(\.topic))")
        #expect(transport.published.count == 2, "one publish per transition, no storm")
        #expect(!transport.published.contains { $0.topic == HATopics.availability(deviceID: "dev1") },
                "availability must never carry the surface visibility (FR-700-23)")
        #expect(transport.connectCount == connects, "no reconnect on a visibility change")
        #expect(transport.disconnectCount == disconnects, "no disconnect on a visibility change")

        await coordinator.stop()
    }

    // @covers FR-710-24
    @Test
    func redundantVisibilitySignalDoesNotRepublish() async throws {
        let transport = FakeMQTTTransport()
        let coordinator = makeCoordinator(transport: transport, entities: [.frameStatus])
        await coordinator.start()
        transport.published.removeAll()

        await coordinator.setSurfaceVisible(true)  // already visible
        #expect(transport.published.isEmpty, "same-value signal must be a no-op")

        await coordinator.setSurfaceVisible(false)
        transport.published.removeAll()
        await coordinator.setSurfaceVisible(false)  // already hidden
        #expect(transport.published.isEmpty, "same-value signal must be a no-op")

        await coordinator.stop()
    }

    // MARK: - Reconnect / announce carry the current visibility

    // @covers FR-710-24, SC-710-08
    @Test
    func reconnectRepublishesTheCurrentVisibility() async throws {
        let transport = FakeMQTTTransport()
        let coordinator = makeCoordinator(transport: transport, entities: [.playback, .frameStatus])
        await coordinator.start()
        await coordinator.setSurfaceVisible(false)  // a modal is up when the broker drops
        await coordinator.handleConnection(false)
        transport.published.removeAll()

        await coordinator.handleConnection(true)

        let statusTopic = HATopics.stateTopic(deviceID: "dev1", entity: .frameStatus)
        #expect(transport.published.contains {
            $0.topic == statusTopic && $0.payload == Data("inactive".utf8) && $0.retain
        }, "announce must republish the CURRENT visibility, not reset to running")
        #expect(!transport.published.contains {
            $0.topic == statusTopic && $0.payload == Data("running".utf8)
        }, "a reconnect under a modal must never claim `running`")

        await coordinator.stop()
    }

    // @covers FR-710-24
    @Test
    func visibilitySignalledBeforeStartSeedsTheAnnouncedState() async throws {
        let transport = FakeMQTTTransport()
        let coordinator = makeCoordinator(transport: transport, entities: [.frameStatus])

        // The presenting layer may build the coordinator while a sheet is already up
        // (foreground return with settings open). Disconnected: record only, no publish.
        await coordinator.setSurfaceVisible(false)
        #expect(transport.published.isEmpty)

        await coordinator.start()
        #expect(transport.published.contains {
            $0.topic == HATopics.stateTopic(deviceID: "dev1", entity: .frameStatus)
                && $0.payload == Data("inactive".utf8) && $0.retain
        }, "announce must publish the seeded visibility")

        await coordinator.stop()
    }

    // @covers FR-710-24
    @Test
    func announceDefaultsToRunningWhenNothingWasSignalled() async throws {
        let transport = FakeMQTTTransport()
        let coordinator = makeCoordinator(transport: transport, entities: [.frameStatus])

        await coordinator.start()

        #expect(transport.published.contains {
            $0.topic == HATopics.stateTopic(deviceID: "dev1", entity: .frameStatus)
                && $0.payload == Data("running".utf8) && $0.retain
        })

        await coordinator.stop()
    }

    // MARK: - helpers

    private func object(from data: Data) throws -> [String: Any] {
        try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private func makeCoordinator(
        transport: FakeMQTTTransport,
        photoReporter: FakePhotoReporting? = nil,
        mode: HAControlCoordinator.Mode = .full,
        entities: Set<HAEntity>
    ) -> HAControlCoordinator {
        HAControlCoordinator(
            transport: transport,
            control: FakeRemoteControl(),
            photoReporter: photoReporter,
            configStore: FakeBrokerConfigStore(config: BrokerConfig(
                host: "broker.local", port: 8883,
                username: "secret-user", password: "secret-pass", deviceID: "dev1")),
            deviceName: "Slideshow",
            enabledEntities: entities,
            mode: mode
        )
    }
}
