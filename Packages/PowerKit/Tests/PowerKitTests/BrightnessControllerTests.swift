import Foundation
import Testing
@testable import PowerKit

/// 410 T005–T010: the brightness policy. The screen drifts like iOS (finding 2), the wall clock
/// is moved by hand, and the 1 s hold loop is driven through `tick()`.
@MainActor
@Suite("410 BrightnessController")
struct BrightnessControllerTests {
    struct Rig {
        let screen: FakeScreenController
        let power: PowerManager
        let store: InMemoryBrightnessStore
        let clock: WallClock
        let controller: BrightnessController

        /// A relaunch: new process objects over the same persisted store and the same screen
        /// (an app write outlives the app, finding 6).
        @MainActor func relaunch() -> Rig {
            BrightnessControllerTests.rig(screen: screen, store: store, clock: clock)
        }
    }

    static func rig(
        screen: FakeScreenController = FakeScreenController(brightness: 0.5),
        store: InMemoryBrightnessStore = InMemoryBrightnessStore(),
        clock: WallClock = WallClock("2026-09-28 12:00")
    ) -> Rig {
        let power = PowerManager(screen: screen, clock: ManualClock())
        let controller = BrightnessController(
            power: power,
            store: store,
            clock: ManualClock(),
            now: { clock.now },
            calendar: WallClock.calendar,
            runsTickLoop: false
        )
        return Rig(screen: screen, power: power, store: store, clock: clock, controller: controller)
    }

    static func nightStore(mode: BrightnessMode = .automatic, preset: Double = 0.8, level: Double = 0.0) -> InMemoryBrightnessStore {
        InMemoryBrightnessStore(settings: BrightnessSettings(
            mode: mode,
            preset: preset,
            night: NightWindow(isEnabled: true, startMinute: 23 * 60, endMinute: 7 * 60, level: level)
        ))
    }

    // MARK: - US1 Automatic (SC-410-01)

    @Test func automaticNeverWrites() async {
        let rig = Self.rig()
        let c = rig.controller
        await c.activate()
        for value in [0.1, 0.9, 0.3] {
            rig.screen.systemMoves(to: value)
            await c.tick()
        }
        c.handOver()
        c.surfaceDisappeared() // a source switch generation swap
        await c.activate()
        c.didEnterBackground()
        await c.willEnterForeground()
        await c.tick()
        c.surfaceDisappeared() // genuine exit
        #expect(rig.screen.brightnessWrites.isEmpty)
        #expect(c.effectiveMode == .automatic)
    }

    // MARK: - US2 Fixed (SC-410-02/03, FR-410-10)

    @Test func fixedAppliesAndHoldsThePresetAgainstDrift() async {
        let rig = Self.rig(store: InMemoryBrightnessStore(settings: BrightnessSettings(mode: .fixed, preset: 0.8)))
        await rig.controller.activate()
        #expect(rig.screen.brightness == 0.8)

        rig.screen.systemMoves(to: 0.75)
        await rig.controller.tick()
        #expect(rig.screen.brightness == 0.8, "one tick re-applies a one-step drift")

        let writes = rig.screen.brightnessWrites.count
        await rig.controller.tick()
        #expect(rig.screen.brightnessWrites.count == writes, "no drift, no write")
    }

    @Test func holdStopsInTheBackgroundAndReappliesOnReturn() async {
        let rig = Self.rig(store: InMemoryBrightnessStore(settings: BrightnessSettings(mode: .fixed, preset: 0.8)))
        await rig.controller.activate()
        rig.controller.didEnterBackground()
        rig.screen.systemMoves(to: 0.2)
        let writes = rig.screen.brightnessWrites.count
        await rig.controller.tick()
        #expect(rig.screen.brightnessWrites.count == writes)

        await rig.controller.willEnterForeground()
        #expect(rig.screen.brightness == 0.8)
    }

    @Test func relaunchReappliesThePreset() async {
        let first = Self.rig(store: InMemoryBrightnessStore(settings: BrightnessSettings(mode: .fixed, preset: 0.7)))
        await first.controller.activate()
        first.screen.systemMoves(to: 0.3)
        let second = first.relaunch()
        await second.controller.activate()
        #expect(second.screen.brightness == 0.7)
    }

    @Test func inAppModeAndPresetArePersisted() async {
        let rig = Self.rig()
        await rig.controller.activate()
        await rig.controller.setMode(.fixed)
        await rig.controller.setPreset(0.9)
        #expect(rig.store.settings.mode == .fixed)
        #expect(rig.store.settings.preset == 0.9)
        #expect(rig.screen.brightness == 0.9)
    }

