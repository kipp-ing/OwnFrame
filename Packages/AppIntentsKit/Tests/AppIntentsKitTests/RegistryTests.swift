import Testing
import HAControlKit
import AppIntentsTestSupport
@testable import AppIntentsKit

/// T003: `FrameControlRegistry` state derivation, weak-reference teardown, and
/// the `awaitReady` cold-launch bridge (data-model.md transitions, research R8).
@MainActor
struct RegistryTests {

    // MARK: - State derivation

    @Test
    func freshRegistry_isNotConfigured() {
        let registry = FrameControlRegistry()
        guard case .notConfigured = registry.state else {
            Issue.record("expected .notConfigured, got \(registry.state)")
            return
        }
    }

    @Test
    func configuredWithNoSurface_isNotLive() {
        let registry = FrameControlRegistry()
        registry.isConfigured = true
        guard case .notLive = registry.state else {
            Issue.record("expected .notLive, got \(registry.state)")
            return
        }
    }

    @Test
    func configuredWithRegisteredSurface_isReady() {
        let registry = FrameControlRegistry()
        registry.isConfigured = true
        let surface = RecordingControlSurface()
        registry.register(surface)
        guard case .ready = registry.state else {
            Issue.record("expected .ready, got \(registry.state)")
            return
        }
    }

    @Test
    func notConfigured_winsOverALiveRegisteredSurface() {
        // A surface is registered (so "not live" would not apply) but the app
        // never flipped `isConfigured` — notConfigured must still win.
        let registry = FrameControlRegistry()
        registry.register(RecordingControlSurface())
        guard case .notConfigured = registry.state else {
            Issue.record("expected .notConfigured to beat a live surface, got \(registry.state)")
            return
        }
    }

    // MARK: - register / unregister

    @Test
    func register_replacesThePreviousSurface() {
        let registry = FrameControlRegistry()
        registry.isConfigured = true
        // Bound to `let`s (not passed as bare temporaries): the registry only
        // holds these weakly, so an unbound temporary would be deallocated the
        // instant `register` returns, before `state` could ever observe it.
        let first = RecordingControlSurface(currentAlbum: "First")
        let second = RecordingControlSurface(currentAlbum: "Second")
        registry.register(first)
        registry.register(second)

        guard case .ready(let surface) = registry.state else {
            Issue.record("expected .ready, got \(registry.state)")
            return
        }
        #expect(surface.currentAlbum == "Second")
    }

    @Test
    func unregister_makesStateNotLive() {
        let registry = FrameControlRegistry()
        registry.isConfigured = true
        registry.register(RecordingControlSurface())
        registry.unregister()

        guard case .notLive = registry.state else {
            Issue.record("expected .notLive after unregister, got \(registry.state)")
            return
        }
    }

    // MARK: - Weak reference

    @Test
    func droppedSurface_readsAsNotLive() {
        let registry = FrameControlRegistry()
        registry.isConfigured = true
        registerTemporarySurface(into: registry)

        guard case .notLive = registry.state else {
            Issue.record("expected a torn-down surface to read as .notLive, got \(registry.state)")
            return
        }
    }

    // MARK: - awaitReady

    @Test
    func awaitReady_unconfigured_throwsNotConfiguredImmediately() async {
        let registry = FrameControlRegistry(sleep: { _ in
            Issue.record("sleep must not be called when unconfigured")
        })

        do {
            _ = try await registry.awaitReady()
            Issue.record("expected .notConfigured to be thrown")
        } catch {
            #expect(error == .notConfigured)
        }
    }

    @Test
    func awaitReady_configuredAndRegistered_returnsImmediately() async throws {
        let registry = FrameControlRegistry(sleep: { _ in
            Issue.record("sleep must not be called when already ready")
        })
        registry.isConfigured = true
        let surface = RecordingControlSurface(currentAlbum: "Vacation")
        registry.register(surface)

        let resolved = try await registry.awaitReady()
        #expect(resolved.currentAlbum == "Vacation")
    }

    @Test
    func awaitReady_configuredEmpty_throwsFrameNotOpenAfterTimeout() async throws {
        // `Task { @MainActor in ... }` (not `async let`): the registry's
        // ControlSurface existential isn't Sendable, and an async-let child task
        // runs nonisolated, so it can't hand a raw surface back across. An
        // explicitly-MainActor `Task` inherits the actor and stays in-domain as
        // long as it only crosses back a Sendable projection (here `currentAlbum`).
        let gate = ManualGate()
        let registry = FrameControlRegistry(sleep: { _ in await gate.wait() })
        registry.isConfigured = true

        let task = Task { @MainActor in
            try await registry.awaitReady().currentAlbum
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

    @Test
    func awaitReady_registeredWhileWaiting_resumesWithTheSurface() async throws {
        let gate = ManualGate()
        let registry = FrameControlRegistry(sleep: { _ in await gate.wait() })
        registry.isConfigured = true

        let task = Task { @MainActor in
            try await registry.awaitReady().currentAlbum
        }
        await gate.waitUntilStarted()

        let surface = RecordingControlSurface(currentAlbum: "Late Arrival")
        registry.register(surface)

        let resolvedAlbum = try await task.value
        #expect(resolvedAlbum == "Late Arrival")

        // Let the now-orphaned internal timeout wait resolve so it doesn't leak
        // its continuation past the end of the test.
        await gate.fire()
    }

    @Test
    func awaitReady_multipleConcurrentWaiters_allResolveWithTheSurface() async throws {
        let gate = ManualGate()
        let registry = FrameControlRegistry(sleep: { _ in await gate.wait() })
        registry.isConfigured = true

        let first = Task { @MainActor in
            try await registry.awaitReady().currentAlbum
        }
        let second = Task { @MainActor in
            try await registry.awaitReady().currentAlbum
        }
        await gate.waitUntilStarted(count: 2)

        let surface = RecordingControlSurface(currentAlbum: "Shared")
        registry.register(surface)

        let firstResolved = try await first.value
        let secondResolved = try await second.value
        #expect(firstResolved == "Shared")
        #expect(secondResolved == "Shared")

        await gate.fire()
    }

    // MARK: - Named grace constant

    @Test
    func coldLaunchGrace_isFiveSeconds() {
        #expect(FrameControlRegistry.coldLaunchGrace == .seconds(5))
    }
}

/// Registers a surface that goes out of scope when this call returns, so the
/// registry's weak reference is the only thing that could keep it alive.
@MainActor
private func registerTemporarySurface(into registry: FrameControlRegistry) {
    let surface = RecordingControlSurface()
    registry.register(surface)
}

/// Deterministic stand-in for the registry's injected sleep seam. `wait()`
/// suspends until `fire()` is called (or returns immediately if `fire()`
/// already ran); `waitUntilStarted(count:)` lets a test block until that many
/// concurrent `wait()` calls have actually been entered, so register-mid-wait
/// races are driven explicitly rather than by hoping cooperative scheduling
/// lines up. Supports multiple concurrent waiters (test 9).
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
