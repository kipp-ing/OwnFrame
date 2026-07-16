//
//  PhotoAlbumPickerView.swift
//  Immich Slideshow
//
//  900 / US1: the Photos-album sibling of `AlbumPickerView`, shared by onboarding
//  (SourceStepView) and Settings → Sources (SourceLibraryView). Choosing the Photos tab
//  presents this view, which requests photo access at that moment (FR-900-04 — never at
//  launch) and, under full access, lists the user's albums (user collections + iCloud
//  Shared Albums) through `PhotoLibraryProvider.collections()` — the same neutral surface
//  the engine consumes, so the picker never touches PhotoKit types itself. Search narrows
//  by title (simple contains; the Immich picker's richer `AlbumSearch` is polish).
//  Tapping a row adds the album to the library (select-then-confirm: the container
//  supplies the pinned confirm action); already-added albums show a checkmark and are
//  disabled. Non-full access shows a calm unavailable state — the full per-cause wording
//  (limited/denied guidance) is US3 (T027–T030).
//  Accessibility ids are namespaced by `idPrefix` (onboarding.photos / sources.photos).
//

import OnboardingKit
import PhotoLibraryKit
import PhotoSourceKit
import SwiftUI

struct PhotoAlbumPickerView: View {
    let gateway: any PhotoLibraryGateway
    @Bindable var sourceLibrary: SourceLibraryViewModel
    let idPrefix: String

    @State private var searchText = ""
    @State private var phase: Phase = .requesting
    @State private var collections: [SourceCollection] = []

    enum Phase { case requesting, loaded, unavailable }

    private var filteredCollections: [SourceCollection] {
        guard !searchText.isEmpty else { return collections }
        return collections.filter { $0.title.localizedCaseInsensitiveContains(searchText) }
    }

    var body: some View {
        VStack(spacing: 0) {
            switch phase {
            case .requesting:
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            case .unavailable:
                ContentUnavailableView {
                    Label("Photos access needed", systemImage: "photo.on.rectangle.angled")
                } description: {
                    Text("Allow full photo access in Settings to list your albums.")
                }
                .frame(maxHeight: .infinity)
                .accessibilityIdentifier("\(idPrefix).unavailable")
            case .loaded:
                searchField

                if collections.isEmpty {
                    ContentUnavailableView {
                        Label("No albums in your Photos library", systemImage: "photo.on.rectangle")
                    } description: {
                        Text("Create an album in the Photos app first.")
                    }
                    .frame(maxHeight: .infinity)
                } else if filteredCollections.isEmpty {
                    ContentUnavailableView.search(text: searchText)
                        .frame(maxHeight: .infinity)
                        .accessibilityIdentifier("\(idPrefix).noResults")
                } else {
                    List(filteredCollections, id: \.id) { collection in
                        collectionRow(collection)
                    }
                    .listStyle(.plain)
                }
            }
        }
        .task { await requestAndLoad() }
    }

    /// FR-900-04: access is requested here — the moment the user chooses "Photos album" —
    /// and the album list requires the full grant (limited cannot enumerate albums, R9).
    private func requestAndLoad() async {
        var status = gateway.authorizationStatus()
        if case .notDetermined = status {
            status = await gateway.requestAuthorization()
        }
        guard case .full = status else {
            phase = .unavailable
            return
        }
        do {
            // Enumeration-only provider (nil collectionID): the same auth gate and failure
            // mapping the engine uses, without this view importing Photos.
            collections = try await PhotoLibraryProvider(gateway: gateway).collections()
            phase = .loaded
        } catch {
            phase = .unavailable
        }
    }

    private var searchField: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("Search albums", text: $searchText)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .accessibilityIdentifier("\(idPrefix).search")
            if !searchText.isEmpty {
                Button {
                    searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("\(idPrefix).search.clear")
            }
        }
        .padding(10)
        .background(.quaternary, in: RoundedRectangle(cornerRadius: 10))
        .padding(.horizontal)
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private func collectionRow(_ collection: SourceCollection) -> some View {
        let label = collection.title.isEmpty ? collection.id : collection.title
        let isAdded = sourceLibrary.sources.contains { $0.label == label }
        Button {
            sourceLibrary.addPhotoLibrarySource(collectionID: collection.id, label: label)
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(label).foregroundStyle(.primary)
                    if collection.assetCount > 0 {
                        Text(collection.assetCount == 1 ? "1 photo" : "\(collection.assetCount) photos")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                Spacer()
                if isAdded {
                    Image(systemName: "checkmark").foregroundStyle(.tint)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isAdded)
        .accessibilityIdentifier("\(idPrefix).\(collection.id)")
    }
}
