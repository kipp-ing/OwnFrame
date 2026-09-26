//
//  DeviceSoakUITests.swift
//  OwnFrameUITests
//
//  Soaks (hitl.md §7) on a REAL, already configured frame, production path (no launch
//  arguments), driven by `.claude/scripts/soak.sh`. The long runs are single tests: offline,
//  iOS won't start a new runner at all, and on iOS 17 only one test per daemon start is
//  trustworthy (#84). The 4 h free-tier run proved a runner survives hours.
//
//  Skipped unless `SOAK=1`; the script sets it.
//

import XCTest

final class DeviceSoakUITests: XCTestCase {

    private let long: TimeInterval = 120

    override func setUpWithError() throws {
        continueAfterFailure = false
        try XCTSkipUnless(ProcessInfo.processInfo.environment["SOAK"] == "1",
                          "Soak step — run via .claude/scripts/soak.sh")
    }

    private var env: [String: String] { ProcessInfo.processInfo.environment }

    /// One checkpoint: a (re)launch reaches a slideshow that advances, shows no purchase UI,
    /// and — for the entitled soak (`EXPECT_CLOCK=1`) — still renders the gated clock, i.e. the
    /// cached entitlement held (SC-1100-04, FR-1100-10).
    @MainActor
    func testSoakCheckpoint() throws {
        let app = XCUIApplication()
        app.launchArguments = []
        app.launch()
        checkpoint(app, "checkpoint")
    }

    /// SC-1100-04 in ONE runner session: airplane on, a relaunch checkpoint every `HOURS`/4
    /// (default 24), airplane off. Separate steps can't work offline: iOS refuses to launch a
    /// test runner while it can't verify the developer certificate ("Developer App Certificate
    /// is not trusted", jk 2026-09-26), so every step after airplane-on would fail to start.
    /// No device reboot: that would end this runner too (SC-1100-04's restart stays a hand check).
    @MainActor
    func testOfflineEntitledSoak() throws {
        continueAfterFailure = true // one bad checkpoint must not skip the rest, or airplane-off
        let hours = Double(env["HOURS"] ?? "") ?? 24
        let app = XCUIApplication()
        app.launchArguments = []
        app.launch()
        addTeardownBlock { @MainActor in AirplaneMode.set(false, returningTo: app) }
        AirplaneMode.set(true, returningTo: app)
        // Really offline, not just a switch: Wi-Fi can stay up in airplane mode.
        AirplaneMode.assertServer(URL(string: "https://bilder.kippings.de")!, reachable: false)
        checkpoint(app, "checkpoint-0")
        for i in 1...4 {
            Thread.sleep(forTimeInterval: hours * 3600 / 4)
            app.terminate()
            app.launch()
            checkpoint(app, "checkpoint-\(i)")
            AirplaneMode.assertServer(URL(string: "https://bilder.kippings.de")!, reachable: false)
        }
    }

    @MainActor
    private func checkpoint(_ app: XCUIApplication, _ name: String) {
        let slideshow = app.descendants(matching: .any).matching(identifier: "slideshow.image").firstMatch
        XCTAssertTrue(slideshow.waitForExistence(timeout: long), "the frame should resume its slideshow")
        assertNoPurchaseUI(app)
        if env["EXPECT_CLOCK"] == "1" {
            XCTAssertTrue(app.descendants(matching: .any)["slideshow.clock"].waitForExistence(timeout: 20),
                          "the clock is a Supporter feature — gone means the cached entitlement was lost")
        }
        let first = slideshow.value as? String ?? ""
        wait(for: [expectation(for: NSPredicate(format: "value != %@", first), evaluatedWith: slideshow)],
             timeout: 180)
        attach(app, name)
    }

    /// Turns the clock overlay on (a Supporter feature), so checkpoints can see the entitlement.
    @MainActor
    func testSoakPrepareClockOn() throws {
        let app = XCUIApplication()
        app.launchArguments = []
        app.launch()
        let slideshow = app.descendants(matching: .any).matching(identifier: "slideshow.image").firstMatch
        XCTAssertTrue(slideshow.waitForExistence(timeout: long))
        if !app.descendants(matching: .any)["slideshow.clock"].exists {
            let settings = app.buttons["slideshow.chrome.settings"]
            if !settings.isHittable { slideshow.tap() }
            XCTAssertTrue(settings.waitForExistence(timeout: 15))
            settings.tap()
            let clock = app.switches["settings.clock"]
            XCTAssertTrue(clock.waitForExistence(timeout: 15), "the clock switch should exist — is the frame entitled?")
            if (clock.value as? String) != "1" { app.tapSwitchControl(clock) } // ScrollHarness
            app.buttons["Done"].tap()
        }
        XCTAssertTrue(app.descendants(matching: .any)["slideshow.clock"].waitForExistence(timeout: 20),
                      "the clock should show — only an entitled frame renders it")
        attach(app, "clock-on")
    }

    /// `AIRPLANE=on|off`, left that way — `soak.sh` owns switching it back (with a trap).
    @MainActor
    func testSoakAirplane() throws {
        let app = XCUIApplication()
        app.launchArguments = []
        app.launch()
        AirplaneMode.set(env["AIRPLANE"] == "on", returningTo: app)
    }

    /// SC-1100-02: hours of free-tier playback with no purchase UI ever appearing. Checks every
    /// 10 minutes that the slideshow is still on screen and has moved on; `HOURS` (default 4).
    @MainActor
    func testFreeTierPlaybackShowsNoPurchaseUI() throws {
        let hours = Double(env["HOURS"] ?? "") ?? 4
        let app = XCUIApplication()
        app.launchArguments = []
        app.launch()
        let slideshow = app.descendants(matching: .any).matching(identifier: "slideshow.image").firstMatch
        XCTAssertTrue(slideshow.waitForExistence(timeout: long))
        let end = Date().addingTimeInterval(hours * 3600)
        var round = 0
        while Date() < end {
            // Sample every 20 s: comparing only the ends of a 10-minute window aliases on a
            // small album (A → B → A reads as "stuck" — seen on Framepad's 2-photo album).
            let windowStart = slideshow.value as? String ?? ""
            var moved = false
            for _ in 0..<30 {
                Thread.sleep(forTimeInterval: 20)
                if (slideshow.value as? String ?? "") != windowStart { moved = true }
            }
            round += 1
            XCTAssertTrue(slideshow.exists, "round \(round): the slideshow should still be on screen")
            assertNoPurchaseUI(app)
            XCTAssertTrue(moved, "round \(round): no new photo in 10 minutes")
            if round % 6 == 0 { attach(app, "hour-\(round / 6)") }
        }
    }

    @MainActor
    private func assertNoPurchaseUI(_ app: XCUIApplication) {
        let purchase = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH 'unlock.'")).firstMatch
        XCTAssertFalse(purchase.exists, "no purchase UI may appear unasked (SC-1100-02)")
    }

    @MainActor
    private func attach(_ app: XCUIApplication, _ name: String) {
        let shot = XCTAttachment(screenshot: app.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }
}
