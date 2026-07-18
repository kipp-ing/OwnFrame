//
//  WelcomeICloudUITests.swift
//  Immich SlideshowUITests
//
//  220 / US1 (T008) — the iCloud/Photos-album welcome path is the lowest-friction option
//  and sits at the TOP of the first-run choice screen, above the shared-link and server
//  rows. Picking it reuses the 900 Photos-album picker (idPrefix "onboarding.photos");
//  adding an album finishes onboarding straight into the slideshow on the Photos backend,
//  with no server involved. `--uitest-photos-auth=full` scripts the authorization outcome
//  so no real PhotoKit prompt ever appears.
//

import XCTest

final class WelcomeICloudUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
        // Never inherit a rotation leaked by an earlier test on the same simulator
        // clone — a launch during a stale landscape state positions the chrome
        // off-screen. Tests that need landscape rotate themselves (and restore).
        MainActor.assumeIsolated { XCUIDevice.shared.orientation = .portrait }
    }

    /// The welcome screen's top option is the iCloud/Photos-album path (friction order:
    /// iCloud album first, then shared link, then server). Tapping it reaches the reused
    /// Photos-album picker; selecting an album finishes onboarding directly into the
    /// slideshow on the Photos backend — no server, no API key.
    @MainActor
    func testICloudAlbumIsTopChoiceAndReachesSlideshow() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--uitest", "--uitest-onboarding-choice", "--uitest-photos-auth=full"]
        app.launch()

        let photoLibraryRow = app.buttons["onboarding.choice.photoLibrary"]
        let sharedLinkRow = app.buttons["onboarding.choice.sharedLink"]
        let serverRow = app.buttons["onboarding.choice.server"]
        XCTAssertTrue(photoLibraryRow.waitForExistence(timeout: 5),
                      "the welcome screen should offer an iCloud/Photos-album path")
        XCTAssertTrue(sharedLinkRow.waitForExistence(timeout: 2))
        XCTAssertTrue(serverRow.waitForExistence(timeout: 2))

        // Friction order (220): the iCloud album option sits ABOVE both other rows.
        XCTAssertLessThan(photoLibraryRow.frame.minY, sharedLinkRow.frame.minY,
                          "the iCloud album row should be above the shared-link row")
        XCTAssertLessThan(photoLibraryRow.frame.minY, serverRow.frame.minY,
                          "the iCloud album row should be above the server row")

        photoLibraryRow.tap()

        // The reused Photos-album picker (same idPrefix as the 900 onboarding source step).
        let family = app.buttons["onboarding.photos.pl-family"]
        XCTAssertTrue(family.waitForExistence(timeout: 5),
                      "album Family should be listed in the reused Photos picker")
        family.tap()

        // Adding the album finishes onboarding straight into the slideshow — no server,
        // no separate confirm step for this lowest-friction path.
        let image = app.descendants(matching: .any).matching(identifier: "slideshow.image").firstMatch
        XCTAssertTrue(image.waitForExistence(timeout: 5),
                      "finishing the iCloud welcome path should start the slideshow")
        let photosAsset = NSPredicate(format: "value IN %@", ["pl-asset-1", "pl-asset-2", "pl-asset-3"])
        expectation(for: photosAsset, evaluatedWith: image)
        waitForExpectations(timeout: 5)
    }
}
