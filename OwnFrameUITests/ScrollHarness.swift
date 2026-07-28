//
//  ScrollHarness.swift
//  OwnFrameUITests
//
//  Deterministic scrolling for the UI suite. Replaces the fixed-swipe-count helper that was
//  copy-pasted into six test files and broke wholesale on iOS 27 (issue #50).
//
//  Two things were wrong with the old shape, and both are fixed here:
//
//  1. A default `swipeUp()` is a hard inertial FLICK. How far the content coasts depends on the
//     system's scroll deceleration, which is not a stable contract across OS releases — iOS 27
//     moved it, and a fixed budget of eight flicks that landed mid-form on 26.5 sailed past the
//     target on 27.0. The failure-time frames show the form scrolled clean past the MQTT section
//     down to Storage, with `broker.host` recycled out of the accessibility tree. Here each step
//     is a LOW-VELOCITY swipe: short travel, little coasting, so overshoot is small and a step
//     that lands on the target is not carried past it.
//
//     It stays a swipe on purpose. `press(forDuration:thenDragTo:)` would be even more precise,
//     but it dwells on whatever sits under the start point, and a SwiftUI `Toggle` tracks that
//     touch — scrolling past the image-publish switch silently flipped it, which cost a real
//     test failure while this file was being written. A flick never dwells.
//
//  2. The loop checked the target only at the top of each iteration and counted swipes rather
//     than watching the content. It could neither stop when it arrived nor tell "not there yet"
//     from "scrolled past it". Here every step re-checks the target, and a step that fails to
//     change the screen means the end was reached — no magic number, and no silent truncation.
//
//  Prefer `scrollUntilHittable`: `exists` is not enough for anything you intend to tap, and
//  "present but not hittable" was the literal message in four of the six iOS 27 failures.
//

import XCTest

extension XCUIApplication {
    enum ScrollDirection {
        case up   // reveal content further down
        case down // reveal content further up
    }

    /// A cheap fingerprint of what is currently on screen. Identical fingerprints across a drag
    /// mean the content did not move, which is how we detect the end of a scroll view without
    /// asking for a content offset XCUITest does not expose.
    @MainActor
    private func scrollFingerprint() -> String {
        let texts = staticTexts
        let count = texts.count
        guard count > 0 else { return "empty" }
        let first = texts.element(boundBy: 0)
        let last = texts.element(boundBy: count - 1)
        // Round the origins: sub-pixel jitter during a settling animation is not movement.
        func stamp(_ e: XCUIElement) -> String {
            guard e.exists else { return "-" }
            return "\(e.label)@\(Int(e.frame.origin.y.rounded()))"
        }
        return "\(count)|\(stamp(first))|\(stamp(last))"
    }

    /// The element gestures are sent to: the scrollable container if there is one, else the app.
    ///
    /// This matters in landscape. `XCUIApplication`'s own frame can be reported in a rotated
    /// coordinate space, so `app.swipeUp()` travels along the wrong axis and the content simply
    /// does not move — on iOS 27 that left `onboarding.confirm.start` permanently unreachable in
    /// the landscape onboarding test even though the step scrolls fine under a finger. A child
    /// container's frame is orientation-correct, so the gesture goes the way it looks.
    @MainActor
    private var scrollSurface: XCUIElement {
        // SwiftUI `Form`/`List` render as a collection view; plain `ScrollView` as a scroll view.
        for candidate in [collectionViews.firstMatch, tables.firstMatch, scrollViews.firstMatch]
        where candidate.exists && candidate.isHittable {
            return candidate
        }
        return self
    }

    /// One short, low-momentum scroll step. Deliberately a flick and not a press-drag: a
    /// press-drag dwells on the control under its start point and can actuate it (see the file
    /// comment). `.slow` keeps the travel small so a step rarely carries the target past the
    /// viewport — which is the whole failure mode this file exists to remove.
    @MainActor
    private func dragStep(_ direction: ScrollDirection, velocity: XCUIGestureVelocity = .slow) {
        let surface = scrollSurface
        switch direction {
        case .up: surface.swipeUp(velocity: velocity)
        case .down: surface.swipeDown(velocity: velocity)
        }
    }

