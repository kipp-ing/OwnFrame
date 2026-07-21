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
    let frameNames: any FrameNameStore
    @State private var imageEnabled: Bool
    @State private var byteCapKB: Double
    // 700 / FR-700-22. Local edit buffer committed on change, so typing never round-trips
    // through the store's blank-means-default normalisation mid-word.
    @State private var frameName: String

    init(
        viewModel: BrokerSetupViewModel,
        publishOptions: any HAPublishOptionsStore,
        frameNames: any FrameNameStore
    ) {
        self._viewModel = Bindable(viewModel)
        self.publishOptions = publishOptions
        self.frameNames = frameNames
        self._imageEnabled = State(initialValue: publishOptions.options.imageEnabled)
        self._byteCapKB = State(initialValue: (Double(publishOptions.options.byteCap) / 1000).rounded())
        self._frameName = State(initialValue: frameNames.name)
    }

    var body: some View {
        Group {
            // Display name only (FR-700-22). Renaming is deliberately safe: Home Assistant
            // anchors on `unique_id`, which comes from the frame's identity and never from this
            // field, so a rename cannot orphan an entity.
            TextField("Frame name", text: $frameName)
                .autocorrectionDisabled()
                .accessibilityIdentifier("frame.name")
                .onChange(of: frameName) { _, newValue in
                    frameNames.name = newValue
                }

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

/// The frame's Home Assistant display name (700 / FR-700-22). Same shape as the publish-options
/// factory: a hermetic suite under `--uitest` so a rename in one test cannot leak into the next,
/// the standard defaults in production. Not a secret and not an identity — purely cosmetic.
enum FrameNameStoreFactory {
    static func make() -> any FrameNameStore {
        #if DEBUG
        if ProcessInfo.processInfo.arguments.contains("--uitest") {
            let suite = "uitest.frameName"
            let defaults = UserDefaults(suiteName: suite) ?? .standard
            if ProcessInfo.processInfo.arguments.contains("--uitest-reset-publish-options") {
                defaults.removePersistentDomain(forName: suite)
            }
            return UserDefaultsFrameNameStore(defaults: defaults, defaultName: "Photo Frame")
        }
        #endif
        return UserDefaultsFrameNameStore(defaultName: "Photo Frame")
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
