import Foundation
import ImmichClient
import Observation

/// The user's selection on the first-run choice screen (210, US1).
public enum OnboardingPathChoice: Sendable, Equatable {
    case sharedLink
    case server
}

@Observable public final class OnboardingViewModel {
    public var step: OnboardingStep = .connection
    public var serverURLInput: String = ""
    public var apiKeyInput: String = ""
    public var albums: [Album] = []
    public var isBusy: Bool = false
    public var errorMessage: String?

    @ObservationIgnored private let api: (ServerConfig) -> any ImmichAPI
    @ObservationIgnored private let config: ConfigStore
    @ObservationIgnored private let keychain: KeychainStore
    @ObservationIgnored private let sourceStore: any SourceLibraryStore
    // Bounded auto-retry for the connection validation. The first request on a fresh
    // install fails while the iOS Local Network permission prompt is up; retrying a few
    // times lets validation complete once the user grants access instead of surfacing a
    // hard error (Bug 1). Injected so tests run instantly with a no-op sleep.
    @ObservationIgnored private let connectionRetryLimit: Int
    @ObservationIgnored private let connectionRetryDelay: Duration
    @ObservationIgnored private let sleep: (Duration) async -> Void

    public init(
        api: @escaping (ServerConfig) -> any ImmichAPI,
        config: ConfigStore,
        keychain: KeychainStore,
        sourceStore: any SourceLibraryStore = InMemorySourceLibraryStore(),
        connectionRetryLimit: Int = 4,
        connectionRetryDelay: Duration = .seconds(1.2),
        sleep: @escaping (Duration) async -> Void = { try? await Task.sleep(for: $0) }
    ) {
        self.api = api
        self.config = config
        self.keychain = keychain
        self.sourceStore = sourceStore
        self.connectionRetryLimit = connectionRetryLimit
        self.connectionRetryDelay = connectionRetryDelay
        self.sleep = sleep
    }

    /// Route from the first-run choice screen: the shared-link path goes to the in-place
    /// link entry (no API key needed); the server path goes to the connection form (210, US1).
    public func choosePath(_ choice: OnboardingPathChoice) {
        errorMessage = nil
        switch choice {
        case .sharedLink:
            step = .sharedLinkSetup
        case .server:
            step = .connection
        }
    }

    /// Whether the current step has a previous step to return to. False on the first step
    /// (`.choice`) and once onboarding is `.done` (FR-210-26).
    public var canGoBack: Bool {
        switch step {
        case .choice, .done: false
        case .sharedLinkSetup, .connection, .source, .confirm: true
        }
    }

    /// Step back to the immediately preceding onboarding screen in-place, without restarting
    /// the app and without discarding entered configuration (FR-210-26). The shared-link and
    /// server paths both fold back to the choice screen; the source/confirm steps fold back
    /// toward connection. `.choice` (and `.done`) have nowhere to go.
    public func back() {
        errorMessage = nil
        switch step {
        case .sharedLinkSetup, .connection:
            step = .choice
        case .source:
            step = .connection
        case .confirm:
            step = .source
        case .choice, .done:
            break
        }
    }

    public func submitConnection() async {
        guard !isBusy else { return }
        errorMessage = nil

        guard let url = normalizedURL() else {
            errorMessage = String(localized: "Please enter a valid HTTPS address.", bundle: .module)
            return
        }

        isBusy = true
        defer { isBusy = false }

        let list: [Album]
        do {
            list = try await validateConnection(url: url)
        } catch let error as ImmichError {
            errorMessage = ConnectionError.message(for: error)
            return
        } catch {
            errorMessage = String(localized: "Unexpected response from the server.", bundle: .module)
            return
        }

        do {
            try keychain.save(apiKeyInput)
        } catch {
            errorMessage = String(localized: "Could not securely store the API key.", bundle: .module)
            return
        }

        // Connection validated — persist the server address so the active source can be
        // resolved later even when the first source is a shared link with no album (120).
        config.saveBaseURL(url)
        albums = list
        // An empty album list still proves the connection works; the user can add a shared
        // link on the next step, so advance rather than dead-end at connection (120, US2).
        step = .source
    }

    /// Validate the connection by fetching the album list, retrying briefly on
    /// `.unreachable`. On a fresh install the first request fails while the iOS Local
    /// Network permission prompt is still up; a few bounded retries let validation
    /// complete once the user taps "Allow", instead of surfacing a hard "server not
    /// available" the user must dismiss and re-trigger (Bug 1). Deterministic failures
    /// (auth, invalid response) are not retried — they won't change on a repeat.
    private func validateConnection(url: URL) async throws -> [Album] {
        let client = api(ServerConfig(baseURL: url, apiKey: apiKeyInput))
        var attempt = 0
        while true {
            do {
                return try await client.albums()
            } catch ImmichError.unreachable where attempt < connectionRetryLimit {
                attempt += 1
                await sleep(connectionRetryDelay)
            }
        }
    }

    /// Load the album list for the source step when it isn't already in memory — e.g. when
    /// onboarding resumes at `.source` on a fresh launch. Best-effort: a failure leaves the
    /// list empty (the user can still add a shared link).
    public func loadAlbumsIfNeeded() async {
        guard albums.isEmpty, !isBusy,
              let url = config.loadBaseURL(), let key = keychain.read() else { return }
        albums = (try? await api(ServerConfig(baseURL: url, apiKey: key)).albums()) ?? []
    }

    /// Move from the add-source step to the confirmation step. The view guards this on the
    /// library having at least one source.
    public func proceedToConfirm() {
        errorMessage = nil
        step = .confirm
    }

    /// Return from confirmation to add another source.
    public func backToSource() {
        errorMessage = nil
        step = .source
    }

    /// Finish onboarding from the confirmation step and route to the running slideshow. An
    /// album active source keeps `AppConfiguration` fully populated so the legacy album
    /// paths (HA album list, 009 album re-select) keep working; a shared-link active source
    /// needs only the base URL already saved at connection (120).
    public func finish() {
        if case let .album(albumID)? = sourceStore.load().active?.kind,
           let url = config.loadBaseURL() ?? normalizedURL() {
            config.save(AppConfiguration(baseURL: url, selectedAlbumID: albumID))
        }
        step = .done
    }

    public func reset() {
        config.clear()
        keychain.delete()
        sourceStore.clear()
        step = .connection
        serverURLInput = ""
        apiKeyInput = ""
        albums = []
        errorMessage = nil
    }

    private func normalizedURL() -> URL? {
        ConnectionURL.normalize(serverURLInput)
    }
}
