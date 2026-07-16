import Foundation

public struct Source: Codable, Sendable, Equatable, Identifiable {
    public let id: String
    public var label: String
    public var kind: SourceKind

    public init(id: String = UUID().uuidString, label: String, kind: SourceKind) {
        self.id = id
        self.label = label
        self.kind = kind
    }
}

public enum SourceKind: Codable, Sendable, Equatable {
    case album(albumID: String)
    case sharedLink(baseURL: URL, slug: String)
    /// A device Apple Photos / iCloud album, identified by its PhotoKit collection ID (900,
    /// FR-900-02). The limited-access "Selected Photos" pool is the same kind with a
    /// well-known sentinel collection ID (the sentinel lives in PhotoSourceKit; here it is
    /// just an opaque String). Codable is additive: the case name keys the collection ID.
    case photoLibrary(collectionID: String)
}

/// How the running slideshow restarts after the active source changes (see
/// `SourceLibrary.restartStrategy(from:to:)`).
public enum SourceRestartStrategy: Sendable, Equatable {
    /// Same authenticated client; only the album changes (`SlideshowViewModel.switchAlbum`).
    case switchAlbum(albumID: String)
    /// Auth/client changed (a shared link is involved) — rebuild the slideshow.
    case rebuild
}
