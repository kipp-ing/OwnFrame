//
//  OnboardingFlowView.swift
//  Immich Slideshow
//
//  First-run setup: server URL + API key -> add a source (album or shared link) ->
//  confirm -> slideshow. Drives the OnboardingViewModel; the source/confirm steps also
//  bind a SourceLibraryViewModel that writes the persisted library shared with the app.
//  Routing to the main screen happens at the app level once step == .done.
//

import OnboardingKit
import SwiftUI

struct OnboardingFlowView: View {
    let viewModel: OnboardingViewModel
    @State private var sourceLibrary: SourceLibraryViewModel
    /// A shared link handed in while the app is still unconfigured (210, US2):
    /// pre-fills the shared-link setup field.
    let sharedLinkPrefill: String

    init(
        viewModel: OnboardingViewModel,
        sharedLinkPrefill: String = "",
        makeSourceLibrary: () -> SourceLibraryViewModel
    ) {
        self.viewModel = viewModel
        self.sharedLinkPrefill = sharedLinkPrefill
        _sourceLibrary = State(initialValue: makeSourceLibrary())
    }

    var body: some View {
        NavigationStack {
            Group {
                switch viewModel.step {
                case .choice:
                    OnboardingChoiceView(viewModel: viewModel)
                case .sharedLinkSetup:
                    SharedLinkSetupView(onboarding: viewModel, sourceLibrary: sourceLibrary, prefill: sharedLinkPrefill)
                case .connection:
                    ConnectionStepView(viewModel: viewModel)
                case .source:
                    SourceStepView(onboarding: viewModel, sourceLibrary: sourceLibrary)
                case .confirm:
                    OnboardingConfirmStepView(onboarding: viewModel, sourceLibrary: sourceLibrary)
                case .done:
                    // Routing to the main screen happens at the app level.
                    EmptyView()
                }
            }
            .navigationTitle("Setup")
            .navigationBarTitleDisplayMode(.inline)
            // Steps swap the NavigationStack root (no push), so there is no system back button;
            // provide our own Back to the previous step for every step after .choice (210, FR-210-26).
            .toolbar {
                if viewModel.canGoBack {
                    ToolbarItem(placement: .topBarLeading) {
                        Button {
                            viewModel.back()
                        } label: {
                            Label("Back", systemImage: "chevron.backward")
                        }
                        .accessibilityIdentifier("onboarding.back")
                    }
                }
            }
        }
    }
}
