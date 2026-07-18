import Foundation
@testable import HAControlKit

final class FakeMQTTTransport: MQTTTransport, @unchecked Sendable {
    // Not `private(set)`: photo-publish tests clear this between announce() and the
    // fired report to isolate the change from discovery/echo noise.
    var published: [MQTTMessage] = []
    private(set) var subscriptions: [String] = []
    private(set) var will: MQTTMessage?
    private(set) var connectCount = 0
    private(set) var disconnectCount = 0
    var connectShouldThrow = false

    private var incomingContinuation: AsyncStream<MQTTMessage>.Continuation?
    private var connectionContinuation: AsyncStream<Bool>.Continuation?

    lazy var incoming: AsyncStream<MQTTMessage> = AsyncStream { continuation in
        self.incomingContinuation = continuation
    }

    lazy var connectionEvents: AsyncStream<Bool> = AsyncStream { continuation in
        self.connectionContinuation = continuation
    }

    func connect(will: MQTTMessage) async throws {
        connectCount += 1
        if connectShouldThrow {
            throw FakeError.connectFailed
        }
        self.will = will
    }

    func disconnect() async {
        disconnectCount += 1
    }

    func publish(_ message: MQTTMessage) async throws {
        published.append(message)
    }

    func subscribe(_ topicFilter: String) async throws {
        subscriptions.append(topicFilter)
    }

    func inject(_ message: MQTTMessage) {
        incomingContinuation?.yield(message)
    }

    func emitConnection(_ up: Bool) {
        connectionContinuation?.yield(up)
    }

    enum FakeError: Error {
        case connectFailed
    }
}

@MainActor
final class FakeRemoteControl: PlaybackControlling {
    var playbackState: PlaybackState = .playing
    var brightness: Double = 0.5
    var albumOptions: [String] = []
    var currentAlbum: String?
    private(set) var pauseCount = 0
    private(set) var resumeCount = 0
    var onLocalChange: (@MainActor () -> Void)?

    func pause() {
        playbackState = .paused
        pauseCount += 1
    }

    func resume() {
        playbackState = .playing
        resumeCount += 1
    }

    func setBrightness(_ value: Double) async {
        brightness = min(max(value, 0), 1)
    }

    func selectAlbum(_ name: String) {
        if albumOptions.contains(name) {
            currentAlbum = name
        }
    }
}

struct FakeBrokerConfigStore: BrokerConfigStore {
    var config: BrokerConfig?

    func load() -> BrokerConfig? {
        config
    }
}

@MainActor
final class FakeSettingsControl: SettingsControlling {
    var themeSettings: ThemeSettingsSnapshot = ThemeSettingsSnapshot(
        order: .shuffle,
        durationSeconds: 15,
        transition: .crossfade,
        kenBurns: false,
        fit: .fit,
        quality: .preview,
        clockOn: false,
        clockPlace: .bottomTrailing,
        clockStyle: .digits,
        clockSize: .room,
        clockDate: false
    )
    private(set) var applyCount = 0
    var onSettingsChange: (@MainActor () -> Void)?

    func apply(_ settings: ThemeSettingsSnapshot) {
        themeSettings = settings
        applyCount += 1
    }
}

@MainActor
final class FakePhotoReporting: PhotoReporting {
    var currentPhotoReport: PhotoReport
    var version: String = "1.2.3-test"
    var onPhotoChange: (@MainActor (PhotoReport) -> Void)?
    private(set) var showNextCount = 0
    private(set) var showPreviousCount = 0

    init(report: PhotoReport = PhotoReport(
        assetID: nil, imageData: nil, takenAt: nil, city: nil, state: nil,
        country: nil, albumID: nil, albumName: nil, phase: .loading, photoCount: 0
    )) {
        self.currentPhotoReport = report
    }

    func showNext() async { showNextCount += 1 }
    func showPrevious() async { showPreviousCount += 1 }

    /// Test lever: fire the coordinator's hook exactly as the real adapter would.
    func emit(_ report: PhotoReport) {
        currentPhotoReport = report
        onPhotoChange?(report)
    }
}
