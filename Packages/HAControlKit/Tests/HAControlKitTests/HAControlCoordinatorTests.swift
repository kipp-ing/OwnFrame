import Foundation
import Testing
@testable import HAControlKit

@MainActor
@Suite
struct HAControlCoordinatorTests {
    @Test
    func startConnectsAnnouncesSubscribesAndEchoesPlaybackState() async throws {
        let transport = FakeMQTTTransport()
        let control = FakeRemoteControl()
        let coordinator = makeCoordinator(transport: transport, control: control)

        await coordinator.start()

        #expect(coordinator.connection == .connected)
        #expect(transport.will?.topic == HATopics.availability(deviceID: "dev1"))
        #expect(transport.will?.payload.string == "offline")
        #expect(transport.will?.retain == true)
        #expect(transport.published.containsMessage(topic: HATopics.availability(deviceID: "dev1"), payload: "online", retain: true))
        #expect(transport.published.contains { message in
            message.topic == HATopics.discoveryConfigTopic(deviceID: "dev1", entity: .playback) && message.retain
        })
        #expect(transport.subscriptions.contains(HATopics.commandTopic(deviceID: "dev1", entity: .playback)))
        #expect(transport.published.containsMessage(topic: HATopics.stateTopic(deviceID: "dev1", entity: .playback), payload: "ON", retain: true))

        await coordinator.stop()
    }

    @Test
    func playbackCommandsPauseResumeAndEchoActualState() async throws {
        let transport = FakeMQTTTransport()
        let control = FakeRemoteControl()
        let coordinator = makeCoordinator(transport: transport, control: control)

        await coordinator.handleIncoming(message("OFF", entity: .playback))

        #expect(control.pauseCount == 1)
        #expect(control.resumeCount == 0)
        #expect(transport.published.last?.topic == HATopics.stateTopic(deviceID: "dev1", entity: .playback))
        #expect(transport.published.last?.payload.string == "OFF")

        await coordinator.handleIncoming(message("ON", entity: .playback))

        #expect(control.pauseCount == 1)
        #expect(control.resumeCount == 1)
        #expect(transport.published.last?.topic == HATopics.stateTopic(deviceID: "dev1", entity: .playback))
        #expect(transport.published.last?.payload.string == "ON")
    }

    @Test
    func rapidPlaybackCommandsApplyLatestValidCommandAndEchoActualState() async throws {
        let transport = FakeMQTTTransport()
        let control = FakeRemoteControl()
        let coordinator = makeCoordinator(transport: transport, control: control)

        await coordinator.handleIncoming(message("OFF", entity: .playback))
        await coordinator.handleIncoming(message("ON", entity: .playback))
        await coordinator.handleIncoming(message("OFF", entity: .playback))

        #expect(control.playbackState == .paused)
        #expect(control.pauseCount == 2)
        #expect(control.resumeCount == 1)
        #expect(transport.published.last?.topic == HATopics.stateTopic(deviceID: "dev1", entity: .playback))
        #expect(transport.published.last?.payload.string == "OFF")
    }

    @Test
    func invalidPlaybackPayloadDoesNotChangeStateButEchoesCurrentState() async throws {
        let transport = FakeMQTTTransport()
        let control = FakeRemoteControl()
        let coordinator = makeCoordinator(transport: transport, control: control)

        await coordinator.handleIncoming(message("garbage", entity: .playback))

        #expect(control.pauseCount == 0)
        #expect(control.resumeCount == 0)
        #expect(control.playbackState == .playing)
        #expect(transport.published.last?.topic == HATopics.stateTopic(deviceID: "dev1", entity: .playback))
        #expect(transport.published.last?.payload.string == "ON")
    }

    @Test
    func localChangeEchoesActualPlaybackState() async throws {
        let transport = FakeMQTTTransport()
        let control = FakeRemoteControl()
        let coordinator = makeCoordinator(transport: transport, control: control)

        await coordinator.start()
        control.pause()
        control.onLocalChange?()
        try await Task.sleep(for: .milliseconds(10))

        #expect(transport.published.last?.topic == HATopics.stateTopic(deviceID: "dev1", entity: .playback))
        #expect(transport.published.last?.payload.string == "OFF")

        await coordinator.stop()
    }

    @Test
    func reconnectReAnnouncesDiscoveryAndState() async throws {
        let transport = FakeMQTTTransport()
        let control = FakeRemoteControl()
        let coordinator = makeCoordinator(transport: transport, control: control)

        await coordinator.start()
        let publishCountAfterStart = transport.published.count

        await coordinator.handleConnection(false)
        #expect(coordinator.connection == .disconnected)

        await coordinator.handleConnection(true)

        #expect(coordinator.connection == .connected)
        #expect(transport.published.count > publishCountAfterStart)
        #expect(transport.published.suffix(from: publishCountAfterStart).containsMessage(topic: HATopics.availability(deviceID: "dev1"), payload: "online", retain: true))
        #expect(transport.published.suffix(from: publishCountAfterStart).contains { message in
            message.topic == HATopics.discoveryConfigTopic(deviceID: "dev1", entity: .playback) && message.retain
        })
        #expect(transport.published.suffix(from: publishCountAfterStart).containsMessage(topic: HATopics.stateTopic(deviceID: "dev1", entity: .playback), payload: "ON", retain: true))

        await coordinator.stop()
    }

    @Test
    func brightnessCommandSetsClampedBrightnessAndEchoesAppliedValue() async throws {
        let transport = FakeMQTTTransport()
        let control = FakeRemoteControl()
        let coordinator = makeCoordinator(transport: transport, control: control, entities: [.brightness])

        await coordinator.handleIncoming(message("128", entity: .brightness))
        #expect(abs(control.brightness - 128.0 / 255.0) < 0.001)
        #expect(transport.published.last?.topic == HATopics.stateTopic(deviceID: "dev1", entity: .brightness))
        #expect(transport.published.last?.payload.string == "128")

        await coordinator.handleIncoming(message("300", entity: .brightness))
        #expect(control.brightness == 1.0)
        #expect(transport.published.last?.payload.string == "255")

        await coordinator.handleIncoming(message("-10", entity: .brightness))
        #expect(control.brightness == 0.0)
        #expect(transport.published.last?.payload.string == "0")
    }

    @Test
    func brightnessInvalidPayloadKeepsStateAndEchoesCurrent() async throws {
        let transport = FakeMQTTTransport()
        let control = FakeRemoteControl()
        control.brightness = 0.4
        let coordinator = makeCoordinator(transport: transport, control: control, entities: [.brightness])

        await coordinator.handleIncoming(message("not-a-number", entity: .brightness))

        #expect(control.brightness == 0.4)
        #expect(transport.published.last?.topic == HATopics.stateTopic(deviceID: "dev1", entity: .brightness))
        #expect(transport.published.last?.payload.string == "102") // round(0.4 * 255)
    }

    @Test
    func albumCommandSelectsValidAlbumAndEchoesSelection() async throws {
        let transport = FakeMQTTTransport()
        let control = FakeRemoteControl()
        control.albumOptions = ["Wohnzimmer", "Urlaub"]
        let coordinator = makeCoordinator(transport: transport, control: control, entities: [.album])

        await coordinator.handleIncoming(message("Urlaub", entity: .album))

        #expect(control.currentAlbum == "Urlaub")
        #expect(transport.published.last?.topic == HATopics.stateTopic(deviceID: "dev1", entity: .album))
        #expect(transport.published.last?.payload.string == "Urlaub")
    }

    @Test
    func albumCommandIgnoresUnknownAlbumAndEchoesCurrent() async throws {
        let transport = FakeMQTTTransport()
        let control = FakeRemoteControl()
        control.albumOptions = ["Wohnzimmer", "Urlaub"]
        control.currentAlbum = "Wohnzimmer"
        let coordinator = makeCoordinator(transport: transport, control: control, entities: [.album])

        await coordinator.handleIncoming(message("Nonexistent", entity: .album))

        #expect(control.currentAlbum == "Wohnzimmer")
        #expect(transport.published.last?.topic == HATopics.stateTopic(deviceID: "dev1", entity: .album))
        #expect(transport.published.last?.payload.string == "Wohnzimmer")
    }

    @Test
    func startEchoesAllEnabledEntityStates() async throws {
        let transport = FakeMQTTTransport()
        let control = FakeRemoteControl()
        control.brightness = 1.0
        control.albumOptions = ["Wohnzimmer"]
        control.currentAlbum = "Wohnzimmer"
        let coordinator = makeCoordinator(transport: transport, control: control, entities: [.playback, .brightness, .album])

        await coordinator.start()

        #expect(transport.subscriptions.contains(HATopics.commandTopic(deviceID: "dev1", entity: .brightness)))
        #expect(transport.subscriptions.contains(HATopics.commandTopic(deviceID: "dev1", entity: .album)))
        #expect(transport.published.containsMessage(topic: HATopics.stateTopic(deviceID: "dev1", entity: .brightness), payload: "255", retain: true))
        #expect(transport.published.containsMessage(topic: HATopics.stateTopic(deviceID: "dev1", entity: .album), payload: "Wohnzimmer", retain: true))

        await coordinator.stop()
    }

    @Test
    func startWithoutConfigDoesNotConnectOrPublish() async throws {
        let transport = FakeMQTTTransport()
        let control = FakeRemoteControl()
        let coordinator = HAControlCoordinator(
            transport: transport,
            control: control,
            configStore: FakeBrokerConfigStore(config: nil),
            deviceName: "Slideshow"
        )

        await coordinator.start()

        #expect(coordinator.connection == .disconnected)
        #expect(transport.connectCount == 0)
        #expect(transport.published.isEmpty)
    }

    @Test
    func failedConnectLeavesCoordinatorDisconnected() async throws {
        let transport = FakeMQTTTransport()
        transport.connectShouldThrow = true
        let control = FakeRemoteControl()
        let coordinator = makeCoordinator(transport: transport, control: control)

        await coordinator.start()

        #expect(coordinator.connection == .disconnected)
        #expect(transport.connectCount == 1)
        #expect(transport.published.isEmpty)
    }

    @Test
    func stopCancelsConsumersDisconnectsAndMarksDisconnected() async throws {
        let transport = FakeMQTTTransport()
        let control = FakeRemoteControl()
        let coordinator = makeCoordinator(transport: transport, control: control)

        await coordinator.start()
        await coordinator.stop()

        #expect(transport.disconnectCount == 1)
        #expect(coordinator.connection == .disconnected)
    }

    private func makeCoordinator(
        transport: FakeMQTTTransport,
        control: FakeRemoteControl,
        entities: Set<HAEntity> = [.playback]
    ) -> HAControlCoordinator {
        HAControlCoordinator(
            transport: transport,
            control: control,
            configStore: FakeBrokerConfigStore(config: BrokerConfig(
                host: "broker.local",
                port: 8883,
                username: "secret-user",
                password: "secret-pass",
                deviceID: "dev1"
            )),
            deviceName: "Slideshow",
            enabledEntities: entities
        )
    }

    private func message(_ payload: String, entity: HAEntity) -> MQTTMessage {
        MQTTMessage(
            topic: HATopics.commandTopic(deviceID: "dev1", entity: entity),
            payload: Data(payload.utf8),
            retain: false
        )
    }
}

