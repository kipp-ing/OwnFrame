//
//  ClockOverlayUITests.swift
//  Immich SlideshowUITests
//
//  Drives the optional clock overlay (510) against the hermetic
//  `--uitest --uitest-slideshow --uitest-clock*` build. Verifies presence and the
//  default digits style, the vanish-on-chrome / return-on-auto-hide rule (SC-500-07),
//  that swipe navigation neither reveals the chrome nor hides the clock, that a failed
//  phase keeps the clock hidden, the pill/analog styles at representative places, and
//  deterministic Random placement that holds within its cadence.
//

import XCTest

final class ClockOverlayUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
        MainActor.assumeIsolated { XCUIDevice.shared.orientation = .portrait }
    }

    // MARK: - Helpers

    @MainActor
    private func launchIntoSlideshow(extraArgs: [String] = [], expectImage: Bool = true) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--uitest", "--uitest-slideshow"] + extraArgs
        app.launch()
        if expectImage {
            XCTAssertTrue(image(app).waitForExistence(timeout: 5), "slideshow should be running")
        }
        return app
    }

    @MainActor private func image(_ app: XCUIApplication) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: "slideshow.image").firstMatch
    }

    @MainActor private func el(_ app: XCUIApplication, _ id: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: id).firstMatch
    }

    // MARK: - Presence & default styling (T006a)

    @MainActor
    func testClockPresentWithDigitsByDefault() throws {
        let app = launchIntoSlideshow(extraArgs: ["--uitest-clock"])
        let clock = el(app, "slideshow.clock")
        XCTAssertTrue(clock.waitForExistence(timeout: 3), "clock should be present")
        XCTAssertEqual(clock.value as? String, "digits", "default style is digits")
    }

    // MARK: - Vanish on chrome, return on auto-hide (SC-500-07, T006b)

    @MainActor
    func testChromeRevealHidesClockAndAutoHideReturnsIt() throws {
        let app = launchIntoSlideshow(extraArgs: ["--uitest-clock"])
        let clock = el(app, "slideshow.clock")
        XCTAssertTrue(clock.waitForExistence(timeout: 3))

        // Reveal the chrome: the clock steps aside while the controls are hittable.
        image(app).tap()
        let settings = app.buttons["slideshow.chrome.settings"]
        XCTAssertTrue(settings.waitForExistence(timeout: 2) && settings.isHittable, "tap reveals chrome")
        XCTAssertTrue(el(app, "slideshow.clock").waitForNonExistence(timeout: 2),
                      "clock must be hidden while the chrome is visible (SC-500-07)")

        // Idle past the ~4.5s auto-hide; the chrome retreats and the clock returns.
        expectation(for: NSPredicate(format: "isHittable == false"), evaluatedWith: settings)
        waitForExpectations(timeout: 8)
        XCTAssertTrue(el(app, "slideshow.clock").waitForExistence(timeout: 3),
                      "clock returns once the chrome auto-hides")
    }

    // MARK: - Swipe keeps the clock, does not reveal chrome (T006c)

    @MainActor
    func testSwipeKeepsClockAndDoesNotRevealChrome() throws {
        let app = launchIntoSlideshow(extraArgs: ["--uitest-clock"])
        XCTAssertTrue(el(app, "slideshow.clock").waitForExistence(timeout: 3))

        image(app).swipeLeft()
        image(app).swipeRight()

        XCTAssertFalse(app.buttons["slideshow.chrome.settings"].isHittable, "swipe must not reveal chrome")
        XCTAssertTrue(el(app, "slideshow.clock").exists, "swipe must not hide the clock")
    }

    // MARK: - Failed phase keeps the clock hidden (T006d)

    @MainActor
    func testFailedPhaseKeepsClockHidden() throws {
        // Clock enabled, but assets fail: the show pins the chrome in the error state, so
        // the clock never shows while the chrome is pinned.
        // `--uitest-reset-storage`: start with no 320 snapshot, otherwise the offline
        // fallback would replay a cached album (left by an earlier test) instead of
        // failing, and the error state we need here would never appear.
        let app = launchIntoSlideshow(
            extraArgs: ["--uitest-reset-storage", "--uitest-clock", "--uitest-assets-fail=unreachable"],
            expectImage: false
        )
        XCTAssertTrue(app.staticTexts["slideshow.error"].waitForExistence(timeout: 8),
                      "failed phase should surface the calm error state")
        XCTAssertFalse(el(app, "slideshow.clock").exists, "clock stays hidden in the failed phase")
    }

    // MARK: - Styles & places sweep (T009)

    @MainActor
    func testPillStyleAtTopCenter() throws {
        let app = launchIntoSlideshow(extraArgs: ["--uitest-clock-style=pill", "--uitest-clock-place=topCenter"])
        let clock = el(app, "slideshow.clock")
        XCTAssertTrue(clock.waitForExistence(timeout: 3), "pill style should render")
        XCTAssertEqual(clock.value as? String, "pill")

        let screen = app.frame
        XCTAssertLessThan(clock.frame.midY, screen.height / 3, "topCenter → top third")
        XCTAssertLessThan(abs(clock.frame.midX - screen.midX), screen.width * 0.15, "topCenter → horizontally centered")
    }

    @MainActor
    func testAnalogStyleAtBottomLeading() throws {
        let app = launchIntoSlideshow(extraArgs: ["--uitest-clock-style=analog", "--uitest-clock-place=bottomLeading"])
        let clock = el(app, "slideshow.clock")
        XCTAssertTrue(clock.waitForExistence(timeout: 3), "analog style should render")
        XCTAssertEqual(clock.value as? String, "analog")

        let screen = app.frame
        XCTAssertGreaterThan(clock.frame.midY, screen.height * 2 / 3, "bottomLeading → bottom third")
        XCTAssertLessThan(clock.frame.midX, screen.width / 2, "bottomLeading → leading half")
    }

    // MARK: - Random determinism holds within the cadence (T010)

    @MainActor
    func testRandomSeededStableWithinCadence() throws {
        let app = launchIntoSlideshow(extraArgs: ["--uitest-clock-place=random", "--uitest-clock-seed=1"])
        let clock = el(app, "slideshow.clock")
        XCTAssertTrue(clock.waitForExistence(timeout: 3), "random clock resolves to a fixed place")
        let before = clock.frame

        // Several fast photo advances stay well within the 6-minute relocation cadence,
        // so the clock must not move.
        for _ in 0..<4 { image(app).swipeLeft() }

        let after = el(app, "slideshow.clock").frame
        XCTAssertEqual(after.midX, before.midX, accuracy: 1, "no relocation within cadence (x)")
        XCTAssertEqual(after.midY, before.midY, accuracy: 1, "no relocation within cadence (y)")
    }

    // MARK: - Live settings rows drive the overlay and persist (T011, FR-500-05)

    @MainActor
    func testClockPersistsAcrossRelaunch() throws {
        // Seam sets a non-default clock (on, analog) from reset defaults; with the chrome
        // hidden the overlay reflects it, and the store persists it.
        let app = XCUIApplication()
        app.launchArguments = [
            "--uitest", "--uitest-slideshow", "--uitest-reset-theme", "--uitest-clock-style=analog"
        ]
        app.launch()
        let clock = el(app, "slideshow.clock")
        XCTAssertTrue(clock.waitForExistence(timeout: 5), "seam clock shows")
        XCTAssertEqual(clock.value as? String, "analog", "overlay reflects the seam style")

        // Relaunch WITHOUT seams: the clock persists on, in Analog (FR-500-05).
        app.terminate()
        let relaunch = XCUIApplication()
        relaunch.launchArguments = ["--uitest", "--uitest-slideshow"]
        relaunch.launch()
        let persisted = relaunch.descendants(matching: .any).matching(identifier: "slideshow.clock").firstMatch
        XCTAssertTrue(persisted.waitForExistence(timeout: 5), "clock persisted on across relaunch")
        XCTAssertEqual(persisted.value as? String, "analog", "style persisted across relaunch")
    }

    // MARK: - Live settings rows reflect the store (T012, FR-500-13)

    @MainActor
    func testSettingsRowsReflectClockStore() throws {
        // Clock on with non-default style/place via seams; Settings open, chrome pinned.
        let app = XCUIApplication()
        app.launchArguments = [
            "--uitest", "--uitest-slideshow", "--uitest-chrome", "--uitest-settings",
            "--uitest-reset-theme", "--uitest-clock-style=analog", "--uitest-clock-place=topCenter"
        ]
        app.launch()

        // The rows exist and read back the store's values (they are live bindings).
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "settings.clock.style").firstMatch
            .waitForExistence(timeout: 5), "clock rows present while the clock is on")
        XCTAssertTrue(app.staticTexts["Analog"].firstMatch.exists, "style row reflects Analog")
        XCTAssertTrue(app.staticTexts["Top middle"].firstMatch.exists, "place row reflects Top middle")
    }
}
