//
//  SharedLinkAddForm.swift
//  Immich Slideshow
//
//  Shared "add a shared link" form (210, US4) embedded inside a parent `Form`. It renders
//  the link URL + optional name fields and an Add button, then drives the
//  SourceLibraryViewModel's two-phase resolve: the link is resolved first and a password
//  is asked for **only** when the server reports one is required (ask-password-when-needed).
//  On success it clears its fields and calls `onResolved` (e.g. dismiss the add sheet);
//  resolve/password errors are shown inline. Used by both the onboarding source step and
//  Settings → Sources, parameterized by an accessibility-id prefix and the Add button's id
//  suffix so each surface keeps its existing identifiers.
//

import OnboardingKit
import SwiftUI

struct SharedLinkAddForm: View {
    @Bindable var sourceLibrary: SourceLibraryViewModel
    /// Accessibility-id prefix, e.g. `onboarding.sharedLink` or `sources.add`.
    let idPrefix: String
    /// The Add button's id suffix (`add` in onboarding, `submit` in Settings).
    let submitIDSuffix: String
    /// Extra side effect on a successful add (the form clears its own fields first).
    var onResolved: () -> Void = {}

    @State private var urlText = ""
    @State private var labelText = ""
    @State private var passwordText = ""
    @State private var showPasswordPrompt = false

    var body: some View {
        Section {
            TextField("https://host/s/slug", text: $urlText)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .keyboardType(.URL)
                .disabled(isResolving)
                .accessibilityIdentifier("\(idPrefix).url")
                // Anchor presentation/lifecycle on this always-present leaf — modifiers on a
                // `Section` are dropped by Form/List, so the password sheet must hang here.
                .onAppear { sourceLibrary.resetSharedLinkAdd() }
                .sheet(isPresented: $showPasswordPrompt, onDismiss: { passwordText = "" }) {
                    passwordPrompt
                }
            TextField("Name (optional)", text: $labelText)
                .disabled(isResolving)
                .accessibilityIdentifier("\(idPrefix).label")
        } header: {
            Text("Shared link")
        } footer: {
            footer
        }

        if !showPasswordPrompt, case let .error(message) = sourceLibrary.addState {
            Section {
                Label(message, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.red)
                    .accessibilityIdentifier("\(idPrefix).error")
            }
        }
    }

    @ViewBuilder
    private var footer: some View {
        if isResolving {
            ProgressView()
        } else {
            Button("Add") { submit() }
                .disabled(urlText.trimmingCharacters(in: .whitespaces).isEmpty)
                .accessibilityIdentifier("\(idPrefix).\(submitIDSuffix)")
        }
    }

    private var isResolving: Bool {
        if case .resolving = sourceLibrary.addState { return true }
        return false
    }

    /// Phase 1: resolve the pasted link. `.needsPassword` opens the prompt; `.resolved`
    /// adds the source and clears the form; `.error` is shown inline.
    private func submit() {
        Task {
            await sourceLibrary.resolveSharedLink(urlString: urlText, label: labelText)
            switch sourceLibrary.addState {
            case .needsPassword:
                showPasswordPrompt = true
            case .resolved:
                finishAdd()
            default:
                break
            }
        }
    }

    /// Phase 2: confirm a password for a protected link. Success dismisses the prompt and
    /// adds the source; a wrong password keeps the prompt open with the error shown.
    private func confirmPassword() {
        Task {
            await sourceLibrary.confirmSharedLinkPassword(passwordText)
            if case .resolved = sourceLibrary.addState {
                showPasswordPrompt = false
                finishAdd()
            }
        }
    }

    private func finishAdd() {
        urlText = ""
        labelText = ""
        passwordText = ""
        sourceLibrary.resetSharedLinkAdd()
        onResolved()
    }

    private var passwordPrompt: some View {
        NavigationStack {
            Form {
                Section {
                    SecureField("Password", text: $passwordText)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .disabled(isResolving)
                        .accessibilityIdentifier("\(idPrefix).password")
                } header: {
                    Text("Password required")
                } footer: {
                    Text("This shared link is password-protected. Enter the password to continue.")
                }

                if case let .error(message) = sourceLibrary.addState {
                    Section {
                        Label(message, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.red)
                            .accessibilityIdentifier("\(idPrefix).password.error")
                    }
                }

                Section {
                    Button {
                        confirmPassword()
                    } label: {
                        HStack {
                            Text("Continue")
                            if isResolving {
                                Spacer()
                                ProgressView()
                            }
                        }
                    }
                    .disabled(passwordText.isEmpty || isResolving)
                    .accessibilityIdentifier("\(idPrefix).password.continue")
                }
            }
            .navigationTitle("Password")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        showPasswordPrompt = false
                        sourceLibrary.resetSharedLinkAdd()
                    }
                    .accessibilityIdentifier("\(idPrefix).password.cancel")
                }
            }
        }
        .presentationDetents([.medium])
    }
}
