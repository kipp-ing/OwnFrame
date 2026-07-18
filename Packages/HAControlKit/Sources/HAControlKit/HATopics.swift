import Foundation

public enum HATopics {
    public static func base(deviceID: String) -> String {
        "immichslideshow/\(deviceID)"
    }

    public static func availability(deviceID: String) -> String {
        "\(base(deviceID: deviceID))/availability"
    }

    public static func commandTopic(deviceID: String, entity: HAEntity) -> String {
        "\(base(deviceID: deviceID))/\(entity.rawValue)/set"
    }

    public static func stateTopic(deviceID: String, entity: HAEntity) -> String {
        "\(base(deviceID: deviceID))/\(entity.rawValue)/state"
    }

    public static func discoveryConfigTopic(deviceID: String, entity: HAEntity) -> String {
        "homeassistant/\(component(for: entity))/\(deviceID)/\(entity.rawValue)/config"
    }

    private static func component(for entity: HAEntity) -> String {
        switch entity {
        case .playback:
            "switch"
        case .brightness:
            "light"
        case .album:
            "select"
        case .order:
            "select"
        case .duration:
            "number"
        case .transition:
            "select"
        case .kenBurns:
            "switch"
        case .fit:
            "select"
        case .quality:
            "select"
        case .clock:
            "switch"
        case .clockCorner:
            "select"
        case .clockStyle:
            "select"
        case .clockSize:
            "select"
        case .clockDate:
            "switch"
        case .next:
            "button"
        case .previous:
            "button"
        case .currentPhoto:
            "sensor"
        case .currentPhotoImage:
            "image"
        case .phase:
            "sensor"
        case .photoCount:
            "sensor"
        case .version:
            "sensor"
        }
    }
}
