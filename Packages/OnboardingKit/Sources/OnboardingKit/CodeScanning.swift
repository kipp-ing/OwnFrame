import Foundation

/// Produces a decoded string from a scanned code (e.g. a QR code) for the shared-link
/// onboarding path (220). This is a Foundation-only seam — no `AVFoundation` — so the view
/// model and its tests never touch the camera directly; the concrete, camera-backed
/// conformance lives in the app target. A decoded string is meant to flow straight into
/// `ScannedShareLink.validate(_:)`.
///
/// A host test can conform a fake to this protocol and script its `scan()` return values
/// (e.g. one call per attempt, or an async sequence of scripted strings) to drive the view
/// model without a camera.
public protocol CodeScanning: Sendable {
    /// Scans until a code is decoded and returns its raw string payload, or `nil` if
    /// scanning ended without one (e.g. the user dismissed the scanner).
    func scan() async -> String?
}
