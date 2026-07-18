import SwiftUI

// The Ken Burns drift as ONE long-running scoped animation per photo, shared by
// the iPad and Apple TV slideshows (pan differs per platform).
//
// Why not per-frame TimelineView sampling (the previous design): every display
// tick re-ran body/diff/layout on the main thread to move sub-pixel amounts
// (~0.8 px/s pan at 15s slides), so any late tick or main-thread hitch became a
// visible spatial error — micro judder — and `context.date` sampled at closure
// run time turned tick-vs-refresh phase drift into mistimed motion. A declared
// linear animation interpolates against the display's frame timestamps and costs
// nothing per frame.
//
// Why not `withAnimation` (the 9a1e252 regression this replaced TimelineView
// for): a global transaction started while a photo swap is in flight cancels the
// swap's transition animations. `.animation(_:body:)` is scoped — it applies
// ONLY to the two modifiers in its closure and creates no global transaction, so
// the sequenced fades and the drift cannot capture each other. Verified on the
// iPad simulator (2026-07-18): sequenced fades stay intact, the blend is gradual
// with no black dip, and the drift runs linearly through every swap.
//
// Execution contract for `KenBurnsAnimator`'s steps (simulator-verified, the
// subtle part): a state mutation inside `onAppear` — or an immediately-enqueued
// main-actor task — merges into the PENDING render commit, so the from-value is
// never committed and the "animation" collapses into a still frame. Snap steps
// therefore apply synchronously, and the animated step is deferred one render
// commit via `DispatchQueue.main.async` (next runloop iteration, past the
// CATransaction commit observer), token-guarded against a newer event landing
// in between.
public struct KenBurnsMotionModifier: ViewModifier {
    /// On only when Ken Burns is enabled and the show is actively playing.
    let isActive: Bool
    /// Per-photo duration; sets the drift rate so every photo completes the same arc.
    let durationSeconds: Double
    /// Maximum diagonal pan offset in points (platform-tuned by the caller).
    let pan: CGFloat

    @State private var animator: KenBurnsAnimator
    @State private var step: KenBurnsAnimator.Step
    /// Invalidates a deferred drift step when a newer event supersedes it.
    @State private var stepToken = 0

    public init(isActive: Bool, durationSeconds: Double, pan: CGFloat) {
        self.isActive = isActive
        self.durationSeconds = durationSeconds
        self.pan = pan
        let animator = KenBurnsAnimator(durationSeconds: durationSeconds)
        _animator = State(initialValue: animator)
        // The first rendered frame must already be correct: the tight start frame
        // for an active show, the calm floor when Ken Burns is off/paused (an
        // onAppear-only fix would flash the start scale for one frame).
        _step = State(initialValue: KenBurnsAnimator.Step(
            scale: animator.initialScale(isActive: isActive),
            linearDuration: nil
        ))
    }

    public func body(content: Content) -> some View {
        // The pan offset targets ride the target scale; `panFraction` is linear
        // in scale, so the linearly interpolated offset matches the old
        // per-frame values at every instant.
        let fraction = CGFloat(animator.drift.panFraction(forScale: step.scale))
        content
            .animation(step.linearDuration.map { .linear(duration: $0) }) { view in
                view
                    .scaleEffect(CGFloat(step.scale))
                    .offset(x: pan * fraction, y: -pan * fraction)
            }
            .onAppear {
                apply(animator.appeared(isActive: isActive, now: now()))
            }
            .onChange(of: isActive) { _, active in
                apply(active ? animator.activated(now: now()) : animator.deactivated())
            }
            .onChange(of: durationSeconds) { _, newDuration in
                apply(animator.durationChanged(to: newDuration, now: now()))
            }
    }

    private func apply(_ steps: [KenBurnsAnimator.Step]) {
        stepToken += 1
        guard let first = steps.first else { return }
        step = first
        guard steps.count > 1 else { return }
        let token = stepToken
        DispatchQueue.main.async {
            guard token == stepToken else { return }
            step = steps[1]
        }
    }

    private func now() -> Double {
        Date().timeIntervalSinceReferenceDate
    }
}

public extension View {
    /// Ken Burns slow zoom-out with proportional diagonal pan. Give each photo a
    /// fresh view identity (`.id`) so the motion restarts per photo; `pan` is the
    /// platform's maximum offset in points.
    func kenBurnsMotion(isActive: Bool, durationSeconds: Double, pan: CGFloat) -> some View {
        modifier(KenBurnsMotionModifier(
            isActive: isActive,
            durationSeconds: durationSeconds,
            pan: pan
        ))
    }
}
