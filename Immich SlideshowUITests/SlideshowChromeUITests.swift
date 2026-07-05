//
//  SlideshowChromeUITests.swift
//  Immich SlideshowUITests
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
        let exit = app.buttons["slideshow.chrome.exit"]

        // Calm default: chrome is not interactive.
        XCTAssertFalse(exit.isHittable, "chrome should be hidden by default")

        // Tap the photo to reveal the chrome.
        app.descendants(matching: .any).matching(identifier: "slideshow.image").firstMatch.tap()

        XCTAssertTrue(exit.waitForExistence(timeout: 2) && exit.isHittable, "tap should reveal chrome")
        XCTAssertTrue(app.buttons["slideshow.chrome.previous"].isHittable)
        XCTAssertTrue(app.buttons["slideshow.chrome.playPause"].isHittable)
        XCTAssertTrue(app.buttons["slideshow.chrome.next"].isHittable)
        XCTAssertTrue(app.buttons["slideshow.chrome.albums"].isHittable)
        XCTAssertTrue(app.buttons["slideshow.chrome.settings"].isHittable)
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
        XCTAssertFalse(app.buttons["slideshow.chrome.exit"].isHittable, "swipe should not reveal chrome")
        // The slideshow is still running and responsive.
        XCTAssertTrue(image.exists)
    }

    @MainActor
    func testChromeAutoHidesWhenIdle() throws {
        let app = launchIntoSlideshow()
        let image = app.descendants(matching: .any).matching(identifier: "slideshow.image").firstMatch
        image.tap()

        let exit = app.buttons["slideshow.chrome.exit"]
        XCTAssertTrue(exit.waitForExistence(timeout: 2) && exit.isHittable)

        // Idle past the ~4.5s auto-hide window; the chrome should retreat.
        let hidden = NSPredicate(format: "isHittable == false")
        expectation(for: hidden, evaluatedWith: exit)
        waitForExpectations(timeout: 8)
    }
}
