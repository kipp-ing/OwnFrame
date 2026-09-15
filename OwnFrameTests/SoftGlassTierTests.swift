//
//  SoftGlassTierTests.swift
//  OwnFrameTests
//
//  300 T003/T004 (#72, FR-300-34): the soft-glass tier and the eased edge scrims, pinned to the
//  design record `docs/design/quiet-glass-2026-07-18.html` (soft-glass CSS `rgba(24,24,27,.38)`,
//  scrim CSS stops, 26% band), plus the worst-case arithmetic: a white glyph over a pure-white
//  photo, under the scrim at the bars' position and inside the soft-glass tint, must reach the
//  3:1 icon threshold of FR-9000-07. Blur and the material's own darkening are ignored, so this
//  is a lower bound; the captures (T002/T009) are the visual gate.
//

import Foundation
import Testing
@testable import OwnFrame

struct SoftGlassTierTests {

    // @covers FR-300-34
    @Test func softGlassTintIsTheRecordsCSSTint() {
        // Jan, 2026-09-15: the record's CSS tint, not the implementation map's "≈ 0.2 black".
        #expect(SoftGlass.tint.red == 24.0 / 255)
        #expect(SoftGlass.tint.green == 24.0 / 255)
        #expect(SoftGlass.tint.blue == 27.0 / 255)
        #expect(SoftGlass.tintOpacity == 0.38)
    }

    @Test func scrimStopsAndBandMatchTheRecord() {
        #expect(ChromeScrim.stops.map(\.opacity) == [0.34, 0.18, 0.06, 0.0])
        #expect(ChromeScrim.stops.map(\.location) == [0.0, 0.40, 0.75, 1.0])
        #expect(ChromeScrim.bandFraction == 0.26)
    }

    @Test func scrimOpacityInterpolatesLinearlyBetweenStops() {
        #expect(ChromeScrim.opacity(at: 0) == 0.34)
        #expect(abs(ChromeScrim.opacity(at: 0.2) - 0.26) < 1e-9)
        #expect(ChromeScrim.opacity(at: 0.40) == 0.18)
        #expect(ChromeScrim.opacity(at: 1) == 0)
        #expect(ChromeScrim.opacity(at: 1.5) == 0)
    }

    /// Heights in points. The smallest iPad height is iPad mini in landscape; iPhone is checked in
    /// portrait. iPhone landscape (≈375 pt) lands at ≈2.75:1 under this model and is checked by
    /// capture only (Jan, 2026-09-15; `specs/300-slideshow/tasks.md` T004).
    // @covers FR-300-34
    @Test(arguments: [
        ("iPhone SE portrait", 667.0),
        ("iPad mini landscape", 744.0),
        ("iPad mini portrait", 1133.0),
    ])
    func whiteGlyphOverWhitePhotoReachesIconContrast(screen: String, height: Double) {
        let glyphCenter = Double(ChromeMetrics.barInset + ChromeMetrics.controlDiameter / 2)
        let scrim = ChromeScrim.opacity(at: glyphCenter / (height * ChromeScrim.bandFraction))

        let photoUnderScrim = ContrastMath.composite((0, 0, 0), opacity: scrim, over: ContrastMath.white)
        let ground = ContrastMath.composite(SoftGlass.tint, opacity: SoftGlass.tintOpacity, over: photoUnderScrim)

        let ratio = ContrastMath.contrastRatio(ContrastMath.white, ground)
        #expect(ratio >= 3.0, "\(screen): \(ratio):1")
    }
}