private extension Data {
    var string: String? {
        String(data: self, encoding: .utf8)
    }
}

private extension Sequence where Element == MQTTMessage {
    func containsMessage(topic: String, payload: String, retain: Bool) -> Bool {
        contains { message in
            message.topic == topic && message.payload.string == payload && message.retain == retain
        }
    }
}

// MARK: - Settings Control Tests

@MainActor
extension HAControlCoordinatorTests {
    @Test
    func settingsOrderValidCommandAppliesAndPublishesNewState() async throws {
        let transport = FakeMQTTTransport()
        let control = FakeRemoteControl()
        let settings = FakeSettingsControl()
        let coordinator = makeCoordinator(transport: transport, control: control, settings: settings, entities: [.order])

        await coordinator.handleIncoming(message("sequential", entity: .order))

        #expect(settings.applyCount == 1)
        #expect(settings.themeSettings.order == .sequential)
        #expect(transport.published.containsMessage(topic: HATopics.stateTopic(deviceID: "dev1", entity: .order), payload: "sequential", retain: true))
    }

    @Test
    func settingsOrderInvalidCommandDoesNotApplyAndReEchoesActualState() async throws {
        let transport = FakeMQTTTransport()
        let control = FakeRemoteControl()
        let settings = FakeSettingsControl()
        let coordinator = makeCoordinator(transport: transport, control: control, settings: settings, entities: [.order])

        await coordinator.handleIncoming(message("random", entity: .order))

        #expect(settings.applyCount == 0)
        #expect(settings.themeSettings.order == .shuffle)
        #expect(transport.published.containsMessage(topic: HATopics.stateTopic(deviceID: "dev1", entity: .order), payload: "shuffle", retain: true))
    }

