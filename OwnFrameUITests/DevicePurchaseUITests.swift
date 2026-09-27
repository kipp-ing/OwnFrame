//
//  DevicePurchaseUITests.swift
//  OwnFrameUITests
//
//  #79 / SC-1100-03 on a real device with a real SANDBOX purchase: tapping Unlock once and
//  confirming the system purchase sheet must show the unlocked state without a second tap
//  (the observed bug) and without a relaunch. Production path: no launch arguments, no
//  StoreKit configuration file — the sandbox account signed in under Settings → Developer.
//
//  Preconditions: a configured frame (slideshow running), an UNPURCHASED sandbox account
//  (Settings → Developer → Sandbox Apple Account → clear purchase history to rerun).
//  Env: TEST_RUNNER_DEVICE_PURCHASE=1, TEST_RUNNER_SANDBOX_PASSWORD (for the sign-in prompt
//  iOS may raise; never logged), TEST_RUNNER_PURCHASE_LABELS (the sheet's buy-button label in the
//  device language, comma-separated). Buys for real in the sandbox — nothing is charged.
//

import XCTest

final class DevicePurchaseUITests: XCTestCase {

    private var env: [String: String] { ProcessInfo.processInfo.environment }

    override func setUpWithError() throws {
        continueAfterFailure = false
        try XCTSkipUnless(env["DEVICE_PURCHASE"] == "1", "Real sandbox purchase — opt-in only")
    }

    @MainActor
    func testSandboxPurchaseUnlocksWithoutSecondTap() throws {
        let app = XCUIApplication()
        app.launchArguments = []
        app.launch()
        let image = app.descendants(matching: .any).matching(identifier: "slideshow.image").firstMatch
        XCTAssertTrue(image.waitForExistence(timeout: 90), "needs a configured frame")

        openSettings(app, image: image)
        let locked = app.descendants(matching: .any)["settings.row.kenburns.locked"]
        scrollFormUntil(app, locked)
        XCTAssertTrue(locked.isHittable, "an unpurchased frame shows Ken Burns locked — clear the sandbox purchase history")
        locked.tap()

        let buy = app.buttons["unlock.buy.supporter"]
        XCTAssertTrue(buy.waitForExistence(timeout: 30), "the unlock screen should offer the Supporter Unlock")
        attach(app, "01-unlock-screen")
        buy.tap() // the ONE tap — never tapped again below

        let done = app.buttons["unlock.done"]
        let started = Date()
        confirmPurchaseSheet(until: done, timeout: 120)
        XCTAssertTrue(done.waitForExistence(timeout: 30),
                      "#79: the unlocked state should show after one tap, without tapping Unlock again")
        print("purchase: unlocked state after \(Int(Date().timeIntervalSince(started))) s")
        attach(app, "05-unlocked")

        done.tap()
        XCTAssertTrue(app.switches["settings.kenBurns"].waitForExistence(timeout: 10)
                        || app.descendants(matching: .any)["settings.kenBurns"].exists,
                      "Ken Burns should now be a live switch, without a relaunch")
        attach(app, "06-settings-unlocked")
    }

    /// FR-1100-11 on a second device: after buying elsewhere, Restore Purchases in Settings
    /// brings the unlock here without a relaunch (a StoreKit sync can ask for the password).
    @MainActor
    func testRestorePurchasesBringsTheUnlockFromAnotherDevice() throws {
        let app = XCUIApplication()
        app.launchArguments = []
        app.launch()
        let image = app.descendants(matching: .any).matching(identifier: "slideshow.image").firstMatch
        XCTAssertTrue(image.waitForExistence(timeout: 90), "needs a configured frame")
        openSettings(app, image: image)

        let restore = app.buttons["unlock.restore"]
        scrollFormUntil(app, restore)
        XCTAssertTrue(restore.isHittable, "Settings should offer Restore Purchases")
        attach(app, "01-before-restore")
        restore.tap()

        let unlocked = app.switches["settings.kenBurns"]
        confirmPurchaseSheet(until: unlocked, timeout: 60)
        // Ken Burns sits above the Unlocks section: scroll back up to find it.
        for _ in 0..<12 where !unlocked.exists {
            app.collectionViews.firstMatch.swipeDown()
        }
        XCTAssertTrue(unlocked.waitForExistence(timeout: 30), "Restore should unlock Ken Burns without a relaunch")
        attach(app, "02-restored")
    }

