//
//  PurchaseGateCoordinatorTests.swift
//  OwnFrameTests
//
//  1100 (T018, amended 2026-07-20 by T050): the `.automation` gate on the HA/MQTT
//  coordinator (data-model.md §Gated feature mapping).
//
//  The amendment: **telemetry is free, only control is gated** (FR-1100-03 / FR-1100-03a).
//  The gate no longer blocks the coordinator — it selects its `Mode`:
//
//  1. Without `.automation` but with a broker configured, the coordinator builds in
//     `.telemetryOnly`: it connects and publishes read-only sensors so Home Assistant can
//     *see* the frame, but never subscribes to a command topic or acts on a command. Reading
//     the broker config (the Keychain hop, `BrokerConfigStore.load()`) is now a free-tier
//     operation — telemetry needs it — but the stored config is NEVER cleared or migrated, so
//     buying Automation later upgrades to `.full` with zero re-entry (FR-1100-14).
//
//  2. R5, the state-topic rule (unchanged). MQTT state topics carry the STORED settings
//     values, never the effective rendering. An Automation-only owner (no `.pro`) who drives
//     the Ken Burns or clock selects over HA must see the stored value echoed back verbatim —
//     the Pro gate bites at the point of rendering, never on the data or on the wire.
//     `SlideshowRemoteControlAdapter` stays entitlement-free.
//

import Foundation
import Testing
import HAControlKit
import ImmichClient
import PhotoSourceKit
import PowerKit
import PurchaseKit
import SlideshowKit
import ThemeKit
@testable import OwnFrame

@MainActor
struct PurchaseGateCoordinatorTests {

    // MARK: - Mode selection (control-only gate)

    @Test func withoutAutomationTheCoordinatorBuildsInTelemetryMode() async throws {
        let fixture = try GateFixture(entitlements: EntitlementSet.none)
        defer { fixture.cleanUp() }

        let coordinator = await fixture.gate(fixture.adapter)

        #expect(coordinator != nil, "a configured broker still connects for free telemetry")
        #expect(fixture.factoryCalls == 1)
        #expect(fixture.lastMode == .telemetryOnly)
    }

    @Test func withAutomationTheCoordinatorBuildsInFullMode() async throws {
        let fixture = try GateFixture(entitlements: [.automation])
        defer { fixture.cleanUp() }

        let coordinator = await fixture.gate(fixture.adapter)

        #expect(coordinator != nil)
        #expect(fixture.factoryCalls == 1)
        #expect(fixture.lastMode == .full)
    }

    /// Ambience and automation are independent purchases: owning Pro buys motion and the
    /// clock, never remote control — so a Pro-only frame gets telemetry, not full control.
    @Test func proAloneGetsTelemetryNotControl() async throws {
        let fixture = try GateFixture(entitlements: [.pro])
        defer { fixture.cleanUp() }

        let coordinator = await fixture.gate(fixture.adapter)

        #expect(coordinator != nil)
        #expect(fixture.lastMode == .telemetryOnly)
    }

    /// The everything-bundle grants both tiers, so it must open the control tier.
    @Test func everythingBundleUnlocksFullControl() async throws {
        let fixture = try GateFixture(entitlements: EntitlementSet.all)
        defer { fixture.cleanUp() }

        let coordinator = await fixture.gate(fixture.adapter)

        #expect(coordinator != nil)
        #expect(fixture.lastMode == .full)
    }

    /// No broker configured → no coordinator at all, regardless of tier (nothing to connect).
    @Test func noBrokerConfiguredBuildsNoCoordinatorEvenFree() async throws {
        let fixture = try GateFixture(entitlements: EntitlementSet.none, broker: nil)
        defer { fixture.cleanUp() }

        let coordinator = await fixture.gate(fixture.adapter)

        #expect(coordinator == nil)
    }

    // MARK: - FR-1100-14: stored configuration is read for telemetry but never touched

    /// Free telemetry DOES read the broker config (it needs it to connect), but never clears
    /// or migrates it — the whole basis for a zero-re-entry upgrade when Automation is bought.
    @Test func telemetryPathReadsBrokerConfigButNeverClears() async throws {
        let fixture = try GateFixture(entitlements: EntitlementSet.none)
        defer { fixture.cleanUp() }

        _ = await fixture.gate(fixture.adapter)

        #expect(fixture.configStore.loadCalls == 1)
        #expect(fixture.configStore.clearCalls == 0)
    }

