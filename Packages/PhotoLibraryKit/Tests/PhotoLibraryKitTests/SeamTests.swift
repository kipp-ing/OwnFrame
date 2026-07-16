// SeamTests.swift — enforces the PhotoKit seam: `import Photos` may appear only in PHKitGateway.swift (spec 900, T016).

import Foundation
import Testing

@Suite struct SeamTests {

    /// The whole point of `PhotoLibraryGateway` is that exactly one file — `PHKitGateway.swift`
    /// — imports Photos; everything else is host-testable pure logic (R4). This walks the
    /// package's `Sources/` and fails if `import Photos` leaks into any other file. It holds
    /// vacuously today (PHKitGateway.swift does not exist yet) and keeps holding once T017
    /// adds it, so the seam can never silently erode.
    @Test func photosImportIsConfinedToPHKitGateway() throws {
        let sourcesURL = Self.packageSourcesURL()
        let fileManager = FileManager.default
        let enumerator = try #require(
            fileManager.enumerator(at: sourcesURL, includingPropertiesForKeys: nil),
            "Could not enumerate package sources at \(sourcesURL.path)"
        )

        // Matches `import Photos`, `import Photos.PHAsset`, and `@preconcurrency import Photos`
        // while ignoring sibling modules like `PhotoSourceKit` / `PhotosUI` (word boundary).
        let photosImportPattern = #"(?m)^[ \t]*(?:@[A-Za-z_]+[ \t]+)?import[ \t]+Photos\b"#

        var scannedSwiftFiles = 0
        for case let fileURL as URL in enumerator where fileURL.pathExtension == "swift" {
            scannedSwiftFiles += 1
            let contents = try String(contentsOf: fileURL, encoding: .utf8)
            let importsPhotos = contents.range(of: photosImportPattern, options: .regularExpression) != nil
            if importsPhotos {
                #expect(
                    fileURL.lastPathComponent == "PHKitGateway.swift",
                    "`import Photos` is only allowed in PHKitGateway.swift, but appears in \(fileURL.lastPathComponent)"
                )
            }
        }

        // Guards against a wrong Sources path making the assertion pass vacuously.
        #expect(scannedSwiftFiles > 0, "Expected to scan at least one Swift source file under \(sourcesURL.path)")
    }

    /// `Sources/` resolved relative to this test file:
    /// `<pkg>/Tests/PhotoLibraryKitTests/SeamTests.swift` → up 3 → `<pkg>` → `Sources`.
    private static func packageSourcesURL() -> URL {
        URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()   // PhotoLibraryKitTests
            .deletingLastPathComponent()   // Tests
            .deletingLastPathComponent()   // package root
            .appendingPathComponent("Sources", isDirectory: true)
    }
}
