import Foundation
import ImmichClient
import Observation

/// Identifiable (object identity) so presentation can use `.sheet(item:)` —
/// the flag+optional-state pattern raced SwiftUI's first sheet render (310).
@MainActor @Observable public final class ConnectionSettingsViewModel: Identifiable {
    public var serverURLInput: String
    public var apiKeyInput: String = ""
    public private(set) var isBusy = false
    public private(set) var errorMessage: String?
    public private(set) var keyIsSet: Bool

    @ObservationIgnored private let api: (ServerConfig) -> any ImmichAPI
    @ObservationIgnored private let config: ConfigStore
    @ObservationIgnored private let keychain: KeychainStore

    public init(
        api: @escaping (ServerConfig) -> any ImmichAPI,
        config: ConfigStore,
        keychain: KeychainStore
    ) {
        self.api = api
        self.config = config
        self.keychain = keychain

        serverURLInput = config.load()?.baseURL.absoluteString ?? ""
        keyIsSet = keychain.read() != nil
    }

    public func save() async -> ConnectionValidationOutcome {
        guard !isBusy else { return .success }
        isBusy = true
        defer { isBusy = false }
        errorMessage = nil

        guard let url = ConnectionURL.normalize(serverURLInput) else {
            errorMessage = String(localized: "Please enter a valid HTTPS address.", bundle: .module)
            return .malformed
        }

        let previousConfiguration = config.load()
        let selectedAlbumID = previousConfiguration?.selectedAlbumID ?? ""
        let effectiveKey = apiKeyInput.isEmpty ? (keychain.read() ?? "") : apiKeyInput

        let albums: [Album]
        do {
            let client = api(ServerConfig(baseURL: url, apiKey: effectiveKey))
            // 130 FR-130-05: reject a pre-v3 server before adopting the connection.
            try await client.ensureServerSupported()
            albums = try await client.albums()
        } catch let error as ImmichError {
            errorMessage = ConnectionError.message(for: error)
            return outcome(for: error)
        } catch {
            errorMessage = String(localized: "Unexpected response from the server.", bundle: .module)
            return .invalidResponse
        }

        if !apiKeyInput.isEmpty {
            do {
                try keychain.save(apiKeyInput)
            } catch {
                errorMessage = String(localized: "Could not securely store the API key.", bundle: .module)
                return .keychainFailure
            }
        }

        config.save(AppConfiguration(baseURL: url, selectedAlbumID: selectedAlbumID))
        keyIsSet = keychain.read() != nil

        if !albums.contains(where: { $0.id == selectedAlbumID }) {
            return .albumMissing(albums: albums)
        }

        return .success
    }

    private func outcome(for error: ImmichError) -> ConnectionValidationOutcome {
        switch error {
        case .unauthorized:
            .unauthorized
        case .unreachable:
            .unreachable
        case .invalidResponse:
            .invalidResponse
        case .invalidShareLink, .shareLinkExpired, .wrongPassword, .passwordRequired:
            // Shared-link-specific errors cannot arise from API-key connection validation;
            // treat them as an unexpected response here. The source library surfaces them
            // through its own shared-link flow (120).
            .invalidResponse
        case let .serverTooOld(version):
            .serverTooOld(version: version)
        }
    }
}
