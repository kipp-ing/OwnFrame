//
//  PhotoInfoUITests.swift
//  Immich SlideshowUITests
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
}
