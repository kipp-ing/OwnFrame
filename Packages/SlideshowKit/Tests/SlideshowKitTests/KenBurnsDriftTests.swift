import SlideshowKit
import Testing

// Ken Burns must read as ONE continuous motion: a constant zoom-out rate that never
// stalls, decelerates, or catches up — even when the photo swap lands late (device
// image-load latency makes the real period `duration + ε`, not `duration`). The old
// span-based progress clamped at scale 1.0 and visibly stopped before every late swap.
// These tests lock the rate-based contract: the drift passes *through* the expected
// settle scale at swap time and keeps moving at the same rate into the grace headroom,
// clamping only at the hard floor (scaledToFill coverage, never reveals an edge).

private let drift = KenBurnsDrift()
private let duration = 10.0
private var span: Double { duration + drift.swapOverlapSeconds }

@Test func driftStartsAtStartScale() {
    #expect(drift.scale(elapsedSeconds: 0, durationSeconds: duration) == drift.startScale)
}

@Test func driftReachesSettleScaleAtExpectedSwapTime() {
    let atSwap = drift.scale(elapsedSeconds: span, durationSeconds: duration)
    #expect(abs(atSwap - drift.settleScale) < 0.0001)
    // Still zoomed at the swap moment — settling to the floor would mean the
    // motion has to stop there.
    #expect(atSwap > drift.floorScale)
}

@Test func driftRateIsConstantAcrossTheSettleBoundary() {
    // Equal time steps produce equal scale deltas before, across, and after the
    // expected swap moment — no deceleration, no stall, no catch-up.
    let step = 1.0
    let samples = [span - 2, span - 1, span, span + 1, span + 2].map {
        drift.scale(elapsedSeconds: $0, durationSeconds: duration)
    }
    let deltas = zip(samples, samples.dropFirst()).map { $0 - $1 }
    for delta in deltas {
        #expect(abs(delta - drift.rate(durationSeconds: duration) * step) < 0.0001)
    }
}

@Test func lateSwapKeepsDriftingThroughGraceHeadroomToTheFloor() {
    let atSwap = drift.scale(elapsedSeconds: span, durationSeconds: duration)
    let late = drift.scale(elapsedSeconds: span + 2, durationSeconds: duration)
    #expect(late < atSwap)

    // Pathologically late: clamps exactly at the floor, never below (a scale below
    // 1.0 would pull the fill-framed photo's edges into the screen).
    let veryLate = drift.scale(elapsedSeconds: span + 600, durationSeconds: duration)
    #expect(veryLate == drift.floorScale)
}

@Test func rateScalesWithSlideDuration() {
    // Longer slides drift slower — each photo completes the same visual arc.
    #expect(drift.rate(durationSeconds: 30) < drift.rate(durationSeconds: 5))
    let expected = (drift.startScale - drift.settleScale) / span
    #expect(abs(drift.rate(durationSeconds: duration) - expected) < 0.0001)
}

@Test func degenerateInputsAreSafe() {
    // Clock weirdness (elapsed < 0) pins to the start; a zero/negative duration
    // must not divide by zero.
    #expect(drift.scale(elapsedSeconds: -5, durationSeconds: duration) == drift.startScale)
    let scale = drift.scale(elapsedSeconds: 1, durationSeconds: 0)
    #expect(scale <= drift.startScale)
    #expect(scale >= drift.floorScale)
    #expect(drift.rate(durationSeconds: 0).isFinite)
}

@Test func settleLeavesAtMostThreePercentCrop() {
    // The photo must end its slide close to the full (fill-framed) frame: the settle
    // margin exists only to keep the motion alive through the ~0.7s transition plus
    // typical prefetch latency — not a multi-second worst case. A big margin is a
    // permanent visible crop on every single photo.
    #expect(drift.settleScale - drift.floorScale <= 0.03 + 0.0001)
}

@Test func graceStillCoversTransitionAndTypicalLatency() {
    // Even when the swap lands 2s late, the outgoing photo must still be in motion
    // for the whole time it remains visible (late swap + 0.7s sequenced fade).
    let lateExit = drift.scale(elapsedSeconds: span + 2 + 0.7, durationSeconds: duration)
    #expect(lateExit > drift.floorScale)
}

@Test func panFractionTracksTheZoomLinearly() {
    // The pan offset rides the same linear clock as the zoom (constant speed), is
    // full at the start scale, and vanishes exactly at the floor so a clamped
    // photo sits centered.
    #expect(drift.panFraction(forScale: drift.startScale) == 1)
    #expect(drift.panFraction(forScale: drift.floorScale) == 0)
    let mid = (drift.startScale + drift.floorScale) / 2
    #expect(abs(drift.panFraction(forScale: mid) - 0.5) < 0.0001)
}

@Test func floorDriftDurationRunsStartToFloorAtTheConstantRate() {
    // The one-shot animation span: the whole start→floor travel at the same
    // constant rate the sampled curve uses. The sampled curve lands exactly on
    // the floor when this span ends — the clamp becomes "the animation completes".
    let total = drift.floorDriftDuration(durationSeconds: duration)
    let expected = (drift.startScale - drift.floorScale) / drift.rate(durationSeconds: duration)
    #expect(abs(total - expected) < 0.0001)
    #expect(abs(drift.scale(elapsedSeconds: total, durationSeconds: duration) - drift.floorScale) < 0.0001)
}

@Test func oneShotLinearAnimationPassesThroughSettleAtTheExpectedSwap() {
    // The theorem behind the scoped-animation redesign: ONE linear animation from
    // startScale to floorScale over floorDriftDuration is point-for-point the
    // sampled drift — evaluated at the expected swap moment it sits exactly at
    // settleScale (still zoomed, still moving), like the per-frame math.
    let total = drift.floorDriftDuration(durationSeconds: duration)
    #expect(total > span)
    let interpolated = drift.startScale + (drift.floorScale - drift.startScale) * (span / total)
    #expect(abs(interpolated - drift.settleScale) < 0.0001)
}
