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

    /// Record an onboarding album pick so it can never dead-end (1000, US2): an existing
    /// source for the **same album** is reused and activated; a genuinely new album gets a
    /// unique label (counter-suffixed on collision, album-id fallback when empty) and is
    /// activated. Returns the id of the now-active source. Unlike `addAlbumSource`, a
    /// duplicate label is resolved rather than rejected — onboarding has no error surface.
    @discardableResult
    public func activateAlbumSource(albumID: String, label: String) -> String? {
        errorMessage = nil

        if let existing = library.sources.first(where: { $0.kind == .album(albumID: albumID) }) {
            setActive(id: existing.id)
            return existing.id
        }

        let trimmed = label.trimmingCharacters(in: .whitespacesAndNewlines)
        var candidate = trimmed.isEmpty ? albumID : trimmed
        var suffix = 2
        while library.sources.contains(where: { $0.label == candidate }) {
            candidate = "\(trimmed.isEmpty ? albumID : trimmed) \(suffix)"
            suffix += 1
        }

        let source = Source(label: candidate, kind: .album(albumID: albumID))
        var library = self.library
        library.add(source)
        persist(library)
        setActive(id: source.id)
        return source.id
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

    /// Batch add for the picker's confirm (210, FR-210-28): one persist for the whole pass.
    /// In the given order, skips shared links, kinds already in the library and batch repeats;
    /// a blank label falls back to the locator, a colliding one gets a " 2", " 3", … suffix.
    /// Never sets an error and never switches the active source. Returns the number added.
    @discardableResult
    public func addSources(_ candidates: [AlbumSelection.Candidate]) -> Int {
        errorMessage = nil

        var library = self.library
        var added = 0
        for candidate in candidates {
            let locator: String
            switch candidate.kind {
            case let .album(albumID): locator = albumID
            case let .photoLibrary(collectionID): locator = collectionID
            case .sharedLink: continue
            }
            guard !library.sources.contains(where: { $0.kind == candidate.kind }) else { continue }

            let trimmed = candidate.label.trimmingCharacters(in: .whitespacesAndNewlines)
            let base = trimmed.isEmpty ? locator : trimmed
            var label = base
            var suffix = 2
            while library.sources.contains(where: { $0.label == label }) {
                label = "\(base) \(suffix)"
                suffix += 1
            }

            let before = library.sources.count
            library.add(Source(label: label, kind: candidate.kind))
            if library.sources.count > before { added += 1 }
        }

        if added > 0 { persist(library) }
        return added
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
        let resolution: SharedLinkResolution
        do {
            // Validate the link (and password, if any) before persisting anything; nothing
            // is written on failure (Constitution III — no half-written secret).
            resolution = try await resolver.resolve(baseURL: pending.baseURL, slug: pending.slug, password: password)
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

        let savedID = persistResolvedLink(pending, albumName: resolution.albumName, password: password)
        pendingLink = nil
        addState = .resolved(sourceID: savedID)
    }

    /// Persist a resolved link, deduping by `(baseURL, slug)`: an existing shared-link
    /// source with the same target is reused (and its password refreshed) rather than
    /// adding a duplicate (210, D7).
    private func persistResolvedLink(
        _ pending: (baseURL: URL, slug: String, label: String),
        albumName: String?,
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
            label: uniqueLabel(from: pending, albumName: albumName),
            kind: .sharedLink(baseURL: pending.baseURL, slug: pending.slug)
        )
        if let password { try? secretStore.savePassword(password, forSourceID: source.id) }

        var library = self.library
        library.add(source)
        persist(library)
        return source.id
    }

    /// A non-empty, unique label for a new shared-link source: the typed label, else the album
    /// name the link reports (310, FR-310-16), else the link host (the low-friction path asks
    /// only for a link). A counter is appended so it never collides with an existing source
    /// label. The localized placeholder is never stored — `displayName(for:)` applies it.
    private func uniqueLabel(
        from pending: (baseURL: URL, slug: String, label: String),
        albumName: String?
    ) -> String {
        let typed = pending.label.trimmingCharacters(in: .whitespacesAndNewlines)
        let name = albumName?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        let base = !typed.isEmpty ? typed : (!name.isEmpty ? name : (pending.baseURL.host ?? pending.slug))
        if !library.sources.contains(where: { $0.label == base }) { return base }
        var suffix = 2
        while library.sources.contains(where: { $0.label == "\(base) \(suffix)" }) { suffix += 1 }
        return "\(base) \(suffix)"
    }

    // MARK: - Display name (120, FR-120-13)

    /// The name to show a person or return to another app for `source` — never a raw host, a
    /// URL or an album id. A stored label that is blank, URL-shaped (`http(s)://…`), or equal
    /// to the link's host / the album's id (case-insensitive, also with the old " N" counter
    /// suffix) maps to a neutral localized placeholder for its kind; every other label —
    /// typed, an album name, or one that merely contains the host — passes through unchanged,
    /// as does every Photos label. Pure: the placeholder is applied at display time only and
    /// never written to storage. Settings → Sources keeps showing the stored label.
    public nonisolated static func displayName(for source: Source) -> String {
        let trimmed = source.label.trimmingCharacters(in: .whitespacesAndNewlines)
        switch source.kind {
        case .photoLibrary:
            return source.label
        case let .sharedLink(baseURL, _):
            return isMachineLabel(trimmed, locator: baseURL.host) ? sharedAlbumPlaceholder : source.label
        case let .album(albumID):
            return isMachineLabel(trimmed, locator: albumID) ? immichAlbumPlaceholder : source.label
        }
    }

    /// Placeholder for an Immich link source without a usable name (FR-120-13, FR-310-16).
    public nonisolated static var sharedAlbumPlaceholder: String {
        String(localized: "Shared album", bundle: .module)
    }

    /// Placeholder for an Immich album source without a usable name (FR-120-13; 9000 vocabulary).
    public nonisolated static var immichAlbumPlaceholder: String {
        String(localized: "Immich album", bundle: .module)
    }

    /// Whether a trimmed label is machine-derived rather than a human name: blank, URL-shaped,
    /// or the source's locator (host or album id), optionally followed by " N".
    private nonisolated static func isMachineLabel(_ label: String, locator: String?) -> Bool {
        if label.isEmpty { return true }
        if label.range(of: "http://", options: [.caseInsensitive, .anchored]) != nil
            || label.range(of: "https://", options: [.caseInsensitive, .anchored]) != nil {
            return true
        }
        guard let locator, !locator.isEmpty else { return false }
        if label.caseInsensitiveCompare(locator) == .orderedSame { return true }
        guard let prefix = label.range(of: locator + " ", options: [.caseInsensitive, .anchored]) else {
            return false
        }
        let suffix = label[prefix.upperBound...]
        return !suffix.isEmpty && suffix.allSatisfy { $0.isASCII && $0.isNumber }
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
        String(localized: "Please enter a valid Immich link.", bundle: .module)
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
                localized: "That code isn't an Immich link — check the QR code, or type the link instead.",
                bundle: .module
            )
        }
    }
}
