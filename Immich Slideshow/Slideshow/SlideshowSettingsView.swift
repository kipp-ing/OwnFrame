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
import HAControlKit
import ImmichClient
import OnboardingKit
import PowerKit
import SlideshowKit
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
    // Reset lives here rather than on the chrome (300/FR-300-28): a wall-mounted photo
    // frame has no real "exit," so the only thing a chrome button could do was reset —
    // better placed as an explicit, clearly destructive Settings action.
    var onReset: () -> Void = {}
    // Storage seams (320, US3): the shared disk cache/snapshot store the engine
    // writes to, plus the budget store. nil hides the Storage section entirely.
    var diskCache: (any DiskImageStoring)?
    var snapshotStore: (any SourceSnapshotStoring)?
    var budgetStore: (any CacheBudgetStore)?

    @Environment(\.dismiss) private var dismiss
    @State private var brightness: Double
    @State private var showResetDialog = false
    // Storage section state (320): live usage (refreshed on appear and after
    // Clear), the selected budget step, and the Clear confirmation.
    @State private var cacheUsage: Int64?
    @State private var selectedBudget: CacheBudget
    @State private var showClearCacheDialog = false
    // Both editors are owned here as @State (not inside the disclosure content) so
    // collapsing/re-expanding a section keeps typed-but-unsaved edits.
    @State private var connectionViewModel: ConnectionSettingsViewModel?
    @State private var sourceLibraryViewModel: SourceLibraryViewModel?
    @State private var brokerViewModel: BrokerSetupViewModel
    // HA photo-publishing prefs (image off by default, FR-710-15). Owned here so the
    // toggle survives collapse/relaunch; shares the coordinator's UserDefaults key.
    @State private var publishOptions: any HAPublishOptionsStore
    // The MQTT section collapses by default (Constitution VII). UI tests pre-expand it via a
    // launch argument so its fields are reachable without a tap. Connection is a pushed editor.
    @State private var mqttExpanded: Bool

    init(
        powerManager: PowerManager,
        themeStore: UserDefaultsThemeStore,
        makeConnectionViewModel: @escaping () -> ConnectionSettingsViewModel? = { nil },
        onConnectionChanged: @escaping (ConnectionValidationOutcome) -> Void = { _ in },
        makeSourceLibraryViewModel: @escaping () -> SourceLibraryViewModel? = { nil },
        makeServerAPI: @escaping () async -> (any ImmichAPI)? = { nil },
        onReset: @escaping () -> Void = {},
        diskCache: (any DiskImageStoring)? = nil,
        snapshotStore: (any SourceSnapshotStoring)? = nil,
        budgetStore: (any CacheBudgetStore)? = nil
    ) {
        self.powerManager = powerManager
        self.themeStore = themeStore
        self.makeConnectionViewModel = makeConnectionViewModel
        self.onConnectionChanged = onConnectionChanged
        self.makeSourceLibraryViewModel = makeSourceLibraryViewModel
        self.makeServerAPI = makeServerAPI
        self.onReset = onReset
        self.diskCache = diskCache
        self.snapshotStore = snapshotStore
        self.budgetStore = budgetStore
        _selectedBudget = State(initialValue: budgetStore?.load() ?? .default)
        _brightness = State(initialValue: Self.currentScreenBrightness())
        _connectionViewModel = State(initialValue: makeConnectionViewModel())
        _sourceLibraryViewModel = State(initialValue: makeSourceLibraryViewModel())
        let broker = BrokerSetupViewModel(store: BrokerSettingsStoreFactory.make())
        broker.load()
        _brokerViewModel = State(initialValue: broker)
        _publishOptions = State(initialValue: HAPublishOptionsStoreFactory.make())
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
                        ForEach(ThemeSettings.durationOptions(including: themeStore.settings.duration), id: \.self) { duration in
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
                        BrokerSettingsSection(viewModel: brokerViewModel, publishOptions: publishOptions)
                    } label: {
                        Label("MQTT", systemImage: "antenna.radiowaves.left.and.right")
                            .accessibilityIdentifier("settings.mqtt")
                    }
                } header: {
                    Text("Home Assistant")
                } footer: {
                    Text("MQTT broker for remote control via Home Assistant.")
                }

                if let diskCache {
                    Section {
                        HStack {
                            Label("Used", systemImage: "internaldrive")
                            Spacer()
                            // The identifier sits on the value Text itself so the
                            // UITest reads the byte string as the element's label.
                            Text(Self.byteLabel(cacheUsage ?? 0))
                                .foregroundStyle(.secondary)
                                .accessibilityIdentifier("settings.storage.usage")
                        }

                        Picker(selection: $selectedBudget) {
                            ForEach(CacheBudget.steps, id: \.self) { step in
                                Text(Self.byteLabel(step.bytes)).tag(step)
                            }
                        } label: {
                            Label("Maximum size", systemImage: "externaldrive")
                        }
                        .accessibilityIdentifier("settings.storage.budget")

                        Button("Clear Cache…", role: .destructive) {
                            showClearCacheDialog = true
                        }
                        .accessibilityIdentifier("settings.storage.clear")
                    } header: {
                        Text("Storage")
                    } footer: {
                        Text("Photos you have viewed are kept on this iPad so the slideshow keeps playing when the network is down.")
                    }
                    .task { cacheUsage = await diskCache.currentUsage() }
                }

                Section {
                    Button("Reset Configuration…", role: .destructive) {
                        showResetDialog = true
                    }
                    .accessibilityIdentifier("settings.reset")
                    // Anchored to the button, not the NavigationStack: an unanchored
                    // dialog popover renders empty on the iPad mini (iPadOS 17.5).
                    .confirmationDialog(
                        "Reset configuration?",
                        isPresented: $showResetDialog,
                        titleVisibility: .visible
                    ) {
                        Button("Reset", role: .destructive, action: onReset)
                        Button("Cancel", role: .cancel) {}
                    } message: {
                        Text("This clears the server, API key, and album, and returns to setup.")
                    }
                } footer: {
                    Text("Clears the server, API key, and album, and returns to setup.")
                }
            }
            // Budget changes persist and prune immediately (FR-320-04); the usage
            // label follows the prune.
            .onChange(of: selectedBudget) { _, newValue in
                budgetStore?.save(newValue)
                guard let diskCache else { return }
                Task {
                    await diskCache.setBudget(newValue.bytes)
                    cacheUsage = await diskCache.currentUsage()
                }
            }
            // The one other destructive Settings action gets the same explicit
            // confirmation as Reset (FR-320-05). Attached to the Form while the
            // reset dialog sits on its own button, so the two never collide.
            .confirmationDialog(
                "Clear cached photos?",
                isPresented: $showClearCacheDialog,
                titleVisibility: .visible
            ) {
                Button("Clear Cache", role: .destructive) {
                    guard let diskCache else { return }
                    Task {
                        await diskCache.clear()
                        snapshotStore?.clear()
                        cacheUsage = await diskCache.currentUsage()
                    }
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Removes the photos stored for offline playback. The slideshow keeps running and re-fills the cache as it plays.")
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

    private static func durationLabel(_ duration: Duration) -> String {
        let seconds = Int(duration.components.seconds)
        // Whole minutes read as "N min" (5 s…600 s presets stay unchanged); a custom
        // value from Home Assistant that isn't a whole minute stays in seconds so it
        // isn't rounded misleadingly (e.g. 90 s → "90 s", not "1 min").
        if seconds >= 60, seconds % 60 == 0 {
            return "\(seconds / 60) min"
        }
        return "\(seconds) s"
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

    /// Decimal byte label ("500 MB", "1 GB") matching CacheBudget's decimal
    /// steps; numeric zero (not "Zero KB") so the usage label stays literal.
    private static func byteLabel(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        formatter.allowsNonnumericFormatting = false
        return formatter.string(fromByteCount: bytes)
    }
}

#Preview("Storage section") {
    let root = FileManager.default.temporaryDirectory
        .appendingPathComponent("settings-preview-\(UUID().uuidString)", isDirectory: true)
    return SlideshowSettingsView(
        powerManager: PowerManager(screen: PreviewScreenController()),
        themeStore: UserDefaultsThemeStore(
            defaults: UserDefaults(suiteName: "preview.theme") ?? .standard
        ),
        diskCache: DiskImageCache(root: root.appendingPathComponent("images"), budget: CacheBudget.default.bytes),
        snapshotStore: FileSourceSnapshotStore(root: root.appendingPathComponent("snapshots")),
        budgetStore: UserDefaultsCacheBudgetStore(
            defaults: UserDefaults(suiteName: "preview.storage") ?? .standard
        )
    )
}

@MainActor
private final class PreviewScreenController: ScreenControlling {
    var brightness: Double = 0.5
    var isIdleTimerDisabled = false
}

