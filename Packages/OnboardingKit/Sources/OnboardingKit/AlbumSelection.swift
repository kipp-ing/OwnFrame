import Foundation

/// Pending album marks in a picker (210, FR-210-28): nothing persists until `commit`.
/// Keyed by `SourceKind`, not by the filtered list, so a mark survives a search change.
public struct AlbumSelection: Equatable, Sendable {
    /// One pickable album: an Immich album or an Apple Photos collection.
    public struct Candidate: Equatable, Sendable {
        /// `.album(albumID:)` or `.photoLibrary(collectionID:)`; a `.sharedLink` is never marked.
        public let kind: SourceKind
        /// The album name as the picker has it; may be empty.
        public let label: String
        /// Index in the picker's unfiltered list.
        public let position: Int

        public init(kind: SourceKind, label: String, position: Int) {
            self.kind = kind
            self.label = label
            self.position = position
        }
    }

    public init() {
        marked = []
    }

    /// Commit order: every `.album` before every `.photoLibrary`, each group by `position`.
    public private(set) var marked: [Candidate]

    public var count: Int { marked.count }
    public var isEmpty: Bool { marked.isEmpty }

    public func isMarked(_ kind: SourceKind) -> Bool {
        marked.contains { $0.kind == kind }
    }

    /// Marks or unmarks (identity = `kind`). No-op when `library` already holds a source of that
    /// exact kind (album id / collection id — never compared by label) or when kind is `.sharedLink`.
    public mutating func toggle(_ candidate: Candidate, in library: SourceLibrary) {
        if case .sharedLink = candidate.kind { return }
        guard !library.sources.contains(where: { $0.kind == candidate.kind }) else { return }

        if let index = marked.firstIndex(where: { $0.kind == candidate.kind }) {
            marked.remove(at: index)
        } else {
            marked.append(candidate)
            marked.sort(by: Self.commitOrder)
        }
    }

    public mutating func discard() {
        marked = []
    }

    /// Adds the marks through `viewModel.addSources` (one persist), clears the marks, returns the added count.
    @MainActor @discardableResult
    public mutating func commit(into viewModel: SourceLibraryViewModel) -> Int {
        let added = viewModel.addSources(marked)
        marked = []
        return added
    }

    private static func commitOrder(_ lhs: Candidate, _ rhs: Candidate) -> Bool {
        let lhsGroup = group(of: lhs.kind)
        let rhsGroup = group(of: rhs.kind)
        return lhsGroup != rhsGroup ? lhsGroup < rhsGroup : lhs.position < rhs.position
    }

    private static func group(of kind: SourceKind) -> Int {
        switch kind {
        case .album: 0
        case .photoLibrary: 1
        case .sharedLink: 2
        }
    }
}
