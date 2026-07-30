import SwiftUI

/// The unlock screen's live motion sample (FR-1100-09): the bundled cliff photo under the same
/// slow drift-and-scale the slideshow's Ken Burns applies, with a miniature Digits clock in the
/// corner — the two visual Supporter features, demonstrated in one tile.
///
/// Self-contained on purpose, twice over:
/// - It does not reach into a running slideshow. The unlock screen must render identically
///   whether it was opened from playback settings or from onboarding, and must never depend on
///   a photo source being configured at all — hence the bundled photo (`UnlockDemoMedia`).
/// - It does not import SlideshowKit's `KenBurnsMotionModifier`. That type's complexity is
///   pause/resume/duration-retune semantics a looping demo has no use for, and PurchaseKit
///   deliberately depends on nothing.
///
/// The drift is one scoped linear animation ping-ponging forever between two keyframes; the
/// scale floor of 1.06 keeps the fill crop covering the tile at both platform aspects across
/// the whole ±16 pt pan. Under Reduce Motion the photo holds a calm mid-drift frame instead.
struct KenBurnsDemoView: View {

    @State private var image: CGImage? = UnlockDemoMedia.cliffImage()
    @State private var drifting = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            if let image {
                photo(image)
            } else {
                placeholder
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
    }

    // MARK: - Live sample

    private func photo(_ image: CGImage) -> some View {
        Color.clear
            .overlay {
                Image(decorative: image, scale: 1)
                    .resizable()
                    .scaledToFill()
                    .scaleEffect(scale)
                    .offset(x: panOffset)
                    // Scoped to the drift flag, like the slideshow's own motion: no global
                    // transaction, so the sheet's other animations can never capture it.
                    .animation(
                        reduceMotion ? nil : .linear(duration: Metrics.driftSeconds).repeatForever(autoreverses: true),
                        value: drifting
                    )
            }
            .overlay(alignment: .topTrailing) {
                demoClock
                    .padding(Metrics.clockPadding)
            }
            .onAppear {
                guard !reduceMotion else { return }
                // KenBurnsMotionModifier's execution contract applies here too: a state
                // mutation inside `onAppear` merges into the pending render commit, so the
                // from-value is never committed and the drift collapses into a still frame.
                // Defer one runloop iteration past the commit.
                DispatchQueue.main.async { drifting = true }
            }
    }

    private var scale: CGFloat {
        reduceMotion ? Metrics.restingScale : (drifting ? Metrics.farScale : Metrics.nearScale)
    }

    private var panOffset: CGFloat {
        reduceMotion ? 0 : (drifting ? -Metrics.pan : Metrics.pan)
    }

    // MARK: - Clock

    /// A miniature of the real overlay's default Digits style (`ClockOverlayView`): rounded
    /// semibold white numerals on a soft radial halo, updated on minute boundaries only. The
    /// fixed 24-hour `HH:mm` mirrors the shipping overlay verbatim — the demo must not promise
    /// a rendering the feature does not deliver.
    private var demoClock: some View {
        TimelineView(.everyMinute) { context in
            Text(verbatim: Self.timeString(context.date))
                .font(.system(size: Metrics.clockPointSize, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .lineLimit(1)
                .fixedSize()
                .foregroundStyle(.white)
                .shadow(color: .black.opacity(0.55), radius: 6, y: 1)
                .shadow(color: .black.opacity(0.35), radius: 16)
                .padding(.horizontal, Metrics.clockPointSize * 0.3)
                .padding(.vertical, Metrics.clockPointSize * 0.16)
                .background(
                    RadialGradient(
                        colors: [.black.opacity(0.28), .black.opacity(0.10), .clear],
                        center: .center,
                        startRadius: 0,
                        endRadius: Metrics.clockPointSize * 1.3
                    )
                )
        }
        .allowsHitTesting(false)
    }

    private static func timeString(_ date: Date) -> String {
        let c = Calendar.current.dateComponents([.hour, .minute], from: date)
        return String(format: "%02d:%02d", c.hour ?? 0, c.minute ?? 0)
    }

    // MARK: - Fallback

    /// The pre-demo neutral tile, kept as the degraded rendering for a missing bundle resource
    /// (which `UnlockDemoMediaTests` exists to prevent). Never the intended path.
    private var placeholder: some View {
        ZStack {
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(
                    LinearGradient(
                        colors: [.indigo.opacity(0.55), .teal.opacity(0.35)],
                        startPoint: .topLeading,
                        endPoint: .bottomTrailing
                    )
                )

            VStack(spacing: 8) {
                Image(systemName: "camera.viewfinder")
                    .font(.system(size: Metrics.placeholderGlyphSize, weight: .light))
                Text("A slow drift and scale across every photo", bundle: .module)
                    .font(.footnote)
                    .multilineTextAlignment(.center)
            }
            .foregroundStyle(.white.opacity(0.9))
            .padding()
        }
    }

    // MARK: - Metrics

    private enum Metrics {
        /// One drift leg. Matches the calm of the slideshow's arc rather than a promo loop.
        static let driftSeconds: Double = 16
        /// Fill-crop floor: at 1.06 the photo's overhang covers the tile at both platform
        /// aspects (iOS ~3.2:1, tvOS ~3.4:1 against the 3.33:1 band) through the whole pan.
        static let nearScale: CGFloat = 1.06
        static let farScale: CGFloat = 1.14
        static let restingScale: CGFloat = 1.08
        static let pan: CGFloat = 16

        #if os(tvOS)
        static let clockPointSize: CGFloat = 40
        static let clockPadding: CGFloat = 24
        static let placeholderGlyphSize: CGFloat = 54
        #else
        static let clockPointSize: CGFloat = 24
        static let clockPadding: CGFloat = 14
        static let placeholderGlyphSize: CGFloat = 34
        #endif
    }
}

#if DEBUG
#Preview("Ken Burns demo tile") {
    KenBurnsDemoView()
        .frame(height: 160)
        .padding(24)
}
#endif
