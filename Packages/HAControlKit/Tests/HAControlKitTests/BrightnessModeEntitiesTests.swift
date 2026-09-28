import Foundation
import Testing
@testable import HAControlKit

/// Brightness Mode / Night Window Home Assistant entities (410, FR-410-08 / FR-410-19).
///
/// Three entities driven by an optional `BrightnessModeControlling` source, injected like
/// `BatteryReporting`: `brightness_mode` (select, controllable → Supporter-gated) and
/// `night_window` (switch, controllable → gated) mirror the effective mode / night toggle;
/// `night_active` (binary_sensor, read-only → free telemetry, like `charging`) reports whether
/// the in-app night window is currently active. All three are omitted entirely without a
/// source, exactly like battery/charging without one.
@MainActor
@Suite
struct BrightnessModeEntitiesTests {

    // MARK: - Classification

    @Test
    func brightnessModeAndNightWindowAreControllableNightActiveIsReadOnly() {
        #expect(HAEntity.brightnessMode.isControllable)
        #expect(HAEntity.nightWindow.isControllable)
        #expect(!HAEntity.brightnessMode.isReadOnlySensor)
        #expect(!HAEntity.nightWindow.isReadOnlySensor)

        #expect(HAEntity.nightActive.isReadOnlySensor)
        #expect(!HAEntity.nightActive.isControllable)
    }

    // MARK: - Component mapping