    /// The stored configuration survives the telemetry path completely unchanged: no clear,
    /// no migration, no masking (FR-1100-14).
    @Test func telemetryPathLeavesTheStoredBrokerConfigByteIdentical() async throws {
        let fixture = try GateFixture(entitlements: EntitlementSet.none)
        defer { fixture.cleanUp() }

        let before = fixture.configStore.stored

        _ = await fixture.gate(fixture.adapter)

        #expect(fixture.configStore.stored == before)
        #expect(fixture.configStore.stored?.password == GateFixture.brokerConfig.password)
        #expect(fixture.configStore.clearCalls == 0)
    }

    /// The full path reads the broker config exactly once — the coordinator factory's own read.
    @Test func fullPathReadsTheBrokerConfigExactlyOnce() async throws {
        let fixture = try GateFixture(entitlements: [.automation])
        defer { fixture.cleanUp() }

        _ = await fixture.gate(fixture.adapter)

        #expect(fixture.configStore.loadCalls == 1)
        #expect(fixture.configStore.clearCalls == 0)
    }

    // MARK: - FR-1100-14 / US5 scenario 3: purchasing Automation upgrades telemetry → full
    // with the previously stored config and zero re-entry.

    /// A frame that stored a broker config while free — already publishing telemetry — then
    /// buys Automation, and its coordinator upgrades from `.telemetryOnly` to `.full` against
    /// the *same* stored config with no re-entry. One config store, one gate; only the
    /// entitlement set flips between the two calls — exactly as a live purchase would flip it,
    /// since the gate reads entitlements at call time.
    @Test func purchasingAutomationUpgradesTelemetryToFullWithTheStoredConfig() async throws {
        let fixture = try GateFixture(entitlements: EntitlementSet.none, suite: "gate.purchase-flip")
        defer { fixture.cleanUp() }

        let configStore = fixture.configStore
        let adapter = fixture.adapter
        let seeded = try #require(configStore.stored)   // the config the frame stored while free

        // A completed purchase flips this set; the gate re-reads it on the next build.
        let owned = EntitlementBox(EntitlementSet.none)
        let seen = ConfigProbe()
        let seenMode = ModeBox()
        let transport = GateStubTransport()
        let calls = CallCounter()

        let gate = AutomationCoordinatorGate(
            entitlements: { owned.value },
            makeCoordinator: { _, mode in
                calls.increment()
                seenMode.value = mode
                guard let config = configStore.load() else { return nil }
                seen.value = config
                return HAControlCoordinator(
                    transport: transport,
                    control: adapter,
                    settings: adapter,
                    configStore: configStore,
                    deviceName: "Photo Frame",
                    enabledEntities: HAEntity.defaultEnabled,
                    mode: mode
                )
            }
        )

        // --- Free: the coordinator builds in telemetry mode against the stored config.
        let before = configStore.stored
        let free = await gate(adapter)
        #expect(free != nil)
        #expect(calls.count == 1)
        #expect(seenMode.value == .telemetryOnly)
        #expect(seen.value == seeded)                  // telemetry runs against the stored config
        #expect(configStore.clearCalls == 0)
        #expect(configStore.stored == before)          // nothing mutated

        // --- Purchase completes: the same set gains `.automation`; nothing else changes.
        owned.value.insert(.automation)

        // --- Entitled: the coordinator now builds in full mode, same seeded config.
        let entitled = await gate(adapter)
        #expect(entitled != nil)
        #expect(calls.count == 2)
        #expect(seenMode.value == .full)
        #expect(configStore.clearCalls == 0)           // never cleared across the whole sequence
        #expect(seen.value == seeded)                  // built against the stored config — zero re-entry
        #expect(configStore.stored == seeded)          // store still byte-identical to the seed
    }

    // MARK: - R5: state topics report stored settings, not effective rendering

    /// An Automation-only owner reads the Ken Burns select over HA: the topic reports the
    /// STORED `true`, while `AmbienceGate` (no `.pro`) renders it off. Data and rendering are
    /// deliberately allowed to disagree.
    @Test func kenBurnsStateTopicReportsStoredValueWhileRenderingStaysProGated() throws {
        let fixture = try GateFixture(entitlements: [.automation])
        defer { fixture.cleanUp() }

        fixture.store.settings.kenBurns = true

        #expect(fixture.adapter.themeSettings.kenBurns == true)

        let ambience = AmbienceGate(entitled: false)
        #expect(ambience.effectiveKenBurns(setting: fixture.store.settings.kenBurns) == false)
    }

