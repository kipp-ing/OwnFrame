import Foundation
import Testing
@testable import HAControlKit

@Suite
struct HADiscoveryTests {
    // @covers FR-700-06, FR-700-07
    @Test
    func playbackDiscoveryContainsStableTopicsAndDevice() throws {
        let first = HADiscovery.config(for: .playback, deviceID: "dev1", deviceName: "Slideshow", albumOptions: [])
        let second = HADiscovery.config(for: .playback, deviceID: "dev1", deviceName: "Slideshow", albumOptions: [])

        #expect(first == second)

        let json = try Self.object(from: first)
        #expect(json["unique_id"] as? String == "dev1_playback")
        #expect(json["availability_topic"] as? String == HATopics.availability(deviceID: "dev1"))
        #expect(json["command_topic"] as? String == HATopics.commandTopic(deviceID: "dev1", entity: .playback))
        #expect(json["state_topic"] as? String == HATopics.stateTopic(deviceID: "dev1", entity: .playback))
        #expect(json["payload_on"] as? String == "ON")
        #expect(json["payload_off"] as? String == "OFF")

        let device = try #require(json["device"] as? [String: Any])
        #expect(device["identifiers"] as? [String] == ["dev1"])
        #expect(device["name"] as? String == "Slideshow")
    }

    // @covers FR-700-24
    @Test
    func discoverySuggestsAnEntityIDFromTheIdentityNotTheName() throws {
        let id = "A85AFA17-91E9-4722-9F06-80FEC688515A"
        let battery = try Self.object(from: HADiscovery.config(
            for: .battery, deviceID: id, deviceName: "OwnFrame", albumOptions: []))
        #expect(battery["default_entity_id"] as? String == "sensor.ownframe_a85a_battery")

        // Snake-cased from the display name, in the entity's own HA domain.
        let place = try Self.object(from: HADiscovery.config(
            for: .clockCorner, deviceID: id, deviceName: "OwnFrame", albumOptions: []))
        #expect(place["default_entity_id"] as? String == "select.ownframe_a85a_clock_place")
        let light = try Self.object(from: HADiscovery.config(
            for: .brightness, deviceID: id, deviceName: "OwnFrame", albumOptions: []))
        #expect(light["default_entity_id"] as? String == "light.ownframe_a85a_brightness")

        // A rename never moves it (FR-700-22); a second frame never collides with the first.
        let renamed = try Self.object(from: HADiscovery.config(
            for: .battery, deviceID: id, deviceName: "Wohnzimmer", albumOptions: []))
        #expect(renamed["default_entity_id"] as? String == "sensor.ownframe_a85a_battery")
        let other = try Self.object(from: HADiscovery.config(
            for: .battery, deviceID: "FCE9EA58-6BF9-4BE1-8621-88BCFD849D50", deviceName: "OwnFrame", albumOptions: []))
        #expect(other["default_entity_id"] as? String == "sensor.ownframe_fce9_battery")
    }

    // @covers FR-700-24
    @Test
    func everyEntitySuggestsAnIDInItsDiscoveryDomain() throws {
        for entity in HAEntity.allCases {
            let json = try Self.object(from: HADiscovery.config(
                for: entity, deviceID: "dev1", deviceName: "OwnFrame", albumOptions: []))
            let suggested = try #require(json["default_entity_id"] as? String, "\(entity) has no default_entity_id")
            let domain = HATopics.discoveryConfigTopic(deviceID: "dev1", entity: entity).split(separator: "/")[1]
            #expect(suggested.hasPrefix("\(domain).ownframe_dev1_"), "\(entity): \(suggested)")
            #expect(suggested.allSatisfy { $0.isLowercase || $0.isNumber || $0 == "_" || $0 == "." })
        }
    }