    @Test func backToAutomaticRestoresTheBaselineOnceThenStops() async {
        let rig = Self.rig(screen: FakeScreenController(brightness: 0.4),
                           store: InMemoryBrightnessStore(settings: BrightnessSettings(mode: .fixed, preset: 0.9)))
        await rig.controller.activate()
        await rig.controller.setMode(.automatic)
        #expect(rig.screen.brightness == 0.4)

        let writes = rig.screen.brightnessWrites.count
        rig.screen.systemMoves(to: 0.1)
        await rig.controller.tick()
        rig.controller.surfaceDisappeared()
        #expect(rig.screen.brightnessWrites.count == writes)
    }

    @Test func exitFromFixedRestoresTheSessionBaseline() async {
        let rig = Self.rig(screen: FakeScreenController(brightness: 0.4),
                           store: InMemoryBrightnessStore(settings: BrightnessSettings(mode: .fixed, preset: 0.9)))
        await rig.controller.activate()
        rig.controller.surfaceDisappeared()
        #expect(rig.screen.brightness == 0.4)
    }

    @Test func aSourceSwapKeepsTheHeldLevelWithoutWriting() async {
        let rig = Self.rig(store: InMemoryBrightnessStore(settings: BrightnessSettings(mode: .fixed, preset: 0.8)))
        await rig.controller.activate()
        await rig.controller.remoteSetLevel(0.3)
        let writes = rig.screen.brightnessWrites.count
        rig.controller.handOver()
        await rig.controller.activate() // successor appears first…
        rig.controller.surfaceDisappeared() // …then the outgoing view disappears (#91)
        #expect(rig.screen.brightnessWrites.count == writes)
        #expect(rig.controller.reportedBrightness == 0.3)
    }

    // MARK: - US3 remote overrides (SC-410-04, FR-410-07)

    @Test func remoteLevelHoldsForTheSessionAndLeavesTheStoreAlone() async {
        let rig = Self.rig()
        await rig.controller.activate()
        await rig.controller.remoteSetLevel(0.0)
        #expect(rig.screen.brightness == 0.0)
        rig.screen.systemMoves(to: 0.15)
        await rig.controller.tick()
        #expect(rig.screen.brightness == 0.0)
        #expect(rig.store.settings == BrightnessSettings())
        #expect(rig.controller.effectiveMode == .fixed)
    }

    @Test func remoteAutoStopsWriting() async {
        let rig = Self.rig(store: InMemoryBrightnessStore(settings: BrightnessSettings(mode: .fixed, preset: 0.8)))
        await rig.controller.activate()
        await rig.controller.remoteSetMode(.automatic)
        let writes = rig.screen.brightnessWrites.count
        rig.screen.systemMoves(to: 0.2)
        await rig.controller.tick()
        #expect(rig.screen.brightnessWrites.count == writes)
        #expect(rig.store.settings.mode == .fixed, "a remote mode is session-only")
    }

    @Test func remoteFixedAppliesThePreset() async {
        let rig = Self.rig(store: InMemoryBrightnessStore(settings: BrightnessSettings(mode: .automatic, preset: 0.65)))
        await rig.controller.activate()
        await rig.controller.remoteSetMode(.fixed)
        #expect(rig.screen.brightness == 0.65)
    }

    @Test func inAppControlEndsAnOverride() async {
        let rig = Self.rig(store: InMemoryBrightnessStore(settings: BrightnessSettings(mode: .fixed, preset: 0.8)))
        await rig.controller.activate()
        await rig.controller.remoteSetLevel(0.1)
        await rig.controller.setPreset(0.6)
        #expect(rig.screen.brightness == 0.6)
    }

    @Test func relaunchDropsARemoteZero() async {
        let first = Self.rig(store: InMemoryBrightnessStore(settings: BrightnessSettings(mode: .fixed, preset: 0.7)))
        await first.controller.activate()
        await first.controller.remoteSetLevel(0.0)
        let second = first.relaunch()
        await second.controller.activate()
        #expect(second.screen.brightness == 0.7)
    }

    // MARK: - US4 night window (SC-410-08/09/10)

