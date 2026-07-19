//
//  PurchaseGateUITests.swift
//  Immich SlideshowUITests
//
//  1100 / T020 — the purchase gate's UI surface, driven hermetically through the
//  `--uitest-entitlements=` seam (contracts/uitest-seams.md). StoreKit is never reached.
//
//  Covers the contract's binding assertions:
//    1. `none`: the three locked rows exist, are HITTABLE (FR-1100-09 — dimmed-but-tappable
//       is the whole point; a merely-existing dimmed row reads as disabled and is never
//       tapped), and each opens its tier's unlock screen.
//    2. `none` + sustained stub playback across ≥ 3 photo advances: no `unlock.`-prefixed
//       element ever appears unprompted (SC-1100-02's hermetic proxy — the ≥ 4 h wall-clock
//       run stays a device-day item).
//    4. `all`: the locked rows are ABSENT. This is the anti-vacuous guard — without it the
//       whole suite would pass by simply never adding the identifiers.
//  Plus the SC-1100-01 onboarding leg: a free-tier shared-link onboarding completes to a
//  running slideshow with zero purchase UI at every step.
//
//  Assertions 3, 5 and 6 (part-ownership visibility, store-unavailable, pre-gate broker
//  config) are separate files; assertion 7 is explicitly not XCUITest.
//

import XCTest

final class PurchaseGateUITests: XCTestCase {

    // MARK: - Timing (all derived, nothing hardcoded as a blind sleep)

    /// Photo duration seeded into the hermetic theme store for the playback window. This is
    /// `ThemeSettings.durationRange.lowerBound` (3 s) — the fastest legal advance, so the
    /// window stays short while still exercising real timer-driven advances.
    private static let stubPhotoSeconds: TimeInterval = 3

    /// SC-1100-02 proxy: the window must span at least this many real photo advances.
    private static let requiredAdvances = 3

    /// Slack on top of `requiredAdvances × stubPhotoSeconds` to absorb launch, decode and
    /// the cost of the accessibility queries the poll loop makes. The loop exits as soon as
    /// the advance quota is met, so this is a ceiling, not a duration.
    private static let windowSlackSeconds: TimeInterval = 15

    /// Poll cadence. Short enough that a purchase sheet flashing between two advances would
    /// still be caught, long enough not to spin the runner.
    private static let pollMicroseconds: UInt32 = 300_000

    override func setUpWithError() throws {
        continueAfterFailure = false
        // Never inherit a rotation leaked by an earlier test on the same simulator clone —
        // a launch during a stale landscape state positions the chrome off-screen.
        MainActor.assumeIsolated { XCUIDevice.shared.orientation = .portrait }
    }

    // MARK: - Assertion 1 — locked rows are visible AND tappable (FR-1100-09)

    /// The free frame still shows every gated feature, in a locked state that a finger can
    /// actually reach. `isHittable`, not `exists`: FR-1100-09 exists precisely because a
    /// plainly dimmed iOS row reads as disabled and nobody taps it.
    @MainActor
    func testLockedRowsAreVisibleAndHittableWithNoEntitlements() throws {
        let app = launchIntoSettings(entitlements: "none")

        // Checked top-down, because each lookup scrolls and the broker banner sits below
        // the display rows.
        for identifier in Self.lockedRowIdentifiers {
            let row = element(app, identifier)
            XCTAssertTrue(scrollToElement(row, in: app),
                          "\(identifier) must be present in settings on the free tier (FR-1100-09)")
            XCTAssertTrue(row.isHittable,
                          "\(identifier) must be tappable, not merely dimmed (FR-1100-09)")
        }
    }

    /// The second half of assertion 1: a locked row is an entry point, not a dead end. Each
    /// row leads to the single unlock screen for its tier — Ken Burns and the clock are Pro
    /// (the launch ambience composition), the broker is Automation.
    @MainActor
    func testTappingALockedRowOpensItsTierUnlockScreen() throws {
        // The two Pro rows open the Pro unlock screen directly.
        let proRows = ["settings.row.kenburns.locked", "settings.row.clock.locked"]

        // A fresh launch per row: no navigation state carried between routes, so a failure
        // names exactly one row.
        for rowID in proRows {
            let app = launchIntoSettings(entitlements: "none")
            let row = element(app, rowID)
            XCTAssertTrue(scrollToElement(row, in: app), "\(rowID) must be present to be tapped")
            row.tap()
            XCTAssertTrue(element(app, "unlock.screen.pro").waitForExistence(timeout: 5),
                          "tapping \(rowID) must open unlock.screen.pro (FR-1100-09)")
            app.terminate()
        }

        // The broker row is different by design (US5): it opens the locked broker view first —
        // where an existing frame's owner sees their saved config — and the unlock offer THERE
        // reaches the Automation screen. So the path is row → locked broker view → unlock screen.
        let app = launchIntoSettings(entitlements: "none")
        let brokerRow = element(app, "settings.row.broker.locked")
        XCTAssertTrue(scrollToElement(brokerRow, in: app), "broker locked row must be present")
        brokerRow.tap()
        // The locked broker view re-uses the same banner identifier; its unlock button leads on.
        let unlockEntry = element(app, "unlock.buy.automation.entry")
        XCTAssertTrue(unlockEntry.waitForExistence(timeout: 5),
                      "broker locked row must open the locked broker view with an unlock offer")
        unlockEntry.tap()
        XCTAssertTrue(element(app, "unlock.screen.automation").waitForExistence(timeout: 5),
                      "the locked broker view's unlock offer must open unlock.screen.automation")
    }

