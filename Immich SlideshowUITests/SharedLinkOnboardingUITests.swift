//
//  SharedLinkOnboardingUITests.swift
//  Immich SlideshowUITests
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

    /// Happy path: choice → "Use a shared link" → paste a non-protected link → Start →
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
        app.buttons["onboarding.sharedLink.start"].tap()

        let password = app.textFields["onboarding.sharedLink.password"]
        XCTAssertTrue(password.waitForExistence(timeout: 5), "a protected link should prompt for a password")
        password.tap()
        password.typeText("letmein")
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
        XCTAssertTrue(image.waitForExistence(timeout: 30), "the shared link should route to the running slideshow")
        let plays = NSPredicate(format: "value IN %@", assets)
        expectation(for: plays, evaluatedWith: image)
        waitForExpectations(timeout: 5)
    }
}
