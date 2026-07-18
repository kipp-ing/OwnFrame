import Foundation
import ImmichClient
import Observation

/// Drives the Settings **Sources** manager (120, US2): the persisted source library
/// plus add/remove/rename/reorder/set-active operations. Add/remove/rename/move persist
/// directly; `setActive` delegates to the app-level switch (US1 `switchActiveSource`)
/// so the running slideshow restarts, then reflects the reloaded library.
@MainActor
@Observable
public final class SourceLibraryViewModel {
    public private(set) var library: SourceLibrary
    public var errorMessage: String?
    /// Drives the resolve-first / ask-password-only-when-needed add-link flow (210).
    public private(set) var addState: SharedLinkAddState = .idle

    // The parsed link awaiting a password while `addState == .needsPassword`.
    @ObservationIgnored private var pendingLink: (baseURL: URL, slug: String, label: String)?

    @ObservationIgnored private let store: any SourceLibraryStore
    @ObservationIgnored private let secretStore: any SharedLinkSecretStore
    @ObservationIgnored private let resolver: any SharedLinkResolving
    @ObservationIgnored private let onSwitchActive: (String) -> Void

    public init(
        store: any SourceLibraryStore,
        secretStore: any SharedLinkSecretStore,
        resolver: any SharedLinkResolving,
        onSwitchActive: @escaping (String) -> Void = { _ in }
    ) {
        self.store = store
        self.secretStore = secretStore
        self.resolver = resolver
        self.onSwitchActive = onSwitchActive
        self.library = store.load()
    }

    public var sources: [Source] { library.sources }
    public var activeID: String? { library.activeID }

    /// Whether `label` (trimmed) is non-empty and not already used — drives the Add
    /// button's enabled state and guards the add operations.
    public func isLabelAvailable(_ label: String) -> Bool {
        let trimmed = label.trimmingCharacters(in: .whitespacesAndNewlines)
        return !trimmed.isEmpty && !library.sources.contains { $0.label == trimmed }
    }

    public func addAlbumSource(albumID: String, label: String) {
        errorMessage = nil
        let trimmed = label.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isLabelAvailable(trimmed) else {
            errorMessage = Self.duplicateLabelMessage
            return
        }

        var library = self.library
        library.add(Source(label: trimmed, kind: .album(albumID: albumID)))
        persist(library)
    }

    /// Add a device photo-library source (an Apple Photos / iCloud album, or the limited-access
    /// "Selected Photos" pool) by its collection ID (900, FR-900-02). Mirrors `addAlbumSource`:
    /// the label is taken as-is at save time, with the same duplicate-label guard.
    public func addPhotoLibrarySource(collectionID: String, label: String) {
        errorMessage = nil
        let trimmed = label.trimmingCharacters(in: .whitespacesAndNewlines)
        guard isLabelAvailable(trimmed) else {
            errorMessage = Self.duplicateLabelMessage
            return
        }

        var library = self.library
        library.add(Source(label: trimmed, kind: .photoLibrary(collectionID: collectionID)))
        persist(library)
    }

    // MARK: - Two-phase resolve (210, D6)

    /// Reset the add-link flow to `.idle` — call when (re)opening the add-link surface.
    public func resetSharedLinkAdd() {
        pendingLink = nil
        addState = .idle
    }

    /// Phase 1: parse + normalize the link (HTTPS-only) and resolve it with no password.
    /// A malformed / non-HTTPS URL ⇒ `.error` with **no** network call (Constitution IV);
    /// `passwordRequired` ⇒ `.needsPassword` (nothing persisted); success ⇒ source saved +
    /// `.resolved`; any other failure ⇒ `.error` and nothing persisted.
    public func resolveSharedLink(urlString: String, label: String) async {
        guard let parsed = SharedLinkURL.parse(urlString) else {
            pendingLink = nil
            addState = .error(Self.invalidURLMessage)
            return
        }
        pendingLink = (parsed.baseURL, parsed.slug, label)
        await attemptResolve(password: nil)
    }

    /// Phase 2: confirm a password for a link that reported `passwordRequired`. A no-op
    /// unless `addState == .needsPassword`. A correct password ⇒ source saved + password
    /// written to the Keychain secret store; `wrongPassword` ⇒ `.error`, nothing persisted.
    public func confirmSharedLinkPassword(_ password: String) async {
        guard case .needsPassword = addState, pendingLink != nil else { return }
        await attemptResolve(password: password)
    }

