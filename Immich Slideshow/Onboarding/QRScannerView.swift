//
//  QRScannerView.swift
//  Immich Slideshow
//
//  Camera-backed QR scanner for the shared-link onboarding path (220, T012). This is the
//  ONLY file in the app that imports `AVFoundation` — `QRScanner` conforms to
//  `OnboardingKit.CodeScanning` so `SourceLibraryViewModel.addScannedSharedLink(using:label:)`
//  (the already-tested routing, see ScannedLinkRoutingTests) can drive it without the view
//  model or its tests ever touching the camera. `QRScannerView` renders the live preview,
//  a Cancel affordance, and a calm fallback when the camera is unavailable or access is
//  denied — the fallback simply dismisses back to manual entry (SharedLinkSetupView keeps
//  the URL field fully usable underneath).
//

import AVFoundation
import Observation
import OnboardingKit
import SwiftUI

// AVFoundation predates Swift's Sendable audit, so `AVCaptureSession` isn't marked Sendable —
// but Apple documents `startRunning()`/`stopRunning()` as safe (indeed expected) to call off
// the main thread, which is exactly the only thing this file dispatches to a background queue.
// `@unchecked Sendable` records that as a deliberate, reviewed choice rather than a race.
extension AVCaptureSession: @unchecked @retroactive Sendable {}

/// Owns the capture session and bridges the metadata-output delegate callback to a single
/// `async` result, conforming to `CodeScanning` so it drops straight into
/// `addScannedSharedLink(using:label:)`. Uses `@Observable` (Observation), not Combine's
/// `ObservableObject` — the latter's synthesized `objectWillChange` witness doesn't play well
/// with this project's `NSObject` + default-`@MainActor`-isolation combination (required here
/// since `AVCaptureMetadataOutputObjectsDelegate` is an `@objc` protocol).
@MainActor
@Observable
final class QRScanner: NSObject, CodeScanning {
    enum State: Equatable {
        case idle
        case permissionDenied
        case noCamera
        case scanning
    }

    private(set) var state: State = .idle

    // None of these drive SwiftUI directly (only `state` does) — `@ObservationIgnored` also
    // sidesteps an `@Observable`-macro/`lazy` interaction issue on `previewLayer` below.
    @ObservationIgnored private let session = AVCaptureSession()
    @ObservationIgnored private let metadataQueue = DispatchQueue(label: "immichslideshow.qrscanner.metadata")
    @ObservationIgnored private var continuation: CheckedContinuation<String?, Never>?
    @ObservationIgnored private var didResume = false
    // Set by `cancel()`. `scan()` has two suspension points (the permission prompt and the
    // metadata-decode continuation) where a tap on Cancel can land before the continuation
    // exists; without this flag that cancel would be dropped (nothing to resume yet) and the
    // continuation created afterwards would then never be resumed, hanging forever.
    @ObservationIgnored private var cancelRequested = false

    /// The live preview layer for `QRScannerView` to host. Created lazily against `session`
    /// so it exists even before `scan()` has configured/started the session.
    @ObservationIgnored lazy var previewLayer: AVCaptureVideoPreviewLayer = {
        let layer = AVCaptureVideoPreviewLayer(session: session)
        layer.videoGravity = .resizeAspectFill
        return layer
    }()

    /// Scans until a QR code is decoded and returns its raw string payload, or `nil` if
    /// scanning ended without one (permission denied, no camera, or the view was dismissed
    /// via `cancel()`). Resumes its continuation exactly once, guarded by `didResume`.
    func scan() async -> String? {
        didResume = false
        cancelRequested = false

        let authStatus = AVCaptureDevice.authorizationStatus(for: .video)
        let granted: Bool
        switch authStatus {
        case .authorized:
            granted = true
        case .notDetermined:
            granted = await AVCaptureDevice.requestAccess(for: .video)
        case .denied, .restricted:
            granted = false
        @unknown default:
            granted = false
        }

        // Cancelled while the permission prompt (or the OS's own async dispatch of it) was
        // in flight — no continuation exists yet, so bail out here instead of proceeding to
        // create one that would never be resumed.
        guard !cancelRequested else { return nil }

        guard granted else {
            state = .permissionDenied
            return nil
        }

        guard let device = AVCaptureDevice.default(for: .video),
              let input = try? AVCaptureDeviceInput(device: device) else {
            state = .noCamera
            return nil
        }

        session.beginConfiguration()
        guard session.canAddInput(input) else {
            session.commitConfiguration()
            state = .noCamera
            return nil
        }
        session.addInput(input)

        let output = AVCaptureMetadataOutput()
        guard session.canAddOutput(output) else {
            session.commitConfiguration()
            state = .noCamera
            return nil
        }
        session.addOutput(output)
        // The delegate must be set, and the output added to the session, before the
        // supported metadata object types can be restricted to QR only.
        output.setMetadataObjectsDelegate(self, queue: metadataQueue)
        output.metadataObjectTypes = [.qr]
        session.commitConfiguration()

        state = .scanning

        return await withCheckedContinuation { continuation in
            // The closure below runs synchronously (no suspension since the prior line) so
            // there is no further race window between this check and `self.continuation`
            // being set.
            guard !cancelRequested else {
                didResume = true
                state = .idle
                continuation.resume(returning: nil)
                return
            }
            self.continuation = continuation
            let session = self.session
            Task.detached(priority: .userInitiated) {
                session.startRunning()
            }
        }
    }

