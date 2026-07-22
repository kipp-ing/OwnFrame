import Foundation
import Testing
@testable import HAControlKit

/// Battery + charging diagnostic telemetry (spec 710 FR-710-23 / SC-710-07, feature 1200 US3).
///
/// Two read-only entities — `battery` (sensor) and `charging` (binary_sensor) — published as
/// **free** telemetry on a battery-bearing device and omitted entirely when there is no
/// battery source (Apple TV). Both publish in `.telemetryOnly` mode because they are
/// read-only sensors.
@MainActor
@Suite
struct BatteryTelemetryTests {

    // MARK: - Classification (T016)

    @Test
    func batteryAndChargingAreReadOnlySensors() {
        #expect(HAEntity.battery.isReadOnlySensor)
        #expect(HAEntity.charging.isReadOnlySensor)
        #expect(!HAEntity.battery.isControllable)
        #expect(!HAEntity.charging.isControllable)
    }

    // MARK: - Component mapping (T017)

    @Test
    func componentMapsBatteryToSensorAndChargingToBinarySensor() {
        #expect(HATopics.discoveryConfigTopic(deviceID: "dev1", entity: .battery)
            == "homeassistant/sensor/dev1/battery/config")
        #expect(HATopics.discoveryConfigTopic(deviceID: "dev1", entity: .charging)
            == "homeassistant/binary_sensor/dev1/charging/config")
    }

    // MARK: - Discovery (T018)

    @Test
    func batteryDiscoveryIsADiagnosticPercentSensorWithNoCommandTopic() throws {
        let json = try Self.object(from:
            HADiscovery.config(for: .battery, deviceID: "dev1", deviceName: "Slideshow", albumOptions: []))
        #expect(json["unique_id"] as? String == "dev1_battery")
        #expect(json["state_topic"] as? String == HATopics.stateTopic(deviceID: "dev1", entity: .battery))
        #expect(json["command_topic"] == nil)
        #expect(json["device_class"] as? String == "battery")
        #expect(json["unit_of_measurement"] as? String == "%")
        #expect(json["state_class"] as? String == "measurement")
        #expect(json["entity_category"] as? String == "diagnostic")
        #expect(json["name"] as? String == "Slideshow Battery")
    }

    @Test
    func chargingDiscoveryIsADiagnosticBinarySensorWithPayloadOnOff() throws {
        let json = try Self.object(from:
            HADiscovery.config(for: .charging, deviceID: "dev1", deviceName: "Slideshow", albumOptions: []))
        #expect(json["unique_id"] as? String == "dev1_charging")
        #expect(json["state_topic"] as? String == HATopics.stateTopic(deviceID: "dev1", entity: .charging))
        #expect(json["command_topic"] == nil)
        #expect(json["device_class"] as? String == "battery_charging")
        #expect(json["payload_on"] as? String == "ON")
        #expect(json["payload_off"] as? String == "OFF")
        #expect(json["entity_category"] as? String == "diagnostic")
        #expect(json["name"] as? String == "Slideshow Charging")
    }

    // MARK: - Echo / state (T019)

    @Test
    func echoPublishesBatteryPercentAndChargingOnForAReadingOnPower() async throws {
        let transport = FakeMQTTTransport()
        let battery = FakeBatteryReporting(hasBattery: true, reading: BatteryReading(level: 87, isOnPower: true))
        let coordinator = makeCoordinator(transport: transport, battery: battery,
            mode: .full, entities: [.battery, .charging])
        await coordinator.start()

        #expect(lastState(transport, .battery) == "87")
        #expect(lastState(transport, .charging) == "ON")

        await coordinator.stop()
    }

    @Test
    func echoPublishesChargingOffWhenNotOnPower() async throws {
        let transport = FakeMQTTTransport()
        let battery = FakeBatteryReporting(hasBattery: true, reading: BatteryReading(level: 20, isOnPower: false))
        let coordinator = makeCoordinator(transport: transport, battery: battery,
            mode: .full, entities: [.battery, .charging])
        await coordinator.start()

        #expect(lastState(transport, .battery) == "20")
        #expect(lastState(transport, .charging) == "OFF")

        await coordinator.stop()
    }

    @Test
    func batteryStateIsSkippedWhenLevelUnknownButChargingStillPublishes() async throws {
        let transport = FakeMQTTTransport()
        let battery = FakeBatteryReporting(hasBattery: true, reading: BatteryReading(level: nil, isOnPower: false))
        let coordinator = makeCoordinator(transport: transport, battery: battery,
            mode: .full, entities: [.battery, .charging])
        await coordinator.start()

        // No misleading percentage until a real reading exists...
        #expect(!transport.published.contains {
            $0.topic == HATopics.stateTopic(deviceID: "dev1", entity: .battery)
        }, "battery state must be skipped while the level is unknown")
        // ...yet battery discovery IS announced (the entity exists), and charging reports.
        #expect(transport.published.contains {
            $0.topic == HATopics.discoveryConfigTopic(deviceID: "dev1", entity: .battery)
        }, "battery discovery is still announced on a battery device")
        #expect(lastState(transport, .charging) == "OFF")

        await coordinator.stop()
    }

    // MARK: - Device omission (T019)

    @Test
    func noBatterySourceOmitsBothEntitiesFromAnnounce() async throws {
        let transport = FakeMQTTTransport()
        // Enabled in the set, but there is no source → nothing about them ships.
        let coordinator = makeCoordinator(transport: transport, battery: nil,
            mode: .full, entities: [.battery, .charging, .phase])
        await coordinator.start()

        for entity: HAEntity in [.battery, .charging] {
            #expect(!transport.published.contains {
                $0.topic == HATopics.discoveryConfigTopic(deviceID: "dev1", entity: entity)
            }, "\(entity.rawValue) discovery must be omitted with no battery source")
            #expect(!transport.published.contains {
                $0.topic == HATopics.stateTopic(deviceID: "dev1", entity: entity)
            }, "\(entity.rawValue) state must be omitted with no battery source")
        }
        await coordinator.stop()
    }

    @Test
    func hasBatteryFalseOmitsBothEntitiesFromAnnounce() async throws {
        let transport = FakeMQTTTransport()
        let battery = FakeBatteryReporting(hasBattery: false, reading: BatteryReading(level: nil, isOnPower: false))
        let coordinator = makeCoordinator(transport: transport, battery: battery,
            mode: .full, entities: [.battery, .charging, .phase])
        await coordinator.start()

        for entity: HAEntity in [.battery, .charging] {
            #expect(!transport.published.contains {
                $0.topic == HATopics.discoveryConfigTopic(deviceID: "dev1", entity: entity)
            }, "\(entity.rawValue) discovery must be omitted when hasBattery == false")
        }
        await coordinator.stop()
    }

    // MARK: - Free telemetry (SC-710-07)

    @Test
    func batteryAndChargingPublishUnderTelemetryOnlyMode() async throws {
        let transport = FakeMQTTTransport()
        let battery = FakeBatteryReporting(hasBattery: true, reading: BatteryReading(level: 55, isOnPower: true))
        let coordinator = makeCoordinator(transport: transport, battery: battery,
            mode: .telemetryOnly, entities: [.battery, .charging])
        await coordinator.start()

        for entity: HAEntity in [.battery, .charging] {
            #expect(transport.published.contains {
                $0.topic == HATopics.discoveryConfigTopic(deviceID: "dev1", entity: entity) && !$0.payload.isEmpty
            }, "\(entity.rawValue) discovery must publish free under telemetry-only mode")
        }
        #expect(lastState(transport, .battery) == "55")
        #expect(lastState(transport, .charging) == "ON")
        // Read-only telemetry never subscribes to a command topic.
        #expect(transport.subscriptions.isEmpty)

        await coordinator.stop()
    }

    // MARK: - Change signal (T019)

    @Test
    func batteryChangeSignalReEchoesBatteryAndCharging() async throws {
        let transport = FakeMQTTTransport()
        let battery = FakeBatteryReporting(hasBattery: true, reading: BatteryReading(level: 50, isOnPower: false))
        let coordinator = makeCoordinator(transport: transport, battery: battery,
            mode: .telemetryOnly, entities: [.battery, .charging])
        await coordinator.start()
        transport.published.removeAll()

        battery.emit(BatteryReading(level: 51, isOnPower: true))
        await settle()

        #expect(lastState(transport, .battery) == "51")
        #expect(lastState(transport, .charging) == "ON")

        await coordinator.stop()
    }

    // MARK: - helpers

    private func settle() async {
        for _ in 0..<50 { await Task.yield() }
    }

    /// Last retained-state payload published for `entity`, decoded as a string.
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
        battery: (any BatteryReporting)?,
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
            battery: battery,
            enabledEntities: entities,
            mode: mode
        )
    }
}

/// Injectable battery source for the host tests — the app adapter provides the real one over
/// `UIDevice`.
@MainActor
final class FakeBatteryReporting: BatteryReporting {
    var hasBattery: Bool
    var current: BatteryReading
    var onBatteryChange: (@MainActor () -> Void)?

    init(hasBattery: Bool, reading: BatteryReading) {
        self.hasBattery = hasBattery
        self.current = reading
    }

    /// Test lever: fire the coordinator's hook exactly as the real adapter would.
    func emit(_ reading: BatteryReading) {
        current = reading
        onBatteryChange?()
    }
}
