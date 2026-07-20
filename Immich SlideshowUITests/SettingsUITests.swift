//
//  SettingsUITests.swift
//  Immich SlideshowUITests
//
//  Slice D — drives the settings shell: reveal chrome, open settings, confirm the
//  live brightness slider and a (disabled) planned-option row are present, adjust
//  brightness, and dismiss back to the slideshow.
//

import XCTest

final class SettingsUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
        // Never inherit a rotation leaked by an earlier test on the same simulator
        // clone — a launch during a stale landscape state positions the chrome
        // off-screen. Tests that need landscape rotate themselves (and restore).
        MainActor.assumeIsolated { XCUIDevice.shared.orientation = .portrait }
    }

    // 1100: this suite exercises the clock (Pro) and MQTT (Automation) settings rows as
    // settings behaviour, not as the gate — so every launch seeds `all`. The locked-row and
    // unlock behaviour is owned entirely by PurchaseGateUITests; seeding here keeps this suite
    // about what it was always about.
    @MainActor
    func testSettingsShowsBrightnessAndLiveDisplayOptionsAndDismisses() throws {
        let app = XCUIApplication()
        // Pin the chrome so opening settings isn't racing the idle auto-hide.
        app.launchArguments = ["--uitest", "--uitest-slideshow", "--uitest-chrome", "--uitest-entitlements=all"]
        app.launch()

        let image = app.descendants(matching: .any)
            .matching(identifier: "slideshow.image").firstMatch
        XCTAssertTrue(image.waitForExistence(timeout: 5))

        let settingsButton = app.buttons["slideshow.chrome.settings"]
        XCTAssertTrue(settingsButton.waitForExistence(timeout: 2))
        settingsButton.tap()

        // Live brightness control.
        let slider = app.sliders["settings.brightness"]
        XCTAssertTrue(slider.waitForExistence(timeout: 3), "brightness slider should appear")
        slider.adjust(toNormalizedSliderPosition: 0.4)

        // Every Display option is live now — the clock overlay was the last placeholder
        // and shipped in 510. The live Clock toggle is present.
        let clockToggle = app.switches["settings.clock"]
        XCTAssertTrue(clockToggle.waitForExistence(timeout: 2), "the Clock overlay control should be live")

        // Dismiss back to the slideshow.
        app.buttons["Done"].tap()
        XCTAssertTrue(image.waitForExistence(timeout: 3))
        let dismissed = NSPredicate(format: "isHittable == false")
        expectation(for: dismissed, evaluatedWith: slider)
        waitForExpectations(timeout: 3)
    }

    /// MQTT/broker (006) is a collapsed section; Connection (009/210, FR-210-29) is now a
    /// pushed row that opens the shared connection editor. Neither shows its fields inline,
    /// keeping the calm default (010, FR-009/010/014).
    @MainActor
    func testConnectionPushesEditorAndMqttStaysCollapsed() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--uitest", "--uitest-slideshow", "--uitest-chrome", "--uitest-entitlements=all"]
        app.launch()

        let image = app.descendants(matching: .any)
            .matching(identifier: "slideshow.image").firstMatch
        XCTAssertTrue(image.waitForExistence(timeout: 5))

        let settingsButton = app.buttons["slideshow.chrome.settings"]
        XCTAssertTrue(settingsButton.waitForExistence(timeout: 2))
        settingsButton.tap()

        // Both rows are present (scrolled into view — they sit below the brightness/display
        // sections), and neither renders its fields inline.
        let connection = app.descendants(matching: .any)
            .matching(identifier: "settings.connection").firstMatch
        XCTAssertTrue(scrollToElement(connection, in: app), "Connection row should be present")
        let mqtt = app.descendants(matching: .any)
            .matching(identifier: "settings.mqtt").firstMatch
        XCTAssertTrue(scrollToElement(mqtt, in: app), "MQTT section should be present")
        XCTAssertFalse(app.textFields["connection.url"].exists, "Connection fields hidden until the editor is opened")
        XCTAssertFalse(app.textFields["broker.host"].exists, "MQTT fields hidden until expanded")

        // Tapping Connection pushes the shared editor, revealing its fields.
        connection.tap()
        XCTAssertTrue(app.textFields["connection.url"].waitForExistence(timeout: 3),
                      "tapping Connection should push the shared connection editor")
        XCTAssertTrue(app.buttons["connection.save"].exists, "the pushed editor shows Save")
    }

    /// The settings form must scroll so every section — including the folded-in
    /// Connection and MQTT at the bottom — is reachable in both orientations (010/US3,
    /// FR-015/FR-016).
    @MainActor
    func testBottomSettingsSectionReachableInBothOrientations() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--uitest", "--uitest-slideshow", "--uitest-chrome", "--uitest-entitlements=all"]
        app.launch()
        defer { XCUIDevice.shared.orientation = .portrait }

        let image = app.descendants(matching: .any)
            .matching(identifier: "slideshow.image").firstMatch
        XCTAssertTrue(image.waitForExistence(timeout: 5))
        let settingsButton = app.buttons["slideshow.chrome.settings"]
        XCTAssertTrue(settingsButton.waitForExistence(timeout: 2))
        settingsButton.tap()

        // Portrait: the bottom-most section (MQTT) scrolls into view.
        MainActor.assumeIsolated { XCUIDevice.shared.orientation = .portrait }
        let mqtt = app.descendants(matching: .any).matching(identifier: "settings.mqtt").firstMatch
        XCTAssertTrue(scrollToElement(mqtt, in: app), "MQTT section reachable in portrait")

        // Landscape: still reachable after rotating (the form keeps scrolling).
        XCUIDevice.shared.orientation = .landscapeLeft
        XCTAssertTrue(scrollToElement(mqtt, in: app), "MQTT section reachable in landscape")
    }

    /// Reset moved from the chrome's exit button into Settings (300/FR-300-28) — a wall-mounted
    /// photo frame has no real "exit," so the destructive action now lives as an explicit row
    /// here instead.
    @MainActor
    func testResetFromSettingsReturnsToOnboarding() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--uitest", "--uitest-slideshow", "--uitest-chrome", "--uitest-entitlements=all"]
        app.launch()

        let image = app.descendants(matching: .any)
            .matching(identifier: "slideshow.image").firstMatch
        XCTAssertTrue(image.waitForExistence(timeout: 5))

        let settingsButton = app.buttons["slideshow.chrome.settings"]
        XCTAssertTrue(settingsButton.waitForExistence(timeout: 2))
        settingsButton.tap()

        let resetButton = app.buttons["settings.reset"]
        XCTAssertTrue(scrollToElement(resetButton, in: app), "Reset row should be present")
        resetButton.tap()

        // On iPad the confirmation renders as a popover with no separate Cancel button
        // (tapping outside it is the implicit cancel) — confirming is what matters here.
        let confirm = app.buttons["Reset"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 2), "confirmation dialog should offer Reset")
        confirm.tap()

        XCTAssertTrue(app.staticTexts["onboarding.connection.description"].waitForExistence(timeout: 5),
                      "reset should return to the combined connection step")
    }

    /// Swipes up until the element exists (or the swipe budget is exhausted).
    @MainActor
    private func scrollToElement(_ element: XCUIElement, in app: XCUIApplication, maxSwipes: Int = 8) -> Bool {
        if element.waitForExistence(timeout: 3) { return true }
        var swipes = 0
        while !element.exists && swipes < maxSwipes {
            app.swipeUp()
            swipes += 1
        }
        return element.exists
    }
}
