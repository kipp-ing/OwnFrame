import Foundation

public enum IncomingSharedLinkOutcome: Equatable, Sendable {
    case prefillOnboarding(URL)
    case switchToExisting(sourceID: String)
    case addAndActivate(baseURL: URL, slug: String)
    case invalid
}

public enum IncomingSharedLink: Sendable {
    public static func route(_ url: URL, library: SourceLibrary, isConfigured: Bool) -> IncomingSharedLinkOutcome {
        guard let parsed = SharedLinkURL.parse(url.absoluteString) else {
            return .invalid
        }

        guard isConfigured else {
            return .prefillOnboarding(url)
        }

        if let existing = library.sources.first(where: { source in
            if case let .sharedLink(baseURL, slug) = source.kind {
                return baseURL == parsed.baseURL && slug == parsed.slug
            }
            return false
        }) {
            return .switchToExisting(sourceID: existing.id)
        }

        return .addAndActivate(baseURL: parsed.baseURL, slug: parsed.slug)
    }
}
