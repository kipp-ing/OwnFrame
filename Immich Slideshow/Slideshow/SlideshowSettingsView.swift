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
import PhotoLibraryKit
import PowerKit
import PurchaseKit
import SlideshowKit
import SwiftUI
import ThemeKit

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
    // 900 / US1: the PhotoKit seam for the add-sheet's Photos-album tab.
    var makePhotoGateway: () -> any PhotoLibraryGateway = { PHKitGateway() }
    // 900 / T033 (FR-900-15): the active source is a Photos-library source — the Display
    // footer then notes the iCloud Shared Album pixel ceiling next to the quality picker.
    var isPhotoLibrarySource = false
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
    // 1100: what the frame owns. Optional so previews render without the app environment;
    // absent means unentitled, so the gate fails closed (same rule as SlideshowView).
    @Environment(EntitlementStore.self) private var entitlements: EntitlementStore?
    // The tier whose unlock screen is being presented, or nil. Only ever set by a user tap on
    // a locked row — nothing here may auto-present (FR-1100-09 / SC-1100-02).
    @State private var unlockTier: Entitlement?
    // Tip jar sheet (US6). Settings-only, never solicited anywhere else.
    @State private var showTipJar = false
    // Locked broker view (US5): masked stored config + unlock offer for an unentitled frame.
    @State private var showLockedBroker = false
    // Non-nil while a Restore is in flight, so the row shows progress and can't be double-tapped.
    @State private var isRestoring = false
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
        makePhotoGateway: @escaping () -> any PhotoLibraryGateway = { PHKitGateway() },
        isPhotoLibrarySource: Bool = false,
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
        self.makePhotoGateway = makePhotoGateway
        self.isPhotoLibrarySource = isPhotoLibrarySource
        self.onReset = onReset
        self.diskCache = diskCache
        self.snapshotStore = snapshotStore
        self.budgetStore = budgetStore
        _selectedBudget = State(initialValue: budgetStore?.load() ?? .default)
        _brightness = State(initialValue: powerManager.currentBrightness)
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
                    .lockedRow(if: !isProEntitled, requires: .pro,
                               identifier: "settings.row.kenburns.locked") { unlockTier = .pro }

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

                    Toggle(isOn: $themeStore.settings.clock.isOn) {
                        Label("Clock", systemImage: "clock")
                    }
                    .accessibilityIdentifier("settings.clock")
                    .lockedRow(if: !isProEntitled, requires: .pro,
                               identifier: "settings.row.clock.locked") { unlockTier = .pro }

                    // The clock's detail rows stay hidden while locked: the stored value is
                    // preserved (FR-1100-14), but offering style/place pickers for something
                    // that cannot render would be noise.
                    if themeStore.settings.clock.isOn, isProEntitled {
                        Picker(selection: $themeStore.settings.clock.style) {
                            Text("Digits").tag(ClockStyle.digits)
                            Text("Pill").tag(ClockStyle.pill)
                            Text("Analog").tag(ClockStyle.analog)
                        } label: {
                            Label("Clock style", systemImage: "clock.badge")
                        }
                        .accessibilityIdentifier("settings.clock.style")

                        Picker(selection: $themeStore.settings.clock.place) {
                            Text("Top left").tag(ClockPlace.topLeading)
                            Text("Top middle").tag(ClockPlace.topCenter)
                            Text("Top right").tag(ClockPlace.topTrailing)
                            Text("Bottom left").tag(ClockPlace.bottomLeading)
                            Text("Bottom middle").tag(ClockPlace.bottomCenter)
                            Text("Bottom right").tag(ClockPlace.bottomTrailing)
                            Text("Random").tag(ClockPlace.random)
                        } label: {
                            Label("Clock place", systemImage: "square.grid.3x3.topleft.filled")
                        }
                        .accessibilityIdentifier("settings.clock.place")

                        Picker(selection: $themeStore.settings.clock.size) {
                            Text("Room").tag(ClockSize.room)
                            Text("Cozy").tag(ClockSize.cozy)
                        } label: {
                            Label("Clock size", systemImage: "arrow.up.left.and.arrow.down.right")
                        }
                        .accessibilityIdentifier("settings.clock.size")

                        Toggle(isOn: $themeStore.settings.clock.showDate) {
                            Label("Date line", systemImage: "calendar")
                        }
                        .accessibilityIdentifier("settings.clock.date")
                    }
                } header: {
                    Text("Display")
                } footer: {
                    if isPhotoLibrarySource {
                        // FR-900-15: never imply better quality exists — iOS caps legacy
                        // iCloud Shared Album photos; the frame shows the source's best.
                        Text("Order and duration take effect immediately. Photos from iCloud "
                             + "Shared Albums are capped by iOS at roughly 2048 px — the frame "
                             + "always shows the best your library provides, and Quality has "
                             + "no effect above that ceiling.")
                            .accessibilityIdentifier("settings.quality.ceilingNote")
                    } else {
                        Text("Order and duration take effect immediately. More options to follow.")
                    }
                }

                if let sourceLibraryViewModel {
                    Section {
                        NavigationLink {
                            SourceLibraryView(viewModel: sourceLibraryViewModel, makeServerAPI: makeServerAPI, makePhotoGateway: makePhotoGateway)
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
                    // Unlike the toggles above, this cannot just be wrapped: a locked
                    // DisclosureGroup would still expand and expose the broker editor. So the
                    // whole control is swapped for a locked row while Automation is absent.
                    // Nothing stored is read, cleared, or migrated by this branch — the config
                    // and its keychain items are simply not surfaced (FR-1100-14).
                    if isAutomationEntitled {
                        DisclosureGroup(isExpanded: $mqttExpanded) {
                            BrokerSettingsSection(viewModel: brokerViewModel, publishOptions: publishOptions)
                        } label: {
                            Label("MQTT", systemImage: "antenna.radiowaves.left.and.right")
                                .accessibilityIdentifier("settings.mqtt")
                        }
                    } else {
                        // US5: tapping opens the locked broker view (masked stored config +
                        // banner + unlock offer), NOT the unlock screen directly — an existing
                        // frame's owner must be able to see their config survived (FR-1100-14).
                        LockedRow(requires: .automation,
                                  identifier: "settings.row.broker.locked",
                                  action: { showLockedBroker = true }) {
                            Label("MQTT", systemImage: "antenna.radiowaves.left.and.right")
                        }
                    }
                } header: {
                    Text("Home Assistant")
                } footer: {
                    Text("MQTT broker for remote control via Home Assistant.")
                }

                // Unlocks (1100): Restore is always here so a re-installed or second frame can
                // recover its purchases without hunting; the tip jar lives here and ONLY here,
                // never solicited from playback or onboarding (US6). Buying tiers happens on the
                // locked rows above — this section is recovery + gratitude, not a storefront.
                Section {
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
                            Spacer()
                            if isRestoring { ProgressView() }
                        }
                    }
                    .disabled(isRestoring)
                    .accessibilityIdentifier("unlock.restore")

                    Button {
                        showTipJar = true
                    } label: {
                        Label("Leave a Tip", systemImage: "heart")
                    }
                    .accessibilityIdentifier("settings.tipjar")
                } header: {
                    Text("Unlocks")
                        .accessibilityIdentifier("settings.section.unlocks")
                } footer: {
                    Text("Restore purchases you already own. Tips are optional and unlock nothing — they just say thanks.")
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
        // Presented ONLY from a locked-row tap. Never auto-presented, and never reachable
        // from playback (SC-1100-02).
        .sheet(item: $unlockTier) { tier in
            UnlockScreenView(tier: tier) { unlockTier = nil }
        }
        .sheet(isPresented: $showTipJar) {
            TipJarView { showTipJar = false }
        }
        .sheet(isPresented: $showLockedBroker) {
            LockedBrokerView(
                viewModel: brokerViewModel,
                onUnlock: { showLockedBroker = false; unlockTier = .automation },
                onClose: { showLockedBroker = false }
            )
        }
    }

    // MARK: - Entitlement gates (1100)

    private var isProEntitled: Bool {
        entitlements?.current.contains(.pro) ?? false
    }

    private var isAutomationEntitled: Bool {
        entitlements?.current.contains(.automation) ?? false
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

