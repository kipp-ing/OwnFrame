//
//  BrokerSetupUITests.swift
//  Immich SlideshowUITests
//
//  Broker (MQTT) setup is folded into the Settings screen as a collapsible section
//  (010, US2). `--uitest-broker` opens Settings with the MQTT section pre-expanded.
//  The existing data shows so it can be changed or removed, without ever prefilling
//  the password in cleartext. Driven hermetically via an in-memory broker store
//  seeded by `--uitest-broker-existing`.
//

import XCTest

final class BrokerSetupUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
        // Never inherit a rotation leaked by an earlier test on the same simulator
        // clone — a launch during a stale landscape state positions the chrome
        // off-screen. Tests that need landscape rotate themselves (and restore).
        MainActor.assumeIsolated { XCUIDevice.shared.orientation = .portrait }
    }

    @MainActor
    func testExistingBrokerPrefillsFieldsMasksPasswordAndRemoves() throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "--uitest", "--uitest-slideshow", "--uitest-chrome", "--uitest-entitlements=automation",
            "--uitest-broker", "--uitest-broker-existing",
        ]
        app.launch()

        // The MQTT section sits at the bottom of the settings form, which lazily
        // renders rows — so each field is scrolled into view before it is read (this
        // also exercises the section's reachability, US3/FR-015).
        let host = app.textFields["broker.host"]
        XCTAssertTrue(scrollToElement(host, in: app), "broker fields should be reachable in the MQTT section")

        // Host / port / username are prefilled from the stored broker so the user can
        // edit them (FR-013 change flow). The form lazily drops off-screen rows, so each
        // field is scrolled into view before it is read — the MQTT section is now long
        // enough that port/username can start below the fold on first render.
        XCTAssertEqual(host.value as? String, "mqtt.example.com")
        let port = app.textFields["broker.port"]
        XCTAssertTrue(scrollToElement(port, in: app), "port field should be reachable in the MQTT section")
        XCTAssertEqual(port.value as? String, "8883")
        let username = app.textFields["broker.username"]
        XCTAssertTrue(scrollToElement(username, in: app), "username field should be reachable in the MQTT section")
        XCTAssertEqual(username.value as? String, "ha-user")

        // The stored password is never prefilled in cleartext; a "set" hint stands in
        // for it instead (FR-013).
        let password = app.textFields["broker.password"]
        XCTAssertTrue(scrollToElement(password, in: app), "password field should be reachable")
        XCTAssertNotEqual(password.value as? String, "secret-pass", "password must not be prefilled")
        // Scroll the hint into view before asserting: the form lazily drops off-screen
        // rows, so the hint just below the password field needs to be rendered first.
        let passwordHint = app.staticTexts["broker.passwordHint"]
        XCTAssertTrue(scrollToElement(passwordHint, in: app), "a 'password is set' hint should replace cleartext prefill")

        // Remove clears the stored config; the inline form resets to a pristine state
        // (FR-013) — the remove action and the "set" hint disappear and the host clears.
        let remove = app.buttons["broker.remove"]
        XCTAssertTrue(scrollToElement(remove, in: app), "existing broker data should offer a remove action")
        remove.tap()

        let gone = NSPredicate(format: "exists == false")
        expectation(for: gone, evaluatedWith: remove)
        waitForExpectations(timeout: 3)
        XCTAssertFalse(passwordHint.exists, "the 'password is set' hint should disappear after removal")
        XCTAssertNotEqual(host.value as? String, "mqtt.example.com", "host should be cleared after removal")
    }

    @MainActor
    func testTypedBrokerInputSurvivesCollapseAndReExpand() throws {
        let app = XCUIApplication()
        // No `--uitest-broker-existing`: the MQTT section starts empty and pre-expanded.
        app.launchArguments = ["--uitest", "--uitest-slideshow", "--uitest-chrome", "--uitest-broker", "--uitest-entitlements=automation"]
        app.launch()

        let host = app.textFields["broker.host"]
        XCTAssertTrue(scrollToElement(host, in: app), "broker host field should be reachable")
        host.tap()
        host.typeText("edited-host.example.com")

        // Collapse then re-expand the MQTT section via its disclosure header.
        let mqttHeader = app.descendants(matching: .any).matching(identifier: "settings.mqtt").firstMatch
        XCTAssertTrue(mqttHeader.waitForExistence(timeout: 2))
        mqttHeader.tap() // collapse
        XCTAssertTrue(scrollToElement(mqttHeader, in: app))
        mqttHeader.tap() // re-expand

        // The typed-but-unsaved edit survives (the view model is owned by the settings
        // screen, not recreated with the disclosure content — 010 edge case / G2).
        let hostAfter = app.textFields["broker.host"]
        XCTAssertTrue(scrollToElement(hostAfter, in: app))
        XCTAssertEqual(hostAfter.value as? String, "edited-host.example.com")
    }

    @MainActor
    func testImagePublishTogglePersistsAcrossRelaunch() throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "--uitest", "--uitest-slideshow", "--uitest-chrome", "--uitest-entitlements=automation",
            "--uitest-broker", "--uitest-reset-publish-options",
        ]
        app.launch()

        // The image-publish toggle sits at the bottom of the MQTT section.
        let toggle = app.switches["broker.imageEnabled"]
        XCTAssertTrue(scrollToElement(toggle, in: app), "image-publish toggle should be reachable in the MQTT section")
        XCTAssertEqual(toggle.value as? String, "0", "image publishing must be off by default (FR-710-15)")

        // Ensure the switch is fully on-screen (it's the last row) before tapping.
        var tries = 0
        while !toggle.isHittable && tries < 4 { app.swipeUp(); tries += 1 }
        // Center-tapping a Form Toggle can land on its (long) label; tap the trailing
        // edge where the switch control sits. Then wait for the value to flip —
        // SwiftUI reflects the @State change asynchronously.
        toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.5)).tap()
        let isOn = NSPredicate(format: "value == %@", "1")
        expectation(for: isOn, evaluatedWith: toggle)
        waitForExpectations(timeout: 3)

        // Relaunch WITHOUT the reset arg — the persisted preference should survive.
        app.terminate()
        app.launchArguments = ["--uitest", "--uitest-slideshow", "--uitest-chrome", "--uitest-broker", "--uitest-entitlements=automation"]
        app.launch()

        let toggleAfter = app.switches["broker.imageEnabled"]
        XCTAssertTrue(scrollToElement(toggleAfter, in: app), "toggle should be reachable after relaunch")
        XCTAssertEqual(toggleAfter.value as? String, "1", "the image-publish toggle should persist across relaunch")
    }

    /// Swipes up until the element exists (or the swipe budget is exhausted). The
    /// folded-in MQTT section is below the fold of the settings form.
    @MainActor
    private func scrollToElement(_ element: XCUIElement, in app: XCUIApplication, maxSwipes: Int = 8) -> Bool {
        if element.waitForExistence(timeout: 5) { return true }
        var swipes = 0
        while !element.exists && swipes < maxSwipes {
            app.swipeUp()
            swipes += 1
        }
        return element.exists
    }
}
