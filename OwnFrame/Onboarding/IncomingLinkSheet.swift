//
//  IncomingLinkSheet.swift
//  OwnFrame
//
//  210, US2 — a shared link handed into the **already-configured** app (via the iOS
//  Share Sheet / the `immichslideshow://` hand-off). It resolves the link first and asks
//  for a password only when the server reports one is required, then makes the link the
//  active source so the running slideshow switches to it. Reuses the SourceLibraryViewModel
//  two-phase resolve engine (D6); `(baseURL,slug)` dedup means a link already in the
//  library simply switches to the existing source rather than adding a duplicate (D7).
//

import OnboardingKit
import SwiftUI

struct IncomingLinkSheet: View {
    @Bindable var sourceLibrary: SourceLibraryViewModel
    let url: String
    let onDone: () -> Void

    @State private var passwordText = ""
    @State private var didStart = false

    var body: some View {
        NavigationStack {
            Form {
                switch sourceLibrary.addState {
                case .idle, .resolving:
                    Section {
                        HStack {
                            ProgressView()
                            Text("Adding shared link…")
                                .padding(.leading, 8)
                        }
                        .accessibilityIdentifier("incomingLink.resolving")
                    }

                case .needsPassword:
                    passwordSection

                case .resolved:
                    // Activation + dismissal happen in `onChange`; show a brief confirmation.
                    Section {
                        Label("Switching to the shared link…", systemImage: "checkmark.circle")
                            .accessibilityIdentifier("incomingLink.resolved")
                    }

                case let .error(message):
                    Section {
                        Label(message, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.red)
                            .accessibilityIdentifier("incomingLink.error")
                    }
                    Section {
                        Button("Close") { onDone() }
                            .accessibilityIdentifier("incomingLink.close")
                    }
                }
            }
            .navigationTitle("Shared link")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        sourceLibrary.resetSharedLinkAdd()
                        onDone()
                    }
                    .accessibilityIdentifier("incomingLink.cancel")
                }
            }
        }
        .task {
            // Resolve once on first appearance. `.task` is keyed to the view identity, so a
            // re-render won't re-resolve; `didStart` guards belt-and-suspenders.
            guard !didStart else { return }
            didStart = true
            await sourceLibrary.resolveSharedLink(urlString: url, label: "")
            if case let .resolved(sourceID) = sourceLibrary.addState {
                activate(sourceID)
            }
        }
    }

    private var passwordSection: some View {
        Group {
            Section {
                AppSecureField("Password", text: $passwordText)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .accessibilityIdentifier("incomingLink.password")
            } header: {
                Text("Password required")
            } footer: {
                Text("This shared link is password-protected. Enter the password to continue.")
            }

            Section {
                Button {
                    Task {
                        await sourceLibrary.confirmSharedLinkPassword(passwordText)
                        if case let .resolved(sourceID) = sourceLibrary.addState {
                            activate(sourceID)
                        }
                    }
                } label: {
                    Text("Continue")
                }
                .disabled(passwordText.isEmpty)
                .accessibilityIdentifier("incomingLink.password.continue")
            }
        }
    }

    /// Make the resolved (or deduped existing) link the active source — this restarts the
    /// running slideshow via the `onSwitchActive` callback wired in `RootView` — then dismiss.
    private func activate(_ sourceID: String) {
        sourceLibrary.setActive(id: sourceID)
        onDone()
    }
}
