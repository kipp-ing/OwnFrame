//
//  PurchaseGateUITests.swift
//  OwnFrameUITests
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
//  config) are separate files; assertion 7 is explicitly not XCUITest. Assertion 3's
//  `ProductID.uiSlug` parenthetical (PR #40 post-merge review gap — `unlock.price.supporter` /
//  `unlock.buy.supporter` were unasserted) is covered here.
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

    /// The second half of assertion 1: a locked row is an entry point, not a dead end. Every
    /// locked row now leads to the one Supporter Unlock screen — a single unlock grants every
    /// gated capability (Ken Burns motion, the clock overlay, and Home Assistant control).
    @MainActor
    func testTappingALockedRowOpensItsTierUnlockScreen() throws {
        // The two display rows open the Supporter unlock screen directly.
        let displayRows = ["settings.row.kenburns.locked", "settings.row.clock.locked"]

        // A fresh launch per row: no navigation state carried between routes, so a failure
        // names exactly one row.
        for rowID in displayRows {
            let app = launchIntoSettings(entitlements: "none")
            let row = element(app, rowID)
            XCTAssertTrue(scrollToElement(row, in: app), "\(rowID) must be present to be tapped")
            row.tap()
            XCTAssertTrue(element(app, "unlock.screen.supporter").waitForExistence(timeout: 5),
                          "tapping \(rowID) must open unlock.screen.supporter (FR-1100-09)")
            app.terminate()
        }

        // The broker row is the "Remote control" locked banner (US5, amended 2026-07-20):
        // telemetry is free so the broker editor stays live below it, and the banner opens the
        // same Supporter unlock screen directly.
        let app = launchIntoSettings(entitlements: "none")
        let brokerRow = element(app, "settings.row.broker.locked")
        XCTAssertTrue(scrollToElement(brokerRow, in: app), "broker control-locked row must be present")
        brokerRow.tap()
        XCTAssertTrue(element(app, "unlock.screen.supporter").waitForExistence(timeout: 5),
                      "the broker control-locked row must open unlock.screen.supporter")
    }

    // MARK: - ProductID.uiSlug coverage — price + buy identifiers on the unlock screen

    /// Closes the gap the PR #40 post-merge review found (recorded in contracts/uitest-seams.md
    /// assertion 3's parenthetical): `ProductID.uiSlug` feeds `unlock.price.supporter` and
    /// `unlock.buy.supporter`, but no XCUITest ever asserted either existed. Opens the one
    /// unlock screen from a locked row under `none` entitlements — `launchIntoSettings` leaves
    /// `--uitest-store=` unset, which `PurchaseUITestSeams.storeBehavior` defaults to `.stub`, so
    /// the screen has a real stub product ("$1.00") to price.
    @MainActor
    func testUnlockScreenShowsSupporterPriceAndBuyIdentifiers() throws {
        let app = launchIntoSettings(entitlements: "none")

        let kenBurnsRow = element(app, "settings.row.kenburns.locked")
        XCTAssertTrue(scrollToElement(kenBurnsRow, in: app), "kenburns locked row must be present")
        kenBurnsRow.tap()

        XCTAssertTrue(element(app, "unlock.screen.supporter").waitForExistence(timeout: 5),
                      "the locked row must open unlock.screen.supporter")

        let price = element(app, "unlock.price.supporter")
        XCTAssertTrue(price.waitForExistence(timeout: 5),
                      "unlock.price.supporter must exist once the stub store's products load")
        XCTAssertFalse(price.label.isEmpty,
                       "unlock.price.supporter must carry a non-empty price label")

        let buy = element(app, "unlock.buy.supporter")
        XCTAssertTrue(buy.waitForExistence(timeout: 5), "unlock.buy.supporter must exist")
        // The unlock sheet's feature list is taller than the viewport on small phones, so the
        // buy button legitimately starts below the fold — scroll to it before demanding a hit
        // test. (What must never happen is the button being unreachable, not it needing a scroll.)
        XCTAssertTrue(app.scrollUntilHittable(buy),
                      "unlock.buy.supporter must be reachable and hittable, not merely present")
    }

    /// 9000 T005 (#59): the filled accent buy button carries a near-black label, not a white one.
    /// Whether SwiftUI picks white over the Messing fill can't be read from source, so this samples
    /// an element screenshot. Only the button's middle band is read (glyphs and fill; the capsule's
    /// corners show the sheet's dark ground): a white label shows as near-white pixels, a near-black
    /// one as pixels far darker than the fill (Messing luma ≈ 0.69).
    // @covers FR-9000-38
    @MainActor
    func testUnlockBuyButtonLabelIsNearBlack() throws {
        let app = launchIntoSettings(entitlements: "none")
        let kenBurnsRow = element(app, "settings.row.kenburns.locked")
        XCTAssertTrue(scrollToElement(kenBurnsRow, in: app), "kenburns locked row must be present")
        kenBurnsRow.tap()

        XCTAssertTrue(element(app, "unlock.price.supporter").waitForExistence(timeout: 5),
                      "the stub product must load so the button shows its final label")
        let buy = element(app, "unlock.buy.supporter")
        XCTAssertTrue(buy.waitForExistence(timeout: 5) && app.scrollUntilHittable(buy))
        sleep(1)

        let screenshot = buy.screenshot()
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = "unlock-buy-ios\(UIDevice.current.systemVersion)"
        attachment.lifetime = .keepAlways
        add(attachment)

        let lumas = try middleBandLumas(of: screenshot.image)
        let count = Double(lumas.count)
        let nearWhite = Double(lumas.filter { $0 > 0.93 }.count) / count
        let nearBlack = Double(lumas.filter { $0 < 0.25 }.count) / count
        XCTAssertLessThan(nearWhite, 0.01, "white label glyphs on the accent fill (\(nearWhite) of the band)")
        XCTAssertGreaterThan(nearBlack, 0.01, "no near-black label glyphs on the accent fill (\(nearBlack) of the band)")
    }

    // MARK: - Assertion 6 — pre-gate broker config degrades gracefully (US5 / SC-1100-06)

    /// A frame configured before the gate keeps its broker settings, and telemetry is free — so
    /// the broker editor stays LIVE (not a masked read-only screen) with the stored values in
    /// place, while the *control* capability shows a locked banner + unlock offer (US5, amended
    /// 2026-07-20 / FR-1100-03a / FR-1100-14). The no-command half is a device-day check.
    @MainActor
    func testSeededBrokerConfigIsVisibleAndControlLockedWhenUnentitled() throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "--uitest", "--uitest-slideshow", "--uitest-chrome", "--uitest-settings",
            "--uitest-broker", "--uitest-broker-existing", "--uitest-entitlements=none",
        ]
        app.launch()

        // Control is locked (needs the Supporter Unlock): the "Remote control" banner is present…
        let brokerRow = element(app, "settings.row.broker.locked")
        XCTAssertTrue(scrollToElement(brokerRow, in: app),
                      "the control-locked banner must be present when unentitled")

        // …while the broker connection editor is LIVE and pre-filled with the stored config
        // ("not an empty or reset screen", US5 scenario 2). `--uitest-broker` pre-expands it.
        let host = app.textFields["broker.host"]
        XCTAssertTrue(scrollToElement(host, in: app), "the saved broker host must be shown in the live editor")
        XCTAssertEqual(host.value as? String, "mqtt.example.com",
                       "the stored host value must be visible in the live editor, not blanked")
        // The password field is masked — never in the clear.
        let password = element(app, "broker.password")
        XCTAssertTrue(scrollToElement(password, in: app))
        XCTAssertNotEqual(password.value as? String, "secret-pass",
                          "the stored password must never be shown in the clear")
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
                      "the live Clock control should be present when the Supporter Unlock is owned")

        // Sweep the whole form — a row that is merely scrolled out of the tree would
        // otherwise read as absent.
        //
        // The MQTT anchor is recorded as "seen at any point during the sweep" rather than
        // "present at the end". A Form recycles rows out of the accessibility tree once they
        // scroll away, so asserting against the final screen only passes when the sweep happens
        // to stop with that section still on it — which is exactly the coincidence that held on
        // iOS 26.5 and broke on 27.0 (issue #50).
        var sawMQTT = false
        app.sweepToEnd { step in
            for identifier in Self.lockedRowIdentifiers {
                XCTAssertFalse(element(app, identifier).exists,
                               "\(identifier) must not exist with everything unlocked (scroll step \(step))")
            }
            sawMQTT = sawMQTT || element(app, "settings.mqtt").exists
        }

        // Proves the sweep really traversed the form rather than failing to move at all.
        XCTAssertTrue(sawMQTT, "the sweep should have passed the MQTT section")
    }

    // MARK: - Helpers

    private static let lockedRowIdentifiers = [
        "settings.row.kenburns.locked",
        "settings.row.clock.locked",
        "settings.row.broker.locked",
    ]

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

    /// Converges on the element rather than spending a fixed swipe budget — see ScrollHarness.
    @MainActor
    private func scrollToElement(_ element: XCUIElement, in app: XCUIApplication) -> Bool {
        if element.waitForExistence(timeout: 3) { return true }
        app.scrollUntilExists(element)
        return element.exists
    }

    /// Rec. 709 luma (0…1, on sRGB values) of every pixel in the middle band of `image`: rows
    /// 30–70 %, columns 15–85 %, which stays inside a capsule button's fill.
    private func middleBandLumas(of image: UIImage) throws -> [Double] {
        let cgImage = try XCTUnwrap(image.cgImage)
        let width = cgImage.width
        let height = cgImage.height
        var buffer = [UInt8](repeating: 0, count: width * height * 4)
        let space = try XCTUnwrap(CGColorSpace(name: CGColorSpace.sRGB))
        let drawn: Bool = buffer.withUnsafeMutableBytes { raw in
            guard let context = CGContext(
                data: raw.baseAddress, width: width, height: height, bitsPerComponent: 8,
                bytesPerRow: width * 4, space: space,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
            ) else { return false }
            context.draw(cgImage, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        XCTAssertTrue(drawn, "could not decode the button screenshot")

        var lumas: [Double] = []
        for y in (height * 3 / 10)..<(height * 7 / 10) {
            for x in (width * 15 / 100)..<(width * 85 / 100) {
                let i = (y * width + x) * 4
                let r = Double(buffer[i]) / 255, g = Double(buffer[i + 1]) / 255, b = Double(buffer[i + 2]) / 255
                lumas.append(0.2126 * r + 0.7152 * g + 0.0722 * b)
            }
        }
        return lumas
    }
}
