//
//  DeviceSoakUITests.swift
//  OwnFrameUITests
//
//  Soaks (hitl.md §7) on a REAL, already configured frame, production path (no launch
//  arguments). Short steps that `.claude/scripts/soak.sh` strings together over hours — a
//  24 h test would die with its runner — plus one long free-tier run, which is a single test
//  so it also fits iOS 17's one-trustworthy-test-per-daemon limit (#84).
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
        attach(app, "checkpoint")
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
        var last = slideshow.value as? String ?? ""
        var round = 0
        while Date() < end {
            Thread.sleep(forTimeInterval: 600)
            round += 1
            XCTAssertTrue(slideshow.exists, "round \(round): the slideshow should still be on screen")
            assertNoPurchaseUI(app)
            let now = slideshow.value as? String ?? ""
            XCTAssertNotEqual(now, last, "round \(round): no new photo in 10 minutes")
            last = now
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
