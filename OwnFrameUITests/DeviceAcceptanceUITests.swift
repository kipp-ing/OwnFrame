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

    // MARK: - Share Sheet round trip (hitl §6, 210 T025/T061–T062, FR-210-31)

    /// Safari → Share → OwnFrame: the extension says "Open OwnFrame to start", Done closes it,
    /// and a cold OwnFrame launch picks the link up into setup (the app is unconfigured).
    @MainActor
    func testShareSheetFromSafariHandsTheLinkToAColdApp() throws {
        let app = launchFresh() // installs a fresh app, so the extension is registered
        app.terminate()

        let safari = XCUIApplication(bundleIdentifier: "com.apple.mobilesafari")
        XCUIDevice.shared.system.open(URL(string: Self.demoLink)!)
        XCTAssertTrue(safari.wait(for: .runningForeground, timeout: 20), "Safari should open the link")
        sleep(3) // let the page settle so Share shares the page URL

        let share = safari.buttons["ShareButton"]
        guard share.waitForExistence(timeout: 20) else {
            attachTree(safari, "safari-no-share-button"); XCTFail("Safari's Share button"); return
        }
        share.tap()
        let target = try ownFrameShareTarget(in: safari)
        sleep(1) // a tap on a still-coasting row only stops the scroll
        target.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.35)).tap() // the icon

        let message = safari.descendants(matching: .any)["share.confirmation.message"]
        guard message.waitForExistence(timeout: 20) else {
            attachTree(safari, "no-extension-ui"); XCTFail("the extension's confirmation"); return
        }
        assertInDeviceLanguage(message, german: "um zu starten", english: "Open OwnFrame",
                               what: "the share confirmation (FR-210-31)")
        attach(safari, "share-confirmation")
        safari.descendants(matching: .any)["share.confirmation.done"].tap()
        XCTAssertTrue(message.waitForNonExistence(timeout: 10), "Done should close the extension")

        app.launch()
        let url = app.textFields["onboarding.sharedLink.url"]
        XCTAssertTrue(url.waitForExistence(timeout: 30), "the shared link should open link setup")
        XCTAssertEqual(url.value as? String, Self.demoLink, "the shared link should be prefilled")
        attach(app, "share-picked-up")
    }

    /// OwnFrame in the share sheet: in the app row, or behind "More" on a device where it was
    /// never used before.
    @MainActor
    private func ownFrameShareTarget(in safari: XCUIApplication) throws -> XCUIElement {
        let named = NSPredicate(format: "label == 'OwnFrame'")
        let target = safari.descendants(matching: .any).matching(named).firstMatch
        let more = safari.descendants(matching: .any)
            .matching(NSPredicate(format: "label IN %@", ["More", "Mehr"])).firstMatch
        // The app row scrolls sideways; Mail sits in it on every device we test on.
        let appRow = safari.descendants(matching: .any)
            .matching(NSPredicate(format: "label IN %@", ["Mail"])).firstMatch
        XCTAssertTrue(appRow.waitForExistence(timeout: 10), "the share sheet should open")
        // Drag from where Mail first sat — inside the popover (a touch outside an iPad share
        // popover dismisses it) — 250 pt left; the point stays inside the row as it scrolls.
        let row = appRow.frame
        let origin = safari.coordinate(withNormalizedOffset: .zero)
        // On-screen by frame: `isHittable` throws for a cell scrolled out of the row.
        func visible(_ e: XCUIElement) -> Bool { e.exists && e.frame.minX >= 0 && e.frame.maxX <= safari.frame.maxX }
        for _ in 0..<10 {
            if visible(target) { return target }
            if visible(more) { break }
            origin.withOffset(CGVector(dx: row.midX, dy: row.midY))
                .press(forDuration: 0.05, thenDragTo: origin.withOffset(CGVector(dx: row.midX - 120, dy: row.midY)))
        }
        if visible(more) {
            more.tap()
            if target.waitForExistence(timeout: 10) { return target }
        }
        attachTree(safari, "share-sheet")
        throw XCTSkip("OwnFrame not found in the share sheet — see the share-sheet attachment")
    }

    @MainActor
    private func attachTree(_ app: XCUIApplication, _ name: String) {
        let tree = XCTAttachment(string: app.debugDescription)
        tree.name = name; tree.lifetime = .keepAlways; add(tree)
        attach(app, name)
    }

    // MARK: - Resilience (hitl §4 resilience smoke, §5 #80) — needs the device on a cable

    /// #80 / UNATT-13: a cold launch while offline resumes the slideshow from the cache
    /// instead of stalling on a black screen.
    @MainActor
    func testOfflineColdLaunchResumesTheSlideshow() throws {
        let app = try startDemoSlideshowAndLetItAdvance()

        goOffline(app)
        app.terminate()
        app.launch()

        let slideshow = app.descendants(matching: .any).matching(identifier: "slideshow.image").firstMatch
        XCTAssertTrue(slideshow.waitForExistence(timeout: 45),
                      "an offline cold launch should resume from the cache (#80: black screen)")
        XCTAssertFalse(app.descendants(matching: .any)["slideshow.error"].exists,
                       "cached photos exist, so no error should show")
        attach(app, "offline-cold-launch")
    }

    /// Resilience smoke: two minutes without a network keep the slideshow on screen, and it
    /// keeps advancing once the network is back.
    @MainActor
    func testTwoMinutesOfflineThenRecovers() throws {
        let app = try startDemoSlideshowAndLetItAdvance()
        let slideshow = app.descendants(matching: .any).matching(identifier: "slideshow.image").firstMatch

        goOffline(app)
        sleep(120)
        XCTAssertTrue(slideshow.exists, "the slideshow should stay on screen while offline")
        XCTAssertFalse(app.descendants(matching: .any)["slideshow.error"].exists,
                       "a network drop over cached photos should stay calm")
        attach(app, "offline-2min")

        AirplaneMode.set(false, returningTo: app)
        AirplaneMode.assertServer(Self.probeURL, reachable: true)
        for round in 1...2 {
            let before = slideshow.value as? String ?? ""
            let moved = expectation(for: NSPredicate(format: "value != %@", before), evaluatedWith: slideshow)
            wait(for: [moved], timeout: 150)
            attach(app, "online-again-\(round)")
        }
    }

    /// Resilience smoke, "add a photo server-side → appears within one refresh interval"
    /// (FR-310-06, 60 min, production value — no refresh seam). Uploads into the device-test
    /// album (`immich-test-album.sh`) while the frame plays it, then expects the new-photos card
    /// (FR-310-15, on by default and free) and the photo itself. The card is up for only 5 s, so
    /// both are polled together; the upload is deleted again however the test ends.
    @MainActor
    func testNewServerPhotoAppearsWithinOneRefresh() throws {
        let env = ProcessInfo.processInfo.environment
        guard let link = env["ARRIVAL_LINK"], let albumID = env["ARRIVAL_ALBUM"],
              let key = env["IMMICH_UPLOAD_KEY"], let url = URL(string: link),
              let server = URL(string: "\(url.scheme ?? "https")://\(url.host ?? "")") else {
            throw XCTSkip("set TEST_RUNNER_ARRIVAL_LINK / _ARRIVAL_ALBUM / _IMMICH_UPLOAD_KEY (device-accept.sh arrival)")
        }
        let app = launchFresh()
        enterLink(app, link)
        answerLocalNetworkAlertIfShown(app)
        let slideshow = app.descendants(matching: .any).matching(identifier: "slideshow.image").firstMatch
        XCTAssertTrue(slideshow.waitForExistence(timeout: long), "the test album should start the slideshow")
        attach(app, "arrival-01-before")

        let assetID = try ImmichTestUpload.uploadNewPhoto(server: server, key: key, albumID: albumID)
        addTeardownBlock { ImmichTestUpload.delete(server: server, key: key, assetID: assetID) }
        let uploaded = Date()

        let card = app.descendants(matching: .any)["slideshow.newPhotosCard"]
        var cardSeen: TimeInterval?
        var photoSeen: TimeInterval?
        // One refresh interval plus slack; then up to a few advances to reach the photo.
        let deadline = uploaded.addingTimeInterval(70 * 60)
        while Date() < deadline && (cardSeen == nil || photoSeen == nil) {
            if cardSeen == nil, card.exists {
                cardSeen = Date().timeIntervalSince(uploaded)
                attach(app, "arrival-02-card")
            }
            if photoSeen == nil, (slideshow.value as? String) == assetID {
                photoSeen = Date().timeIntervalSince(uploaded)
                attach(app, "arrival-03-photo")
            }
            Thread.sleep(forTimeInterval: 0.5)
        }
        XCTAssertNotNil(cardSeen, "the new-photos card should announce the arrival within one refresh interval")
        XCTAssertNotNil(photoSeen, "the uploaded photo should be shown after the refresh")
        print("arrival: card after \(cardSeen.map { Int($0) } ?? -1) s, photo after \(photoSeen.map { Int($0) } ?? -1) s")
    }

    /// A public host, NOT the demo server: split-horizon DNS makes that one a LAN address from
    /// inside, and the runner process has no Local Network permission — a probe of it fails
    /// even online, which would make every "offline" check pass vacuously.
    private static let probeURL = URL(string: "https://www.apple.com/library/test/success.html")!

    @MainActor
    private func startDemoSlideshowAndLetItAdvance() throws -> XCUIApplication {
        let app = launchFresh()
        enterLink(app, Self.demoLink)
        answerLocalNetworkAlertIfShown(app)
        let slideshow = app.descendants(matching: .any).matching(identifier: "slideshow.image").firstMatch
        XCTAssertTrue(slideshow.waitForExistence(timeout: long), "the demo link should start the slideshow")
        // One advance, so more than the first photo is cached before the network goes.
        let first = slideshow.value as? String ?? ""
        wait(for: [expectation(for: NSPredicate(format: "value != %@", first), evaluatedWith: slideshow)],
             timeout: 150)
        return app
    }

    /// Airplane mode on, proven by a failed probe; switched off again however the test ends —
    /// this is a person's iPad.
    @MainActor
    private func goOffline(_ app: XCUIApplication) {
        addTeardownBlock { @MainActor in AirplaneMode.set(false, returningTo: XCUIApplication()) }
        AirplaneMode.set(true, returningTo: app)
        AirplaneMode.assertServer(Self.probeURL, reachable: false)
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
        // Read back and retype: a synthesized keystroke can drop silently (Framepad 2026-09-26).
        for _ in 0..<3 {
            let old = url.value as? String ?? ""
            if !old.isEmpty, old != url.placeholderValue {
                url.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: old.count))
            }
            url.typeText(link)
            if (url.value as? String) == link { break }
        }
        XCTAssertEqual(url.value as? String, link, "the link field should hold exactly the link")
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
