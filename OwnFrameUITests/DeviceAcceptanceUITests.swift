//
//  DeviceAcceptanceUITests.swift
//  OwnFrameUITests
//
//  Device acceptance (220 Phase 7, T022/T023) — the automatable half of the manual device
//  checklist, run on a REAL iPad against the REAL system: real permission alerts, real
//  network, the real demo link. Like `DeviceRigConfigUITests` it launches with NO launch
//  arguments (the production path), so nothing here is faked.
//
//  Every test expects a FRESH install — camera and Local Network permission undetermined, no
//  source configured. `.claude/scripts/device-accept.sh` uninstalls the app before each single
//  test; running the class any other way gives meaningless results, so it is skipped unless
//  `DEVICE_ACCEPT=1`:
//
//      .claude/scripts/device-accept.sh <device-udid> [test-name…]
//
//  This is the first class in the suite that answers SpringBoard alerts. Permission alerts
//  put "Don't Allow" first and the allowing button ("Allow"/"OK") second on every iOS we
//  support, so buttons are picked by position, not by (localized) label.
//

import XCTest

final class DeviceAcceptanceUITests: XCTestCase {

    /// The password-free demo shared link (public review link, not a secret).
    private static let demoLink = "https://bilder.kippings.de/s/Iceland2021"

    /// Real device, real network: simulator-calibrated timeouts produce fake product bugs.
    private let long: TimeInterval = 90

    @MainActor
    private var springboard: XCUIApplication { XCUIApplication(bundleIdentifier: "com.apple.springboard") }

    /// The language the SYSTEM alerts should use. The scheme runs tests in English, so the
    /// runner can't see that the device itself is German — `EXPECT_LANG` (set by the script)
    /// says so; the runner's own language is only the fallback.
    private var deviceIsGerman: Bool {
        let set = ProcessInfo.processInfo.environment["EXPECT_LANG"].flatMap { $0.isEmpty ? nil : $0 }
        let expected = set ?? Locale.preferredLanguages.first ?? ""
        return expected.hasPrefix("de")
    }

