//
//  AlbumSearchUITests.swift
//  OwnFrameUITests
//
//  210 / US3 — the searchable, subscrollable onboarding album picker. With 50+ albums the
//  user can narrow by name / year / photo count (case- and diacritic-insensitive), sees a
//  no-results state when nothing matches, and the primary Continue action stays pinned while
//  the list scrolls — in portrait and landscape. Hermetic `--uitest` build: the source step
//  is reached directly (`--uitest-onboarding-source`) and seeded with 60 metadata-bearing
//  stub albums (`--uitest-albums-many`), incl. a diacritic name ("München Trip").
//

import XCTest

final class AlbumSearchUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
        // Never inherit a rotation leaked by an earlier test on the same simulator
        // clone — a launch during a stale landscape state positions the chrome
        // off-screen. Tests that need landscape rotate themselves (and restore).
        MainActor.assumeIsolated { XCUIDevice.shared.orientation = .portrait }
    }

    /// Portrait: search narrows the list (diacritic-insensitive), a no-match shows the empty
    /// state, and Continue stays pinned while the list scrolls.
    @MainActor
    func testAlbumPickerSearchNarrowsAndKeepsActionPinned() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--uitest", "--uitest-onboarding-source", "--uitest-albums-many"]
        app.launch()

        let munich = app.buttons["onboarding.album.album-munich"]
        XCTAssertTrue(munich.waitForExistence(timeout: 10), "the seeded album list should appear")
        XCTAssertTrue(app.buttons["onboarding.album.album-1"].waitForExistence(timeout: 2),
                      "a non-matching album should be present before searching")

        // Diacritic-insensitive narrowing: "munchen" matches only "München Trip".
        let search = app.textFields["onboarding.album.search"]
        XCTAssertTrue(search.waitForExistence(timeout: 5), "the album search field should appear")
        search.tap()
        search.typeText("munchen")

        XCTAssertTrue(munich.waitForExistence(timeout: 5), "the matching album should remain after searching")
        XCTAssertFalse(app.buttons["onboarding.album.album-1"].exists, "non-matching albums should be filtered out")

        attachScreenshot(app, name: "album-search-narrowed")

        // A query that matches nothing shows the no-results state.
        app.buttons["onboarding.album.search.clear"].tap()
        search.typeText("zzzqqq")
        let noResults = app.descendants(matching: .any).matching(identifier: "onboarding.album.noResults").firstMatch
        XCTAssertTrue(noResults.waitForExistence(timeout: 5), "a no-match query should show the no-results state")

        // Clear, add an album, then confirm Continue stays pinned while the list scrolls.
        app.buttons["onboarding.album.search.clear"].tap()
        XCTAssertTrue(munich.waitForExistence(timeout: 5))
        munich.tap()

        let cont = app.buttons["onboarding.source.continue"]
        XCTAssertTrue(cont.waitForExistence(timeout: 5), "Continue should appear once a source is added")
        app.swipeUp()
        app.swipeUp()
        XCTAssertTrue(cont.exists, "Continue should stay pinned while the album list scrolls")
        XCTAssertTrue(cont.isHittable, "the pinned Continue should remain tappable after scrolling")
    }

    /// Landscape (the iPad's primary orientation): the same search-narrows + pinned-action
    /// behavior holds when the device is rotated.
    @MainActor
    func testAlbumPickerSearchInLandscape() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--uitest", "--uitest-onboarding-source", "--uitest-albums-many"]
        app.launch()
        XCUIDevice.shared.orientation = .landscapeLeft
        defer { XCUIDevice.shared.orientation = .portrait }

        let munich = app.buttons["onboarding.album.album-munich"]
        XCTAssertTrue(munich.waitForExistence(timeout: 10), "the seeded album list should render in landscape")

        let search = app.textFields["onboarding.album.search"]
        search.tap()
        search.typeText("munchen")
        XCTAssertTrue(munich.waitForExistence(timeout: 5))
        XCTAssertFalse(app.buttons["onboarding.album.album-1"].exists, "search should narrow the list in landscape")

        app.buttons["onboarding.album.search.clear"].tap()
        munich.tap()
        let cont = app.buttons["onboarding.source.continue"]
        XCTAssertTrue(cont.waitForExistence(timeout: 5))
        app.swipeUp()
        XCTAssertTrue(cont.isHittable, "Continue should stay pinned and tappable in landscape")
        attachScreenshot(app, name: "album-search-landscape")
    }

    // MARK: - Helpers

    @MainActor
    private func attachScreenshot(_ app: XCUIApplication, name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
}
