import Testing
@testable import PowerKit

@MainActor
@Suite
struct PowerManagerTests {
    // @covers FR-400-01
    @Test
    func activateKeepsScreenAwake() {
        let screen = FakeScreenController()
        let manager = PowerManager(screen: screen, clock: ManualClock())

        manager.activate()

        #expect(screen.isIdleTimerDisabled == true)
        #expect(manager.isKeepingAwake == true)
    }

    // @covers FR-400-02, SC-400-02
    @Test
    func deactivateReleasesScreenAwake() {
        let screen = FakeScreenController()
        let manager = PowerManager(screen: screen, clock: ManualClock())

        manager.activate()
        manager.deactivate()

        #expect(screen.isIdleTimerDisabled == false)
        #expect(manager.isKeepingAwake == false)
    }

    // @covers FR-400-03, FR-400-04
    @Test
    func backgroundReleasesAwakeWithoutBrightnessWriteAndForegroundRestoresAwake() {
        let screen = FakeScreenController()
        let manager = PowerManager(screen: screen, clock: ManualClock())

        manager.activate()
        manager.didEnterBackground()

        #expect(screen.isIdleTimerDisabled == false)
        #expect(manager.isKeepingAwake == false)
        #expect(screen.brightnessWrites.isEmpty)

        manager.willEnterForeground()

        #expect(screen.isIdleTimerDisabled == true)
        #expect(manager.isKeepingAwake == true)
        #expect(screen.brightnessWrites.isEmpty)
    }

    // @covers FR-400-10, FR-400-11, SC-400-05
    @Test
    func deactivateRestoresBaselineAfterBrightnessChange() async {
        let screen = FakeScreenController(brightness: 0.7)
        let manager = PowerManager(screen: screen, clock: ManualClock())

        manager.activate()
        await manager.setBrightness(0.1, animated: false)
        manager.deactivate()

        #expect(screen.brightnessWrites.last == 0.7)
    }

    // @covers FR-400-11
    @Test
    func deactivateDoesNotWriteBrightnessWhenUnchanged() {
        let screen = FakeScreenController(brightness: 0.7)
        let manager = PowerManager(screen: screen, clock: ManualClock())

        manager.activate()
        manager.deactivate()

        #expect(screen.brightnessWrites.isEmpty)
    }

    // @covers FR-400-02, SC-400-02
    @Test
    func repeatedActivationAndSceneTransitionsEndReleased() {
        let screen = FakeScreenController()
        let manager = PowerManager(screen: screen, clock: ManualClock())

        manager.activate()
        manager.activate()
        manager.didEnterBackground()
        manager.willEnterForeground()
        manager.didEnterBackground()
        manager.willEnterForeground()
        manager.deactivate()

        #expect(screen.isIdleTimerDisabled == false)
        #expect(manager.isKeepingAwake == false)
    }
}
