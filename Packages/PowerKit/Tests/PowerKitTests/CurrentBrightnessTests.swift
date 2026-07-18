import Testing
import PowerKit

// FR-1000-07: brightness is read through the `ScreenControlling` seam, never past it.
@MainActor
struct CurrentBrightnessTests {
    @Test func currentBrightnessReadsThroughSeam() {
        let screen = FakeScreenController(brightness: 0.42)
        let manager = PowerManager(screen: screen)
        #expect(manager.currentBrightness == 0.42)
    }

    @Test func currentBrightnessReflectsLaterSeamValue() {
        let screen = FakeScreenController(brightness: 0.5)
        let manager = PowerManager(screen: screen)
        screen.brightness = 0.9
        #expect(manager.currentBrightness == 0.9)
    }
}
