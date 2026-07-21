import Foundation
import ImmichClient
import Testing
@testable import OnboardingKit

// T011 (220, US2): a scanned shared-link QR code must route through the exact same resolve
// path a typed link uses (FR-220-04 parity), a code that isn't a usable Immich share link
// must be rejected calmly with no network call and nothing persisted (FR-220-06), and a
// cancelled scan (no code) must be a silent no-op.

@MainActor
// @covers FR-220-04, FR-120-12, FR-220-12
@Test func addScannedSharedLinkResolvesTheSameAsATypedLink() async {
    let store = InMemorySourceLibraryStore()
    let resolver = ScanStubResolver()
    let vm = SourceLibraryViewModel(store: store, secretStore: InMemorySharedLinkSecretStore(), resolver: resolver)
    let decoded = "https://host.example/s/abc123"
    let scanner = ScriptedScanner(result: decoded)

    await vm.addScannedSharedLink(using: scanner, label: "")

    let expectedParsed = SharedLinkURL.parse(decoded)!
    #expect(resolver.requests.count == 1)
    #expect(resolver.requests[0].baseURL == expectedParsed.baseURL)
    #expect(resolver.requests[0].slug == expectedParsed.slug)
    #expect(resolver.requests[0].password == nil)
    #expect(vm.sources.count == 1)
    if case .resolved(let sourceID) = vm.addState {
        #expect(sourceID == vm.sources[0].id)
    } else {
        Issue.record("expected .resolved, got \(vm.addState)")
    }
    #expect(store.load().sources.count == 1)
}

// T034 (120, US2): FR-120-12 — the shared add-source form (Settings → Sources, onboarding step 2)
// offers the same scan, and it carries the optional name typed alongside the link. The onboarding
// first-run path passes "" and keeps falling back to the host-derived label.

@MainActor
// @covers FR-120-12
@Test func addScannedSharedLinkKeepsTheTypedLabel() async {
    let store = InMemorySourceLibraryStore()
    let resolver = ScanStubResolver()
    let vm = SourceLibraryViewModel(store: store, secretStore: InMemorySharedLinkSecretStore(), resolver: resolver)
    let scanner = ScriptedScanner(result: "https://host.example/s/abc123")

    await vm.addScannedSharedLink(using: scanner, label: "Iceland 2021")

    #expect(vm.sources.count == 1)
    #expect(vm.sources[0].label == "Iceland 2021")
    #expect(store.load().sources[0].label == "Iceland 2021")
}

@MainActor
@Test func addScannedSharedLinkWithoutALabelStillDerivesOne() async {
    let store = InMemorySourceLibraryStore()
    let resolver = ScanStubResolver()
    let vm = SourceLibraryViewModel(store: store, secretStore: InMemorySharedLinkSecretStore(), resolver: resolver)
    let scanner = ScriptedScanner(result: "https://host.example/s/abc123")

    await vm.addScannedSharedLink(using: scanner, label: "")

    #expect(vm.sources.count == 1)
    #expect(!vm.sources[0].label.isEmpty)
}

@MainActor
// @covers FR-220-06
@Test func addScannedSharedLinkRejectsNonURLWithoutNetwork() async {
    await assertCalmRejection(decoded: "just some text")
}

@MainActor
// @covers FR-220-06
@Test func addScannedSharedLinkRejectsNonHTTPSWithoutNetwork() async {
    await assertCalmRejection(decoded: "http://host.example/s/abc")
}

@MainActor
// @covers FR-220-06
@Test func addScannedSharedLinkRejectsNonShareLinkWithoutNetwork() async {
    await assertCalmRejection(decoded: "https://host.example")
}

@MainActor
@Test func addScannedSharedLinkCancelledScanIsANoOp() async {
    let store = InMemorySourceLibraryStore()
    let resolver = ScanStubResolver()
    let vm = SourceLibraryViewModel(store: store, secretStore: InMemorySharedLinkSecretStore(), resolver: resolver)
    let scanner = ScriptedScanner(result: nil)

    await vm.addScannedSharedLink(using: scanner, label: "")

    #expect(vm.addState == .idle)
    #expect(resolver.requests.isEmpty)
    #expect(vm.sources.isEmpty)
    #expect(store.load().sources.isEmpty)
}

// MARK: - Helpers

@MainActor
private func assertCalmRejection(decoded: String) async {
    let store = InMemorySourceLibraryStore()
    let resolver = ScanStubResolver()
    let vm = SourceLibraryViewModel(store: store, secretStore: InMemorySharedLinkSecretStore(), resolver: resolver)
    let scanner = ScriptedScanner(result: decoded)

    await vm.addScannedSharedLink(using: scanner, label: "")

    #expect(resolver.requests.isEmpty)
    if case .error = vm.addState {} else { Issue.record("expected .error, got \(vm.addState)") }
    #expect(vm.sources.isEmpty)
    #expect(store.load().sources.isEmpty)
}

/// A `CodeScanning` fake that returns a single scripted decoded string (or `nil` for a
/// cancelled scan) from `scan()`.
private struct ScriptedScanner: CodeScanning {
    let result: String?

    func scan() async -> String? {
        result
    }
}

/// A `SharedLinkResolving` fake that always succeeds and records every call, so the parity
/// test can assert it was invoked with the exact same `(baseURL, slug)` a typed link would
/// produce, and the rejection tests can assert it was never invoked.
private final class ScanStubResolver: SharedLinkResolving, @unchecked Sendable {
    struct Request: Equatable {
        let baseURL: URL
        let slug: String
        let password: String?
    }

    private(set) var requests: [Request] = []

    func resolve(baseURL: URL, slug: String, password: String?) async throws -> SharedLinkResolution {
        requests.append(Request(baseURL: baseURL, slug: slug, password: password))
        return SharedLinkResolution(key: "k", albumID: "a", expiresAt: nil)
    }
}
