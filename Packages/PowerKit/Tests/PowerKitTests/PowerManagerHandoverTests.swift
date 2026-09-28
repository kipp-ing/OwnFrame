import Testing
@testable import PowerKit

/// Issue #91: a slideshow generation swap (a source switch) replaces the surface; the
/// outgoing view's disappear and the successor's appear hit the SAME PowerManager in an
/// order SwiftUI does not promise. The swap must neither snap a set brightness back to the
/// baseline nor drop the keep-awake hold — whichever order the two land in.
@MainActor
@Suite
struct PowerManagerHandoverTests {
    // @covers FR-400-01, FR-400-10
    @Test
    func handoverWithOldDisappearFirstKeepsLevelAndKeepAwake() async {
        let screen = FakeScreenController(brightness: 1.0)
        let manager = PowerManager(screen: screen, clock: ManualClock())
        manager.activate()
        await manager.setBrightness(0.25, animated: false)

        manager.handOver()
        manager.surfaceDisappeared() // outgoing surface
        manager.activate()           // successor

        #expect(screen.brightness == 0.25)
        #expect(screen.isIdleTimerDisabled == true)
        #expect(manager.isKeepingAwake == true)
        await manager.setBrightness(0.5, animated: false)
        #expect(screen.brightness == 0.5, "HA brightness must still apply after the swap")
    }

    // @covers FR-400-01, FR-400-10
    @Test
    func handoverWithSuccessorAppearFirstKeepsLevelAndKeepAwake() async {
        let screen = FakeScreenController(brightness: 1.0)
        let manager = PowerManager(screen: screen, clock: ManualClock())
        manager.activate()
        await manager.setBrightness(0.25, animated: false)

        manager.handOver()
        manager.activate()           // successor
        manager.surfaceDisappeared() // outgoing surface

        #expect(screen.brightness == 0.25)
        #expect(screen.isIdleTimerDisabled == true)
        #expect(manager.isKeepingAwake == true)
        await manager.setBrightness(0.5, animated: false)
        #expect(screen.brightness == 0.5, "HA brightness must still apply after the swap")
    }

    // @covers FR-400-02, FR-400-11
    @Test
    func disappearWithoutHandoverIsAGenuineExit() async {
        let screen = FakeScreenController(brightness: 0.7)
        let manager = PowerManager(screen: screen, clock: ManualClock())
        manager.activate()
        await manager.setBrightness(0.1, animated: false)

        manager.surfaceDisappeared()

        #expect(screen.brightness == 0.7)
        #expect(screen.isIdleTimerDisabled == false)
        #expect(manager.isKeepingAwake == false)
    }

    // @covers FR-400-02, FR-400-11
    @Test
    func deactivateClearsAnUnconsumedHandover() async {
        // A swap while Settings covers the slideshow never fires the outgoing disappear, so
        // its hand-over stays unconsumed; the explicit teardown (reset) must clear it, or the
        // next genuine exit would be mistaken for a swap.
        let screen = FakeScreenController(brightness: 0.7)
        let manager = PowerManager(screen: screen, clock: ManualClock())
        manager.activate()
        manager.handOver()
        manager.deactivate()

        manager.activate()
        await manager.setBrightness(0.1, animated: false)
        manager.surfaceDisappeared()

        #expect(screen.brightness == 0.7)
        #expect(screen.isIdleTimerDisabled == false)
    }
}