    @Test
    func settingsTransitionValidCommandAppliesAndPublishesNewState() async throws {
        let transport = FakeMQTTTransport()
        let control = FakeRemoteControl()
        let settings = FakeSettingsControl()
        let coordinator = makeCoordinator(transport: transport, control: control, settings: settings, entities: [.transition])

        await coordinator.handleIncoming(message("slide", entity: .transition))

        #expect(settings.applyCount == 1)
        #expect(settings.themeSettings.transition == .slide)
        #expect(transport.published.containsMessage(topic: HATopics.stateTopic(deviceID: "dev1", entity: .transition), payload: "slide", retain: true))
    }

    @Test
    func settingsFitValidCommandAppliesAndPublishesNewState() async throws {
        let transport = FakeMQTTTransport()
        let control = FakeRemoteControl()
        let settings = FakeSettingsControl()
        let coordinator = makeCoordinator(transport: transport, control: control, settings: settings, entities: [.fit])

        await coordinator.handleIncoming(message("fill", entity: .fit))

        #expect(settings.applyCount == 1)
        #expect(settings.themeSettings.fit == .fill)
        #expect(transport.published.containsMessage(topic: HATopics.stateTopic(deviceID: "dev1", entity: .fit), payload: "fill", retain: true))
    }

    @Test
    func settingsQualityValidCommandAppliesAndPublishesNewState() async throws {
        let transport = FakeMQTTTransport()
        let control = FakeRemoteControl()
        let settings = FakeSettingsControl()
        let coordinator = makeCoordinator(transport: transport, control: control, settings: settings, entities: [.quality])

        await coordinator.handleIncoming(message("original", entity: .quality))

        #expect(settings.applyCount == 1)
        #expect(settings.themeSettings.quality == .original)
        #expect(transport.published.containsMessage(topic: HATopics.stateTopic(deviceID: "dev1", entity: .quality), payload: "original", retain: true))
    }

