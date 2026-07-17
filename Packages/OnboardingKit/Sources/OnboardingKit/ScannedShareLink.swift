import Foundation

/// The non-secret payload of a scanned Immich share link, mirroring `SharedLinkURL.parse`'s
/// tuple with a named, `Equatable` value type so `ScannedShareLink.validate`'s `Result` can
/// be compared directly in tests.
public struct ParsedSharedLink: Sendable, Equatable {
    public let baseURL: URL
    public let slug: String

    public init(baseURL: URL, slug: String) {
        self.baseURL = baseURL
        self.slug = slug
    }
}

/// Why a decoded code string (e.g. from a scanned QR code) isn't a usable Immich shared
/// link. Drives the app target's rejection copy (220) — this type carries no strings.
public enum InvalidCodeReason: Error, Sendable, Equatable {
    /// Doesn't parse as a URL at all (e.g. contains whitespace, empty).
    case notAURL
    /// Parses as a URL, but with an explicit non-HTTPS scheme.
    case notHTTPS
    /// Parses as an HTTPS URL with a host, but has no `/s/<slug>` (or bare-slug) shape.
    case notAShareLink
}

/// Validates a decoded code string as an Immich shared-link URL for the QR-scan onboarding
/// path (220, sub-spec of 200). Wraps `SharedLinkURL.parse`, classifying *why* a string was
/// rejected so the caller can show a specific message. Pure and synchronous: no network
/// call, no persistence, no camera — the seam for the latter is `CodeScanning`.
public enum ScannedShareLink {
    public static func validate(_ decoded: String) -> Result<ParsedSharedLink, InvalidCodeReason> {
        if let parsed = SharedLinkURL.parse(decoded) {
            return .success(ParsedSharedLink(baseURL: parsed.baseURL, slug: parsed.slug))
        }

        // Mirror SharedLinkURL.parse's own normalization (HTTPS assumed when the scheme is
        // omitted) to reclassify why the very same parse failed.
        let trimmed = decoded.trimmingCharacters(in: .whitespacesAndNewlines)
        let urlString = trimmed.contains("://") ? trimmed : "https://\(trimmed)"
        guard let url = URL(string: urlString), let host = url.host, !host.isEmpty else {
            return .failure(.notAURL)
        }
        guard url.scheme == "https" else {
            return .failure(.notHTTPS)
        }
        // A valid HTTPS host reached this point only because `SharedLinkURL.parse` still
        // returned nil above — the sole remaining reason is a missing share-link shape.
        return .failure(.notAShareLink)
    }
}
