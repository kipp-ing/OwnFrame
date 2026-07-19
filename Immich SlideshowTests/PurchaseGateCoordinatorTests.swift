//
//  PurchaseGateCoordinatorTests.swift
//  Immich SlideshowTests
//
//  1100 (T018) RED: the `.automation` gate on the HA/MQTT coordinator
//  (data-model.md §Gated feature mapping — "coordinator start in
//  SlideshowRemoteControlAdapter / TVRemoteControlAdapter").
//
//  Two rules are pinned here.
//
//  1. The gate is a *construction* gate, not a runtime mute. Without `.automation`
//     the coordinator is never built and never started — no transport, no connect,
//     and crucially no read of the broker config, which in production resolves
//     through `BrokerConfigProvider` into the Keychain. Counting `load()` on the
//     config store is therefore the exact, hermetic proxy for "the Keychain was
//     never touched" (FR-1100-14): production's only path from the gate to a
//     Keychain item runs through `BrokerConfigStore.load()`.
//
//  2. R5, the state-topic rule. MQTT state topics carry the STORED settings values,
//     never the effective rendering. An Automation-only owner (no `.pro`) who drives
//     the Ken Burns or clock selects over HA must see the stored value echoed back
//     verbatim — the Pro gate bites at the point of rendering, never on the data or
//     on the wire. `SlideshowRemoteControlAdapter` must stay entitlement-free.
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
@testable import Immich_Slideshow

@MainActor
struct PurchaseGateCoordinatorTests {

    // MARK: - Construction gate

    @Test func withoutAutomationTheCoordinatorFactoryIsNeverInvoked() async throws {
        let fixture = try GateFixture(entitlements: EntitlementSet.none)
        defer { fixture.cleanUp() }

        let coordinator = await fixture.gate(fixture.adapter)

        #expect(coordinator == nil)
        #expect(fixture.factoryCalls == 0)
    }

    @Test func withAutomationTheCoordinatorIsConstructed() async throws {
        let fixture = try GateFixture(entitlements: [.automation])
        defer { fixture.cleanUp() }

        let coordinator = await fixture.gate(fixture.adapter)

        #expect(coordinator != nil)
        #expect(fixture.factoryCalls == 1)
    }

    /// Ambience and automation are independent purchases: owning Pro buys motion and
    /// the clock, never remote control.
    @Test func proAloneDoesNotUnlockRemoteControl() async throws {
        let fixture = try GateFixture(entitlements: [.pro])
        defer { fixture.cleanUp() }

        let coordinator = await fixture.gate(fixture.adapter)

        #expect(coordinator == nil)
        #expect(fixture.factoryCalls == 0)
    }

    /// The everything-bundle grants both tiers, so it must open this gate too.
    @Test func everythingBundleUnlocksRemoteControl() async throws {
        let fixture = try GateFixture(entitlements: EntitlementSet.all)
        defer { fixture.cleanUp() }

        let coordinator = await fixture.gate(fixture.adapter)

        #expect(coordinator != nil)
        #expect(fixture.factoryCalls == 1)
    }

    // MARK: - FR-1100-14: stored configuration is never touched by the gate

    /// The gated path must short-circuit *before* the broker config is read, so an
    /// unentitled device never reaches the Keychain item holding the MQTT password.
    @Test func gatedPathNeverReadsTheBrokerConfigOrKeychain() async throws {
        let fixture = try GateFixture(entitlements: EntitlementSet.none)
        defer { fixture.cleanUp() }

        _ = await fixture.gate(fixture.adapter)

        #expect(fixture.configStore.loadCalls == 0)
    }

    /// …and the stored configuration survives the gated path completely unchanged:
    /// no clear, no migration, no masking. Purchasing later must re-enable HA with
    /// zero re-entry (FR-1100-14).
    @Test func gatedPathLeavesTheStoredBrokerConfigByteIdentical() async throws {
        let fixture = try GateFixture(entitlements: EntitlementSet.none)
        defer { fixture.cleanUp() }

        let before = fixture.configStore.stored

        _ = await fixture.gate(fixture.adapter)

        #expect(fixture.configStore.stored == before)
        #expect(fixture.configStore.stored?.password == GateFixture.brokerConfig.password)
        #expect(fixture.configStore.clearCalls == 0)
    }

    /// The entitled path is unchanged from pre-gate behaviour: exactly the one config
    /// read the coordinator factory always did.
    @Test func entitledPathReadsTheBrokerConfigExactlyOnce() async throws {
        let fixture = try GateFixture(entitlements: [.automation])
        defer { fixture.cleanUp() }

        _ = await fixture.gate(fixture.adapter)

        #expect(fixture.configStore.loadCalls == 1)
        #expect(fixture.configStore.clearCalls == 0)
    }

    // MARK: - R5: state topics report stored settings, not effective rendering

    /// An Automation-only owner reads the Ken Burns select over HA: the topic reports
    /// the STORED `true`, while `AmbienceGate` (no `.pro`) renders it off. Data and
    /// rendering are deliberately allowed to disagree.
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

    /// A remote apply from an Automation-only owner is stored verbatim and echoed
    /// back verbatim. The gate must never rewrite an incoming command to `false`,
    /// which would silently destroy the owner's stored preference.
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

    /// The adapter is entitlement-free by construction — it takes no entitlement
    /// input and its snapshot is a pure mirror of the store. This pins the invariant
    /// from data-model.md §Invariants: PurchaseKit never reads, writes, masks, or
    /// migrates `ThemeSettings` / `ClockSettings`.
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

    var factoryCalls: Int { calls.count }

    init(entitlements: EntitlementSet, suite: String = "gate.default") throws {
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
        configStore = RecordingBrokerConfigStore(stored: Self.brokerConfig)

        // Mirrors the production factory in `Immich_SlideshowApp.swift`: read the broker
        // config first (the Keychain hop), bail without one, otherwise build a coordinator.
        // The gate must short-circuit *ahead* of this whole closure.
        let configStore = self.configStore
        let transport = self.transport
        let calls = self.calls
        let adapter = self.adapter
        gate = AutomationCoordinatorGate(
            entitlements: { entitlements },
            makeCoordinator: { _ in
                calls.increment()
                guard configStore.load() != nil else { return nil }
                return HAControlCoordinator(
                    transport: transport,
                    control: adapter,
                    settings: adapter,
                    configStore: configStore,
                    deviceName: "Photo Frame",
                    enabledEntities: HAEntity.defaultEnabled
                )
            }
        )
    }

    func cleanUp() {
        defaults.removePersistentDomain(forName: suiteName)
    }
}

/// Counts `load()` so a test can prove the gated path never reaches the Keychain —
/// in production `BrokerConfigProvider.load()` is the sole hop from here into
/// `KeychainBrokerSettingsStore`. Also proves nothing is ever cleared (FR-1100-14).
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
