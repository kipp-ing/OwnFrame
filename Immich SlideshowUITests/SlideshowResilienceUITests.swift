//
//  SlideshowResilienceUITests.swift
//  Immich SlideshowUITests
//
//  310 release-gate tests — the resilience behavior a reviewer (or a power cut)
//  actually sees. Drives the hermetic `--uitest --uitest-slideshow` build with
//  the failure seams `--uitest-assets-fail=` / `--uitest-assets-recover-after=`:
//  the calm error state, the actionable auth variant, the manual retry path,
//  and — most importantly — unattended auto-recovery with no interaction at all.
//  Part of the standard suite, so every release runs them (test_sim, whole class).
//

import XCTest

final class SlideshowResilienceUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
        // Never inherit a rotation leaked by an earlier test on the same simulator
        // clone (house rule — see SlideshowChromeUITests).
        MainActor.assumeIsolated { XCUIDevice.shared.orientation = .portrait }
    }

    @MainActor
    private func launchSlideshow(extraArgs: [String]) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchArguments = ["--uitest", "--uitest-slideshow"] + extraArgs
        app.launch()
        return app
    }

    /// US1-2 / SC-310-01 at the UI level: a dead server at launch shows the calm
    /// error state, and when the server returns the slideshow starts entirely on
    /// its own — this test never taps anything.
    @MainActor
    func testTransientFailureShowsCalmErrorThenAutoRecovers() throws {
        let app = launchSlideshow(extraArgs: [
            "--uitest-assets-fail=unreachable",
            "--uitest-assets-recover-after=2"
        ])

        // Calm error state, generic copy, retry offered.
        let errorTitle = app.staticTexts["slideshow.error"]
        XCTAssertTrue(errorTitle.waitForExistence(timeout: 5), "calm error state should appear")
        XCTAssertEqual(errorTitle.label, "Couldn’t load the album")
        XCTAssertTrue(app.buttons["slideshow.retry"].exists)

        // The chrome is pinned while failed — Settings/Albums reachable without
        // the screen-wide tap gesture (which is masked off so the error card's
        // buttons win).
        let settings = app.buttons["slideshow.chrome.settings"]
        XCTAssertTrue(settings.waitForExistence(timeout: 2) && settings.isHittable,
                      "chrome should be pinned visible in the failed state")

        // Unattended recovery: the stub recovers after 2 failed fetches; the
        // backoff (~1 s, ~2 s) brings the show up without any user input.
        let image = app.descendants(matching: .any)
            .matching(identifier: "slideshow.image").firstMatch
        XCTAssertTrue(image.waitForExistence(timeout: 15),
                      "slideshow should start by itself once the server recovers")
        XCTAssertFalse(errorTitle.exists, "error state should be gone after recovery")
    }

    /// FR-310-05: auth failures name the actionable problem (not the generic
    /// network hint) and surface the connection editor directly.
    @MainActor
    func testAuthFailureShowsActionableCopyAndOpensConnectionEditor() throws {
        let app = launchSlideshow(extraArgs: ["--uitest-assets-fail=unauthorized"])

        let errorTitle = app.staticTexts["slideshow.error"]
        XCTAssertTrue(errorTitle.waitForExistence(timeout: 5), "error state should appear")
        XCTAssertEqual(errorTitle.label, "Access was denied", "auth failures get the actionable title")

        // The actionable copy names the fix.
        XCTAssertTrue(
            app.staticTexts.containing(NSPredicate(format: "label CONTAINS %@", "connection settings"))
                .firstMatch.exists,
            "auth copy should point at the connection settings"
        )

        // And the fix is one tap away.
        let fixButton = app.buttons["slideshow.fixConnection"]
        XCTAssertTrue(fixButton.exists, "auth failure should offer the connection editor")
        fixButton.tap()
        XCTAssertTrue(app.buttons["connection.save"].waitForExistence(timeout: 5),
                      "Edit connection should open the in-app connection editor")
    }

    /// FR-310-04: the manual retry button stays functional against a server that
    /// keeps failing — an immediate attempt, back to the calm state, no crash,
    /// no dead end.
    @MainActor
    func testManualRetryAgainstDeadServerStaysCalm() throws {
        let app = launchSlideshow(extraArgs: ["--uitest-assets-fail=unreachable"])

        let retry = app.buttons["slideshow.retry"]
        XCTAssertTrue(retry.waitForExistence(timeout: 5), "error state should appear")

        retry.tap()

        // The attempt fails again: still the calm error state, still retryable.
        let errorTitle = app.staticTexts["slideshow.error"]
        XCTAssertTrue(errorTitle.waitForExistence(timeout: 5), "error state should return after a failed manual retry")
        XCTAssertTrue(retry.exists)
        XCTAssertEqual(errorTitle.label, "Couldn’t load the album")
    }
}
