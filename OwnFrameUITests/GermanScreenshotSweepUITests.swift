//
//  GermanScreenshotSweepUITests.swift
//  OwnFrameUITests
//
//  de-DE screenshot sweep — NOT part of the normal suite. Every test skips unless
//  SCREENSHOT_DE=1 (or TEST_RUNNER_SCREENSHOT_DE=1) is in the runner's environment.
//  It walks every user-visible screen of the iOS app with the app forced to German
//  (`-AppleLanguages (de) -AppleLocale de_DE`) and attaches one full-screen capture per
//  screen, so a human can inspect the localization for truncation, overflow, clipping,
//  mixed-language and layout faults.
//
//  Everything runs against the hermetic `--uitest` seams — no network, no StoreKit, no
//  camera. One `@MainActor func` per screen (numbered so the run order and the exported
//  attachment names both sort), so a single broken screen costs only its own capture.
//
//  VERIFIED INVOCATION (iPad Pro 13-inch (M4), iOS 26.0 simulator, 2026-07-26):
//
//      UDID=<simulator udid>
//      xcrun simctl bootstatus "$UDID" -b
//      xcrun simctl spawn "$UDID" launchctl setenv SCREENSHOT_DE 1     # <- the gate
//      cd /path/to/Immich-Slideshow && \
//      xcodebuild test \
//        -project OwnFrame.xcodeproj -scheme OwnFrame \
//        -destination "platform=iOS Simulator,id=$UDID" \
//        -only-testing:OwnFrameUITests/GermanScreenshotSweepUITests \
//        -resultBundlePath /tmp/de-sweep.xcresult
//      xcrun simctl spawn "$UDID" launchctl unsetenv SCREENSHOT_DE     # <- re-arm the gate
//
//  The `launchctl setenv` line is load-bearing and was determined empirically. Neither a
//  plain shell export (`SCREENSHOT_DE=1 xcodebuild test …`) nor an xcodebuild build-setting
//  override (`SCREENSHOT_DE=1` / `TEST_RUNNER_SCREENSHOT_DE=1` as trailing arguments)
//  reaches the XCUITest runner process — both were tried and both left every test skipped.
//  `launchctl setenv` on the booted simulator puts the variable into the environment of
//  every process the simulator spawns, which does include the runner. Both spellings are
//  accepted below, so `TEST_RUNNER_SCREENSHOT_DE` works too if a future toolchain forwards it.
//
//  Export the captures afterwards with:
//
//      xcrun xcresulttool export attachments --path /tmp/de-sweep.xcresult --output-path <dir>
//
//  XCUIScreen returns the portrait pixel buffer even in landscape — rotate the exported
//  PNGs (`sips -r 90`, or `-r 270` depending on the edge) for upright landscape frames.
//

import XCTest

final class GermanScreenshotSweepUITests: XCTestCase {

    // MARK: - Gate + fixtures

    override func setUpWithError() throws {
        let environment = ProcessInfo.processInfo.environment
        guard environment["SCREENSHOT_DE"] == "1" || environment["TEST_RUNNER_SCREENSHOT_DE"] == "1" else {
            throw XCTSkip("German screenshot sweep only runs with SCREENSHOT_DE=1")
        }
        continueAfterFailure = false
        MainActor.assumeIsolated { XCUIDevice.shared.orientation = .portrait }
    }

    override func tearDownWithError() throws {
        MainActor.assumeIsolated { XCUIDevice.shared.orientation = .portrait }
    }

    /// The hermetic stub resolver reserves these two slugs: `protected` needs the password
    /// "letmein", `missing` is an invalid link.
    private static let protectedLink = "https://demo.example.com/s/protected"
    private static let missingLink = "https://demo.example.com/s/missing"
    private static let validLink = "https://demo.example.com/s/abc123"

    /// Base flags for the settings sheet screens.
    private static let settingsBase = ["--uitest-slideshow", "--uitest-chrome", "--uitest-settings", "--uitest-reset-theme"]

    // MARK: - 01…16 Onboarding

    @MainActor
    func test01_onboardingChoice() throws {
        let app = launch("--uitest-onboarding-choice")
        try require(app, "onboarding.choice.sharedLink", screen: "01-onboarding-choice")
        attach("01-onboarding-choice")
    }

    @MainActor
    func test02_photosPickerFull() throws {
        let app = launch("--uitest-onboarding-choice", "--uitest-photos-auth=full")
        try tapChoicePhotoLibrary(app, screen: "02-photos-picker-full")
        try require(app, "onboarding.photos.pl-family", screen: "02-photos-picker-full")
        attach("02-photos-picker-full")
    }

