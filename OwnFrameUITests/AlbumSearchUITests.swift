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

        // Clear, mark an album, then confirm Continue stays pinned while the list scrolls.
        app.buttons["onboarding.album.search.clear"].tap()
        XCTAssertTrue(munich.waitForExistence(timeout: 5))
        munich.tap()
        XCTAssertTrue(munich.isSelected, "tapping an album should mark it")

        let cont = app.buttons["onboarding.source.continue"]
        XCTAssertTrue(cont.waitForExistence(timeout: 5), "Continue should appear once a source is added")
        app.swipeUp()
        app.swipeUp()
        XCTAssertTrue(cont.exists, "Continue should stay pinned while the album list scrolls")
        XCTAssertTrue(cont.isHittable, "the pinned Continue should remain tappable after scrolling")
    }

    /// 120, FR-120-13 (#61): an Immich album without a name shows the neutral placeholder as its
    /// row text, never its album id.
    @MainActor
    func testUnnamedAlbumRowShowsPlaceholderNotID() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--uitest", "--uitest-onboarding-source", "--uitest-albums-many"]
        app.launch()

        let search = app.textFields["onboarding.album.search"]
        XCTAssertTrue(search.waitForExistence(timeout: 10), "the album search field should appear")
        let row = app.buttons["onboarding.album.album-unnamed"]
        for _ in 0..<12 where !row.exists { app.swipeUp() }
        XCTAssertTrue(row.waitForExistence(timeout: 5), "the unnamed stub album should be listed")

        XCTAssertTrue(row.label.contains("Immich album"), "row text should be the placeholder, got \(row.label)")
        XCTAssertFalse(row.label.contains("album-unnamed"), "row text must never be the album id")

        // The review step right after lists the added source by the same display name.
        row.tap()
        let cont = app.buttons["onboarding.source.continue"]
        XCTAssertTrue(cont.waitForExistence(timeout: 5), "Continue should appear once the album is added")
        cont.tap()
        let reviewRow = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH %@", "onboarding.confirm.row."))
            .firstMatch
        XCTAssertTrue(reviewRow.waitForExistence(timeout: 5), "the review step should list the added source")
        XCTAssertTrue(reviewRow.label.contains("Immich album"), "review row should be the placeholder, got \(reviewRow.label)")
        XCTAssertFalse(reviewRow.label.contains("album-unnamed"), "review row must never be the album id")
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

    /// 210 / FR-210-28 (#71) — in onboarding, tapping albums only marks them: Continue commits
    /// exactly the marked albums, and an album marked then unmarked again is not added.
    @MainActor
    func testContinueCommitsExactlyTheMarkedAlbums() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--uitest", "--uitest-onboarding-source", "--uitest-albums-many"]
        app.launch()

        let munich = app.buttons["onboarding.album.album-munich"]
        let second = app.buttons["onboarding.album.album-2"]
        XCTAssertTrue(munich.waitForExistence(timeout: 10), "the seeded album list should appear")
        munich.tap()
        second.tap()
        second.tap()
        XCTAssertTrue(munich.isSelected, "tapping an album should mark it")
        XCTAssertFalse(second.isSelected, "tapping a marked album again should unmark it")

        let cont = app.buttons["onboarding.source.continue"]
        XCTAssertTrue(cont.waitForExistence(timeout: 5), "Continue should appear once an album is marked")
        attachScreenshot(app, name: "album-marked-portrait")
        cont.tap()

        let reviewRows = app.descendants(matching: .any)
            .matching(NSPredicate(format: "identifier BEGINSWITH %@", "onboarding.confirm.row."))
        XCTAssertTrue(reviewRows.firstMatch.waitForExistence(timeout: 5), "the review step should list the added source")
        XCTAssertEqual(reviewRows.count, 1, "exactly the one marked album should be added")
        XCTAssertTrue(reviewRows.firstMatch.label.contains("München Trip"), "got \(reviewRows.firstMatch.label)")
    }

    /// 210 / FR-210-28 (#71) — leaving the source step with Back discards the marks: on return
    /// the album is neither added nor marked, and there is no Continue bar.
    @MainActor
    func testBackAfterMarkingAddsNothing() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--uitest", "--uitest-onboarding-source", "--uitest-albums-many"]
        app.launch()

        let munich = app.buttons["onboarding.album.album-munich"]
        XCTAssertTrue(munich.waitForExistence(timeout: 10), "the seeded album list should appear")
        munich.tap()
        let cont = app.buttons["onboarding.source.continue"]
        XCTAssertTrue(cont.waitForExistence(timeout: 5), "Continue should appear once an album is marked")

        app.buttons["onboarding.back"].tap()
        let connectionContinue = app.buttons["onboarding.connection.continue"]
        XCTAssertTrue(connectionContinue.waitForExistence(timeout: 5), "Back should return to the connection step")
        if !connectionContinue.isEnabled {
            let url = app.textFields["onboarding.serverURL"]
            // An empty text field reports its placeholder as its value.
            let urlValue = url.value as? String ?? ""
            if urlValue.isEmpty || urlValue == url.placeholderValue {
                url.tap()
                url.typeText("https://photos.example.test")
            }
            let key = app.descendants(matching: .any).matching(identifier: "onboarding.apiKey").firstMatch
            key.tap()
            key.typeText("uitest-key")
        }
        connectionContinue.tap()

        XCTAssertTrue(munich.waitForExistence(timeout: 10), "the source step should show the albums again")
        XCTAssertTrue(munich.isEnabled, "an album that was only marked must not have been added")
        XCTAssertFalse(munich.isSelected, "Back should discard the mark")
        XCTAssertFalse(cont.exists, "nothing was added, so there should be no Continue bar")
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
