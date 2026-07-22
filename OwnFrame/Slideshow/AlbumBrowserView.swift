//
//  AlbumBrowserView.swift
//  OwnFrame
//
//  Slice B — Liquid Glass album browser presented as a sheet over the running
//  slideshow (the show keeps playing behind). Album grid → tap an album → its
//  photo thumbnail grid → tap a thumbnail to start the slideshow there. One album
//  is the active source at a time; selection is handed back via `onSelect`.
//

import ImmichClient
import SwiftUI

struct AlbumBrowserView: View {
    let api: any ImmichAPI
    let currentAlbumID: String?
    /// Hands the chosen (album, asset) back to the slideshow, which switches album
    /// if needed and jumps to that asset.
    var onSelect: (_ albumID: String, _ assetID: String) -> Void
    /// Whether a server (base URL + API key) is configured — the discriminator that keeps the
    /// "no server configured" guidance distinct from a genuine load failure, mirroring the add
    /// source picker (210, FR-210-30 / FR-210-27). Injectable; defaults to `true` because both
    /// runtime call sites present this browser only with a live connection, so the default
    /// preserves existing behavior. A shared-link-only caller can pass the host-tested
    /// `OnboardingKit.serverConfigured(config:keychain:)` to route to the connection editor.
    var isServerConfigured: () -> Bool = { true }
    /// Routes the no-server guidance into the shared server-connection editor (FR-210-29); nil
    /// withholds only the shortcut button (the guidance still explains the problem).
    var onAddServer: (() -> Void)? = nil

    @Environment(\.dismiss) private var dismiss
    @State private var albums: [Album] = []
    @State private var phase: BrowserPhase = .loading

    private let columns = [GridItem(.adaptive(minimum: 150), spacing: 16)]

    var body: some View {
        NavigationStack {
            content
                .navigationTitle("Albums")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") { dismiss() }
                    }
                }
        }
        .task { await loadAlbums() }
    }

    @ViewBuilder
    private var content: some View {
        switch phase {
        case .loading:
            ProgressView().controlSize(.large)
        case .noServer:
            ContentUnavailableView {
                Label("Add a server or check your connection", systemImage: "server.rack")
            } description: {
                Text("Listing albums needs an Immich server. Add one to browse albums, or add a shared link instead.")
            } actions: {
                if let onAddServer {
                    Button("Add a server", action: onAddServer)
                        .accessibilityIdentifier("album.addServer")
                }
            }
        case .failed:
            ContentUnavailableView(
                "Couldn't load albums",
                systemImage: "wifi.exclamationmark"
            )
        case .loaded where albums.isEmpty:
            ContentUnavailableView("No albums", systemImage: "photo.on.rectangle")
        case .loaded:
            ScrollView {
                LazyVGrid(columns: columns, spacing: 16) {
                    ForEach(albums, id: \.id) { album in
                        NavigationLink {
                            AlbumThumbnailGrid(
                                api: api,
                                album: album,
                                onSelect: { assetID in
                                    onSelect(album.id, assetID)
                                    dismiss()
                                }
                            )
                        } label: {
                            AlbumCard(name: album.name, isCurrent: album.id == currentAlbumID)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("album.row.\(album.id)")
                    }
                }
                .padding()
            }
        }
    }

    private func loadAlbums() async {
        // No stored base URL + API key is the no-server case — reached without a network call,
        // guiding the user to add a server rather than showing "couldn't load albums". A thrown
        // error below is a genuine load failure against a configured server (210, FR-210-30).
        guard isServerConfigured() else {
            phase = .noServer
            return
        }
        do {
            albums = try await api.albums()
            phase = .loaded
        } catch {
            phase = .failed
        }
    }

    private enum BrowserPhase { case loading, loaded, noServer, failed }
}

/// A single album tile in the album grid.
private struct AlbumCard: View {
    let name: String
    let isCurrent: Bool

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "photo.stack")
                .font(.system(size: 40))
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity)
                .frame(height: 110)
            Text(name)
                .font(.headline)
                .lineLimit(1)
            if isCurrent {
                Text("Active")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.tint)
            }
        }
        .padding()
        .frame(maxWidth: .infinity)
        .glassCard(cornerRadius: 18)
    }
}

/// The photo thumbnail grid for one album. Tapping a thumbnail starts the show there.
private struct AlbumThumbnailGrid: View {
    let api: any ImmichAPI
    let album: Album
    var onSelect: (_ assetID: String) -> Void

    @State private var assets: [Asset] = []
    @State private var phase: GridPhase = .loading

    private let columns = [GridItem(.adaptive(minimum: 110), spacing: 8)]

    var body: some View {
        content
            .navigationTitle(album.name)
            .navigationBarTitleDisplayMode(.inline)
            .task { await loadAssets() }
    }

    @ViewBuilder
    private var content: some View {
        switch phase {
        case .loading:
            ProgressView().controlSize(.large)
        case .failed:
            ContentUnavailableView(
                "Couldn't load photos",
                systemImage: "wifi.exclamationmark"
            )
        case .loaded where assets.isEmpty:
            ContentUnavailableView("No photos", systemImage: "photo")
        case .loaded:
            ScrollView {
                LazyVGrid(columns: columns, spacing: 8) {
                    ForEach(assets, id: \.id) { asset in
                        Button { onSelect(asset.id) } label: {
                            ThumbnailCell(api: api, assetID: asset.id)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("album.thumbnail.\(asset.id)")
                    }
                }
                .padding(8)
            }
        }
    }

    private func loadAssets() async {
        do {
            assets = try await api.assets(albumID: album.id).filter { $0.type == "IMAGE" }
            phase = .loaded
        } catch {
            phase = .failed
        }
    }

    private enum GridPhase { case loading, loaded, failed }
}

/// Lazily loads a single asset's thumbnail (cheaper than the full preview).
private struct ThumbnailCell: View {
    let api: any ImmichAPI
    let assetID: String
    @State private var image: UIImage?

    var body: some View {
        ZStack {
            Color(.secondarySystemBackground)
            if let image {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFill()
            }
        }
        .aspectRatio(1, contentMode: .fill)
        .clipShape(RoundedRectangle(cornerRadius: 10))
        .contentShape(RoundedRectangle(cornerRadius: 10))
        .task { await load() }
    }

    private func load() async {
        guard image == nil else { return }
        guard let data = try? await api.thumbnail(assetID: assetID),
              let decoded = UIImage(data: data) else { return }
        image = decoded
    }
}
