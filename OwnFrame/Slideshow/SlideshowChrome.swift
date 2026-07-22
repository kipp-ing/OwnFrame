//
//  SlideshowChrome.swift
//  OwnFrame
//
//  Reveal-on-tap Liquid Glass chrome over the running slideshow: a top bar
//  (photo info · albums · settings) and a bottom transport bar
//  (previous · play/pause · next). Hidden by default to keep the calm photo-frame
//  look (Konstitution VII); the parent (SlideshowView) owns visibility and the
//  auto-hide timing and passes interactions back via `onInteraction` so any tap
//  keeps the chrome alive. Fixed dark scrims sit behind the bars so the controls
//  stay legible over any photo, bright or dark (FR-300-34).
//

import SlideshowKit
import SwiftUI

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
            .padding(.vertical, 44)
        }
        .tint(.white)
    }

    /// Fixed dark gradients pinned to the top/bottom screen edges, behind the bars. Liquid
    /// Glass materials pick up the photo behind them, so on a bright or near-white photo the
    /// glass blur and white icon tint can both wash out together; a guaranteed-dark backing
    /// keeps the icons legible no matter what's in the photo (FR-300-34). Never intercepts
    /// touches, so the tap-to-hide-chrome gesture on the image beneath still works through it.
    private var edgeScrims: some View {
        VStack {
            LinearGradient(colors: [.black.opacity(0.45), .clear], startPoint: .top, endPoint: .bottom)
                .frame(height: 160)
            Spacer()
            LinearGradient(colors: [.clear, .black.opacity(0.45)], startPoint: .top, endPoint: .bottom)
                .frame(height: 160)
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
        label: String,
        id: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            Image(systemName: systemName)
                .font(.title2)
                .frame(width: 52, height: 52)
                .contentShape(.circle)
        }
        .glassButtonStyle()
        .buttonBorderShape(.circle)
        .accessibilityLabel(label)
        .accessibilityIdentifier(id)
    }
}