    // MARK: - System purchase sheet

    /// Works through whatever the system shows — sign-in prompt, purchase sheet, "all set"
    /// confirmation — until `target` appears in the app. English labels first; on another system
    /// language the StoreKit sheet's primary action (its lowest hittable button) is the fallback.
    @MainActor
    private func confirmPurchaseSheet(until target: XCUIElement, timeout: TimeInterval) {
        // The sheet can live in the app (remote view), SpringBoard or the StoreKit UI service.
        let hosts = [XCUIApplication(),
                     XCUIApplication(bundleIdentifier: "com.apple.springboard"),
                     XCUIApplication(bundleIdentifier: "com.apple.ios.StoreKitUIService")]
        // The device's own language arrives as data (PURCHASE_LABELS, comma-separated, e.g. the
        // German sheet's buy button), so no non-English literal lives in the source.
        let local = (env["PURCHASE_LABELS"] ?? "").split(separator: ",").map(String.init)
        // `pay-now` is the iOS 27 sheet's buy-button identifier, language-independent (FramePhone).
        let confirm = ["pay-now", "Purchase", "Buy", "Confirm", "Subscribe"] + local
        let signIn = ["Sign In"]
        let ok = ["OK", "Done"]
        var step = 2
        var typedPassword = false
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline && !target.exists {
            var acted = false
            for host in hosts where host.state != .notRunning {
                if let password = env["SANDBOX_PASSWORD"], !typedPassword, host.secureTextFields.firstMatch.exists {
                    attach(host, "0\(step)-sign-in"); step += 1
                    host.secureTextFields.firstMatch.tap()
                    // Return submits in any language; the Sign In label is only a fallback.
                    host.secureTextFields.firstMatch.typeText(password + "\n")
                    typedPassword = true
                    tapFirst(host, signIn); acted = true; break
                }
                if tapFirst(host, confirm, before: { self.attach(host, "0\(step)-sheet"); step += 1 }) { acted = true; break }
                if tapFirst(host, ok, before: { self.attach(host, "0\(step)-confirmation"); step += 1 }) { acted = true; break }
            }
            if !acted, hosts[2].state != .notRunning {
                let primary = hosts[2].buttons.allElementsBoundByIndex
                    .filter { $0.isHittable }.max { $0.frame.maxY < $1.frame.maxY }
                if let primary {
                    attach(hosts[2], "0\(step)-sheet-primary-\(primary.label)"); step += 1
                    primary.tap(); acted = true
                }
            }
            Thread.sleep(forTimeInterval: acted ? 2 : 1)
        }
    }

    @discardableResult @MainActor
    private func tapFirst(_ host: XCUIApplication, _ labels: [String], before: () -> Void = {}) -> Bool {
        for label in labels {
            let button = host.buttons[label]
            if button.exists && button.isHittable {
                before()
                button.tap()
                return true
            }
        }
        return false
    }

    // MARK: - Helpers

    @MainActor
    private func openSettings(_ app: XCUIApplication, image: XCUIElement) {
        let settings = app.buttons["slideshow.chrome.settings"]
        for _ in 0..<3 where !settings.isHittable {
            image.tap()
            _ = settings.waitForExistence(timeout: 2)
        }
        settings.tap()
    }

    /// Short drags on the Form's list: rows only materialise in view, and a flick overshoots.
    @MainActor
    private func scrollFormUntil(_ app: XCUIApplication, _ element: XCUIElement) {
        let form = app.collectionViews.firstMatch.exists ? app.collectionViews.firstMatch : app.tables.firstMatch
        var steps = 0
        while !(element.waitForExistence(timeout: steps == 0 ? 5 : 1) && element.isHittable) && steps < 10 {
            form.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.75))
                .press(forDuration: 0.1, thenDragTo: form.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.45)))
            steps += 1
        }
    }

    @MainActor
    private func attach(_ app: XCUIApplication, _ name: String) {
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }
}