    /// Scan a QR code and route it through the exact same resolve-first flow a typed link
    /// uses (220, FR-220-04) — a scanned link is not a second code path. A cancelled scan
    /// (`scanner.scan()` returns `nil`) is a silent no-op; a decoded string that isn't a
    /// usable Immich share link is rejected calmly, with no network call and nothing
    /// persisted (FR-220-06).
    public func addScannedSharedLink(using scanner: some CodeScanning, label: String = "") async {
        guard let decoded = await scanner.scan() else { return }
        switch ScannedShareLink.validate(decoded) {
        case .success:
            await resolveSharedLink(urlString: decoded, label: label)
        case .failure(let reason):
            pendingLink = nil
            addState = .error(Self.scanRejectionMessage(for: reason))
        }
    }

    private func attemptResolve(password: String?) async {
        guard let pending = pendingLink else { return }
        addState = .resolving
        do {
            // Validate the link (and password, if any) before persisting anything; nothing
            // is written on failure (Constitution III — no half-written secret).
            _ = try await resolver.resolve(baseURL: pending.baseURL, slug: pending.slug, password: password)
        } catch ImmichError.passwordRequired {
            addState = .needsPassword
            return
        } catch let error as ImmichError {
            addState = .error(ConnectionError.message(for: error))
            return
        } catch {
            addState = .error(Self.unexpectedResponseMessage)
            return
        }

        let savedID = persistResolvedLink(pending, password: password)
        pendingLink = nil
        addState = .resolved(sourceID: savedID)
    }

    /// Persist a resolved link, deduping by `(baseURL, slug)`: an existing shared-link
    /// source with the same target is reused (and its password refreshed) rather than
    /// adding a duplicate (210, D7).
    private func persistResolvedLink(
        _ pending: (baseURL: URL, slug: String, label: String),
        password: String?
    ) -> String {
        if let existing = library.sources.first(where: {
            if case let .sharedLink(baseURL, slug) = $0.kind {
                return baseURL == pending.baseURL && slug == pending.slug
            }
            return false
        }) {
            if let password { try? secretStore.savePassword(password, forSourceID: existing.id) }
            return existing.id
        }

        let source = Source(
            label: uniqueLabel(from: pending),
            kind: .sharedLink(baseURL: pending.baseURL, slug: pending.slug)
        )
        if let password { try? secretStore.savePassword(password, forSourceID: source.id) }

        var library = self.library
        library.add(source)
        persist(library)
        return source.id
    }

    /// A non-empty, unique label for a new shared-link source. Falls back to the link host
    /// when none was supplied (the low-friction path asks only for a link), then appends a
    /// counter so it never collides with an existing source label.
    private func uniqueLabel(from pending: (baseURL: URL, slug: String, label: String)) -> String {
        let trimmed = pending.label.trimmingCharacters(in: .whitespacesAndNewlines)
        let base = trimmed.isEmpty ? (pending.baseURL.host ?? pending.slug) : trimmed
        if !library.sources.contains(where: { $0.label == base }) { return base }
        var suffix = 2
        while library.sources.contains(where: { $0.label == "\(base) \(suffix)" }) { suffix += 1 }
        return "\(base) \(suffix)"
    }

    public func remove(id: String) {
        if case .sharedLink = library.sources.first(where: { $0.id == id })?.kind {
            secretStore.deletePassword(forSourceID: id)
        }

        var library = self.library
        library.remove(id: id)
        persist(library)
    }

    public func rename(id: String, to label: String) {
        errorMessage = nil
        var library = self.library
        library.rename(id: id, to: label.trimmingCharacters(in: .whitespacesAndNewlines))
        persist(library)
    }

    public func move(from source: IndexSet, to destination: Int) {
        var library = self.library
        library.move(from: source, to: destination)
        persist(library)
    }

    public func setActive(id: String) {
        guard id != library.activeID, library.sources.contains(where: { $0.id == id }) else {
            return
        }

        // The app layer persists the active change and restarts the running slideshow
        // (US1); reflect the persisted state locally afterwards.
        onSwitchActive(id)
        library = store.load()
    }

    private func persist(_ library: SourceLibrary) {
        self.library = library
        store.save(library)
    }

    private static var duplicateLabelMessage: String {
        String(localized: "A source with this name already exists.", bundle: .module)
    }

    private static var invalidURLMessage: String {
        String(localized: "Please enter a valid shared-link address.", bundle: .module)
    }

    private static var unexpectedResponseMessage: String {
        String(localized: "Unexpected response from the server.", bundle: .module)
    }

    /// Calm, jargon-light rejection copy for a scanned code that isn't a usable Immich
    /// shared link (220, FR-220-06). A single friendly message covers every reason.
    private static func scanRejectionMessage(for reason: InvalidCodeReason) -> String {
        switch reason {
        case .notAURL, .notHTTPS, .notAShareLink:
            return String(
                localized: "That code isn't an Immich shared link — check the QR code, or type the link instead.",
                bundle: .module
            )
        }
    }
}
