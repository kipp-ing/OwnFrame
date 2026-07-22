import CoreGraphics
import ThemeKit

/// Pure, host-testable framing decisions for the Ken Burns effect, extracted out of the
/// SwiftUI renderers so the "Ken Burns honors Fit" contract (FR-500-20 / SC-500-09,
/// reconciling 300 FR-300-33 / SC-300-13) can be unit-tested without a simulator.
///
/// Ken Burns previously forced `scaledToFill` and a diagonal pan regardless of the user's
/// fit choice, silently switching a Fitted photo to Fill and revealing background beyond the
/// letterbox. It now honors the active fit: **Fill** pans and zooms as before; **Fit** keeps
/// the whole photo visible (letterboxed) and confines its motion to a centered zoom with the
/// pan suppressed — the scale envelope (`KenBurnsDrift`) is identical in both cases.
public enum KenBurnsFraming {
    /// Whether the renderer should fill the screen (`scaledToFill`) for the given fit.
    /// Ken Burns no longer participates in this decision, so a Fitted photo stays fitted
    /// (letterboxed) whether or not Ken Burns is on.
    public static func fillsScreen(fit: ImageFit) -> Bool {
        fit == .fill
    }

    /// The Ken Burns pan magnitude to hand to `.kenBurnsMotion(pan:)`, given the platform's
    /// base pan (16 pt on iPad, 24 pt on tvOS). **Fill** pans by `basePan` (unchanged motion);
    /// **Fit** suppresses the pan (`0`) so the zoom stays centered and reveals no background
    /// beyond the fitted letterbox.
    public static func pan(fit: ImageFit, basePan: CGFloat) -> CGFloat {
        fit == .fill ? basePan : 0
    }
}
