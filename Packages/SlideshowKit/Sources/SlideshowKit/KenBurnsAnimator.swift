import Foundation

/// Pure state machine behind the scoped-animation Ken Burns modifier: it owns the
/// drift anchor and answers every lifecycle event with a declarative step list the
/// SwiftUI modifier executes verbatim. Host-testable like `KenBurnsDrift` — time
/// comes in as plain seconds, no clocks, no SwiftUI.
///
/// Step semantics (the modifier's execution contract, verified on the simulator):
/// a `linearDuration == nil` step is an unanimated snap applied synchronously; an
/// animated step must be applied ONE RENDER COMMIT LATER (`DispatchQueue.main.async`)
/// — a state mutation inside `onAppear` (or an immediately-run main-actor task)
/// merges into the pending commit, so the from-value is never committed and the
/// animation collapses into a still frame.
public struct KenBurnsAnimator: Equatable, Sendable {
    /// One rendered target: snap to it (`linearDuration == nil`) or drift to it
    /// with a linear animation of the given span.
    public struct Step: Equatable, Sendable {
        public let scale: Double
        public let linearDuration: Double?

        public init(scale: Double, linearDuration: Double?) {
            self.scale = scale
            self.linearDuration = linearDuration
        }
    }

    public let drift: KenBurnsDrift
    /// Anchor of the current arc in the caller's clock; nil while inactive.
    private var driftStart: Double?
    private var durationSeconds: Double

    public init(drift: KenBurnsDrift = KenBurnsDrift(), durationSeconds: Double) {
        self.drift = drift
        self.durationSeconds = durationSeconds
    }

    /// The pre-`onAppear` rendered scale: the tight start frame for an active
    /// show, the calm full-fill floor otherwise (never a start-scale flash while
    /// Ken Burns is off or paused).
    public func initialScale(isActive: Bool) -> Double {
        isActive ? drift.startScale : drift.floorScale
    }

    public mutating func appeared(isActive: Bool, now: Double) -> [Step] {
        isActive ? activated(now: now) : deactivated()
    }

    /// Start (or restart) the arc: snap to the start frame, then one linear
    /// animation over the whole start→floor span. Constant rate makes it pass
    /// `settleScale` exactly at the expected swap moment and keep moving through
    /// late-swap grace headroom; a pathologically late swap parks at the floor
    /// (the animation completes and holds).
    public mutating func activated(now: Double) -> [Step] {
        driftStart = now
        return [
            Step(scale: drift.startScale, linearDuration: nil),
            Step(scale: drift.floorScale,
                 linearDuration: drift.floorDriftDuration(durationSeconds: durationSeconds)),
        ]
    }

    /// Pause / Ken Burns off: today's semantics preserved — a hard snap to the
    /// calm full-fill frame; resume restarts the arc.
    public mutating func deactivated() -> [Step] {
        driftStart = nil
        return [Step(scale: drift.floorScale, linearDuration: nil)]
    }

    /// A live per-photo duration change retunes the rate immediately (008 review
    /// R4): freeze exactly where the drift stands, then run the remaining travel
    /// at the new rate. The anchor is rebased so `currentScale` stays continuous.
    public mutating func durationChanged(to newDuration: Double, now: Double) -> [Step] {
        guard driftStart != nil else {
            durationSeconds = newDuration
            return []
        }
        let frozen = currentScale(now: now)
        durationSeconds = newDuration
        // Rebase the anchor so the same math yields `frozen` at `now` under the
        // new rate — elapsed = (start - frozen) / newRate.
        let newRate = drift.rate(durationSeconds: newDuration)
        driftStart = now - (drift.startScale - frozen) / newRate
        return [
            Step(scale: frozen, linearDuration: nil),
            Step(scale: drift.floorScale,
                 linearDuration: (frozen - drift.floorScale) / newRate),
        ]
    }

    /// Where the drift stands at `now` — the same value the in-flight animation
    /// presents, computed from the anchor. The floor while inactive.
    public func currentScale(now: Double) -> Double {
        guard let driftStart else { return drift.floorScale }
        return drift.scale(elapsedSeconds: now - driftStart, durationSeconds: durationSeconds)
    }
}
