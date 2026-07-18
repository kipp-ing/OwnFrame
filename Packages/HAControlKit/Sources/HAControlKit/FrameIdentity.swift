/// Stable per-platform identity for a photo frame in Home Assistant (topic 1000, FR-1000-08).
///
/// The iPad frame and the Apple TV frame must register as DISTINCT HA devices so their MQTT
/// topics and discovery entities never collide when both run against the same broker. A
/// distinct `deviceID` per platform (e.g. "ABC" vs "ABC-appletv") is what guarantees that:
/// it seeds both `HATopics.base(deviceID:)` (the topic namespace) and the discovery
/// `unique_id` / device `identifiers`.
///
/// Dependency-light by design: it carries only the two strings the topic/discovery wiring
/// needs. The actual wiring lives in `HATopics` / `HADiscovery`, which take these values.
public struct FrameIdentity: Sendable, Equatable {
    /// Topic-namespace and discovery id seed. Distinct per platform => non-colliding topics.
    public let deviceID: String

    /// Human-facing device name in Home Assistant (e.g. "Photo Frame (Apple TV)").
    public let deviceName: String

    public init(deviceID: String, deviceName: String) {
        self.deviceID = deviceID
        self.deviceName = deviceName
    }
}
