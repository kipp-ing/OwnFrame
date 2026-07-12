import Foundation

/// Pure time→geometry math for the Ken Burns zoom-out, host-testable like
/// `TransitionDescriptor` (the SwiftUI modifier just samples it per frame).
///
/// The drift is *rate-based*, not span-based: the photo swap lands at
/// `duration + image-load latency`, and that latency is unbounded on a real device.
/// The old design mapped a fixed span onto scale 1.12→1.0 and clamped — any late swap
/// left the photo standing still at 1.0, and the next photo's motion then read as a
/// fast "catch-up". Instead, the zoom-out runs at a constant rate that reaches
/// `settleScale` (still zoomed, still moving) at the *expected* swap moment and simply
/// keeps drifting through the `settleScale → floorScale` grace headroom when the swap
/// is late. Outgoing and incoming photo always move at the identical rate, so the
/// motion stays continuous through the whole cross-fade; the clamp at `floorScale`
/// (below which a fill-framed photo would pull its edges into view) is reachable only
/// after many seconds of pathological lateness.
public struct KenBurnsDrift: Equatable, Sendable {
    /// Scale a fresh photo starts at.
    public let startScale: Double
    /// Scale at the expected swap moment (`duration + swapOverlapSeconds`) — kept
    /// above the floor so the photo is still in motion while it fades away.
    public let settleScale: Double
    /// Hard clamp: `scaledToFill` covers the screen exactly at 1.0.
    public let floorScale: Double
    /// How far the expected timeline runs past the slide's own length, covering the
    /// 0.7s sequenced swap. Feeds the rate only — the motion no longer ends here.
    public let swapOverlapSeconds: Double

    public init(
        startScale: Double = 1.15,
        settleScale: Double = 1.06,
        floorScale: Double = 1.0,
        swapOverlapSeconds: Double = 1.0
    ) {
        self.startScale = startScale
        self.settleScale = settleScale
        self.floorScale = floorScale
        self.swapOverlapSeconds = swapOverlapSeconds
    }

    /// Constant zoom-out rate (scale units per second) for a slide of the given
    /// length: longer slides drift slower, so every photo completes the same arc.
    public func rate(durationSeconds: Double) -> Double {
        (startScale - settleScale) / (max(durationSeconds, 0.1) + swapOverlapSeconds)
    }

    /// Scale after `elapsedSeconds` on screen — linear from `startScale` down at
    /// `rate`, clamped to `[floorScale, startScale]`.
    public func scale(elapsedSeconds: Double, durationSeconds: Double) -> Double {
        let drifted = startScale - rate(durationSeconds: durationSeconds) * max(elapsedSeconds, 0)
        return min(max(drifted, floorScale), startScale)
    }

    /// Pan magnitude for a given scale: 1 at `startScale`, linearly down to 0 at
    /// `floorScale`. Linear in scale — and scale is linear in time — so the pan
    /// moves at constant speed too, and a floor-clamped photo sits centered.
    public func panFraction(forScale scale: Double) -> Double {
        (scale - floorScale) / (startScale - floorScale)
    }
}
