//
//  TVSettingsView.swift
//  OwnFrameTV
//
//  1100 (T033) — the tvOS unlock surface. The Apple TV frame's settings screen, reached from the
//  slideshow chrome's gear. It mirrors the iOS Unlocks section + locked-row treatment
//  (`SlideshowSettingsView`) with tvOS focus-engine-native controls, and it is the native
//  purchase + restore surface that universal purchase requires on tvOS (US4 scenario 3,
//  FR-1100-07).
//
//  Everything here is entitlement-gated at its point of effect, fail-closed: an absent
//  `EntitlementStore` reads as unentitled. PurchaseKit's `UnlockScreenView` / `TipJarView` /
//  `LockedRow` are already tvOS-ready and are reused verbatim. Presentation is via
//  `fullScreenCover` — tvOS has no sheet or swipe-to-dismiss — and each presented screen carries
//  its own Close button. This view never auto-presents purchase UI: every unlock screen opens from
//  a control the user clicked (SC-1100-02).
//

import BrokerSetupKit
import PurchaseKit
import SwiftUI

struct TVSettingsView: View {
    /// Optional + fail-closed, exactly like the iOS gates and `UnlockScreenView`: a wiring mistake
    /// degrades to "unentitled", never a crash on a paying user's TV.
    @Environment(EntitlementStore.self) private var entitlements: EntitlementStore?

    var onDone: () -> Void = {}

    // Only one cover is ever up at a time.
    @State private var unlockTier: Entitlement?
    @State private var showTipJar = false
    @State private var showBrokerSetup = false
    @State private var isRestoring = false

    /// One unlock now grants every gated capability, so ambience and remote control read the
    /// same entitlement. Fail-closed: an absent store reads as unentitled.
    private var isUnlocked: Bool { entitlements?.current.contains(.supporter) ?? false }

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            ScrollView {
                VStack(alignment: .leading, spacing: 44) {
                    Text("Settings")
                        .font(.largeTitle.weight(.semibold))

                    ambienceRow
                    homeAssistantRow
                    unlocksSection

                    Button("Done", action: onDone)
                        .accessibilityIdentifier("tv.settings.done")
                }
                .frame(maxWidth: 900, alignment: .leading)
                .padding(60)
            }
        }
        .fullScreenCover(item: $unlockTier) { tier in
            UnlockScreenView(tier: tier) { unlockTier = nil }
        }
        .fullScreenCover(isPresented: $showTipJar) {
            TipJarView { showTipJar = false }
        }
        .fullScreenCover(isPresented: $showBrokerSetup) {
            TVBrokerSetupView(onDone: { showBrokerSetup = false })
        }
        #if DEBUG
        // Screenshot/verification seam (DEBUG only): auto-open a sub-screen so XcodeBuildMCP can
        // capture it without tvOS navigation tools. `--uitest-tv-present=<unlock-supporter|tip|
        // broker-setup>`.
        .onAppear {
            guard let arg = ProcessInfo.processInfo.arguments
                .first(where: { $0.hasPrefix("--uitest-tv-present=") })?
                .dropFirst("--uitest-tv-present=".count)
            else { return }
            switch arg {
            case "unlock-supporter": unlockTier = .supporter
            case "tip": showTipJar = true
            case "broker-setup": showBrokerSetup = true
            default: break
            }
        }
        #endif
    }

    // MARK: - Ambience

    @ViewBuilder
    private var ambienceRow: some View {
        if isUnlocked {
            // Owned: nothing to configure on tvOS (Ken Burns just plays; there is no tvOS clock
            // yet — a known 1000 leftover). Confirm it, so an all-unlocked frame shows no locked
            // rows at all (mirrors the iOS "no locked rows when everything is unlocked" check).
            Label("Ambience — Ken Burns motion is on", systemImage: "checkmark.seal")
                .font(.title3)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("tv.settings.row.pro.unlocked")
        } else {
            LockedRow(requires: .supporter, identifier: "settings.row.kenburns.locked") {
                unlockTier = .supporter
            } content: {
                Label {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Ambience — Ken Burns motion").font(.title3.weight(.medium))
                        Text("Photos drift and scale slowly instead of sitting still.")
                            .font(.callout).foregroundStyle(.secondary)
                    }
                } icon: {
                    Image(systemName: "camera.viewfinder")
                }
            }
        }
    }

    // MARK: - Home Assistant

    @ViewBuilder
    private var homeAssistantRow: some View {
        // 1100 (amended 2026-07-20): telemetry is free (FR-1100-03a). The broker setup is
        // available to everyone so a free Apple TV frame can report its status to Home Assistant.
        // Only *control* needs the Supporter Unlock — when unentitled a control-locked banner above
        // the setup row opens the unlock screen directly; buying it adds control with zero
        // re-entry (FR-1100-14).
        if !isUnlocked {
            LockedRow(requires: .supporter, identifier: "settings.row.broker.locked") {
                unlockTier = .supporter
            } content: {
                Label {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Remote control").font(.title3.weight(.medium))
                        Text("Let Home Assistant and Shortcuts drive the frame.")
                            .font(.callout).foregroundStyle(.secondary)
                    }
                } icon: {
                    Image(systemName: "slider.horizontal.3")
                }
            }
        }
        Button { showBrokerSetup = true } label: {
            Label {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Home Assistant (MQTT)").font(.title3.weight(.medium))
                    if !isUnlocked {
                        Text("Connect a broker so Home Assistant can see this frame.")
                            .font(.callout).foregroundStyle(.secondary)
                    }
                }
            } icon: {
                Image(systemName: "house")
            }
        }
        .accessibilityIdentifier("tv.settings.row.broker")
    }

    // MARK: - Unlocks (Restore + Tip)

    private var unlocksSection: some View {
        VStack(alignment: .leading, spacing: 20) {
            Text("Unlocks")
                .font(.title2.weight(.semibold))
                .accessibilityIdentifier("settings.section.unlocks")

            // Always present so a re-installed or second frame can recover purchases without
            // hunting (FR-1100-11).
            Button {
                guard !isRestoring else { return }
                isRestoring = true
                Task {
                    try? await entitlements?.restore()
                    isRestoring = false
                }
            } label: {
                HStack {
                    Label("Restore Purchases", systemImage: "arrow.clockwise")
                    if isRestoring {
                        Spacer()
                        ProgressView()
                    }
                }
            }
            .disabled(isRestoring)
            .accessibilityIdentifier("unlock.restore")

            // The tip jar lives here and ONLY here — never solicited from playback or onboarding
            // (US6).
            Button { showTipJar = true } label: {
                Label("Leave a Tip", systemImage: "heart")
            }
            .accessibilityIdentifier("settings.tipjar")

            Text("Restore purchases you already own. Tips are optional and unlock nothing — they just say thanks.")
                .font(.callout)
                .foregroundStyle(.secondary)

            // Transparency statement (docs/where-the-money-goes.md) — calm, never a nag (FR-1100-09).
            Text("Where your money goes: the Supporter Unlock covers the project's running costs — developer account, AI tools, test hardware — and everything beyond that goes back to open-source projects that serve the community. The free frame stays whole, forever.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("settings.unlocks.moneyPledge")
        }
    }
}

// (US5 amended 2026-07-20) The old `TVLockedBrokerView` masked-config screen is gone: telemetry
// is free, so an unentitled Apple TV frame publishes read-only sensors and its broker setup is
// reachable live. Only *control* is gated, surfaced by the "Remote control" locked banner in
// `homeAssistantRow`, which opens the Supporter Unlock screen directly.
