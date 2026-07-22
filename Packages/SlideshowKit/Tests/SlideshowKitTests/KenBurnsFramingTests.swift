import CoreGraphics
import SlideshowKit
import Testing
import ThemeKit

// Ken Burns must HONOR the active fit, not override it (FR-500-20 / SC-500-09, reconciling
// 300 FR-300-33 / SC-300-13). The old renderer forced `scaledToFill` and a diagonal pan the
// moment Ken Burns turned on, silently switching a Fitted photo to Fill and revealing
// background beyond the letterbox. The decision the SwiftUI renderers consume is extracted
// into `KenBurnsFraming` so this contract is testable on the host without a simulator:
// Fill pans and zooms as before; Fit stays letterboxed with a centered zoom (pan suppressed).

@Test func fitNeverFillsScreenRegardlessOfKenBurns() {
    // `fillsScreen` is now a pure function of fit only — Ken Burns does not enter into it —
    // so a Fitted photo stays fitted whether Ken Burns is on or off, and Fill fills.
    #expect(KenBurnsFraming.fillsScreen(fit: .fit) == false)
    #expect(KenBurnsFraming.fillsScreen(fit: .fill) == true)
}

@Test func fitSuppressesKenBurnsPan() {
    // Fit → centered zoom only: pan input is 0, so `pan * fraction` contributes no offset
    // and no background beyond the fitted letterbox is ever revealed — on either platform's
    // base pan (16 pt iPad, 24 pt tvOS).
    #expect(KenBurnsFraming.pan(fit: .fit, basePan: 16) == 0)
    #expect(KenBurnsFraming.pan(fit: .fit, basePan: 24) == 0)
}

@Test func fillPansByTheBasePan() {
    // Fill → unchanged motion: the platform's full pan magnitude passes straight through.
    #expect(KenBurnsFraming.pan(fit: .fill, basePan: 16) == 16)
    #expect(KenBurnsFraming.pan(fit: .fill, basePan: 24) == 24)
}