    // @covers FR-700-25
    @Test
    func entityNamesDoNotRepeatSlideshow() throws {
        for entity in HAEntity.allCases {
            let json = try Self.object(from: HADiscovery.config(
                for: entity, deviceID: "dev1", deviceName: "OwnFrame", albumOptions: []))
            let name = try #require(json["name"] as? String)
            #expect(!name.contains("Slideshow"), "\(entity): \(name)")
        }
    }

    // @covers FR-700-13
    @Test
    func brightnessDiscoveryIsDimmableLightWithBrightnessTopics() throws {
        let data = HADiscovery.config(for: .brightness, deviceID: "dev1", deviceName: "Slideshow", albumOptions: [])
        let json = try Self.object(from: data)

        #expect(json["unique_id"] as? String == "dev1_brightness")
        #expect(json["availability_topic"] as? String == HATopics.availability(deviceID: "dev1"))
        // command_topic is kept (HA's default light schema requires it even with
        // on_command_type: brightness), but state_topic must NOT also be set: HA
        // treats a present state_topic as the authoritative ON/OFF state (expecting
        // "ON"/"OFF"), so one pointing at the same topic as brightness_state_topic
        // makes HA fail to parse the raw numeric brightness payload and show the
        // light as permanently "unknown" (found via live HA verification against a
        // real broker).
        #expect(json["command_topic"] as? String == HATopics.commandTopic(deviceID: "dev1", entity: .brightness))
        #expect(json["state_topic"] == nil)
        #expect(json["brightness_command_topic"] as? String == HATopics.commandTopic(deviceID: "dev1", entity: .brightness))
        #expect(json["brightness_state_topic"] as? String == HATopics.stateTopic(deviceID: "dev1", entity: .brightness))
        #expect(json["brightness_scale"] as? Int == 255)

        let device = try #require(json["device"] as? [String: Any])
        #expect(device["identifiers"] as? [String] == ["dev1"])
    }

    // @covers FR-700-14
    @Test
    func albumDiscoveryIsSelectWithOptions() throws {
        let options = ["Wohnzimmer", "Urlaub 2026"]
        let data = HADiscovery.config(for: .album, deviceID: "dev1", deviceName: "Slideshow", albumOptions: options)
        let json = try Self.object(from: data)

        #expect(json["unique_id"] as? String == "dev1_album")
        #expect(json["command_topic"] as? String == HATopics.commandTopic(deviceID: "dev1", entity: .album))
        #expect(json["state_topic"] as? String == HATopics.stateTopic(deviceID: "dev1", entity: .album))
        #expect(json["options"] as? [String] == options)
    }

    @Test
    func discoveryPayloadContainsNoCredentialFields() throws {
        let data = HADiscovery.config(for: .playback, deviceID: "dev1", deviceName: "Slideshow", albumOptions: [])
        let json = try Self.object(from: data)

        #expect(json["username"] == nil)
        #expect(json["password"] == nil)
        #expect(json["user"] == nil)
        #expect(json["pass"] == nil)
    }

    // @covers FR-710-01, FR-710-02
    @Test
    func orderDiscoveryHasOptionsArray() throws {
        let data = HADiscovery.config(for: .order, deviceID: "dev1", deviceName: "Slideshow", albumOptions: [])
        let json = try Self.object(from: data)

        #expect(json["unique_id"] as? String == "dev1_order")
        #expect(json["command_topic"] as? String == HATopics.commandTopic(deviceID: "dev1", entity: .order))
        #expect(json["state_topic"] as? String == HATopics.stateTopic(deviceID: "dev1", entity: .order))

        let options = try #require(json["options"] as? [String])
        #expect(options == ["shuffle", "sequential"])
    }

