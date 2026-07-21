import Foundation

/// Durable storage for a frame's Home Assistant identity (700 US3 / FR-700-16).
///
/// The one property that matters: it MUST outlive app deletion and reinstall. That is what lets
/// a reinstalled frame re-register as *itself* instead of appearing as a second device and
/// leaving its previous entities stranded.
///
/// The identity is **not a secret** — it is protected for durability, not confidentiality — so
/// implementations are free to pick storage on those grounds (see the note on the Keychain-backed
/// implementation in the app target).
public protocol FrameIdentityStorage: Sendable {
    /// The persisted identity, or nil if this frame has never registered.
    func loadIdentity() -> String?
    /// Persist an identity durably. Called at most once per frame.
    func saveIdentity(_ identity: String)
}

/// Decides who a frame is in Home Assistant, once, and then never again.
///
/// Pure and storage-injected so the whole decision table is host-testable; the durable store it
/// is given is what needs hardware verification (SC-700-11).
///
/// ## Why this exists
///
/// Identity used to be `UIDevice.current.identifierForVendor` read at each launch. iOS
/// regenerates that value once the last app from a vendor is deleted, so a reinstall silently
/// changed the frame's identity: Home Assistant saw a new device, and every entity, dashboard
/// binding, and automation attached to the old one was orphaned with no way for the app — or the
/// user — to clean it up. Verified live on hardware, where 19 entities had to be retracted by
/// hand against the broker.
///
/// The fallback was worse. `?? "immich-slideshow-device"` is a *shared constant*, and
/// `identifierForVendor` is nil before the first unlock after a reboot — precisely the state a
/// photo frame is in when it recovers from a power cut. Two frames there did not merely get wrong
/// identities, they got the **same** one: one topic namespace, one set of `unique_id`s, stomping
/// each other with nothing surfaced anywhere. Hence FR-700-18 and the `UUID()` default below:
/// absence of information must produce a unique value, never a literal.
public enum FrameIdentityResolver {

    /// Resolves this frame's identity, persisting it the first time.
    ///
    /// Precedence, in order:
    /// 1. **Stored** — returned verbatim and never rewritten (FR-700-16). Already carries any
    ///    platform suffix, so it is not suffixed again.
    /// 2. **Legacy platform identifier** — adopted and persisted (FR-700-21). An app *update*
    ///    never changes `identifierForVendor`, so a frame already registered under it keeps the
    ///    identity it has and nothing is orphaned by the migration itself.
    /// 3. **Freshly generated** — unique per frame (FR-700-18).
    ///
    /// - Parameters:
    ///   - storage: the durable store; the sole reason identity survives reinstall.
    ///   - legacyIdentifier: the platform identifier this frame *used* to publish under, without
    ///     any platform suffix. Blank or nil counts as absent — adopting `""` would persist an
    ///     empty identity, the one state the store could not recover from by itself.
    ///   - platformSuffix: keeps the iPad and Apple TV frames distinct on one broker
    ///     (FR-1000-08). Applied only when minting or adopting, never to a stored value.
    ///   - makeNew: the generator, injectable for tests. The default is what makes case 3 unique.
    public static func resolve(
        storage: any FrameIdentityStorage,
        legacyIdentifier: String?,
        platformSuffix: String = "",
        makeNew: () -> String = { UUID().uuidString }
    ) -> String {
        if let stored = storage.loadIdentity(), !stored.trimmed.isEmpty {
            return stored
        }

        let legacy = legacyIdentifier?.trimmed ?? ""
        let base = legacy.isEmpty ? makeNew() : legacy
        let identity = base + platformSuffix

        storage.saveIdentity(identity)
        return identity
    }
}

private extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}
