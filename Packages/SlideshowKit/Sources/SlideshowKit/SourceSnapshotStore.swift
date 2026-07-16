import Foundation
import PhotoSourceKit

/// Remembers the active source's last successful photo list (320, FR-320-06) so an
/// offline relaunch can play from disk. Content is asset IDs + kind only — never
/// credentials or URLs (FR-320-10). `SourceAsset` encodes byte-identically to the
/// pre-900 `[Asset]` snapshot (`{"id","type"}`), so fielded files decode without
/// migration (900 R2, FR-900-01).
public protocol SourceSnapshotStoring: Sendable {
    /// Replaces the key's previous snapshot.
    func save(_ assets: [SourceAsset], forKey key: String)

    /// nil when missing or undecodable — a corrupt snapshot is just absent.
    func load(forKey key: String) -> [SourceAsset]?

    /// Removes all snapshots (part of Clear cache, FR-320-05).
    func clear()
}

/// One JSON file per source key under `root`. The production root lives in
/// Application Support (not Caches: the KB-sized list pins the offline experience
/// and must not be purged away from under gigabytes of surviving images) and is
/// created backup-excluded — reconstructible device-local state (FR-320-10).
public final class FileSourceSnapshotStore: SourceSnapshotStoring, Sendable {
    private let root: URL

    public init(root: URL) {
        self.root = root
        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        var url = root
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try? url.setResourceValues(values)
    }

    public func save(_ assets: [SourceAsset], forKey key: String) {
        guard let data = try? JSONEncoder().encode(assets) else {
            return
        }
        try? data.write(to: fileURL(for: key), options: .atomic)
    }

    public func load(forKey key: String) -> [SourceAsset]? {
        guard let data = try? Data(contentsOf: fileURL(for: key)) else {
            return nil
        }
        return try? JSONDecoder().decode([SourceAsset].self, from: data)
    }

    public func clear() {
        let files = (try? FileManager.default.contentsOfDirectory(
            at: root, includingPropertiesForKeys: nil
        )) ?? []
        for file in files {
            try? FileManager.default.removeItem(at: file)
        }
    }

    /// Keys are album IDs (UUIDs); `/` is mapped defensively anyway.
    private func fileURL(for key: String) -> URL {
        let safe = key.replacingOccurrences(of: "/", with: "_")
        return root.appendingPathComponent("\(safe).json")
    }
}