    @Test
    func componentMapsToSelectSwitchAndBinarySensor() {
        #expect(HATopics.discoveryConfigTopic(deviceID: "dev1", entity: .brightnessMode)
            == "homeassistant/select/dev1/brightness_mode/config")
        #expect(HATopics.discoveryConfigTopic(deviceID: "dev1", entity: .nightWindow)
            == "homeassistant/switch/dev1/night_window/config")
        #expect(HATopics.discoveryConfigTopic(deviceID: "dev1", entity: .nightActive)
            == "homeassistant/binary_sensor/dev1/night_active/config")
    }

    // MARK: - Discovery payloads

    @Test
    func brightnessModeDiscoveryIsASelectWithAutoFixedOptions() throws {
        let json = try Self.object(from:
            HADiscovery.config(for: .brightnessMode, deviceID: "dev1", deviceName: "Slideshow", albumOptions: []))
        #expect(json["unique_id"] as? String == "dev1_brightness_mode")
        #expect(json["command_topic"] as? String == HATopics.commandTopic(deviceID: "dev1", entity: .brightnessMode))
        #expect(json["state_topic"] as? String == HATopics.stateTopic(deviceID: "dev1", entity: .brightnessMode))
        let options = try #require(json["options"] as? [String])
        #expect(options == ["auto", "fixed"])
        #expect(options == BrightnessModeSetting.allCases.map(\.rawValue))
    }

    @Test
    func nightWindowDiscoveryIsASwitchWithPayloadOnOff() throws {
        let json = try Self.object(from:
            HADiscovery.config(for: .nightWindow, deviceID: "dev1", deviceName: "Slideshow", albumOptions: []))
        #expect(json["unique_id"] as? String == "dev1_night_window")
        #expect(json["command_topic"] as? String == HATopics.commandTopic(deviceID: "dev1", entity: .nightWindow))
        #expect(json["state_topic"] as? String == HATopics.stateTopic(deviceID: "dev1", entity: .nightWindow))
        #expect(json["payload_on"] as? String == "ON")
        #expect(json["payload_off"] as? String == "OFF")
    }

    @Test
    func nightActiveDiscoveryIsAReadOnlyBinarySensorWithPayloadOnOff() throws {
        let json = try Self.object(from:
            HADiscovery.config(for: .nightActive, deviceID: "dev1", deviceName: "Slideshow", albumOptions: []))
        #expect(json["unique_id"] as? String == "dev1_night_active")
        #expect(json["state_topic"] as? String == HATopics.stateTopic(deviceID: "dev1", entity: .nightActive))
        #expect(json["command_topic"] == nil)
        #expect(json["payload_on"] as? String == "ON")
        #expect(json["payload_off"] as? String == "OFF")
    }

    // MARK: - Device omission (no source → omitted like battery)

    @Test
    func noSourceOmitsAllThreeEntitiesFromAnnounce() async throws {
        let transport = FakeMQTTTransport()
        let coordinator = makeCoordinator(transport: transport, brightnessMode: nil,
            mode: .full, entities: [.brightnessMode, .nightWindow, .nightActive, .playback])
        await coordinator.start()

        for entity: HAEntity in [.brightnessMode, .nightWindow, .nightActive] {
            #expect(!transport.published.contains {
                $0.topic == HATopics.discoveryConfigTopic(deviceID: "dev1", entity: entity)
            }, "\(entity.rawValue) discovery must be omitted with no source")
            #expect(!transport.published.contains {
                $0.topic == HATopics.stateTopic(deviceID: "dev1", entity: entity)
            }, "\(entity.rawValue) state must be omitted with no source")
        }
        await coordinator.stop()
    }

    // MARK: - Unentitled: night_active free, the two controls gated

    @Test
    func unentitledPublishesNightActiveOnlyAndIgnoresControlCommands() async throws {
        let transport = FakeMQTTTransport()
        let source = FakeBrightnessModeControlling(mode: .fixed, isNightActive: true, isNightWindowEnabled: true)
        let coordinator = makeCoordinator(transport: transport, brightnessMode: source,
            mode: .telemetryOnly, entities: [.brightnessMode, .nightWindow, .nightActive])
        await coordinator.start()

        // Free telemetry: night_active discovery + state ARE published.
        #expect(transport.published.contains {
            $0.topic == HATopics.discoveryConfigTopic(deviceID: "dev1", entity: .nightActive) && !$0.payload.isEmpty
        }, "night_active discovery must publish free under telemetry-only mode")
        #expect(lastState(transport, .nightActive) == "ON")

        // Gated controls: no real discovery config for either.
        for controllable: HAEntity in [.brightnessMode, .nightWindow] {
            #expect(!transport.published.contains {
                $0.topic == HATopics.discoveryConfigTopic(deviceID: "dev1", entity: controllable) && !$0.payload.isEmpty
            }, "\(controllable.rawValue) discovery must NOT publish a config in telemetry mode")
        }
        #expect(transport.subscriptions.isEmpty, "telemetry mode must subscribe to zero command topics")

        // Commands ignored even if one somehow arrived (defense in depth, mirrors playback).
        await coordinator.handleIncoming(MQTTMessage(
            topic: HATopics.commandTopic(deviceID: "dev1", entity: .brightnessMode),
            payload: Data("auto".utf8), retain: false))
        await coordinator.handleIncoming(MQTTMessage(
            topic: HATopics.commandTopic(deviceID: "dev1", entity: .nightWindow),
            payload: Data("OFF".utf8), retain: false))
        #expect(source.setBrightnessModeCalls.isEmpty)
        #expect(source.setNightWindowEnabledCalls.isEmpty)

        await coordinator.stop()
    }

    // MARK: - Entitled: state echoes, commands routed, unknown option ignored

    @Test
    func entitledEchoesEffectiveModeAndNightState() async throws {
        let transport = FakeMQTTTransport()
        let source = FakeBrightnessModeControlling(mode: .auto, isNightActive: false, isNightWindowEnabled: true)
        let coordinator = makeCoordinator(transport: transport, brightnessMode: source,
            mode: .full, entities: [.brightnessMode, .nightWindow, .nightActive])
        await coordinator.start()

        #expect(lastState(transport, .brightnessMode) == "auto")
        #expect(lastState(transport, .nightWindow) == "ON")
        #expect(lastState(transport, .nightActive) == "OFF")

        await coordinator.stop()
    }

    @Test
    func brightnessModeCommandRoutesToSourceAndEchoesState() async throws {
        let transport = FakeMQTTTransport()
        let source = FakeBrightnessModeControlling(mode: .auto)
        let coordinator = makeCoordinator(transport: transport, brightnessMode: source,
            mode: .full, entities: [.brightnessMode])
        await coordinator.start()

        await coordinator.handleIncoming(MQTTMessage(
            topic: HATopics.commandTopic(deviceID: "dev1", entity: .brightnessMode),
            payload: Data("fixed".utf8), retain: false))

        #expect(source.setBrightnessModeCalls == [.fixed])
        #expect(lastState(transport, .brightnessMode) == "fixed")

        await coordinator.stop()
    }

    @Test
    func brightnessModeCommandUnknownOptionIsIgnored() async throws {
        let transport = FakeMQTTTransport()
        let source = FakeBrightnessModeControlling(mode: .auto)
        let coordinator = makeCoordinator(transport: transport, brightnessMode: source,
            mode: .full, entities: [.brightnessMode])
        await coordinator.start()

        await coordinator.handleIncoming(MQTTMessage(
            topic: HATopics.commandTopic(deviceID: "dev1", entity: .brightnessMode),
            payload: Data("bogus".utf8), retain: false))

        #expect(source.setBrightnessModeCalls.isEmpty)
        // Actual (unchanged) state is still re-echoed.
        #expect(lastState(transport, .brightnessMode) == "auto")

        await coordinator.stop()
    }

    @Test
    func nightWindowCommandOnOffRoutesToSourceAndEchoesState() async throws {
        let transport = FakeMQTTTransport()
        let source = FakeBrightnessModeControlling(isNightWindowEnabled: false)
        let coordinator = makeCoordinator(transport: transport, brightnessMode: source,
            mode: .full, entities: [.nightWindow])
        await coordinator.start()

        await coordinator.handleIncoming(MQTTMessage(
            topic: HATopics.commandTopic(deviceID: "dev1", entity: .nightWindow),
            payload: Data("ON".utf8), retain: false))

        #expect(source.setNightWindowEnabledCalls == [true])
        #expect(lastState(transport, .nightWindow) == "ON")

        await coordinator.stop()
    }

    // MARK: - Change callback re-echoes

    @Test
    func changeCallbackReEchoesAllThreeEnabledEntitiesWhenEntitled() async throws {
        let transport = FakeMQTTTransport()
        let source = FakeBrightnessModeControlling(mode: .auto, isNightActive: false, isNightWindowEnabled: false)
        let coordinator = makeCoordinator(transport: transport, brightnessMode: source,
            mode: .full, entities: [.brightnessMode, .nightWindow, .nightActive])
        await coordinator.start()
        transport.published.removeAll()

        source.brightnessMode = .fixed
        source.isNightActive = true
        source.isNightWindowEnabled = true
        source.emitChange()
        await settle()

        #expect(lastState(transport, .brightnessMode) == "fixed")
        #expect(lastState(transport, .nightActive) == "ON")
        #expect(lastState(transport, .nightWindow) == "ON")

        await coordinator.stop()
    }

    @Test
    func changeCallbackReEchoesOnlyNightActiveWhenUnentitled() async throws {
        let transport = FakeMQTTTransport()
        let source = FakeBrightnessModeControlling(mode: .auto, isNightActive: false, isNightWindowEnabled: false)
        let coordinator = makeCoordinator(transport: transport, brightnessMode: source,
            mode: .telemetryOnly, entities: [.brightnessMode, .nightWindow, .nightActive])
        await coordinator.start()
        transport.published.removeAll()

        source.isNightActive = true
        source.emitChange()
        await settle()

        #expect(lastState(transport, .nightActive) == "ON")
        #expect(!transport.published.contains {
            $0.topic == HATopics.stateTopic(deviceID: "dev1", entity: .brightnessMode)
        }, "brightness_mode must never be echoed while unentitled")
        #expect(!transport.published.contains {
            $0.topic == HATopics.stateTopic(deviceID: "dev1", entity: .nightWindow)
        }, "night_window must never be echoed while unentitled")

        await coordinator.stop()
    }

    // MARK: - helpers

    private func settle() async {
        for _ in 0..<50 { await Task.yield() }
    }

    private func lastState(_ transport: FakeMQTTTransport, _ entity: HAEntity) -> String? {
        transport.published.last {
            $0.topic == HATopics.stateTopic(deviceID: "dev1", entity: entity)
        }.flatMap { String(data: $0.payload, encoding: .utf8) }
    }

    private static func object(from data: Data) throws -> [String: Any] {
        try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private func makeCoordinator(
        transport: FakeMQTTTransport,
        brightnessMode: (any BrightnessModeControlling)?,
        mode: HAControlCoordinator.Mode,
        entities: Set<HAEntity>
    ) -> HAControlCoordinator {
        HAControlCoordinator(
            transport: transport,
            control: FakeRemoteControl(),
            photoReporter: nil,
            configStore: FakeBrokerConfigStore(config: BrokerConfig(
                host: "broker.local", port: 8883,
                username: "secret-user", password: "secret-pass", deviceID: "dev1")),
            deviceName: "Slideshow",
            brightnessMode: brightnessMode,
            enabledEntities: entities,
            mode: mode
        )
    }
}
