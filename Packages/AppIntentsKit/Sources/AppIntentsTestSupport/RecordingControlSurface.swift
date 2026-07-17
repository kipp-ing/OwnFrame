import Foundation
import HAControlKit

/// Scriptable `PlaybackControlling & PhotoReporting` fake shared by the
/// AppIntentsKit suites and the app-hosted glue tests (spec 800, T005). Records
/// every call in order with its argument; state is plain settable vars — no
/// logic beyond recording (parity with the HAControlKit test fakes).
@MainActor
public final class RecordingControlSurface: PlaybackControlling, PhotoReporting {
    public enum Call: Equatable {
        case pause
        case resume
        case setBrightness(Double)
        case selectAlbum(String)
        case showNext
        case showPrevious
    }

    public private(set) var calls: [Call] = []

    public var playbackState: PlaybackState
    public var brightness: Double
    public var albumOptions: [String]
    public var currentAlbum: String?
    public var currentPhotoReport: PhotoReport
    public var version: String

    public var onLocalChange: (@MainActor () -> Void)?
    public var onPhotoChange: (@MainActor (PhotoReport) -> Void)?

    public init(
        playbackState: PlaybackState = .paused,
        brightness: Double = 0.5,
        albumOptions: [String] = [],
        currentAlbum: String? = nil,
        currentPhotoReport: PhotoReport = RecordingControlSurface.emptyReport,
        version: String = "1.0"
    ) {
        self.playbackState = playbackState
        self.brightness = brightness
        self.albumOptions = albumOptions
        self.currentAlbum = currentAlbum
        self.currentPhotoReport = currentPhotoReport
        self.version = version
    }

    public static let emptyReport = PhotoReport(
        assetID: nil,
        imageData: nil,
        takenAt: nil,
        city: nil,
        state: nil,
        country: nil,
        albumID: nil,
        albumName: nil,
        phase: .empty,
        photoCount: 0
    )

    public func pause() {
        calls.append(.pause)
    }

    public func resume() {
        calls.append(.resume)
    }

    public func setBrightness(_ value: Double) async {
        calls.append(.setBrightness(value))
    }

    public func selectAlbum(_ name: String) {
        calls.append(.selectAlbum(name))
    }

    public func showNext() async {
        calls.append(.showNext)
    }

    public func showPrevious() async {
        calls.append(.showPrevious)
    }
}
