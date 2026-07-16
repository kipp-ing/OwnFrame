public struct StartupGate: Sendable {
    private let config: ConfigStore
    private let keychain: KeychainStore
    private let sourceStore: any SourceLibraryStore

    public init(config: ConfigStore, keychain: KeychainStore, sourceStore: any SourceLibraryStore) {
        self.config = config
        self.keychain = keychain
        self.sourceStore = sourceStore
    }

    public func initialStep() -> OnboardingStep {
        // The active source — not a single selectedAlbumID — decides the rest (120).
        // `load()` migrates a legacy selectedAlbumID into a one-entry album library, so
        // existing installs still resolve through the album branch below.
        if let active = sourceStore.load().active {
            switch active.kind {
            case .sharedLink:
                // A shared link authenticates itself — complete with no API key and no
                // separately saved base URL (210, D2).
                return .done
            case .photoLibrary:
                // A device photo-library source needs no Immich connection; photo
                // authorization is (re)checked by the provider at engine start (900, R5),
                // so relaunch resumes straight into the slideshow (US1-4 startup parity).
                return .done
            case .album:
                // Album sources still need the authenticated client: API key + base URL.
                guard keychain.read() != nil, config.loadBaseURL() != nil else { return .connection }
                return .done
            }
        }

        // No active source yet. A validated connection (key + base URL) resumes at the
        // add-source step; a blank install opens on the choice screen (210, US1).
        if keychain.read() != nil, config.loadBaseURL() != nil {
            return .source
        }
        return .choice
    }
}
