//
//  PhotoInfoView.swift
//  Immich Slideshow
//
//  Slice C — Liquid Glass photo-info overlay shown from the chrome: date/time and
//  location for the current photo, fetched lazily from Immich EXIF. Reloads when
//  the slideshow advances to another asset. Stays quiet (renders nothing) when the
//  photo carries no usable info, keeping with the calm default.
//

import ImmichClient
import SwiftUI

struct PhotoInfoView: View {
    let api: any ImmichAPI
    let assetID: String

    @State private var info: AssetInfo?
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
        guard let takenAt = info?.takenAt else { return nil }
        return takenAt.formatted(date: .long, time: .shortened)
    }

    private var locationText: String? {
        let parts = [info?.city, info?.country].compactMap { $0 }.filter { !$0.isEmpty }
        return parts.isEmpty ? nil : parts.joined(separator: ", ")
    }

    private func load() async {
        didLoad = false
        info = try? await api.assetInfo(assetID: assetID)
        didLoad = true
    }
}
