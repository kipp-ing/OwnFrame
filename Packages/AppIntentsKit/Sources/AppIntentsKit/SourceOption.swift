import Foundation

/// Package-neutral projection of a selectable source (data-model.md
/// "SourceOption") — deliberately just an id/label pair, nothing an automation
/// could use to leak collection identity (no `kind`, no URLs).
public struct SourceOption: Sendable, Equatable, Identifiable {
    public let id: String
    /// The stored label: what applying the option matches on (the HA select's option).
    public let label: String
    /// What a person sees in the Shortcuts picker — never a raw host or album id (120,
    /// FR-120-13). The app fills it from its display-name rule; it defaults to `label`.
    public let displayName: String

    public init(id: String, label: String, displayName: String? = nil) {
        self.id = id
        self.label = label
        self.displayName = displayName ?? label
    }
}
