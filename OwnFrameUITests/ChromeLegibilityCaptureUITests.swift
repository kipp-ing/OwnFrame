//
//  ChromeLegibilityCaptureUITests.swift
//  OwnFrameUITests
//
//  300 T002/T009 (#72, FR-300-34): captures of the slideshow chrome over the worst-case photo
//  tones, via the `--uitest-photo-tone` stub seam. Material blur can't be asserted numerically,
//  so these are a visual gate, compared by eye across runtimes (18.6 = soft-glass path,
//  26 = Liquid Glass). Opt-in like AppStoreScreenshotUITests: the default suite records a skip.
//
//  Run with runner env `CHROME_LEGIBILITY_CAPTURE=1`. `CHROME_LEGIBILITY_CAPTURE_DIR=<path>`
//  additionally writes each capture as PNG to that host directory (the simulator shares the
//  host file system), named `<surface>-<tone>-ios<version>.png`.
//

import XCTest

final class ChromeLegibilityCaptureUITests: XCTestCase {

    override func setUpWithError() throws {
        guard ProcessInfo.processInfo.environment["CHROME_LEGIBILITY_CAPTURE"] == "1" else {
            throw XCTSkip("chrome legibility capture only runs with CHROME_LEGIBILITY_CAPTURE=1")
        }
        continueAfterFailure = false
        MainActor.assumeIsolated { XCUIDevice.shared.orientation = .portrait }
    }

    @MainActor
    func testCaptureOverNearWhite() throws {
        captureMatrix(tone: "white")
    }

    @MainActor
    func testCaptureOverNearBlack() throws {
        captureMatrix(tone: "black")
    }

    /// Bars, then bars + photo-info card (chrome pinned), then the clock pill (chrome hidden,
    /// since the clock steps aside whenever the chrome is up, SC-500-07), then the new-photos
    /// card (310 #60, FR-310-15). Every launch passes `--uitest-reset-storage`: the 320 offline
    /// snapshot otherwise replays images cached by an earlier run instead of the toned renders.
    @MainActor
    private func captureMatrix(tone: String) {
        let app = XCUIApplication()
        app.launchArguments = [
            "--uitest", "--uitest-slideshow", "--uitest-reset-storage", "--uitest-chrome", "--uitest-photo-tone=\(tone)",
        ]
        app.launch()
        XCTAssertTrue(element(app, "slideshow.image").waitForExistence(timeout: 5), "slideshow should be running")

        let infoButton = app.buttons["slideshow.chrome.info"]
        XCTAssertTrue(infoButton.waitForExistence(timeout: 3))
        sleep(1)
        capture("chrome", tone: tone)

        infoButton.tap()
        XCTAssertTrue(element(app, "slideshow.info.card").waitForExistence(timeout: 3), "info card should appear")
        sleep(1)
        capture("info", tone: tone)
        app.terminate()

        let clockApp = XCUIApplication()
        clockApp.launchArguments = [
            "--uitest", "--uitest-slideshow", "--uitest-reset-storage", "--uitest-entitlements=supporter",
            "--uitest-clock-style=pill", "--uitest-clock-place=topCenter", "--uitest-photo-tone=\(tone)",
        ]
        clockApp.launch()
        XCTAssertTrue(element(clockApp, "slideshow.clock").waitForExistence(timeout: 5), "pill clock should render")
        sleep(1)
        capture("clock-pill", tone: tone)
        clockApp.terminate()

        // Same hermetic arrival as GermanScreenshotSweepUITests.test55_newPhotosCard; the Photos
        // gateway serves the stub renders, so the tone seam applies to it too.
        let cardApp = XCUIApplication()
        cardApp.launchArguments = [
            "--uitest", "--uitest-slideshow", "--uitest-reset-storage", "--uitest-photos-source",
            "--uitest-photos-auth=full", "--uitest-new-photos-card", "--uitest-reset-theme",
            "--uitest-photo-tone=\(tone)",
        ]
        cardApp.launch()
        XCTAssertTrue(element(cardApp, "slideshow.newPhotosCard").waitForExistence(timeout: 10),
                      "new-photos card should show")
        capture("new-photos-card", tone: tone)
    }

    @MainActor
    private func element(_ app: XCUIApplication, _ id: String) -> XCUIElement {
        app.descendants(matching: .any).matching(identifier: id).firstMatch
    }

    @MainActor
    private func capture(_ surface: String, tone: String) {
        let screenshot = XCUIScreen.main.screenshot()
        let name = "\(surface)-\(tone)-ios\(UIDevice.current.systemVersion)"
        let attachment = XCTAttachment(screenshot: screenshot)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)

        if let directory = ProcessInfo.processInfo.environment["CHROME_LEGIBILITY_CAPTURE_DIR"] {
            let url = URL(fileURLWithPath: directory).appendingPathComponent("\(name).png")
            XCTAssertNoThrow(try screenshot.pngRepresentation.write(to: url), "write \(url.path)")
        }
    }
}
