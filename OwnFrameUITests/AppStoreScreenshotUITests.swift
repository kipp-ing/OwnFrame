//
//  AppStoreScreenshotUITests.swift
//  OwnFrameUITests
//
//  App Store screenshot capture — NOT part of the test suite. Skips unless the
//  SCREENSHOT_CAPTURE=1 environment variable is set, because it runs the REAL app
//  (no --uitest stubs) against the live demo shared link and needs network access.
//  Run it alone on the iPad Pro 13" simulator after uninstalling the app (fresh
//  onboarding state), then export the attachments from the xcresult bundle:
//
//      xcrun xcresulttool export attachments --path <bundle>.xcresult --output-path <dir>
//
//  PORTRAIT (2026-08-25). The store set is portrait — iPad 13" 2064×2752, iPhone 6.9"
//  1320×2868 — so this rig no longer forces landscape, and the `sips -r 270` rotation
//  step the old landscape recipe needed is GONE: XCUIScreen returns the portrait pixel
//  buffer, which is now the orientation we actually want.
//
//  LOCALE. `SCREENSHOT_LOCALE=de` (or TEST_RUNNER_SCREENSHOT_LOCALE) re-runs the same
//  navigation in German; the default is English. de-DE previously shipped the English
//  captures because this rig could only produce them. Same mechanism as
//  GermanScreenshotSweepUITests — `-AppleLanguages` / `-AppleLocale` launch arguments,
//  which are plain NSUserDefaults overrides and independent of the --uitest seams.
//
//  WHAT THIS RIG IS FOR. Only the frames that need REAL photographs: the store set's
//  photo slots. Everything that is pure UI (the source-choice screen, the album picker —
//  neither renders a photo thumbnail) comes from the hermetic sweep instead, which is
//  faster, needs no network, and localizes for free. See docs/app-store-presentation.md.
//
//  The demo link and hero assets are the ones referenced in the App Review notes
//  (docs/app-store-listing.md): album "2021-06-Island best of", 38 images.
//

import XCTest

final class AppStoreScreenshotUITests: XCTestCase {

    private static let demoLink = "https://bilder.kippings.de/s/Iceland2021"

    /// The photo slots of the store set, in capture order, each targeted by an asset-id
    /// oracle on `slideshow.image`. Asset ids are device- and locale-independent.
    ///
    /// PLACEHOLDER PICKS: these are still the Iceland album's two heroes. The store set
    /// needs four photographs from the curated everyday/family album (slots 1, 2, 5, 6) —
    /// add the remaining ids here once that album's shared link exists, and point
    /// `demoLink` at it. The rig captures however many entries this list holds.
    private static let heroes: [(name: String, assetID: String)] = [
        ("01-hero-drawer", "87b68d06-03e7-4d9d-a07d-dd00171af601"),   // DSC05546, red-roof chapel
        ("02-hero-favourites", "a21c487a-802b-4be5-a1d5-62f3e41978dd"), // DJI_0371, iceberg drone shot
    ]

    /// English unless the runner asks for German. Mirrors GermanScreenshotSweepUITests.
    private static var locale: (language: String, locale: String) {
        let environment = ProcessInfo.processInfo.environment
        let requested = environment["SCREENSHOT_LOCALE"]
            ?? environment["TEST_RUNNER_SCREENSHOT_LOCALE"]
            ?? "en"
        return requested == "de" ? ("(de)", "de_DE") : ("(en)", "en_US")
    }

    override func setUpWithError() throws {
        guard ProcessInfo.processInfo.environment["SCREENSHOT_CAPTURE"] == "1" else {
            throw XCTSkip("screenshot capture only runs with SCREENSHOT_CAPTURE=1")
        }
        continueAfterFailure = false
    }

    override func tearDownWithError() throws {
        MainActor.assumeIsolated { XCUIDevice.shared.orientation = .portrait }
    }

    /// The store set's photo slots: onboard through the demo link, then walk to each hero
    /// and capture it full-screen with no chrome showing. This is the marketing critical
    /// path and is deliberately free of the chrome-reveal races that make the sheet
    /// captures below flaky — if those fail, these are already attached.
    @MainActor
    func testCaptureHeroPhotos() throws {
        let app = launch()
        let image = try startSlideshow(app)

        for hero in Self.heroes {
            advance(image, to: hero.assetID)
            attach(name: hero.name)
        }
    }

    /// Chrome, photo-info overlay and settings sheet over a live photo. Not part of the
    /// six-slot store set, kept because these are the only captures of those surfaces with
    /// a REAL photograph behind them (the hermetic sweep renders flat rectangles).
    ///
    /// Ordered so the settings sheet comes LAST and is never dismissed: its Done button
    /// carries no accessibility id and its label is localized, so tapping it would need a
    /// German string literal (which the english-only rule forbids) or an app change. Ending
    /// on the sheet sidesteps that entirely.
    @MainActor
    func testCaptureChromeAndSheets() throws {
        let app = launch()
        let image = try startSlideshow(app)
        guard let hero = Self.heroes.first else { return XCTFail("no hero configured") }
        advance(image, to: hero.assetID)

        revealChrome(app, image: image)
        attach(name: "20-chrome")

        // Date + location load async, give them a beat. The chrome auto-hide races taps on
        // an aged chrome, so re-reveal fresh and retry until the card appears.
        let infoCard = app.descendants(matching: .any).matching(identifier: "slideshow.info.card").firstMatch
        for _ in 0..<3 {
            if infoCard.exists { break }
            revealChrome(app, image: image)
            app.buttons["slideshow.chrome.info"].tap()
            _ = infoCard.waitForExistence(timeout: 3)
        }
        XCTAssertTrue(infoCard.exists, "the photo info overlay should appear")
        sleep(2)
        attach(name: "21-photo-info")

        let settings = app.buttons["slideshow.chrome.settings"]
        for _ in 0..<3 {
            revealChrome(app, image: image)
            settings.tap()
            if app.sliders.firstMatch.waitForExistence(timeout: 3) { break }
        }
        XCTAssertTrue(app.sliders.firstMatch.exists, "the settings sheet should present")
        sleep(1)
        attach(name: "22-settings")
    }

