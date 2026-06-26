import Foundation
import Testing
@testable import OnboardingKit

@Test func pendingSharedLinkStoreTakesSavedURLExactlyOnce() {
    let store = InMemoryPendingSharedLinkStore()
    let url = URL(string: "https://demo.example.com/s/abc")!

    store.savePendingURL(url)

    #expect(store.takePendingURL() == url)
    #expect(store.takePendingURL() == nil)
}

@Test func appGroupPendingSharedLinkStorePersistsOnlyURLString() {
    let suiteName = "PendingSharedLinkStoreTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defaults.removePersistentDomain(forName: suiteName)
    defer { defaults.removePersistentDomain(forName: suiteName) }
    let store = AppGroupPendingSharedLinkStore(suiteName: suiteName)
    let url = URL(string: "https://demo.example.com/s/abc")!

    store.savePendingURL(url)

    #expect(defaults.string(forKey: "pendingSharedLinkURL") == url.absoluteString)
    #expect(defaults.object(forKey: "password") == nil)
    #expect(defaults.object(forKey: "apiKey") == nil)
    #expect(defaults.object(forKey: "secret") == nil)
}

@Test func appGroupPendingSharedLinkStoreMissingSuiteDegradesGracefully() {
    let store = AppGroupPendingSharedLinkStore(suiteName: "")

    store.savePendingURL(URL(string: "https://demo.example.com/s/abc")!)

    #expect(store.takePendingURL() == nil)
}
