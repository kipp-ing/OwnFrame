import Testing
import Foundation
import HAControlKit
import AppIntentsTestSupport
@testable import AppIntentsKit

/// T021: `FrameCommandService.frameState()` mapping onto `FrameStateSnapshot` —
/// the whitelist leak probe (a fully-populated fake carries only the six
/// approved fields), the structural `Mirror` guard (SC-800-04), brightness
/// rounding, and registry-error passthrough (data-model.md "FrameStateSnapshot",
/// research R6).
@MainActor
struct FrameStateSnapshotTests {

    // MARK: - Leak probe

    @Test
    func fullyPopulatedSurface_snapshotCarriesOnlyTheSixWhitelistedFields() async throws {
        // Every PhotoReport field is planted, including ones that must NOT
        // survive into the snapshot (assetID, imageData, albumID, albumName,
        // phase, photoCount, version) and `state` (region) specifically.
        let takenAt = Date(timeIntervalSince1970: 1_700_000_000)
        let report = PhotoReport(
            assetID: "SECRET-ASSET",
            imageData: Data([0x01, 0x02, 0x03]),
            takenAt: takenAt,
            city: "Berlin",
            state: "BE",
            country: "DE",
            albumID: "SECRET-ALBUM",
            albumName: "Berlin Trip",
            phase: .playing,
            photoCount: 42
        )
        let registry = FrameControlRegistry()
        registry.isConfigured = true
        let surface = RecordingControlSurface(
            playbackState: .playing,
            brightness: 0.4,
            currentAlbum: "Iceland",
            currentPhotoReport: report,
            version: "9.9.9"
        )
        registry.register(surface)
        let service = FrameCommandService(registry: registry)

        let snapshot = try await service.frameState()

        #expect(snapshot == FrameStateSnapshot(
            isPlaying: true,
            brightnessPercent: 40,
            sourceLabel: "Iceland",
            photoDate: takenAt,
            photoCity: "Berlin",
            photoCountry: "DE"
        ))
    }

    // MARK: - Structural whitelist (SC-800-04)

    @Test
    func snapshot_hasExactlyTheSixWhitelistedStoredProperties() {
        // A seventh stored property can never sneak in unnoticed: this asserts
        // on the type's actual runtime shape, not just its documented one.
        let snapshot = FrameStateSnapshot(
            isPlaying: true,
            brightnessPercent: 50,
            sourceLabel: "Iceland",
            photoDate: Date(),
            photoCity: "Berlin",
            photoCountry: "DE"
        )
        let children = Mirror(reflecting: snapshot).children
        #expect(children.count == 6)

        let labels = Set(children.compactMap(\.label))
        #expect(labels == [
            "isPlaying", "brightnessPercent", "sourceLabel",
            "photoDate", "photoCity", "photoCountry",
        ])
    }

    // MARK: - Brightness rounding

    @Test
    func brightness_zero_roundsToZeroPercent() async throws {
        // Bound to `let` (not discarded via `_`): the registry only holds the
        // surface weakly, and destructuring straight into `_` releases it
        // immediately — same lesson as RegistryTests' bare-temporary note.
        let (service, surface) = makeReadyService(brightness: 0.0)
        let snapshot = try await service.frameState()
        #expect(snapshot.brightnessPercent == 0)
        #expect(surface.calls.isEmpty)
    }

    @Test
    func brightness_one_roundsToOneHundredPercent() async throws {
        let (service, surface) = makeReadyService(brightness: 1.0)
        let snapshot = try await service.frameState()
        #expect(snapshot.brightnessPercent == 100)
        #expect(surface.calls.isEmpty)
    }

    @Test
    func brightness_pointZeroZeroFive_roundsUpToOnePercent() async throws {
        // Rounded, not truncated: 0.5 (after *100) rounds away from zero to 1.
        let (service, surface) = makeReadyService(brightness: 0.005)
        let snapshot = try await service.frameState()
        #expect(snapshot.brightnessPercent == 1)
        #expect(surface.calls.isEmpty)
    }

    // MARK: - isPlaying

    @Test
    func pausedSurface_isPlayingIsFalse() async throws {
        let (service, surface) = makeReadyService(playbackState: .paused)
        let snapshot = try await service.frameState()
        #expect(snapshot.isPlaying == false)
        #expect(surface.calls.isEmpty)
    }

    // MARK: - Registry errors propagate unchanged (never guessed)

    @Test
    func unconfiguredRegistry_throwsNotConfigured() async {
        let registry = FrameControlRegistry()
        let service = FrameCommandService(registry: registry)

        await expectFrameStateError(.notConfigured) { _ = try await service.frameState() }
    }

    @Test
    func configuredEmpty_throwsFrameNotOpenAfterTimeout() async throws {
        let gate = ManualGate()
        let registry = FrameControlRegistry(sleep: { _ in await gate.wait() })
        registry.isConfigured = true
        let service = FrameCommandService(registry: registry)

        let task = Task { @MainActor in
            try await service.frameState()
        }
        await gate.waitUntilStarted()
        await gate.fire()

        do {
            _ = try await task.value
            Issue.record("expected .frameNotOpen after the injected timeout fired")
        } catch let error as FrameCommandError {
            #expect(error == .frameNotOpen)
        }
    }
}

/// A registry configured + registered with a scripted `RecordingControlSurface`,
/// wrapped in a `FrameCommandService`.
@MainActor
private func makeReadyService(
    playbackState: PlaybackState = .playing,
    brightness: Double = 0.5
) -> (service: FrameCommandService, surface: RecordingControlSurface) {
    let registry = FrameControlRegistry()
    registry.isConfigured = true
    let surface = RecordingControlSurface(playbackState: playbackState, brightness: brightness)
    registry.register(surface)
    return (FrameCommandService(registry: registry), surface)
}

/// Awaits a `frameState()` call expected to fail with the given error.
@MainActor
private func expectFrameStateError(
    _ expected: FrameCommandError,
    sourceLocation: SourceLocation = #_sourceLocation,
    _ operation: () async throws -> Void
) async {
    do {
        try await operation()
        Issue.record("expected \(expected) to be thrown", sourceLocation: sourceLocation)
    } catch let error as FrameCommandError {
        #expect(error == expected, sourceLocation: sourceLocation)
    } catch {
        Issue.record("expected FrameCommandError, got \(error)", sourceLocation: sourceLocation)
    }
}

/// Deterministic stand-in for the registry's injected sleep seam (copied from
/// RegistryTests/FrameCommandServiceTests — top-level `private` is file-scoped
/// in Swift, so this is a distinct type, not a redeclaration).
private actor ManualGate {
    private var fired = false
    private var startedCount = 0
    private var fireContinuations: [CheckedContinuation<Void, Never>] = []
    private var startWaiters: [(threshold: Int, continuation: CheckedContinuation<Void, Never>)] = []

    func wait() async {
        startedCount += 1
        let reached = startWaiters.filter { startedCount >= $0.threshold }
        startWaiters.removeAll { startedCount >= $0.threshold }
        for waiter in reached {
            waiter.continuation.resume()
        }

        if fired { return }
        await withCheckedContinuation { continuation in
            fireContinuations.append(continuation)
        }
    }

    func waitUntilStarted(count: Int = 1) async {
        if startedCount >= count { return }
        await withCheckedContinuation { continuation in
            startWaiters.append((threshold: count, continuation: continuation))
        }
    }

    func fire() {
        fired = true
        let pending = fireContinuations
        fireContinuations.removeAll()
        for continuation in pending {
            continuation.resume()
        }
    }
}