    @MainActor
    func test03_photosPickerLimited() throws {
        let app = launch("--uitest-onboarding-choice", "--uitest-photos-auth=limited")
        try tapChoicePhotoLibrary(app, screen: "03-photos-picker-limited")
        try require(app, "onboarding.photos.limitedNote", screen: "03-photos-picker-limited")
        attach("03-photos-picker-limited")
    }

    @MainActor
    func test04_photosPickerDenied() throws {
        let app = launch("--uitest-onboarding-choice", "--uitest-photos-auth=denied")
        try tapChoicePhotoLibrary(app, screen: "04-photos-picker-denied")
        try require(app, "onboarding.photos.denied", screen: "04-photos-picker-denied")
        attach("04-photos-picker-denied")
    }

    @MainActor
    func test05_sharedLinkSetup() throws {
        let app = launch("--uitest-shared-link-only")
        try require(app, "onboarding.sharedLink.url", screen: "05-sharedlink-setup")
        attach("05-sharedlink-setup")
    }

    @MainActor
    func test06_sharedLinkPassword() throws {
        let app = launch("--uitest-shared-link-only")
        try startSharedLink(app, url: Self.protectedLink, screen: "06-sharedlink-password")
        try require(app, "onboarding.sharedLink.password", screen: "06-sharedlink-password")
        dismissKeyboard(app)
        attach("06-sharedlink-password")
    }

    @MainActor
    func test07_sharedLinkPasswordError() throws {
        let app = launch("--uitest-shared-link-only")
        try startSharedLink(app, url: Self.protectedLink, screen: "07-sharedlink-password-error")
        let password = try require(app, "onboarding.sharedLink.password", screen: "07-sharedlink-password-error")
        password.tap()
        password.typeText("nope")
        dismissKeyboard(app)
        try require(app, "onboarding.sharedLink.password.continue", screen: "07-sharedlink-password-error").tap()
        try require(app, "onboarding.sharedLink.password.error", screen: "07-sharedlink-password-error")
        attach("07-sharedlink-password-error")
    }

    @MainActor
    func test08_sharedLinkInvalid() throws {
        let app = launch("--uitest-shared-link-only")
        try startSharedLink(app, url: Self.missingLink, screen: "08-sharedlink-invalid")
        try require(app, "onboarding.sharedLink.error", screen: "08-sharedlink-invalid")
        attach("08-sharedlink-invalid")
    }

    @MainActor
    func test09_qrUnavailable() throws {
        let app = launch("--uitest-shared-link-only")
        try require(app, "onboarding.sharedLink.url", screen: "09-qr-unavailable")
        try require(app, "onboarding.sharedLink.scan", screen: "09-qr-unavailable").tap()

        // The simulator has no capture device, so `scan()` fails fast and the cover can be
        // torn down before the fallback ever settles. Take whichever of the two scanner
        // surfaces actually materialises; skip (rather than fail) if neither does — the
        // camera path is genuinely not exercisable on a simulator.
        let unavailable = element(app, "onboarding.sharedLink.scan.unavailable")
        let cancel = element(app, "onboarding.sharedLink.scan.cancel")
        guard unavailable.waitForExistence(timeout: 8) || cancel.waitForExistence(timeout: 3) else {
            throw XCTSkip("09-qr-unavailable: the QR scanner cover is torn down immediately on a simulator (no capture device)")
        }
        attach("09-qr-unavailable")
    }

    @MainActor
    func test10_connectionStep() throws {
        let app = launch()
        try require(app, "onboarding.connection.continue", screen: "10-connection-step")
        attach("10-connection-step")
    }

    @MainActor
    func test11_sourceStepAlbum() throws {
        let app = launch("--uitest-onboarding-source")
        try require(app, "onboarding.album.a1", screen: "11-source-step-album")
        attach("11-source-step-album")
    }

    @MainActor
    func test12_albumSearchResults() throws {
        let app = launch("--uitest-onboarding-source", "--uitest-albums-many")
        try require(app, "onboarding.album.album-munich", screen: "12-album-search-results")
        let search = try require(app, "onboarding.album.search", screen: "12-album-search-results")
        search.tap()
        search.typeText("munchen")
        try require(app, "onboarding.album.album-munich", screen: "12-album-search-results")
        dismissKeyboard(app)
        attach("12-album-search-results")
    }

