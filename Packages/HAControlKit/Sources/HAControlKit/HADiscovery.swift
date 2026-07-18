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
        case .phase, .photoCount, .version:
            // Read-only diagnostic sensors: no command topic, marked diagnostic so
            // HA files them under the device's diagnostics (FR-710-07).
            json["command_topic"] = nil
            json["entity_category"] = "diagnostic"
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
        }

        return (try? JSONSerialization.data(withJSONObject: json, options: [.sortedKeys])) ?? Data()
    }

    private static func name(for entity: HAEntity) -> String {
        switch entity {
        case .playback:
            "Slideshow Playback"
        case .brightness:
            "Slideshow Brightness"
        case .album:
            "Slideshow Album"
        case .order:
            "Slideshow Order"
        case .duration:
            "Slideshow Duration"
        case .transition:
            "Slideshow Transition"
        case .kenBurns:
            "Slideshow Ken Burns"
        case .fit:
            "Slideshow Fit"
        case .quality:
            "Slideshow Quality"
        case .clock:
            "Slideshow Clock"
        case .clockCorner:
            "Slideshow Clock Place"
        case .clockStyle:
            "Slideshow Clock Style"
        case .clockSize:
            "Slideshow Clock Size"
        case .clockDate:
            "Slideshow Clock Date"
        case .next:
            "Slideshow Next"
        case .previous:
            "Slideshow Previous"
        case .currentPhoto:
            "Slideshow Current Photo"
        case .currentPhotoImage:
            "Slideshow Current Photo Image"
        case .phase:
            "Slideshow Phase"
        case .photoCount:
            "Slideshow Photo Count"
        case .version:
            "Slideshow Version"
        }
    }
}