    @Test func windowStartFadesToNightAndEndReturnsToThePreset() async {
        let rig = Self.rig(store: Self.nightStore(mode: .fixed, preset: 0.8, level: 0.05), clock: WallClock("2026-09-28 22:59"))
        await rig.controller.activate()
        #expect(rig.screen.brightness == 0.8)
        #expect(!rig.controller.isNightActive)

        rig.clock.set("2026-09-28 23:00")
        await rig.controller.tick()
        #expect(rig.screen.brightness == 0.05)
        #expect(rig.controller.isNightActive)

        rig.clock.set("2026-09-29 07:00")
        await rig.controller.tick()
        #expect(rig.screen.brightness == 0.8)
    }

    @Test func automaticNightRestoresThePreNightBrightnessAndStops() async {
        let rig = Self.rig(screen: FakeScreenController(brightness: 0.55), store: Self.nightStore(), clock: WallClock("2026-09-28 22:59"))
        await rig.controller.activate()
        rig.clock.set("2026-09-28 23:00")
        await rig.controller.tick()
        #expect(rig.screen.brightness == 0.0)
        #expect(rig.store.preNightBaseline == 0.55)

        rig.clock.set("2026-09-29 07:00")
        await rig.controller.tick()
        #expect(rig.screen.brightness == 0.55)
        #expect(rig.store.preNightBaseline == nil)

        let writes = rig.screen.brightnessWrites.count
        rig.screen.systemMoves(to: 0.9)
        await rig.controller.tick()
        #expect(rig.screen.brightnessWrites.count == writes)
        #expect(rig.controller.effectiveMode == .automatic)
    }

    @Test func launchInsideTheWindowStartsAtNight() async {
        let rig = Self.rig(store: Self.nightStore(level: 0.1), clock: WallClock("2026-09-29 02:00"))
        await rig.controller.activate()
        #expect(rig.screen.brightness == 0.1)
    }

    @Test func nightRelaunchThenWindowEndRestoresTheRememberedValueNeverTheNightLevel() async {
        let first = Self.rig(screen: FakeScreenController(brightness: 0.6), store: Self.nightStore(), clock: WallClock("2026-09-28 22:59"))
        await first.controller.activate()
        first.clock.set("2026-09-28 23:00")
        await first.controller.tick()
        // Crash at 02:00: the night write outlives the app.
        first.clock.set("2026-09-29 02:00")
        let second = first.relaunch()
        await second.controller.activate()
        #expect(second.screen.brightness == 0.0)
        second.clock.set("2026-09-29 07:00")
        await second.controller.tick()
        #expect(second.screen.brightness == 0.6)
    }

    @Test func launchAfterAMissedWindowEndRestoresOnce() async {
        let store = Self.nightStore()
        store.preNightBaseline = 0.6
        let rig = Self.rig(screen: FakeScreenController(brightness: 0.0), store: store, clock: WallClock("2026-09-29 09:00"))
        await rig.controller.activate()
        #expect(rig.screen.brightness == 0.6)
        #expect(store.preNightBaseline == nil)
        rig.controller.surfaceDisappeared()
        #expect(rig.screen.brightness == 0.6, "handed back to iOS, exit does not write again")
    }

    @Test func remoteLevelAtNightHoldsUntilTheWindowEnd() async {
        let rig = Self.rig(store: Self.nightStore(mode: .fixed, preset: 0.8), clock: WallClock("2026-09-29 01:00"))
        await rig.controller.activate()
        await rig.controller.remoteSetLevel(0.5)
        rig.clock.set("2026-09-29 03:00")
        await rig.controller.tick()
        #expect(rig.screen.brightness == 0.5)
        rig.clock.set("2026-09-29 07:00")
        await rig.controller.tick()
        #expect(rig.screen.brightness == 0.8)
    }

    @Test func daytimeRemoteLevelIsReplacedAtWindowStart() async {
        let rig = Self.rig(store: Self.nightStore(level: 0.02), clock: WallClock("2026-09-28 20:00"))
        await rig.controller.activate()
        await rig.controller.remoteSetLevel(0.9)
        rig.clock.set("2026-09-28 23:00")
        await rig.controller.tick()
        #expect(rig.screen.brightness == 0.02)
    }

    @Test func windowEdgeCrossedInTheBackgroundAppliesOnReturn() async {
        let rig = Self.rig(store: Self.nightStore(mode: .fixed, preset: 0.8, level: 0.1), clock: WallClock("2026-09-28 22:00"))
        await rig.controller.activate()
        rig.controller.didEnterBackground()
        rig.clock.set("2026-09-28 23:30")
        await rig.controller.willEnterForeground()
        await rig.controller.tick()
        #expect(rig.screen.brightness == 0.1)
    }

