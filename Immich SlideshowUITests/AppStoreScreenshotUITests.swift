//
//  AppStoreScreenshotUITests.swift
//  Immich SlideshowUITests
//
//  App Store screenshot capture — NOT part of the test suite. Skips unless the
//  SCREENSHOT_CAPTURE=1 environment variable is set, because it runs the REAL app
//  (no --uitest stubs) against the live demo shared link and needs network access.
//  Run it alone on the iPad Pro 13" simulator after uninstalling the app (fresh
//  onboarding state), then export the attachments from the xcresult bundle:
//
//      xcrun xcresulttool export attachments --path <bundle>.xcresult --output-path <dir>
//
//  XCUIScreen returns the portrait pixel buffer even in landscape — rotate the
//  exported PNGs 90° CCW (`sips -r 270`) to get the 2752×2064 landscape frames.
//  The demo link and hero assets are the ones referenced in the App Review notes
//  (docs/app-store-listing.md): album "2021-06-Island best of", 38 images.
//

import XCTest

final class AppStoreScreenshotUITests: XCTestCase {

    private static let demoLink = "https://bilder.kippings.de/s/Iceland2021"
    // Hero photos (Jan's picks): the red-roof chapel and the iceberg drone shot.
    private static let chapelAssetID = "87b68d06-03e7-4d9d-a07d-dd00171af601"   // DSC05546
    private static let icebergAssetID = "a21c487a-802b-4be5-a1d5-62f3e41978dd"  // DJI_0371

    override func setUpWithError() throws {
        guard ProcessInfo.processInfo.environment["SCREENSHOT_CAPTURE"] == "1" else {
            throw XCTSkip("screenshot capture only runs with SCREENSHOT_CAPTURE=1")
        }
        continueAfterFailure = false
    }

    override func tearDownWithError() throws {
        MainActor.assumeIsolated { XCUIDevice.shared.orientation = .portrait }
    }

    /// One pass through the marketing states: onboarding choice, shared-link setup,
    /// two slideshow heroes, chrome, photo info, settings. Captures are attached
    /// full-screen; the heroes are reached via the `slideshow.image` value oracle.
    @MainActor
    func testCaptureAppStoreScreenshots() throws {
        let app = XCUIApplication()
        app.launch()
        XCUIDevice.shared.orientation = .landscapeLeft
        sleep(1)

        // 1 — first-run choice screen (requires a fresh install).
        let sharedLinkChoice = app.buttons["onboarding.choice.sharedLink"]
        XCTAssertTrue(sharedLinkChoice.waitForExistence(timeout: 10),
                      "expected the first-run choice screen — uninstall the app before capturing")
        attach(name: "01-onboarding-choice")
        sharedLinkChoice.tap()

        // 2 — shared-link setup, filled with the demo link, keyboard dismissed.
        let url = app.textFields["onboarding.sharedLink.url"]
        XCTAssertTrue(url.waitForExistence(timeout: 5))
        url.tap()
        url.typeText(Self.demoLink)
        dismissKeyboard(app)
        attach(name: "02-onboarding-sharedlink")
        app.buttons["onboarding.sharedLink.start"].tap()

        // 3 — slideshow running (live resolve + first image over the network).
        let image = app.descendants(matching: .any).matching(identifier: "slideshow.image").firstMatch
        XCTAssertTrue(image.waitForExistence(timeout: 60), "the demo link should start the slideshow")
        sleep(2)

        // 4 — hero 1: the chapel. Swipe (never reveals chrome) until the oracle matches.
        advance(image, to: Self.chapelAssetID)
        attach(name: "03-hero-chapel")

        // 5 — chrome over the chapel.
        revealChrome(app, image: image)
        attach(name: "04-chrome")

        // 6 — hero 2: the iceberg. Hide the chrome, swipe on.
        hideChrome(app, image: image)
        advance(image, to: Self.icebergAssetID)
        attach(name: "05-hero-iceberg")

        // 7 — settings sheet over the iceberg. The chrome auto-hide races taps on an
        // aged chrome, so re-reveal fresh and retry until the sheet's Done appears.
        let done = app.buttons["Done"]
        for _ in 0..<3 {
            if done.exists { break }
            revealChrome(app, image: image)
            app.buttons["slideshow.chrome.settings"].tap()
            _ = done.waitForExistence(timeout: 3)
        }
        XCTAssertTrue(done.exists, "the settings sheet should present")
        sleep(1)
        attach(name: "06-settings")
        done.tap()
        sleep(1)

        // 8 — photo info overlay over the iceberg (drone shot carries GPS), using the
        // overlay card as the oracle; date + location load async, give them a beat.
        let infoCard = app.descendants(matching: .any).matching(identifier: "slideshow.info.card").firstMatch
        for _ in 0..<3 {
            if infoCard.exists { break }
            revealChrome(app, image: image)
            app.buttons["slideshow.chrome.info"].tap()
            _ = infoCard.waitForExistence(timeout: 3)
        }
        XCTAssertTrue(infoCard.exists, "the photo info overlay should appear")
        sleep(2)
        attach(name: "07-photo-info")
    }

    // MARK: - Helpers

    /// Swipes forward until `slideshow.image`'s value reports the wanted asset id.
    /// Bounded by the album size; a short settle wait lets the crossfade finish.
    @MainActor
    private func advance(_ image: XCUIElement, to assetID: String, maxSwipes: Int = 45) {
        for _ in 0..<maxSwipes {
            if (image.value as? String) == assetID { break }
            image.swipeLeft()
            usleep(600_000)
        }
        XCTAssertEqual(image.value as? String, assetID, "expected to reach asset \(assetID)")
        sleep(3)
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

    @MainActor
    private func hideChrome(_ app: XCUIApplication, image: XCUIElement) {
        if app.buttons["slideshow.chrome.next"].isHittable {
            image.tap()
            usleep(800_000)
        }
    }

    /// Best-effort dismissal of the iPad keyboard (dedicated dismiss key). Falls
    /// back to leaving the keyboard up — the capture is still usable then.
    @MainActor
    private func dismissKeyboard(_ app: XCUIApplication) {
        let dismiss = app.keyboards.buttons.matching(
            NSPredicate(format: "label CONTAINS[c] 'hide' OR label CONTAINS[c] 'dismiss' OR label CONTAINS[c] 'ausblenden'")
        ).firstMatch
        if dismiss.exists {
            dismiss.tap()
            usleep(500_000)
        }
    }

    @MainActor
    private func attach(name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
