//
//  ConnectionStepView.swift
//  Immich Slideshow
//
//  Step 1 (merged): enter the server URL and API key on one screen. A single
//  Continue validates reachability AND authorization in one action (010), then
//  advances to the add-source step (album or shared link, 120).
//

import OnboardingKit
import SwiftUI

struct ConnectionStepView: View {
    @Bindable var viewModel: OnboardingViewModel

    var body: some View {
        Form {
            Section {
                Text("Connect to your Immich server with its address and an API key to browse and pick albums.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("onboarding.connection.description")
            }

            ConnectionFieldsView(
                serverURL: $viewModel.serverURLInput,
                apiKey: $viewModel.apiKeyInput,
                errorMessage: viewModel.errorMessage,
                isBusy: viewModel.isBusy,
                serverFooter: "Address of your Immich instance. Only HTTPS is supported.",
                apiKeyFooter: "Create one in Immich under Account Settings → API Keys.",
                ids: .init(
                    url: "onboarding.serverURL",
                    apiKey: "onboarding.apiKey",
                    keySet: "onboarding.connection.keySet",
                    error: "onboarding.connection.error"
                )
            )

            Section {
                Button {
                    Task { await viewModel.submitConnection() }
                } label: {
                    HStack {
                        Text("Continue")
                        if viewModel.isBusy {
                            Spacer()
                            ProgressView()
                        }
                    }
                }
                .disabled(isContinueDisabled)
                .accessibilityIdentifier("onboarding.connection.continue")
            }
        }
    }

    // Both values are required before a single connection can be validated (FR-005).
    private var isContinueDisabled: Bool {
        viewModel.isBusy
            || viewModel.serverURLInput.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            || viewModel.apiKeyInput.isEmpty
    }
}
