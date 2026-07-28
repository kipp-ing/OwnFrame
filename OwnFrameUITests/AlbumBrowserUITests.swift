//
//  AlbumBrowserUITests.swift
//  OwnFrameUITests
//
//  Slice B — drives the album-browser sheet against the hermetic
//  `--uitest --uitest-slideshow` build: reveal chrome, open Albums, drill into an
//  album's thumbnail grid, tap a thumbnail, and confirm it returns to the running
//  slideshow.
//

import XCTest

final class AlbumBrowserUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
        // Never inherit a rotation leaked by an earlier test on the same simulator
        // clone — a launch during a stale landscape state positions the chrome
        // off-screen. Tests that need landscape rotate themselves (and restore).
        MainActor.assumeIsolated { XCUIDevice.shared.orientation = .portrait }
    }

    @MainActor
    func testAlbumBrowserOpensDrillsInAndSelectionReturnsToSlideshow() throws {
        let app = XCUIApplication()
        // Pin the chrome so opening the browser isn't racing the idle auto-hide.
        app.launchArguments = ["--uitest", "--uitest-slideshow", "--uitest-chrome"]
        app.launch()

        let image = app.descendants(matching: .any)
            .matching(identifier: "slideshow.image").firstMatch
        XCTAssertTrue(image.waitForExistence(timeout: 5))

        // Open the album browser from the chrome.
        let albumsButton = app.buttons["slideshow.chrome.albums"]
        XCTAssertTrue(albumsButton.waitForExistence(timeout: 2))
        albumsButton.tap()

        // Album grid (stub albums a1/a2). NavigationLink may surface as a link/other
        // rather than a button, so match by identifier across any element type.
        let album = app.descendants(matching: .any).matching(identifier: "album.row.a1").firstMatch
        XCTAssertTrue(album.waitForExistence(timeout: 5), "album grid should list the stub album")
        // Existence is not enough to tap: a card that is present but not hit-testable swallows
        // the tap, and the drill-in never happens (issue #50 — the 27.0 failure frame shows the
        // grid still on screen while the test waits for thumbnails).
        XCTAssertTrue(app.scrollUntilHittable(album), "the stub album card should be tappable")
        // KNOWN FAILING ON iOS 27 (issue #50). The card is a proper Button in the tree at a valid
        // frame and is hittable, but neither an element tap nor a coordinate tap navigates — the
        // screen recording shows the grid simply sitting there for the rest of the test. Both were
        // tried; neither is a workaround, so the assertion below is left to report it honestly
        // rather than being routed around. Whether a HUMAN tap navigates on 27.0 is untested and
        // is the next thing to check: if it does not, this is a product bug in the
        // NavigationLink-in-LazyVGrid-in-sheet path, not a harness problem.
        album.tap()

        // Thumbnail grid → pick a photo.
        let thumb = app.descendants(matching: .any).matching(identifier: "album.thumbnail.asset-2").firstMatch
        XCTAssertTrue(thumb.waitForExistence(timeout: 5), "album thumbnails should appear")
        XCTAssertTrue(app.scrollUntilHittable(thumb), "the thumbnail should be tappable")
        thumb.tap()

        // Sheet dismisses; the slideshow is running again in fullscreen.
        XCTAssertTrue(image.waitForExistence(timeout: 3))
        let dismissed = NSPredicate(format: "isHittable == false")
        expectation(for: dismissed, evaluatedWith: album)
        waitForExpectations(timeout: 3)
    }
}