    /// Ends scanning without a code — the view was dismissed (Cancel tapped, or the sheet
    /// was swiped away). Safe to call before the continuation exists (see `cancelRequested`)
    /// and a no-op if the scan already resumed (a code was decoded, or permission/camera
    /// setup already failed synchronously).
    func cancel() {
        cancelRequested = true
        resume(with: nil)
    }

    private func resume(with value: String?) {
        guard !didResume else { return }
        didResume = true
        state = .idle
        let session = self.session
        Task.detached(priority: .userInitiated) {
            session.stopRunning()
        }
        continuation?.resume(returning: value)
        continuation = nil
    }
}

extension QRScanner: AVCaptureMetadataOutputObjectsDelegate {
    nonisolated func metadataOutput(
        _ output: AVCaptureMetadataOutput,
        didOutput metadataObjects: [AVMetadataObject],
        from connection: AVCaptureConnection
    ) {
        guard let code = metadataObjects
            .compactMap({ $0 as? AVMetadataMachineReadableCodeObject })
            .first(where: { $0.type == .qr })?.stringValue
        else { return }

        Task { @MainActor in
            self.resume(with: code)
        }
    }
}

/// Full-bleed live camera preview for `QRScanner`, plus a Cancel control and a calm fallback
/// shown when the camera can't be used. Purely presentational — it does NOT call
/// `scanner.scan()` itself; the caller (`SharedLinkSetupView`) drives that indirectly by
/// awaiting `SourceLibraryViewModel.addScannedSharedLink(using: scanner, ...)`, so a decoded
/// code routes through the exact same resolve path a typed link uses. This view only reflects
/// `scanner.state` and lets the user cancel — either via the Cancel/Done control or by
/// dismissing the cover, both of which call `scanner.cancel()`. `cancel()` is safe to call
/// more than once (idempotent past the first resume).
struct QRScannerView: View {
    let scanner: QRScanner

    var body: some View {
        ZStack {
            switch scanner.state {
            case .permissionDenied, .noCamera:
                fallback
            default:
                CameraPreview(scanner: scanner)
                    .ignoresSafeArea()
                cancelOverlay
            }
        }
        // Covers system-driven dismissal too (e.g. an interactive swipe-down on the cover)
        // so `scan()`'s continuation — and the camera session — never leak/keep running.
        .onDisappear { scanner.cancel() }
    }

    private var cancelOverlay: some View {
        VStack {
            HStack {
                Spacer()
                Button {
                    scanner.cancel()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title)
                        .foregroundStyle(.white, .black.opacity(0.6))
                }
                .padding()
                .accessibilityLabel("Cancel")
                .accessibilityIdentifier("onboarding.sharedLink.scan.cancel")
            }
            Spacer()
        }
    }

    private var fallback: some View {
        VStack(spacing: 16) {
            Image(systemName: "camera.fill")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            Text("Camera access is off. You can still paste the link below.")
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .accessibilityIdentifier("onboarding.sharedLink.scan.unavailable")
            Button("Done") {
                scanner.cancel()
            }
            .buttonStyle(.borderedProminent)
            .accessibilityIdentifier("onboarding.sharedLink.scan.cancel")
        }
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// Hosts `QRScanner.previewLayer` full-bleed, keeping its frame in sync with the view.
private struct CameraPreview: UIViewRepresentable {
    let scanner: QRScanner

    func makeUIView(context: Context) -> PreviewUIView {
        let view = PreviewUIView()
        view.previewLayer = scanner.previewLayer
        view.layer.addSublayer(scanner.previewLayer)
        return view
    }

    func updateUIView(_ uiView: PreviewUIView, context: Context) {
        uiView.previewLayer = scanner.previewLayer
    }

    final class PreviewUIView: UIView {
        var previewLayer: AVCaptureVideoPreviewLayer? {
            didSet { setNeedsLayout() }
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            previewLayer?.frame = bounds
        }
    }
}
