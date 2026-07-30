import CoreGraphics
import Foundation
import ImageIO

/// The bundled sample photo behind the unlock screen's live Ken Burns demo (FR-1100-09).
///
/// Bundled, not fetched: the unlock screen can be presented from onboarding, before any photo
/// source exists, and must render identically there (`UnlockScreenView`'s contract). The photo
/// is a pre-cropped wide band (1800×540) so the tile shows the composed part of the frame at
/// every aspect the demo slot takes, and the file stays under 100 KB of bundle weight.
///
/// Loading goes through ImageIO so the same code serves iOS, tvOS, and the macOS host tests —
/// no UIKit. A `nil` return means the resource is missing from the bundle; the demo view then
/// degrades to its neutral placeholder instead of failing.
enum UnlockDemoMedia {

    static func cliffImage() -> CGImage? {
        guard
            let url = Bundle.module.url(forResource: "UnlockDemoCliff", withExtension: "jpg"),
            let source = CGImageSourceCreateWithURL(url as CFURL, nil)
        else { return nil }
        return CGImageSourceCreateImageAtIndex(source, 0, nil)
    }
}
