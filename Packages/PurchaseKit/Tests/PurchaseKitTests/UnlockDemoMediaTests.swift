import CoreGraphics
import Testing
@testable import PurchaseKit

// FR-1100-09 — the unlock screen's live Ken Burns demo runs on a bundled sample photo: the
// screen can be presented from onboarding, before any photo source exists, so the image must
// ship inside the package bundle. These tests pin that resource in place. The classic failure
// they guard against is silent: a manifest that forgets the resource still compiles, and the
// demo quietly degrades to the placeholder on every install.

@Test func demoCliffImageResolvesFromThePackageBundle() {
    #expect(UnlockDemoMedia.cliffImage() != nil)
}

@Test func demoCliffImageIsLandscapeAndSharpEnoughForTheDemoTile() throws {
    let image = try #require(UnlockDemoMedia.cliffImage())
    // The iOS tile shows a ~512 pt band at @2x (~1024 px), tvOS ~880 px at 1x, and the drift
    // zooms beyond 1×. 1200 px of width is the floor below which the demo turns visibly soft.
    #expect(image.width >= 1200)
    #expect(image.width > image.height)
}
