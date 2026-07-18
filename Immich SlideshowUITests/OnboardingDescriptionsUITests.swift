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
        // Never inherit a rotation leaked by an earlier test on the same simulator
        // clone — a launch during a stale landscape state positions the chrome
        // off-screen. Tests that need landscape rotate themselves (and restore).
        MainActor.assumeIsolated { XCUIDevice.shared.orientation = .portrait }
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

    /// 220 / US3 — the choice screen offers exactly three friction-ordered options
    /// (iCloud, then shared link, then server), each with its own helper text, and no Back.
    @MainActor
    func testChoiceScreenShowsThreeFrictionOrderedOptions() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--uitest", "--uitest-onboarding-choice"]
        app.launch()

        let photoLibrary = app.buttons["onboarding.choice.photoLibrary"]
        let sharedLink = app.buttons["onboarding.choice.sharedLink"]
        let server = app.buttons["onboarding.choice.server"]

        XCTAssertTrue(photoLibrary.waitForExistence(timeout: 5), "the iCloud option should exist")
        XCTAssertTrue(sharedLink.waitForExistence(timeout: 5), "the shared-link option should exist")
        XCTAssertTrue(server.waitForExistence(timeout: 5), "the server option should exist")

        let choiceButtons = app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "onboarding.choice."))
        XCTAssertEqual(choiceButtons.count, 3, "exactly three friction-ordered options should be offered")

        // Friction order, top to bottom: iCloud (easiest), then shared link, then server.
        XCTAssertLessThan(photoLibrary.frame.minY, sharedLink.frame.minY, "iCloud should sit above the shared-link option")
        XCTAssertLessThan(sharedLink.frame.minY, server.frame.minY, "shared link should sit above the server option")

        // Each option exposes helper text beyond a bare title — asserted by length rather than
        // exact copy so light rewording of the description doesn't break this test. A title
        // alone (e.g. "Connect to a server") runs well under this threshold; combined with its
        // one-line helper text via accessibilityElement(children: .combine) it comfortably clears it.
        for button in [photoLibrary, sharedLink, server] {
            XCTAssertGreaterThan(
                button.label.count, 30,
                "\(button.identifier) should expose helper text, not just a title"
            )
        }

        XCTAssertFalse(app.buttons["onboarding.back"].exists, "the choice screen should have no Back")
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
