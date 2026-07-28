import Foundation

/// The user-facing name of a frame in Home Assistant (700 / FR-700-22).
///
/// Strictly cosmetic, and that is the point. Home Assistant anchors entities on `unique_id`, so
/// renaming a frame updates its display name while every `entity_id`, dashboard binding, and
/// automation keeps working. Nothing here may ever feed an identity, a topic, or a `unique_id` —
/// the moment a name becomes part of a key, renaming orphans entities, which is the defect
/// FR-700-16…21 exist to remove.
///
/// Free-form by design: non-unique and non-ASCII are both fine, because it is never sanitised
/// into a key.
@MainActor
public protocol FrameNameStore: AnyObject {
    /// Never empty — a blank stored value reads back as the platform default.
    var name: String { get set }
}

@MainActor
public final class UserDefaultsFrameNameStore: FrameNameStore {
    /// The single key this store owns. Exposed so a test seam can clear it directly instead of
    /// calling `removePersistentDomain` — see `UserDefaultsHAPublishOptionsStore.defaultsKey`.
    public static let defaultsKey = "haControl.frameName"

    private static let key = defaultsKey

    private let defaults: UserDefaults
    private let defaultName: String

    /// - Parameter defaultName: what an un-named frame is called. Differs per platform so an
    ///   iPad and an Apple TV on one broker are still tellable apart before anyone renames them.
    public init(defaults: UserDefaults = .standard, defaultName: String) {
        self.defaults = defaults
        self.defaultName = defaultName
    }

    public var name: String {
        get {
            // Trim on read as well as write: a value stored by an older build, or one that
            // arrived blank, must not surface as a nameless device in Home Assistant.
            let stored = defaults.string(forKey: Self.key)?
                .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return stored.isEmpty ? defaultName : stored
        }
        set {
            let trimmed = newValue.trimmingCharacters(in: .whitespacesAndNewlines)
            if trimmed.isEmpty {
                // Clearing the field means "go back to the default", not "call me nothing".
                defaults.removeObject(forKey: Self.key)
            } else {
                defaults.set(trimmed, forKey: Self.key)
            }
        }
    }
}
