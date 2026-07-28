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

        // Album grid (stub albums a1/a2). Typed `.buttons` query rather than
        // `descendants(matching: .any)`: the card resolves as a Button (confirmed in the 27.0
        // hierarchy dump), and the any-type query inside a sheet can hand back an outer node whose
        // tap never reaches the NavigationLink.
        let album = app.buttons["album.row.a1"]
        XCTAssertTrue(album.waitForExistence(timeout: 5), "album grid should list the stub album")
        // Existence is not enough to tap: a card that is present but not hit-testable swallows
        // the tap, and the drill-in never happens (issue #50 — the 27.0 failure frame shows the
        // grid still on screen while the test waits for thumbnails).
        XCTAssertTrue(app.scrollUntilHittable(album), "the stub album card should be tappable")
        // A brief press rather than an instantaneous tap. A finger navigates here on 27.0
        // (confirmed manually on FramePhone), while a synthesized zero-duration tap did not —
        // nor did a coordinate tap. See issue #50.
        album.press(forDuration: 0.05)

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
