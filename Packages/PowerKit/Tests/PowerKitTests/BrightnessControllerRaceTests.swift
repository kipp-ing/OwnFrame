import Foundation
import Testing
@testable import PowerKit

/// 410 adversarial-review findings, pinned: events that arrive while a soft dim is still
/// running, and a pre-night value that outlives its session.
@MainActor
@Suite("410 BrightnessController races")
struct BrightnessControllerRaceTests {
    private func rig(screen: FakeScreenController, store: InMemoryBrightnessStore, clock: WallClock)
        -> (PowerManager, BrightnessController) {
        let power = PowerManager(screen: screen, clock: YieldingClock())
        let controller = BrightnessController(
            power: power, store: store, clock: ManualClock(),
            now: { clock.now }, calendar: WallClock.calendar, runsTickLoop: false
        )
        return (power, controller)
    }

    @Test func automaticDuringAFixedRampWinsAndRestores() async {
        let screen = FakeScreenController(brightness: 0.3)
        let (_, c) = rig(screen: screen, store: InMemoryBrightnessStore(), clock: WallClock("2026-09-28 12:00"))
        await c.activate()
        let toFixed = Task { await c.setMode(.fixed) }
        let toAuto = Task { await c.setMode(.automatic) }
        await toFixed.value
        await toAuto.value
        #expect(c.effectiveMode == .automatic)
        #expect(screen.brightness == 0.3, "the stale ramp must not win over the newer event")
    }

    @Test func nightToggledOnAndOffWithinTheRampEndsBright() async {
        let screen = FakeScreenController(brightness: 0.5)
        let (_, c) = rig(screen: screen, store: InMemoryBrightnessStore(), clock: WallClock("2026-09-28 23:30"))
        await c.activate()
        let on = Task { await c.remoteSetNightWindowEnabled(true) }
        let off = Task { await c.remoteSetNightWindowEnabled(false) }
        await on.value
        await off.value
        #expect(!c.isNightActive)
        #expect(screen.brightness == 0.5)
    }

    @Test func aWriteDuringARestoreKeepsTheExitRestoreArmed() async {
        let screen = FakeScreenController(brightness: 0.3)
        let power = PowerManager(screen: screen, clock: YieldingClock())
        power.activate()
        await power.setBrightness(0.9, animated: false)
        let restore = Task { await power.restore(to: 0.3, animated: true) }
        let write = Task { await power.setBrightness(0.7, animated: false) }
        await restore.value
        await write.value
        #expect(power.hasChangedBrightness, "a level set after the restore began is still the app's")
    }

    @Test func exitAtNightAfterAHandBackForgetsThePreNightValue() async {
        let screen = FakeScreenController(brightness: 0.5)
        let store = InMemoryBrightnessStore(settings: BrightnessSettings(
            night: NightWindow(isEnabled: true, startMinute: 23 * 60, endMinute: 7 * 60, level: 0)))
        let clock = WallClock("2026-09-28 22:59")
        let (_, c) = rig(screen: screen, store: store, clock: clock)
        await c.activate()
        clock.set("2026-09-28 23:00")
        await c.tick()
        await c.remoteSetMode(.automatic) // hands back to iOS at night
        c.surfaceDisappeared()
        #expect(store.preNightBaseline == nil)

        // Next day: iOS is somewhere else; Automatic must write nothing.
        screen.systemMoves(to: 0.9)
        clock.set("2026-09-29 12:00")
        let writes = screen.brightnessWrites.count
        let (_, next) = rig(screen: screen, store: store, clock: clock)
        await next.activate()
        #expect(screen.brightnessWrites.count == writes)
    }
}
