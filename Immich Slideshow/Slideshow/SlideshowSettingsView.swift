//
//  SlideshowSettingsView.swift
//  Immich Slideshow
//
//  Settings shell reached from the chrome. Brightness is live (PowerManager / 004)
//  and the display options bind the ThemeSettings store (008). Connection (009) and
//  MQTT/broker (006) are folded in here as collapsed-by-default disclosure sections
//  (010) — the calm default stays brightness + display, with the advanced config
//  tucked away until opened.
//

import BrokerSetupKit
import ImmichClient
import OnboardingKit
import PowerKit
import SwiftUI
import ThemeKit
import UIKit

struct SlideshowSettingsView: View {
    let powerManager: PowerManager
    // The shared display-preferences store, bound live by the display-option rows (008).
    @Bindable var themeStore: UserDefaultsThemeStore
    // Connection editor seams (009): the editor view model and a callback so a saved
    // change reconnects the running slideshow without re-onboarding.
    var makeConnectionViewModel: () -> ConnectionSettingsViewModel? = { nil }
    var onConnectionChanged: (ConnectionValidationOutcome) -> Void = { _ in }
    // Source manager seams (120, US2): the source-library view model and a server
    // API-key client for the add-source album picker.
    var makeSourceLibraryViewModel: () -> SourceLibraryViewModel? = { nil }
    var makeServerAPI: () async -> (any ImmichAPI)? = { nil }

    @Environment(\.dismiss) private var dismiss
    @State private var brightness: Double
    // Both editors are owned here as @State (not inside the disclosure content) so
    // collapsing/re-expanding a section keeps typed-but-unsaved edits.
    @State private var connectionViewModel: ConnectionSettingsViewModel?
    @State private var sourceLibraryViewModel: SourceLibraryViewModel?
    @State private var brokerViewModel: BrokerSetupViewModel
    // The MQTT section collapses by default (Constitution VII). UI tests pre-expand it via a
    // launch argument so its fields are reachable without a tap. Connection is a pushed editor.
    @State private var mqttExpanded: Bool

    init(
        powerManager: PowerManager,
        themeStore: UserDefaultsThemeStore,
        makeConnectionViewModel: @escaping () -> ConnectionSettingsViewModel? = { nil },
        onConnectionChanged: @escaping (ConnectionValidationOutcome) -> Void = { _ in },
        makeSourceLibraryViewModel: @escaping () -> SourceLibraryViewModel? = { nil },
        makeServerAPI: @escaping () async -> (any ImmichAPI)? = { nil }
    ) {
        self.powerManager = powerManager
        self.themeStore = themeStore
        self.makeConnectionViewModel = makeConnectionViewModel
        self.onConnectionChanged = onConnectionChanged
        self.makeSourceLibraryViewModel = makeSourceLibraryViewModel
        self.makeServerAPI = makeServerAPI
        _brightness = State(initialValue: Self.currentScreenBrightness())
        _connectionViewModel = State(initialValue: makeConnectionViewModel())
        _sourceLibraryViewModel = State(initialValue: makeSourceLibraryViewModel())
        let broker = BrokerSetupViewModel(store: BrokerSettingsStoreFactory.make())
        broker.load()
        _brokerViewModel = State(initialValue: broker)
        let args = ProcessInfo.processInfo.arguments
        _mqttExpanded = State(initialValue: args.contains("--uitest-broker"))
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    HStack(spacing: 12) {
                        Image(systemName: "sun.min").foregroundStyle(.secondary)
                        Slider(value: $brightness, in: 0...1)
                            .accessibilityIdentifier("settings.brightness")
                        Image(systemName: "sun.max").foregroundStyle(.secondary)
                    }
                } header: {
                    Text("Brightness")
                } footer: {
                    Text("Only takes effect in the foreground while the slideshow is running.")
                }

