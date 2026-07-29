import Foundation

public enum HAEntity: String, CaseIterable, Sendable {
    case playback
    case brightness
    case album
    case order
    case duration
    case transition
    case kenBurns = "ken_burns"
    case fit
    case quality
    case clock
    case clockCorner = "clock_corner"
    case clockStyle = "clock_style"
    case clockSize = "clock_size"
    case clockDate = "clock_date"
    case next
    case previous
    case currentPhoto = "current_photo"
    case currentPhotoImage = "current_photo_image"
    case phase
    case photoCount = "photo_count"
    case version
    case battery
    case charging
    /// FR-710-24 (2026-07-26): `running` when the slideshow surface is frontmost,
    /// `inactive` when an in-app modal covers it. Driven by an explicit UI-visibility
    /// signal from the presenting layer — never inferred from view lifecycle, and never
    /// a third value on the (binary) availability topic (FR-700-23).
    case frameStatus = "frame_status"
}

public extension HAEntity {
    /// Entities enabled by default (contracts/ha-mqtt-entities.md §2: "all except
    /// current_photo_image", which is opt-in via `HAPublishOptions`, FR-710-07/15).
    static let defaultEnabled: Set<HAEntity> = Set(HAEntity.allCases).subtracting([.currentPhotoImage])

    /// Read-only status entities (HA sensors / diagnostics / image) — no command topic.
    /// These are the **free** telemetry surface: an unentitled frame publishes them so Home
    /// Assistant can *see* it (spec 1100 FR-1100-03a). Their discovery sets `command_topic`
    /// to `nil` (see `HADiscovery`); nothing here is ever driven from HA.
    var isReadOnlySensor: Bool {
        switch self {
        case .currentPhoto, .currentPhotoImage, .phase, .photoCount, .version, .battery, .charging,
             .frameStatus:
            true
        case .playback, .brightness, .album, .order, .duration, .transition, .kenBurns,
             .fit, .quality, .clock, .clockCorner, .clockStyle, .clockSize, .clockDate,
             .next, .previous:
            false
        }
    }

    /// Controllable entities carry a `command_topic`; Home Assistant can drive them. These
    /// (plus command handling and App Intents) require the **Automation** unlock — they are
    /// only published/subscribed in `.full` mode (spec 1100 FR-1100-03).
    var isControllable: Bool { !isReadOnlySensor }

    /// The two device-conditional diagnostics: published only on a battery-bearing device
    /// with a `BatteryReporting` source, omitted entirely otherwise (FR-710-23).
    var isBatteryEntity: Bool {
        self == .battery || self == .charging
    }
}

public enum PlaybackState: Sendable, Equatable {
    case playing
    case paused
}

public enum ConnectionState: Sendable, Equatable {
    case disconnected
    case connecting
    case connected
}
