//
//  DeviceRigConfigUITests.swift
//  OwnFrameUITests
//
//  Device test rig (1100 / T056) — configures a REAL frame against REAL infrastructure.
//
//  Everything else in this target is hermetic: it launches with `--uitest`, which swaps in
//  in-memory stores, a stub Immich API, and — critically — `makeCoordinator: { _ in nil }`,
//  i.e. no MQTT broker in the process at all. That makes the hermetic suite structurally
//  incapable of exercising the HA gating contract (FR-1100-03a), which is the one thing a
//  physical frame can prove and a simulator cannot.
//
//  So this file does the opposite: it launches with NO launch arguments, i.e. the production
//  path — real network, real Keychain, real broker, real (unpurchased ⇒ unentitled) StoreKit
//  entitlements. That last part is why T056 needs no seam: a frame that never bought anything
//  IS the gated case.
//
//  OPT-IN ONLY. It touches Jan's live broker and rewrites the frame's stored configuration, so
//  it is skipped unless `DEVICE_RIG=1`, and a normal suite run never sees it. Invoke as:
//
//      TEST_RUNNER_DEVICE_RIG=1 TEST_RUNNER_MQTT_PASSWORD=… \
//      xcodebuild test-without-building -only-testing:"…/DeviceRigConfigUITests" …
//
//  `xcodebuild` forwards `TEST_RUNNER_*` into the runner with the prefix stripped. The broker
//  password is read from that environment and never appears in this file — Konstitution III.
//

import XCTest

final class DeviceRigConfigUITests: XCTestCase {

    /// The password-free demo shared link. Safe to hard-code: it is the public review/demo link,
    /// not a secret.
    private static let demoLink = "https://bilder.kippings.de/s/Iceland2021"

    private static let brokerHost = "home.kippings.de"
    private static let brokerPort = "8883"
    private static let brokerUser = "car"

    /// Generous throughout: this is a 2017 iPad Pro on iOS 17.7.10 fetching real photos over the
    /// real network. Simulator-calibrated timeouts produce flakes that look like product bugs.
    private let long: TimeInterval = 90

