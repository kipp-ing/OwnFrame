//
//  LiveSmokeUITests.swift
//  OwnFrameUITests
//
//  Live manual-smoke driver — NOT part of the test suite. Skips unless the
//  LIVE_SMOKE=1 environment variable is set, because it runs the REAL app (no
//  --uitest stubs) against the live demo shared link and needs network access.
//  Run it alone after uninstalling the app (fresh onboarding state); it walks the
//  whole first-run journey the way a first-time user would — including a typo on
//  the first attempt and a scheme-less URL on the second — and attaches a
//  full-screen capture at every step (portrait first, then landscape). Export the
//  attachments and eyeball them; XCUITest cannot see the system status bar, so
//  status-bar/overlay verification happens on the exported PNGs:
//
//      xcrun xcresulttool export attachments --path <bundle>.xcresult --output-path <dir>
//

import XCTest

final class LiveSmokeUITests: XCTestCase {

    // Typed the way a first-time user would: no https://, and the first attempt
    // is incomplete (slug forgotten) so the inline error must show and recover.
    private static let incompleteLink = "bilder.kippings.de/s/"
    private static let demoSlug = "Iceland2021"

    override func setUpWithError() throws {
        guard ProcessInfo.processInfo.environment["LIVE_SMOKE"] == "1" else {
            throw XCTSkip("live smoke only runs with LIVE_SMOKE=1")
        }
        continueAfterFailure = false
        MainActor.assumeIsolated { XCUIDevice.shared.orientation = .portrait }
    }

    override func tearDownWithError() throws {
        MainActor.assumeIsolated { XCUIDevice.shared.orientation = .portrait }
    }

    @MainActor
    func testFirstTimeUserJourneyThroughLiveDemoLink() throws {
        let app = XCUIApplication()
        app.launch()

        // 1 — first-run choice screen (requires a fresh install).
        let sharedLinkChoice = app.buttons["onboarding.choice.sharedLink"]
        XCTAssertTrue(sharedLinkChoice.waitForExistence(timeout: 10),
                      "expected the first-run choice screen — uninstall the app before the smoke")
        attach("p01-choice")
        sharedLinkChoice.tap()

        // 2 — first attempt: incomplete link (no slug) must error inline, not hang.
        let url = app.textFields["onboarding.sharedLink.url"]
        XCTAssertTrue(url.waitForExistence(timeout: 5))
        url.tap()
        url.typeText(Self.incompleteLink)
        app.buttons["onboarding.sharedLink.start"].tap()
        let error = app.staticTexts["onboarding.sharedLink.error"]
        XCTAssertTrue(error.waitForExistence(timeout: 5),
                      "an incomplete link should surface the inline error")
        attach("p02-error-incomplete-link")

        // 3 — fix it in place: cursor to the end of the field, append the slug.
        url.coordinate(withNormalizedOffset: CGVector(dx: 0.95, dy: 0.5)).tap()
        url.typeText(Self.demoSlug)
        XCTAssertEqual(url.value as? String, Self.incompleteLink + Self.demoSlug,
                       "appending at the field's right edge should complete the link")
        attach("p03-filled-keyboard-up")
        app.buttons["onboarding.sharedLink.start"].tap()

        // 4 — live resolve + first image over the network (scheme-less entry).
        let image = app.descendants(matching: .any)
            .matching(identifier: "slideshow.image").firstMatch
        XCTAssertTrue(image.waitForExistence(timeout: 60),
                      "the scheme-less demo link should start the live slideshow")
        sleep(2)
        attach("p04-slideshow-portrait")

        // 5 — swipe advances (and never reveals the chrome).
        let before = image.value as? String
        image.swipeLeft()
        expectValueChange(of: image, from: before)
        XCTAssertFalse(app.buttons["slideshow.chrome.next"].isHittable,
                       "swiping must not reveal the chrome")
        attach("p05-swiped")

        // 6 — tap reveals the chrome.
        revealChrome(app, image: image)
        attach("p06-chrome-portrait")

        // 7 — transport: next advances, pause/resume keeps the chrome responsive.
        // Timed generously and recorded: ~instant = healthy (prefetched or a fast
        // fetch); ~15s = the tap was swallowed and the auto-advance ticker moved
        // the show instead; 40s+ = the manual step genuinely stalled.
        let beforeNext = image.value as? String
        app.buttons["slideshow.chrome.next"].tap()
        let tappedAt = Date()
        let advanced = XCTNSPredicateExpectation(
            predicate: NSPredicate(format: "value != %@", beforeNext ?? ""), object: image
        )
        let outcome = XCTWaiter().wait(for: [advanced], timeout: 40)
        let note = XCTAttachment(
            string: "next tap → advance: \(outcome) after \(Date().timeIntervalSince(tappedAt))s"
        )
        note.name = "diag-next-advance"
        note.lifetime = .keepAlways
        add(note)
        XCTAssertEqual(outcome, .completed, "Next never advanced the photo within 40s")
        revealChrome(app, image: image)
        let playPause = app.buttons["slideshow.chrome.playPause"]
        playPause.tap()
        usleep(500_000)
        attach("p07-paused")
        XCTAssertTrue(playPause.isHittable, "pause must keep the chrome up")
        playPause.tap()
        usleep(500_000)

        // 8 — photo info overlay on and off (EXIF date/location load async).
        toggleInfo(app, image: image, on: true)
        sleep(2)
        attach("p08-photo-info-portrait")
        toggleInfo(app, image: image, on: false)

        // 9 — settings sheet opens and dismisses.
        openSettings(app, image: image)
        sleep(1)
        attach("p09-settings-portrait")
        app.buttons["Done"].tap()
        sleep(1)

        // 10 — leave the app and come back: the slideshow must survive.
        XCUIDevice.shared.press(.home)
        sleep(2)
        app.activate()
        XCTAssertTrue(image.waitForExistence(timeout: 10),
                      "the slideshow should resume after backgrounding")
        sleep(1)
        attach("p10-after-background")

        // 11 — the same story in landscape.
        XCUIDevice.shared.orientation = .landscapeLeft
        sleep(1)
        attach("l01-slideshow-landscape")

        revealChrome(app, image: image)
        attach("l02-chrome-landscape")

        toggleInfo(app, image: image, on: true)
        sleep(2)
        attach("l03-photo-info-landscape")
        toggleInfo(app, image: image, on: false)

        openSettings(app, image: image)
        sleep(1)
        attach("l04-settings-landscape")
        app.buttons["Done"].tap()
    }

