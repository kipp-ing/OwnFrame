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
        // On iOS 27 no synthesized tap navigates this NavigationLink — element tap, coordinate
        // tap and a brief press were all tried, and the screen recording shows the grid simply
        // sitting there. A FINGER does navigate (verified manually on FramePhone/27.0), so the
        // app is fine and this is XCUITest synthesis. Recorded as an expected failure rather
        // than skipped, so the rest of the test still runs on 27 and the whole thing keeps
        // guarding 17–26 normally. `isStrict` means XCTest fails the test if the drill-in ever
        // starts working, which is the prompt to delete this block. See issue #50.
        //
        // Runtime check, not `#available`: the app is built against the iOS 26.5 SDK, which has
        // no iOS 27 availability symbol to compile against.
        if ProcessInfo.processInfo.operatingSystemVersion.majorVersion >= 27 {
            XCTExpectFailure(
                "iOS 27: synthesized taps do not activate a NavigationLink in a LazyVGrid in a sheet (#50)",
                strict: true
            )
        }
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
