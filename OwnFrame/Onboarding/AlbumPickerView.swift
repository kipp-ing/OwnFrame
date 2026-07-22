//
//  AlbumPickerView.swift
//  OwnFrame
//
//  Reusable searchable, independently-scrollable album picker shared by onboarding
//  (SourceStepView) and Settings → Sources (SourceLibraryView) — 210, FR-210-27/28. Search
//  narrows by name / year / photo count (case- and diacritic-insensitive via AlbumSearch);
//  each row shows a date·count subtitle; a no-results state appears when nothing matches.
//  Tapping a row adds the album to the library (select-then-confirm: the container supplies
//  the pinned confirm action), already-added albums show a checkmark and are disabled. The
//  list scrolls within its own region so the container's pinned action stays reachable.
//  Accessibility ids are namespaced by `idPrefix` (e.g. onboarding.album / sources.album) so
//  the two hosts stay independently testable.
//

import ImmichClient
import OnboardingKit
import SwiftUI

struct AlbumPickerView: View {
    let albums: [Album]
    @Bindable var sourceLibrary: SourceLibraryViewModel
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
                    Text("Add a shared link instead.")
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
        let label = album.name.isEmpty ? album.id : album.name
        let isAdded = sourceLibrary.sources.contains { $0.label == label }
        Button {
            sourceLibrary.addAlbumSource(albumID: album.id, label: label)
        } label: {
            HStack {
                VStack(alignment: .leading, spacing: 2) {
                    Text(label).foregroundStyle(.primary)
                    if let subtitle = Self.subtitle(for: album) {
                        Text(subtitle).font(.caption).foregroundStyle(.secondary)
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
        .accessibilityIdentifier("\(idPrefix).\(album.id)")
    }

    /// "2024 · 120 photos" — the advisory date range and asset count, each omitted when the
    /// server didn't provide it. Years use a UTC calendar to match `AlbumSearch`'s haystack.
    static func subtitle(for album: Album) -> String? {
        var parts: [String] = []
        if let dateText = dateText(album.startDate, album.endDate) { parts.append(dateText) }
        if let count = album.assetCount { parts.append(count == 1 ? "1 photo" : "\(count) photos") }
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
