import Foundation
import Testing
@testable import OnboardingKit

// @covers FR-200-09
@Test func userDefaultsConfigStoreLoadsSavedConfiguration() throws {
    let defaults = makeDefaults()
    let store = UserDefaultsConfigStore(defaults: defaults)
    let configuration = AppConfiguration(
        baseURL: try #require(URL(string: "https://photos.example.test")),
        selectedAlbumID: "album-1"
    )

    store.save(configuration)

    #expect(store.load() == configuration)
}

@Test func userDefaultsConfigStoreClearRemovesSavedConfiguration() throws {
    let defaults = makeDefaults()
    let store = UserDefaultsConfigStore(defaults: defaults)
    let configuration = AppConfiguration(
        baseURL: try #require(URL(string: "https://photos.example.test")),
        selectedAlbumID: "album-1"
    )
    store.save(configuration)

    store.clear()

    #expect(store.load() == nil)
}

@Test func userDefaultsConfigStoreLoadReturnsNilWhenOnlyBaseURLExists() {
    let defaults = makeDefaults()
    defaults.set("https://photos.example.test", forKey: "immich.baseURL")
    let store = UserDefaultsConfigStore(defaults: defaults)

    #expect(store.load() == nil)
}

@Test func userDefaultsConfigStoreLoadsBaseURLWithoutSelectedAlbumID() throws {
    let defaults = makeDefaults()
    defaults.set("https://photos.example.test", forKey: "immich.baseURL")
    let store = UserDefaultsConfigStore(defaults: defaults)

    #expect(store.loadBaseURL() == URL(string: "https://photos.example.test"))
}

@Test func userDefaultsConfigStoreLoadReturnsNilWhenOnlySelectedAlbumIDExists() {
    let defaults = makeDefaults()
    defaults.set("album-1", forKey: "immich.selectedAlbumID")
    let store = UserDefaultsConfigStore(defaults: defaults)

    #expect(store.load() == nil)
}

@Test func userDefaultsConfigStoreLoadReturnsNilForNonHTTPSURL() {
    let defaults = makeDefaults()
    defaults.set("http://photos.example.test", forKey: "immich.baseURL")
    defaults.set("album-1", forKey: "immich.selectedAlbumID")
    let store = UserDefaultsConfigStore(defaults: defaults)

    #expect(store.load() == nil)
}

@Test func userDefaultsConfigStoreSaveBaseURLPersistsBaseURLWithoutSelectedAlbum() throws {
    let defaults = makeDefaults()
    let store = UserDefaultsConfigStore(defaults: defaults)

    store.saveBaseURL(try #require(URL(string: "https://photos.example.test")))

    // baseURL is readable on its own (a shared-link-first install has no album),
    // while load() stays nil until a selected album exists (120).
    #expect(store.loadBaseURL() == URL(string: "https://photos.example.test"))
    #expect(store.load() == nil)
}

@Test func userDefaultsConfigStoreSaveBaseURLLeavesExistingSelectedAlbumIntact() throws {
    let defaults = makeDefaults()
    let store = UserDefaultsConfigStore(defaults: defaults)
    let url = try #require(URL(string: "https://photos.example.test"))
    store.save(AppConfiguration(baseURL: url, selectedAlbumID: "album-1"))

    store.saveBaseURL(try #require(URL(string: "https://new.example.test")))

    #expect(store.loadBaseURL() == URL(string: "https://new.example.test"))
    #expect(store.load()?.selectedAlbumID == "album-1")
}

@Test func userDefaultsConfigStoreLoadReturnsNilForHTTPSURLWithoutHost() {
    let defaults = makeDefaults()
    defaults.set("https:photos.example.test", forKey: "immich.baseURL")
    defaults.set("album-1", forKey: "immich.selectedAlbumID")
    let store = UserDefaultsConfigStore(defaults: defaults)

    #expect(store.load() == nil)
}

private func makeDefaults() -> UserDefaults {
    let suiteName = "OnboardingKitTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defaults.removePersistentDomain(forName: suiteName)
    return defaults
}
