//
//  AlbumPickerView.swift
//  OwnFrame
//
//  Reusable searchable, independently-scrollable album picker shared by onboarding
//  (SourceStepView) and Settings → Sources (SourceLibraryView) — 210, FR-210-27/28. Search
//  narrows by name / year / photo count (case- and diacritic-insensitive via AlbumSearch);
//  each row shows a date·count subtitle; a no-results state appears when nothing matches.
//  Tapping a row only marks it in the host's `AlbumSelection` (select-then-confirm, FR-210-28):
//  the host's pinned confirm commits the marks and Cancel discards them, so the picker never
//  persists. Marked and already-added albums show a checkmark; already-added ones (matched by
//  album id) are disabled. The list scrolls within its own region so the container's pinned
//  action stays reachable. Accessibility ids are namespaced by `idPrefix` (e.g. onboarding.album
//  / sources.album) so the two hosts stay independently testable.
//

import ImmichClient
import OnboardingKit
import SwiftUI

struct AlbumPickerView: View {
    let albums: [Album]
    @Bindable var sourceLibrary: SourceLibraryViewModel
    @Binding var selection: AlbumSelection
    let idPrefix: String
    @State private var searchText = ""

    private var filteredAlbums: [Album] {
        AlbumSearch.filter(albums, query: searchText)
    }

    var body: some View {
        VStack(spacing: 0) {
            searchField

            if albums.isEmpty {
                ContentUnavailableView {
                    Label("No albums on this server", systemImage: "photo.on.rectangle")
                } description: {
                    Text("Add an Immich link instead.")
                }
                .frame(maxHeight: .infinity)
            } else if filteredAlbums.isEmpty {
                ContentUnavailableView.search(text: searchText)
                    .frame(maxHeight: .infinity)
                    .accessibilityIdentifier("\(idPrefix).noResults")
            } else {
                List(filteredAlbums, id: \.id) { album in
                    albumRow(album)
                }
                .listStyle(.plain)
            }
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
    private func albumRow(_ album: Album) -> some View {
        // The stored label stays the album id for an unnamed album; the row shows its display
        // name, so the id never reaches the screen (120, FR-120-13).
        let label = album.name.isEmpty ? album.id : album.name
        let kind = SourceKind.album(albumID: album.id)
        let shownLabel = SourceLibraryViewModel.displayName(for: Source(label: label, kind: kind))
        let isAdded = sourceLibrary.sources.contains { $0.kind == kind }
        let isMarked = selection.isMarked(kind)
        Button {
            let position = albums.firstIndex { $0.id == album.id } ?? 0
            selection.toggle(.init(kind: kind, label: label, position: position), in: sourceLibrary.library)
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(shownLabel).foregroundStyle(.primary)
                    if let subtitle = Self.subtitle(for: album) {
                        Text(subtitle).font(.caption).foregroundStyle(.secondary)
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
        .accessibilityIdentifier("\(idPrefix).\(album.id)")
    }

    /// "2024 · 120 photos" — the advisory date range and asset count, each omitted when the
    /// server didn't provide it. Years use a UTC calendar to match `AlbumSearch`'s haystack.
    static func subtitle(for album: Album) -> String? {
        var parts: [String] = []
        if let dateText = dateText(album.startDate, album.endDate) { parts.append(dateText) }
        // Built as a String and joined, so the count needs an explicit lookup — a bare literal
        // here would ship the English text into an otherwise localized subtitle.
        if let count = album.assetCount {
            parts.append(count == 1 ? String(localized: "1 photo") : String(localized: "\(count) photos"))
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    private static func dateText(_ start: Date?, _ end: Date?) -> String? {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .current
        let years = [start, end].compactMap { $0.map { calendar.component(.year, from: $0) } }
        guard let first = years.first, let last = years.last else { return nil }
        return first == last ? "\(first)" : "\(first)–\(last)"
    }
}
