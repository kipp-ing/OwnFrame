//
//  SourceOnboardingUITests.swift
//  Immich SlideshowUITests
//
//  120 / US2 — first-run onboarding adds the first slideshow source. After connecting,
//  the user adds either an Immich album (picker) or a shared link (URL + optional
//  password), confirms the library, and lands on the running slideshow playing the
//  chosen source. Hermetic `--uitest` build: stub API + in-memory stores shared between
//  onboarding and the slideshow, so the onboarded source actually drives the show.
//

import XCTest

final class SourceOnboardingUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
        // Never inherit a rotation leaked by an earlier test on the same simulator
        // clone — a launch during a stale landscape state positions the chrome
        // off-screen. Tests that need landscape rotate themselves (and restore).
        MainActor.assumeIsolated { XCUIDevice.shared.orientation = .portrait }
    }

    /// Album path: connect → pick album a1 → confirm → slideshow plays a1 (asset-1…3).
    @MainActor
    func testOnboardingAddAlbumSourceReachesSlideshow() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--uitest"]
        app.launch()

        connect(app)

        // Source step: pick the first stubbed album, then continue to confirmation.
        let album = app.buttons["onboarding.album.a1"]
        XCTAssertTrue(album.waitForExistence(timeout: 5), "stubbed album row should appear")
        album.tap()

        // The Continue button appears once the source is added (async state update).
        let cont = app.buttons["onboarding.source.continue"]
        XCTAssertTrue(cont.waitForExistence(timeout: 5), "Continue should appear after adding a source")
        cont.tap()

        // Confirmation step lists the library; start the slideshow.
        let start = app.buttons["onboarding.confirm.start"]
        XCTAssertTrue(start.waitForExistence(timeout: 5), "confirmation step should offer Start")
        start.tap()

        // The chosen album source plays: a1 → asset-1…3.
        let image = app.descendants(matching: .any).matching(identifier: "slideshow.image").firstMatch
        XCTAssertTrue(image.waitForExistence(timeout: 30), "onboarding should route to the running slideshow")
        let plays = NSPredicate(format: "value IN %@", ["asset-1", "asset-2", "asset-3"])
        expectation(for: plays, evaluatedWith: image)
        waitForExpectations(timeout: 5)
    }

    /// Shared-link path: connect → add a shared link (validated by the stub resolver,
    /// which maps any link to album a2) → confirm → slideshow plays a2 (asset-4…6).
    @MainActor
    func testOnboardingAddSharedLinkSourceReachesSlideshow() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--uitest"]
        app.launch()

        connect(app)

        // Switch the source kind to a shared link and fill the form.
        XCTAssertTrue(app.buttons["onboarding.album.a1"].waitForExistence(timeout: 5))
        app.buttons["Shared link"].tap()

        let url = app.textFields["onboarding.sharedLink.url"]
        XCTAssertTrue(url.waitForExistence(timeout: 3))
        url.tap()
        url.typeText("https://demo.example.com/s/abc123")

        let label = app.textFields["onboarding.sharedLink.label"]
        label.tap()
        label.typeText("Korsika 2026")

        app.buttons["onboarding.sharedLink.add"].tap()

        // The added source appears once the link resolves; continue and start.
        let cont = app.buttons["onboarding.source.continue"]
        XCTAssertTrue(cont.waitForExistence(timeout: 10), "Continue should appear after the link resolves")
        cont.tap()
        let start = app.buttons["onboarding.confirm.start"]
        XCTAssertTrue(start.waitForExistence(timeout: 5))
        start.tap()

        // The shared link resolves to album a2 → asset-4…6.
        let image = app.descendants(matching: .any).matching(identifier: "slideshow.image").firstMatch
        XCTAssertTrue(image.waitForExistence(timeout: 30), "onboarding should route to the running slideshow")
        let plays = NSPredicate(format: "value IN %@", ["asset-4", "asset-5", "asset-6"])
        expectation(for: plays, evaluatedWith: image)
        waitForExpectations(timeout: 5)
    }

    /// Landscape: the same album onboarding flow renders and completes when the device is
    /// rotated (the iPad's primary orientation). Guards the Form/List layout in landscape.
    @MainActor
    func testOnboardingAddAlbumSourceReachesSlideshowInLandscape() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--uitest"]
        app.launch()
        XCUIDevice.shared.orientation = .landscapeLeft
        defer { XCUIDevice.shared.orientation = .portrait }

        connect(app)

        let album = app.buttons["onboarding.album.a1"]
        XCTAssertTrue(album.waitForExistence(timeout: 5), "album row should appear in landscape")
        album.tap()

        let cont = app.buttons["onboarding.source.continue"]
        XCTAssertTrue(cont.waitForExistence(timeout: 5), "Continue should appear after adding a source")
        cont.tap()

        let start = app.buttons["onboarding.confirm.start"]
        XCTAssertTrue(start.waitForExistence(timeout: 5), "confirmation step should offer Start")
        start.tap()

        let image = app.descendants(matching: .any).matching(identifier: "slideshow.image").firstMatch
        XCTAssertTrue(image.waitForExistence(timeout: 30), "onboarding should route to the running slideshow")
        let plays = NSPredicate(format: "value IN %@", ["asset-1", "asset-2", "asset-3"])
        expectation(for: plays, evaluatedWith: image)
        waitForExpectations(timeout: 5)
    }

    // MARK: - Helpers

    /// Drive the combined connection step (server URL + API key on one screen).
    @MainActor
    private func connect(_ app: XCUIApplication) {
        let serverField = app.textFields["onboarding.serverURL"]
        XCTAssertTrue(serverField.waitForExistence(timeout: 5), "server URL field should appear")
        serverField.tap()
        serverField.typeText("https://demo.example.com")

        let keyField = app.textFields["onboarding.apiKey"]
        XCTAssertTrue(keyField.waitForExistence(timeout: 5), "API key field should appear")
        keyField.tap()
        keyField.typeText("dummy-key")

        app.buttons["onboarding.connection.continue"].tap()
    }
}
