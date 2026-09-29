import Foundation

public enum HADiscovery {
    public static func config(
        for entity: HAEntity,
        deviceID: String,
        deviceName: String,
        albumOptions: [String]
    ) -> Data {
        var json: [String: Any] = [
            "unique_id": "\(deviceID)_\(entity.rawValue)",
            "availability_topic": HATopics.availability(deviceID: deviceID),
            "command_topic": HATopics.commandTopic(deviceID: deviceID, entity: entity),
            "state_topic": HATopics.stateTopic(deviceID: deviceID, entity: entity),
            "name": name(for: entity),
            "default_entity_id": defaultEntityID(for: entity, deviceID: deviceID),
            "device": [
                "identifiers": [deviceID],
                "name": deviceName,
            ],
        ]

        switch entity {
        case .playback:
            json["payload_on"] = "ON"
            json["payload_off"] = "OFF"
        case .brightness:
            // Dimmable light on the basic schema. `command_topic` is required by
            // HA's schema even with `on_command_type: brightness` (it's just not
            // used for turning on — brightness IS the on-command); but a `state_topic`
            // alongside `brightness_state_topic` makes HA expect "ON"/"OFF" strings
            // on the same topic as the raw numeric brightness payload, so only that
            // one must be dropped (shows as permanently "unknown" otherwise).
            json["state_topic"] = nil
            json["brightness_command_topic"] = HATopics.commandTopic(deviceID: deviceID, entity: entity)
            json["brightness_state_topic"] = HATopics.stateTopic(deviceID: deviceID, entity: entity)
            json["brightness_scale"] = 255
            json["on_command_type"] = "brightness"
            json["payload_off"] = "OFF"
        case .album:
            json["options"] = albumOptions
        case .order:
            json["options"] = PlayOrderSetting.allCases.map(\.rawValue)
        case .duration:
            json["min"] = 3
            json["max"] = 600
            json["step"] = 1
            json["unit_of_measurement"] = "s"
        case .transition:
            json["options"] = TransitionSetting.allCases.map(\.rawValue)
        case .kenBurns:
            json["payload_on"] = "ON"
            json["payload_off"] = "OFF"
        case .fit:
            json["options"] = FitSetting.allCases.map(\.rawValue)
        case .quality:
            json["options"] = QualitySetting.allCases.map(\.rawValue)
        case .clock:
            json["payload_on"] = "ON"
            json["payload_off"] = "OFF"
        case .clockDate:
            json["payload_on"] = "ON"
            json["payload_off"] = "OFF"
        case .clockCorner:
            json["options"] = ClockCornerSetting.allCases.map(\.rawValue)
        case .clockStyle:
            json["options"] = ClockStyleSetting.allCases.map(\.rawValue)
        case .clockSize:
            json["options"] = ClockSizeSetting.allCases.map(\.rawValue)
        case .next, .previous:
            // Stateless HA button: command topic + payload_press, no state topic.
            json["state_topic"] = nil
            json["payload_press"] = "PRESS"
        case .phase, .photoCount, .version, .frameStatus:
            // Read-only diagnostic sensors: no command topic, marked diagnostic so
            // HA files them under the device's diagnostics (FR-710-07). `frame_status`
            // (FR-710-24) shares the shape — incl. the availability binding above, so
            // an offline frame shows the entity as unavailable rather than a stale
            // `running`/`inactive`.
            json["command_topic"] = nil
            json["entity_category"] = "diagnostic"
        case .battery:
            // Read-only diagnostic percent sensor (FR-710-23). device_class + unit let HA
            // draw the battery glyph; state_class enables long-term statistics.
            json["command_topic"] = nil
            json["entity_category"] = "diagnostic"
            json["device_class"] = "battery"
            json["unit_of_measurement"] = "%"
            json["state_class"] = "measurement"
        case .charging:
            // Read-only diagnostic binary_sensor (FR-710-23): ON = on external power.
            json["command_topic"] = nil
            json["entity_category"] = "diagnostic"
            json["device_class"] = "battery_charging"
            json["payload_on"] = "ON"
            json["payload_off"] = "OFF"
        case .currentPhoto:
            json["command_topic"] = nil
            json["state_topic"] = HATopics.stateTopic(deviceID: deviceID, entity: entity)
            json["value_template"] = "{{ value_json.id }}"
            json["json_attributes_topic"] = HATopics.stateTopic(deviceID: deviceID, entity: entity)
        case .currentPhotoImage:
            json["command_topic"] = nil
            json["state_topic"] = nil
            json["image_topic"] = HATopics.stateTopic(deviceID: deviceID, entity: entity)
            json["content_type"] = "image/jpeg"
            break
        case .brightnessMode:
            // 410, FR-410-08: session-override select, `auto`/`fixed`.
            json["options"] = BrightnessModeSetting.allCases.map(\.rawValue)
        case .nightWindow:
            // 410, FR-410-19: remote switch for the app's night window.
            json["payload_on"] = "ON"
            json["payload_off"] = "OFF"
        case .nightActive:
            // 410, FR-410-19: read-only diagnostic binary_sensor — free telemetry, same
            // shape as `charging` minus its battery-specific device_class.
            json["command_topic"] = nil
            json["entity_category"] = "diagnostic"
            json["payload_on"] = "ON"
            json["payload_off"] = "OFF"
        case .brightnessModeStatus:
            // 410, FR-410-08: read-only diagnostic enum sensor of the effective mode — the
            // free counterpart of the gated `brightness_mode` select, same option values.
            json["command_topic"] = nil
            json["entity_category"] = "diagnostic"
            json["device_class"] = "enum"
            json["options"] = BrightnessModeSetting.allCases.map(\.rawValue)
        }

        return (try? JSONSerialization.data(withJSONObject: json, options: [.sortedKeys])) ?? Data()
    }