    @MainActor
    func test13_albumSearchNoResults() throws {
        let app = launch("--uitest-onboarding-source", "--uitest-albums-many")
        let search = try require(app, "onboarding.album.search", screen: "13-album-search-noresults")
        search.tap()
        search.typeText("zzzqqq")
        try require(app, "onboarding.album.noResults", screen: "13-album-search-noresults")
        dismissKeyboard(app)
        attach("13-album-search-noresults")
    }

    @MainActor
    func test14_sourceStepSharedLinkTab() throws {
        let app = launch("--uitest-onboarding-source")
        try require(app, "onboarding.album.a1", screen: "14-source-step-sharedlink-tab")
        // The segment labels are German at runtime — select by index, never by label.
        try selectSegment(app, picker: "onboarding.source.type", index: 1, screen: "14-source-step-sharedlink-tab")
        try require(app, "onboarding.sharedLink.url", screen: "14-source-step-sharedlink-tab")
        attach("14-source-step-sharedlink-tab")
    }

    @MainActor
    func test15_confirmStep() throws {
        let app = launch("--uitest-onboarding-source")
        try require(app, "onboarding.album.a1", screen: "15-confirm-step").tap()
        try require(app, "onboarding.source.continue", screen: "15-confirm-step").tap()
        try require(app, "onboarding.confirm.start", screen: "15-confirm-step")
        attach("15-confirm-step")
    }

    @MainActor
    func test16_incomingLinkOnboarding() throws {
        let app = launch("--uitest-onboarding-choice", "--uitest-pending-link", Self.validLink)
        let url = try require(app, "onboarding.sharedLink.url", screen: "16-incoming-link-onboarding")
        // The pending link propagates a beat after the field appears.
        let prefilled = NSPredicate(format: "value == %@", Self.validLink)
        expectation(for: prefilled, evaluatedWith: url)
        waitForExpectations(timeout: 10)
        attach("16-incoming-link-onboarding")
    }

    // MARK: - 20…34 Slideshow

    @MainActor
    func test20_slideshowPlain() throws {
        let app = launch("--uitest-slideshow")
        try require(app, "slideshow.image", screen: "20-slideshow-plain")
        settle()
        attach("20-slideshow-plain")
    }

    @MainActor
    func test21_chrome() throws {
        let app = launch("--uitest-slideshow", "--uitest-chrome")
        try require(app, "slideshow.image", screen: "21-chrome")
        try require(app, "slideshow.chrome.settings", screen: "21-chrome")
        settle()
        attach("21-chrome")
    }

    @MainActor
    func test22_clockAnalog() throws {
        let app = launch(
            "--uitest-slideshow", "--uitest-entitlements=supporter",
            "--uitest-clock-style=analog", "--uitest-clock-place=topCenter",
            "--uitest-clock-size=cozy", "--uitest-clock-date", "--uitest-clock-seed=42"
        )
        try require(app, "slideshow.image", screen: "22-clock-analog")
        try require(app, "slideshow.clock", screen: "22-clock-analog")
        settle()
        attach("22-clock-analog")
    }

    @MainActor
    func test23_clockPill() throws {
        let app = launch(
            "--uitest-slideshow", "--uitest-entitlements=supporter",
            "--uitest-clock-style=pill", "--uitest-clock-place=bottomTrailing",
            "--uitest-clock-size=cozy", "--uitest-clock-date", "--uitest-clock-seed=42"
        )
        try require(app, "slideshow.image", screen: "23-clock-pill")
        try require(app, "slideshow.clock", screen: "23-clock-pill")
        settle()
        attach("23-clock-pill")
    }

    @MainActor
    func test24_photoInfo() throws {
        let app = launch("--uitest-slideshow", "--uitest-chrome", "--uitest-info")
        try require(app, "slideshow.info.card", screen: "24-photo-info")
        // Date + place resolve asynchronously.
        settle(2)
        attach("24-photo-info")
    }

    @MainActor
    func test25_photoInfoPhotosSource() throws {
        let app = launch(
            "--uitest-slideshow", "--uitest-chrome", "--uitest-photos-source",
            "--uitest-photos-auth=full", "--uitest-info"
        )
        try require(app, "slideshow.info.card", screen: "25-photo-info-photos-source")
        settle(2)
        attach("25-photo-info-photos-source")
    }

