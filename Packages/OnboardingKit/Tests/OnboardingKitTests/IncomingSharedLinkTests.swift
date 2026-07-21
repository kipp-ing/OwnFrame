import Foundation
import Testing
@testable import OnboardingKit

@Test func incomingSharedLinkRejectsInvalidURLBeforeConfigurationState() {
    let url = URL(string: "http://demo.example.com/s/abc")!

    #expect(IncomingSharedLink.route(url, library: SourceLibrary(), isConfigured: false) == .invalid)
}

@Test func incomingSharedLinkPrefillsOnboardingWhenNotConfigured() {
    let url = URL(string: "https://demo.example.com/s/abc")!

    #expect(IncomingSharedLink.route(url, library: SourceLibrary(), isConfigured: false) == .prefillOnboarding(url))
}

// @covers FR-210-16
@Test func incomingSharedLinkSwitchesToExistingSharedLinkSource() {
    let baseURL = URL(string: "https://demo.example.com")!
    let existing = Source(id: "shared-1", label: "Shared", kind: .sharedLink(baseURL: baseURL, slug: "abc"))
    let library = SourceLibrary(sources: [existing], activeID: existing.id)
    let url = URL(string: "https://demo.example.com/s/abc")!

    #expect(IncomingSharedLink.route(url, library: library, isConfigured: true) == .switchToExisting(sourceID: "shared-1"))
}

@Test func incomingSharedLinkAddsAndActivatesNewSharedLinkSource() {
    let url = URL(string: "https://demo.example.com/s/abc")!

    #expect(IncomingSharedLink.route(url, library: SourceLibrary(), isConfigured: true) == .addAndActivate(baseURL: URL(string: "https://demo.example.com")!, slug: "abc"))
}
