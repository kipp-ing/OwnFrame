//
//  SlideshowErrorView.swift
//  Immich Slideshow
//
//  Shown when the album's asset list cannot be loaded (FR-010). Offers a retry
//  rather than leaving a blank or crashed screen. Auto-retry keeps running
//  behind this state (310, FR-310-01); when the failure is an auth problem the
//  copy names the actionable fix instead of a generic hint (FR-310-05).
//

import SlideshowKit
import SwiftUI

struct SlideshowErrorView: View {
    /// Why the load failed — switches the message between the generic transient
    /// hint and the actionable auth copy (310, FR-310-05). nil reads as transient.
    var reason: SlideshowFailureReason?
    var onRetry: () -> Void = {}
    // Opens the in-app connection editor so a broken/expired connection can be fixed
    // in place, without a full reset/re-onboarding (009, US2).
    var onFixConnection: (() -> Void)?

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: iconName)
                .imageScale(.large)
                .foregroundStyle(.secondary)
            Text(title)
                .font(.headline)
                .accessibilityIdentifier("slideshow.error")
            Text(message)
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

    private var iconName: String {
        reason == .authentication ? "key.slash" : "wifi.exclamationmark"
    }

    private var title: String {
        reason == .authentication ? "Access was denied" : "Couldn’t load the album"
    }

    private var message: String {
        switch reason {
        case .authentication:
            return "Check your connection settings — the API key or shared link "
                + "may have expired. Retrying automatically in the background."
        case .transient, nil:
            return "Check the connection to your Immich server and try again. "
                + "Retrying automatically in the background."
        }
    }
}

#Preview("Transient") {
    ZStack {
        Color.black.ignoresSafeArea()
        SlideshowErrorView(reason: .transient)
    }
}

#Preview("Authentication") {
    ZStack {
        Color.black.ignoresSafeArea()
        SlideshowErrorView(reason: .authentication, onFixConnection: {})
    }
}
