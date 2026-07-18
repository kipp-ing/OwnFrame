import Foundation

/// Package-neutral projection of a selectable source (data-model.md
/// "SourceOption") — deliberately just an id/label pair, nothing an automation
/// could use to leak collection identity (no `kind`, no URLs).
public struct SourceOption: Sendable, Equatable, Identifiable {
    public let id: String
    public let label: String

    public init(id: String, label: String) {
        self.id = id
        self.label = label
    }
}