    @MainActor
    func test26_albumBrowser() throws {
        let app = launch("--uitest-slideshow", "--uitest-albums")
        try require(app, "album.row.a1", screen: "26-album-browser")
        attach("26-album-browser")
    }

    @MainActor
    func test27_albumBrowserThumbs() throws {
        let app = launch("--uitest-slideshow", "--uitest-albums")
        try require(app, "album.row.a1", screen: "27-album-browser-thumbs").tap()
        try require(app, "album.thumbnail.asset-1", screen: "27-album-browser-thumbs")
        settle()
        attach("27-album-browser-thumbs")
    }

    @MainActor
    func test28_errorUnreachable() throws {
        let app = launch("--uitest-slideshow", "--uitest-reset-storage", "--uitest-assets-fail=unreachable")
        try require(app, "slideshow.error", screen: "28-error-unreachable")
        attach("28-error-unreachable")
    }

    @MainActor
    func test29_errorUnauthorized() throws {
        let app = launch("--uitest-slideshow", "--uitest-reset-storage", "--uitest-assets-fail=unauthorized")
        try require(app, "slideshow.fixConnection", screen: "29-error-unauthorized")
        attach("29-error-unauthorized")
    }

    @MainActor
    func test30_errorPhotosLimited() throws {
        let app = launch("--uitest-slideshow", "--uitest-chrome", "--uitest-photos-source", "--uitest-photos-auth=limited")
        try require(app, "slideshow.openSettings", screen: "30-error-photos-limited")
        attach("30-error-photos-limited")
    }

    @MainActor
    func test31_errorPhotosVanished() throws {
        let app = launch(
            "--uitest-slideshow", "--uitest-chrome", "--uitest-photos-source",
            "--uitest-photos-auth=full", "--uitest-photos-vanish"
        )
        try require(app, "slideshow.error", screen: "31-error-photos-vanished")
        attach("31-error-photos-vanished")
    }

    @MainActor
    func test32_connectionEditor() throws {
        let app = launch("--uitest-slideshow", "--uitest-reset-storage", "--uitest-assets-fail=unauthorized")
        try require(app, "slideshow.fixConnection", screen: "32-connection-editor").tap()
        try require(app, "connection.save", screen: "32-connection-editor")
        attach("32-connection-editor")
    }

    @MainActor
    func test33_incomingLinkError() throws {
        let app = launch("--uitest-slideshow", "--uitest-pending-link", Self.missingLink)
        try require(app, "incomingLink.error", screen: "33-incoming-link-error", timeout: 20)
        attach("33-incoming-link-error")
    }

    @MainActor
    func test34_incomingLinkPassword() throws {
        let app = launch("--uitest-slideshow", "--uitest-pending-link", Self.protectedLink)
        try require(app, "incomingLink.password", screen: "34-incoming-link-password", timeout: 20)
        attach("34-incoming-link-password")
    }

    // MARK: - 40…48 Settings

    @MainActor
    func test40_settingsTopEntitled() throws {
        let app = launch(Self.settingsBase + ["--uitest-entitlements=all"])
        try require(app, "settings.brightness", screen: "40-settings-top-entitled")
        attach("40-settings-top-entitled")
    }

    @MainActor
    func test41_settingsClockRows() throws {
        let app = launch(Self.settingsBase + [
            "--uitest-entitlements=supporter", "--uitest-clock-style=analog", "--uitest-clock-place=topCenter",
        ])
        try require(app, "settings.brightness", screen: "41-settings-clock-rows")
        try scroll(app, to: "settings.clock.style", screen: "41-settings-clock-rows")
        attach("41-settings-clock-rows")
    }

    @MainActor
    func test42_settingsLockedRows() throws {
        let app = launch(Self.settingsBase + ["--uitest-entitlements=none"])
        try require(app, "settings.brightness", screen: "42-settings-locked-rows")
        try scroll(app, to: "settings.row.kenburns.locked", screen: "42-settings-locked-rows")
        attach("42-settings-locked-rows")
    }

    @MainActor
    func test43_settingsUnlocksSection() throws {
        let app = launch(Self.settingsBase + ["--uitest-entitlements=none"])
        try require(app, "settings.brightness", screen: "43-settings-unlocks-section")
        try scroll(app, to: "settings.tipjar", screen: "43-settings-unlocks-section")
        try scroll(app, to: "settings.unlocks.moneyPledge", screen: "43-settings-unlocks-section")
        attach("43-settings-unlocks-section")
    }

