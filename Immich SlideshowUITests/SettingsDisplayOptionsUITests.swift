//
//  SettingsDisplayOptionsUITests.swift
//  Immich SlideshowUITests
//
//  008 / US1 — the order and duration rows are live controls bound to the settings
//  store, and the choices survive an app relaunch (SC-002). Drives the menu pickers
//  via XCUITest (MCP has no tap tools); the live-apply-to-the-running-show timing is
//  covered by the host DurationTickerTests.
//

import XCTest

final class SettingsDisplayOptionsUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    @MainActor
    func testOrderAndDurationPersistAcrossRelaunch() throws {
        // Start from the calm defaults (reset the hermetic theme suite).
        let app = XCUIApplication()
        app.launchArguments = [
            "--uitest", "--uitest-slideshow", "--uitest-chrome", "--uitest-settings", "--uitest-reset-theme"
        ]
        app.launch()

        // Both live rows are present, showing the defaults.
        let order = app.descendants(matching: .any).matching(identifier: "settings.order").firstMatch
        XCTAssertTrue(order.waitForExistence(timeout: 5), "order picker should exist")
        let duration = app.descendants(matching: .any).matching(identifier: "settings.duration").firstMatch
        XCTAssertTrue(duration.waitForExistence(timeout: 2), "duration picker should exist")
        XCTAssertTrue(app.staticTexts["Shuffle"].firstMatch.exists, "order defaults to shuffle")
        XCTAssertTrue(app.staticTexts["15 s"].firstMatch.exists, "duration defaults to 15 s")

        // Change order shuffle -> sequential via the menu picker.
        order.tap()
        app.buttons["Sequential"].firstMatch.tap()

        // Change duration 15 s -> 30 s.
        duration.tap()
        app.buttons["30 s"].firstMatch.tap()

        // Relaunch WITHOUT the reset arg: the choices persist (SC-002).
        app.terminate()
        let relaunch = XCUIApplication()
        relaunch.launchArguments = [
            "--uitest", "--uitest-slideshow", "--uitest-chrome", "--uitest-settings"
        ]
        relaunch.launch()

        let orderAfter = relaunch.descendants(matching: .any)
            .matching(identifier: "settings.order").firstMatch
        XCTAssertTrue(orderAfter.waitForExistence(timeout: 5), "settings reopen after relaunch")
        XCTAssertTrue(
            relaunch.staticTexts["Sequential"].firstMatch.waitForExistence(timeout: 2),
            "sequential order should persist across relaunch"
        )
        XCTAssertTrue(
            relaunch.staticTexts["30 s"].firstMatch.exists,
            "30 s duration should persist across relaunch"
        )
    }

    @MainActor
    func testTransitionAndKenBurnsPersistAcrossRelaunch() throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "--uitest", "--uitest-slideshow", "--uitest-chrome", "--uitest-settings", "--uitest-reset-theme"
        ]
        app.launch()

        // Defaults: crossfade transition, Ken Burns off.
        let transition = app.descendants(matching: .any).matching(identifier: "settings.transition").firstMatch
        XCTAssertTrue(transition.waitForExistence(timeout: 5), "transition picker should exist")
        let kenBurns = app.switches["settings.kenBurns"]
        XCTAssertTrue(kenBurns.waitForExistence(timeout: 2), "Ken Burns toggle should exist")
        XCTAssertEqual(kenBurns.value as? String, "0", "Ken Burns defaults to off")

        // Change transition crossfade -> slide; enable Ken Burns.
        transition.tap()
        app.buttons["Slide"].firstMatch.tap()
        // Tap the switch control on the row's trailing edge (a center tap lands on the
        // label in a Form row and doesn't flip the toggle).
        kenBurns.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.5)).tap()
        XCTAssertEqual(kenBurns.value as? String, "1", "tapping the toggle should turn Ken Burns on")

        // Dismiss the sheet (a natural settle so the writes flush) before relaunch.
        app.buttons["Done"].tap()
        let image = app.descendants(matching: .any).matching(identifier: "slideshow.image").firstMatch
        XCTAssertTrue(image.waitForExistence(timeout: 3))

        // Relaunch WITHOUT reset: the choices persist.
        app.terminate()
        let relaunch = XCUIApplication()
        relaunch.launchArguments = [
            "--uitest", "--uitest-slideshow", "--uitest-chrome", "--uitest-settings"
        ]
        relaunch.launch()

        XCTAssertTrue(
            relaunch.descendants(matching: .any).matching(identifier: "settings.transition").firstMatch
                .waitForExistence(timeout: 5)
        )
        XCTAssertTrue(
            relaunch.staticTexts["Slide"].firstMatch.waitForExistence(timeout: 2),
            "slide transition should persist across relaunch"
        )
        XCTAssertEqual(
            relaunch.switches["settings.kenBurns"].value as? String, "1",
            "Ken Burns should persist as on across relaunch"
        )
    }
}
