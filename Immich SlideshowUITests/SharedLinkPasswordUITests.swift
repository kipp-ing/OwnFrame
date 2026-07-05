//
//  SharedLinkPasswordUITests.swift
//  Immich SlideshowUITests
//
//  210 / US4 — ask-password-only-when-needed across both add-a-shared-link surfaces:
//  the onboarding source step and Settings → Sources. Neither surface shows an upfront
//  password field; the link is resolved first and a password is requested only when the
//  server reports one is required. A wrong password is a distinct error with nothing
//  persisted. Hermetic `--uitest` build: the stub resolver maps any link to album a2 and
//  reserves slug `protected` (password "letmein").
//

import XCTest

final class SharedLinkPasswordUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = false
    }

    // MARK: - Onboarding source step

    /// A non-protected link in the onboarding source step adds without ever showing a
    /// password field — the low-friction path.
    @MainActor
    func testOnboardingNonProtectedLinkAddsWithoutAskingForPassword() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--uitest"]
        app.launch()

        connect(app)
        openSharedLinkTab(app)

        XCTAssertFalse(app.textFields["onboarding.sharedLink.password"].exists,
                       "no upfront password field should be shown")

        enterURL(app, prefix: "onboarding.sharedLink", "https://demo.example.com/s/abc123")
        app.buttons["onboarding.sharedLink.add"].tap()

        // The added source surfaces the pinned Continue bar; no password was ever asked.
        XCTAssertTrue(app.buttons["onboarding.source.continue"].waitForExistence(timeout: 10),
                      "a non-protected link should add straight away")
        XCTAssertFalse(app.textFields["onboarding.sharedLink.password"].exists,
                       "a non-protected link must not prompt for a password")
    }

    /// A protected link prompts exactly once: a wrong password is a distinct error with
    /// nothing persisted; the correct password then adds the source.
    @MainActor
    func testOnboardingProtectedLinkPromptsWrongThenCorrect() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--uitest"]
        app.launch()

        connect(app)
        openSharedLinkTab(app)

        enterURL(app, prefix: "onboarding.sharedLink", "https://demo.example.com/s/protected")
        app.buttons["onboarding.sharedLink.add"].tap()

        // Wrong password → distinct error, still on the prompt, nothing added.
        let password = app.textFields["onboarding.sharedLink.password"]
        XCTAssertTrue(password.waitForExistence(timeout: 5), "a protected link should prompt for a password")
        password.tap()
        password.typeText("nope")
        app.buttons["onboarding.sharedLink.password.continue"].tap()

        XCTAssertTrue(app.staticTexts["onboarding.sharedLink.password.error"].waitForExistence(timeout: 5),
                      "a wrong password should surface a distinct error")
        XCTAssertFalse(app.buttons["onboarding.source.continue"].exists,
                       "nothing should be persisted on a wrong password")

        // Cancel and retry with the correct password → the source is added.
        app.buttons["onboarding.sharedLink.password.cancel"].tap()
        app.buttons["onboarding.sharedLink.add"].tap()
        let retry = app.textFields["onboarding.sharedLink.password"]
        XCTAssertTrue(retry.waitForExistence(timeout: 5))
        retry.tap()
        retry.typeText("letmein")
        app.buttons["onboarding.sharedLink.password.continue"].tap()

        XCTAssertTrue(app.buttons["onboarding.source.continue"].waitForExistence(timeout: 10),
                      "the correct password should add the source")
    }

    // MARK: - Settings → Sources

    /// A non-protected link added from Settings → Sources saves with no password field.
    @MainActor
    func testSettingsNonProtectedLinkAddsWithoutAskingForPassword() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--uitest", "--uitest-slideshow", "--uitest-chrome"]
        app.launch()

        let image = app.descendants(matching: .any).matching(identifier: "slideshow.image").firstMatch
        XCTAssertTrue(image.waitForExistence(timeout: 5))

        openSourcesAddSharedLink(app)

        XCTAssertFalse(app.textFields["sources.add.password"].exists,
                       "no upfront password field should be shown in Settings")

        enterURL(app, prefix: "sources.add", "https://demo.example.com/s/abc123")
        let label = app.textFields["sources.add.label"]
        label.tap()
        label.typeText("Shared Album")
        app.buttons["sources.add.submit"].tap()

        // The add sheet dismisses on success and the new row appears in the manager.
        XCTAssertTrue(app.buttons["Shared Album"].waitForExistence(timeout: 5),
                      "a non-protected link should add and dismiss the sheet")
    }

    /// A wrong password in Settings → Sources is a distinct error and the sheet stays open
    /// (nothing persisted — the SourceLibraryViewModel unit tests own the persistence guarantee).
    @MainActor
    func testSettingsProtectedLinkWrongPasswordErrorsAndPersistsNothing() throws {
        let app = XCUIApplication()
        app.launchArguments = ["--uitest", "--uitest-slideshow", "--uitest-chrome"]
        app.launch()

        let image = app.descendants(matching: .any).matching(identifier: "slideshow.image").firstMatch
        XCTAssertTrue(image.waitForExistence(timeout: 5))

        openSourcesAddSharedLink(app)

        enterURL(app, prefix: "sources.add", "https://demo.example.com/s/protected")
        app.buttons["sources.add.submit"].tap()

        let password = app.textFields["sources.add.password"]
        XCTAssertTrue(password.waitForExistence(timeout: 5), "a protected link should prompt for a password")
        password.tap()
        password.typeText("nope")
        app.buttons["sources.add.password.continue"].tap()

        XCTAssertTrue(app.staticTexts["sources.add.password.error"].waitForExistence(timeout: 5),
                      "a wrong password should surface a distinct error")
        // The prompt stays open (no save + dismiss) — nothing was persisted.
        XCTAssertTrue(app.buttons["sources.add.password.continue"].exists,
                      "a wrong password must keep the prompt open without persisting")
    }

    // MARK: - Helpers

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

    @MainActor
    private func openSharedLinkTab(_ app: XCUIApplication) {
        XCTAssertTrue(app.buttons["onboarding.album.a1"].waitForExistence(timeout: 5))
        app.buttons["Shared link"].tap()
    }

    @MainActor
    private func openSourcesAddSharedLink(_ app: XCUIApplication) {
        let settingsButton = app.buttons["slideshow.chrome.settings"]
        XCTAssertTrue(settingsButton.waitForExistence(timeout: 2))
        settingsButton.tap()

        let sources = app.descendants(matching: .any).matching(identifier: "settings.sources").firstMatch
        var swipes = 0
        while !sources.exists && swipes < 8 {
            app.swipeUp()
            swipes += 1
        }
        XCTAssertTrue(sources.waitForExistence(timeout: 3), "Sources row should be present in settings")
        sources.tap()

        app.buttons["sources.add"].tap()
        app.buttons["Shared link"].tap()
    }

    @MainActor
    private func enterURL(_ app: XCUIApplication, prefix: String, _ link: String) {
        let url = app.textFields["\(prefix).url"]
        XCTAssertTrue(url.waitForExistence(timeout: 5), "shared-link URL field should appear")
        url.tap()
        url.typeText(link)
    }
}