    /// Scrolls until `element` is hittable, the content stops moving, or `maxSteps` is spent.
    ///
    /// `maxSteps` is a runaway guard, not a scroll budget — it is deliberately far larger than
    /// any real form needs, because convergence (not the counter) is what normally ends the loop.
    @MainActor
    @discardableResult
    func scrollUntilHittable(
        _ element: XCUIElement,
        direction: ScrollDirection = .up,
        maxSteps: Int = 60
    ) -> Bool {
        scrollUntil(direction: direction, maxSteps: maxSteps) {
            element.exists && element.isHittable
        }
    }

    /// Like `scrollUntilHittable` but satisfied by mere existence. Use only when the element is
    /// never tapped — for anything you touch, hittability is the property that matters.
    @MainActor
    @discardableResult
    func scrollUntilExists(
        _ element: XCUIElement,
        direction: ScrollDirection = .up,
        maxSteps: Int = 60
    ) -> Bool {
        scrollUntil(direction: direction, maxSteps: maxSteps) { element.exists }
    }

    /// Scrolls until `condition` holds or the content stops moving.
    @MainActor
    @discardableResult
    func scrollUntil(
        direction: ScrollDirection = .up,
        maxSteps: Int = 60,
        condition: () -> Bool
    ) -> Bool {
        if condition() { return true }
        var fingerprint = scrollFingerprint()
        for _ in 0 ..< maxSteps {
            dragStep(direction)
            if condition() { return true }
            var updated = scrollFingerprint()
            if updated == fingerprint {
                // Nothing moved — but do not conclude "end of content" yet. A `.slow` flick can be
                // too short to shift anything in a shallow viewport (landscape on a phone was
                // exactly this: the settings form stopped one section above MQTT and the harness
                // called it the end), and an unchanged read also happens mid-animation, e.g. when
                // scrolling before a rotation has settled. Escalate once before believing it.
                dragStep(direction, velocity: .default)
                if condition() { return true }
                updated = scrollFingerprint()
                if updated == fingerprint { return condition() } // genuinely at the end
            }
            fingerprint = updated
        }
        return condition()
    }

    /// Drags from the current position to the end of the scrollable content, invoking `onStep`
    /// once before the first drag and once after every drag.
    ///
    /// This is the shape a "sweep the whole form" assertion wants: the old version swiped a fixed
    /// eight times and then asserted against the *final* screen, so on iOS 27 it scrolled past
    /// the section it was checking for and read the recycled-away element as absent. Observing at
    /// every step instead of only at the end makes the assertion independent of how far one drag
    /// happens to travel.
    @MainActor
    func sweepToEnd(
        direction: ScrollDirection = .up,
        maxSteps: Int = 60,
        onStep: (Int) -> Void
    ) {
        onStep(0)
        var fingerprint = scrollFingerprint()
        for step in 1 ... maxSteps {
            dragStep(direction)
            onStep(step)
            var updated = scrollFingerprint()
            if updated == fingerprint {
                dragStep(direction, velocity: .default) // escalate — see the note in scrollUntil
                onStep(step)
                updated = scrollFingerprint()
                if updated == fingerprint { return } // genuinely at the end
            }
            fingerprint = updated
        }
    }

    /// Taps the control end of a Form `Toggle`.
    ///
    /// Center-tapping a SwiftUI Form toggle can land on its (long) label instead of the switch,
    /// so the tap goes to the trailing edge. The part that used to break was never the offset —
    /// it was tapping a switch that had scrolled half out of the viewport, so scroll it fully
    /// into view first and fail loudly rather than tapping into empty space.
    @MainActor
    func tapSwitchControl(
        _ toggle: XCUIElement,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertTrue(
            scrollUntilHittable(toggle),
            "switch must be scrolled fully into view before tapping it",
            file: file,
            line: line
        )
        toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.5)).tap()
    }
}
