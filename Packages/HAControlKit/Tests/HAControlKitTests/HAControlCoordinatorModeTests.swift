import Foundation
import Testing
@testable import HAControlKit

/// Free-telemetry / paid-control split (spec 1100 FR-1100-03 / FR-1100-03a, amended
/// 2026-07-20). `.telemetryOnly` publishes read-only sensor entities so Home Assistant can
/// *see* the frame, but subscribes to zero command topics and never acts on a command;
/// `.full` (the Automation unlock) is the unchanged read+control behaviour.
@MainActor
@Suite
struct HAControlCoordinatorModeTests {

    // MARK: - T043: entity partition (sensors vs controls)

    @Test
    func readOnlySensorsAreExactlyTheNonCommandEntities() {
        // frame_status joined the read-only set 2026-07-26 (FR-710-24 free telemetry).
        let sensors: Set<HAEntity> = [.currentPhoto, .currentPhotoImage, .phase, .photoCount, .version, .battery, .charging, .frameStatus]
        for entity in HAEntity.allCases {
            #expect(entity.isReadOnlySensor == sensors.contains(entity),
                    "\(entity.rawValue): isReadOnlySensor mismatch")
            #expect(entity.isControllable == !sensors.contains(entity),
                    "\(entity.rawValue): isControllable mismatch")
        }
    }

    // MARK: - T044: telemetry-only mode

    @Test
    func telemetryModePublishesSensorDiscoveryAndAvailabilityButNeverSubscribesOrPublishesControls() async throws {
        let transport = FakeMQTTTransport()
        let control = FakeRemoteControl()
        control.albumOptions = ["A"]
        let reporter = FakePhotoReporting(report: PhotoReport(
            assetID: "a1", imageData: nil, takenAt: nil, city: nil, state: nil, country: nil,
            albumID: "alb", albumName: "Album", phase: .playing, photoCount: 3))
        let coordinator = makeCoordinator(
            transport: transport, control: control, photoReporter: reporter,
            mode: .telemetryOnly,
            entities: [.playback, .brightness, .album, .phase, .photoCount, .version, .currentPhoto])

        await coordinator.start()

        // Availability + sensor discovery ARE published (HA can see the frame).
        #expect(transport.published.contains {
            $0.topic == HATopics.availability(deviceID: "dev1") && $0.payload.string == "online"
        })
        for sensor: HAEntity in [.phase, .photoCount, .version, .currentPhoto] {
            #expect(transport.published.contains {
                $0.topic == HATopics.discoveryConfigTopic(deviceID: "dev1", entity: sensor)
            }, "sensor \(sensor.rawValue) discovery should be published")
        }
        // No controllable entity is announced with a real config — HA must never show a
        // dead control. (An *empty* retained payload on the same topic is the removal
        // tombstone and is asserted separately below.)
        for controllable: HAEntity in [.playback, .brightness, .album] {
            #expect(!transport.published.contains {
                $0.topic == HATopics.discoveryConfigTopic(deviceID: "dev1", entity: controllable)
                    && !$0.payload.isEmpty
            }, "controllable \(controllable.rawValue) discovery must NOT publish a config in telemetry mode")
        }
        // Zero command-topic subscriptions (SC-1100-06).
        #expect(transport.subscriptions.isEmpty,
                "telemetry mode must subscribe to zero command topics, got \(transport.subscriptions)")

        await coordinator.stop()
    }

    @Test
    func telemetryModeIgnoresIncomingCommands() async throws {
        let transport = FakeMQTTTransport()
        let control = FakeRemoteControl()
        let coordinator = makeCoordinator(
            transport: transport, control: control, photoReporter: nil,
            mode: .telemetryOnly, entities: [.playback])

        await coordinator.handleIncoming(MQTTMessage(
            topic: HATopics.commandTopic(deviceID: "dev1", entity: .playback),
            payload: Data("OFF".utf8), retain: false))

        #expect(control.pauseCount == 0, "telemetry mode must not act on HA commands")
        #expect(transport.published.isEmpty, "telemetry mode must not echo command state")
    }

    @Test
    func telemetryModeStillPublishesPhotoTelemetry() async throws {
        let transport = FakeMQTTTransport()
        let reporter = FakePhotoReporting()
        let coordinator = makeCoordinator(
            transport: transport, control: FakeRemoteControl(), photoReporter: reporter,
            mode: .telemetryOnly, entities: [.currentPhoto, .currentPhotoImage, .phase, .photoCount])
        await coordinator.start()
        transport.published.removeAll()

        reporter.emit(PhotoReport(
            assetID: "asset-7", imageData: Data([0xFF, 0xD8]), takenAt: nil,
            city: "Berlin", state: nil, country: nil,
            albumID: "a", albumName: "A", phase: .playing, photoCount: 2))
        await settle()

        #expect(transport.published.contains {
            $0.topic == HATopics.stateTopic(deviceID: "dev1", entity: .currentPhoto)
        }, "photo metadata telemetry must publish free")
        #expect(transport.published.contains {
            $0.topic == HATopics.stateTopic(deviceID: "dev1", entity: .currentPhotoImage) && $0.payload == Data([0xFF, 0xD8])
        }, "photo image telemetry must publish free when its toggle is on")

        await coordinator.stop()
    }

    /// The upgrade path, which is the *common* path: a frame that ran the pre-gate build
    /// left a **retained** discovery config on the broker for every controllable entity.
    /// Skipping the publish does not remove those — the broker replays them to Home
    /// Assistant forever, and because every entity shares one availability topic (which
    /// telemetry mode still sets to "online"), HA renders them as live, interactive
    /// controls that silently do nothing. Removing a retained discovery config requires an
    /// explicit empty retained payload on the same topic, so telemetry mode must publish
    /// that tombstone (SC-1100-06 "zero controllable entities" / FR-1100-03a).
    @Test
    func telemetryModeTombstonesControlDiscoverySoAPreGateUpgradeLeavesNoDeadControls() async throws {
        let transport = FakeMQTTTransport()
        let control = FakeRemoteControl()
        control.albumOptions = ["A"]
        let coordinator = makeCoordinator(
            transport: transport, control: control, photoReporter: nil,
            mode: .telemetryOnly,
            entities: [.playback, .brightness, .album, .phase, .photoCount])

        await coordinator.start()

        // Every controllable entity gets an empty *retained* payload, whether or not it is
        // in the currently enabled set — a stale config can survive from any earlier run.
        for controllable in HAEntity.allCases where controllable.isControllable {
            #expect(transport.published.contains {
                $0.topic == HATopics.discoveryConfigTopic(deviceID: "dev1", entity: controllable)
                    && $0.payload.isEmpty && $0.retain
            }, "controllable \(controllable.rawValue) must be tombstoned with an empty retained payload")
        }

        // Sensors are untouched by the tombstone sweep.
        for sensor in HAEntity.allCases where sensor.isReadOnlySensor {
            #expect(!transport.published.contains {
                $0.topic == HATopics.discoveryConfigTopic(deviceID: "dev1", entity: sensor)
                    && $0.payload.isEmpty
            }, "sensor \(sensor.rawValue) must never be tombstoned")
        }

        await coordinator.stop()
    }

    /// The mirror of the above: `.full` must never tombstone, or buying Automation would
    /// erase the very entities it just unlocked.
    @Test
    func fullModeNeverTombstonesControlDiscovery() async throws {
        let transport = FakeMQTTTransport()
        let control = FakeRemoteControl()
        control.albumOptions = ["A"]
        let coordinator = makeCoordinator(
            transport: transport, control: control, photoReporter: nil,
            mode: .full, entities: [.playback, .brightness, .album, .phase])

        await coordinator.start()

        #expect(!transport.published.contains {
            $0.topic.contains("/config") && $0.payload.isEmpty
        }, "full mode must never publish an empty discovery payload")

        await coordinator.stop()
    }

    @Test
    func fullModeStillSubscribesAndPublishesControls() async throws {
        let transport = FakeMQTTTransport()
        let control = FakeRemoteControl()
        control.albumOptions = ["A"]
        let coordinator = makeCoordinator(
            transport: transport, control: control, photoReporter: nil,
            mode: .full, entities: [.playback, .brightness, .album, .phase])
        await coordinator.start()

        for controllable: HAEntity in [.playback, .brightness, .album] {
            #expect(transport.subscriptions.contains(HATopics.commandTopic(deviceID: "dev1", entity: controllable)),
                    "full mode must subscribe controllable \(controllable.rawValue)")
            #expect(transport.published.contains {
                $0.topic == HATopics.discoveryConfigTopic(deviceID: "dev1", entity: controllable)
            }, "full mode must publish controllable \(controllable.rawValue) discovery")
        }

        await coordinator.stop()
    }

    // MARK: - helpers

    private func settle() async {
        for _ in 0..<50 { await Task.yield() }
    }

    private func makeCoordinator(
        transport: FakeMQTTTransport,
        control: FakeRemoteControl,
        photoReporter: FakePhotoReporting?,
        mode: HAControlCoordinator.Mode,
        entities: Set<HAEntity>
    ) -> HAControlCoordinator {
        HAControlCoordinator(
            transport: transport,
            control: control,
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

private extension Data {
    var string: String? { String(data: self, encoding: .utf8) }
}
