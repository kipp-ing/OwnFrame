//
//  BrokerSetupView.swift
//  Immich Slideshow
//
//  Inline MQTT/broker editor rendered inside the Settings screen's collapsible
//  "MQTT" section (010 — folded in from the old standalone sheet). Backed by the
//  host-tested BrokerSetupViewModel, which the settings screen owns in its own
//  @State so collapsing/re-expanding the section keeps typed-but-unsaved edits.
//  Credentials live only in the Keychain via the injected store, and the stored
//  password is never prefilled in cleartext (FR-013).
//

import BrokerSetupKit
import Foundation
import HAControlKit
import SwiftUI

struct BrokerSettingsSection: View {
    @Bindable var viewModel: BrokerSetupViewModel
    let publishOptions: any HAPublishOptionsStore
    @State private var imageEnabled: Bool
    @State private var byteCapKB: Double

    init(viewModel: BrokerSetupViewModel, publishOptions: any HAPublishOptionsStore) {
        self._viewModel = Bindable(viewModel)
        self.publishOptions = publishOptions
        self._imageEnabled = State(initialValue: publishOptions.options.imageEnabled)
        self._byteCapKB = State(initialValue: (Double(publishOptions.options.byteCap) / 1000).rounded())
    }

    var body: some View {
        Group {
            TextField("Host", text: $viewModel.host)
                .textInputAutocapitalization(.never)
                .keyboardType(.URL)
                .autocorrectionDisabled()
                .accessibilityIdentifier("broker.host")

            TextField("Port", text: $viewModel.port)
                .keyboardType(.numberPad)
                .accessibilityIdentifier("broker.port")

            TextField("Username", text: $viewModel.username)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .accessibilityIdentifier("broker.username")

            AppSecureField(viewModel.passwordIsSet ? "New password" : "Password", text: $viewModel.password)
                .accessibilityIdentifier("broker.password")

            if viewModel.passwordIsSet {
                Text("Password is set — re-enter to change it.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("broker.passwordHint")
            }

            if let message = viewModel.validationError.map(Self.message(for:)) {
                Text(message)
                    .foregroundStyle(.red)
                    .accessibilityIdentifier("broker.validation")
            }

            Button("Save") {
                // On success, reload from the store so the password masks itself again
                // and the "password is set" hint / remove action appear (FR-013).
                if viewModel.save() { viewModel.load() }
            }
            .accessibilityIdentifier("broker.save")

            if viewModel.passwordIsSet {
                Button("Remove", role: .destructive) { viewModel.remove() }
                    .accessibilityIdentifier("broker.remove")
            }

            // Photo image publishing is off by default (FR-710-15): metadata always
            // flows, but the image bytes only when the user opts in here.
            Toggle("Publish photo image to Home Assistant", isOn: $imageEnabled)
                .accessibilityIdentifier("broker.imageEnabled")
                .onChange(of: imageEnabled) { _, newValue in
                    publishOptions.options.imageEnabled = newValue
                }

            // FR-900-12: the opt-in is global — say plainly that it also covers photos
            // from the device library, which otherwise never leave the device (FR-900-14).
            Text("Applies to every source — Immich albums, shared links, and albums from "
                 + "your Photos library.")
                .font(.footnote)
                .foregroundStyle(.secondary)
                .accessibilityIdentifier("broker.imagePublishScope")

            if imageEnabled {
                Stepper("Max image size: \(Int(byteCapKB)) KB", value: $byteCapKB, in: 100...2000, step: 100)
                    .accessibilityIdentifier("broker.byteCap")
                    .onChange(of: byteCapKB) { _, newValue in
                        publishOptions.options.byteCap = Int(newValue * 1000)
                    }

                Text("Larger images may exceed the broker's packet limit and be skipped.")
                    .font(.footnote)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("broker.byteCapHint")
            }
        }
    }

    private nonisolated static func message(for error: BrokerValidationError) -> String {
        switch error {
        case .emptyHost:
            "Please enter a broker host."
        case .invalidPort:
            "Please enter a port between 1 and 65535."
        case .emptyUsername:
            "Please enter a username."
        case .emptyPassword:
            "Please enter a password."
        }
    }
}

/// The broker configuration as an unentitled frame sees it (1100, US5 / FR-1100-14).
///
/// Pre-gate frames — Jan's own, and any internal build that had HA configured before the gate —
/// keep their broker settings after the update. This surface exists so the owner can *see* that
/// their configuration survived: the stored host/port/username are shown, the password state is
/// shown masked exactly as the live editor masks it, and a locked banner explains the tier and
/// offers the unlock. It is strictly read-only — no field is editable, nothing connects, and
/// nothing is cleared or migrated. Purchasing Automation swaps this for the live editor with every
/// value already in place (zero re-entry, FR-1100-14).
///
/// It reads only the broker view model the settings screen already owns; it never reaches into
/// PurchaseKit, and PurchaseKit never reaches into it — the entitlement is passed in as a plain
/// callback so this app-target view owns the (app-target) broker data and the (PurchaseKit) unlock
/// screen stays free of any broker/keychain coupling.
struct LockedBrokerView: View {
    let viewModel: BrokerSetupViewModel
    /// Presents the Automation unlock screen. Owned by the caller so this view stays PurchaseKit-free.
    let onUnlock: () -> Void
    let onClose: () -> Void

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    // The same lock/tier treatment as the settings rows, as a banner. Tapping it
                    // is the unlock entry point (US1 seam) — hittable, never disabled.
                    Button(action: onUnlock) {
                        HStack(spacing: 12) {
                            Image(systemName: "lock.fill")
                            VStack(alignment: .leading, spacing: 2) {
                                Text("Remote control needs the Automation unlock")
                                    .font(.headline)
                                Text("Your Home Assistant setup is saved and resumes the moment you unlock — nothing to re-enter.")
                                    .font(.footnote)
                                    .foregroundStyle(.secondary)
                            }
                        }
                    }
                    .accessibilityIdentifier("settings.row.broker.locked")
                }

