//
//  SlideshowChrome.swift
//  Immich Slideshow
//
//  Reveal-on-tap Liquid Glass chrome over the running slideshow: a top bar
//  (exit · photo info · albums · settings) and a bottom transport bar
//  (previous · play/pause · next). Hidden by default to keep the calm photo-frame
//  look (Konstitution VII); the parent (SlideshowView) owns visibility and the
//  auto-hide timing and passes interactions back via `onInteraction` so any tap
//  keeps the chrome alive.
//

import SlideshowKit
import SwiftUI

struct SlideshowChrome: View {
    let viewModel: SlideshowViewModel
    var onExit: () -> Void = {}
    var onInfo: () -> Void = {}
    var onAlbums: () -> Void = {}
    var onSettings: () -> Void = {}
    /// Called whenever the user touches a control, so the parent can reset the
    /// auto-hide countdown.
    var onInteraction: () -> Void = {}

    var body: some View {
        VStack {
            topBar
            Spacer()
            bottomBar
        }
        .padding(.horizontal, 32)
        // The slideshow hides the status bar and home indicator for the whole run, so the
        // safe-area insets the chrome used to lean on collapse to ~0 on iPad. Inset the bars
        // explicitly so the round controls always clear the physical screen edges in every
        // orientation instead of crowding/clipping at the top and bottom.
        .padding(.vertical, 44)
        .tint(.white)
    }

    private var topBar: some View {
        HStack {
            iconButton("xmark", label: "Exit slideshow", id: "slideshow.chrome.exit") {
                onInteraction(); onExit()
            }
            Spacer()
            GlassEffectContainer(spacing: 14) {
                HStack(spacing: 14) {
                    iconButton("info.circle", label: "Photo info", id: "slideshow.chrome.info") {
                        onInteraction(); onInfo()
                    }
                    iconButton("photo.stack", label: "Albums", id: "slideshow.chrome.albums") {
                        onInteraction(); onAlbums()
                    }
                    iconButton("gearshape", label: "Settings", id: "slideshow.chrome.settings") {
                        onInteraction(); onSettings()
                    }
                }
            }
        }
    }

    private var bottomBar: some View {
        GlassEffectContainer(spacing: 18) {
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
        .buttonStyle(.glass)
        .buttonBorderShape(.circle)
        .accessibilityLabel(label)
        .accessibilityIdentifier(id)
    }
}
