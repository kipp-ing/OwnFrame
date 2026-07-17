import Foundation
import HAControlKit

/// The process-stable handle the app registers once and every per-generation
/// adapter plugs into (data-model.md "FrameControlRegistry", research R2/R3/R8).
/// Bridges the `openAppWhenRun` cold-launch race via `awaitReady`.
@MainActor
public final class FrameControlRegistry {
    public typealias ControlSurface = any PlaybackControlling & PhotoReporting

    public enum RegistryState {
        case ready(ControlSurface)
        case notConfigured
        case notLive
    }

    /// Named per analysis finding A1 — referenced by tests, contract copy, and
    /// the manual drills, not just this default parameter.
    public static let coldLaunchGrace: Duration = .seconds(5)

    public var isConfigured: Bool = false
    public var sourceOptions: @MainActor () -> [SourceOption] = { [] }

    // Weak: a torn-down slideshow generation must never be kept alive by the
    // registry (the 900 no-leaked-timers discipline).
    private weak var surface: ControlSurface?
    private let sleep: @Sendable (Duration) async throws -> Void
    private var waiters: [Waiter] = []

    public init(sleep: @escaping @Sendable (Duration) async throws -> Void = { try await ContinuousClock().sleep(for: $0) }) {
        self.sleep = sleep
    }

    public var state: RegistryState {
        // Not configured beats not live even when both would otherwise apply.
        guard isConfigured else { return .notConfigured }
        guard let surface else { return .notLive }
        return .ready(surface)
    }

    public func register(_ surface: ControlSurface) {
        self.surface = surface
        let pending = waiters
        waiters.removeAll()
        for waiter in pending {
            waiter.resume()
        }
    }

    public func unregister() {
        surface = nil
    }

    public func awaitReady(
        timeout: Duration = FrameControlRegistry.coldLaunchGrace
    ) async throws(FrameCommandError) -> ControlSurface {
        guard isConfigured else { throw FrameCommandError.notConfigured }
        if let surface { return surface }

        // The continuation only ever carries a Void wake-up signal — never the
        // non-Sendable `ControlSurface` itself — because `CheckedContinuation`
        // treats its resume value as `sending`, and the same surface instance
        // gets handed to every pending waiter, which a single-owner transfer
        // can't express. Once woken (by `register` or the timeout), we simply
        // re-read `surface` synchronously, still on this actor.
        await withCheckedContinuation { (continuation: CheckedContinuation<Void, Never>) in
            let waiter = Waiter(continuation)
            waiters.append(waiter)
            let sleep = self.sleep
            Task { @MainActor [weak self] in
                try? await sleep(timeout)
                self?.timeoutWaiter(waiter)
            }
        }

        guard let surface else { throw FrameCommandError.frameNotOpen }
        return surface
    }

    private func timeoutWaiter(_ waiter: Waiter) {
        waiters.removeAll { $0 === waiter }
        waiter.resume()
    }

    /// Box around a single continuation so it can be resumed at most once by
    /// whichever of `register` / the injected timeout reaches it first.
    private final class Waiter {
        private var continuation: CheckedContinuation<Void, Never>?

        init(_ continuation: CheckedContinuation<Void, Never>) {
            self.continuation = continuation
        }

        func resume() {
            guard let continuation else { return }
            self.continuation = nil
            continuation.resume()
        }
    }
}
