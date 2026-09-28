import Testing
@testable import PowerKit

/// 410 T004: the seams BrightnessController needs on PowerManager (400 mechanics stay put).
@MainActor
@Suite("410 PowerManager restore seams")
struct PowerManagerRestoreTests {
    @Test func restoreWritesAndDisarmsTheExitRestore() async {
        let screen = FakeScreenController(brightness: 0.5)
        let manager = PowerManager(screen: screen, clock: ManualClock())
        manager.activate()
        await manager.setBrightness(0.9, animated: false)

        await manager.restore(to: 0.4, animated: false)
        #expect(screen.brightness == 0.4)

        let writes = screen.brightnessWrites.count
        manager.deactivate()
        #expect(screen.brightnessWrites.count == writes, "restore(to:) hands back to iOS; exit must not write again")
    }

    @Test func restoreIsForegroundOnly() async {
        let screen = FakeScreenController(brightness: 0.5)
        let manager = PowerManager(screen: screen, clock: ManualClock())
        manager.activate()
        manager.didEnterBackground()
        await manager.restore(to: 0.2, animated: false)
        #expect(screen.brightnessWrites.isEmpty)
    }

    @Test func deactivateRestoringToAChosenValue() async {
        let screen = FakeScreenController(brightness: 0.5)
        let manager = PowerManager(screen: screen, clock: ManualClock())
        manager.activate()
        await manager.setBrightness(0.1, animated: false)
        manager.deactivate(restoringTo: 0.7)
        #expect(screen.brightness == 0.7)
    }

    @Test func deactivateRestoringToDoesNothingWhenTheAppNeverWrote() {
        let screen = FakeScreenController(brightness: 0.5)
        let manager = PowerManager(screen: screen, clock: ManualClock())
        manager.activate()
        manager.deactivate(restoringTo: 0.7)
        #expect(screen.brightnessWrites.isEmpty)
    }

    @Test func exposesForegroundAndBaseline() {
        let screen = FakeScreenController(brightness: 0.35)
        let manager = PowerManager(screen: screen, clock: ManualClock())
        #expect(!manager.isForegroundActive)
        manager.activate()
        #expect(manager.isForegroundActive)
        #expect(manager.baseline == 0.35)
        #expect(!manager.hasChangedBrightness)
    }

    @Test func isRampingDuringAnAnimatedDim() async {
        let screen = FakeScreenController(brightness: 0.5)
        let clock = BlockingManualClock()
        let manager = PowerManager(screen: screen, clock: clock)
        manager.activate()
        let ramp = Task { await manager.setBrightness(0.1, animated: true) }
        await clock.waitUntilSleeping()
        #expect(manager.isRamping)
        for _ in 0..<PowerConfig.default.softDimSteps {
            await clock.waitUntilSleeping()
            clock.advanceOne()
        }
        await ramp.value
        #expect(!manager.isRamping)
    }
}
