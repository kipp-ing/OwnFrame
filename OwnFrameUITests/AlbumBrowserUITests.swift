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
        album.tap()

        // Thumbnail grid → pick a photo.
        let thumb = app.descendants(matching: .any).matching(identifier: "album.thumbnail.asset-2").firstMatch
        XCTAssertTrue(thumb.waitForExistence(timeout: 5), "album thumbnails should appear")
        thumb.tap()

        // Sheet dismisses; the slideshow is running again in fullscreen.
        XCTAssertTrue(image.waitForExistence(timeout: 3))
        let dismissed = NSPredicate(format: "isHittable == false")
        expectation(for: dismissed, evaluatedWith: album)
        waitForExpectations(timeout: 3)
    }
}
