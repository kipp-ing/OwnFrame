//
//  SlideshowErrorView.swift
//  Immich Slideshow
//
//  Shown when the album's asset list cannot be loaded (FR-010). Offers a retry
//  rather than leaving a blank or crashed screen.
//

import SwiftUI

struct SlideshowErrorView: View {
    var onRetry: () -> Void = {}
    // Opens the in-app connection editor so a broken/expired connection can be fixed
    // in place, without a full reset/re-onboarding (009, US2).
    var onFixConnection: (() -> Void)?

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "wifi.exclamationmark")
                .imageScale(.large)
                .foregroundStyle(.secondary)
            Text("Couldn’t load the album")
                .font(.headline)
                .accessibilityIdentifier("slideshow.error")
            Text("Check the connection to your Immich server and try again.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
            Button("Try again", action: onRetry)
                .buttonStyle(.borderedProminent)
                .accessibilityIdentifier("slideshow.retry")
            if let onFixConnection {
                Button("Edit connection", action: onFixConnection)
                    .buttonStyle(.bordered)
                    .accessibilityIdentifier("slideshow.fixConnection")
            }
        }
        .padding()
        .foregroundStyle(.white)
    }
}

#Preview {
    ZStack {
        Color.black.ignoresSafeArea()
        SlideshowErrorView()
    }
}