    /// Same rule for the clock select.
    @Test func clockStateTopicReportsStoredValueWhileRenderingStaysProGated() throws {
        let fixture = try GateFixture(entitlements: [.automation])
        defer { fixture.cleanUp() }

        fixture.store.settings.clock = ClockSettings(
            isOn: true, style: .pill, place: .topLeading, size: .cozy, showDate: true
        )

        let snapshot = fixture.adapter.themeSettings
        #expect(snapshot.clockOn == true)
        #expect(snapshot.clockStyle == .pill)
        #expect(snapshot.clockPlace == .topLeading)

        let ambience = AmbienceGate(entitled: false)
        #expect(ambience.effectiveClock(setting: snapshot.clockOn) == false)
    }

    /// A remote apply from an Automation-only owner is stored verbatim and echoed back
    /// verbatim. The gate must never rewrite an incoming command to `false`, which would
    /// silently destroy the owner's stored preference.
    @Test func remoteApplyStoresProGatedValuesVerbatimForAnAutomationOnlyOwner() throws {
        let fixture = try GateFixture(entitlements: [.automation])
        defer { fixture.cleanUp() }

        var snapshot = fixture.adapter.themeSettings
        snapshot.kenBurns = true
        snapshot.clockOn = true
        fixture.adapter.apply(snapshot)

        #expect(fixture.store.settings.kenBurns == true)
        #expect(fixture.store.settings.clock.isOn == true)
        #expect(fixture.adapter.themeSettings.kenBurns == true)
        #expect(fixture.adapter.themeSettings.clockOn == true)
    }

    /// The adapter is entitlement-free by construction — it takes no entitlement input and its
    /// snapshot is a pure mirror of the store. This pins the invariant from data-model.md
    /// §Invariants: PurchaseKit never reads, writes, masks, or migrates
    /// `ThemeSettings` / `ClockSettings`.
    @Test func adapterSnapshotIsAPureMirrorOfTheStoreRegardlessOfEntitlements() throws {
        let cases: [EntitlementSet] = [EntitlementSet.none, [.pro], [.automation], EntitlementSet.all]
        for (index, entitlements) in cases.enumerated() {
            let fixture = try GateFixture(entitlements: entitlements, suite: "gate.mirror.\(index)")
            defer { fixture.cleanUp() }

            fixture.store.settings.kenBurns = true
            fixture.store.settings.clock = ClockSettings(
                isOn: true, style: .digits, place: .bottomTrailing, size: .room, showDate: false
            )

            #expect(fixture.adapter.themeSettings.kenBurns == true)
            #expect(fixture.adapter.themeSettings.clockOn == true)
        }
    }
}

// MARK: - Fixture

@MainActor
private final class GateFixture {
    static let brokerConfig = BrokerConfig(
        host: "broker.local",
        port: 8883,
        username: "frame",
        password: "s3cret-never-cleared",
        deviceID: "dev-gate"
    )

    let store: UserDefaultsThemeStore
    let adapter: SlideshowRemoteControlAdapter
    let configStore: RecordingBrokerConfigStore
    let gate: AutomationCoordinatorGate
    private let defaults: UserDefaults
    private let suiteName: String
    private let transport = GateStubTransport()
    private let calls = CallCounter()
    private let modeBox = ModeBox()

    var factoryCalls: Int { calls.count }
    var lastMode: HAControlCoordinator.Mode? { modeBox.value }

