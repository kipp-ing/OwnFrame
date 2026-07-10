import Foundation

/// Immich API v3 baseline gate (130). The app speaks the v3 API only; a server reporting a
/// major version below `minimumMajor` is unsupported and surfaces as `serverTooOld`.
///
/// Pure and side-effect free so onboarding (connect) and the slideshow refresh both classify a
/// version identically and test it without a network round-trip.
public enum ServerVersionGate {
    /// Lowest supported Immich major version.
    public static let minimumMajor = 3

    /// The leading integer of a `major.minor.patch` string, tolerating a pre-release suffix
    /// (e.g. `"3.0.0-rc.2"` → `3`). `nil` when no leading integer can be read.
    public static func majorVersion(from versionString: String) -> Int? {
        let firstComponent = versionString.split(separator: ".").first.map(String.init) ?? versionString
        let digits = firstComponent.prefix { $0.isNumber }
        return Int(digits)
    }

    /// `true`/`false` when the major version is known, `nil` when it cannot be parsed.
    /// An unknown version is never treated as too-old (FR-130-09) — the caller keeps whatever
    /// reach/decoding category it already has instead.
    public static func isSupported(_ versionString: String) -> Bool? {
        guard let major = majorVersion(from: versionString) else { return nil }
        return major >= minimumMajor
    }
}

public extension ImmichAPI {
    /// Fetch the server version and throw `serverTooOld` when the major version is below the
    /// supported floor. Network/decoding failures propagate as their own categories
    /// (`unreachable`/`invalidResponse`); an unparseable version does not block (FR-130-04/09).
    func ensureServerSupported() async throws {
        let version = try await serverVersion()
        if ServerVersionGate.isSupported(version) == false {
            throw ImmichError.serverTooOld(version: version)
        }
    }
}
