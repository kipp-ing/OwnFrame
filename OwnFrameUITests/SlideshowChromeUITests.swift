//
//  SlideshowChromeUITests.swift
//  OwnFrameUITests
//
//  Slice A — drives the reveal-on-tap Liquid Glass chrome against the hermetic
//  `--uitest --uitest-slideshow` build (stub API + in-memory stores, straight
//  into the running slideshow). Verifies the calm default (chrome hidden), tap to
//  reveal, the transport controls, the play/pause toggle, and idle auto-hide.
//

import XCTest

final class SlideshowChromeUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
        // Never inherit a rotation leaked by an earlier test on the same simulator
        // clone — a launch during a stale landscape state positions the chrome
        // off-screen. Tests that need landscape rotate themselves (and restore).
        MainActor.assumeIsolated { XCUIDevice.shared.orientation = .portrait }
    }

    @MainActor
    private func launchIntoSlideshow(extraArgs: [String] = []) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--uitest", "--uitest-slideshow"] + extraArgs
        app.launch()

        let image = app.descendants(matching: .any)
            .matching(identifier: "slideshow.image").firstMatch
        XCTAssertTrue(image.waitForExistence(timeout: 5), "slideshow should be running")
        return app
    }

    @MainActor
    func testChromeHiddenByDefaultAndRevealsOnTap() throws {
        let app = launchIntoSlideshow()
        let settings = app.buttons["slideshow.chrome.settings"]

        // Calm default: chrome is not interactive.
        XCTAssertFalse(settings.isHittable, "chrome should be hidden by default")

        // Tap the photo to reveal the chrome.
        app.descendants(matching: .any).matching(identifier: "slideshow.image").firstMatch.tap()

        XCTAssertTrue(settings.waitForExistence(timeout: 2) && settings.isHittable, "tap should reveal chrome")
        XCTAssertTrue(app.buttons["slideshow.chrome.previous"].isHittable)
        XCTAssertTrue(app.buttons["slideshow.chrome.playPause"].isHittable)
        XCTAssertTrue(app.buttons["slideshow.chrome.next"].isHittable)
        XCTAssertTrue(app.buttons["slideshow.chrome.albums"].isHittable)
        XCTAssertTrue(app.buttons["slideshow.chrome.info"].isHittable)
        // The exit/reset button is gone from chrome — reset now lives in Settings (FR-300-28).
        XCTAssertFalse(app.buttons["slideshow.chrome.exit"].exists)
    }

    @MainActor
    func testTransportAndPlayPauseToggle() throws {
        // Pin the chrome (--uitest-chrome) so the transport focus isn't racing the
        // idle auto-hide; reveal/auto-hide are covered by their own tests.
        let app = launchIntoSlideshow(extraArgs: ["--uitest-chrome"])
        let playPause = app.buttons["slideshow.chrome.playPause"]
        XCTAssertTrue(playPause.waitForExistence(timeout: 2))
        // Running show starts playing -> button offers "Pause".
        XCTAssertEqual(playPause.label, "Pause")
        playPause.tap()
        XCTAssertTrue(waitForLabel(playPause, equals: "Play", timeout: 3),
                      "tapping play/pause should pause the show")

        // Transport remains usable while paused.
        app.buttons["slideshow.chrome.next"].tap()
        app.buttons["slideshow.chrome.previous"].tap()
        // Still paused after manual navigation.
        XCTAssertTrue(waitForLabel(playPause, equals: "Play", timeout: 2))
    }

    /// Regression guard (live smoke, iPhone): the FIRST tap on a freshly revealed
    /// chrome's Next button must advance the photo. Both live-smoke runs showed the
    /// tap being swallowed — the show only moved when the auto-advance ticker fired
    /// ~13s later. Unlike testTransportAndPlayPauseToggle (pinned chrome via
    /// --uitest-chrome, asserts only the pause state), this walks the real reveal
    /// path and asserts the advance itself.
    @MainActor
    func testFirstTapOnRevealedChromeNextAdvances() throws {
        let app = launchIntoSlideshow()
        let image = app.descendants(matching: .any)
            .matching(identifier: "slideshow.image").firstMatch

        image.tap()
        let next = app.buttons["slideshow.chrome.next"]
        XCTAssertTrue(next.waitForExistence(timeout: 2) && next.isHittable,
                      "tap should reveal the chrome")

        let before = image.value as? String
        next.tap()
        let changed = NSPredicate(format: "value != %@", before ?? "")
        expectation(for: changed, evaluatedWith: image)
        waitForExpectations(timeout: 3)
    }

    /// Discriminator for the swallowed-tap bug: same Next-advances assertion, but with
    /// the chrome pinned from launch (--uitest-chrome, no reveal transition). Passing
    /// here while the reveal-path test fails isolates the bug to the reveal path;
    /// failing here means the Next button never advanced at all.
    @MainActor
    func testNextTapAdvancesWithPinnedChrome() throws {
        let app = launchIntoSlideshow(extraArgs: ["--uitest-chrome"])
        let image = app.descendants(matching: .any)
            .matching(identifier: "slideshow.image").firstMatch
        let next = app.buttons["slideshow.chrome.next"]
        XCTAssertTrue(next.waitForExistence(timeout: 2))

        let before = image.value as? String
        next.tap()
        let changed = NSPredicate(format: "value != %@", before ?? "")
        expectation(for: changed, evaluatedWith: image)
        waitForExpectations(timeout: 3)
    }

    @MainActor
    private func waitForLabel(_ element: XCUIElement, equals value: String, timeout: TimeInterval) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline, element.label != value { usleep(100_000) }
        return element.label == value
    }

    @MainActor
    func testSwipeAdvancesWithoutRevealingChrome() throws {
        let app = launchIntoSlideshow()
        let image = app.descendants(matching: .any).matching(identifier: "slideshow.image").firstMatch

        image.swipeLeft()
        image.swipeRight()

        // Swiping navigates but must NOT reveal the chrome (handover).
        XCTAssertFalse(app.buttons["slideshow.chrome.settings"].isHittable, "swipe should not reveal chrome")
        // The slideshow is still running and responsive.
        XCTAssertTrue(image.exists)
    }

    /// Regression guard (300/FR-300-33): `cb83884` fixed a Ken-Burns-forced fill framing
    /// shift in the chrome layout, and `365aea9` silently reverted that structural fix a day
    /// later while chasing an unrelated status-bar bug — with no test to catch it, the shift
    /// came back. Assert the chrome control's on-screen position is identical before/after
    /// toggling Ken Burns live, in landscape (the orientation where it was reported crowding
    /// the screen edge).
    @MainActor
    func testChromeInsetsStableAcrossOrientationAndKenBurns() throws {
        // 1100: this test actually taps Ken Burns on (to force fill framing), so it must own
        // the Supporter Unlock — otherwise the tap hits the locked row and opens the unlock
        // sheet instead of toggling, and the layout check would pass without testing anything.
        let app = launchIntoSlideshow(extraArgs: ["--uitest-chrome", "--uitest-entitlements=supporter"])
        defer { XCUIDevice.shared.orientation = .portrait }

        let settingsButton = app.buttons["slideshow.chrome.settings"]
        XCTAssertTrue(settingsButton.waitForExistence(timeout: 2))

        XCUIDevice.shared.orientation = .landscapeLeft
        XCTAssertTrue(settingsButton.waitForExistence(timeout: 2))
        let frameBefore = settingsButton.frame
        XCTAssertGreaterThan(frameBefore.minY, 20, "chrome control should clear the top edge in landscape")
        XCTAssertLessThan(frameBefore.maxX, app.frame.width - 10,
                          "chrome control should clear the trailing edge in landscape")

        // Toggle Ken Burns on live (forces fill framing) and verify the same control doesn't shift.
        settingsButton.tap()
        let kenBurnsToggle = app.switches["settings.kenBurns"]
        XCTAssertTrue(kenBurnsToggle.waitForExistence(timeout: 3))
        kenBurnsToggle.tap()
        app.buttons["Done"].tap()

        XCTAssertTrue(settingsButton.waitForExistence(timeout: 2))
        let frameAfter = settingsButton.frame
        XCTAssertEqual(frameAfter.origin.x, frameBefore.origin.x, accuracy: 1,
                       "Ken Burns must not shift the chrome horizontally")
        XCTAssertEqual(frameAfter.origin.y, frameBefore.origin.y, accuracy: 1,
                       "Ken Burns must not shift the chrome vertically")
    }

    @MainActor
    func testChromeAutoHidesWhenIdle() throws {
        let app = launchIntoSlideshow()
        let image = app.descendants(matching: .any).matching(identifier: "slideshow.image").firstMatch
        image.tap()

        let settings = app.buttons["slideshow.chrome.settings"]
        XCTAssertTrue(settings.waitForExistence(timeout: 2) && settings.isHittable)

        // Idle past the ~4.5s auto-hide window; the chrome should retreat.
        let hidden = NSPredicate(format: "isHittable == false")
        expectation(for: hidden, evaluatedWith: settings)
        waitForExpectations(timeout: 8)
    }
}
