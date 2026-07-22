//
//  TVOnboardingView.swift
//  OwnFrameTV
//
//  Topic 1000 (US2) — the Apple TV first-run setup screen. A self-contained, focus-driven
//  tvOS view that DRIVES the shared `OnboardingViewModel` from OnboardingKit (the same
//  connection/navigation logic the iPad app uses); only the presentation is tvOS-native.
//
//  The iPad's Photos-library path is intentionally omitted on tvOS (no on-device photo
//  library), so the choice screen offers just the shared-link and server paths.
//
//  Album selection: `OnboardingViewModel` has no "record the picked album" method — on iOS
//  that lives on a separate `SourceLibraryViewModel` sharing the same store. Rather than pull
//  that dependency in here, the picked album is surfaced through the `onSelectAlbum` closure
//  so the orchestrator can persist it (e.g. `SourceLibraryViewModel.addAlbumSource`) before
//  the confirm step's `finish()` reads it back from the shared store.
//
//  Routing to the running slideshow (step == .done) is handled by the orchestrator; this view
//  renders `EmptyView` there and calls `onFinished()` when the user starts the show.
//

import ImmichClient
import OnboardingKit
import SwiftUI

struct TVOnboardingView: View {
    let viewModel: OnboardingViewModel
    /// Called when the user starts the slideshow from the confirm step (after `finish()`).
    var onFinished: () -> Void = {}
    /// Seam for recording the picked album into the persisted source library — wired by the
    /// orchestrator (`OnboardingViewModel` itself has no album-record method; see file header).
    var onSelectAlbum: (Album) -> Void = { _ in }

    /// The album the user picked on the source step, shown as a summary on confirm.
    @State private var selectedAlbumName: String?

    var body: some View {
        switch viewModel.step {
        case .choice:
            TVChoiceStep(viewModel: viewModel)
        case .sharedLinkSetup:
            TVSharedLinkStep(viewModel: viewModel)
        case .connection:
            TVConnectionStep(viewModel: viewModel)
        case .source:
            TVSourceStep(viewModel: viewModel) { album in
                selectedAlbumName = album.name.isEmpty ? album.id : album.name
                onSelectAlbum(album)
                viewModel.proceedToConfirm()
            }
        case .confirm:
            TVConfirmStep(
                viewModel: viewModel,
                selectedAlbumName: selectedAlbumName,
                onFinished: onFinished
            )
        case .photoLibrarySetup:
            TVPhotoLibraryUnavailableStep(viewModel: viewModel)
        case .done:
            // Routing to the running slideshow is handled by the orchestrator.
            EmptyView()
        }
    }
}

// MARK: - Shared scaffold

/// A calm, dark, focus-navigable full-screen column: a large centred title/subtitle, the
/// step's controls, and — where the flow allows going back — an on-screen Back button (the
/// Menu button is handled by the host).
private struct TVStepScaffold<Content: View>: View {
    let title: String
    var subtitle: String? = nil
    let viewModel: OnboardingViewModel
    @ViewBuilder var content: Content

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()

            ScrollView {
                VStack(spacing: 44) {
                    VStack(spacing: 16) {
                        Text(title)
                            .font(.largeTitle.weight(.semibold))
                            .multilineTextAlignment(.center)
                        if let subtitle {
                            Text(subtitle)
                                .font(.title3)
                                .foregroundStyle(.secondary)
                                .multilineTextAlignment(.center)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }

                    content

                    if viewModel.canGoBack {
                        Button("Back") { viewModel.back() }
                            .buttonStyle(.bordered)
                    }
                }
                .frame(maxWidth: 1200)
                .frame(maxWidth: .infinity)
                .padding(.horizontal, 120)
                .padding(.vertical, 100)
            }
        }
        .foregroundStyle(.white)
    }
}

/// Inline error + spinner row shared by the connection and shared-link steps.
private struct TVStatusRow: View {
    let errorMessage: String?
    let isBusy: Bool

    var body: some View {
        VStack(spacing: 16) {
            if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle")
                    .font(.title3)
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
            }
            if isBusy {
                ProgressView()
            }
        }
    }
}

// MARK: - Steps

/// First-run entry: pick the shared-link path or the server path. The Photos-library path is
/// not offered on tvOS.
private struct TVChoiceStep: View {
    let viewModel: OnboardingViewModel

    var body: some View {
        TVStepScaffold(
            title: "Welcome",
            subtitle: "Choose how to reach your photos. You can change this later.",
            viewModel: viewModel
        ) {
            VStack(spacing: 28) {
                Button {
                    viewModel.choosePath(.sharedLink)
                } label: {
                    TVChoiceLabel(
                        title: "Use a shared album link",
                        detail: "Paste an Immich share link — no account or API key needed.",
                        systemImage: "link"
                    )
                }

                Button {
                    viewModel.choosePath(.server)
                } label: {
                    TVChoiceLabel(
                        title: "Connect to my Immich server",
                        detail: "Sign in with your server address and an API key to pick an album.",
                        systemImage: "externaldrive.connected.to.line.below"
                    )
                }
            }
            .buttonStyle(.bordered)
        }
    }
}

/// The two-line label inside a choice button.
private struct TVChoiceLabel: View {
    let title: String
    let detail: String
    let systemImage: String

