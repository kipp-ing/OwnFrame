import Foundation

/// The teardown-decision seam for the slideshow surface (FR-700-23, added 2026-07-26).
///
/// `onDisappear` fires both for genuine exits AND for in-app modal covers — observed on
/// the live iOS 17 frame (presenting Settings/albums/sources/the connection editor fires
/// the presenting view's `onDisappear`), and structural on tvOS, where the settings
/// `fullScreenCover` removes the covered view. Tearing the HA coordinator down on every
/// disappearance is what made Home Assistant show the frame offline whenever any modal
/// was up, and re-armed the idle timer while the slideshow was still active underneath
/// (the FR-400-01 half of the same defect).
///
/// The decision is therefore made by *why* the event happened — the presenting layer's
/// modal state — never by the lifecycle callback itself:
/// - a modal cover keeps the broker session and the keep-awake hold; the covered surface
///   is reported through the `frame_status` sensor instead (FR-710-24), fed by its own
///   explicit signal (`HAControlCoordinator.setSurfaceVisible(_:)`), not by lifecycle;
/// - a genuine exit tears down as before;
/// - leaving the foreground always tears down, modal or not (FR-400-03; FR-700-23 counts
///   backgrounding as a real loss of app-level connectivity).
public enum SlideshowSurfaceLifecycle {
    /// The lifecycle events whose meaning is ambiguous without the modal context.
    public enum Event: Sendable, Equatable {
        /// The slideshow view's `onDisappear` fired.
        case viewDisappeared
        /// The scene left `.active` (backgrounded or inactive).
        case leftForeground
    }

    public enum Decision: Sendable, Equatable {
        /// A modal covers the still-live surface: keep the broker session (availability
        /// stays online — FR-700-23/SC-700-15) and keep the idle timer disabled
        /// (FR-400-01). Only the `frame_status` signal changes.
        case keepAlive
        /// A genuine exit or a foreground loss: stop the coordinator (graceful retained
        /// offline) and re-arm the idle timer, exactly as before the amendment.
        case tearDown
    }

    public static func decision(for event: Event, isModalPresented: Bool) -> Decision {
        switch event {
        case .viewDisappeared:
            isModalPresented ? .keepAlive : .tearDown
        case .leftForeground:
            .tearDown
        }
    }
}

/// Identity-scoped owner of the per-run `HAControlCoordinator` (iOS; tvOS owns its
/// coordinator on `TVAppModel`, which sequences teardown explicitly).
///
/// Held in `@State`, its lifetime is the *view identity's* lifetime — not the view
/// value's, and not tied to appear/disappear. That is what makes the `keepAlive`
/// decision above safe: `onDisappear` may skip teardown while a modal merely covers the
/// slideshow, and if the surface is instead *destroyed* with a sheet still up (reset from
/// Settings, a source switch from the sources sheet — both bump the host's
/// `.id(connectionGeneration)` or clear the slideshow), the lease deinits with the
/// identity and stops the coordinator anyway. Without that backstop a leaked coordinator
/// would keep its transport connected and auto-reconnecting while the successor
/// generation connects a second transport under the SAME MQTT client id (the frame's
/// device ID) — the two sessions would take each other over in a loop, firing the LWT's
/// retained "offline" on every takeover.
@MainActor
public final class HACoordinatorLease {
    // `nonisolated(unsafe)`: the nonisolated deinit must reach the reference to schedule
    // the MainActor stop. Every write happens on the MainActor, and deinit only runs once
    // no other reference remains, so the access cannot race.
    nonisolated(unsafe) private var stored: HAControlCoordinator?

    public init() {}

    /// The currently owned coordinator, `nil` when none is running.
    public var coordinator: HAControlCoordinator? { stored }

    /// Take ownership of a freshly built coordinator. Adopting over a live one schedules
    /// a stop of the previous coordinator first (the two may overlap briefly while that
    /// async stop drains — what the lease guarantees is that no coordinator is ever
    /// dropped without one).
    public func adopt(_ coordinator: HAControlCoordinator) {
        if let previous = stored {
            Task { await previous.stop() }
        }
        stored = coordinator
    }

    /// Graceful teardown: publish retained offline, disconnect, release.
    public func stop() async {
        guard let coordinator = stored else { return }
        stored = nil
        await coordinator.stop()
    }

    deinit {
        // The owning identity is gone (source switch, reset). Schedule the stop on the
        // main actor — deinit itself is nonisolated, so the reference crosses inside an
        // unchecked-Sendable box; it is only ever *used* back on the MainActor, where the
        // coordinator lives.
        guard let coordinator = stored else { return }
        stored = nil
        let box = UncheckedSendableBox(coordinator)
        Task { @MainActor in
            await box.value.stop()
        }
    }
}

/// Carries a MainActor-bound reference across the nonisolated deinit hop above.
private struct UncheckedSendableBox<Value>: @unchecked Sendable {
    let value: Value
    init(_ value: Value) { self.value = value }
}
