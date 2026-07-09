import Foundation

/// The persistence tier under the RAM `ImageCache` (320): photos survive network
/// outages and relaunches on disk, byte-capped with least-recently-used eviction.
public protocol DiskImageStoring: Sendable {
    /// Bytes for the key, or nil on miss. A hit refreshes the entry's recency.
    /// Corrupt/unreadable entries are removed and reported as a miss (FR-320-09).
    func data(forKey key: String) async -> Data?

    /// Persist bytes under the key, then prune to the budget. Failures are
    /// swallowed — playback must never notice (FR-320-09). An entry larger than
    /// the whole budget is not persisted.
    func store(_ data: Data, forKey key: String) async

    /// Change the budget; prunes immediately when lowered (FR-320-04).
    func setBudget(_ bytes: Int64) async

    /// Remove every entry (FR-320-05).
    func clear() async

    /// Tracked byte total of all entries (the Settings usage label).
    func currentUsage() async -> Int64
}

/// Byte-capped LRU over one file per entry in `root`. The filesystem is the index:
/// a killed app or an iOS cache purge never desyncs anything — the next scan simply
/// sees fewer files. Recency lives in each file's modification date, stamped from
/// the injected `now` on every store AND read so eviction order is deterministic
/// under test (research R2).
public actor DiskImageCache: DiskImageStoring {
    private struct Entry {
        var size: Int64
        var stamp: Date
    }

    private let root: URL
    private let now: @Sendable () -> Date
    private var budget: Int64
    /// filename → size/recency, seeded by one directory scan on first use; kept in
    /// step with every mutation so `usage` stays a cheap running total.
    private var entries: [String: Entry] = [:]
    private var usage: Int64 = 0
    private var isSeeded = false

    public init(root: URL, budget: Int64, now: @escaping @Sendable () -> Date = { Date() }) {
        self.root = root
        self.budget = budget
        self.now = now
    }

    public func data(forKey key: String) async -> Data? {
        seedIfNeeded()
        let name = Self.fileName(for: key)
        guard let entry = entries[name] else {
            return nil
        }

        let url = root.appendingPathComponent(name)
        guard let data = try? Data(contentsOf: url), !data.isEmpty else {
            // Corrupt or unreadable: a miss, and the entry is gone (FR-320-09).
            try? FileManager.default.removeItem(at: url)
            entries[name] = nil
            usage -= entry.size
            return nil
        }

        stamp(url: url, name: name)
        return data
    }

    public func store(_ data: Data, forKey key: String) async {
        seedIfNeeded()
        guard !data.isEmpty, Int64(data.count) <= budget else {
            return
        }

        let name = Self.fileName(for: key)
        let url = root.appendingPathComponent(name)
        do {
            try data.write(to: url, options: .atomic)
        } catch {
            // Disk full / unwritable root: keep playing, try again some other
            // time (FR-320-09) — the usage total stays untouched.
            return
        }

        if let replaced = entries[name] {
            usage -= replaced.size
        }
        entries[name] = Entry(size: Int64(data.count), stamp: now())
        usage += Int64(data.count)
        stamp(url: url, name: name)
        prune()
    }

    public func setBudget(_ bytes: Int64) async {
        seedIfNeeded()
        budget = bytes
        prune()
    }

    public func clear() async {
        seedIfNeeded()
        let files = (try? FileManager.default.contentsOfDirectory(
            at: root, includingPropertiesForKeys: nil
        )) ?? []
        for file in files {
            try? FileManager.default.removeItem(at: file)
        }
        entries = [:]
        usage = 0
    }

    public func currentUsage() async -> Int64 {
        seedIfNeeded()
        return usage
    }

    /// One lazy scan seeds the in-memory index from whatever survived on disk —
    /// prior runs, iOS purges, crashes mid-write. Regular files only.
    private func seedIfNeeded() {
        guard !isSeeded else {
            return
        }
        isSeeded = true

        try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let keys: Set<URLResourceKey> = [.fileSizeKey, .contentModificationDateKey, .isRegularFileKey]
        let files = (try? FileManager.default.contentsOfDirectory(
            at: root, includingPropertiesForKeys: Array(keys)
        )) ?? []

        for file in files {
            guard let values = try? file.resourceValues(forKeys: keys),
                  values.isRegularFile == true else {
                continue
            }
            let size = Int64(values.fileSize ?? 0)
            let stamp = values.contentModificationDate ?? .distantPast
            entries[file.lastPathComponent] = Entry(size: size, stamp: stamp)
            usage += size
        }
    }

    /// Delete least-recently-stamped entries until the budget holds (FR-320-03).
    private func prune() {
        while usage > budget {
            guard let oldest = entries.min(by: { $0.value.stamp < $1.value.stamp }) else {
                return
            }
            try? FileManager.default.removeItem(at: root.appendingPathComponent(oldest.key))
            entries[oldest.key] = nil
            usage -= oldest.value.size
        }
    }

    /// Refresh the entry's recency in the index and on the file itself, so a
    /// relaunch reconstructs the same LRU order from modification dates.
    private func stamp(url: URL, name: String) {
        let stamp = now()
        entries[name]?.stamp = stamp
        try? FileManager.default.setAttributes(
            [.modificationDate: stamp], ofItemAtPath: url.path
        )
    }

    /// Cache keys are `assetID#quality`; asset IDs are UUIDs, so `#` is the only
    /// character that needs mapping to stay a plain filename.
    private static func fileName(for key: String) -> String {
        key.replacingOccurrences(of: "#", with: "_")
            .replacingOccurrences(of: "/", with: "_")
    }
}
