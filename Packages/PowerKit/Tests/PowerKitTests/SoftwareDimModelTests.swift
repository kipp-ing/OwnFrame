import Testing
@testable import PowerKit

@Suite
struct SoftwareDimModelTests {
    @Test
    func fullBrightnessMeansNoOverlay() {
        #expect(SoftwareDimModel.overlayOpacity(forBrightness: 1.0) == 0.0)
    }

    @Test
    func zeroBrightnessMeansFullBlackOverlay() {
        #expect(SoftwareDimModel.overlayOpacity(forBrightness: 0.0) == 1.0)
    }

    @Test
    func halfBrightnessMeansHalfOverlay() {
        #expect(SoftwareDimModel.overlayOpacity(forBrightness: 0.5) == 0.5)
    }

    @Test
    func clampsBelowZeroToFullBlackOverlay() {
        // -0.3 clamps to brightness 0.0 -> fully opaque black overlay.
        #expect(SoftwareDimModel.overlayOpacity(forBrightness: -0.3) == 1.0)
    }

    @Test
    func clampsAboveOneToNoOverlay() {
        // 1.7 clamps to brightness 1.0 -> no overlay.
        #expect(SoftwareDimModel.overlayOpacity(forBrightness: 1.7) == 0.0)
    }

    @Test
    func monotonicNonIncreasingInBrightness() {
        let samples = [0.0, 0.1, 0.25, 0.5, 0.75, 0.9, 1.0]
        let opacities = samples.map { SoftwareDimModel.overlayOpacity(forBrightness: $0) }
        for index in 1..<opacities.count {
            #expect(opacities[index] <= opacities[index - 1])
        }
    }
}
