// SourceVocabularyCatalogTests.swift — one concept, one name (spec 9000, FR-9000-26; issue #68).
//
// Each photo source has exactly one on-screen name, shared with the store listing:
// the Immich shared-album link source is "Immich link", the Apple Photos album source is
// "iCloud album". This reads every shipped iOS String Catalog from disk and fails if an
// English or German user-facing value still carries a retired source name.

import Foundation
import Testing

@Suite struct SourceVocabularyCatalogTests {

    /// Repo root: Tests/OnboardingKitTests/<this file> → Packages/OnboardingKit → repo.
    private static let repoRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent() // OnboardingKitTests
        .deletingLastPathComponent() // Tests
        .deletingLastPathComponent() // OnboardingKit
        .deletingLastPathComponent() // Packages
        .deletingLastPathComponent() // repo root

    /// The catalogs that must exist; the scan also picks up any other iOS-side catalog.
    private static let requiredCatalogs = [
        "OwnFrame/Localizable.xcstrings",
        "OwnFrame/AppShortcuts.xcstrings",
        "Packages/OnboardingKit/Sources/OnboardingKit/Localizable.xcstrings",
        "Packages/PurchaseKit/Sources/PurchaseKit/Localizable.xcstrings",
    ]

    /// Retired English source names (case-insensitive).
    private static let retiredEnglish = [
        #"\bshared[- ]links?\b"#,
        #"\bshare links?\b"#,
        #"\bphotos albums?\b"#,
        #"^photos$"#, // bare "Photos" used as the Apple Photos source's name
    ]

    /// Retired German source names (case-insensitive; lowercase regex fixtures only).
    private static let retiredGerman = [
        #"geteilte[nmrs]? links?\b"#,
        #"freigabe-?links?"#,
        #"fotos-alben?\b"#,
        #"fotos-album"#,
        #"^fotos$"#,
    ]

    // MARK: - Catalog reading

    private struct Entry {
        let catalog: String
        let key: String
        let english: [String]
        let german: [String]
    }

    private static func catalogPaths() throws -> [String] {
        var paths = Set(requiredCatalogs)
        let fileManager = FileManager.default
        for base in ["OwnFrame", "OwnFrameShareExtension", "Packages"] {
            let baseURL = repoRoot.appendingPathComponent(base)
            guard let enumerator = fileManager.enumerator(at: baseURL, includingPropertiesForKeys: nil) else {
                continue
            }
            for case let url as URL in enumerator where url.pathExtension == "xcstrings" {
                let relative = String(url.path.dropFirst(repoRoot.path.count + 1))
                if relative.contains("/.build/") { continue }
                if base == "Packages", !relative.contains("/Sources/") { continue }
                paths.insert(relative)
            }
        }
        return paths.sorted()
    }

    /// Collects every `stringUnit.value` under a localization, including plural/device variations.
    private static func stringUnitValues(_ node: Any) -> [String] {
        if let dict = node as? [String: Any] {
            var values: [String] = []
            if let unit = dict["stringUnit"] as? [String: Any], let value = unit["value"] as? String {
                values.append(value)
            }
            for (key, child) in dict where key != "stringUnit" {
                values += stringUnitValues(child)
            }
            return values
        }
        if let array = node as? [Any] {
            return array.flatMap(stringUnitValues)
        }
        return []
    }

    private static func entries() throws -> [Entry] {
        var result: [Entry] = []
        for relative in try catalogPaths() {
            let url = repoRoot.appendingPathComponent(relative)
            let data = try Data(contentsOf: url)
            let root = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
            let strings = try #require(root["strings"] as? [String: Any], "\(relative) has no strings")
            for (key, value) in strings {
                let json = value as? [String: Any] ?? [:]
                let localizations = json["localizations"] as? [String: Any] ?? [:]
                var english = localizations["en"].map(stringUnitValues) ?? []
                // Without an explicit English localization, the key itself is the English source.
                if english.isEmpty { english = [key] }
                let german = localizations["de"].map(stringUnitValues) ?? []
                result.append(Entry(catalog: relative, key: key, english: english, german: german))
            }
        }
        return result
    }

    private static func matches(_ text: String, _ patterns: [String]) -> String? {
        patterns.first { text.range(of: $0, options: [.regularExpression, .caseInsensitive]) != nil }
    }

    // MARK: - Tests

    // @covers FR-9000-26
    @Test func shippedCatalogsCarryNoRetiredSourceName() throws {
        for relative in Self.requiredCatalogs {
            let path = Self.repoRoot.appendingPathComponent(relative).path
            #expect(FileManager.default.fileExists(atPath: path), "missing catalog \(relative)")
        }

        let entries = try Self.entries()
        #expect(entries.count > 100, "expected to scan the shipped catalogs, found \(entries.count) entries")

        for entry in entries {
            for value in entry.english {
                if let pattern = Self.matches(value, Self.retiredEnglish) {
                    Issue.record("\(entry.catalog): English \"\(value)\" uses a retired source name (\(pattern))")
                }
            }
            for value in entry.german {
                if let pattern = Self.matches(value, Self.retiredGerman) {
                    Issue.record("\(entry.catalog): German value for \"\(entry.key)\" = \"\(value)\" uses a retired source name (\(pattern))")
                }
            }
        }
    }

    // @covers FR-9000-26
    @Test func shippedCatalogsNameEachSourceOnce() throws {
        let appCatalog = "OwnFrame/Localizable.xcstrings"
        let entries = try Self.entries().filter { $0.catalog == appCatalog }
        let byKey = Dictionary(entries.map { ($0.key, $0) }, uniquingKeysWith: { first, _ in first })

        let expected: [(key: String, germanContains: String)] = [
            ("Immich link", "Immich-Link"),
            ("Use an Immich link", "Immich-Link"),
            ("iCloud album", "iCloud-Album"),
            ("Use an iCloud album", "iCloud-Album"),
        ]
        for (key, germanName) in expected {
            let entry = try #require(byKey[key], "\(appCatalog) is missing the source name \"\(key)\"")
            #expect(
                entry.german.contains { $0.contains(germanName) },
                "German for \"\(key)\" should use \"\(germanName)\", got \(entry.german)"
            )
        }
    }
}
