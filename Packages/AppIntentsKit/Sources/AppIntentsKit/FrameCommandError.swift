import Foundation

/// Closed error taxonomy for the intent command surface (data-model.md
/// "FrameCommandError"). Shells map these 1:1 to localized copy; state is left
/// untouched by every case here (validation/resolution failures never mutate).
public enum FrameCommandError: Error, Equatable, Sendable {
    /// Onboarding was never completed — the registry was never flipped configured.
    case notConfigured
    /// Configured, but no live slideshow surface registered after the cold-launch grace.
    case frameNotOpen
    /// Requested brightness percent was outside `0...100`.
    case brightnessOutOfRange(Int)
    /// The requested source id no longer resolves; carries its display label.
    case sourceMissing(label: String)
}
