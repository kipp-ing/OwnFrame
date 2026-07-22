//
//  TVSlideshowChrome.swift
//  OwnFrameTV
//
//  Topic 1000 (US1) — the Apple TV transport overlay: Previous / Play-Pause / Next, shown
//  only while the chrome is visible (driven by `TVChromeModel` in the host). Bottom-anchored
//  over a subtle gradient scrim so it reads over any photo. The buttons are focusable
//  `.card` buttons (the tvOS idiom), so the Siri Remote can move between them and click.
//

import SwiftUI

struct TVSlideshowChrome: View {
    let isPaused: Bool
    let onPrevious: () -> Void
    let onPlayPause: () -> Void
    let onNext: () -> Void
    /// Opens the tvOS settings surface (Home Assistant / MQTT broker). US4.
    var onSettings: () -> Void = {}

    var body: some View {
        VStack {
            Spacer()
            HStack(spacing: 60) {
                Button(action: onPrevious) {
                    Image(systemName: "backward.end.fill")
                }
                Button(action: onPlayPause) {
                    Image(systemName: isPaused ? "play.fill" : "pause.fill")
                }
                Button(action: onNext) {
                    Image(systemName: "forward.end.fill")
                }
                Button(action: onSettings) {
                    Image(systemName: "gearshape.fill")
                }
            }
            .font(.system(size: 48, weight: .semibold))
            .buttonStyle(.card)
            .padding(.bottom, 80)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
        .background(alignment: .bottom) {
            LinearGradient(
                colors: [.clear, .black.opacity(0.55)],
                startPoint: .center,
                endPoint: .bottom
            )
            .frame(height: 400)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
            .allowsHitTesting(false)
            .ignoresSafeArea()
        }
    }
}