    // MARK: - Helpers

    /// Waits for the slideshow image oracle to report a different asset id.
    @MainActor
    private func expectValueChange(of image: XCUIElement, from previous: String?) {
        let changed = NSPredicate(format: "value != %@", previous ?? "")
        expectation(for: changed, evaluatedWith: image)
        waitForExpectations(timeout: 10)
    }

    /// Taps the photo until the chrome is actually hittable (it toggles, and an
    /// auto-hide racing the tap can swallow one toggle).
    @MainActor
    private func revealChrome(_ app: XCUIApplication, image: XCUIElement) {
        let probe = app.buttons["slideshow.chrome.next"]
        for _ in 0..<3 {
            if probe.isHittable { return }
            image.tap()
            usleep(800_000)
        }
        XCTAssertTrue(probe.isHittable, "chrome should be visible after tapping the photo")
    }

    /// Toggles the photo-info overlay via the chrome, retrying across auto-hides.
    @MainActor
    private func toggleInfo(_ app: XCUIApplication, image: XCUIElement, on: Bool) {
        let card = app.descendants(matching: .any)
            .matching(identifier: "slideshow.info.card").firstMatch
        for _ in 0..<3 {
            if card.exists == on { break }
            revealChrome(app, image: image)
            app.buttons["slideshow.chrome.info"].tap()
            let settled = NSPredicate(format: "exists == %@", NSNumber(value: on))
            let wait = XCTNSPredicateExpectation(predicate: settled, object: card)
            _ = XCTWaiter.wait(for: [wait], timeout: 3)
        }
        XCTAssertEqual(card.exists, on, "the photo info overlay should toggle \(on ? "on" : "off")")
    }

    /// Opens the settings sheet via the chrome, retrying across auto-hides.
    @MainActor
    private func openSettings(_ app: XCUIApplication, image: XCUIElement) {
        let done = app.buttons["Done"]
        for _ in 0..<3 {
            if done.exists { break }
            revealChrome(app, image: image)
            app.buttons["slideshow.chrome.settings"].tap()
            _ = done.waitForExistence(timeout: 3)
        }
        XCTAssertTrue(done.exists, "the settings sheet should present")
    }

    @MainActor
    private func attach(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