                Section {
                    Picker(selection: $themeStore.settings.order) {
                        Text("Shuffle").tag(PlayOrder.shuffle)
                        Text("Sequential").tag(PlayOrder.sequential)
                    } label: {
                        Label("Order", systemImage: "shuffle")
                    }
                    .accessibilityIdentifier("settings.order")

                    Picker(selection: $themeStore.settings.duration) {
                        ForEach(Self.durationPresets, id: \.self) { duration in
                            Text(Self.durationLabel(duration)).tag(duration)
                        }
                    } label: {
                        Label("Duration", systemImage: "timer")
                    }
                    .accessibilityIdentifier("settings.duration")

                    Picker(selection: $themeStore.settings.transition) {
                        Text("Crossfade").tag(Transition.crossfade)
                        Text("Slide").tag(Transition.slide)
                        Text("Dissolve").tag(Transition.dissolve)
                        Text("None").tag(Transition.none)
                    } label: {
                        Label("Transition", systemImage: "wand.and.stars")
                    }
                    .accessibilityIdentifier("settings.transition")

                    Toggle(isOn: $themeStore.settings.kenBurns) {
                        Label("Ken Burns", systemImage: "camera.viewfinder")
                    }
                    .accessibilityIdentifier("settings.kenBurns")

                    Picker(selection: $themeStore.settings.fit) {
                        Text("Fit").tag(ImageFit.fit)
                        Text("Fill").tag(ImageFit.fill)
                    } label: {
                        Label("Image fit", systemImage: "aspectratio")
                    }
                    .accessibilityIdentifier("settings.fit")

                    Picker(selection: $themeStore.settings.quality) {
                        Text("Preview").tag(ImageQuality.preview)
                        Text("Original").tag(ImageQuality.original)
                    } label: {
                        Label("Quality", systemImage: "photo")
                    }
                    .accessibilityIdentifier("settings.quality")

                    placeholderRow("Clock overlay", value: "Off", systemImage: "clock")
                } header: {
                    Text("Display")
                } footer: {
                    Text("Order and duration take effect immediately. More options to follow.")
                }

                if let sourceLibraryViewModel {
                    Section {
                        NavigationLink {
                            SourceLibraryView(viewModel: sourceLibraryViewModel, makeServerAPI: makeServerAPI)
                        } label: {
                            Label("Sources", systemImage: "photo.stack")
                                .accessibilityIdentifier("settings.sources")
                        }
                    } header: {
                        Text("Slideshow")
                    } footer: {
                        Text("Manage albums and shared links and choose the active source.")
                    }
                }

                if let connectionViewModel {
                    Section {
                        NavigationLink {
                            ConnectionSettingsView(viewModel: connectionViewModel, showsCancelButton: false) { outcome in
                                onConnectionChanged(outcome)
                            }
                        } label: {
                            HStack {
                                Label("Connection", systemImage: "server.rack")
                                Spacer()
                                Text(connectionViewModel.serverURLInput)
                                    .foregroundStyle(.secondary)
                                    .font(.footnote)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            }
                            .accessibilityIdentifier("settings.connection")
                        }
                    } header: {
                        Text("Server")
                    } footer: {
                        Text("Change the server address and API key.")
                    }
                }

                Section {
                    DisclosureGroup(isExpanded: $mqttExpanded) {
                        BrokerSettingsSection(viewModel: brokerViewModel)
                    } label: {
                        Label("MQTT", systemImage: "antenna.radiowaves.left.and.right")
                            .accessibilityIdentifier("settings.mqtt")
                    }
                } header: {
                    Text("Home Assistant")
                } footer: {
                    Text("MQTT broker for remote control via Home Assistant.")
                }
            }
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
        .onChange(of: brightness) { _, newValue in
            Task { await powerManager.setBrightness(newValue, animated: false) }
        }
    }

    /// Duration presets surfaced in the picker (a subset of the 3 s…600 s range the
    /// store accepts; out-of-range values are clamped by the store).
    private static let durationPresets: [Duration] = [
        .seconds(5), .seconds(10), .seconds(15), .seconds(30), .seconds(60), .seconds(300)
    ]

    private static func durationLabel(_ duration: Duration) -> String {
        let seconds = Int(duration.components.seconds)
        if seconds < 60 {
            return "\(seconds) s"
        }
        return "\(seconds / 60) min"
    }

    /// A disabled preview of a planned setting (lights up once its module exists).
    private func placeholderRow(_ title: String, value: String, systemImage: String) -> some View {
        HStack {
            Label(title, systemImage: systemImage)
            Spacer()
            Text(value)
        }
        .foregroundStyle(.secondary)
        .accessibilityIdentifier("settings.row.\(title)")
    }

    /// Live built-in-screen brightness via the active window scene (iOS 26 dropped
    /// `UIScreen.main`), mirroring UIScreenController so the slider starts accurate.
    private static func currentScreenBrightness() -> Double {
        let windowScenes = UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
        let screen = (windowScenes.first { $0.activationState == .foregroundActive } ?? windowScenes.first)?.screen
        return Double(screen?.brightness ?? 1.0)
    }
}

