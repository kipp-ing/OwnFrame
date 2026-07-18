import Observation
import PowerKit
import UIKit

// tvOS `ScreenControlling` (FR-1000-07). tvOS exposes no panel-brightness API, so
// "brightness" is a *software dim*: the stored value (0...1) drives a black compositing
// overlay the slideshow paints over the photo (opacity = 1 - brightness, via
// `SoftwareDimModel`). On self-emissive panels this genuinely lowers emitted light.
// The idle-timer maps to the tvOS idle timer (screensaver/sleep prevention while the app
// is frontmost) — `UIApplication.isIdleTimerDisabled` exists on tvOS. Kept in the tvOS
// app target so PowerKit stays UIKit-free (constitution II); PowerManager drives it
// unchanged through the two-property seam.
@MainActor
@Observable
final class SoftwareDimScreenController: ScreenControlling {
    /// Software-dim level, 1.0 = no dim (full brightness), near-0 = near-black.
    var brightness: Double = 1.0

    var isIdleTimerDisabled: Bool {
        get { UIApplication.shared.isIdleTimerDisabled }
        set { UIApplication.shared.isIdleTimerDisabled = newValue }
    }

    /// Opacity of the black dim overlay the slideshow composites over the current photo.
    /// Observed by the tvOS slideshow host so a brightness change repaints live.
    var dimOverlayOpacity: Double {
        SoftwareDimModel.overlayOpacity(forBrightness: brightness)
    }
}
