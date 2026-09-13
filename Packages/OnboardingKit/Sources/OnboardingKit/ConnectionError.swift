import Foundation
import ImmichClient

public enum ConnectionError {
    public static func message(for error: ImmichError) -> String {
        switch error {
        case .unauthorized:
            String(localized: "Invalid API key.", bundle: .module)
        case .unreachable:
            String(localized: "Server not reachable.", bundle: .module)
        case .invalidResponse:
            String(localized: "Unexpected response from the server.", bundle: .module)
        case .invalidShareLink:
            String(localized: "This Immich link is invalid or has been removed.", bundle: .module)
        case .shareLinkExpired:
            String(localized: "This Immich link has expired.", bundle: .module)
        case .wrongPassword:
            String(localized: "Incorrect password for this Immich link.", bundle: .module)
        case .passwordRequired:
            String(localized: "This Immich link requires a password.", bundle: .module)
        case let .serverTooOld(version):
            String(
                localized: "This app requires Immich v3 or newer. This server is running \(version) — please update Immich.",
                bundle: .module
            )
        }
    }
}
