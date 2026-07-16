//
//  PhotoInfoView.swift
//  Immich Slideshow
//
//  Slice C — Liquid Glass photo-info overlay shown from the chrome: date/time and
//  location for the current photo, fetched lazily through the engine's neutral metadata
//  pass-through (900 T032, FR-900-10) so every backend renders the same card — Immich
//  supplies its EXIF place, a Photos source the capture date only (no geocoding, R7).
//  Reloads when the slideshow advances to another asset. Stays quiet (renders nothing)
//  when the photo carries no usable info, keeping with the calm default.
//

import PhotoSourceKit
import SwiftUI

struct PhotoInfoView: View {
    /// Fetches the current photo's neutral metadata; nil on failure (the card stays quiet).
    let fetchMetadata: (String) async -> AssetMetadata?
    let assetID: String

    @State private var metadata: AssetMetadata?
    @State private var didLoad = false

    var body: some View {
        Group {
            if let line = lines, !line.isEmpty {
                VStack(spacing: 4) {
                    if let dateText {
                        Label(dateText, systemImage: "calendar")
                    }
                    if let locationText {
                        Label(locationText, systemImage: "mappin.and.ellipse")
                    }
                }
                .font(.callout)
                .foregroundStyle(.white)
                .padding(.horizontal, 18)
                .padding(.vertical, 12)
                .glassCard(cornerRadius: 16)
                // A real container element (not just an identifier flattened onto the
                // text children) so UI tests see the card's full glass frame; the
                // labels inside stay individually queryable.
                .accessibilityElement(children: .contain)
                .accessibilityIdentifier("slideshow.info.card")
            } else if !didLoad {
                ProgressView()
                    .controlSize(.small)
                    .tint(.white)
            }
        }
        .task(id: assetID) { await load() }
    }

    /// The non-nil display lines; empty when the photo has neither date nor place.
    private var lines: [String]? {
        guard didLoad else { return nil }
        return [dateText, locationText].compactMap { $0 }
    }

    private var dateText: String? {
        guard let capturedAt = metadata?.capturedAt else { return nil }
        return capturedAt.formatted(date: .long, time: .shortened)
    }

    private var locationText: String? {
        guard let placeName = metadata?.placeName, !placeName.isEmpty else { return nil }
        return placeName
    }

    private func load() async {
        didLoad = false
        metadata = await fetchMetadata(assetID)
        didLoad = true
    }
}