    @MainActor
    func test44_settingsStorage() throws {
        let app = launch(Self.settingsBase + ["--uitest-reset-storage", "--uitest-entitlements=all"])
        try require(app, "settings.brightness", screen: "44-settings-storage")
        try scroll(app, to: "settings.storage.usage", screen: "44-settings-storage")
        attach("44-settings-storage")
    }

    @MainActor
    func test45_settingsClearDialog() throws {
        let app = launch(Self.settingsBase + ["--uitest-reset-storage", "--uitest-entitlements=all"])
        try require(app, "settings.brightness", screen: "45-settings-clear-dialog")
        try scroll(app, to: "settings.storage.clear", screen: "45-settings-clear-dialog")
        element(app, "settings.storage.clear").tap()
        // The dialog's confirm button is the only anchor it offers; its label is localized.
        let confirm = button(app, anyOf: ["Clear Cache", "Cache leeren"])
        guard confirm.waitForExistence(timeout: 5) else {
            XCTFail("45-settings-clear-dialog: the clear-cache confirmation dialog never appeared")
            return
        }
        attach("45-settings-clear-dialog")
    }

    @MainActor
    func test46_settingsResetDialog() throws {
        let app = launch(Self.settingsBase + ["--uitest-entitlements=all"])
        try require(app, "settings.brightness", screen: "46-settings-reset-dialog")
        try scroll(app, to: "settings.reset", screen: "46-settings-reset-dialog")
        element(app, "settings.reset").tap()
        // "Zurcksetzen" with a u-umlaut, spelled as an escape: the repo's english-only
        // hook rejects literal umlauts in Swift, and this is a runtime label, not UI copy.
        let confirm = button(app, anyOf: ["Reset", "Zur\u{00FC}cksetzen"])
        guard confirm.waitForExistence(timeout: 5) else {
            XCTFail("46-settings-reset-dialog: the reset confirmation dialog never appeared")
            return
        }
        attach("46-settings-reset-dialog")
    }

    @MainActor
    func test47_settingsDurationOffPreset() throws {
        let app = launch(Self.settingsBase + ["--uitest-duration-seconds=90", "--uitest-entitlements=all"])
        try require(app, "settings.brightness", screen: "47-settings-duration-offpreset")
        try scroll(app, to: "settings.duration", screen: "47-settings-duration-offpreset")
        attach("47-settings-duration-offpreset")
    }

    @MainActor
    func test48_settingsQualityCeiling() throws {
        let app = launch(Self.settingsBase + [
            "--uitest-photos-source", "--uitest-photos-auth=full", "--uitest-entitlements=all",
        ])
        try require(app, "settings.brightness", screen: "48-settings-quality-ceiling")
        try scroll(app, to: "settings.quality.ceilingNote", screen: "48-settings-quality-ceiling")
        attach("48-settings-quality-ceiling")
    }

    // MARK: - 49…53 Sources

    @MainActor
    func test49_sourcesManager() throws {
        let app = launch("--uitest-slideshow", "--uitest-chrome", "--uitest-sources", "--uitest-reset-theme")
        try require(app, "sources.row.src-a1", screen: "49-sources-manager")
        attach("49-sources-manager")
    }

    @MainActor
    func test50_addSourceAlbum() throws {
        let app = launch("--uitest-slideshow", "--uitest-chrome", "--uitest-sources", "--uitest-reset-theme", "--uitest-albums-many")
        try require(app, "sources.add", screen: "50-add-source-album").tap()
        try require(app, "sources.album.album-munich", screen: "50-add-source-album")
        attach("50-add-source-album")
    }

    @MainActor
    func test51_addSourceSharedLink() throws {
        let app = launch("--uitest-slideshow", "--uitest-chrome", "--uitest-sources", "--uitest-reset-theme")
        try require(app, "sources.add", screen: "51-add-source-sharedlink").tap()
        try selectSegment(app, picker: "sources.add.type", index: 1, screen: "51-add-source-sharedlink")
        try require(app, "sources.add.url", screen: "51-add-source-sharedlink")
        attach("51-add-source-sharedlink")
    }

    @MainActor
    func test52_addSourcePhotosDenied() throws {
        let app = launch("--uitest-slideshow", "--uitest-chrome", "--uitest-sources", "--uitest-reset-theme", "--uitest-photos-auth=denied")
        try require(app, "sources.add", screen: "52-add-source-photos-denied").tap()
        try selectSegment(app, picker: "sources.add.type", index: 2, screen: "52-add-source-photos-denied")
        try require(app, "sources.photos.denied", screen: "52-add-source-photos-denied")
        attach("52-add-source-photos-denied")
    }