    // MARK: - Launch + onboarding

    /// See FR-9010-34: the shipped captures are taken at an enlarged Dynamic Type size so a
    /// truncated string cannot reach the store page. `-UIPreferredContentSizeCategoryName` is a
    /// plain NSUserDefaults override in the same class as `-AppleLanguages`, so no app-source
    /// change is needed. Pass a full category name, e.g. `UICTContentSizeCategoryXXL`; unset
    /// means the device default.
    private static var textSizeArguments: [String] {
        let environment = ProcessInfo.processInfo.environment
        guard let requested = environment["SCREENSHOT_TEXT_SIZE"]
            ?? environment["TEST_RUNNER_SCREENSHOT_TEXT_SIZE"],
              !requested.isEmpty
        else { return [] }
        return ["-UIPreferredContentSizeCategoryName", Self.contentSizeCategory(requested)]
    }

    /// The raw values UIKit actually accepts. The preference silently ignores anything else and
    /// renders the whole run at the default size while still reporting success — a false green
    /// this rig must not allow, because the resulting captures look plausible and are wrong.
    /// The trap that cost a capture run: the accessibility categories end in `M`/`L`/`XL`, so
    /// `UICTContentSizeCategoryAccessibilityMedium` is not a category at all.
    private static let knownContentSizeCategories: Set<String> = [
        "XS", "S", "M", "L", "XL", "XXL", "XXXL",
        "AccessibilityM", "AccessibilityL", "AccessibilityXL",
        "AccessibilityXXL", "AccessibilityXXXL",
    ]

    /// Accepts either a full `UICTContentSizeCategory…` value or its bare suffix (`XXL`,
    /// `AccessibilityM`), and traps on anything UIKit would drop on the floor.
    private static func contentSizeCategory(_ requested: String) -> String {
        let prefix = "UICTContentSizeCategory"
        let suffix = requested.hasPrefix(prefix) ? String(requested.dropFirst(prefix.count)) : requested
        guard knownContentSizeCategories.contains(suffix) else {
            preconditionFailure("""
                SCREENSHOT_TEXT_SIZE=\(requested) is not a Dynamic Type category. UIKit would \
                ignore it silently and capture at the default size. Use one of: \
                \(knownContentSizeCategories.sorted().joined(separator: ", ")) — \
                bare or prefixed with \(prefix).
                """)
        }
        return prefix + suffix
    }

    @MainActor
    private func launch() -> XCUIApplication {
        let app = XCUIApplication()
        let locale = Self.locale
        app.launchArguments = ["-AppleLanguages", locale.language, "-AppleLocale", locale.locale]
            + Self.textSizeArguments
        app.launch()
        XCUIDevice.shared.orientation = .portrait
        sleep(1)
        return app
    }

    /// Fresh-install onboarding through the demo shared link, up to the first live image.
    @MainActor
    private func startSlideshow(_ app: XCUIApplication) throws -> XCUIElement {
        let sharedLinkChoice = app.buttons["onboarding.choice.sharedLink"]
        XCTAssertTrue(sharedLinkChoice.waitForExistence(timeout: 10),
                      "expected the first-run choice screen — uninstall the app before capturing")
        sharedLinkChoice.tap()

        let url = app.textFields["onboarding.sharedLink.url"]
        XCTAssertTrue(url.waitForExistence(timeout: 5))
        url.tap()
        url.typeText(Self.demoLink)
        dismissKeyboard(app)
        app.buttons["onboarding.sharedLink.start"].tap()

        let image = app.descendants(matching: .any).matching(identifier: "slideshow.image").firstMatch
        XCTAssertTrue(image.waitForExistence(timeout: 60), "the demo link should start the slideshow")
        sleep(2)
        return image
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

    /// Best-effort keyboard dismissal: the iPad's dedicated dismiss key when present,
    /// otherwise return (ends editing on the URL field — the iPhone keyboard has no
    /// dismiss key, and a visible keyboard would also expose the sim's stubborn
    /// German QWERTZ layout in an English listing).
    @MainActor
    private func dismissKeyboard(_ app: XCUIApplication) {
        let dismiss = app.keyboards.buttons.matching(
            NSPredicate(format: "label CONTAINS[c] 'hide' OR label CONTAINS[c] 'dismiss' OR label CONTAINS[c] 'ausblenden'")
        ).firstMatch
        if dismiss.exists {
            dismiss.tap()
        } else if app.keyboards.firstMatch.exists {
            app.typeText("\n")
        }
        usleep(500_000)
    }

    @MainActor
    private func attach(name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
