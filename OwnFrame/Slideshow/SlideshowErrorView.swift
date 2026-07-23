//
//  SlideshowErrorView.swift
//  OwnFrame
//
//  Shown when the album's asset list cannot be loaded (FR-010). Offers a retry
//  rather than leaving a blank or crashed screen. Auto-retry keeps running
//  behind this state (310, FR-310-01); when the failure is an auth problem the
//  copy names the actionable fix instead of a generic hint (FR-310-05).
//

import SlideshowKit
import SwiftUI
import UIKit

struct SlideshowErrorView: View {
    /// Why the load failed — switches the message between the generic transient
    /// hint and the actionable auth copy (310, FR-310-05). nil reads as transient.
    var reason: SlideshowFailureReason?
    var onRetry: () -> Void = {}
    // Opens the in-app connection editor so a broken/expired connection can be fixed
    // in place, without a full reset/re-onboarding (009, US2).
    var onFixConnection: (() -> Void)?
    /// Photos-library source context (900, US3): auth failures mean reduced/revoked photo
    /// access — the copy names that cause and the fix is iOS Settings, not the connection
    /// editor (pass `onFixConnection: nil` alongside).
    var isPhotoLibrarySource = false

    @Environment(\.openURL) private var openURL

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
            if isPhotoLibrarySource, case .authentication = reason ?? .transient {
                Button("Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) {
                        openURL(url)
                    }
                }
                .buttonStyle(.bordered)
                .accessibilityIdentifier("slideshow.openSettings")
            }
        }
        .padding()
        .foregroundStyle(.white)
    }

    private var iconName: String {
        switch reason {
        case .unsupportedServer: return "exclamationmark.triangle"
        case .authentication: return "key.slash"
        case .notFound: return "photo.on.rectangle.angled"
        case .transient, nil: return "wifi.exclamationmark"
        }
    }

    private var title: LocalizedStringKey {
        switch reason {
        case .unsupportedServer: return "Immich update required"
        case .authentication:
            return isPhotoLibrarySource ? "Photo access needed" : "Access was denied"
        case .notFound: return "This source is gone"
        case .transient, nil: return "Couldn’t load the album"
        }
    }

    private var message: LocalizedStringKey {
        switch reason {
        case .unsupportedServer:
            // 130 FR-130-05/06: terminal — no background retry, so the copy points at the fix.
            return "This app needs Immich v3 or newer. Update your Immich server, then tap Try again."
        case .authentication:
            // 900 US3-3/4: for a Photos source the cause is insufficient photo access —
            // name it and point at Settings, not at the Immich connection. "Missing or
            // reduced" also covers the never-asked state (e.g. after a backup restore),
            // where nothing was ever revoked.
            if isPhotoLibrarySource {
                return "Photo access for this app is missing or was reduced, so this source can't play. Allow full photo access in Settings."
            }
            return "Check your connection settings — the API key or shared link may have expired. Retrying automatically in the background."
        case .notFound:
            // 900 FR-900-16: terminal vanish state — deleted, unshared, or migrated out of
            // this device's view (an owner-upgraded album on the new iCloud format is
            // invisible below iOS 27). Recovery is picking a source, not retrying.
            return "This album is no longer available — it may have been deleted, unshared, or upgraded to a newer iCloud shared album format this device can't show yet. Pick another source to keep the show going."
        case .transient, nil:
            return "Check the connection to your Immich server and try again. Retrying automatically in the background."
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
