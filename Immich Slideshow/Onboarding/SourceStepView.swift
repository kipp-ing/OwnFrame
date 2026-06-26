//
//  SourceStepView.swift
//  Immich Slideshow
//
//  Onboarding step 2 (120, US2): add the first slideshow source after connecting —
//  an Immich album (picked from the connected server's albums) or a shared link
//  (resolve-first; a password is asked for only when the link needs one — 210, US4).
//  The first source added becomes active. The matching
//  confirmation step lists the saved library with the active source marked before the
//  slideshow starts. Both bind the OnboardingViewModel (connection + navigation) and a
//  SourceLibraryViewModel (the persisted library, shared with the rest of the app).
//  The album tab uses the shared `AlbumPickerView`, the same picker Settings uses (210, FR-210-27).
//

import ImmichClient
import OnboardingKit
import SwiftUI

struct SourceStepView: View {
    @Bindable var onboarding: OnboardingViewModel
    @Bindable var sourceLibrary: SourceLibraryViewModel

    enum Kind: Hashable { case album, sharedLink }
    @State private var kind: Kind = .album

    var body: some View {
        VStack(spacing: 0) {
            Text("Add at least one source to play — an Immich album or a shared link. The first source you add starts the slideshow.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal)
                .padding(.top, 8)
                .accessibilityIdentifier("onboarding.source.description")

            Picker("Source type", selection: $kind) {
                Text("Album").tag(Kind.album)
                Text("Shared link").tag(Kind.sharedLink)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal)
            .padding(.top, 8)
            .accessibilityIdentifier("onboarding.source.type")

            // Album-add errors surface here; the shared-link form reports its own resolve /
            // password errors inline (210, US4), so this stays scoped to the album tab.
            if kind == .album, let errorMessage = sourceLibrary.errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle")
                    .font(.callout)
                    .foregroundStyle(.red)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal)
                    .padding(.top, 8)
                    .accessibilityIdentifier("onboarding.source.error")
            }

            switch kind {
            case .album:
                AlbumPickerView(albums: onboarding.albums, sourceLibrary: sourceLibrary, idPrefix: "onboarding.album")
            case .sharedLink:
                Form {
                    SharedLinkAddForm(
                        sourceLibrary: sourceLibrary,
                        idPrefix: "onboarding.sharedLink",
                        submitIDSuffix: "add"
                    )
                }
            }
        }
        .navigationTitle("Add a source")
        // The primary action stays pinned while the album list scrolls underneath (210, US3).
        .safeAreaInset(edge: .bottom) {
            if !sourceLibrary.sources.isEmpty {
                AddedSourcesBar(count: sourceLibrary.sources.count) {
                    onboarding.proceedToConfirm()
                }
            }
        }
        .task { await onboarding.loadAlbumsIfNeeded() }
    }
}

/// The pinned bottom bar: a compact added-count and the primary Continue action (210, US3).
private struct AddedSourcesBar: View {
    let count: Int
    let onContinue: () -> Void

    var body: some View {
        VStack(spacing: 8) {
            Text(count == 1 ? "1 source added" : "\(count) sources added")
                .font(.footnote)
                .foregroundStyle(.secondary)
            Button(action: onContinue) {
                Text("Continue").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .accessibilityIdentifier("onboarding.source.continue")
        }
        .padding()
        .background(.bar)
    }
}

/// Onboarding confirmation step: lists the saved library with the active source marked,
/// lets the user add another source, and starts the slideshow.
struct OnboardingConfirmStepView: View {
    @Bindable var onboarding: OnboardingViewModel
    @Bindable var sourceLibrary: SourceLibraryViewModel

    var body: some View {
        List {
            Section {
                Text("Review your sources, then start the slideshow.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("onboarding.confirm.description")
            }

            Section {
                ForEach(sourceLibrary.sources) { source in
                    HStack(spacing: 12) {
                        Image(systemName: source.kind.onboardingIconName)
                            .foregroundStyle(.secondary)
                            .frame(width: 24)
                        Text(source.label)
                        Spacer()
                        if source.id == sourceLibrary.activeID {
                            Text("Active")
                                .font(.caption2.weight(.semibold))
                                .foregroundStyle(.tint)
                            Image(systemName: "checkmark").foregroundStyle(.tint)
                        }
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel(source.id == sourceLibrary.activeID ? "\(source.label), active" : source.label)
                    .accessibilityIdentifier("onboarding.confirm.row.\(source.id)")
                }
            } header: {
                Text("Your sources")
            } footer: {
                Text("The active source plays first. You can manage sources later in Settings.")
            }

            Section {
                Button("Add another source") {
                    onboarding.backToSource()
                }
                .accessibilityIdentifier("onboarding.confirm.addMore")

                Button {
                    onboarding.finish()
                } label: {
                    Text("Start slideshow")
                }
                .accessibilityIdentifier("onboarding.confirm.start")
            }
        }
        .navigationTitle("Confirm")
    }
}

private extension SourceKind {
    var onboardingIconName: String {
        switch self {
        case .album: "photo.stack"
        case .sharedLink: "link"
        }
    }
}