    @Test func switchingTheWindowOnInsideItAppliesTheNightAndOffRestores() async {
        let rig = Self.rig(screen: FakeScreenController(brightness: 0.5), clock: WallClock("2026-09-29 01:00"))
        await rig.controller.activate()
        await rig.controller.remoteSetNightWindowEnabled(true)
        #expect(rig.store.settings.night.isEnabled)
        #expect(rig.screen.brightness == 0.0)
        await rig.controller.remoteSetNightWindowEnabled(false)
        #expect(rig.screen.brightness == 0.5)
        #expect(!rig.controller.isNightActive)
    }

    // MARK: - Peek (SC-410-11)

    @Test func tapAtNightPeeksAndFadesBack() async {
        let rig = Self.rig(store: Self.nightStore(mode: .fixed, preset: 0.8, level: 0.0), clock: WallClock("2026-09-29 01:00"))
        await rig.controller.activate()
        await rig.controller.userTapped()
        #expect(rig.screen.brightness == 0.8)

        rig.clock.advance(seconds: 40)
        await rig.controller.userTapped() // extends
        rig.clock.advance(seconds: 40)
        await rig.controller.tick()
        #expect(rig.screen.brightness == 0.8, "extended by the second tap")

        rig.clock.advance(seconds: 25)
        await rig.controller.tick()
        #expect(rig.screen.brightness == 0.0, "back within 70 s of the last tap")
    }

    @Test func peekInAutomaticShowsThePreNightBrightness() async {
        let rig = Self.rig(screen: FakeScreenController(brightness: 0.45), store: Self.nightStore(), clock: WallClock("2026-09-28 22:59"))
        await rig.controller.activate()
        rig.clock.set("2026-09-28 23:00")
        await rig.controller.tick()
        await rig.controller.userTapped()
        #expect(rig.screen.brightness == 0.45)
    }

    @Test func peekDuringARemoteLevelReturnsToTheRemoteLevel() async {
        let rig = Self.rig(store: Self.nightStore(mode: .fixed, preset: 0.8), clock: WallClock("2026-09-29 01:00"))
        await rig.controller.activate()
        await rig.controller.remoteSetLevel(0.3)
        await rig.controller.userTapped()
        #expect(rig.screen.brightness == 0.8)
        rig.clock.advance(seconds: 61)
        await rig.controller.tick()
        #expect(rig.screen.brightness == 0.3)
    }

    @Test func tapByDayDoesNothing() async {
        let rig = Self.rig(store: Self.nightStore(mode: .fixed, preset: 0.8), clock: WallClock("2026-09-28 12:00"))
        await rig.controller.activate()
        let writes = rig.screen.brightnessWrites.count
        await rig.controller.userTapped()
        #expect(rig.screen.brightnessWrites.count == writes)
    }

    // MARK: - Reporting (FR-410-09, SC-410-05)

    @Test func reportedBrightnessStartsAtTheScreenAndFollowsAHeldLevel() async {
        let rig = Self.rig(screen: FakeScreenController(brightness: 0.35))
        #expect(rig.controller.reportedBrightness == 0.35)
        await rig.controller.activate()
        await rig.controller.remoteSetLevel(0.7)
        #expect(rig.controller.reportedBrightness == 0.7)
    }

    @Test func automaticReportsOnlyAStepAndAtMostEveryFiveSeconds() async {
        let rig = Self.rig(screen: FakeScreenController(brightness: 0.5))
        var changes = 0
        rig.controller.onChange = { changes += 1 }
        await rig.controller.activate()

        rig.screen.systemMoves(to: 0.52)
        rig.clock.advance(seconds: 10)
        await rig.controller.tick()
        #expect(rig.controller.reportedBrightness == 0.5, "less than a step")

        rig.screen.systemMoves(to: 0.6)
        await rig.controller.tick()
        #expect(rig.controller.reportedBrightness == 0.6)

        rig.screen.systemMoves(to: 0.3)
        rig.clock.advance(seconds: 2)
        await rig.controller.tick()
        #expect(rig.controller.reportedBrightness == 0.6, "rate-limited")

        rig.clock.advance(seconds: 4)
        await rig.controller.tick()
        #expect(rig.controller.reportedBrightness == 0.3)
        #expect(changes == 2)
    }
}
