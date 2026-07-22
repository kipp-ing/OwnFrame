//
//  PhotoInfoUITests.swift
//  OwnFrameUITests
//
//  Slice C — drives the photo-info overlay against the hermetic build. The stub
//  API returns deterministic EXIF (Berlin, Germany), so revealing the chrome and
//  tapping the info button must surface the date + location card.
//

import XCTest

final class PhotoInfoUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
        // Never inherit a rotation leaked by an earlier test on the same simulator
        // clone — a launch during a stale landscape state positions the chrome
        // off-screen. Tests that need landscape rotate themselves (and restore).
        MainActor.assumeIsolated { XCUIDevice.shared.orientation = .portrait }
    }

    @MainActor
    func testInfoButtonTogglesDateAndLocationOverlay() throws {
        let app = XCUIApplication()
        // Pin the chrome so the info-toggle focus isn't racing the idle auto-hide.
        app.launchArguments = ["--uitest", "--uitest-slideshow", "--uitest-chrome"]
        app.launch()

        let image = app.descendants(matching: .any)
            .matching(identifier: "slideshow.image").firstMatch
        XCTAssertTrue(image.waitForExistence(timeout: 5))

        // Toggle the info overlay on.
        let infoButton = app.buttons["slideshow.chrome.info"]
        XCTAssertTrue(infoButton.waitForExistence(timeout: 2))
        infoButton.tap()

        let card = app.descendants(matching: .any)
            .matching(identifier: "slideshow.info.card").firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 3), "info overlay should appear")
        XCTAssertTrue(
            app.staticTexts["Berlin, Germany"].waitForExistence(timeout: 2),
            "overlay should show the stub location"
        )

        // Toggle it back off.
        infoButton.tap()
        let gone = NSPredicate(format: "exists == false")
        expectation(for: gone, evaluatedWith: card)
        waitForExpectations(timeout: 3)
    }

    /// Regression guard (live smoke, iPhone portrait): the info card was overlaid at a
    /// fixed 100pt from the top, which collides with the top chrome buttons on compact
    /// widths — the centered card and the right-aligned button row only miss each other
    /// on wide (iPad/landscape) screens. The card must never cover the chrome's buttons.
    @MainActor
    func testInfoCardDoesNotCoverChromeButtons() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--uitest", "--uitest-slideshow", "--uitest-chrome"]
        app.launch()

        let infoButton = app.buttons["slideshow.chrome.info"]
        XCTAssertTrue(infoButton.waitForExistence(timeout: 5))
        infoButton.tap()

        let card = app.descendants(matching: .any)
            .matching(identifier: "slideshow.info.card").firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 3), "info overlay should appear")

        // The card's AX frame is the union of its text labels; the glass background
        // extends another 12pt (the card's vertical padding) beyond it, so demand
        // that much clearance below the bar's lowest button.
        let barBottom = ["slideshow.chrome.info", "slideshow.chrome.albums", "slideshow.chrome.settings"]
            .map { app.buttons[$0].frame.maxY }
            .max() ?? 0
        XCTAssertGreaterThanOrEqual(
            card.frame.minY - 12, barBottom,
            "info card (incl. its glass padding) must sit below the top chrome bar, card \(card.frame), bar bottom \(barBottom)"
        )
    }
}
