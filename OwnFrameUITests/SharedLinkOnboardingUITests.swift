//
//  SharedLinkOnboardingUITests.swift
//  OwnFrameUITests
//
//  210 / US1 — shared-link-only onboarding. From the first-run choice screen the user
//  picks the shared-link path and reaches the slideshow with no API key and no server
//  connection step; a password is asked for only when the link requires one; an invalid
//  link errors with nothing persisted. Hermetic `--uitest` build: the stub resolver maps
//  any link to album a2, reserves slug `protected` (password "letmein") and slug `missing`
//  (invalid link).
//

import XCTest

final class SharedLinkOnboardingUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
        // Never inherit a rotation leaked by an earlier test on the same simulator
        // clone — a launch during a stale landscape state positions the chrome
        // off-screen. Tests that need landscape rotate themselves (and restore).
        MainActor.assumeIsolated { XCUIDevice.shared.orientation = .portrait }
    }

    /// Happy path: choice → "Use an Immich link" → paste a non-protected link → Start →
    /// the slideshow plays (a2 → asset-4…6). No connection step, so no API key was entered.
    @MainActor
    func testSharedLinkOnlyChoiceReachesSlideshowWithoutAPIKey() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--uitest", "--uitest-onboarding-choice"]
        app.launch()

        let sharedLinkChoice = app.buttons["onboarding.choice.sharedLink"]
        XCTAssertTrue(sharedLinkChoice.waitForExistence(timeout: 5), "choice screen should offer the shared-link path")
        sharedLinkChoice.tap()

        enterLink(app, "https://demo.example.com/s/abc123")
        app.releaseKeyboardFocus() // #75: iOS 26+ swallows a synthesized tap while a field has focus
        app.buttons["onboarding.sharedLink.start"].tap()

        // No password prompt for a non-protected link — it goes straight to the slideshow.
        XCTAssertFalse(app.textFields["onboarding.sharedLink.password"].waitForExistence(timeout: 2),
                       "a non-protected link must not prompt for a password")

        assertSlideshowPlays(app, assets: ["asset-4", "asset-5", "asset-6"])
    }

    /// Protected link: Start surfaces a single password prompt; the correct password
    /// continues to the slideshow.
    @MainActor
    func testProtectedSharedLinkPromptsOnceThenReachesSlideshow() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--uitest", "--uitest-shared-link-only"]
        app.launch()

        enterLink(app, "https://demo.example.com/s/protected")
        app.releaseKeyboardFocus() // #75: iOS 26+ swallows a synthesized tap while a field has focus
        app.buttons["onboarding.sharedLink.start"].tap()

        let password = app.textFields["onboarding.sharedLink.password"]
        XCTAssertTrue(password.waitForExistence(timeout: 5), "a protected link should prompt for a password")
        password.tap()
        password.typeText("letmein")
        app.releaseKeyboardFocus() // #75: iOS 26+ swallows a synthesized tap while a field has focus
        app.buttons["onboarding.sharedLink.password.continue"].tap()

        assertSlideshowPlays(app, assets: ["asset-4", "asset-5", "asset-6"])
    }

    /// Invalid link: an unresolvable link surfaces a classified error and stays on the
    /// setup screen — nothing is persisted, so no slideshow starts.
    @MainActor
    func testInvalidSharedLinkErrorsAndDoesNotStart() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--uitest", "--uitest-shared-link-only"]
        app.launch()

        enterLink(app, "https://demo.example.com/s/missing")
        app.releaseKeyboardFocus() // #75: iOS 26+ swallows a synthesized tap while a field has focus
        app.buttons["onboarding.sharedLink.start"].tap()

        let error = app.staticTexts["onboarding.sharedLink.error"]
        XCTAssertTrue(error.waitForExistence(timeout: 5), "an invalid link should surface an error")

        // Still on the setup screen; no slideshow image ever appears.
        XCTAssertTrue(app.textFields["onboarding.sharedLink.url"].exists, "should remain on the shared-link setup screen")
        let image = app.descendants(matching: .any).matching(identifier: "slideshow.image").firstMatch
        XCTAssertFalse(image.waitForExistence(timeout: 3), "an invalid link must not start the slideshow")
    }

    /// Landscape (the iPad's primary orientation): the choice screen and the shared-link
    /// setup both render and the happy path completes when the device is rotated. Guards
    /// the Form/List layout of the two new screens in landscape.
    @MainActor
    func testSharedLinkOnlyChoiceReachesSlideshowInLandscape() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--uitest", "--uitest-onboarding-choice"]
        app.launch()
        XCUIDevice.shared.orientation = .landscapeLeft
        defer { XCUIDevice.shared.orientation = .portrait }

        let sharedLinkChoice = app.buttons["onboarding.choice.sharedLink"]
        XCTAssertTrue(sharedLinkChoice.waitForExistence(timeout: 5), "choice screen should render in landscape")
        sharedLinkChoice.tap()

        enterLink(app, "https://demo.example.com/s/abc123")
        app.releaseKeyboardFocus() // #75: iOS 26+ swallows a synthesized tap while a field has focus
        app.buttons["onboarding.sharedLink.start"].tap()

        assertSlideshowPlays(app, assets: ["asset-4", "asset-5", "asset-6"])
    }

    // MARK: - Helpers

    @MainActor
    private func enterLink(_ app: XCUIApplication, _ link: String) {
        let url = app.textFields["onboarding.sharedLink.url"]
        XCTAssertTrue(url.waitForExistence(timeout: 5), "shared-link URL field should appear")
        url.tap()
        url.typeText(link)
    }

    @MainActor
    private func assertSlideshowPlays(_ app: XCUIApplication, assets: [String]) {
        let image = app.descendants(matching: .any).matching(identifier: "slideshow.image").firstMatch
        XCTAssertTrue(image.waitForExistence(timeout: 30), "the Immich link should route to the running slideshow")
        let plays = NSPredicate(format: "value IN %@", assets)
        expectation(for: plays, evaluatedWith: image)
        waitForExpectations(timeout: 5)
    }

    /// 220 SC-220-05 + issue #82 — Scan QR must never open an EMPTY cover (#82: stale
    /// `isPresented` + `if let` rendered it black). Without a usable camera (iOS 17/18
    /// simulators) it must land on the calm "paste the link instead" fallback and stay there
    /// until Done — a failed scan used to dismiss the cover before the fallback showed. iOS 27
    /// simulators offer a camera, so there the live scanner's Cancel is the proof instead.
    @MainActor
    func testScanWithoutUsableCameraShowsFallbackUntilDone() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--uitest", "--uitest-shared-link-only"]
        app.launch()

        let scan = app.buttons["onboarding.sharedLink.scan"]
        XCTAssertTrue(scan.waitForExistence(timeout: 5), "the link step should offer Scan QR")
        scan.tap()

        // A simulator that has a camera may ask first — deny, so the fallback path runs.
        let permission = XCUIApplication(bundleIdentifier: "com.apple.springboard").alerts.firstMatch
        if permission.waitForExistence(timeout: 3) { permission.buttons.element(boundBy: 0).tap() }

        let fallback = app.staticTexts["onboarding.sharedLink.scan.unavailable"]
        let cancel = app.buttons["onboarding.sharedLink.scan.cancel"]
        XCTAssertTrue(cancel.waitForExistence(timeout: 10),
                      "the scanner cover must show its controls, never an empty black cover (#82)")
        let sawFallback = fallback.exists
        sleep(2) // a failed scan used to dismiss the cover right here
        XCTAssertTrue(cancel.exists, "the cover must stay until the user dismisses it")
        if sawFallback {
            XCTAssertTrue(fallback.exists, "the fallback must stay until the user dismisses it")
        }

        cancel.tap()
        XCTAssertTrue(app.textFields["onboarding.sharedLink.url"].waitForExistence(timeout: 5),
                      "Cancel/Done should return to the link field")
    }
}