    // @covers FR-710-01, FR-710-03
    @Test
    func durationDiscoveryHasMinMaxStepAndUnit() throws {
        let data = HADiscovery.config(for: .duration, deviceID: "dev1", deviceName: "Slideshow", albumOptions: [])
        let json = try Self.object(from: data)

        #expect(json["unique_id"] as? String == "dev1_duration")
        #expect(json["command_topic"] as? String == HATopics.commandTopic(deviceID: "dev1", entity: .duration))
        #expect(json["state_topic"] as? String == HATopics.stateTopic(deviceID: "dev1", entity: .duration))

        #expect(json["min"] as? Int == 3)
        #expect(json["max"] as? Int == 600)
        #expect(json["step"] as? Int == 1)
        #expect(json["unit_of_measurement"] as? String == "s")
    }

    // @covers FR-710-01, FR-710-02
    @Test
    func transitionDiscoveryHasOptionsArray() throws {
        let data = HADiscovery.config(for: .transition, deviceID: "dev1", deviceName: "Slideshow", albumOptions: [])
        let json = try Self.object(from: data)

        #expect(json["unique_id"] as? String == "dev1_transition")
        #expect(json["command_topic"] as? String == HATopics.commandTopic(deviceID: "dev1", entity: .transition))
        #expect(json["state_topic"] as? String == HATopics.stateTopic(deviceID: "dev1", entity: .transition))

        let options = try #require(json["options"] as? [String])
        #expect(options == ["crossfade", "slide", "dissolve", "none"])
    }

    // @covers FR-710-01
    @Test
    func kenBurnsDiscoveryHasPayloadOnOff() throws {
        let data = HADiscovery.config(for: .kenBurns, deviceID: "dev1", deviceName: "Slideshow", albumOptions: [])
        let json = try Self.object(from: data)

        #expect(json["unique_id"] as? String == "dev1_ken_burns")
        #expect(json["command_topic"] as? String == HATopics.commandTopic(deviceID: "dev1", entity: .kenBurns))
        #expect(json["state_topic"] as? String == HATopics.stateTopic(deviceID: "dev1", entity: .kenBurns))
        #expect(json["payload_on"] as? String == "ON")
        #expect(json["payload_off"] as? String == "OFF")
    }

    // @covers FR-710-01, FR-710-02
    @Test
    func fitDiscoveryHasOptionsArray() throws {
        let data = HADiscovery.config(for: .fit, deviceID: "dev1", deviceName: "Slideshow", albumOptions: [])
        let json = try Self.object(from: data)

        #expect(json["unique_id"] as? String == "dev1_fit")
        #expect(json["command_topic"] as? String == HATopics.commandTopic(deviceID: "dev1", entity: .fit))
        #expect(json["state_topic"] as? String == HATopics.stateTopic(deviceID: "dev1", entity: .fit))

        let options = try #require(json["options"] as? [String])
        #expect(options == ["fit", "fill"])
    }

    // @covers FR-710-01, FR-710-02
    @Test
    func qualityDiscoveryHasOptionsArray() throws {
        let data = HADiscovery.config(for: .quality, deviceID: "dev1", deviceName: "Slideshow", albumOptions: [])
        let json = try Self.object(from: data)

        #expect(json["unique_id"] as? String == "dev1_quality")
        #expect(json["command_topic"] as? String == HATopics.commandTopic(deviceID: "dev1", entity: .quality))
        #expect(json["state_topic"] as? String == HATopics.stateTopic(deviceID: "dev1", entity: .quality))

        let options = try #require(json["options"] as? [String])
        #expect(options == ["preview", "original"])
    }

    // @covers FR-710-01
    @Test
    func clockDiscoveryHasPayloadOnOff() throws {
        let data = HADiscovery.config(for: .clock, deviceID: "dev1", deviceName: "Slideshow", albumOptions: [])
        let json = try Self.object(from: data)

        #expect(json["unique_id"] as? String == "dev1_clock")
        #expect(json["command_topic"] as? String == HATopics.commandTopic(deviceID: "dev1", entity: .clock))
        #expect(json["state_topic"] as? String == HATopics.stateTopic(deviceID: "dev1", entity: .clock))
        #expect(json["payload_on"] as? String == "ON")
        #expect(json["payload_off"] as? String == "OFF")
    }