    @Test
    func settingsClockCornerValidCommandAppliesAndPublishesNewState() async throws {
        let transport = FakeMQTTTransport()
        let control = FakeRemoteControl()
        let settings = FakeSettingsControl()
        let coordinator = makeCoordinator(transport: transport, control: control, settings: settings, entities: [.clockCorner])

        await coordinator.handleIncoming(message("topLeading", entity: .clockCorner))

        #expect(settings.applyCount == 1)
        #expect(settings.themeSettings.clockCorner == .topLeading)
        #expect(transport.published.containsMessage(topic: HATopics.stateTopic(deviceID: "dev1", entity: .clockCorner), payload: "topLeading", retain: true))
    }

    @Test
    func settingsDurationValidCommandAppliesAndEchoesValue() async throws {
        let transport = FakeMQTTTransport()
        let control = FakeRemoteControl()
        let settings = FakeSettingsControl()
        let coordinator = makeCoordinator(transport: transport, control: control, settings: settings, entities: [.duration])

        await coordinator.handleIncoming(message("42", entity: .duration))

        #expect(settings.applyCount == 1)
        #expect(settings.themeSettings.durationSeconds == 42)
        #expect(transport.published.containsMessage(topic: HATopics.stateTopic(deviceID: "dev1", entity: .duration), payload: "42", retain: true))
    }

    @Test
    func settingsDurationBelowRangeDoesNotApplyAndReEchoesActual() async throws {
        let transport = FakeMQTTTransport()
        let control = FakeRemoteControl()
        let settings = FakeSettingsControl()
        let coordinator = makeCoordinator(transport: transport, control: control, settings: settings, entities: [.duration])

        await coordinator.handleIncoming(message("2", entity: .duration))

        #expect(settings.applyCount == 0)
        #expect(settings.themeSettings.durationSeconds == 15)
        #expect(transport.published.containsMessage(topic: HATopics.stateTopic(deviceID: "dev1", entity: .duration), payload: "15", retain: true))
    }

    @Test
    func settingsDurationAboveRangeDoesNotApplyAndReEchoesActual() async throws {
        let transport = FakeMQTTTransport()
        let control = FakeRemoteControl()
        let settings = FakeSettingsControl()
        let coordinator = makeCoordinator(transport: transport, control: control, settings: settings, entities: [.duration])

        await coordinator.handleIncoming(message("601", entity: .duration))

        #expect(settings.applyCount == 0)
        #expect(settings.themeSettings.durationSeconds == 15)
        #expect(transport.published.containsMessage(topic: HATopics.stateTopic(deviceID: "dev1", entity: .duration), payload: "15", retain: true))
    }

