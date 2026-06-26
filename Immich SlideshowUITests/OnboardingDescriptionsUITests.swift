//
//  OnboardingDescriptionsUITests.swift
//  Immich SlideshowUITests
//
//  210 / US5 — every onboarding screen carries concise helper text describing the step's
//  purpose and the expected action (FR-210-23, SC-210-08). Each screen is reached via its
//  hermetic `--uitest` seam and asserted to expose an identified description element so a
//  first-time user is never guessing.
//

import XCTest

final class OnboardingDescriptionsUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    /// Choice screen: the first-run entry explains how to reach your photos.
    @MainActor
    func testChoiceScreenShowsDescription() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--uitest", "--uitest-onboarding-choice"]
        app.launch()

        let description = app.staticTexts["onboarding.choice.intro"]
        XCTAssertTrue(description.waitForExistence(timeout: 5), "the choice screen should show helper text")
    }

    /// Shared-link setup: the lowest-friction path explains it needs only a link.
    @MainActor
    func testSharedLinkSetupShowsDescription() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--uitest", "--uitest-shared-link-only"]
        app.launch()

        let description = app.staticTexts["onboarding.sharedLink.description"]
        XCTAssertTrue(description.waitForExistence(timeout: 5), "the shared-link setup screen should show helper text")
    }

    /// Connection step: explains the server-connection path.
    @MainActor
    func testConnectionStepShowsDescription() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--uitest"]
        app.launch()

        let description = app.staticTexts["onboarding.connection.description"]
        XCTAssertTrue(description.waitForExistence(timeout: 5), "the connection step should show helper text")
    }

    /// Source step and confirm step: both annotate their purpose. The confirm step is
    /// reached by adding the first stubbed album and continuing.
    @MainActor
    func testSourceAndConfirmStepsShowDescriptions() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--uitest", "--uitest-onboarding-source"]
        app.launch()

        let sourceDescription = app.staticTexts["onboarding.source.description"]
        XCTAssertTrue(sourceDescription.waitForExistence(timeout: 5), "the source step should show helper text")

        // Add an album so the confirm step becomes reachable.
        let album = app.buttons["onboarding.album.a1"]
        XCTAssertTrue(album.waitForExistence(timeout: 5))
        album.tap()
        let cont = app.buttons["onboarding.source.continue"]
        XCTAssertTrue(cont.waitForExistence(timeout: 5))
        cont.tap()

        let confirmDescription = app.staticTexts["onboarding.confirm.description"]
        XCTAssertTrue(confirmDescription.waitForExistence(timeout: 5), "the confirm step should show helper text")
    }
}
