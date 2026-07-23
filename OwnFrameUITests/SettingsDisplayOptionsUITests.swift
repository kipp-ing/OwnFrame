//
//  SettingsDisplayOptionsUITests.swift
//  OwnFrameUITests
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
        // Never inherit a rotation leaked by an earlier test on the same simulator
        // clone — a launch during a stale landscape state positions the chrome
        // off-screen. Tests that need landscape rotate themselves (and restore).
        MainActor.assumeIsolated { XCUIDevice.shared.orientation = .portrait }
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

    // Regression: a non-preset duration (any integer 3…600 s Home Assistant can push,
    // retained on the MQTT broker across a device reinstall) must still show a value in
    // the picker instead of rendering blank. See ThemeSettings.durationOptions(including:).
    @MainActor
    func testNonPresetDurationIsShownInsteadOfBlank() throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "--uitest", "--uitest-slideshow", "--uitest-chrome", "--uitest-settings",
            "--uitest-reset-theme", "--uitest-duration-seconds=20"
        ]
        app.launch()

        let duration = app.descendants(matching: .any).matching(identifier: "settings.duration").firstMatch
        XCTAssertTrue(duration.waitForExistence(timeout: 5), "duration picker should exist")
        // The off-preset selection is rendered (this was blank before the fix).
        XCTAssertTrue(
            app.staticTexts["20 s"].firstMatch.waitForExistence(timeout: 2),
            "a non-preset 20 s duration should be shown in the picker"
        )

        // And it remains a real option once the menu opens, alongside the presets.
        duration.tap()
        XCTAssertTrue(app.buttons["20 s"].firstMatch.waitForExistence(timeout: 2),
                      "20 s should be a selectable option")
        XCTAssertTrue(app.buttons["30 s"].firstMatch.exists, "presets stay available")
    }

    @MainActor
    func testTransitionAndKenBurnsPersistAcrossRelaunch() throws {
        let app = XCUIApplication()
        // 1100: Ken Burns sits behind the Supporter Unlock, so this behaviour test seeds the entitlement — it is
        // about persistence, not the gate (PurchaseGateUITests owns the locked case).
        app.launchArguments = [
            "--uitest", "--uitest-slideshow", "--uitest-chrome", "--uitest-settings",
            "--uitest-reset-theme", "--uitest-entitlements=supporter"
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
            "--uitest", "--uitest-slideshow", "--uitest-chrome", "--uitest-settings",
            "--uitest-entitlements=supporter"
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
