//
//  SourceLibraryView.swift
//  OwnFrame
//
//  Settings → Sources (120, US2): manage the saved slideshow sources (Immich albums
//  and shared links). Tap a source to make it active — the running slideshow restarts
//  from it (the view model delegates to the app-level switch). Swipe to rename/remove,
//  reorder via the edit button, and add a new album (picker) or shared link (resolve-first;
//  a password is asked for only when the link needs one — 210, US4).
//

import ImmichClient
import OnboardingKit
import PhotoLibraryKit
import SwiftUI

struct SourceLibraryView: View {
    @Bindable var viewModel: SourceLibraryViewModel
    var makeServerAPI: () async -> (any ImmichAPI)? = { nil }
    // 900 / US1: builds the PhotoKit seam for the add-sheet's Photos-album tab — the real
    // gateway in production, the scripted fake under `--uitest` (injected from the app).
    var makePhotoGateway: () -> any PhotoLibraryGateway = { PHKitGateway() }

    @State private var showAddSheet = false
    @State private var renameTarget: Source?
    @State private var renameText = ""

    var body: some View {
        List {
            Section {
                ForEach(viewModel.sources) { source in
                    Button {
                        viewModel.setActive(id: source.id)
                    } label: {
                        SourceRow(source: source, isActive: source.id == viewModel.activeID)
                    }
                    .accessibilityIdentifier("sources.row.\(source.id)")
                    .swipeActions(edge: .trailing) {
                        Button(role: .destructive) {
                            viewModel.remove(id: source.id)
                        } label: {
                            Label("Delete", systemImage: "trash")
                        }
                        Button {
                            renameText = source.label
                            renameTarget = source
                        } label: {
                            Label("Rename", systemImage: "pencil")
                        }
                        .tint(.blue)
                    }
                }
                .onMove { viewModel.move(from: $0, to: $1) }
            } footer: {
                if viewModel.sources.isEmpty {
                    Text("No source yet. Add an album or a shared link.")
                } else {
                    Text("Tap a source to make it active.")
                }
            }
        }
        .navigationTitle("Sources")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                EditButton()
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    viewModel.errorMessage = nil
                    showAddSheet = true
                } label: {
                    Image(systemName: "plus")
                }
                .accessibilityIdentifier("sources.add")
            }
        }
        .sheet(isPresented: $showAddSheet) {
            AddSourceView(viewModel: viewModel, makeServerAPI: makeServerAPI, makePhotoGateway: makePhotoGateway)
        }
        .alert("Rename", isPresented: renameAlertPresented, presenting: renameTarget) { source in
            TextField("Name", text: $renameText)
                .accessibilityIdentifier("sources.rename.field")
            Button("Save") { viewModel.rename(id: source.id, to: renameText) }
            Button("Cancel", role: .cancel) {}
        }
    }

    private var renameAlertPresented: Binding<Bool> {
        Binding(
            get: { renameTarget != nil },
            set: { if !$0 { renameTarget = nil } }
        )
    }
}

/// One row in the source list: a kind icon, the label, a subtitle locator, and an
/// "Active" marker on the active source (also surfaced in the accessibility label).
private struct SourceRow: View {
    let source: Source
    let isActive: Bool

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: source.kind.iconName)
                .foregroundStyle(.secondary)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(source.label)
                    .foregroundStyle(.primary)
                Text(source.kind.subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            Spacer()
            if isActive {
                Text("Active")
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(.tint)
                Image(systemName: "checkmark")
                    .foregroundStyle(.tint)
            }
        }
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityLabel(isActive ? "\(source.label), active" : source.label)
    }
}

/// Add-source sheet: pick the kind, then confirm. The album tab uses the same searchable,
/// subscrollable `AlbumPickerView` as onboarding (210, FR-210-27/28): tap albums to add them
/// (select-then-confirm) and Done to finish; the shared-link form validates the link (and
/// password, if any) before saving anything.
private struct AddSourceView: View {
    @Bindable var viewModel: SourceLibraryViewModel
    var makeServerAPI: () async -> (any ImmichAPI)?
    var makePhotoGateway: () -> any PhotoLibraryGateway

    @Environment(\.dismiss) private var dismiss
    @State private var kind: Kind = .album
    /// Source count when the sheet opened, so the Done bar can report how many were added
    /// in this pass rather than the library total.
    @State private var initialSourceCount: Int?