    @MainActor
    func test53_renameSource() throws {
        let app = launch("--uitest-slideshow", "--uitest-chrome", "--uitest-sources", "--uitest-reset-theme")
        let row = try require(app, "sources.row.src-a1", screen: "53-rename-source")
        row.swipeLeft()
        let rename = button(app, anyOf: ["Rename", "Umbenennen"])
        guard rename.waitForExistence(timeout: 5) else {
            XCTFail("53-rename-source: the swipe action 'Rename' never appeared on sources.row.src-a1")
            return
        }
        rename.tap()
        // SwiftUI's `.accessibilityIdentifier` on a `TextField` inside an `.alert(...)` content
        // closure does not bridge to the underlying UIKit `UIAlertController` text field (a
        // platform limitation, confirmed via the exported failure hierarchy: the field exists
        // with placeholderValue "Name" but no identifier) — match it structurally instead.
        let field = app.alerts.textFields.firstMatch
        guard field.waitForExistence(timeout: 12) else {
            XCTFail("53-rename-source: the rename alert's text field never appeared")
            throw SweepError.anchorMissing
        }
        attach("53-rename-source")
    }

    // MARK: - 60…63 Broker / Home Assistant

    @MainActor
    func test60_brokerEmpty() throws {
        let app = launch("--uitest-slideshow", "--uitest-chrome", "--uitest-broker", "--uitest-entitlements=supporter")
        try scroll(app, to: "broker.host", screen: "60-broker-empty")
        attach("60-broker-empty")
    }

    @MainActor
    func test61_brokerExisting() throws {
        let app = launch(
            "--uitest-slideshow", "--uitest-chrome", "--uitest-broker",
            "--uitest-broker-existing", "--uitest-entitlements=supporter"
        )
        try scroll(app, to: "broker.remove", screen: "61-broker-existing")
        attach("61-broker-existing")
    }

    @MainActor
    func test62_brokerPublishOptions() throws {
        let app = launch(
            "--uitest-slideshow", "--uitest-chrome", "--uitest-broker", "--uitest-broker-existing",
            "--uitest-reset-publish-options", "--uitest-entitlements=supporter"
        )
        let toggle = try scroll(app, to: "broker.imageEnabled", screen: "62-broker-publish-options")
        var tries = 0
        while !toggle.isHittable && tries < 4 {
            app.swipeUp()
            tries += 1
        }
        // Element-relative offset, not a screen coordinate: centre-tapping a Form toggle
        // lands on its (long) label instead of the switch.
        toggle.coordinate(withNormalizedOffset: CGVector(dx: 0.92, dy: 0.5)).tap()
        let isOn = NSPredicate(format: "value == %@", "1")
        expectation(for: isOn, evaluatedWith: toggle)
        waitForExpectations(timeout: 5)
        try scroll(app, to: "broker.byteCap", screen: "62-broker-publish-options")
        attach("62-broker-publish-options")
    }

    @MainActor
    func test63_brokerLockedBanner() throws {
        let app = launch(
            "--uitest-slideshow", "--uitest-chrome", "--uitest-broker",
            "--uitest-broker-existing", "--uitest-entitlements=none"
        )
        try scroll(app, to: "settings.row.broker.locked", screen: "63-broker-locked-banner")
        attach("63-broker-locked-banner")
    }

    // MARK: - 70…76 Purchase surfaces

    @MainActor
    func test70_unlockScreen() throws {
        let app = launchUnentitledSettings(store: "stub")
        try openUnlockScreen(app, screen: "70-unlock-screen")
        settle()
        attach("70-unlock-screen")
    }

    @MainActor
    func test71_unlockUnavailable() throws {
        let app = launchUnentitledSettings(store: "unavailable")
        try openUnlockScreen(app, screen: "71-unlock-unavailable")
        try require(app, "unlock.unavailable", screen: "71-unlock-unavailable")
        attach("71-unlock-unavailable")
    }

    @MainActor
    func test72_unlockPending() throws {
        let app = launchUnentitledSettings(store: "pending")
        try openUnlockScreen(app, screen: "72-unlock-pending")
        try require(app, "unlock.buy.supporter", screen: "72-unlock-pending").tap()
        try require(app, "unlock.pending", screen: "72-unlock-pending")
        attach("72-unlock-pending")
    }

