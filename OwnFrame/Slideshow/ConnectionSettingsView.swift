//
//  ConnectionSettingsView.swift
//  OwnFrame
//
//  In-app editor for the Immich connection (server URL + API key), reachable from
//  the settings screen and from the slideshow's connection-error state (009).
//  Validates (reachable + authorized) before persisting; the stored API key is
//  never shown — only a "key is set" indicator — and an empty key field keeps the
//  existing key (Constitution III). On a successful save the app reconnects the
//  running slideshow without re-onboarding.
//

import OnboardingKit
import SwiftUI

struct ConnectionSettingsView: View {
    @Bindable var viewModel: ConnectionSettingsViewModel
    /// Shown when presented as a sheet (error recovery); hidden when pushed from Settings,
    /// where the navigation back button already dismisses (210, FR-210-29).
    var showsCancelButton: Bool = true
    var onSaved: (ConnectionValidationOutcome) -> Void = { _ in }

    @Environment(\.dismiss) private var dismiss

    var body: some View {
        Form {
            ConnectionFieldsView(
                serverURL: $viewModel.serverURLInput,
                apiKey: $viewModel.apiKeyInput,
                keyIsSet: viewModel.keyIsSet,
                errorMessage: viewModel.errorMessage,
                isBusy: viewModel.isBusy,
                apiKeyPlaceholder: "New API Key",
                apiKeyFooter: "Leave empty to keep the saved key.",
                ids: .init(
                    url: "connection.url",
                    apiKey: "connection.apiKey",
                    keySet: "connection.keySet",
                    error: "connection.error"
                )
            )
        }
        .navigationTitle("Connection")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            if showsCancelButton {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                        .disabled(viewModel.isBusy)
                }
            }
            ToolbarItem(placement: .confirmationAction) {
                if viewModel.isBusy {
                    ProgressView()
                } else {
                    Button("Save", action: save)
                        .disabled(isSaveDisabled)
                        .accessibilityIdentifier("connection.save")
                }
            }
        }
    }

    private var isSaveDisabled: Bool {
        viewModel.serverURLInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func save() {
        Task {
            let outcome = await viewModel.save()
            switch outcome {
            case .success, .albumMissing:
                onSaved(outcome)
                dismiss()
            default:
                // A failure leaves the prior connection intact; the inline error is
                // shown and the editor stays open so the user can correct it.
                break
            }
        }
    }
}
