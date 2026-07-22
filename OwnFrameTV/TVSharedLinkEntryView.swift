//
//  TVSharedLinkEntryView.swift
//  OwnFrameTV
//
//  The primary, lowest-friction tvOS setup path (US2-5): one shared-link URL, with a password
//  asked for ONLY when the link needs one (topic 210 resolve-first semantics). Driven by the
//  shared `SourceLibraryViewModel` via the composition model, so the real Immich resolution
//  and password handling are reused unchanged.
//

import OnboardingKit
import SwiftUI

struct TVSharedLinkEntryView: View {
    @Bindable var model: TVAppModel
    @State private var urlText = ""
    @State private var passwordText = ""

    private var addState: SharedLinkAddState { model.sourceLibrary.addState }
    private var isResolving: Bool { addState == .resolving }
    private var needsPassword: Bool { addState == .needsPassword }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            ScrollView {
                VStack(spacing: 40) {
                    VStack(spacing: 14) {
                        Text("Play a shared album")
                            .font(.largeTitle.weight(.semibold))
                        Text("Paste the Immich share link someone sent you. You'll only be asked for a password if the link needs one.")
                            .font(.title3)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    if needsPassword {
                        passwordEntry
                    } else {
                        linkEntry
                    }

                    if case let .error(message) = addState {
                        Text(message)
                            .font(.headline)
                            .foregroundStyle(.red)
                            .multilineTextAlignment(.center)
                            .accessibilityIdentifier("tv.sharedLink.error")
                    }

                    if model.onboarding.canGoBack {
                        Button("Back") { model.onboarding.back() }
                            .accessibilityIdentifier("tv.sharedLink.back")
                    }
                }
                .frame(maxWidth: 900)
                .padding(60)
            }
        }
    }

    @ViewBuilder
    private var linkEntry: some View {
        VStack(spacing: 28) {
            TextField("https://your-immich.example/s/…", text: $urlText)
                .textContentType(.URL)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .accessibilityIdentifier("tv.sharedLink.url")

            Button {
                Task { await model.submitSharedLink(urlText) }
            } label: {
                if isResolving { ProgressView() } else { Text("Continue") }
            }
            .disabled(urlText.isEmpty || isResolving)
            .accessibilityIdentifier("tv.sharedLink.continue")
        }
    }

    @ViewBuilder
    private var passwordEntry: some View {
        VStack(spacing: 28) {
            Text("This shared link is password-protected.")
                .font(.title3)
                .foregroundStyle(.secondary)
            SecureField("Password", text: $passwordText)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .accessibilityIdentifier("tv.sharedLink.password")
            Button {
                Task { await model.confirmSharedLinkPassword(passwordText) }
            } label: {
                if isResolving { ProgressView() } else { Text("Continue") }
            }
            .disabled(passwordText.isEmpty || isResolving)
            .accessibilityIdentifier("tv.sharedLink.password.continue")
        }
    }
}