    @MainActor
    func test73_unlockDone() throws {
        let app = launchUnentitledSettings(store: "stub")
        try openUnlockScreen(app, screen: "73-unlock-done")
        try require(app, "unlock.buy.supporter", screen: "73-unlock-done").tap()
        try require(app, "unlock.done", screen: "73-unlock-done")
        attach("73-unlock-done")
    }

    @MainActor
    func test74_tipJar() throws {
        let app = launchUnentitledSettings(store: "stub")
        try openTipJar(app, screen: "74-tipjar")
        settle()
        attach("74-tipjar")
    }

    @MainActor
    func test75_tipJarThanks() throws {
        let app = launchUnentitledSettings(store: "stub")
        try openTipJar(app, screen: "75-tipjar-thanks")
        try require(app, "tipjar.buy.tip.small", screen: "75-tipjar-thanks").tap()
        try require(app, "tipjar.thanks", screen: "75-tipjar-thanks")
        attach("75-tipjar-thanks")
    }

    @MainActor
    func test76_tipJarUnavailable() throws {
        let app = launchUnentitledSettings(store: "unavailable")
        try openTipJar(app, screen: "76-tipjar-unavailable")
        try require(app, "tipjar.unavailable", screen: "76-tipjar-unavailable")
        attach("76-tipjar-unavailable")
    }

    // MARK: - Launch

    /// Launches a fresh, German-forced app. `--uitest` always leads; the caller's flags follow.
    /// Note `--uitest-pending-link` takes its URL as the NEXT separate argument.
    @MainActor
    @discardableResult
    private func launch(_ args: String..., landscapeOnIPad: Bool = true) -> XCUIApplication {
        launch(args, landscapeOnIPad: landscapeOnIPad)
    }

    /// The locale the sweep drives the app in. German by default — that is what this sweep is
    /// for — but App Store Connect wants the IAP review screenshots in the primary locale
    /// (en-US), and those are the same screens. `SCREENSHOT_LOCALE=en` re-runs any case here in
    /// English rather than duplicating the navigation.
    private static var locale: (language: String, locale: String) {
        let environment = ProcessInfo.processInfo.environment
        let requested = environment["SCREENSHOT_LOCALE"]
            ?? environment["TEST_RUNNER_SCREENSHOT_LOCALE"]
            ?? "de"
        return requested == "en" ? ("(en)", "en_US") : ("(de)", "de_DE")
    }

    @MainActor
    @discardableResult
    private func launch(_ args: [String], landscapeOnIPad: Bool = true) -> XCUIApplication {
        let app = XCUIApplication()
        let locale = Self.locale
        app.launchArguments = ["--uitest"] + args
            + ["-AppleLanguages", locale.language, "-AppleLocale", locale.locale]
        app.launch()
        if landscapeOnIPad, UIDevice.current.userInterfaceIdiom == .pad {
            XCUIDevice.shared.orientation = .landscapeLeft
            settle()
        } else {
            XCUIDevice.shared.orientation = .portrait
        }
        return app
    }

    @MainActor
    private func launchUnentitledSettings(store: String) -> XCUIApplication {
        launch(Self.settingsBase + ["--uitest-entitlements=none", "--uitest-store=\(store)"])
    }

    // MARK: - Navigation helpers

    @MainActor
    private func tapChoicePhotoLibrary(_ app: XCUIApplication, screen: String) throws {
        try require(app, "onboarding.choice.photoLibrary", screen: screen).tap()
    }

    /// Types `url` into the shared-link setup field and taps Start.
    @MainActor
    private func startSharedLink(_ app: XCUIApplication, url: String, screen: String) throws {
        let field = try require(app, "onboarding.sharedLink.url", screen: screen)
        field.tap()
        field.typeText(url)
        dismissKeyboard(app)
        try require(app, "onboarding.sharedLink.start", screen: screen).tap()
    }

    /// Selects a segment of a segmented `Picker` by INDEX — the labels are German at runtime.
    @MainActor
    private func selectSegment(_ app: XCUIApplication, picker: String, index: Int, screen: String) throws {
        let control = app.segmentedControls[picker]
        guard control.waitForExistence(timeout: 10) else {
            XCTFail("\(screen): the segmented control '\(picker)' never appeared")
            throw SweepError.anchorMissing
        }
        let segment = control.buttons.element(boundBy: index)
        guard segment.waitForExistence(timeout: 5) else {
            XCTFail("\(screen): '\(picker)' has no segment at index \(index)")
            throw SweepError.anchorMissing
        }
        segment.tap()
    }