    enum Kind: Hashable { case album, sharedLink, photoLibrary }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("Type", selection: $kind) {
                    Text("Album").tag(Kind.album)
                    Text("Shared link").tag(Kind.sharedLink)
                    Text("Photos album").tag(Kind.photoLibrary)
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.top, 8)
                .accessibilityIdentifier("sources.add.type")

                // Album-add errors (Immich and Photos alike) surface here; the shared-link
                // form reports its own resolve / password errors inline (210, US4).
                if kind != .sharedLink, let errorMessage = viewModel.errorMessage {
                    Label(errorMessage, systemImage: "exclamationmark.triangle")
                        .font(.callout)
                        .foregroundStyle(.red)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.horizontal)
                        .padding(.top, 8)
                        .accessibilityIdentifier("sources.add.error")
                }

                switch kind {
                case .album:
                    AddAlbumPicker(viewModel: viewModel, makeServerAPI: makeServerAPI)
                case .sharedLink:
                    Form {
                        SharedLinkAddForm(
                            sourceLibrary: viewModel,
                            idPrefix: "sources.add",
                            submitIDSuffix: "submit"
                        ) { dismiss() }
                    }
                case .photoLibrary:
                    PhotoAlbumPickerView(gateway: makePhotoGateway(), sourceLibrary: viewModel, idPrefix: "sources.photos")
                }
            }
            .navigationTitle("Add source")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .accessibilityIdentifier("sources.add.cancel")
                }
            }
            // Albums (Immich and Photos) add on tap; Done finishes. The shared-link tab
            // finishes via its own Add button, so it carries no pinned Done (210, FR-210-28).
            .safeAreaInset(edge: .bottom) {
                if kind != .sharedLink {
                    AddAlbumDoneBar(addedCount: viewModel.sources.count - (initialSourceCount ?? viewModel.sources.count)) {
                        dismiss()
                    }
                }
            }
            .onAppear { if initialSourceCount == nil { initialSourceCount = viewModel.sources.count } }
        }
    }
}

/// Loads the connected server's albums, then shows the shared `AlbumPickerView`. Tapping a
/// row adds the album to the library; the pinned Done in `AddSourceView` finishes.
private struct AddAlbumPicker: View {
    @Bindable var viewModel: SourceLibraryViewModel
    var makeServerAPI: () async -> (any ImmichAPI)?

    @State private var albums: [Album] = []
    @State private var phase: Phase = .loading

    enum Phase { case loading, loaded, failed }

    var body: some View {
        Group {
            switch phase {
            case .loading:
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .failed:
                ContentUnavailableView {
                    Label("Couldn't load albums", systemImage: "wifi.exclamationmark")
                } description: {
                    Text("Add a shared link instead.")
                }
                .frame(maxHeight: .infinity)
            case .loaded:
                AlbumPickerView(albums: albums, sourceLibrary: viewModel, idPrefix: "sources.album")
            }
        }
        .task {
            guard let api = await makeServerAPI() else { phase = .failed; return }
            do {
                albums = try await api.albums()
                phase = .loaded
            } catch {
                phase = .failed
            }
        }
    }
}

/// The pinned bottom bar on the album tab: a Done action that finishes adding, annotated with
/// how many albums were added in this pass (210, FR-210-28).
private struct AddAlbumDoneBar: View {
    let addedCount: Int
    let onDone: () -> Void

    var body: some View {
        Button(action: onDone) {
            Text(doneLabel).frame(maxWidth: .infinity)
        }
        .buttonStyle(.borderedProminent)
        .padding()
        .background(.bar)
        .accessibilityIdentifier("sources.add.done")
    }

    private var doneLabel: String {
        switch addedCount {
        case ..<1: "Done"
        case 1: "Done · 1 added"
        default: "Done · \(addedCount) added"
        }
    }
}

private extension SourceKind {
    var iconName: String {
        switch self {
        case .album: "photo.stack"
        case .sharedLink: "link"
        case .photoLibrary: "photo.on.rectangle.angled"
        }
    }

    var subtitle: String {
        switch self {
        case .album:
            "Album"
        case let .sharedLink(baseURL, _):
            baseURL.host ?? "Shared link"
        case .photoLibrary:
            // 900: a device Apple Photos / iCloud album.
            "Photos"
        }
    }
}
