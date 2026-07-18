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
}

public extension HAEntity {
    /// Entities enabled by default (contracts/ha-mqtt-entities.md §2: "all except
    /// current_photo_image", which is opt-in via `HAPublishOptions`, FR-710-07/15).
    static let defaultEnabled: Set<HAEntity> = Set(HAEntity.allCases).subtracting([.currentPhotoImage])
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
