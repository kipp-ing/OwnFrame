//
//  TVBrokerSetupView.swift
//  Immich SlideshowTV
//
//  Focus-navigable tvOS screen for configuring the Home-Assistant MQTT broker (topic
//  1000, US4). Backed by the host-tested `BrokerSetupViewModel`; credentials live only in
//  the Keychain via the injected store, and the stored password is never prefilled in
//  cleartext (the field masks itself and only a re-entry changes it).
//

import BrokerSetupKit
import SwiftUI

struct TVBrokerSetupView: View {
    @State private var vm = BrokerSetupViewModel(store: KeychainBrokerSettingsStore())
    var onDone: () -> Void = {}

    var body: some View {
        ZStack {
            Color.black.ignoresSafeArea()
            ScrollView {
                VStack(spacing: 40) {
                    VStack(spacing: 14) {
                        Text("Home Assistant (MQTT)")
                            .font(.largeTitle.weight(.semibold))
                        Text("Connect to your MQTT broker to control the slideshow from Home Assistant.")
                            .font(.title3)
                            .foregroundStyle(.secondary)
                            .multilineTextAlignment(.center)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    fields

                    if let message = vm.validationError.map(Self.message(for:)) {
                        Text(message)
                            .font(.headline)
                            .foregroundStyle(.red)
                            .multilineTextAlignment(.center)
                            .accessibilityIdentifier("tv.broker.validation")
                    }

                    actions
                }
                .frame(maxWidth: 900)
                .padding(60)
            }
        }
        .onAppear { vm.load() }
    }

    @ViewBuilder
    private var fields: some View {
        VStack(spacing: 24) {
            TextField("Host", text: $vm.host)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .accessibilityIdentifier("tv.broker.host")

            TextField("Port", text: $vm.port)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .accessibilityIdentifier("tv.broker.port")

            TextField("Username", text: $vm.username)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .accessibilityIdentifier("tv.broker.username")

            SecureField(vm.passwordIsSet ? "New password" : "Password", text: $vm.password)
                .autocorrectionDisabled()
                .textInputAutocapitalization(.never)
                .accessibilityIdentifier("tv.broker.password")

            if vm.passwordIsSet {
                Text("Password is set — re-enter to change it.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("tv.broker.passwordHint")
            }
        }
    }

    @ViewBuilder
    private var actions: some View {
        VStack(spacing: 20) {
            Button("Save") {
                // On success, reload from the store so the password masks itself again and
                // the "password is set" hint / Remove action appear.
                if vm.save() {
                    vm.load()
                    onDone()
                }
            }
            .accessibilityIdentifier("tv.broker.save")

            if vm.passwordIsSet {
                Button("Remove", role: .destructive) { vm.remove() }
                    .accessibilityIdentifier("tv.broker.remove")
            }

            Button("Done") { onDone() }
                .accessibilityIdentifier("tv.broker.done")
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
