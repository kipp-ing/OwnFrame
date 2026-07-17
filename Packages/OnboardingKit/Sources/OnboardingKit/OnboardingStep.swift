public enum OnboardingStep: Sendable, Equatable {
    // First-run entry: the user picks the shared-link path or the server path (210, US1).
    case choice
    // Shared-link-only path: paste a link → resolve → (password only if required) → start,
    // reaching the slideshow with no API key (210, US1).
    case sharedLinkSetup
    // Device-Photos/iCloud-album path: pick an on-device album, no server/API key involved
    // (220, sub-spec of 200; reuses the 900 photoLibrary source).
    case photoLibrarySetup
    case connection
    // Add the first source after connecting: an Immich album (picker) or a shared
    // link (URL + optional password). Replaces the old single-album step (120, US2).
    case source
    // Review the saved library and start: lists the sources with the active one marked.
    case confirm
    case done
}
