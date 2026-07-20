//
//  TVSettingsView.swift
//  Immich SlideshowTV
//
//  1100 (T033) — the tvOS unlock surface. The Apple TV frame's settings screen, reached from the
//  slideshow chrome's gear. It mirrors the iOS Unlocks section + locked-row treatment
//  (`SlideshowSettingsView` / `LockedBrokerView`) with tvOS focus-engine-native controls, and it
//  is the native purchase + restore surface that universal purchase requires on tvOS
//  (US4 scenario 3, FR-1100-07).
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

    // Only one cover is ever up at a time. Handing off from the locked-broker cover to the unlock
    // screen is a close-then-present: `onUnlock` clears `showLockedBroker` and sets `unlockTier`.
    @State private var unlockTier: Entitlement?
    @State private var showTipJar = false
    @State private var showBrokerSetup = false
    @State private var showLockedBroker = false
    @State private var isRestoring = false

    private var isProEntitled: Bool { entitlements?.current.contains(.pro) ?? false }
    private var isAutomationEntitled: Bool { entitlements?.current.contains(.automation) ?? false }

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
        .fullScreenCover(isPresented: $showLockedBroker) {
            TVLockedBrokerView(
                onUnlock: { showLockedBroker = false; unlockTier = .automation },
                onClose: { showLockedBroker = false }
            )
        }
        #if DEBUG
        // Screenshot/verification seam (DEBUG only): auto-open a sub-screen so XcodeBuildMCP can
        // capture it without tvOS navigation tools. `--uitest-tv-present=<unlock-pro|
        // unlock-automation|tip|locked-broker>`.
        .onAppear {
            guard let arg = ProcessInfo.processInfo.arguments
                .first(where: { $0.hasPrefix("--uitest-tv-present=") })?
                .dropFirst("--uitest-tv-present=".count)
            else { return }
            switch arg {
            case "unlock-pro": unlockTier = .pro
            case "unlock-automation": unlockTier = .automation
            case "tip": showTipJar = true
            case "locked-broker": showLockedBroker = true
            default: break
            }
        }
        #endif
    }

    // MARK: - Ambience (Pro)

    @ViewBuilder
    private var ambienceRow: some View {
        if isProEntitled {
            // Owned: nothing to configure on tvOS (Ken Burns just plays; there is no tvOS clock
            // yet — a known 1000 leftover). Confirm it, so an all-unlocked frame shows no locked
            // rows at all (mirrors the iOS "no locked rows when everything is unlocked" check).
            Label("Ambience — Ken Burns motion is on", systemImage: "checkmark.seal")
                .font(.title3)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("tv.settings.row.pro.unlocked")
        } else {
            LockedRow(requires: .pro, identifier: "settings.row.kenburns.locked") {
                unlockTier = .pro
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

    // MARK: - Home Assistant (Automation)

    @ViewBuilder
    private var homeAssistantRow: some View {
        if isAutomationEntitled {
            Button { showBrokerSetup = true } label: {
                Label {
                    Text("Home Assistant (MQTT)").font(.title3.weight(.medium))
                } icon: {
                    Image(systemName: "house")
                }
            }
            .accessibilityIdentifier("tv.settings.row.broker")
        } else {
            // The row stays a LockedRow (US1 discovery); tapping it opens the masked, never-reset
            // broker view — NOT the unlock screen directly — so the stored config stays visible
            // (US5) and PurchaseKit still never reads broker data (FR-1100-14).
            LockedRow(requires: .automation, identifier: "settings.row.broker.locked") {
                showLockedBroker = true
            } content: {
                Label {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Home Assistant (MQTT)").font(.title3.weight(.medium))
                        Text("Control the frame from Home Assistant over MQTT.")
                            .font(.callout).foregroundStyle(.secondary)
                    }
                } icon: {
                    Image(systemName: "house")
                }
            }
        }
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

            Text("Restore purchases you already own. Tips are optional and unlock nothing — "
                 + "they just say thanks.")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
    }
}

/// The tvOS equivalent of the iOS `LockedBrokerView` (US5): an unentitled Apple TV frame that
/// already has a saved broker config sees it — visible and masked, never reset — behind a locked
/// banner, with the Automation unlock one click away. tvOS-native layout (no `NavigationStack` /
/// navigation-bar APIs, which don't exist on tvOS).
///
/// It reads the broker view model only; it never reaches into PurchaseKit (the unlock is a plain
/// callback), so the (app-target) broker/keychain data and the (PurchaseKit) unlock screen stay
/// decoupled exactly as on iOS — PurchaseKit never reads broker config (FR-1100-14).
struct TVLockedBrokerView: View {
    @State private var vm = BrokerSetupViewModel(store: KeychainBrokerSettingsStore())
    let onUnlock: () -> Void
    let onClose: () -> Void

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            ScrollView {
                VStack(spacing: 40) {
                    Text("Home Assistant")
                        .font(.largeTitle.weight(.semibold))

                    // The same lock/tier treatment as the settings row, as a banner. Focusable and
                    // clickable — the unlock entry point, never disabled.
                    Button(action: onUnlock) {
                        HStack(spacing: 16) {
                            Image(systemName: "lock.fill")
                            VStack(alignment: .leading, spacing: 4) {
                                Text("Remote control needs the Automation unlock")
                                    .font(.title3.weight(.semibold))
                                Text("Your Home Assistant setup is saved and resumes the moment "
                                     + "you unlock — nothing to re-enter.")
                                    .font(.callout)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .accessibilityIdentifier("settings.row.broker.locked")

                    // The stored configuration, visible and masked exactly as the live editor
                    // shows it — "not an empty or reset screen" (US5 scenario 2). Read-only.
                    VStack(spacing: 16) {
                        Text("Saved configuration")
                            .font(.title3.weight(.semibold))
                            .frame(maxWidth: .infinity, alignment: .leading)
                        savedRow("Host", vm.host.isEmpty ? "—" : vm.host, id: "broker.host")
                        savedRow("Port", vm.port, id: "broker.port")
                        savedRow("Username", vm.username.isEmpty ? "—" : vm.username, id: "broker.username")
                        savedRow("Password", vm.passwordIsSet ? "••••••••" : "Not set", id: "broker.password")
                    }

                    Button("Unlock Automation", action: onUnlock)
                        .accessibilityIdentifier("unlock.buy.automation.entry")

                    Button("Done", action: onClose)
                        .accessibilityIdentifier("tv.broker.locked.done")
                }
                .frame(maxWidth: 900)
                .padding(60)
            }
        }
        .onAppear { vm.load() }   // reflect the stored values; load() never writes.
    }

    /// A read-only "label … value" row whose combined label carries both the field name and the
    /// stored value, so a device-day check (or a future TV test) reads the value off `.label`.
    private func savedRow(_ label: String, _ value: String, id: String) -> some View {
        HStack {
            Text(label)
            Spacer()
            Text(value).foregroundStyle(.secondary)
        }
        .font(.title3)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label): \(value)")
        .accessibilityIdentifier(id)
    }
}
