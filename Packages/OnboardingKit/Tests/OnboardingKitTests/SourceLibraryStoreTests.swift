import Foundation
import Testing
@testable import OnboardingKit

@Test func userDefaultsSourceLibraryStorePersistsJSONLibrary() {
    let defaults = makeSourceLibraryDefaults()
    let store = UserDefaultsSourceLibraryStore(defaults: defaults)
    var library = SourceLibrary()
    library.add(Source(id: "album-source", label: "Album", kind: .album(albumID: "album-1")))
    library.add(Source(id: "shared-source", label: "Shared", kind: .sharedLink(baseURL: URL(string: "https://photos.example.test")!, slug: "summer")))
    library.setActive(id: "shared-source")

    store.save(library)

    #expect(store.load() == library)
    let storedData = defaults.data(forKey: "immich.sourceLibrary")
    #expect(storedData != nil)
    #expect(defaults.string(forKey: "immich.sourceLibrary") == nil)
}

@Test func userDefaultsSourceLibraryStoreClearRemovesLibrary() {
    let defaults = makeSourceLibraryDefaults()
    let store = UserDefaultsSourceLibraryStore(defaults: defaults)
    var library = SourceLibrary()
    library.add(Source(id: "source-1", label: "Album", kind: .album(albumID: "album-1")))
    store.save(library)

    store.clear()

    #expect(store.load() == SourceLibrary())
}

@Test func userDefaultsSourceLibraryStoreMigratesLegacySelectedAlbumIDOnce() {
    let defaults = makeSourceLibraryDefaults()
    defaults.set("legacy-album", forKey: "immich.selectedAlbumID")
    let store = UserDefaultsSourceLibraryStore(defaults: defaults)

    let migrated = store.load()

    #expect(migrated.sources.count == 1)
    #expect(migrated.sources[0].label == "legacy-album")
    #expect(migrated.sources[0].kind == .album(albumID: "legacy-album"))
    #expect(migrated.activeID == migrated.sources[0].id)
    #expect(defaults.data(forKey: "immich.sourceLibrary") != nil)
    #expect(store.load() == migrated)
}

@Test func userDefaultsSourceLibraryStoreDoesNotMigrateWhenLibraryExists() {
    let defaults = makeSourceLibraryDefaults()
    let store = UserDefaultsSourceLibraryStore(defaults: defaults)
    var library = SourceLibrary()
    library.add(Source(id: "source-1", label: "Current", kind: .album(albumID: "album-1")))
    store.save(library)
    defaults.set("legacy-album", forKey: "immich.selectedAlbumID")

    #expect(store.load() == library)
}

@Test func userDefaultsSourceLibraryStorePersistsPhotoLibrarySource() {
    let defaults = makeSourceLibraryDefaults()
    let store = UserDefaultsSourceLibraryStore(defaults: defaults)
    var library = SourceLibrary()
    library.add(Source(id: "album-source", label: "Album", kind: .album(albumID: "album-1")))
    library.add(Source(id: "shared-source", label: "Shared", kind: .sharedLink(baseURL: URL(string: "https://photos.example.test")!, slug: "summer")))
    library.add(Source(id: "photos-source", label: "Selected Photos", kind: .photoLibrary(collectionID: "selected-photos")))
    library.setActive(id: "photos-source")

    store.save(library)

    #expect(store.load() == library)
    #expect(store.load().active?.kind == .photoLibrary(collectionID: "selected-photos"))
}

@Test func inMemorySourceLibraryStoreRoundTripsAndClears() {
    let store = InMemorySourceLibraryStore()
    var library = SourceLibrary()
    library.add(Source(id: "source-1", label: "Album", kind: .album(albumID: "album-1")))

    store.save(library)
    #expect(store.load() == library)

    store.clear()
    #expect(store.load() == SourceLibrary())
}

private func makeSourceLibraryDefaults() -> UserDefaults {
    let suiteName = "SourceLibraryStoreTests.\(UUID().uuidString)"
    let defaults = UserDefaults(suiteName: suiteName)!
    defaults.removePersistentDomain(forName: suiteName)
    return defaults
}