    override func setUpWithError() throws {
        continueAfterFailure = false
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["DEVICE_RIG"] == "1",
            "Device rig only — set TEST_RUNNER_DEVICE_RIG=1. Skipped so the normal suite never "
                + "touches the live broker."
        )
        MainActor.assumeIsolated { XCUIDevice.shared.orientation = .portrait }
    }

    /// One ordered flow rather than two tests: XCTest orders by name, and the broker step
    /// requires the source step to have completed, so splitting them would encode ordering in
    /// alphabetical luck.
    @MainActor
    func testConfigureFrameWithSharedLinkAndBroker() throws {
        let app = XCUIApplication()
        app.launchArguments = [] // production path — see the file comment
        app.launch()

        attach(app, "01-launch")

        try configureSharedLinkSourceIfNeeded(app)
        attach(app, "02-slideshow")

        try openSettings(app)
        attach(app, "03-settings")

        try configureBroker(app)
        attach(app, "04-broker-saved")
    }

    /// T056 — hold the configured, unentitled frame in the foreground long enough for the HA
    /// coordinator to connect and announce.
    ///
    /// A `devicectl process launch` is not sufficient: with the screen asleep the app never
    /// reaches the foreground, and MQTT never connects (the same foreground-only constraint that
    /// governs brightness and the idle timer). Running under XCUITest guarantees a foreground,
    /// non-suspended app for the whole window.
    ///
    /// This asserts nothing about MQTT itself — the contract lives on the broker and in Home
    /// Assistant, which are checked externally with `mosquitto_sub`/`hactl`. Asserting it from
    /// inside the app would only re-test the app's own belief about what it published.
    @MainActor
    func testHoldForegroundSoCoordinatorAnnounces() throws {
        let app = XCUIApplication()
        app.launchArguments = [] // production ⇒ unentitled ⇒ .telemetryOnly
        app.launch()

        let slideshow = app.descendants(matching: .any)
            .matching(identifier: "slideshow.image").firstMatch
        XCTAssertTrue(slideshow.waitForExistence(timeout: long),
                      "a configured frame should boot straight into the slideshow")
        attach(app, "t056-01-slideshow")

        // Long enough to cover TLS handshake + connect + announce on a 2017 iPad, with slack.
        Thread.sleep(forTimeInterval: 120)
        attach(app, "t056-02-after-hold")
    }

    /// Diagnostic: the frame will not connect and this device yields no logs (`os.Logger` output
    /// cannot be streamed off it), so the app's own UI is the only available instrument. Holds
    /// the foreground, then opens Settings and captures the MQTT section — `broker.validation`
    /// renders the connection/auth error if there is one.
    @MainActor
    func testDiagnoseBrokerConnectionState() throws {
        let app = XCUIApplication()
        app.launchArguments = []
        app.launch()

        let slideshow = app.descendants(matching: .any)
            .matching(identifier: "slideshow.image").firstMatch
        XCTAssertTrue(slideshow.waitForExistence(timeout: long))

        Thread.sleep(forTimeInterval: 45) // give the coordinator time to try

        try openSettings(app)
        // Walk down to the MQTT block, capturing as we go — the validation text may sit anywhere
        // in that section depending on how it wrapped.
        for i in 0..<6 {
            attach(app, "diag-scroll-\(i)")
            app.swipeUp()
        }
        attach(app, "diag-final")

        let validation = app.staticTexts["broker.validation"]
        if validation.exists {
            XCTFail("broker.validation says: \(validation.label)") // surfaces the text in the log
        }
    }

    // MARK: - Steps

    /// Drives first-run onboarding to the demo link. Tolerates an already-configured frame so the
    /// rig is re-runnable: a rig you can only run against a pristine device is a rig you will
    /// stop using.
    @MainActor
    private func configureSharedLinkSourceIfNeeded(_ app: XCUIApplication) throws {
        let slideshow = app.descendants(matching: .any)
            .matching(identifier: "slideshow.image").firstMatch
        let choice = app.buttons["onboarding.choice.sharedLink"]

        // Whichever appears first decides the branch: a configured frame boots straight into the
        // slideshow, a blank one into the choice screen.
        let start = Date()
        while Date().timeIntervalSince(start) < long {
            if slideshow.exists { return }        // already configured
            if choice.exists { break }
            usleep(500_000)
        }

        XCTAssertTrue(choice.waitForExistence(timeout: 10),
                      "expected either a running slideshow or the first-run choice screen")
        choice.tap()

        let url = app.textFields["onboarding.sharedLink.url"]
        XCTAssertTrue(url.waitForExistence(timeout: 15), "shared-link URL field should appear")
        url.tap()
        url.typeText(Self.demoLink)
        attach(app, "01b-link-entered")

        app.buttons["onboarding.sharedLink.start"].tap()

        // The demo link is password-free; if that ever changes this assert is the early warning.
        XCTAssertFalse(app.textFields["onboarding.sharedLink.password"].waitForExistence(timeout: 5),
                       "the demo link is expected to be password-free")

        XCTAssertTrue(slideshow.waitForExistence(timeout: long),
                      "the demo link should resolve and start the slideshow")
    }

    @MainActor
    private func openSettings(_ app: XCUIApplication) throws {
        let settings = app.buttons["slideshow.chrome.settings"]
        if !settings.isHittable {
            // Chrome is hidden by default; a tap on the photo reveals it.
            app.descendants(matching: .any).matching(identifier: "slideshow.image")
                .firstMatch.tap()
        }
        XCTAssertTrue(settings.waitForExistence(timeout: 15) && settings.isHittable,
                      "tapping the photo should reveal the chrome settings button")
        settings.tap()
    }

    /// Fills the broker editor. Reachable while unentitled by design: the 1100 amendment made HA
    /// telemetry free, so the editor is live and only *control* sits behind the Automation
    /// unlock (the old fully-masked LockedBrokerView was deleted).
    @MainActor
    private func configureBroker(_ app: XCUIApplication) throws {
        let password = try XCTUnwrap(
            ProcessInfo.processInfo.environment["MQTT_PASSWORD"],
            "set TEST_RUNNER_MQTT_PASSWORD — the rig never hard-codes the broker password"
        )

        // No navigation row to tap: in the unentitled path the broker editor is rendered INLINE
        // in the settings form (the DisclosureGroup was removed because an always-present
        // collapsed one starved a sibling Section's async `.task`). So the fields are already on
        // this screen — just below the fold on a 10.5" display.
        set(app, "broker.host", to: Self.brokerHost)
        set(app, "broker.port", to: Self.brokerPort)
        set(app, "broker.username", to: Self.brokerUser)
        set(app, "broker.password", to: password, secure: true)

        let save = app.buttons["broker.save"]
        XCTAssertTrue(save.waitForExistence(timeout: 10), "broker editor should offer Save")
        save.tap()
    }

    // MARK: - Helpers

    /// Clears and retypes a field. Clearing matters on a re-run: the frame may already hold a
    /// previous value, and `typeText` appends.
    @MainActor
    private func set(_ app: XCUIApplication, _ identifier: String, to value: String, secure: Bool = false) {
        let field = secure
            ? app.secureTextFields[identifier].exists
                ? app.secureTextFields[identifier] : app.textFields[identifier]
            : app.textFields[identifier].exists
                ? app.textFields[identifier] : app.secureTextFields[identifier]

        XCTAssertTrue(field.waitForExistence(timeout: 15), "\(identifier) should exist")

        // The inline MQTT section sits below the fold on a 10.5" screen, and the keyboard covers
        // more of it with each field. `exists` is true for off-screen elements but `tap()` on a
        // non-hittable one fails, so scroll it into view first.
        var swipes = 0
        while !field.isHittable && swipes < 8 {
            app.swipeUp()
            swipes += 1
        }
        XCTAssertTrue(field.isHittable, "\(identifier) should be reachable after scrolling")
        field.tap()

        if let existing = field.value as? String, !existing.isEmpty, !existing.hasPrefix("•") {
            field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: existing.count))
        }
        field.typeText(value)
    }

    /// Screenshots are the ONLY way to observe this device — there is no devicectl screenshot and
    /// no log streaming off it — so every step attaches one, kept even on success.
    @MainActor
    private func attach(_ app: XCUIApplication, _ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }
}
