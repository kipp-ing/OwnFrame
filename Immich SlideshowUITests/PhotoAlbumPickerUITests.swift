//
//  PhotoAlbumPickerUITests.swift
//  Immich SlideshowUITests
//
//  900 / US1 (T018) — the full-access Photos-album picker flow, hermetic. `--uitest-photos`
//  swaps in an in-app fake PhotoLibraryGateway with deterministic collections ("Family"
//  pl-family, "Holiday 2024" pl-holiday); `--uitest-photos-auth=full` scripts the
//  authorization request's outcome, so no real PhotoKit prompt ever appears. Covers both
//  entry points: Settings → Sources → add (Photos album tab) and the onboarding source
//  step. Flow under test: entry point → access request → searchable album list → select →
//  the source lands in the library and the slideshow plays (acceptance 1–3).
//

import XCTest

final class PhotoAlbumPickerUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
        // Never inherit a rotation leaked by an earlier test on the same simulator
        // clone — a launch during a stale landscape state positions the chrome
        // off-screen. Tests that need landscape rotate themselves (and restore).
        MainActor.assumeIsolated { XCUIDevice.shared.orientation = .portrait }
    }

    /// Settings → Sources → add: the Photos-album tab requests access (fake grants full),
    /// lists the fake gateway's albums in the searchable picker (title + count), narrows by
    /// title, and select-then-confirm adds the album as a source. Activating it keeps the
    /// slideshow playing (photoLibrary sources rebuild through the hermetic stub).
    @MainActor
    func testAddPhotosAlbumFromSettingsPlaysSlideshow() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--uitest", "--uitest-slideshow", "--uitest-chrome",
                               "--uitest-photos", "--uitest-photos-auth=full"]
        app.launch()

        let image = app.descendants(matching: .any).matching(identifier: "slideshow.image").firstMatch
        XCTAssertTrue(image.waitForExistence(timeout: 5))

        openSources(in: app)
        app.buttons["sources.add"].tap()

        // Entry point: the add-source sheet offers a Photos-album kind next to Album and
        // Shared link. Choosing it triggers the access request (US1 acceptance 1); the
        // scripted full grant lets the album list load.
        let photosTab = app.buttons["Photos album"]
        XCTAssertTrue(photosTab.waitForExistence(timeout: 3),
                      "the add-source sheet should offer a Photos album tab")
        photosTab.tap()

        // Full access: the fake gateway's collections appear in the same searchable picker
        // pattern the Immich album picker uses (US1 acceptance 2).
        let search = app.textFields["sources.photos.search"]
        XCTAssertTrue(search.waitForExistence(timeout: 5),
                      "the Photos album picker should show a search field")

        let family = app.buttons["sources.photos.pl-family"]
        let holiday = app.buttons["sources.photos.pl-holiday"]
        XCTAssertTrue(family.waitForExistence(timeout: 5), "album Family should be listed")
        XCTAssertTrue(holiday.waitForExistence(timeout: 2), "album Holiday 2024 should be listed")

        // Search narrows by title, case-insensitively; non-matching albums drop out.
        search.tap()
        search.typeText("holiday")
        XCTAssertTrue(holiday.waitForExistence(timeout: 3),
                      "the matching album should remain while searching")
        XCTAssertFalse(family.exists, "non-matching albums should be filtered out")

        // Select-then-confirm, same as the Immich picker: tap the album, then Done.
        app.buttons["sources.photos.search.clear"].tap()
        XCTAssertTrue(family.waitForExistence(timeout: 3))
        family.tap()
        let done = app.buttons["sources.add.done"]
        XCTAssertTrue(done.waitForExistence(timeout: 3),
                      "the pinned Done action should be present on the Photos tab")
        done.tap()

        // The chosen album is saved into the source library (US1 acceptance 3)…
        let newRow = app.buttons["Family"]
        XCTAssertTrue(newRow.waitForExistence(timeout: 5),
                      "the selected Photos album should appear as a source row")

        // …and activating it restarts the slideshow from the Photos source. Cross-backend
        // switches use the rebuild strategy, which recreates the SlideshowView — the
        // settings/sources sheets tear down with it and the rebuilt slideshow appears
        // directly (same behavior as an album↔shared-link switch).
        newRow.tap()

        XCTAssertTrue(image.waitForExistence(timeout: 5),
                      "the rebuilt slideshow should play from the Photos source")
        // The pl-* asset ids come from the fake photo gateway through the REAL
        // PhotoLibraryProvider — proof the switch landed on the Photos backend, not
        // merely that a slideshow is running.
        let photosAsset = NSPredicate(format: "value IN %@", ["pl-asset-1", "pl-asset-2", "pl-asset-3"])
        expectation(for: photosAsset, evaluatedWith: image)
        waitForExpectations(timeout: 5)
    }

    /// Onboarding source step: the Photos-album tab appears next to Album and Shared link;
    /// picking an album adds the first source and the flow continues through confirm into
    /// the running slideshow (US1 acceptance 1–3 from the onboarding entry point).
    /// No `--uitest-photos-auth` arg: this is the FIRST-RUN path — access starts
    /// notDetermined and is requested the moment the tab is chosen (FR-900-04), with the
    /// fake granting full like a user tapping Allow.
    @MainActor
    func testOnboardingPhotosAlbumTabAddsFirstSource() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--uitest", "--uitest-onboarding-source", "--uitest-photos"]
        app.launch()

        // The source step offers the Photos-album kind.
        let photosTab = app.buttons["Photos album"]
        XCTAssertTrue(photosTab.waitForExistence(timeout: 5),
                      "onboarding should offer a Photos album tab")
        photosTab.tap()

        // Full access granted: the fake gateway's albums appear in the searchable picker.
        let family = app.buttons["onboarding.photos.pl-family"]
        XCTAssertTrue(family.waitForExistence(timeout: 5),
                      "album Family should be listed in the onboarding picker")

        // Selecting it adds the first source; the pinned Continue appears.
        family.tap()
        let continueButton = app.buttons["onboarding.source.continue"]
        XCTAssertTrue(continueButton.waitForExistence(timeout: 3),
                      "adding a Photos album should surface the Continue bar")
        continueButton.tap()

        // Confirm lists the new source as active; Start plays the slideshow.
        let start = app.buttons["onboarding.confirm.start"]
        XCTAssertTrue(start.waitForExistence(timeout: 5))
        start.tap()

        let image = app.descendants(matching: .any).matching(identifier: "slideshow.image").firstMatch
        XCTAssertTrue(image.waitForExistence(timeout: 5),
                      "finishing onboarding with a Photos source should start the slideshow")
        XCTAssertTrue(["pl-asset-1", "pl-asset-2", "pl-asset-3"].contains(image.value as? String ?? ""),
                      "the show should play the Photos backend's assets via the real provider")
    }

    /// US1 acceptance 4 — startup parity: a launch with a saved, active Photos source
    /// (seeded by `--uitest-photos-source`, access already granted) resumes directly into
    /// the Photos slideshow with no picker involved, exactly like an Immich source. The
    /// hermetic switch also proves the app-UI path back: the Immich source row is still
    /// there and activating it swaps the show back to the stub album (acceptance 5).
    @MainActor
    func testLaunchWithSavedPhotosSourceResumesDirectly() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--uitest", "--uitest-slideshow", "--uitest-chrome",
                               "--uitest-photos-source", "--uitest-photos-auth=full"]
        app.launch()

        let image = app.descendants(matching: .any).matching(identifier: "slideshow.image").firstMatch
        XCTAssertTrue(image.waitForExistence(timeout: 5),
                      "a saved Photos source should resume straight into the slideshow")
        let photosAsset = NSPredicate(format: "value IN %@", ["pl-asset-1", "pl-asset-2", "pl-asset-3"])
        expectation(for: photosAsset, evaluatedWith: image)
        waitForExpectations(timeout: 5)

        // Cross-backend switch in the other direction: Photos → Immich album rebuilds
        // back onto the stub album's assets.
        openSources(in: app)
        let albumRow = app.buttons["sources.row.src-a1"]
        XCTAssertTrue(albumRow.waitForExistence(timeout: 3))
        albumRow.tap()

        XCTAssertTrue(image.waitForExistence(timeout: 5))
        let immichAsset = NSPredicate(format: "value IN %@", ["asset-1", "asset-2", "asset-3"])
        expectation(for: immichAsset, evaluatedWith: image)
        waitForExpectations(timeout: 5)
    }

    // MARK: - Helpers

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
    private func scrollToElement(_ element: XCUIElement, in app: XCUIApplication, maxSwipes: Int = 8) -> Bool {
        if element.waitForExistence(timeout: 3) { return true }
        var swipes = 0
        while !element.exists && swipes < maxSwipes {
            app.swipeUp()
            swipes += 1
        }
        return element.exists
    }
}
