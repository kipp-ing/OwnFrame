//
//  OnboardingBackUITests.swift
//  Immich SlideshowUITests
//
//  210 / FR-210-26 — every onboarding step after the choice screen offers a Back affordance
//  that returns to the previous step in-place (no app restart). Hermetic `--uitest` build:
//  onboarding starts on the choice screen (`--uitest-onboarding-choice`).
//

import XCTest

final class OnboardingBackUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// Shared-link path → Back returns to the choice screen.
    @MainActor
    func testBackFromSharedLinkReturnsToChoice() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--uitest", "--uitest-onboarding-choice"]
        app.launch()

        let sharedLinkChoice = app.buttons["onboarding.choice.sharedLink"]
        XCTAssertTrue(sharedLinkChoice.waitForExistence(timeout: 5))
        sharedLinkChoice.tap()

        let back = app.buttons["onboarding.back"]
        XCTAssertTrue(back.waitForExistence(timeout: 5), "the shared-link setup step should offer Back")
        back.tap()

        XCTAssertTrue(sharedLinkChoice.waitForExistence(timeout: 5), "Back should return to the choice screen")
    }

    /// Server path → Back returns to the choice screen.
    @MainActor
    func testBackFromServerConnectionReturnsToChoice() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--uitest", "--uitest-onboarding-choice"]
        app.launch()

        let serverChoice = app.buttons["onboarding.choice.server"]
        XCTAssertTrue(serverChoice.waitForExistence(timeout: 5))
        serverChoice.tap()

        let back = app.buttons["onboarding.back"]
        XCTAssertTrue(back.waitForExistence(timeout: 5), "the server connection step should offer Back")
        back.tap()

        XCTAssertTrue(serverChoice.waitForExistence(timeout: 5), "Back should return to the choice screen")
    }

    /// The choice screen is the first step and has no Back.
    @MainActor
    func testChoiceScreenHasNoBack() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--uitest", "--uitest-onboarding-choice"]
        app.launch()

        XCTAssertTrue(app.buttons["onboarding.choice.sharedLink"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["onboarding.back"].exists, "the first onboarding step should have no Back")
    }
}
