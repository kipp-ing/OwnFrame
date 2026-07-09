//
//  SettingsStorageUITests.swift
//  Immich SlideshowUITests
//
//  320 / US3 — the Storage section: usage label, fixed-step budget picker, and
//  Clear behind a confirmation. Hermetic: the `--uitest` build wires REAL
//  file-backed stores rooted in the sandbox tmp dir (they persist across
//  relaunches; `--uitest-reset-storage` starts clean), so these tests exercise
//  the production disk paths without a server.
//

import XCTest

final class SettingsStorageUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
        // Never inherit a rotation leaked by an earlier test on the same simulator
        // clone — a launch during a stale landscape state positions the chrome
        // off-screen. Tests that need landscape rotate themselves (and restore).
        MainActor.assumeIsolated { XCUIDevice.shared.orientation = .portrait }
    }

    /// The Form vends rows lazily, and Storage sits far down — swipe until the
    /// element exists (bounded so a missing row fails the assertion, not hangs).
    @MainActor
    private func scrollTo(_ element: XCUIElement, in app: XCUIApplication) {
        for _ in 0..<4 where !element.exists {
            app.swipeUp()
        }
    }

    @MainActor
    func testStorageSectionShowsUsageBudgetAndClear() throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "--uitest", "--uitest-slideshow", "--uitest-chrome", "--uitest-settings",
            "--uitest-reset-storage"
        ]
        app.launch()

        let usage = app.descendants(matching: .any)
            .matching(identifier: "settings.storage.usage").firstMatch
        XCTAssertTrue(usage.waitForExistence(timeout: 5) || {
            self.scrollTo(usage, in: app)
            return usage.exists
        }(), "storage usage row should exist")

        let budget = app.descendants(matching: .any)
            .matching(identifier: "settings.storage.budget").firstMatch
        scrollTo(budget, in: app)
        XCTAssertTrue(budget.exists, "budget picker should exist")
        XCTAssertTrue(
            app.staticTexts["500 MB"].firstMatch.exists,
            "budget defaults to 500 MB (FR-320-04)"
        )

        let clear = app.buttons["settings.storage.clear"]
        scrollTo(clear, in: app)
        XCTAssertTrue(clear.exists, "Clear Cache button should exist")
    }

    @MainActor
    func testBudgetSelectionPersistsAcrossRelaunch() throws {
        let app = XCUIApplication()
        app.launchArguments = [
            "--uitest", "--uitest-slideshow", "--uitest-chrome", "--uitest-settings",
            "--uitest-reset-storage"
        ]
        app.launch()

        let budget = app.descendants(matching: .any)
            .matching(identifier: "settings.storage.budget").firstMatch
        XCTAssertTrue(budget.waitForExistence(timeout: 5) || {
            self.scrollTo(budget, in: app)
            return budget.exists
        }(), "budget picker should exist")

        // 500 MB -> 1 GB via the menu picker.
        budget.tap()
        let oneGigabyte = app.buttons["1 GB"].firstMatch
        XCTAssertTrue(oneGigabyte.waitForExistence(timeout: 3))
        oneGigabyte.tap()
        XCTAssertTrue(app.staticTexts["1 GB"].firstMatch.waitForExistence(timeout: 2))

        // Relaunch WITHOUT the reset arg: the choice persists (UserDefaults suite).
        app.terminate()
        let relaunch = XCUIApplication()
        relaunch.launchArguments = [
            "--uitest", "--uitest-slideshow", "--uitest-chrome", "--uitest-settings"
        ]
        relaunch.launch()

        let budgetAfter = relaunch.descendants(matching: .any)
            .matching(identifier: "settings.storage.budget").firstMatch
        XCTAssertTrue(budgetAfter.waitForExistence(timeout: 5) || {
            self.scrollTo(budgetAfter, in: relaunch)
            return budgetAfter.exists
        }(), "settings reopen after relaunch")
        XCTAssertTrue(
            relaunch.staticTexts["1 GB"].firstMatch.waitForExistence(timeout: 2),
            "1 GB budget should persist across relaunch"
        )
    }

    @MainActor
    func testClearResetsTheUsageLabelAfterConfirmation() throws {
        // Let the slideshow PLAY first (no auto-opened settings): the engine
        // writes the stub photos through to the real disk store.
        let app = XCUIApplication()
        app.launchArguments = [
            "--uitest", "--uitest-slideshow", "--uitest-chrome", "--uitest-reset-storage"
        ]
        app.launch()

        let image = app.descendants(matching: .any)
            .matching(identifier: "slideshow.image").firstMatch
        XCTAssertTrue(image.waitForExistence(timeout: 5), "slideshow should be playing")

        // Open Settings from the (pinned) chrome — the usage label reads the
        // store when the Storage section appears, after the writes above.
        app.buttons["slideshow.chrome.settings"].tap()
        let usage = app.staticTexts["settings.storage.usage"]
        XCTAssertTrue(usage.waitForExistence(timeout: 5) || {
            self.scrollTo(usage, in: app)
            return usage.exists
        }(), "storage usage label should exist")
        XCTAssertNotEqual(
            usage.label, "0 bytes",
            "played photos should have produced non-zero usage"
        )

        // Clear behind its confirmation dialog (FR-320-05).
        let clear = app.buttons["settings.storage.clear"]
        scrollTo(clear, in: app)
        clear.tap()
        let confirm = app.buttons["Clear Cache"].firstMatch
        XCTAssertTrue(confirm.waitForExistence(timeout: 3), "confirmation dialog should appear")
        confirm.tap()

        // The usage label returns to zero without leaving the slideshow.
        let zero = NSPredicate(format: "label == %@", "0 bytes")
        let becameZero = XCTNSPredicateExpectation(predicate: zero, object: usage)
        XCTAssertEqual(
            XCTWaiter().wait(for: [becameZero], timeout: 5), .completed,
            "usage should read 0 bytes after Clear"
        )
    }
}
