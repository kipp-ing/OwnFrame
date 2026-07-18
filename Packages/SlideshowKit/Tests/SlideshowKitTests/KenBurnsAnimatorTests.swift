import SlideshowKit
import Testing

// The animator is the pure state machine behind the scoped-animation Ken Burns
// modifier: it owns the drift anchor and answers every lifecycle event with a
// declarative step list — [unanimated snap, animated drift] — that the SwiftUI
// modifier executes verbatim (snap synchronously, drift one render commit later).
// Time comes in as plain seconds so every path is host-testable.

private let drift = KenBurnsDrift()
private let duration = 10.0

@Test func initialScaleMatchesTheFirstRenderedFrame() {
    let animator = KenBurnsAnimator(durationSeconds: duration)
    // Active show: the photo's first frame is the tight start frame. Inactive
    // (Ken Burns off / paused): the calm full-fill floor — never a 1.10 flash.
    #expect(animator.initialScale(isActive: true) == drift.startScale)
    #expect(animator.initialScale(isActive: false) == drift.floorScale)
}

@Test func activationEmitsUnanimatedResetThenFullLinearDrift() {
    var animator = KenBurnsAnimator(durationSeconds: duration)
    let steps = animator.activated(now: 100)
    #expect(steps.count == 2)
    #expect(steps[0] == KenBurnsAnimator.Step(scale: drift.startScale, linearDuration: nil))
    #expect(steps[1].scale == drift.floorScale)
    #expect(steps[1].linearDuration != nil)
    let expected = drift.floorDriftDuration(durationSeconds: duration)
    #expect(abs((steps[1].linearDuration ?? 0) - expected) < 0.0001)
}

@Test func appearingActiveBehavesLikeActivation() {
    var byAppear = KenBurnsAnimator(durationSeconds: duration)
    var byActivate = KenBurnsAnimator(durationSeconds: duration)
    #expect(byAppear.appeared(isActive: true, now: 100) == byActivate.activated(now: 100))
}

@Test func appearingInactiveEmitsOnlyTheFloorSnap() {
    var animator = KenBurnsAnimator(durationSeconds: duration)
    let steps = animator.appeared(isActive: false, now: 100)
    #expect(steps == [KenBurnsAnimator.Step(scale: drift.floorScale, linearDuration: nil)])
}

@Test func deactivationSnapsToTheFloorWithoutAnimation() {
    var animator = KenBurnsAnimator(durationSeconds: duration)
    _ = animator.activated(now: 100)
    let steps = animator.deactivated()
    // Today's pause semantics, preserved: a hard snap to the calm full-fill frame.
    #expect(steps == [KenBurnsAnimator.Step(scale: drift.floorScale, linearDuration: nil)])
}

@Test func reactivationRestartsTheArcFromStartScale() {
    var animator = KenBurnsAnimator(durationSeconds: duration)
    _ = animator.activated(now: 100)
    _ = animator.deactivated()
    let steps = animator.activated(now: 130)
    // Resume restarts the arc (today's semantics) with a fresh anchor.
    #expect(steps.first == KenBurnsAnimator.Step(scale: drift.startScale, linearDuration: nil))
    #expect(abs(animator.currentScale(now: 130) - drift.startScale) < 0.0001)
}

@Test func currentScaleMatchesDriftMathAnchoredAtActivation() {
    var animator = KenBurnsAnimator(durationSeconds: duration)
    _ = animator.activated(now: 100)
    for elapsed in [0.0, 1.0, 5.5, duration, duration + 5, duration + 600] {
        let expected = drift.scale(elapsedSeconds: elapsed, durationSeconds: duration)
        #expect(abs(animator.currentScale(now: 100 + elapsed) - expected) < 0.0001)
    }
}

@Test func durationChangeMidDriftFreezesThenDriftsTheRemainderAtTheNewRate() {
    var animator = KenBurnsAnimator(durationSeconds: duration)
    _ = animator.activated(now: 100)
    let atChange = animator.currentScale(now: 104)
    let steps = animator.durationChanged(to: 30, now: 104)
    #expect(steps.count == 2)
    // Freeze exactly where the drift stands, no jump…
    #expect(steps[0].linearDuration == nil)
    #expect(abs(steps[0].scale - atChange) < 0.0001)
    // …then run the remaining travel at the NEW rate.
    #expect(steps[1].scale == drift.floorScale)
    let remaining = (atChange - drift.floorScale) / drift.rate(durationSeconds: 30)
    #expect(abs((steps[1].linearDuration ?? 0) - remaining) < 0.0001)
    // The anchor is rebased: currentScale continues seamlessly at the new rate.
    #expect(abs(animator.currentScale(now: 104) - atChange) < 0.0001)
    let later = animator.currentScale(now: 106)
    #expect(abs(later - (atChange - 2 * drift.rate(durationSeconds: 30))) < 0.0001)
}

@Test func durationChangeWhileInactiveOnlyRetunes() {
    var animator = KenBurnsAnimator(durationSeconds: duration)
    let steps = animator.durationChanged(to: 30, now: 104)
    // Nothing to re-render — but the next activation must use the new rate.
    #expect(steps.isEmpty)
    let activation = animator.activated(now: 110)
    let expected = drift.floorDriftDuration(durationSeconds: 30)
    #expect(abs((activation[1].linearDuration ?? 0) - expected) < 0.0001)
}

@Test func degenerateEventsAreSafe() {
    var animator = KenBurnsAnimator(durationSeconds: duration)
    // Deactivating a never-activated animator: still the floor snap, no crash.
    #expect(animator.deactivated().count == 1)
    // currentScale before any activation reports the floor (the rendered state).
    #expect(animator.currentScale(now: 50) == drift.floorScale)
    // Clock weirdness: a `now` before the anchor pins to the start scale.
    _ = animator.activated(now: 100)
    #expect(animator.currentScale(now: 90) == drift.startScale)
}
