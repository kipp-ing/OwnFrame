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
// second App-Group write (the "extension starts persisting a secret" case), networking creeping
// in, or a host-open call coming back (FR-210-31). If the files move, this test must fail loudly
// and be updated — never skipped.

private var repoRoot: URL {
    // …/Packages/OnboardingKit/Tests/OnboardingKitTests/<this file> → drop the file name,
    // then four directories, to reach the repo root.
    URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
}

/// Every Swift file of the extension, joined: the guards cover all extension code, not only
/// ShareViewController, so moving code into a second file can't slip past them.
private var shareExtensionSource: String {
    get throws {
        let folder = repoRoot.appendingPathComponent("OwnFrameShareExtension")
        let files = try FileManager.default.contentsOfDirectory(at: folder, includingPropertiesForKeys: nil)
            .filter { $0.pathExtension == "swift" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
        guard files.contains(where: { $0.lastPathComponent == "ShareViewController.swift" }) else {
            throw CocoaError(.fileNoSuchFile)
        }
        return try files.map { try String(contentsOf: $0, encoding: .utf8) }.joined(separator: "\n")
    }
}

/// The German `stringUnit` of `key` in the extension's String Catalog, or nil.
private func germanUnit(for key: String) throws -> [String: Any]? {
    let catalogURL = repoRoot.appendingPathComponent("OwnFrameShareExtension/Localizable.xcstrings")
    let data = try Data(contentsOf: catalogURL)
    let catalog = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    let strings = try #require(catalog["strings"] as? [String: Any])
    let entry = strings[key] as? [String: Any]
    let german = (entry?["localizations"] as? [String: Any])?["de"] as? [String: Any]
    return german?["stringUnit"] as? [String: Any]
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

// A Share extension cannot bring its host forward on iOS, so it must not pretend to.
// @covers FR-210-31
@Test func shareExtensionNeverTriesToOpenTheHost() throws {
    let source = try shareExtensionSource

    for forbidden in ["extensionContext?.open", "extensionContext.open", "openHost", "immichslideshow://"] {
        #expect(!source.contains(forbidden), "extension source still contains \(forbidden)")
    }
}

// Instead it tells the person to open OwnFrame, in English and German, and closes on Done.
// @covers FR-210-31
@Test func shareExtensionConfirmsWithALocalizedOpenOwnFrameMessage() throws {
    let source = try shareExtensionSource
    #expect(source.contains("\"Open OwnFrame to start\""))
    #expect(source.contains("\"share.confirmation.done\""))

    for key in ["Open OwnFrame to start", "Done"] {
        let unit = try germanUnit(for: key)
        #expect(unit?["state"] as? String == "translated", "\(key) has no translated German entry")
        #expect((unit?["value"] as? String)?.isEmpty == false, "\(key) has an empty German value")
    }
}