                // The stored configuration, visible and masked exactly as the live editor shows
                // it — "not an empty or reset screen" (US5 scenario 2). Read-only: no bindings,
                // no Save/Remove, no connect. The identifier sits on the VALUE Text (as the
                // Storage rows do) so an XCUITest reads the stored value as the element's label.
                Section("Saved configuration") {
                    savedRow("Host", viewModel.host.isEmpty ? "—" : viewModel.host, id: "broker.host")
                    savedRow("Port", viewModel.port, id: "broker.port")
                    savedRow("Username", viewModel.username.isEmpty ? "—" : viewModel.username, id: "broker.username")
                    savedRow("Password", viewModel.passwordIsSet ? "••••••••" : "Not set", id: "broker.password")
                }

                Section {
                    Button("Unlock Automation", action: onUnlock)
                        .accessibilityIdentifier("unlock.buy.automation.entry")
                }
            }
            .navigationTitle("Home Assistant")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done", action: onClose)
                }
            }
            .task { viewModel.load() }   // reflect the stored values; load() never writes.
        }
    }

    /// A read-only "label … value" row. The row is a single combined accessibility element whose
    /// label carries BOTH the field name and the stored value, so an XCUITest lookup by
    /// identifier reads the value off `.label` unambiguously (Form rows otherwise merge their
    /// children and the value can go missing from a child Text's own element).
    @ViewBuilder
    private func savedRow(_ label: String, _ value: String, id: String) -> some View {
        HStack {
            Text(label)
            Spacer()
            Text(value)
                .foregroundStyle(.secondary)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label): \(value)")
        .accessibilityIdentifier(id)
    }
}

/// Selects the broker settings store: an in-memory store under `--uitest` so the
/// hermetic flow never touches the real Keychain, the Keychain store in production.
enum BrokerSettingsStoreFactory {
    static func make() -> any BrokerSettingsStore {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--uitest") {
            return BrokerSetupUITestStore.shared
        }
        #endif
        return KeychainBrokerSettingsStore()
    }
}

/// Selects the HA publish-options store. Under `--uitest` it uses a dedicated,
/// persistent UserDefaults suite (so a toggle survives relaunch) that
/// `--uitest-reset-publish-options` clears for a deterministic start; production
/// uses the standard defaults (no secrets — just booleans and a byte cap).
enum HAPublishOptionsStoreFactory {
    static func make() -> any HAPublishOptionsStore {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--uitest") {
            let suite = "uitest.haPublish"
            let defaults = UserDefaults(suiteName: suite) ?? .standard
            if ProcessInfo.processInfo.arguments.contains("--uitest-reset-publish-options") {
                defaults.removePersistentDomain(forName: suite)
            }
            return UserDefaultsHAPublishOptionsStore(defaults: defaults)
        }
        #endif
        return UserDefaultsHAPublishOptionsStore()
    }
}

#if DEBUG
/// In-memory broker store for hermetic XCUITests (`--uitest`). Seeded with a
/// representative broker when `--uitest-broker-existing` is passed, so the change /
/// remove (US2) flow is testable without the real Keychain. Never built into Release.
final class BrokerSetupUITestStore: BrokerSettingsStore, @unchecked Sendable {
    static let shared = BrokerSetupUITestStore()

    private let lock = NSLock()
    private var stored: BrokerSettings?

    init() {
        if ProcessInfo.processInfo.arguments.contains("--uitest-broker-existing") {
            stored = BrokerSettings(
                host: "mqtt.example.com",
                port: 8883,
                username: "ha-user",
                password: "secret-pass"
            )
        }
    }

    func save(_ settings: BrokerSettings) throws {
        if let error = settings.validate() { throw error }
        lock.withLock { stored = settings }
    }

    func load() -> BrokerSettings? { lock.withLock { stored } }

    func clear() { lock.withLock { stored = nil } }
}
#endif
