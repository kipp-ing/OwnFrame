import Foundation
import Testing
@testable import OnboardingKit

// 220: pins the pre-existing 900 startup-parity behavior against regression as the welcome
// screen gains a photo-library path. A `.photoLibrary`-only active source needs no Immich
// connection at all — no API key, no saved base URL — so a relaunch must resume straight
// into the slideshow rather than re-onboarding.

@Test func startupGateReturnsDoneForPhotoLibraryOnlyActiveSourceWithNoConnection() {
    let config = InMemoryConfigStore()
    let keychain = InMemoryKeychainStore()
    var library = SourceLibrary()
    library.add(Source(label: "Beach 2019", kind: .photoLibrary(collectionID: "col-1")))
    let sourceStore = InMemorySourceLibraryStore(library: library)
    let gate = StartupGate(config: config, keychain: keychain, sourceStore: sourceStore)

    #expect(gate.initialStep() == .done)
}
