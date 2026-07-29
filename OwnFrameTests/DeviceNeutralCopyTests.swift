import Foundation
import Testing

// Issue #53: the Storage footer told an iPhone user that photos are kept on "this iPad".
// The app is iPad-first, but iPhone ships and the tvOS target shares several of these surfaces,
// where a hard-coded "iPad" is wrong twice over. Copy that names a device is only ever correct by
// accident, so this guards the whole catalogue rather than the one string that was reported.
//
// The catalogue is read from the source tree via `#filePath` — the compiled `.strings` in the test
// bundle would not carry the German translations of the *app* target, and it is the source of
// truth we actually want to pin.
struct DeviceNeutralCopyTests {

    /// Device names that must not appear in copy describing "the machine you are holding".
    /// `UnlockScreenView`'s deliberate "iPad, iPhone, and Apple TV" enumeration lives in
    /// PurchaseKit's own catalogue, so it is out of scope here by construction.
    private static let deviceNames = ["iPad", "iPhone", "Apple TV"]

    private static var catalogURL: URL {
        URL(fileURLWithPath: #filePath)          // OwnFrameTests/DeviceNeutralCopyTests.swift
            .deletingLastPathComponent()          // OwnFrameTests/
            .deletingLastPathComponent()          // repo root
            .appendingPathComponent("OwnFrame/Localizable.xcstrings")
    }

    private struct Catalog: Decodable {
        struct Entry: Decodable {
            struct Localization: Decodable {
                struct Unit: Decodable { let value: String }
                let stringUnit: Unit?
            }
            let localizations: [String: Localization]?
        }
        let strings: [String: Entry]
    }

    @Test func noUserFacingStringNamesTheDeviceItRunsOn() throws {
        let data = try Data(contentsOf: Self.catalogURL)
        let catalog = try JSONDecoder().decode(Catalog.self, from: data)

        var offenders: [String] = []
        for (key, entry) in catalog.strings {
            var candidates = [("en", key)]
            for (locale, localization) in entry.localizations ?? [:] {
                if let value = localization.stringUnit?.value { candidates.append((locale, value)) }
            }
            for (locale, text) in candidates where Self.deviceNames.contains(where: text.contains) {
                offenders.append("[\(locale)] \(text)")
            }
        }

        #expect(
            offenders.isEmpty,
            "copy names the device it runs on: \n\(offenders.sorted().joined(separator: "\n"))"
        )
    }
}