    // @covers FR-710-01
    @Test
    func clockDateDiscoveryHasPayloadOnOff() throws {
        let data = HADiscovery.config(for: .clockDate, deviceID: "dev1", deviceName: "Slideshow", albumOptions: [])
        let json = try Self.object(from: data)

        #expect(json["unique_id"] as? String == "dev1_clock_date")
        #expect(json["command_topic"] as? String == HATopics.commandTopic(deviceID: "dev1", entity: .clockDate))
        #expect(json["state_topic"] as? String == HATopics.stateTopic(deviceID: "dev1", entity: .clockDate))
        #expect(json["payload_on"] as? String == "ON")
        #expect(json["payload_off"] as? String == "OFF")
    }

    // @covers FR-710-01, FR-710-02, FR-710-18
    @Test
    func clockCornerDiscoveryHasWidenedOptionsAndPlaceName() throws {
        let data = HADiscovery.config(for: .clockCorner, deviceID: "dev1", deviceName: "Slideshow", albumOptions: [])
        let json = try Self.object(from: data)

        // Entity id / topics stay `clock_corner` (retained-state compatibility), but
        // the options widen to the seven ClockCornerSetting raws and the display name
        // becomes "Clock Place" (510 data-model; no "Slideshow" since FR-700-25).
        #expect(json["unique_id"] as? String == "dev1_clock_corner")
        #expect(json["command_topic"] as? String == HATopics.commandTopic(deviceID: "dev1", entity: .clockCorner))
        #expect(json["state_topic"] as? String == HATopics.stateTopic(deviceID: "dev1", entity: .clockCorner))
        #expect(json["name"] as? String == "Clock Place")

        let options = try #require(json["options"] as? [String])
        #expect(options == ["topLeading", "topCenter", "topTrailing", "bottomLeading", "bottomCenter", "bottomTrailing", "random"])
        #expect(options == ClockCornerSetting.allCases.map(\.rawValue))
    }

    // @covers FR-710-01, FR-710-02
    @Test
    func clockStyleDiscoveryHasOptionsArray() throws {
        let data = HADiscovery.config(for: .clockStyle, deviceID: "dev1", deviceName: "Slideshow", albumOptions: [])
        let json = try Self.object(from: data)

        #expect(json["unique_id"] as? String == "dev1_clock_style")
        #expect(json["command_topic"] as? String == HATopics.commandTopic(deviceID: "dev1", entity: .clockStyle))
        #expect(json["state_topic"] as? String == HATopics.stateTopic(deviceID: "dev1", entity: .clockStyle))
        #expect(json["name"] as? String == "Clock Style")

        let options = try #require(json["options"] as? [String])
        #expect(options == ["digits", "pill", "analog"])
        #expect(options == ClockStyleSetting.allCases.map(\.rawValue))
    }

    // @covers FR-710-01, FR-710-02
    @Test
    func clockSizeDiscoveryHasOptionsArray() throws {
        let data = HADiscovery.config(for: .clockSize, deviceID: "dev1", deviceName: "Slideshow", albumOptions: [])
        let json = try Self.object(from: data)

        #expect(json["unique_id"] as? String == "dev1_clock_size")
        #expect(json["command_topic"] as? String == HATopics.commandTopic(deviceID: "dev1", entity: .clockSize))
        #expect(json["state_topic"] as? String == HATopics.stateTopic(deviceID: "dev1", entity: .clockSize))
        #expect(json["name"] as? String == "Clock Size")

        let options = try #require(json["options"] as? [String])
        #expect(options == ["room", "cozy"])
        #expect(options == ClockSizeSetting.allCases.map(\.rawValue))
    }

