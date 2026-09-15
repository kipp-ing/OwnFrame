//
//  NewPhotosCardScrimTests.swift
//  OwnFrameTests
//
//  310 T036 (#60, FR-310-15): the new-photos card carries one in-shape dark layer (the soft-glass
//  tint color at `cardScrimOpacity`) so its white text stays at WCAG AA over a pure-white photo,
//  with the glass itself ignored. The floor is computed here, never hard-coded; the constant may
//  only move up from it after Jan's eyeball of the capture (T038).
//

import Foundation
import Testing
@testable import OwnFrame

struct NewPhotosCardScrimTests {

    // @covers FR-310-15
    @Test func cardScrimKeepsWhiteTextAtAAOverAPureWhitePhoto() {
        let ground = ContrastMath.composite(
            SoftGlass.tint, opacity: NewPhotosOverlayView.cardScrimOpacity, over: ContrastMath.white
        )
        let ratio = ContrastMath.contrastRatio(ContrastMath.white, ground)
        #expect(ratio >= 4.5, "card text over white: \(ratio):1")
    }

    /// Below iOS 26 the darker of tier tint and card scrim wins, so the two never stack; the card
    /// scrim must be the darker one or it would be a no-op there.
    @Test func cardScrimIsDarkerThanTheTierTint() {
        #expect(NewPhotosOverlayView.cardScrimOpacity > SoftGlass.tintOpacity)
    }
}
