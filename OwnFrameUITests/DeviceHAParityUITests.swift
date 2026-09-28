//
//  DeviceHAParityUITests.swift
//  OwnFrameUITests
//
//  hitl §4 "HA parity with a Photos source" (900 quickstart, FR-900-11/12) on a real device:
//  adds one of the device's Photos albums as a SECOND source of an already configured frame, so
//  the HA album select has something to switch between. The HA side — the select lists it,
//  metadata without a place, no image without the opt-in, availability after rapid source
//  switches (#48) — is asserted on the broker by `device-accept.sh <udid> ha-parity`, not here:
//  asserting it from inside the app would only re-test the app's own belief.
//
//  Production path: no launch arguments, the real PhotoKit prompt (answered in whatever
//  language the device speaks — "full access" is the first button without an ellipsis).
//  Env: TEST_RUNNER_DEVICE_HA_PARITY=1, optional TEST_RUNNER_PHOTOS_ALBUM=<title>. Prints `photos-source: <title>` for the script.
//

import XCTest

final class DeviceHAParityUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
        try XCTSkipUnless(ProcessInfo.processInfo.environment["DEVICE_HA_PARITY"] == "1",
                          "Device HA parity only — set TEST_RUNNER_DEVICE_HA_PARITY=1")
        MainActor.assumeIsolated { XCUIDevice.shared.orientation = .portrait }
    }

    @MainActor
    func testAddFirstPhotosAlbumAsSecondSource() throws {
        let app = XCUIApplication()
        app.launchArguments = []
        app.launch()
        let image = app.descendants(matching: .any).matching(identifier: "slideshow.image").firstMatch
        XCTAssertTrue(image.waitForExistence(timeout: 90), "needs a configured frame")

        let settings = app.buttons["slideshow.chrome.settings"]
        for _ in 0..<3 where !settings.isHittable {
            image.tap()
            _ = settings.waitForExistence(timeout: 2)
        }
        settings.tap()
        let sources = app.descendants(matching: .any).matching(identifier: "settings.sources").firstMatch
        if !sources.waitForExistence(timeout: 5) { app.scrollUntilExists(sources) }
        sources.tap()

        let add = app.buttons["sources.add"]
        XCTAssertTrue(add.waitForExistence(timeout: 10))
        add.tap()
        // The segmented type picker: Album, Immich link, iCloud album — by position, so the
        // app's language never matters.
        let type = app.segmentedControls["sources.add.type"]
        XCTAssertTrue(type.waitForExistence(timeout: 10))
        type.buttons.element(boundBy: 2).tap()
        answerPhotosPrompt()

        // First real album row: `sources.photos.<collection id>`, not the search field or its clear button.
        let rows = app.buttons.matching(NSPredicate(format:
            "identifier BEGINSWITH 'sources.photos.' AND NOT (identifier BEGINSWITH 'sources.photos.search')"))
        XCTAssertTrue(rows.firstMatch.waitForExistence(timeout: 60), "the device's Photos library should list an album")
        // PHOTOS_ALBUM names the album; otherwise the one with the most items among those
        // listed, so a video-only album (plays nothing) is not picked by accident.
        let listed = rows.allElementsBoundByIndex.filter { $0.exists }
        let wanted = ProcessInfo.processInfo.environment["PHOTOS_ALBUM"].flatMap { $0.isEmpty ? nil : $0 }
        func count(_ e: XCUIElement) -> Int {
            Int(e.label.components(separatedBy: CharacterSet.decimalDigits.inverted).filter { !$0.isEmpty }.last ?? "") ?? 0
        }
        let chosen = wanted.flatMap { name in listed.first { $0.label.hasPrefix(name) } }
            ?? listed.max { count($0) < count($1) }!
        let title = wanted ?? chosen.label.components(separatedBy: ",").first!.trimmingCharacters(in: .whitespaces)
        print("photos albums listed: \(listed.map(\.label))")
        chosen.tap()
        attach("01-album-marked")
        app.buttons["sources.add.done"].tap()

        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", title)).firstMatch
                        .waitForExistence(timeout: 15), "the Photos album should join the source list")
        attach("02-sources")
        print("photos-source: \(title)")
    }

    /// For the race step only (#48/#91): a device without Photos albums gets a second Immich
    /// link instead (TEST_RUNNER_SECOND_LINK). Prints `link-source: <label>`.
    @MainActor
    func testAddSecondImmichLinkSource() throws {
        guard let link = ProcessInfo.processInfo.environment["SECOND_LINK"], !link.isEmpty else {
            throw XCTSkip("set TEST_RUNNER_SECOND_LINK")
        }
        let app = XCUIApplication()
        app.launchArguments = []
        app.launch()
        let image = app.descendants(matching: .any).matching(identifier: "slideshow.image").firstMatch
        XCTAssertTrue(image.waitForExistence(timeout: 90), "needs a configured frame")
        let settings = app.buttons["slideshow.chrome.settings"]
        for _ in 0..<3 where !settings.isHittable {
            image.tap()
            _ = settings.waitForExistence(timeout: 2)
        }
        settings.tap()
        let sources = app.descendants(matching: .any).matching(identifier: "settings.sources").firstMatch
        if !sources.waitForExistence(timeout: 5) { app.scrollUntilExists(sources) }
        sources.tap()
        app.buttons["sources.add"].tap()
        let type = app.segmentedControls["sources.add.type"]
        XCTAssertTrue(type.waitForExistence(timeout: 10))
        type.buttons.element(boundBy: 1).tap() // Immich link
        let label = "Race B"
        for (id, text) in [("sources.add.url", link), ("sources.add.label", label)] {
            let field = app.textFields[id]
            XCTAssertTrue(field.waitForExistence(timeout: 10), "\(id) should exist")
            field.tap()
            for _ in 0..<3 where (field.value as? String) != text {
                let old = field.value as? String ?? ""
                if !old.isEmpty, old != field.placeholderValue {
                    field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: old.count))
                }
                field.typeText(text)
            }
        }
        app.releaseKeyboardFocus()
        app.buttons["sources.add.submit"].tap()
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", label)).firstMatch
                        .waitForExistence(timeout: 60), "the second link should join the source list")
        attach("02-sources")
        print("link-source: \(label)")
    }

    /// The PhotoKit authorization alert lives in SpringBoard. Its limited-access button ends in
    /// an ellipsis ("Select Photos…" on iOS 17, "Limit Access…" later) and comes first; the next
    /// one grants full access. Nothing shows when access was granted before — then a no-op.
    @MainActor
    private func answerPhotosPrompt() {
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let alert = springboard.alerts.firstMatch
        guard alert.waitForExistence(timeout: 8) else { return }
        attach("00-photos-prompt")
        let full = alert.buttons.allElementsBoundByIndex.first {
            !$0.label.hasSuffix("…") && !$0.label.hasSuffix("...")
        }
        (full ?? alert.buttons.element(boundBy: 1)).tap()
    }

    @MainActor
    private func attach(_ name: String) {
        let shot = XCTAttachment(screenshot: XCUIScreen.main.screenshot())
        shot.name = name
        shot.lifetime = .keepAlways
        add(shot)
    }
}
