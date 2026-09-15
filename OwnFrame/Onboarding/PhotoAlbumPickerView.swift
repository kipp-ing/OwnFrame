//
//  PhotoAlbumPickerView.swift
//  OwnFrame
//
//  900 / US1: the Photos-album sibling of `AlbumPickerView`, shared by onboarding
//  (SourceStepView) and Settings → Sources (SourceLibraryView). Choosing the Photos tab
//  presents this view, which requests photo access at that moment (FR-900-04 — never at
//  launch) and, under full access, lists the user's albums (user collections + iCloud
//  Shared Albums) through `PhotoLibraryProvider.collections()` — the same neutral surface
//  the engine consumes, so the picker never touches PhotoKit types itself. Search narrows
//  by title (simple contains; the Immich picker's richer `AlbumSearch` is polish).
//  With a `selection`, tapping a row only marks it (select-then-confirm, FR-210-28): the
//  host's pinned confirm commits and Cancel discards. Without one (the welcome screen's
//  iCloud path, 220, exempt by the FR-210-28 amendment) a tap adds the album at once.
//  Marked and already-added albums show a checkmark; already-added ones (matched by
//  collection id) are disabled. Non-full access shows a calm unavailable state — the full per-cause wording
//  (limited/denied guidance) is US3 (T027–T030).
//  Accessibility ids are namespaced by `idPrefix` (onboarding.photos / sources.photos).
//

import OnboardingKit
import PhotoLibraryKit
import PhotoSourceKit
import PurchaseKit
import SwiftUI
import UIKit

struct PhotoAlbumPickerView: View {
    let gateway: any PhotoLibraryGateway
    @Bindable var sourceLibrary: SourceLibraryViewModel
    /// The host's pending marks; nil means a tap adds immediately (welcome iCloud path only).
    var selection: Binding<AlbumSelection>? = nil
    let idPrefix: String

    @State private var searchText = ""
    @State private var phase: Phase = .requesting
    @State private var collections: [SourceCollection] = []
    @Environment(\.openURL) private var openURL

    /// `limited` carries the Selected-Photos pseudo-collection (nil when its enumeration
    /// failed — the row is still offered, just without a count). `denied` covers denied AND
    /// a request left unanswered; `unavailable` is a load failure under full access.
    enum Phase { case requesting, loaded, limited(SourceCollection?), denied, unavailable }

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
            case let .limited(pool):
                limitedContent(pool)
            case .denied:
                deniedContent
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

    /// FR-900-04: access is requested here — the moment the user chooses "iCloud album" —
    /// and the album list requires the full grant (limited cannot enumerate albums, R9).
    /// Limited access offers the single Selected-Photos pool instead of an album list
    /// (US3-2); denied gets the calm Settings path (US3-1).
    private func requestAndLoad() async {
        var status = gateway.authorizationStatus()
        if case .notDetermined = status {
            status = await gateway.requestAuthorization()
        }
        switch status {
        case .full:
            do {
                // Enumeration-only provider (nil collectionID): the same auth gate and
                // failure mapping the engine uses, without this view importing Photos.
                collections = try await PhotoLibraryProvider(gateway: gateway).collections()
                phase = .loaded
            } catch {
                phase = .unavailable
            }
        case .limited:
            // The pool row is offered even when its enumeration fails — the user can still
            // add it and manage the selection; only the count is missing then.
            phase = .limited(try? SelectedPhotosSource.collection(using: gateway))
        case .denied, .notDetermined:
            phase = .denied
        }
    }

    // MARK: - Limited (US3-2)

    @ViewBuilder
    private func limitedContent(_ pool: SourceCollection?) -> some View {
        // The pool's model-side title is a fixed English identifier (PhotoLibraryKit ships no
        // catalog); the row shows — and persists — the localized name instead. Identity is the
        // sentinel collection ID, not the label, so neither a rename nor a language switch can
        // make an already-added pool look un-added.
        let label = String(localized: "Selected Photos")
        let kind = SourceKind.photoLibrary(collectionID: PhotoLibrarySource.selectedPhotosID)
        let isAdded = sourceLibrary.sources.contains { $0.kind == kind }
        let isMarked = selection?.wrappedValue.isMarked(kind) ?? false
        List {
            Section {
                Button {
                    pick(kind: kind, label: label, position: 0)
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(label).foregroundStyle(.primary)
                            if let count = pool?.assetCount {
                                Text(count == 1 ? "1 photo" : "\(count) photos")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        Spacer()
                        if isAdded || isMarked {
                            Image(systemName: "checkmark").foregroundStyle(.tint)
                        }
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(isAdded)
                .accessibilityAddTraits(isMarked ? .isSelected : [])
                .accessibilityIdentifier("\(idPrefix).\(PhotoLibrarySource.selectedPhotosID)")

                Button {
                    gateway.presentManageSelection()
                } label: {
                    Label("Manage selection", systemImage: "checklist")
                }
                .accessibilityIdentifier("\(idPrefix).manageSelection")
            } footer: {
                // The honest note (US3-2): never render an empty album list as if the user
                // had no albums — say why they are missing.
                Text("Photo access is limited to selected photos. Albums — including iCloud Shared Albums — need full photo access, which you can grant in Settings.")
                    .accessibilityIdentifier("\(idPrefix).limitedNote")
            }
        }
        .listStyle(.plain)
    }

    // MARK: - Denied (US3-1)

    private var deniedContent: some View {
        VStack(spacing: 16) {
            ContentUnavailableView {
                Label("No photo access", systemImage: "photo.on.rectangle.angled")
            } description: {
                Text("The frame can't see your photos. Allow photo access in Settings to play albums from your Photos library — other sources keep working.")
                    .accessibilityIdentifier("\(idPrefix).denied")
            }
            Button("Open Settings") {
                if let url = URL(string: UIApplication.openSettingsURLString) {
                    openURL(url)
                }
            }
            .buttonStyle(.accentProminent)
            .accessibilityIdentifier("\(idPrefix).openSettings")
        }
        .frame(maxHeight: .infinity)
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
        let kind = SourceKind.photoLibrary(collectionID: collection.id)
        let isAdded = sourceLibrary.sources.contains { $0.kind == kind }
        let isMarked = selection?.wrappedValue.isMarked(kind) ?? false
        Button {
            let position = collections.firstIndex { $0.id == collection.id } ?? 0
            pick(kind: kind, label: label, position: position)
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
                if isAdded || isMarked {
                    Image(systemName: "checkmark").foregroundStyle(.tint)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .disabled(isAdded)
        .accessibilityAddTraits(isMarked ? .isSelected : [])
        .accessibilityIdentifier("\(idPrefix).\(collection.id)")
    }

    /// Marks the album in the host's selection, or adds it at once when there is none. The
    /// immediate add goes through the same batch path, so a name already used by another source
    /// gets the counter suffix instead of a silently rejected tap.
    private func pick(kind: SourceKind, label: String, position: Int) {
        let candidate = AlbumSelection.Candidate(kind: kind, label: label, position: position)
        if let selection {
            selection.wrappedValue.toggle(candidate, in: sourceLibrary.library)
        } else {
            sourceLibrary.addSources([candidate])
        }
    }
}
