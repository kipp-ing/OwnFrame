//
//  AccentFilledControlGuardTests.swift
//  OwnFrameTests
//
//  9000 T003 (#59, FR-9000-38): a filled accent control must carry a near-black label on Messing.
//  The one shared style for that is PurchaseKit's `.accentProminent`, which wraps the system
//  prominent style and pins the label. A source scan keeps any iOS filled accent control from
//  using the bare system style, where SwiftUI picks a white label. `OwnFrameTV/` is deferred
//  (CLAUDE.md testing policy) and not scanned.
//

import Foundation
import Testing

// Compile-time, not a file-exists probe: on the simulator a missing path must still fail loudly.
#if targetEnvironment(simulator)
private let sourceTreeReachable = true
#else
private let sourceTreeReachable = false
#endif

@Suite(.enabled(if: sourceTreeReachable, "Reads the repo via #filePath: simulator only, a device has no access to the Mac's disk"))
struct AccentFilledControlGuardTests {

    private static let repoRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()

    private static let styleFile = "AccentProminentButtonStyle.swift"

    // @covers FR-9000-38
    @Test func filledAccentControlsUseTheSharedNearBlackLabelStyle() throws {
        var scanned = 0
        var hits: [String] = []
        for root in ["OwnFrame", "Packages/PurchaseKit/Sources"] {
            let directory = Self.repoRoot.appendingPathComponent(root)
            let enumerator = try #require(FileManager.default.enumerator(at: directory, includingPropertiesForKeys: nil))
            for case let url as URL in enumerator where url.pathExtension == "swift" {
                guard url.lastPathComponent != Self.styleFile else { continue }
                scanned += 1
                let lines = try String(contentsOf: url, encoding: .utf8).components(separatedBy: .newlines)
                for (index, line) in lines.enumerated() where line.contains("borderedProminent") {
                    hits.append("\(root)/…/\(url.lastPathComponent):\(index + 1)")
                }
            }
        }
        // A scan that silently read nothing would pass; require that it really read the sources.
        #expect(scanned > 50, "scanned only \(scanned) Swift files")
        #expect(hits.isEmpty, "use .buttonStyle(.accentProminent) instead (FR-9000-38): \(hits)")
    }

    @Test func theSharedStyleExists() {
        let path = Self.repoRoot
            .appendingPathComponent("Packages/PurchaseKit/Sources/PurchaseKit/UI")
            .appendingPathComponent(Self.styleFile).path
        #expect(FileManager.default.fileExists(atPath: path))
    }
}