    init(entitlements: EntitlementSet, suite: String = "gate.default", broker: BrokerConfig? = GateFixture.brokerConfig) throws {
        suiteName = "de.kippings.ImmichSlideshow.tests.\(suite)"
        defaults = try #require(UserDefaults(suiteName: suiteName))
        defaults.removePersistentDomain(forName: suiteName)

        store = UserDefaultsThemeStore(defaults: defaults)
        let slideshow = SlideshowViewModel(
            source: GateStubAPI(),
            collectionID: "album-1",
            ticker: GateStubTicker(),
            settingsStore: store
        )
        adapter = SlideshowRemoteControlAdapter(
            slideshow: slideshow,
            powerManager: PowerManager(screen: GateStubScreen()),
            themeStore: store
        )
        configStore = RecordingBrokerConfigStore(stored: broker)

        // Mirrors the production factory in `OwnFrameApp.swift`: read the broker
        // config (the Keychain hop), bail without one, otherwise build a coordinator in the
        // gate-selected mode. Reading is now free-tier; the factory never clears or migrates.
        let configStore = self.configStore
        let transport = self.transport
        let calls = self.calls
        let modeBox = self.modeBox
        let adapter = self.adapter
        gate = AutomationCoordinatorGate(
            entitlements: { entitlements },
            makeCoordinator: { _, mode in
                calls.increment()
                modeBox.value = mode
                guard configStore.load() != nil else { return nil }
                return HAControlCoordinator(
                    transport: transport,
                    control: adapter,
                    settings: adapter,
                    configStore: configStore,
                    deviceName: "Photo Frame",
                    enabledEntities: HAEntity.defaultEnabled,
                    mode: mode
                )
            }
        )
    }

    func cleanUp() {
        defaults.removePersistentDomain(forName: suiteName)
    }
}

/// Counts `load()` and `clear()` so a test can prove the telemetry path reads the broker
/// config exactly once and never clears it — in production `BrokerConfigProvider.load()` is
/// the sole hop from here into `KeychainBrokerSettingsStore` (FR-1100-14).
private final class RecordingBrokerConfigStore: BrokerConfigStore, @unchecked Sendable {
    private(set) var stored: BrokerConfig?
    private(set) var loadCalls = 0
    private(set) var clearCalls = 0

    init(stored: BrokerConfig?) {
        self.stored = stored
    }

    func load() -> BrokerConfig? {
        loadCalls += 1
        return stored
    }

    func clear() {
        clearCalls += 1
        stored = nil
    }
}

private final class CallCounter: @unchecked Sendable {
    private(set) var count = 0
    func increment() { count += 1 }
}

/// A mutable entitlement source so one gate can be re-read across a simulated purchase. Same
/// `@unchecked Sendable` shape as `CallCounter`: every access here happens on the main actor.
private final class EntitlementBox: @unchecked Sendable {
    var value: EntitlementSet
    init(_ value: EntitlementSet) { self.value = value }
}

/// Captures the `BrokerConfig` the coordinator factory actually read, so a test can prove the
/// upgraded build ran against the previously stored config rather than a re-entered one.
private final class ConfigProbe: @unchecked Sendable {
    var value: BrokerConfig?
}

/// Captures the `Mode` the gate selected for the factory.
private final class ModeBox: @unchecked Sendable {
    var value: HAControlCoordinator.Mode?
}

private final class GateStubTransport: MQTTTransport, @unchecked Sendable {
    lazy var incoming: AsyncStream<MQTTMessage> = AsyncStream { _ in }
    lazy var connectionEvents: AsyncStream<Bool> = AsyncStream { _ in }

    func connect(will: MQTTMessage) async throws {}
    func disconnect() async {}
    func publish(_ message: MQTTMessage) async throws {}
    func subscribe(_ topicFilter: String) async throws {}
}

private struct GateStubAPI: ImmichAPI, PhotoSourceProviding {
    func serverVersion() async throws -> String { "test" }
    func albums() async throws -> [Album] { [] }
    func assets(albumID: String) async throws -> [Asset] { [] }
    func preview(assetID: String) async throws -> Data { Data() }

    func ensureReady() async throws {}
    func collections() async throws -> [SourceCollection] { [] }
    func assets(in collectionID: String) async throws -> [SourceAsset] { [] }
    func imageData(for assetID: String, fidelity: ImageFidelity) async throws -> Data { Data() }
    func metadata(for assetID: String) async throws -> AssetMetadata {
        AssetMetadata(capturedAt: nil, latitude: nil, longitude: nil, placeName: nil)
    }
}

/// Parked ticker: nothing auto-advances, so the gate assertions are timing-free.
private struct GateStubTicker: SlideshowTicker {
    func waitForNextTick(duration: Duration) async throws {
        try await Task.sleep(for: .seconds(3_600))
    }
}

private final class GateStubScreen: ScreenControlling {
    var brightness: Double = 0.5
    var isIdleTimerDisabled = false
}
