import Foundation
import Testing
@testable import OnboardingKit
import ImmichClient

// 220: the welcome-screen overhaul adds a third first-run path — an on-device Photos /
// iCloud album, routed straight to its own setup step with no server/API key involved.
// These tests pin the new `.photoLibrary` routing alongside the existing paths and the
// `finish()` behavior for a `.photoLibrary` active source (no album config is written).

// @covers FR-220-02
@MainActor @Test func choosePathRoutesPhotoLibraryToSetup() {
    let vm = makeWelcomePathVM()
    vm.step = .choice
    vm.errorMessage = "stale"

    vm.choosePath(.photoLibrary)

    #expect(vm.step == .photoLibrarySetup)
    #expect(vm.errorMessage == nil)
}

// @covers FR-210-01
@MainActor @Test func choosePathStillRoutesSharedLinkToSetup() {
    let vm = makeWelcomePathVM()
    vm.step = .choice

    vm.choosePath(.sharedLink)

    #expect(vm.step == .sharedLinkSetup)
}

// @covers FR-210-01, FR-220-07
@MainActor @Test func choosePathStillRoutesServerToConnection() {
    let vm = makeWelcomePathVM()
    vm.step = .choice

    vm.choosePath(.server)

    #expect(vm.step == .connection)
}

// @covers FR-210-26
@MainActor @Test func canGoBackIsTrueAtPhotoLibrarySetup() {
    let vm = makeWelcomePathVM()

    vm.step = .photoLibrarySetup

    #expect(vm.canGoBack == true)
}

// @covers FR-210-26
@MainActor @Test func backFromPhotoLibrarySetupReturnsToChoice() {
    let vm = makeWelcomePathVM()
    vm.step = .photoLibrarySetup

    vm.back()

    #expect(vm.step == .choice)
}

// @covers FR-220-02
@MainActor @Test func finishFromPhotoLibraryOnlyPathCompletesWithoutAlbumConfig() {
    // The active source is a device Photos/iCloud album — no Immich connection is
    // involved, so `finish()` must not write an `AppConfiguration` (the `.album` guard
    // is skipped for `.photoLibrary`, same as for `.sharedLink`).
    let config = InMemoryConfigStore()
    let keychain = InMemoryKeychainStore()
    var library = SourceLibrary()
    library.add(Source(label: "Beach 2019", kind: .photoLibrary(collectionID: "col-1")))
    let sourceStore = InMemorySourceLibraryStore(library: library)
    let vm = makeWelcomePathVM(config: config, keychain: keychain, sourceStore: sourceStore)
    vm.step = .photoLibrarySetup

    vm.finish()

    #expect(vm.step == .done)
    #expect(keychain.read() == nil)
    #expect(config.load() == nil)
}

@MainActor private func makeWelcomePathVM(
    config: InMemoryConfigStore = .init(),
    keychain: InMemoryKeychainStore = .init(),
    sourceStore: InMemorySourceLibraryStore = .init()
) -> OnboardingViewModel {
    OnboardingViewModel(
        api: { _ in NeverCalledAPI() },
        config: config,
        keychain: keychain,
        sourceStore: sourceStore,
        connectionRetryLimit: 0,
        connectionRetryDelay: .zero,
        sleep: { _ in }
    )
}

/// A photo-library-only welcome path never touches the network — this fake fails loudly
/// if the view model calls it, rather than silently returning empty data.
private struct NeverCalledAPI: ImmichAPI {
    func serverVersion() async throws -> String {
        Issue.record("NeverCalledAPI.serverVersion() should not be called on the photo-library path")
        throw ImmichError.unreachable
    }

    func albums() async throws -> [Album] {
        Issue.record("NeverCalledAPI.albums() should not be called on the photo-library path")
        throw ImmichError.unreachable
    }

    func assets(albumID: String) async throws -> [Asset] {
        Issue.record("NeverCalledAPI.assets(albumID:) should not be called on the photo-library path")
        throw ImmichError.unreachable
    }

    func preview(assetID: String) async throws -> Data {
        Issue.record("NeverCalledAPI.preview(assetID:) should not be called on the photo-library path")
        throw ImmichError.unreachable
    }
}