    private static func object(from data: Data) throws -> [String: Any] {
        try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    // @covers FR-710-06
    @Test
    func currentPhotoDiscoveryHasNoCommandTopicWithValueTemplate() throws {
        let data = HADiscovery.config(for: .currentPhoto, deviceID: "dev1", deviceName: "Slideshow", albumOptions: [])
        let json = try Self.object(from: data)

        // Sensor entity: NO command_topic
        #expect(json["command_topic"] == nil)
        #expect(json["state_topic"] as? String == "ownframe/dev1/current_photo/state")
        #expect(json["value_template"] as? String == "{{ value_json.id }}")
        #expect(json["json_attributes_topic"] as? String == "ownframe/dev1/current_photo/state")

        #expect(json["unique_id"] as? String == "dev1_current_photo")
        #expect(json["availability_topic"] as? String == HATopics.availability(deviceID: "dev1"))
        #expect(json["name"] as? String == "Current Photo")

        let device = try #require(json["device"] as? [String: Any])
        #expect(device["identifiers"] as? [String] == ["dev1"])
        #expect(device["name"] as? String == "Slideshow")
    }

    // @covers FR-710-05
    @Test
    func currentPhotoImageDiscoveryHasNoCommandOrStateTopicWithImageTopic() throws {
        let data = HADiscovery.config(for: .currentPhotoImage, deviceID: "dev1", deviceName: "Slideshow", albumOptions: [])
        let json = try Self.object(from: data)

        // Image entity: NO command_topic, NO state_topic
        #expect(json["command_topic"] == nil)
        #expect(json["state_topic"] == nil)
        #expect(json["image_topic"] as? String == "ownframe/dev1/current_photo_image/state")
        #expect(json["content_type"] as? String == "image/jpeg")

        #expect(json["unique_id"] as? String == "dev1_current_photo_image")
        #expect(json["availability_topic"] as? String == HATopics.availability(deviceID: "dev1"))
        #expect(json["name"] as? String == "Current Photo Image")

        let device = try #require(json["device"] as? [String: Any])
        #expect(device["identifiers"] as? [String] == ["dev1"])
        #expect(device["name"] as? String == "Slideshow")
    }

    // @covers FR-710-04
    @Test
    func nextButtonDiscoveryHasPayloadPressAndNoStateTopic() throws {
        let data = HADiscovery.config(for: .next, deviceID: "dev1", deviceName: "Slideshow", albumOptions: [])
        let json = try Self.object(from: data)
        #expect(json["unique_id"] as? String == "dev1_next")
        #expect(json["command_topic"] as? String == HATopics.commandTopic(deviceID: "dev1", entity: .next))
        #expect(json["payload_press"] as? String == "PRESS")
        #expect(json["state_topic"] == nil)
        #expect(json["name"] as? String == "Next")
    }

    // @covers FR-710-04
    @Test
    func previousButtonDiscoveryHasPayloadPressAndNoStateTopic() throws {
        let data = HADiscovery.config(for: .previous, deviceID: "dev1", deviceName: "Slideshow", albumOptions: [])
        let json = try Self.object(from: data)
        #expect(json["unique_id"] as? String == "dev1_previous")
        #expect(json["command_topic"] as? String == HATopics.commandTopic(deviceID: "dev1", entity: .previous))
        #expect(json["payload_press"] as? String == "PRESS")
        #expect(json["state_topic"] == nil)
        #expect(json["name"] as? String == "Previous")
    }

    // @covers FR-710-07
    @Test
    func diagnosticSensorsAreReadOnlyAndDiagnosticCategory() throws {
        // .frameStatus added 2026-07-26 (FR-710-24): same diagnostic-sensor shape.
        for entity in [HAEntity.phase, .photoCount, .version, .frameStatus] {
            let data = HADiscovery.config(for: entity, deviceID: "dev1", deviceName: "Slideshow", albumOptions: [])
            let json = try Self.object(from: data)
            #expect(json["state_topic"] as? String == HATopics.stateTopic(deviceID: "dev1", entity: entity))
            #expect(json["entity_category"] as? String == "diagnostic")
            #expect(json["command_topic"] == nil)
        }
    }
}