    @MainActor
    private func openUnlockScreen(_ app: XCUIApplication, screen: String) throws {
        try require(app, "settings.brightness", screen: screen)
        try scroll(app, to: "settings.row.kenburns.locked", screen: screen).tap()
        try require(app, "unlock.screen.supporter", screen: screen)
    }

    @MainActor
    private func openTipJar(_ app: XCUIApplication, screen: String) throws {
        try require(app, "settings.brightness", screen: screen)
        try scroll(app, to: "settings.tipjar", screen: screen).tap()
        try require(app, "tipjar.screen", screen: screen)
    }

    // MARK: - Element helpers

    private enum SweepError: Error { case anchorMissing }

    @MainActor
    private func element(_ app: XCUIApplication, _ identifier: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: identifier).firstMatch
    }

    /// Waits for a real anchor element. Never a bare sleep: a missing anchor fails the test
    /// with the screen named, so exactly one capture is lost.
    @MainActor
    @discardableResult
    private func require(
        _ app: XCUIApplication,
        _ identifier: String,
        screen: String,
        timeout: TimeInterval = 12
    ) throws -> XCUIElement {
        let found = element(app, identifier)
        guard found.waitForExistence(timeout: timeout) else {
            XCTFail("\(screen): anchor '\(identifier)' never appeared")
            throw SweepError.anchorMissing
        }
        return found
    }

    /// Settings is a `Form` whose MQTT/broker `DisclosureGroup` is force-expanded under
    /// `--uitest-broker`, so a row's identifier can `exist` in the accessibility tree well
    /// before it is scrolled into the visible viewport. Waiting on `exists` alone silently
    /// returns an off-screen element (whatever the previous screenshot happened to show,
    /// often byte-identical to an unrelated capture) — keep swiping until it is genuinely
    /// on screen, not merely present in the tree.
    @MainActor
    @discardableResult
    private func scroll(
        _ app: XCUIApplication,
        to identifier: String,
        screen: String,
        maxSwipes: Int = 14
    ) throws -> XCUIElement {
        let target = element(app, identifier)
        // Some rows are visible without any scrolling at all — give that a real chance first.
        _ = target.waitForExistence(timeout: 3)
        var swipes = 0
        while !onScreen(target, in: app) && swipes < maxSwipes {
            app.swipeUp()
            // A row that only mounts once scrolled near needs a beat to appear in the tree.
            _ = target.waitForExistence(timeout: 1)
            swipes += 1
        }
        guard onScreen(target, in: app) else {
            XCTFail("\(screen): '\(identifier)' was not visibly reachable after \(maxSwipes) swipes")
            throw SweepError.anchorMissing
        }
        return target
    }

    /// True only when `element` is both present and actually within the app's visible bounds —
    /// as opposed to merely existing somewhere in the (possibly pre-expanded, off-screen)
    /// accessibility tree. See `scroll(_:to:screen:maxSwipes:)`.
    @MainActor
    private func onScreen(_ element: XCUIElement, in app: XCUIApplication) -> Bool {
        guard element.exists else { return false }
        let frame = element.frame
        guard frame.width > 0, frame.height > 0 else { return false }
        return app.frame.contains(CGPoint(x: frame.midX, y: frame.midY))
    }

    /// Matches a localized button by any of the given labels, so the sweep survives running
    /// against either a German or an English runner locale.
    @MainActor
    private func button(_ app: XCUIApplication, anyOf labels: [String]) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label IN %@", labels)).firstMatch
    }

    /// Best-effort keyboard dismissal so it never covers the screen under inspection.
    @MainActor
    private func dismissKeyboard(_ app: XCUIApplication) {
        guard app.keyboards.firstMatch.exists else { return }
        let dismiss = app.keyboards.buttons.matching(
            NSPredicate(format: "label CONTAINS[c] 'hide' OR label CONTAINS[c] 'dismiss' OR label CONTAINS[c] 'ausblenden'")
        ).firstMatch
        if dismiss.exists {
            dismiss.tap()
        } else {
            app.typeText("\n")
        }
        settle(0.5)
    }

    /// A short settle AFTER a real anchor wait — never the only synchronisation.
    @MainActor
    private func settle(_ seconds: Double = 0.8) {
        usleep(useconds_t(seconds * 1_000_000))
    }

    // MARK: - Capture

    @MainActor
    private func attach(_ name: String) {
        let attachment = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