    var body: some View {
        HStack(spacing: 28) {
            Image(systemName: systemImage)
                .font(.largeTitle)
                .frame(width: 60)
            VStack(alignment: .leading, spacing: 8) {
                Text(title).font(.title2.weight(.semibold))
                Text(detail)
                    .font(.body)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 12)
    }
}

/// Shared-link path: paste the link, then Continue drives the shared model's connection
/// submission. Errors and the busy spinner surface inline.
private struct TVSharedLinkStep: View {
    @Bindable var viewModel: OnboardingViewModel

    var body: some View {
        TVStepScaffold(
            title: "Shared link",
            subtitle: "Set up a slideshow from just a shared link — no account or API key needed.",
            viewModel: viewModel
        ) {
            VStack(spacing: 32) {
                TextField("https://host/s/slug", text: $viewModel.serverURLInput)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .disabled(viewModel.isBusy)

                TVStatusRow(errorMessage: viewModel.errorMessage, isBusy: viewModel.isBusy)

                Button("Continue") {
                    Task { await viewModel.submitConnection() }
                }
                .buttonStyle(.borderedProminent)
                .disabled(viewModel.isBusy || isBlank(viewModel.serverURLInput))
            }
        }
    }
}

/// Server path: server address + API key, then Continue validates the connection and advances
/// to the album (source) step.
private struct TVConnectionStep: View {
    @Bindable var viewModel: OnboardingViewModel

    var body: some View {
        TVStepScaffold(
            title: "Connect to your server",
            subtitle: "Enter your Immich address and an API key to browse and pick an album.",
            viewModel: viewModel
        ) {
            VStack(spacing: 32) {
                TextField("https://immich.example.com", text: $viewModel.serverURLInput)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .disabled(viewModel.isBusy)

                SecureField("API key", text: $viewModel.apiKeyInput)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .disabled(viewModel.isBusy)

                TVStatusRow(errorMessage: viewModel.errorMessage, isBusy: viewModel.isBusy)

                Button("Continue") {
                    Task { await viewModel.submitConnection() }
                }
                .buttonStyle(.borderedProminent)
                .disabled(
                    viewModel.isBusy
                        || isBlank(viewModel.serverURLInput)
                        || viewModel.apiKeyInput.isEmpty
                )
            }
        }
    }
}

/// Source step: load the connected server's albums and let the user pick one. Selecting a row
/// records it (via the parent's closure) and advances to confirm.
private struct TVSourceStep: View {
    let viewModel: OnboardingViewModel
    let onSelect: (Album) -> Void

    var body: some View {
        TVStepScaffold(
            title: "Choose an album",
            subtitle: "Pick the album to play. You can change it later in Settings.",
            viewModel: viewModel
        ) {
            Group {
                if viewModel.isBusy && viewModel.albums.isEmpty {
                    ProgressView()
                        .padding(.vertical, 40)
                } else if viewModel.albums.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "photo.on.rectangle")
                            .font(.largeTitle)
                            .foregroundStyle(.secondary)
                        Text("No albums on this server")
                            .font(.title3)
                            .foregroundStyle(.secondary)
                    }
                    .padding(.vertical, 40)
                } else {
                    LazyVStack(spacing: 20) {
                        ForEach(viewModel.albums, id: \.id) { album in
                            Button {
                                onSelect(album)
                            } label: {
                                TVAlbumRow(album: album)
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                }
            }
        }
        .task { await viewModel.loadAlbumsIfNeeded() }
    }
}

/// One album row: name plus an advisory photo count when the server provided one.
private struct TVAlbumRow: View {
    let album: Album

    var body: some View {
        HStack(spacing: 20) {
            Image(systemName: "photo.stack")
            VStack(alignment: .leading, spacing: 6) {
                Text(album.name.isEmpty ? album.id : album.name)
                    .font(.title3.weight(.semibold))
                if let count = album.assetCount {
                    Text(count == 1 ? "1 photo" : "\(count) photos")
                        .font(.body)
                        .foregroundStyle(.secondary)
                }
            }
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 8)
    }
}

/// Confirm step: a short summary and the primary Start action. `finish()` persists the
/// active source, then `onFinished()` lets the orchestrator route to the slideshow.
private struct TVConfirmStep: View {
    let viewModel: OnboardingViewModel
    let selectedAlbumName: String?
    let onFinished: () -> Void

    var body: some View {
        TVStepScaffold(
            title: "Ready to play",
            subtitle: summary,
            viewModel: viewModel
        ) {
            Button("Start slideshow") {
                viewModel.finish()
                onFinished()
            }
            .buttonStyle(.borderedProminent)
        }
    }

    private var summary: String {
        if let selectedAlbumName {
            return "\"\(selectedAlbumName)\" will play on this Apple TV."
        }
        return "Your slideshow is ready to start."
    }
}

/// The Photos-library path is not reachable on tvOS, but the shared enum still has the case;
/// render a calm note with the Back affordance in case it is ever routed here.
private struct TVPhotoLibraryUnavailableStep: View {
    let viewModel: OnboardingViewModel

    var body: some View {
        TVStepScaffold(
            title: "Not available on Apple TV",
            subtitle: "Playing from a Photos library isn't supported here. Use a shared link or connect to your Immich server instead.",
            viewModel: viewModel
        ) {
            EmptyView()
        }
    }
}

// MARK: - Helpers

private func isBlank(_ value: String) -> Bool {
    value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
}