    override func setUpWithError() throws {
        continueAfterFailure = false
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["DEVICE_ACCEPT"] == "1",
            "Device acceptance only — run via .claude/scripts/device-accept.sh, which "
                + "reinstalls the app before every test."
        )
        MainActor.assumeIsolated { XCUIDevice.shared.orientation = .portrait }
    }

    // MARK: - T022 camera permission → live scanner (#82, #81, SC-220-02/05)

    @MainActor
    func testCameraAllowedScannerStaysUsableAndCancelReturns() throws {
        let app = launchFresh()
        openScanner(app)

        let alert = try systemAlert("camera permission")
        assertInDeviceLanguage(alert, german: "nutzt die Kamera nur", english: "uses the camera only",
                               what: "NSCameraUsageDescription (#81)")
        alert.buttons.element(boundBy: 1).tap() // allow
        attach(app, "02-camera-allowed")

        // #82: the screen went black and hung right after this tap. A live scanner keeps its
        // Cancel control, shows no fallback, and Cancel actually returns.
        let cancel = app.buttons["onboarding.sharedLink.scan.cancel"]
        XCTAssertTrue(cancel.waitForExistence(timeout: 15), "the scanner should stay on screen")
        XCTAssertFalse(app.staticTexts["onboarding.sharedLink.scan.unavailable"].exists,
                       "camera was allowed, so the denied fallback must not show")
        sleep(3) // let the preview run; the screenshot is the eyeball check for a black preview
        attach(app, "03-scanner-live")
        cancel.tap()
        XCTAssertTrue(app.textFields["onboarding.sharedLink.url"].waitForExistence(timeout: 10),
                      "Cancel should return to the link field — the #82 hang never came back")
    }

    @MainActor
    func testCameraDeniedShowsCalmFallback() throws {
        let app = launchFresh()
        openScanner(app)

        let alert = try systemAlert("camera permission")
        alert.buttons.element(boundBy: 0).tap() // don't allow

        XCTAssertTrue(app.staticTexts["onboarding.sharedLink.scan.unavailable"].waitForExistence(timeout: 15),
                      "a denied camera should show the paste-the-link fallback (SC-220-05)")
        attach(app, "03-camera-denied")
        app.buttons["onboarding.sharedLink.scan.cancel"].tap()
        XCTAssertTrue(app.textFields["onboarding.sharedLink.url"].waitForExistence(timeout: 10),
                      "Done should return to the link field")
    }

    // MARK: - T023 fresh install → Immich link → running slideshow

    @MainActor
    func testFreshInstallDemoLinkReachesRunningSlideshow() throws {
        let app = launchFresh()
        enterLink(app, Self.demoLink)
        answerLocalNetworkAlertIfShown(app)

        let slideshow = app.descendants(matching: .any).matching(identifier: "slideshow.image").firstMatch
        XCTAssertTrue(slideshow.waitForExistence(timeout: long), "the demo link should start the slideshow")
        attach(app, "04-slideshow")

        // Running, not just rendered: the asset id in `value` moves on.
        let first = slideshow.value as? String ?? ""
        let advanced = expectation(for: NSPredicate(format: "value != %@", first), evaluatedWith: slideshow)
        wait(for: [advanced], timeout: 150)
    }

    @MainActor
    func testFreshInstallProtectedLinkRejectsWrongPasswordThenStarts() throws {
        let env = ProcessInfo.processInfo.environment
        guard let link = env["PROTECTED_LINK"], let password = env["PROTECTED_PASSWORD"] else {
            throw XCTSkip("set TEST_RUNNER_PROTECTED_LINK and TEST_RUNNER_PROTECTED_PASSWORD")
        }
        let app = launchFresh()
        enterLink(app, link)
        answerLocalNetworkAlertIfShown(app)

        try typeIntoPasswordField(app, "definitely-not-the-password")
        app.releaseKeyboardFocus() // #75
        app.buttons["onboarding.sharedLink.password.continue"].tap()
        XCTAssertTrue(app.descendants(matching: .any)["onboarding.sharedLink.password.error"]
                        .waitForExistence(timeout: 30),
                      "a wrong password should surface the distinct error")
        attach(app, "05-wrong-password")

        try typeIntoPasswordField(app, password)
        app.releaseKeyboardFocus() // #75
        app.buttons["onboarding.sharedLink.password.continue"].tap()
        let slideshow = app.descendants(matching: .any).matching(identifier: "slideshow.image").firstMatch
        XCTAssertTrue(slideshow.waitForExistence(timeout: long), "the right password should start the slideshow")
        attach(app, "06-protected-slideshow")
    }

    // MARK: - Helpers

    @MainActor
    private func launchFresh() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [] // production path — see the file comment
        app.launch()
        XCTAssertTrue(app.buttons["onboarding.choice.sharedLink"].waitForExistence(timeout: long),
                      "a fresh install should open on the welcome screen — did the script reinstall?")
        attach(app, "01-welcome")
        return app
    }

    @MainActor
    private func openScanner(_ app: XCUIApplication) {
        app.buttons["onboarding.choice.sharedLink"].tap()
        let scan = app.buttons["onboarding.sharedLink.scan"]
        XCTAssertTrue(scan.waitForExistence(timeout: 15), "Scan QR should be offered")
        scan.tap()
    }

    @MainActor
    private func enterLink(_ app: XCUIApplication, _ link: String) {
        app.buttons["onboarding.choice.sharedLink"].tap()
        let url = app.textFields["onboarding.sharedLink.url"]
        XCTAssertTrue(url.waitForExistence(timeout: 15), "the link field should appear")
        url.tap()
        url.typeText(link)
        app.releaseKeyboardFocus() // #75
        app.buttons["onboarding.sharedLink.start"].tap()
    }

    /// The first request to a LAN server (split-horizon DNS makes the demo host one from inside)
    /// raises the Local Network alert on a fresh install. It must be answered, and its text is
    /// checked like the camera text: a German device gets German.
    @MainActor
    private func answerLocalNetworkAlertIfShown(_ app: XCUIApplication) {
        let alert = springboard.alerts.firstMatch
        guard alert.waitForExistence(timeout: 15) else { return } // not on the LAN: no alert
        attach(springboard, "local-network-alert")
        assertInDeviceLanguage(alert, german: "Fotoserver", english: "photo server",
                               what: "NSLocalNetworkUsageDescription")
        alert.buttons.element(boundBy: 1).tap() // allow
    }

    @MainActor
    private func systemAlert(_ what: String) throws -> XCUIElement {
        let alert = springboard.alerts.firstMatch
        XCTAssertTrue(alert.waitForExistence(timeout: 15), "iOS should ask for \(what)")
        attach(springboard, "\(what) alert")
        return alert
    }

    /// Checks the alert's whole text for a distinctive phrase of the expected language.
    @MainActor
    private func assertInDeviceLanguage(_ alert: XCUIElement, german: String, english: String, what: String) {
        // One snapshot, not element-by-element queries: the alert can re-layout mid-read.
        func labels(_ node: XCUIElementSnapshot) -> [String] {
            [node.label] + node.children.flatMap(labels)
        }
        let text = ((try? alert.snapshot()).map(labels) ?? [alert.label]).joined(separator: " ")
        let expected = deviceIsGerman ? german : english
        XCTAssertTrue(text.localizedCaseInsensitiveContains(expected),
                      "\(what) should be in the device language (expected “\(expected)”), got: \(text)")
    }

    @MainActor
    private func typeIntoPasswordField(_ app: XCUIApplication, _ text: String) throws {
        let secure = app.secureTextFields["onboarding.sharedLink.password"]
        let plain = app.textFields["onboarding.sharedLink.password"]
        let field = secure.waitForExistence(timeout: 30) ? secure : plain
        XCTAssertTrue(field.waitForExistence(timeout: 5), "the protected link should ask for a password")
        field.tap()
        if let old = field.value as? String, !old.isEmpty, old != field.placeholderValue {
            field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: old.count))
        }
        field.typeText(text)
    }

    /// Screenshots are the only way to see a device's screen afterwards — kept even on success.
    @MainActor
    private func attach(_ app: XCUIApplication, _ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }
}
