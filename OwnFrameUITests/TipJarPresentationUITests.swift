//
//  TipJarPresentationUITests.swift
//  OwnFrameUITests
//
//  1100 / US6 (FR-1100-08) — the tip jar is optional, reachable ONLY via settings, and
//  presents a real sheet when its row is tapped. This is the durable regression guard for
//  that "reachable + presents" requirement, driven hermetically through the `--uitest-store=`
//  and `--uitest-entitlements=` seams (contracts/uitest-seams.md). StoreKit is never reached.
//
//  Ungated, English-only, part of the normal suite — unlike GermanScreenshotSweepUITests,
//  whose tip-jar screens (74–76) are SCREENSHOT_DE-gated and first captured this as a crash
//  rather than an assertion. See issue #42: with the simulator's hardware keyboard connected
//  (the default), presenting this sheet in landscape aborts the app inside UIKit's focus
//  engine — an unfixed UIKit bug (Apple r.154431813), defused for UI tests by
//  FocusEngineUITestWorkaround in OwnFrameApp.swift. This file asserts the sheet actually
//  presents (`tipjar.screen`), so it goes RED again if that shim regresses.
//

import XCTest

final class TipJarPresentationUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
        // Never inherit a rotation leaked by an earlier test on the same simulator clone.
        MainActor.assumeIsolated { XCUIDevice.shared.orientation = .portrait }
    }

    // MARK: - FR-1100-08 — the tip jar presents from settings

    /// The whole of FR-1100-08's "reachable via settings" leg: a user in Settings scrolls to
    /// the Unlocks section, taps "Leave a Tip", and the tip jar sheet actually appears. Nothing
    /// exotic — a plain scroll + single tap, the minimal realistic gesture.
    ///
    /// Without the issue-#42 shim, presenting the sheet aborts the app in UIKit's focus engine
    /// before `tipjar.screen` ever mounts, and the wait times out on a dead app.
    @MainActor
    func testTipJarPresentsFromSettings() throws {
        let app = launchIntoSettings()

        let tipRow = element(app, "settings.tipjar")
        XCTAssertTrue(scrollToElement(tipRow, in: app),
                      "the 'Leave a Tip' row must be reachable in the Unlocks section (FR-1100-08)")
        tipRow.tap()

        XCTAssertTrue(element(app, "tipjar.screen").waitForExistence(timeout: 10),
                      "tapping settings.tipjar must present the tip jar sheet (tipjar.screen) (FR-1100-08)")
    }

    // MARK: - Helpers

    /// Launches straight into the settings sheet over the hermetic stub slideshow, unentitled
    /// (the tip jar lives in the Unlocks section on every tier) with the stub store wired so the
    /// tip jar has real products to price. Mirrors PurchaseGateUITests' launch seam:
    /// `--uitest-chrome` pins the chrome, `--uitest-settings` opens the sheet without a tap,
    /// `--uitest-reset-theme` clears any persisted UI-test theme state.
    @MainActor
    private func launchIntoSettings() -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = [
            "--uitest", "--uitest-slideshow", "--uitest-chrome", "--uitest-settings",
            "--uitest-reset-theme", "--uitest-entitlements=none", "--uitest-store=stub",
        ]
        app.launch()
        // Landscape is LOAD-BEARING for this regression, not cosmetic: the frame lives on a
        // wall-mounted iPad in landscape (as the sweep drives it), and the issue #42 focus-engine
        // abort only fires when the tip jar sheet is presented over a landscape iPad Form. In
        // portrait the very same navigation presents cleanly. Do not "simplify" this to portrait —
        // that turns the test green without fixing the crash. (Reproduces on iPadOS 26.0 and 18.6.)
        if UIDevice.current.userInterfaceIdiom == .pad {
            XCUIDevice.shared.orientation = .landscapeLeft
        }
        XCTAssertTrue(app.sliders["settings.brightness"].waitForExistence(timeout: 10),
                      "settings should be open")
        return app
    }

    @MainActor
    private func element(_ app: XCUIApplication, _ identifier: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    /// Converges on the element rather than spending a fixed swipe budget — see ScrollHarness.
    @MainActor
    private func scrollToElement(
        _ element: XCUIElement,
        in app: XCUIApplication
    ) -> Bool {
        _ = element.waitForExistence(timeout: 3)
        app.scrollUntilHittable(element)
        return element.exists
    }
}
