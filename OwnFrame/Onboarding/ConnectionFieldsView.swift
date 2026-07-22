//
//  ConnectionFieldsView.swift
//  OwnFrame
//
//  The shared server-URL + API-key fields used by every connection editor — onboarding
//  (ConnectionStepView), Settings, and the slideshow's connection-error recovery
//  (ConnectionSettingsView) — so all three look and validate identically (210, FR-210-29).
//  Section-based (lives inside a Form); the host supplies the bindings, the per-screen copy,
//  and the accessibility ids so each surface keeps its existing test contract. The stored key
//  is never shown — only an optional "key is set" indicator.
//

import SwiftUI

struct ConnectionFieldsView: View {
    @Binding var serverURL: String
    @Binding var apiKey: String
    var keyIsSet: Bool = false
    var errorMessage: String?
    var isBusy: Bool = false
    var apiKeyPlaceholder: LocalizedStringKey = "API Key"
    var serverFooter: LocalizedStringKey?
    var apiKeyFooter: LocalizedStringKey?
    let ids: IDs

    struct IDs {
        let url: String
        let apiKey: String
        let keySet: String
        let error: String
    }

    var body: some View {
        Section {
            TextField("https://immich.example.com", text: $serverURL)
                .textContentType(.URL)
                .keyboardType(.URL)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .disabled(isBusy)
                .accessibilityIdentifier(ids.url)
        } header: {
            Text("Server address")
        } footer: {
            if let serverFooter { Text(serverFooter) }
        }

        Section {
            AppSecureField(apiKeyPlaceholder, text: $apiKey)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .disabled(isBusy)
                .accessibilityIdentifier(ids.apiKey)
            if keyIsSet {
                Label("Key is set", systemImage: "key.fill")
                    .foregroundStyle(.secondary)
                    .font(.footnote)
                    .accessibilityIdentifier(ids.keySet)
            }
        } header: {
            Text("API Key")
        } footer: {
            if let apiKeyFooter { Text(apiKeyFooter) }
        }

        if let errorMessage {
            Section {
                Label(errorMessage, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.red)
                    .accessibilityIdentifier(ids.error)
            }
        }
    }
}