    // MARK: - Assertion 6 — pre-gate broker config degrades gracefully (US5 / SC-1100-06)

    /// A frame configured before the gate keeps its broker settings. Opening the (locked) broker
    /// surface unentitled shows the stored values, masks the password as usual, carries a locked
    /// banner, and clears nothing (FR-1100-14). The no-connection half is a device-day check.
    @MainActor
    func testSeededBrokerConfigIsVisibleAndLockedWhenUnentitled() throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "--uitest", "--uitest-slideshow", "--uitest-chrome", "--uitest-settings",
            "--uitest-broker", "--uitest-broker-existing", "--uitest-entitlements=none",
        ]
        app.launch()

        let brokerRow = element(app, "settings.row.broker.locked")
        XCTAssertTrue(scrollToElement(brokerRow, in: app),
                      "the MQTT row is locked when Automation is not owned")
        brokerRow.tap()

        // Stored config is visible — "not an empty or reset screen" (US5 scenario 2). Scroll it
        // into view first: a lazy Form row reports exists==true while off-screen but only
        // realises its accessibility value once rendered (the entitled broker tests do the same).
        // The combined row exposes "Host: mqtt.example.com" as its label (its `.value` is an
        // empty string, so read the label, not value ?? label — an empty string isn't nil).
        let host = element(app, "broker.host")
        XCTAssertTrue(scrollToElement(host, in: app), "the saved broker host must be shown")
        XCTAssertTrue(host.label.contains("mqtt.example.com"),
                      "the stored host value must be visible, not blanked")
        // The password is shown masked, never in the clear.
        let password = element(app, "broker.password")
        XCTAssertTrue(scrollToElement(password, in: app))
        XCTAssertFalse(password.label.lowercased().contains("secret"),
                       "the stored password must never be shown in the clear")
        // The locked banner and unlock offer are both present.
        XCTAssertTrue(element(app, "unlock.buy.automation.entry").exists,
                      "an unlock offer must be present on the locked broker surface")
    }

    // MARK: - Assertion 2 — no purchase UI during free playback (SC-1100-02 proxy)

    /// Sustained free-tier playback must stay a photo frame. Polls the whole accessibility
    /// tree for anything identified `unlock.*` across a window spanning at least
    /// `requiredAdvances` real photo advances, rather than sampling once and hoping.
    @MainActor
    func testNoPurchaseUIAppearsDuringSustainedFreePlayback() throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "--uitest", "--uitest-slideshow", "--uitest-reset-theme",
            "--uitest-duration-seconds=\(Int(Self.stubPhotoSeconds))",
            "--uitest-entitlements=none",
        ]
        app.launch()

        let image = element(app, "slideshow.image")
        XCTAssertTrue(image.waitForExistence(timeout: 10), "free-tier slideshow should be running")

        var lastAsset = image.exists ? (image.value as? String ?? "") : ""
        var advances = 0
        let deadline = Date().addingTimeInterval(
            Double(Self.requiredAdvances) * Self.stubPhotoSeconds + Self.windowSlackSeconds
        )

        while Date() < deadline && advances < Self.requiredAdvances {
            assertNoUnlockUI(app, context: "during playback (advance \(advances))")

            if image.exists, let current = image.value as? String, !current.isEmpty,
               current != lastAsset {
                advances += 1
                lastAsset = current
            }
            usleep(Self.pollMicroseconds)
        }

        XCTAssertGreaterThanOrEqual(
            advances, Self.requiredAdvances,
            "the window must cover at least \(Self.requiredAdvances) photo advances for SC-1100-02 to mean anything"
        )
        // One last look after the final advance settled.
        assertNoUnlockUI(app, context: "after the last advance")
    }

    // MARK: - SC-1100-01 — free onboarding completes with zero purchase UI

    /// The shared-link path (210) end to end on the free tier: choice screen → link → running
    /// slideshow, with the tree swept for `unlock.*` at every step. Nothing about setting up
    /// a photo frame may mention money.
    @MainActor
    func testFreeSharedLinkOnboardingCompletesWithNoPurchaseUI() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--uitest", "--uitest-onboarding-choice", "--uitest-entitlements=none"]
        app.launch()

        let sharedLinkChoice = app.buttons["onboarding.choice.sharedLink"]
        XCTAssertTrue(sharedLinkChoice.waitForExistence(timeout: 5),
                      "choice screen should offer the shared-link path")
        assertNoUnlockUI(app, context: "onboarding choice screen")
        sharedLinkChoice.tap()

        let url = app.textFields["onboarding.sharedLink.url"]
        XCTAssertTrue(url.waitForExistence(timeout: 5), "shared-link URL field should appear")
        assertNoUnlockUI(app, context: "shared-link setup screen")
        url.tap()
        url.typeText("https://demo.example.com/s/abc123")
        app.buttons["onboarding.sharedLink.start"].tap()

        // The stub resolver maps any link to album a2 (asset-4…6).
        let image = element(app, "slideshow.image")
        XCTAssertTrue(image.waitForExistence(timeout: 30),
                      "the free tier must reach a running slideshow (SC-1100-01)")
        let plays = NSPredicate(format: "value IN %@", ["asset-4", "asset-5", "asset-6"])
        expectation(for: plays, evaluatedWith: image)
        waitForExpectations(timeout: 5)

        assertNoUnlockUI(app, context: "running slideshow after onboarding")
    }

    // MARK: - Assertion 4 — `all` control case (guards against a vacuous suite)

    /// With everything owned, the locked rows must not exist anywhere in the settings form.
    /// Without this test the whole file would pass by never wiring the identifiers at all.
    @MainActor
    func testNoLockedRowsWhenEverythingIsUnlocked() throws {
        let app = launchIntoSettings(entitlements: "all")

        // Anchor: we really are in a populated settings form, so an absence below means
        // "not rendered", not "never got here".
        XCTAssertTrue(app.switches["settings.clock"].waitForExistence(timeout: 5),
                      "the live Clock control should be present when Pro is owned")

        // Sweep the whole form — a row that is merely scrolled out of the tree would
        // otherwise read as absent.
        for step in 0...Self.maxSwipes {
            for identifier in Self.lockedRowIdentifiers {
                XCTAssertFalse(element(app, identifier).exists,
                               "\(identifier) must not exist with everything unlocked (scroll step \(step))")
            }
            if step < Self.maxSwipes { app.swipeUp() }
        }

        // Proves the sweep actually reached the bottom of the form, where the broker lives.
        XCTAssertTrue(element(app, "settings.mqtt").exists,
                      "the sweep should have scrolled as far as the MQTT section")
    }

    // MARK: - Helpers

    private static let lockedRowIdentifiers = [
        "settings.row.kenburns.locked",
        "settings.row.clock.locked",
        "settings.row.broker.locked",
    ]

    private static let maxSwipes = 8

    /// Launches straight into the settings sheet over the hermetic stub slideshow:
    /// `--uitest-chrome` pins the chrome so nothing races the idle auto-hide, and
    /// `--uitest-settings` opens the sheet without needing a tap. `--uitest-reset-theme`
    /// clears whatever an earlier test persisted into the shared UI-test theme suite.
    @MainActor
    private func launchIntoSettings(entitlements: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "--uitest", "--uitest-slideshow", "--uitest-chrome", "--uitest-settings",
            "--uitest-reset-theme", "--uitest-entitlements=\(entitlements)",
        ]
        app.launch()
        XCTAssertTrue(app.sliders["settings.brightness"].waitForExistence(timeout: 10),
                      "settings should be open")
        return app
    }

    @MainActor
    private func element(_ app: XCUIApplication, _ identifier: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    /// Every element the gate could possibly surface shares the `unlock.` identifier prefix
    /// (contract table), so one predicate covers screens, prices, buttons and notices.
    @MainActor
    private func unlockElements(_ app: XCUIApplication) -> XCUIElementQuery {
        app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH %@", "unlock."))
    }

    @MainActor
    private func assertNoUnlockUI(
        _ app: XCUIApplication,
        context: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        XCTAssertEqual(unlockElements(app).count, 0,
                       "no purchase UI may appear unprompted — \(context)",
                       file: file, line: line)
    }

    /// Swipes up until the element exists (or the swipe budget is exhausted).
    @MainActor
    private func scrollToElement(
        _ element: XCUIElement,
        in app: XCUIApplication,
        maxSwipes: Int = PurchaseGateUITests.maxSwipes
    ) -> Bool {
        if element.waitForExistence(timeout: 3) { return true }
        var swipes = 0
        while !element.exists && swipes < maxSwipes {
            app.swipeUp()
            swipes += 1
        }
        return element.exists
    }
}
