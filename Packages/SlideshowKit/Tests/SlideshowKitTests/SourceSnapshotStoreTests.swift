import Foundation
import PhotoSourceKit
import SlideshowKit
import Testing

/// T004 — FileSourceSnapshotStore contract (FR-320-06/10): one JSON per source key,
/// replace-on-save, corrupt files degrade to nil, root is backup-excluded.
@Suite("SourceSnapshotStore — remembered photo lists")
struct SourceSnapshotStoreTests {
    private let assets = [
        SourceAsset(id: "photo-1", kind: .image),
        SourceAsset(id: "photo-2", kind: .image),
        SourceAsset(id: "photo-3", kind: .image),
    ]

    // @covers FR-320-06
    @Test func roundTripReturnsTheSavedList() throws {
        let root = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = FileSourceSnapshotStore(root: root)

        store.save(assets, forKey: "album-1")
        let loaded = store.load(forKey: "album-1")

        #expect(loaded?.map(\.id) == assets.map(\.id))
        #expect(loaded?.map(\.kind) == assets.map(\.kind))
    }

    // 900 R2 (FR-900-01 wire compat): fielded 320 frames have snapshot files on disk
    // written by the pre-900 `[Asset]` store — raw `{"id","type"}` JSON. The refactored
    // `[SourceAsset]` store must decode those exact bytes without migration. This fixture
    // is byte-identical to what `JSONEncoder().encode([Asset])` produced (Immich type
    // strings as `MediaKind` raw values), so a decode failure here means fielded frames
    // would lose their offline list on the first post-update launch.
    @Test func loadsLegacyAssetSnapshotBytesWithoutMigration() throws {
        let root = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = FileSourceSnapshotStore(root: root)

        let legacyJSON = #"[{"id":"legacy-1","type":"IMAGE"},{"id":"legacy-2","type":"VIDEO"}]"#
        try Data(legacyJSON.utf8).write(to: root.appendingPathComponent("album-legacy.json"))

        let loaded = store.load(forKey: "album-legacy")
        #expect(loaded?.map(\.id) == ["legacy-1", "legacy-2"])
        #expect(loaded?.map(\.kind) == [.image, .video])
    }

    @Test func loadReturnsNilForAnUnknownKey() throws {
        let root = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = FileSourceSnapshotStore(root: root)

        #expect(store.load(forKey: "never-played") == nil)
    }

    // @covers FR-320-06
    @Test func saveReplacesTheKeysPreviousSnapshot() throws {
        let root = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = FileSourceSnapshotStore(root: root)

        store.save(assets, forKey: "album-1")
        let shrunk = [SourceAsset(id: "photo-9", kind: .image)]
        store.save(shrunk, forKey: "album-1")

        #expect(store.load(forKey: "album-1")?.map(\.id) == ["photo-9"])
    }

    // @covers FR-320-06
    @Test func snapshotsAreIsolatedPerSourceKey() throws {
        let root = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: root) }
        let store = FileSourceSnapshotStore(root: root)

        store.save(assets, forKey: "album-a")
        store.save([SourceAsset(id: "other", kind: .image)], forKey: "album-b")

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

    // @covers FR-320-10
    @Test func aCreatedRootIsExcludedFromBackup() throws {
        let parent = try makeTempDirectory()
        defer { try? FileManager.default.removeItem(at: parent) }
        var root = parent.appendingPathComponent("SourceSnapshots", isDirectory: true)
        _ = FileSourceSnapshotStore(root: root)

        root.removeAllCachedResourceValues()
        let values = try root.resourceValues(forKeys: [.isExcludedFromBackupKey])
        #expect(values.isExcludedFromBackup == true)
    }

    // @covers FR-320-06, FR-320-10
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
