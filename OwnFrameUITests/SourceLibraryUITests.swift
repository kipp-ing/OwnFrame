//
//  SourceLibraryUITests.swift
//  OwnFrameUITests
//
//  120 / US2 — drives the Settings → Sources source manager against the hermetic
//  in-memory source library: open the manager, add a second source, switch the active
//  one (the running slideshow swaps its photo), and remove a source.
//

import XCTest

final class SourceLibraryUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
        // Never inherit a rotation leaked by an earlier test on the same simulator
        // clone — a launch during a stale landscape state positions the chrome
        // off-screen. Tests that need landscape rotate themselves (and restore).
        MainActor.assumeIsolated { XCUIDevice.shared.orientation = .portrait }
    }

    /// Switching the active source restarts the running slideshow from it: the seeded
    /// album (a1) plays asset-1…3; after adding and activating album a2 the photo swaps
    /// to asset-4…6. The asset id is read from the image's accessibility value.
    @MainActor
    func testSwitchingActiveSourceSwapsRunningSlideshow() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--uitest", "--uitest-slideshow", "--uitest-chrome"]
        app.launch()

        let image = app.descendants(matching: .any).matching(identifier: "slideshow.image").firstMatch
        XCTAssertTrue(image.waitForExistence(timeout: 5))
        XCTAssertTrue(["asset-1", "asset-2", "asset-3"].contains(image.value as? String ?? ""),
                      "seeded source a1 should be playing first")

        openSources(in: app)

        // Seeded source is present and active.
        XCTAssertTrue(app.buttons["sources.row.src-a1"].waitForExistence(timeout: 3))

        addAlbum(named: "Urlaub 2026", in: app)

        // Activate the new source; the manager marks it and the slideshow swaps album.
        let newRow = app.buttons["Urlaub 2026"]
        XCTAssertTrue(newRow.waitForExistence(timeout: 3))
        newRow.tap()

        // Back out of the manager and close settings to see the running slideshow.
        app.navigationBars["Sources"].buttons.element(boundBy: 0).tap()
        app.buttons["Done"].tap()

        XCTAssertTrue(image.waitForExistence(timeout: 3))
        let swapped = NSPredicate(format: "value IN %@", ["asset-4", "asset-5", "asset-6"])
        expectation(for: swapped, evaluatedWith: image)
        waitForExpectations(timeout: 5)
    }

    /// A source can be added and removed; after a swipe-delete its row is gone.
    @MainActor
    func testAddAndRemoveSource() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--uitest", "--uitest-slideshow", "--uitest-chrome"]
        app.launch()

        let image = app.descendants(matching: .any).matching(identifier: "slideshow.image").firstMatch
        XCTAssertTrue(image.waitForExistence(timeout: 5))

        openSources(in: app)
        addAlbum(named: "Urlaub 2026", in: app)

        let newRow = app.buttons["Urlaub 2026"]
        XCTAssertTrue(newRow.waitForExistence(timeout: 3))

        // Swipe-delete the just-added (non-active) source.
        newRow.swipeLeft()
        app.buttons["Delete"].firstMatch.tap()

        XCTAssertFalse(newRow.waitForExistence(timeout: 2), "removed source row should be gone")
        // The seeded source remains.
        XCTAssertTrue(app.buttons["sources.row.src-a1"].exists)
    }

    /// 210 / FR-210-27/28 — Settings → Sources uses the same searchable, subscrollable album
    /// picker as onboarding: search narrows (diacritic-insensitive), a no-match shows the
    /// no-results state, and adding is select-then-confirm (tap album → Done).
    @MainActor
    func testSettingsAlbumPickerSearchesAndSelectThenConfirm() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--uitest", "--uitest-slideshow", "--uitest-chrome", "--uitest-albums-many"]
        app.launch()

        let image = app.descendants(matching: .any).matching(identifier: "slideshow.image").firstMatch
        XCTAssertTrue(image.waitForExistence(timeout: 5))

        openSources(in: app)
        app.buttons["sources.add"].tap()

        // The shared searchable picker is present in Settings (the same component as onboarding).
        let search = app.textFields["sources.album.search"]
        XCTAssertTrue(search.waitForExistence(timeout: 5), "Settings add-album should show the search field")

        let munich = app.buttons["sources.album.album-munich"]
        XCTAssertTrue(munich.waitForExistence(timeout: 5), "the seeded album list should appear")
        XCTAssertTrue(app.buttons["sources.album.album-1"].waitForExistence(timeout: 2),
                      "a non-matching album should be present before searching")

        // Diacritic-insensitive narrowing: "munchen" matches only "München Trip".
        search.tap()
        search.typeText("munchen")
        XCTAssertTrue(munich.waitForExistence(timeout: 5), "the matching album should remain after searching")
        XCTAssertFalse(app.buttons["sources.album.album-1"].exists, "non-matching albums should be filtered out")

        // A query that matches nothing shows the no-results state rather than a blank list.
        app.buttons["sources.album.search.clear"].tap()
        search.typeText("zzzqqq")
        let noResults = app.descendants(matching: .any).matching(identifier: "sources.album.noResults").firstMatch
        XCTAssertTrue(noResults.waitForExistence(timeout: 5), "a no-match query should show the no-results state")

        // Select-then-confirm: clear, tap the album to mark it, then Done commits (FR-210-28).
        app.buttons["sources.album.search.clear"].tap()
        XCTAssertTrue(munich.waitForExistence(timeout: 5))
        munich.tap()
        XCTAssertTrue(munich.isSelected, "tapping an album should mark it")
        let done = app.buttons["sources.add.done"]
        XCTAssertTrue(done.waitForExistence(timeout: 3), "the pinned Done action should be present")
        XCTAssertTrue(done.label.contains("1"), "Done should count the marked album, got \(done.label)")
        done.tap()

        // The added album appears as a new source row in the manager.
        XCTAssertTrue(app.buttons["München Trip"].waitForExistence(timeout: 5),
                      "the selected album should be added as a source after Done")
    }

    /// 120 / FR-120-12 — adding a shared link later offers the same QR scan the first-run
    /// path has, and never at the cost of manual entry: the URL field and Add button stay
    /// put, so a denied or missing camera can't strand the user (FR-220-05 parity).
    @MainActor
    func testAddSharedLinkFormOffersQRScanAlongsideManualEntry() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--uitest", "--uitest-slideshow", "--uitest-chrome"]
        app.launch()

        openSources(in: app)
        app.buttons["sources.add"].tap()

        let picker = app.segmentedControls["sources.add.type"]
        XCTAssertTrue(picker.waitForExistence(timeout: 3), "add-source type picker should exist")
        picker.buttons["Immich link"].tap()

        XCTAssertTrue(app.buttons["sources.add.scan"].waitForExistence(timeout: 3),
                      "Settings → Sources → Immich link should offer Scan QR")
        XCTAssertTrue(app.textFields["sources.add.url"].exists,
                      "manual link entry must remain available alongside scanning")
        XCTAssertTrue(app.textFields["sources.add.label"].exists,
                      "the optional name field must remain available alongside scanning")
    }

    /// 210 / FR-210-28 (#71) — tapping albums only marks them, so Cancel adds nothing.
    @MainActor
    func testCancelDiscardsMarkedAlbums() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--uitest", "--uitest-slideshow", "--uitest-chrome", "--uitest-albums-many"]
        app.launch()
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "slideshow.image").firstMatch
            .waitForExistence(timeout: 5))

        openSources(in: app)
        XCTAssertTrue(app.buttons["sources.row.src-a1"].waitForExistence(timeout: 3))
        app.buttons["sources.add"].tap()

        let munich = app.buttons["sources.album.album-munich"]
        let second = app.buttons["sources.album.album-2"]
        XCTAssertTrue(munich.waitForExistence(timeout: 5))
        munich.tap()
        second.tap()
        XCTAssertTrue(munich.isSelected && second.isSelected, "tapped albums should be marked")

        app.buttons["sources.add.cancel"].tap()
        XCTAssertTrue(app.buttons["sources.add"].waitForExistence(timeout: 3))
        XCTAssertEqual(sourceRows(in: app).count, 1, "Cancel must leave the library unchanged")
        XCTAssertFalse(app.buttons["München Trip"].exists, "a marked album must not be added on Cancel")
    }

    /// 210 / FR-210-28 (#71) — Done commits exactly the marked albums; an album marked and
    /// unmarked again is not added.
    @MainActor
    func testDoneAddsExactlyTheMarkedAlbums() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--uitest", "--uitest-slideshow", "--uitest-chrome", "--uitest-albums-many"]
        app.launch()
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "slideshow.image").firstMatch
            .waitForExistence(timeout: 5))

        openSources(in: app)
        XCTAssertTrue(app.buttons["sources.row.src-a1"].waitForExistence(timeout: 3))
        app.buttons["sources.add"].tap()

        let munich = app.buttons["sources.album.album-munich"]
        let first = app.buttons["sources.album.album-1"]
        let second = app.buttons["sources.album.album-2"]
        XCTAssertTrue(munich.waitForExistence(timeout: 5))
        munich.tap()
        first.tap()
        second.tap()
        second.tap()
        XCTAssertFalse(second.isSelected, "tapping a marked album again should unmark it")

        let done = app.buttons["sources.add.done"]
        XCTAssertTrue(done.label.contains("2"), "Done should count the two marked albums, got \(done.label)")
        done.tap()

        XCTAssertTrue(app.buttons["München Trip"].waitForExistence(timeout: 5), "a marked album should be added")
        XCTAssertEqual(sourceRows(in: app).count, 3, "exactly the two marked albums should be added")
    }

    /// 210 / FR-210-28 (#71) — adding an Immich link closes the sheet; albums marked on the Album
    /// tab before that are committed with it, never dropped unseen.
    @MainActor
    func testAddingALinkKeepsAlbumsMarkedOnTheAlbumTab() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--uitest", "--uitest-slideshow", "--uitest-chrome"]
        app.launch()
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "slideshow.image").firstMatch
            .waitForExistence(timeout: 5))

        openSources(in: app)
        XCTAssertTrue(app.buttons["sources.row.src-a1"].waitForExistence(timeout: 3))
        app.buttons["sources.add"].tap()

        let urlaub = app.buttons["sources.album.a2"]
        XCTAssertTrue(urlaub.waitForExistence(timeout: 5), "stub album a2 should be listed")
        urlaub.tap()

        app.segmentedControls["sources.add.type"].buttons["Immich link"].tap()
        let url = app.textFields["sources.add.url"]
        XCTAssertTrue(url.waitForExistence(timeout: 3))
        url.tap()
        url.typeText("https://demo.example.com/s/abc123")
        app.buttons["sources.add.submit"].tap()

        XCTAssertTrue(app.buttons["Urlaub 2026"].waitForExistence(timeout: 5),
                      "the album marked before adding the link should be added too")
        XCTAssertEqual(sourceRows(in: app).count, 3, "the seeded source, the marked album and the link")
    }

    /// 210 / FR-210-30 case a (SC-210-13) — with no server stored, the Album tab guides the user
    /// to add a server instead of showing a load failure.
    @MainActor
    func testAlbumTabWithoutServerShowsAddServerPrompt() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--uitest", "--uitest-slideshow", "--uitest-chrome", "--uitest-no-server"]
        app.launch()
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "slideshow.image").firstMatch
            .waitForExistence(timeout: 5))

        openSources(in: app)
        app.buttons["sources.add"].tap()

        XCTAssertTrue(app.buttons["sources.add.addServer"].waitForExistence(timeout: 5),
                      "the Album tab should offer Add a server when no server is stored")
        XCTAssertFalse(app.textFields["sources.album.search"].exists,
                       "no album list should load without a server")
    }

    // MARK: - Helpers

    @MainActor
    private func sourceRows(in app: XCUIApplication) -> XCUIElementQuery {
        app.buttons.matching(NSPredicate(format: "identifier BEGINSWITH %@", "sources.row."))
    }

    @MainActor
    private func openSources(in app: XCUIApplication) {
        let settingsButton = app.buttons["slideshow.chrome.settings"]
        XCTAssertTrue(settingsButton.waitForExistence(timeout: 2))
        settingsButton.tap()

        let sources = app.descendants(matching: .any).matching(identifier: "settings.sources").firstMatch
        XCTAssertTrue(scrollToElement(sources, in: app), "Sources row should be present in settings")
        sources.tap()
    }

    @MainActor
    private func addAlbum(named name: String, in app: XCUIApplication) {
        app.buttons["sources.add"].tap()
        // Album mode is the default; pick the album that becomes the new source.
        let albumButton = app.buttons["sources.album.a2"]
        XCTAssertTrue(albumButton.waitForExistence(timeout: 3), "stub album a2 should be listed")
        albumButton.tap()
        // Select-then-confirm (210, FR-210-28): tapping the album marks it; Done commits and
        // dismisses, and the new row appears in the manager.
        XCTAssertTrue(albumButton.isSelected, "tapping the album should mark it")
        app.buttons["sources.add.done"].tap()
        XCTAssertTrue(app.buttons[name].waitForExistence(timeout: 3))
    }

    /// Converges on the element rather than spending a fixed swipe budget — see ScrollHarness.
    @MainActor
    private func scrollToElement(_ element: XCUIElement, in app: XCUIApplication) -> Bool {
        if element.waitForExistence(timeout: 3) { return true }
        app.scrollUntilExists(element)
        return element.exists
    }
}
