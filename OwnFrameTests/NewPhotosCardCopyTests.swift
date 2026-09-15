import Foundation
import Testing

// The new-photos arrival card (310, FR-310-14) is on by default and appears on the App Store's
// share tile, yet its three strings never reached the String Catalog: a German frame showed
// "+1 new photo" / "Updated automatically" in English. Found by the German store-screenshot
// capture run, 2026-09-13. `NewPhotosOverlayView` already goes through `String(localized:)` and
// `Text("…")`, so the catalog entries are the whole fix — this pins them.
//
// Read from the source tree via `#filePath`, like `DeviceNeutralCopyTests`: the test bundle's
// compiled strings would not carry the app target's German translations. Simulator only, gated at
// compile time so a missing catalogue on the simulator still fails loudly.
#if targetEnvironment(simulator)
private let sourceTreeReachable = true
#else
private let sourceTreeReachable = false
#endif

@Suite(.enabled(if: sourceTreeReachable, "Reads the repo via #filePath: simulator only, a device has no access to the Mac's disk"))
struct NewPhotosCardCopyTests {

    /// The keys exactly as `NewPhotosOverlayView` produces them; an `Int` interpolation is `%lld`.
    private static let cardKeys = ["Updated automatically", "+1 new photo", "+%lld new photos"]

    private static var catalogURL: URL {
        URL(fileURLWithPath: #filePath)          // OwnFrameTests/NewPhotosCardCopyTests.swift
            .deletingLastPathComponent()          // OwnFrameTests/
            .deletingLastPathComponent()          // repo root
            .appendingPathComponent("OwnFrame/Localizable.xcstrings")
    }

    private struct Catalog: Decodable {
        struct Entry: Decodable {
            struct Localization: Decodable {
                struct Unit: Decodable { let state: String?; let value: String }
                let stringUnit: Unit?
            }
            let localizations: [String: Localization]?
        }
        let strings: [String: Entry]
    }

    @Test(arguments: cardKeys)
    func cardStringIsTranslatedIntoGerman(_ key: String) throws {
        let data = try Data(contentsOf: Self.catalogURL)
        let catalog = try JSONDecoder().decode(Catalog.self, from: data)

        let entry = try #require(catalog.strings[key], "the card string \(key) is missing from the catalog")
        let german = try #require(entry.localizations?["de"]?.stringUnit, "no German translation for \(key)")
        #expect(german.state == "translated")
        #expect(!german.value.isEmpty && german.value != key, "German for \(key) is still the English source")
        if key.contains("%lld") {
            #expect(german.value.contains("%lld"), "German for \(key) lost its count placeholder")
        }
    }
}
