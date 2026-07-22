//
//  ShareSheetIncomingUITests.swift
//  OwnFrameUITests
//
//  210 / US2 — the host's consumption of a shared link handed in by the Share Extension.
//  The real system Share Sheet isn't XCUITest-drivable (that round trip is the manual
//  device test, T025), so the `--uitest-pending-link <url>` seam injects the pending URL
//  exactly as the extension would (App-Group hand-off), and these tests assert the host's
//  routing: unconfigured pre-fills onboarding; configured resolves+activates and the
//  slideshow switches; an invalid link errors with nothing persisted. The hermetic stub
//  resolver maps any link to album a2 and reserves slug `missing` (invalid).
//

import XCTest

final class ShareSheetIncomingUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
        // Never inherit a rotation leaked by an earlier test on the same simulator
        // clone — a launch during a stale landscape state positions the chrome
        // off-screen. Tests that need landscape rotate themselves (and restore).
        MainActor.assumeIsolated { XCUIDevice.shared.orientation = .portrait }
    }

    /// Unconfigured: a shared link arriving on a blank install routes to the shared-link
    /// setup screen with the link pre-filled, ready to Start.
    @MainActor
    func testIncomingLinkPrefillsSetupWhenUnconfigured() throws {
        let link = "https://demo.example.com/s/abc123"
        let app = XCUIApplication()
        app.launchArguments = ["--uitest", "--uitest-onboarding-choice", "--uitest-pending-link", link]
        app.launch()

        let url = app.textFields["onboarding.sharedLink.url"]
        XCTAssertTrue(url.waitForExistence(timeout: 5), "an incoming link should open the shared-link setup screen")
        // The pending link populates the field as onboarding flips to the shared-link step.
        // Under full-suite load that propagation can lag the field's first appearance by a
        // beat, during which the still-empty field reads back as its "https://host/s/slug"
        // placeholder — so wait for the value to converge instead of reading it once (#22).
        let prefilled = NSPredicate(format: "value == %@", link)
        expectation(for: prefilled, evaluatedWith: url)
        waitForExpectations(timeout: 5)
    }

    /// Configured: a shared link arriving while a slideshow is already running resolves and
    /// becomes the active source — playback switches to the shared link's album (a2).
    @MainActor
    func testIncomingLinkAddsActivatesAndSwitchesPlaybackWhenConfigured() throws {
        let link = "https://demo.example.com/s/holiday"
        let app = XCUIApplication()
        // `--uitest-slideshow` starts configured on album a1 (asset-1…3); the incoming link
        // resolves to a2 (asset-4…6), so a switch is observable.
        app.launchArguments = ["--uitest", "--uitest-slideshow", "--uitest-pending-link", link]
        app.launch()

        assertSlideshowPlays(app, assets: ["asset-4", "asset-5", "asset-6"])
    }

    /// Configured + invalid: an unresolvable link surfaces an error in the add sheet and
    /// nothing is persisted, so playback never switches to the shared link's album.
    @MainActor
    func testIncomingInvalidLinkErrorsAndDoesNotSwitch() throws {
        let link = "https://demo.example.com/s/missing"
        let app = XCUIApplication()
        app.launchArguments = ["--uitest", "--uitest-slideshow", "--uitest-pending-link", link]
        app.launch()

        let error = app.staticTexts["incomingLink.error"]
        XCTAssertTrue(error.waitForExistence(timeout: 10), "an invalid incoming link should surface an error")

        // Closing the error sheet leaves the original album (a1) playing — no switch to a2.
        app.buttons["incomingLink.close"].tap()
        let image = app.descendants(matching: .any).matching(identifier: "slideshow.image").firstMatch
        XCTAssertTrue(image.waitForExistence(timeout: 10), "the original slideshow should still be running")
        let stayed = NSPredicate(format: "value IN %@", ["asset-1", "asset-2", "asset-3"])
        expectation(for: stayed, evaluatedWith: image)
        waitForExpectations(timeout: 5)
    }

    // MARK: - Helpers

    @MainActor
    private func assertSlideshowPlays(_ app: XCUIApplication, assets: [String]) {
        let image = app.descendants(matching: .any).matching(identifier: "slideshow.image").firstMatch
        XCTAssertTrue(image.waitForExistence(timeout: 30), "the incoming link should route to the running slideshow")
        let plays = NSPredicate(format: "value IN %@", assets)
        expectation(for: plays, evaluatedWith: image)
        waitForExpectations(timeout: 15)
    }
}
