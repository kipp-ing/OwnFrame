import Foundation
import Testing
@testable import OnboardingKit

// The Share extension deliberately does NOT link OnboardingKit: ShareViewController duplicates
// the App-Group suite/key constants and writes UserDefaults directly, to stay thin and free of
// app-extension link constraints. That leaves FR-210-13's obligations (hand over the non-secret
// URL only, no network) enforced by no compiled test, and a constant drift would break the
// hand-off silently — the host would read a key the extension no longer writes (issue #28).
//
// This guard scans the extension's SOURCE, since no test target compiles it. Textual, but each
// assertion is chosen so the realistic regressions go red: a renamed constant on either side, a
// second App-Group write (the "extension starts persisting a secret" case), or networking
// creeping in. If the file moves, this test must fail loudly and be updated — never skipped.

private var shareExtensionSource: String {
    get throws {
        // …/Packages/OnboardingKit/Tests/OnboardingKitTests/<this file> → drop the file name,
        // then four directories, to reach the repo root.
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let file = repoRoot
            .appendingPathComponent("Immich SlideshowShareExtension")
            .appendingPathComponent("ShareViewController.swift")
        return try String(contentsOf: file, encoding: .utf8)
    }
}

// @covers FR-210-13
@Test func shareExtensionMirrorsTheAppGroupSuiteAndKeyConstants() throws {
    let source = try shareExtensionSource

    // The extension's duplicated literals must equal the store's — quoted, so a partial or
    // renamed value cannot slip through as a substring match on prose.
    #expect(source.contains("\"\(AppGroupPendingSharedLinkStore.defaultSuiteName)\""))
    #expect(source.contains("\"\(AppGroupPendingSharedLinkStore.pendingURLKey)\""))
}

// @covers FR-210-13
@Test func shareExtensionWritesExactlyThePendingURLAndNothingElse() throws {
    let source = try shareExtensionSource

    // One defaults write, and it is the pending-URL one. A second `.set(` — a password, an
    // API key, anything — makes the count 2 and this red.
    let writes = source.components(separatedBy: ".set(").count - 1
    #expect(writes == 1)
    let writeLine = source
        .components(separatedBy: .newlines)
        .filter { $0.contains(".set(") }
    #expect(writeLine.count == 1)
    #expect(writeLine.first?.contains("forKey: Self.pendingURLKey") == true)

    // "No network, no secret" (FR-210-13): the extension has no business touching either API.
    #expect(!source.contains("URLSession"))
    #expect(!source.contains("SecItem"))
}
