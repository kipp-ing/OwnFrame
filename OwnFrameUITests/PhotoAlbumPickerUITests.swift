//
//  PhotoAlbumPickerUITests.swift
//  OwnFrameUITests
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

    // MARK: - US3: permissions handled honestly (T029)

    /// US3-2 — limited access: the picker offers exactly ONE "Selected Photos" source (the
    /// granted pool), the system's manage-selection affordance, and an honest note that
    /// albums — including iCloud Shared Albums — need full access. It must never render an
    /// empty album list as if the user had no albums. Selecting the pool source plays it.
    @MainActor
    func testLimitedAccessOffersSelectedPhotosOnly() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--uitest", "--uitest-slideshow", "--uitest-chrome",
                               "--uitest-photos", "--uitest-photos-auth=limited"]
        app.launch()

        let image = app.descendants(matching: .any).matching(identifier: "slideshow.image").firstMatch
        XCTAssertTrue(image.waitForExistence(timeout: 5))

        openSources(in: app)
        app.buttons["sources.add"].tap()
        app.buttons["Photos album"].tap()

        // The single offerable source, not an album list (and not a bare unavailable state).
        let selectedRow = app.buttons["sources.photos.selected-photos"]
        XCTAssertTrue(selectedRow.waitForExistence(timeout: 5),
                      "limited access should offer the Selected Photos pool as one source")
        XCTAssertFalse(app.buttons["sources.photos.pl-family"].exists,
                       "albums must not be listed under limited access")

        // Honest note + the system manage-selection affordance.
        XCTAssertTrue(app.descendants(matching: .any).matching(identifier: "sources.photos.limitedNote")
            .firstMatch.exists, "the picker should state plainly that albums need full access")
        XCTAssertTrue(app.buttons["sources.photos.manageSelection"].exists,
                      "the system manage-selection affordance should be offered")

        // Selecting the pool adds it; activating plays the granted assets.
        selectedRow.tap()
        app.buttons["sources.add.done"].tap()
        let newRow = app.buttons["Selected Photos"]
        XCTAssertTrue(newRow.waitForExistence(timeout: 5))
        newRow.tap()

        XCTAssertTrue(image.waitForExistence(timeout: 5))
        let poolAsset = NSPredicate(format: "value BEGINSWITH %@", "pl-asset")
        expectation(for: poolAsset, evaluatedWith: image)
        waitForExpectations(timeout: 5)
    }

    /// US3-1 — denied access: a calm message explains the frame cannot see photos and links
    /// to iOS Settings; the other source kinds keep working untouched.
    @MainActor
    func testDeniedAccessShowsCalmMessageWithSettingsPath() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--uitest", "--uitest-slideshow", "--uitest-chrome",
                               "--uitest-photos", "--uitest-photos-auth=denied"]
        app.launch()

        let image = app.descendants(matching: .any).matching(identifier: "slideshow.image").firstMatch
        XCTAssertTrue(image.waitForExistence(timeout: 5))

        openSources(in: app)
        app.buttons["sources.add"].tap()
        app.buttons["Photos album"].tap()

        let denied = app.descendants(matching: .any).matching(identifier: "sources.photos.denied").firstMatch
        XCTAssertTrue(denied.waitForExistence(timeout: 5),
                      "denied access should show a calm explanation")
        XCTAssertTrue(app.buttons["sources.photos.openSettings"].exists,
                      "the denied state should link to iOS Settings")

        // Other source kinds keep working: the Immich album tab still lists albums.
        app.buttons["Album"].tap()
        XCTAssertTrue(app.buttons["sources.album.a2"].waitForExistence(timeout: 5),
                      "denied photo access must not affect Immich album sources")
    }

    /// US3-4 — mid-life downgrade: a saved, active Photos ALBUM source under an access
    /// downgrade (full → limited) becomes calmly unavailable with copy naming the cause and
    /// the fix in iOS Settings — not the Immich connection-editor path.
    @MainActor
    func testDowngradeMakesActiveAlbumSourceCalmlyUnavailable() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--uitest", "--uitest-slideshow", "--uitest-chrome",
                               "--uitest-photos-source", "--uitest-photos-auth=limited"]
        app.launch()

        let error = app.staticTexts["slideshow.error"]
        XCTAssertTrue(error.waitForExistence(timeout: 5),
                      "a downgraded album source should land in the calm error state")

        // The fix is re-granting photo access, not editing the Immich connection.
        XCTAssertTrue(app.buttons["slideshow.openSettings"].waitForExistence(timeout: 3),
                      "the error state should offer the iOS Settings path for photo access")
        XCTAssertFalse(app.buttons["slideshow.fixConnection"].exists,
                       "the Immich connection editor is the wrong fix for a Photos source")
        let photoCopy = app.staticTexts.containing(
            NSPredicate(format: "label CONTAINS[c] %@", "photo access")
        ).firstMatch
        XCTAssertTrue(photoCopy.exists, "the copy should name reduced photo access as the cause")
    }

    /// FR-900-16 — vanish: an active Photos source whose backing collection disappears
    /// (deleted / unshared / upgraded to the new iCloud format) fails to the calm terminal
    /// state whose copy names the possible causes, including the iOS 27 upgrade hint.
    @MainActor
    func testVanishedAlbumShowsCauseCopyIncludingUpgradeHint() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--uitest", "--uitest-slideshow", "--uitest-chrome",
                               "--uitest-photos-source", "--uitest-photos-auth=full",
                               "--uitest-photos-vanish"]
        app.launch()

        let error = app.staticTexts["slideshow.error"]
        XCTAssertTrue(error.waitForExistence(timeout: 5),
                      "a vanished collection should land in the calm error state")
        XCTAssertEqual(error.label, "This source is gone")

        let upgradeHint = app.staticTexts.containing(
            NSPredicate(format: "label CONTAINS %@", "iCloud")
        ).firstMatch
        XCTAssertTrue(upgradeHint.exists,
                      "the vanish copy should include the upgraded-iCloud-album hint (FR-900-16)")
    }

    /// FR-900-10 (T032) — the info overlay works for a Photos source through the neutral
    /// metadata path and renders DATE ONLY: no geocoding means no place line (R7), and an
    /// absent place renders nothing rather than a blank line.
    @MainActor
    func testPhotosSourceInfoOverlayShowsDateOnly() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--uitest", "--uitest-slideshow", "--uitest-chrome",
                               "--uitest-photos-source", "--uitest-photos-auth=full"]
        app.launch()

        let image = app.descendants(matching: .any).matching(identifier: "slideshow.image").firstMatch
        XCTAssertTrue(image.waitForExistence(timeout: 5))

        let infoButton = app.buttons["slideshow.chrome.info"]
        XCTAssertTrue(infoButton.waitForExistence(timeout: 3),
                      "the info affordance should exist for a Photos source")
        infoButton.tap()

        let card = app.descendants(matching: .any)
            .matching(identifier: "slideshow.info.card").firstMatch
        XCTAssertTrue(card.waitForExistence(timeout: 3), "info overlay should appear")

        // The fake gateway's capture date (June 2024) renders; no place line exists.
        let dateLine = app.staticTexts.containing(
            NSPredicate(format: "label CONTAINS %@", "2024")
        ).firstMatch
        XCTAssertTrue(dateLine.waitForExistence(timeout: 2),
                      "the capture date should render")
        XCTAssertFalse(app.staticTexts["Berlin, Germany"].exists,
                       "a Photos asset has no place — nothing must render for it")
    }

    /// FR-900-15 (T033) — quality honesty: with a Photos source active, the Display
    /// section notes the iCloud Shared Album pixel ceiling so the quality picker never
    /// implies better quality exists. (Immich sources keep the unannotated footer.)
    @MainActor
    func testPhotosSourceShowsQualityCeilingNote() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--uitest", "--uitest-slideshow", "--uitest-chrome",
                               "--uitest-settings", "--uitest-photos-source",
                               "--uitest-photos-auth=full"]
        app.launch()

        let note = app.descendants(matching: .any)
            .matching(identifier: "settings.quality.ceilingNote").firstMatch
        XCTAssertTrue(scrollToElement(note, in: app),
                      "the Display footer should note the shared-album quality ceiling")
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
