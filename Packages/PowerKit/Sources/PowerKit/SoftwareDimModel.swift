/// Maps a target brightness (0...1) to the opacity of a full-screen black overlay used to
/// dim the display in software on platforms without a panel-brightness API (tvOS, topic 1000).
///
/// tvOS cannot lower `UIScreen.brightness`, so "dimming" is achieved by fading a black layer
/// over the slideshow content. This is the pure, UIKit-free mapping behind that layer.
///
/// Contract: `overlayOpacity = 1 - clamp(brightness, 0...1)`. Brightness 1.0 leaves no overlay
/// (0.0), brightness 0.0 draws a fully opaque black overlay (1.0), 0.5 -> 0.5. Out-of-range
/// inputs clamp, and the mapping is monotonic non-increasing in brightness.
public struct SoftwareDimModel: Sendable {
    public static func overlayOpacity(forBrightness brightness: Double) -> Double {
        let clamped = min(max(brightness, 0.0), 1.0)
        return 1.0 - clamped
    }
}
