import Foundation
import Testing

// FR-9000-05/-06 (issue #70): the app is dark on every app-drawn screen, whatever the system
// setting, and that is declared exactly once per `@main` entry point — never per screen, so a new
// sheet cannot quietly opt out. The rendered appearance is checked on the simulator; what a host
// test can pin is the declaration contract itself, read from the source tree via `#filePath`.
//
// @covers FR-9000-05
// @covers FR-9000-06
struct AppearanceRootTests {

    private static let declaration = ".preferredColorScheme(.dark)"

    private static var repoRoot: URL {
        URL(fileURLWithPath: #filePath)           // OwnFrameTests/AppearanceRootTests.swift
            .deletingLastPathComponent()           // OwnFrameTests/
            .deletingLastPathComponent()           // repo root
    }

    /// The two `@main` entry points FR-9000-06 names.
    private static let entryPoints = ["OwnFrame/OwnFrameApp.swift", "OwnFrameTV/TVRootView.swift"]

    /// Every Swift source that ships UI: both app targets and all package sources.
    private static func shippedSwiftFiles() throws -> [String] {
        let fm = FileManager.default
        var roots = ["OwnFrame", "OwnFrameTV", "OwnFrameShareExtension"]
        let packages = repoRoot.appendingPathComponent("Packages")
        for package in try fm.contentsOfDirectory(atPath: packages.path) {
            roots.append("Packages/\(package)/Sources")
        }
        var files: [String] = []
        for root in roots {
            let url = repoRoot.appendingPathComponent(root)
            guard let walker = fm.enumerator(atPath: url.path) else { continue }
            for case let relative as String in walker
            where relative.hasSuffix(".swift") && !relative.contains(".build/") {
                files.append("\(root)/\(relative)")
            }
        }
        return files
    }

    private static func occurrences(in path: String) throws -> Int {
        let text = try String(contentsOf: repoRoot.appendingPathComponent(path), encoding: .utf8)
        return text.components(separatedBy: "preferredColorScheme(").count - 1
    }

    @Test(arguments: entryPoints)
    func entryPointDeclaresDarkExactlyOnce(_ path: String) throws {
        let text = try String(contentsOf: Self.repoRoot.appendingPathComponent(path), encoding: .utf8)
        #expect(text.components(separatedBy: Self.declaration).count - 1 == 1,
                "\(path) must declare \(Self.declaration) exactly once at its root")
    }

    @Test func noScreenDeclaresItsOwnAppearance() throws {
        let files = try Self.shippedSwiftFiles()
        #expect(files.count > 50, "the source walk resolved almost nothing — check the roots")
        let offenders = try files
            .filter { !Self.entryPoints.contains($0) }
            .filter { try Self.occurrences(in: $0) > 0 }
        #expect(offenders.isEmpty, "per-screen appearance declarations: \(offenders)")
    }
}
