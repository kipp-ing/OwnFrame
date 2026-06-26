//
//  OnboardingChoiceView.swift
//  Immich Slideshow
//
//  First-run entry (210, US1): the user picks the lowest-friction shared-link path
//  ("paste a link, no API key") or the full server path (URL + API key → album).
//  Routes the OnboardingViewModel via `choosePath`; the app shows this on `.choice`.
//

import OnboardingKit
import SwiftUI

struct OnboardingChoiceView: View {
    let viewModel: OnboardingViewModel

    var body: some View {
        List {
            Section {
                Text("Choose how to reach your photos. You can add more sources later in Settings.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("onboarding.choice.intro")
            }

            Section {
                ChoiceRow(
                    title: "Use a shared link",
                    description: "Paste an Immich share link — no account or API key needed.",
                    systemImage: "link",
                    identifier: "onboarding.choice.sharedLink"
                ) { viewModel.choosePath(.sharedLink) }

                ChoiceRow(
                    title: "Connect to a server",
                    description: "Sign in with your server address and API key to pick an album.",
                    systemImage: "externaldrive.connected.to.line.below",
                    identifier: "onboarding.choice.server"
                ) { viewModel.choosePath(.server) }
            }
        }
        .navigationTitle("Get started")
    }
}

/// A tappable onboarding option: icon + title + one-line description + a chevron.
private struct ChoiceRow: View {
    let title: String
    let description: String
    let systemImage: String
    let identifier: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 16) {
                Image(systemName: systemImage)
                    .font(.title2)
                    .foregroundStyle(.tint)
                    .frame(width: 34)
                VStack(alignment: .leading, spacing: 4) {
                    Text(title)
                        .font(.headline)
                        .foregroundStyle(.primary)
                    Text(description)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                Spacer(minLength: 8)
                Image(systemName: "chevron.forward")
                    .font(.footnote.weight(.semibold))
                    .foregroundStyle(.tertiary)
            }
            .padding(.vertical, 6)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(identifier)
    }
}