    @Test
    func settingsDurationNonNumericDoesNotApplyAndReEchoesActual() async throws {
        let transport = FakeMQTTTransport()
        let control = FakeRemoteControl()
        let settings = FakeSettingsControl()
        let coordinator = makeCoordinator(transport: transport, control: control, settings: settings, entities: [.duration])

        await coordinator.handleIncoming(message("abc", entity: .duration))

        #expect(settings.applyCount == 0)
        #expect(settings.themeSettings.durationSeconds == 15)
        #expect(transport.published.containsMessage(topic: HATopics.stateTopic(deviceID: "dev1", entity: .duration), payload: "15", retain: true))
    }

    @Test
    func settingsKenBurnsONAppliesTrueAndPublishesState() async throws {
        let transport = FakeMQTTTransport()
        let control = FakeRemoteControl()
        let settings = FakeSettingsControl()
        let coordinator = makeCoordinator(transport: transport, control: control, settings: settings, entities: [.kenBurns])

        await coordinator.handleIncoming(message("ON", entity: .kenBurns))

        #expect(settings.applyCount == 1)
        #expect(settings.themeSettings.kenBurns == true)
        #expect(transport.published.containsMessage(topic: HATopics.stateTopic(deviceID: "dev1", entity: .kenBurns), payload: "ON", retain: true))
    }

    @Test
    func settingsKenBurnsOFFAppliesFalseAndPublishesState() async throws {
        let transport = FakeMQTTTransport()
        let control = FakeRemoteControl()
        let settings = FakeSettingsControl()
        let coordinator = makeCoordinator(transport: transport, control: control, settings: settings, entities: [.kenBurns])

        await coordinator.handleIncoming(message("OFF", entity: .kenBurns))

        #expect(settings.applyCount == 1)
        #expect(settings.themeSettings.kenBurns == false)
        #expect(transport.published.containsMessage(topic: HATopics.stateTopic(deviceID: "dev1", entity: .kenBurns), payload: "OFF", retain: true))
    }

    @Test
    func settingsKenBurnsInvalidDoesNotApplyAndReEchoesActual() async throws {
        let transport = FakeMQTTTransport()
        let control = FakeRemoteControl()
        let settings = FakeSettingsControl()
        let coordinator = makeCoordinator(transport: transport, control: control, settings: settings, entities: [.kenBurns])

        await coordinator.handleIncoming(message("MAYBE", entity: .kenBurns))

        #expect(settings.applyCount == 0)
        #expect(settings.themeSettings.kenBurns == false)
        #expect(transport.published.containsMessage(topic: HATopics.stateTopic(deviceID: "dev1", entity: .kenBurns), payload: "OFF", retain: true))
    }

    @Test
    func settingsClockONAppliesTrueAndPublishesState() async throws {
        let transport = FakeMQTTTransport()
        let control = FakeRemoteControl()
        let settings = FakeSettingsControl()
        let coordinator = makeCoordinator(transport: transport, control: control, settings: settings, entities: [.clock])

        await coordinator.handleIncoming(message("ON", entity: .clock))

        #expect(settings.applyCount == 1)
        #expect(settings.themeSettings.clockOn == true)
        #expect(transport.published.containsMessage(topic: HATopics.stateTopic(deviceID: "dev1", entity: .clock), payload: "ON", retain: true))
    }

    @Test
    func settingsClockOFFAppliesFalseAndPublishesState() async throws {
        let transport = FakeMQTTTransport()
        let control = FakeRemoteControl()
        let settings = FakeSettingsControl()
        let coordinator = makeCoordinator(transport: transport, control: control, settings: settings, entities: [.clock])

        await coordinator.handleIncoming(message("OFF", entity: .clock))

        #expect(settings.applyCount == 1)
        #expect(settings.themeSettings.clockOn == false)
        #expect(transport.published.containsMessage(topic: HATopics.stateTopic(deviceID: "dev1", entity: .clock), payload: "OFF", retain: true))
    }

    @Test
    func settingsClockInvalidDoesNotApplyAndReEchoesActual() async throws {
        let transport = FakeMQTTTransport()
        let control = FakeRemoteControl()
        let settings = FakeSettingsControl()
        let coordinator = makeCoordinator(transport: transport, control: control, settings: settings, entities: [.clock])

        await coordinator.handleIncoming(message("MAYBE", entity: .clock))

        #expect(settings.applyCount == 0)
        #expect(settings.themeSettings.clockOn == false)
        #expect(transport.published.containsMessage(topic: HATopics.stateTopic(deviceID: "dev1", entity: .clock), payload: "OFF", retain: true))
    }

