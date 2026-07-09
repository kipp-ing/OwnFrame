import Foundation
import ImmichClient
import SlideshowKit
import Testing

/// T004 — FileSourceSnapshotStore contract (FR-320-06/10): one JSON per source key,
/// replace-on-save, corrupt files degrade to nil, root is backup-excluded.
@Suite("SourceSnapshotStore — remembered photo lists")
struct SourceSnapshotStoreTests {
    private let assets = [
        Asset(id: "photo-1", type: "IMAGE"),
        Asset(id: "photo-2", type: "IMAGE"),
        Asset(id: "photo-3", type: "IMAGE"),
    ]

    @Test func roundTripReturnsTheSavedList() throws {
        let root = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = FileSourceSnapshotStore(root: root)

        store.save(assets, forKey: "album-1")
        let loaded = store.load(forKey: "album-1")

        #expect(loaded?.map(\.id) == assets.map(\.id))
        #expect(loaded?.map(\.type) == assets.map(\.type))
    }

    @Test func loadReturnsNilForAnUnknownKey() throws {
        let root = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = FileSourceSnapshotStore(root: root)

        #expect(store.load(forKey: "never-played") == nil)
    }

    @Test func saveReplacesTheKeysPreviousSnapshot() throws {
        let root = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = FileSourceSnapshotStore(root: root)

        store.save(assets, forKey: "album-1")
        let shrunk = [Asset(id: "photo-9", type: "IMAGE")]
        store.save(shrunk, forKey: "album-1")

        #expect(store.load(forKey: "album-1")?.map(\.id) == ["photo-9"])
    }

    @Test func snapshotsAreIsolatedPerSourceKey() throws {
        let root = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = FileSourceSnapshotStore(root: root)

        store.save(assets, forKey: "album-a")
        store.save([Asset(id: "other", type: "IMAGE")], forKey: "album-b")

        #expect(store.load(forKey: "album-a")?.count == 3)
        #expect(store.load(forKey: "album-b")?.map(\.id) == ["other"])
    }

    @Test func corruptSnapshotFileLoadsAsNilAndNeverThrows() throws {
        let root = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = FileSourceSnapshotStore(root: root)
        store.save(assets, forKey: "album-1")

        let file = root.appendingPathComponent("album-1.json")
        try Data("not json{{".utf8).write(to: file)

        #expect(store.load(forKey: "album-1") == nil)
    }

    @Test func clearRemovesAllSnapshots() throws {
        let root = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = FileSourceSnapshotStore(root: root)

        store.save(assets, forKey: "album-a")
        store.save(assets, forKey: "album-b")
        store.clear()

        #expect(store.load(forKey: "album-a") == nil)
        #expect(store.load(forKey: "album-b") == nil)
        #expect(try FileManager.default.contentsOfDirectory(atPath: root.path).isEmpty)
    }

    @Test func aCreatedRootIsExcludedFromBackup() throws {
        let parent = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: parent) }
        var root = parent.appendingPathComponent("SourceSnapshots", isDirectory: true)
        _ = FileSourceSnapshotStore(root: root)

        root.removeAllCachedResourceValues()
        let values = try root.resourceValues(forKeys: [.isExcludedFromBackupKey])
        #expect(values.isExcludedFromBackup == true)
    }

    @Test func snapshotFileContainsOnlyIdsAndTypes() throws {
        let root = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = FileSourceSnapshotStore(root: root)

        store.save(assets, forKey: "album-1")

        let raw = try Data(contentsOf: root.appendingPathComponent("album-1.json"))
        let decoded = try JSONSerialization.jsonObject(with: raw) as? [[String: Any]]
        let keys = Set(decoded?.flatMap(\.keys) ?? [])
        #expect(keys == ["id", "type"])
    }
}
