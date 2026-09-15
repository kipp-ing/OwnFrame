//
//  SlideshowChrome.swift
//  OwnFrame
//
//  Reveal-on-tap Liquid Glass chrome over the running slideshow: a top bar
//  (photo info · albums · settings) and a bottom transport bar
//  (previous · play/pause · next). Hidden by default to keep the calm photo-frame
//  look (Konstitution VII); the parent (SlideshowView) owns visibility and the
//  auto-hide timing and passes interactions back via `onInteraction` so any tap
//  keeps the chrome alive. Eased dark scrims sit behind the bars and the controls use
//  the soft-glass tier below iOS 26, so they stay legible over any photo, bright or
//  dark (FR-300-34).
//

import SlideshowKit
import SwiftUI

/// The eased edge scrim of the design record (`docs/design/quiet-glass-2026-07-18.html`, CSS
/// `.scrim`): black at these opacities and locations, measured from the screen edge inward,
/// over `bandFraction` of the screen height (300 T003).
nonisolated enum ChromeScrim {
    static let stops: [(opacity: Double, location: Double)] = [
        (0.34, 0.0), (0.18, 0.40), (0.06, 0.75), (0.0, 1.0),
    ]
    static let bandFraction: Double = 0.26

    static var gradientStops: [Gradient.Stop] {
        stops.map { Gradient.Stop(color: .black.opacity($0.opacity), location: $0.location) }
    }

    /// The scrim's opacity at `location` (0 = screen edge, 1 = inner end of the band), linear
    /// between stops as the gradient renders it; 0 past the band.
    static func opacity(at location: Double) -> Double {
        guard let first = stops.first, location > first.location else { return stops.first?.opacity ?? 0 }
        for (lower, upper) in zip(stops, stops.dropFirst()) where location <= upper.location {
            let t = (location - lower.location) / (upper.location - lower.location)
            return lower.opacity * (1 - t) + upper.opacity * t
        }
        return 0
    }
}

/// Layout constants the bars share with the scrim legibility arithmetic (`SoftGlassTierTests`).
nonisolated enum ChromeMetrics {
    /// Explicit inset of both bars from the physical top/bottom screen edges.
    static let barInset: CGFloat = 44
    static let controlDiameter: CGFloat = 52
}

struct SlideshowChrome<Info: View>: View {
    let viewModel: SlideshowViewModel
    // The photo-info and album-browser affordances are Immich-backed: `nil` hides the
    // button. A Photos-library source runs without an Immich API (900, US1) until
    // T031/T032 bring source-neutral parity for these surfaces.
    var onInfo: (() -> Void)?
    var onAlbums: (() -> Void)?
    var onSettings: () -> Void = {}
    /// Called whenever the user touches a control, so the parent can reset the
    /// auto-hide countdown.
    var onInteraction: () -> Void = {}
    /// The photo-info card. Laid out in the VStack directly under the top bar —
    /// not as a free overlay — so it can never cover the bar's buttons on narrow
    /// (iPhone portrait) screens, where a centered overlay collided with the
    /// right-aligned button row (live-smoke bug).
    @ViewBuilder var info: Info

    var body: some View {
        ZStack(alignment: .top) {
            // Behind everything, unaffected by the bars' own insets below, so it always
            // reaches the true screen edges.
            edgeScrims

            VStack {
                topBar
                info
                Spacer()
                bottomBar
            }
            .padding(.horizontal, 32)
            // The slideshow hides the status bar and home indicator for the whole run, so the
            // safe-area insets the chrome used to lean on collapse to ~0 on iPad. Inset the bars
            // explicitly so the round controls always clear the physical screen edges in every
            // orientation instead of crowding/clipping at the top and bottom.
            .padding(.vertical, ChromeMetrics.barInset)
        }
        .tint(.white)
    }

    /// Eased dark gradients pinned to the top/bottom screen edges, behind the bars ("Scrims that
    /// whisper"): four stops with a 34% peak over 26% of the screen height. The glass tiers carry
    /// most of the legibility; the scrim steadies the extremes, such as a near-white photo
    /// (FR-300-34). It applies on every runtime, not only below iOS 26. Never intercepts touches,
    /// so the tap-to-hide-chrome gesture on the image beneath still works through it.
    private var edgeScrims: some View {
        GeometryReader { proxy in
            let band = proxy.size.height * ChromeScrim.bandFraction
            VStack(spacing: 0) {
                LinearGradient(stops: ChromeScrim.gradientStops, startPoint: .top, endPoint: .bottom)
                    .frame(height: band)
                Spacer(minLength: 0)
                LinearGradient(stops: ChromeScrim.gradientStops, startPoint: .bottom, endPoint: .top)
                    .frame(height: band)
            }
        }
        .ignoresSafeArea()
        .allowsHitTesting(false)
    }

    private var topBar: some View {
        HStack {
            Spacer()
            glassGroup(spacing: 14) {
                HStack(spacing: 14) {
                    if let onInfo {
                        iconButton("info.circle", label: "Photo info", id: "slideshow.chrome.info") {
                            onInteraction(); onInfo()
                        }
                    }
                    if let onAlbums {
                        iconButton("photo.stack", label: "Albums", id: "slideshow.chrome.albums") {
                            onInteraction(); onAlbums()
                        }
                    }
                    iconButton("gearshape", label: "Settings", id: "slideshow.chrome.settings") {
                        onInteraction(); onSettings()
                    }
                }
            }
        }
    }

    private var bottomBar: some View {
        glassGroup(spacing: 18) {
            HStack(spacing: 18) {
                iconButton("backward.end.fill", label: "Previous", id: "slideshow.chrome.previous") {
                    onInteraction()
                    Task { await viewModel.showPrevious() }
                }
                iconButton(
                    viewModel.isPaused ? "play.fill" : "pause.fill",
                    label: viewModel.isPaused ? "Play" : "Pause",
                    id: "slideshow.chrome.playPause"
                ) {
                    onInteraction()
                    viewModel.togglePause()
                }
                iconButton("forward.end.fill", label: "Next", id: "slideshow.chrome.next") {
                    onInteraction()
                    Task { await viewModel.showNext() }
                }
            }
        }
    }

    private func iconButton(
        _ systemName: String,
        label: LocalizedStringKey,
        id: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.title2)
                .frame(width: ChromeMetrics.controlDiameter, height: ChromeMetrics.controlDiameter)
                .contentShape(.circle)
        }
        .glassButtonStyle()
        .buttonBorderShape(.circle)
        .accessibilityLabel(label)
        .accessibilityIdentifier(id)
    }
}
