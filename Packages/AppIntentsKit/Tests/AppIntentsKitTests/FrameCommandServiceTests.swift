import Testing
import HAControlKit
import AppIntentsTestSupport
@testable import AppIntentsKit

/// T010: `FrameCommandService` HA-parity call sequences for pause/resume/next/
/// previous, plus registry-error passthrough (data-model.md
/// "FrameCommandService", research R2).
@MainActor
struct FrameCommandServiceTests {

    // MARK: - HA-parity call sequences

    // @covers FR-800-02
    @Test
    func pause_matchesHAPauseSwitchPath() async throws {
        // Identical to the HA pause switch path: HAControlCoordinator command →
        // PlaybackControlling.pause().
        let registry = FrameControlRegistry()
        registry.isConfigured = true
        let surface = RecordingControlSurface()
        registry.register(surface)
        let service = FrameCommandService(registry: registry)

        try await service.pause()
        #expect(surface.calls == [.pause])
    }

    // @covers FR-800-02
    @Test
    func resume_recordsResume() async throws {
        let registry = FrameControlRegistry()
        registry.isConfigured = true
        let surface = RecordingControlSurface()
        registry.register(surface)
        let service = FrameCommandService(registry: registry)

        try await service.resume()
        #expect(surface.calls == [.resume])
    }

    // @covers FR-800-02
    @Test
    func nextPhoto_stepsWithoutResumingWhenPaused() async throws {
        // HA next-button parity (topic 710 US3): with a scripted paused
        // playbackState the call list is exactly [.showNext] — stepping never
        // issues a .resume call.
        let registry = FrameControlRegistry()
        registry.isConfigured = true
        let surface = RecordingControlSurface(playbackState: .paused)
        registry.register(surface)
        let service = FrameCommandService(registry: registry)

        try await service.nextPhoto()
        #expect(surface.calls == [.showNext])
    }

    // @covers FR-800-02
    @Test
    func previousPhoto_recordsShowPrevious() async throws {
        let registry = FrameControlRegistry()
        registry.isConfigured = true
        let surface = RecordingControlSurface()
        registry.register(surface)
        let service = FrameCommandService(registry: registry)

        try await service.previousPhoto()
        #expect(surface.calls == [.showPrevious])
    }

    // MARK: - Registry errors surface unchanged

    @Test
    func everyVerb_notConfigured_throwsNotConfiguredWithNoCallsRecorded() async {
        // A surface is registered (so "not live" would not otherwise apply) but
        // isConfigured stays false — notConfigured must still win (RegistryTests
        // parity: `notConfigured_winsOverALiveRegisteredSurface`).
        let registry = FrameControlRegistry()
        let surface = RecordingControlSurface()
        registry.register(surface)
        let service = FrameCommandService(registry: registry)

        await expectNotConfigured { try await service.pause() }
        await expectNotConfigured { try await service.resume() }
        await expectNotConfigured { try await service.nextPhoto() }
        await expectNotConfigured { try await service.previousPhoto() }

        #expect(surface.calls.isEmpty)
    }

    // MARK: - awaitReady bridging (cold-launch race)

    @Test
    func pause_configuredButNothingRegistered_throwsFrameNotOpenAfterTimeout() async throws {
        let gate = ManualGate()
        let registry = FrameControlRegistry(sleep: { _ in await gate.wait() })
        registry.isConfigured = true
        let service = FrameCommandService(registry: registry)

        let task = Task { @MainActor in
            try await service.pause()
        }
        await gate.waitUntilStarted()
        await gate.fire()

        do {
            try await task.value
            Issue.record("expected .frameNotOpen after the injected timeout fired")
        } catch let error as FrameCommandError {
            #expect(error == .frameNotOpen)
        }
    }

    @Test
    func pause_registeredWhileWaiting_resolvesAndRecordsPause() async throws {
        let gate = ManualGate()
        let registry = FrameControlRegistry(sleep: { _ in await gate.wait() })
        registry.isConfigured = true
        let service = FrameCommandService(registry: registry)

        let task = Task { @MainActor in
            try await service.pause()
        }
        await gate.waitUntilStarted()

        let surface = RecordingControlSurface()
        registry.register(surface)

        try await task.value
        #expect(surface.calls == [.pause])

        // Let the now-orphaned internal timeout wait resolve so it doesn't leak
        // its continuation past the end of the test.
        await gate.fire()
    }
}

/// Awaits an operation expected to fail with `.notConfigured`.
@MainActor
private func expectNotConfigured(
    _ operation: () async throws -> Void,
    sourceLocation: SourceLocation = #_sourceLocation
) async {
    do {
        try await operation()
        Issue.record("expected .notConfigured to be thrown", sourceLocation: sourceLocation)
    } catch let error as FrameCommandError {
        #expect(error == .notConfigured, sourceLocation: sourceLocation)
    } catch {
        Issue.record("expected FrameCommandError, got \(error)", sourceLocation: sourceLocation)
    }
}

/// Deterministic stand-in for the registry's injected sleep seam (copied from
/// RegistryTests — top-level `private` is file-scoped in Swift, so this is a
/// distinct type from that file's copy, not a redeclaration). `wait()` suspends
/// until `fire()` is called; `waitUntilStarted()` lets a test block until that
/// `wait()` call has actually been entered, so register-mid-wait races are
/// driven explicitly rather than by hoping cooperative scheduling lines up.
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