    /// FR-700-24: `<component>.ownframe_<short>_<entity>`, from the identity only — every frame is
    /// named "OwnFrame" by default, and HA's name-derived ids gave the second frame `_2`. HA uses
    /// it only at first registration, so frames registered earlier keep their ids.
    static func defaultEntityID(for entity: HAEntity, deviceID: String) -> String {
        let short = String(deviceID.lowercased().filter { $0.isLetter || $0.isNumber }.prefix(4))
        let slug = name(for: entity).lowercased().replacingOccurrences(of: " ", with: "_")
        return "\(HATopics.component(for: entity)).ownframe_\(short)_\(slug)"
    }

    /// FR-700-25: HA prefixes every friendly name with the device (frame) name, so no "Slideshow".
    private static func name(for entity: HAEntity) -> String {
        switch entity {
        case .playback:
            "Playback"
        case .brightness:
            "Brightness"
        case .album:
            "Album"
        case .order:
            "Order"
        case .duration:
            "Duration"
        case .transition:
            "Transition"
        case .kenBurns:
            "Ken Burns"
        case .fit:
            "Fit"
        case .quality:
            "Quality"
        case .clock:
            "Clock"
        case .clockCorner:
            "Clock Place"
        case .clockStyle:
            "Clock Style"
        case .clockSize:
            "Clock Size"
        case .clockDate:
            "Clock Date"
        case .next:
            "Next"
        case .previous:
            "Previous"
        case .currentPhoto:
            "Current Photo"
        case .currentPhotoImage:
            "Current Photo Image"
        case .phase:
            "Phase"
        case .photoCount:
            "Photo Count"
        case .version:
            "Version"
        case .battery:
            "Battery"
        case .charging:
            "Charging"
        case .frameStatus:
            "Frame Status"
        case .brightnessMode:
            "Brightness Mode"
        case .nightWindow:
            "Night Window"
        case .nightActive:
            "Night Active"
        case .brightnessModeStatus:
            "Brightness Mode Status"
        }
    }
}