    @Test
    func settingsClockDateONAppliesTrueAndPublishesState() async throws {
        let transport = FakeMQTTTransport()
        let control = FakeRemoteControl()
        let settings = FakeSettingsControl()
        let coordinator = makeCoordinator(transport: transport, control: control, settings: settings, entities: [.clockDate])

        await coordinator.handleIncoming(message("ON", entity: .clockDate))

        #expect(settings.applyCount == 1)
        #expect(settings.themeSettings.clockDate == true)
        #expect(transport.published.containsMessage(topic: HATopics.stateTopic(deviceID: "dev1", entity: .clockDate), payload: "ON", retain: true))
    }

    @Test
    func settingsClockDateOFFAppliesFalseAndPublishesState() async throws {
        let transport = FakeMQTTTransport()
        let control = FakeRemoteControl()
        let settings = FakeSettingsControl()
        let coordinator = makeCoordinator(transport: transport, control: control, settings: settings, entities: [.clockDate])

        await coordinator.handleIncoming(message("OFF", entity: .clockDate))

        #expect(settings.applyCount == 1)
        #expect(settings.themeSettings.clockDate == false)
        #expect(transport.published.containsMessage(topic: HATopics.stateTopic(deviceID: "dev1", entity: .clockDate), payload: "OFF", retain: true))
    }

    @Test
    func settingsClockDateInvalidDoesNotApplyAndReEchoesActual() async throws {
        let transport = FakeMQTTTransport()
        let control = FakeRemoteControl()
        let settings = FakeSettingsControl()
        let coordinator = makeCoordinator(transport: transport, control: control, settings: settings, entities: [.clockDate])

        await coordinator.handleIncoming(message("MAYBE", entity: .clockDate))

        #expect(settings.applyCount == 0)
        #expect(settings.themeSettings.clockDate == false)
        #expect(transport.published.containsMessage(topic: HATopics.stateTopic(deviceID: "dev1", entity: .clockDate), payload: "OFF", retain: true))
    }

    @Test
    func allSettingsEntitiesValidCommandPublishesStateWithRetainTrue() async throws {
        let transport = FakeMQTTTransport()
        let control = FakeRemoteControl()
        let settings = FakeSettingsControl()
        let entities: Set<HAEntity> = [.order, .duration, .transition, .kenBurns, .fit, .quality, .clock, .clockCorner, .clockDate]
        let coordinator = makeCoordinator(transport: transport, control: control, settings: settings, entities: entities)

        // Send valid command for each entity
        await coordinator.handleIncoming(message("sequential", entity: .order))
        await coordinator.handleIncoming(message("42", entity: .duration))
        await coordinator.handleIncoming(message("slide", entity: .transition))
        await coordinator.handleIncoming(message("ON", entity: .kenBurns))
        await coordinator.handleIncoming(message("fill", entity: .fit))
        await coordinator.handleIncoming(message("original", entity: .quality))
        await coordinator.handleIncoming(message("ON", entity: .clock))
        await coordinator.handleIncoming(message("topLeading", entity: .clockCorner))
        await coordinator.handleIncoming(message("ON", entity: .clockDate))

        // Every entity echoes exactly once per command, retained (SC-710-02 / FR-710-11).
        for entity in entities {
            let messages = transport.published.filter { $0.topic == HATopics.stateTopic(deviceID: "dev1", entity: entity) }
            #expect(messages.count == 1, "expected exactly one state publish for \(entity.rawValue), got \(messages.count)")
            for message in messages {
                #expect(message.retain == true, "State message for \(entity.rawValue) should have retain=true")
            }
        }
    }
}

// MARK: - Settings Coordinator Helper

extension HAControlCoordinatorTests {
    private func makeCoordinator(
        transport: FakeMQTTTransport,
        control: FakeRemoteControl,
        settings: FakeSettingsControl? = nil,
        entities: Set<HAEntity> = [.playback]
    ) -> HAControlCoordinator {
        HAControlCoordinator(
            transport: transport,
            control: control,
            settings: settings,
            configStore: FakeBrokerConfigStore(config: BrokerConfig(
                host: "broker.local",
                port: 8883,
                username: "secret-user",
                password: "secret-pass",
                deviceID: "dev1"
            )),
            deviceName: "Slideshow",
            enabledEntities: entities
        )
    }
}
