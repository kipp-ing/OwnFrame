//
//  QRScannerView.swift
//  OwnFrame
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
import os
import PurchaseKit
import SwiftUI

// AVFoundation predates Swift's Sendable audit, so `AVCaptureSession` isn't marked Sendable —
// but Apple documents `startRunning()`/`stopRunning()` as safe (indeed expected) to call off
// the main thread, which is exactly the only thing this file dispatches to a background queue.
// `@unchecked Sendable` records that as a deliberate, reviewed choice rather than a race.
extension AVCaptureSession: @unchecked @retroactive Sendable {}

/// Retries a throwing step a few times with a short pause. The camera input can fail right
/// after the person taps "Allow", or right after OwnFrame comes back to the foreground, and
/// then succeed a moment later (Framepad 2026-09-29: "not allowed" on the first try, flawless
/// on the second). Returns `nil` once `attempts` are spent or `shouldStop` turns true.
enum CameraStartRetry {
    @MainActor
    static func firstSuccess<T>(
        attempts: Int,
        delay: Duration,
        shouldStop: () -> Bool = { false },
        onFailure: (Int, any Error) -> Void = { _, _ in },
        _ attempt: () throws -> T
    ) async -> T? {
        for number in 1...max(attempts, 1) {
            do {
                return try attempt()
            } catch {
                onFailure(number, error)
                if shouldStop() || number == attempts { return nil }
                try? await Task.sleep(for: delay)
                if shouldStop() { return nil }
            }
        }
        return nil
    }
}

/// Owns the capture session and bridges the metadata-output delegate callback to a single
/// `async` result, conforming to `CodeScanning` so it drops straight into
/// `addScannedSharedLink(using:label:)`. Uses `@Observable` (Observation), not Combine's
/// `ObservableObject` — the latter's synthesized `objectWillChange` witness doesn't play well
/// with this project's `NSObject` + default-`@MainActor`-isolation combination (required here
/// since `AVCaptureMetadataOutputObjectsDelegate` is an `@objc` protocol).
@MainActor
@Observable
final class QRScanner: NSObject, CodeScanning, Identifiable {
    enum State: Equatable {
        case idle
        case permissionDenied
        case noCamera
        case scanning
    }

    private(set) var state: State = .idle

    // Diagnostics for on-device scanner reports (Framepad 2026-09-28: closed after "Allow",
    // then an "invalid link" on the next try). Never logs a decoded payload beyond its host —
    // the path carries the share key.
    @ObservationIgnored private let log = Logger(subsystem: "ing.kipp.Immich-Slideshow", category: "QRScanner")

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
    @ObservationIgnored private var rotationCoordinator: AVCaptureDevice.RotationCoordinator?
    @ObservationIgnored private var rotationObservation: NSKeyValueObservation?
    @ObservationIgnored private var lifecycleObservers: [any NSObjectProtocol] = []

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
    /// The scan ended on the calm fallback (camera denied or missing). The cover must then
    /// stay up until the user taps Done — dismissing it with the scan's result hid the
    /// fallback before it could be read (SC-220-05, found on device 2026-09-25).
    var showsFallback: Bool { state == .permissionDenied || state == .noCamera }

    func scan() async -> String? {
        // A second scan on the same scanner (the cover's `.task` restarted) takes over from the
        // first instead of failing against the session the first one already configured —
        // that failure read as "Camera access is off" (Framepad 2026-09-29).
        if let previous = continuation {
            continuation = nil
            previous.resume(returning: nil)
        }
        didResume = false
        cancelRequested = false

        let authStatus = AVCaptureDevice.authorizationStatus(for: .video)
        log.notice("scan: camera authorization \(authStatus.rawValue, privacy: .public)")
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
        log.notice("scan: access granted \(granted, privacy: .public), cancel requested \(self.cancelRequested, privacy: .public)")
        guard !cancelRequested else { return nil }

        guard granted else {
            state = .permissionDenied
            return nil
        }

        guard await configureSessionIfNeeded() else {
            guard !cancelRequested else { return nil }
            state = .noCamera
            return nil
        }
        guard !cancelRequested else { return nil }

        state = .scanning
        log.notice("scan: session configured, starting")

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
            observeSessionLifecycle()
            let session = self.session
            Task.detached(priority: .userInitiated) {
                session.startRunning()
            }
        }
    }

    /// Adds the camera input and the QR output once per scanner. A session that already has
    /// them (an earlier `scan()` on this scanner) is reused as is.
    private func configureSessionIfNeeded() async -> Bool {
        if !session.inputs.isEmpty && !session.outputs.isEmpty { return true }
        await waitUntilActive()
        guard let device = AVCaptureDevice.default(for: .video) else {
            log.error("scan: no video device")
            return false
        }
        let input = await CameraStartRetry.firstSuccess(
            attempts: 6,
            delay: .milliseconds(300),
            shouldStop: { [weak self] in self?.cancelRequested ?? true },
            onFailure: { [log] attempt, error in
                let nsError = error as NSError
                log.error("scan: camera input attempt \(attempt, privacy: .public) failed: \(nsError.domain, privacy: .public) \(nsError.code, privacy: .public)")
            }
        ) {
            try AVCaptureDeviceInput(device: device)
        }
        guard let input else { return false }

        session.beginConfiguration()
        defer { session.commitConfiguration() }
        guard session.canAddInput(input) else {
            log.error("scan: session refused the camera input")
            return false
        }
        session.addInput(input)

        let output = AVCaptureMetadataOutput()
        guard session.canAddOutput(output) else {
            log.error("scan: session refused the metadata output")
            session.removeInput(input)
            return false
        }
        session.addOutput(output)
        // The delegate must be set, and the output added to the session, before the
        // supported metadata object types can be restricted to QR only.
        output.setMetadataObjectsDelegate(self, queue: metadataQueue)
        output.metadataObjectTypes = [.qr]
        startRotationTracking(for: device)
        return true
    }

    /// Right after the permission alert closes, or after a return from another app, the app
    /// is still inactive for a moment and the camera refuses to start. Waits up to ~2 s.
    private func waitUntilActive() async {
        for _ in 0..<20 where UIApplication.shared.applicationState != .active {
            try? await Task.sleep(for: .milliseconds(100))
        }
    }

    /// Keeps the preview upright in every iPad orientation. Without it the picture was turned
    /// sideways against the room (Framepad 2026-09-29: "weirdly mirrored").
    private func startRotationTracking(for device: AVCaptureDevice) {
        let coordinator = AVCaptureDevice.RotationCoordinator(device: device, previewLayer: previewLayer)
        rotationCoordinator = coordinator
        applyPreviewRotation(coordinator.videoRotationAngleForHorizonLevelPreview)
        rotationObservation = coordinator.observe(\.videoRotationAngleForHorizonLevelPreview, options: [.new]) { [weak self] coordinator, _ in
            let angle = coordinator.videoRotationAngleForHorizonLevelPreview
            Task { @MainActor in self?.applyPreviewRotation(angle) }
        }
    }

    private func applyPreviewRotation(_ angle: CGFloat) {
        guard let connection = previewLayer.connection, connection.isVideoRotationAngleSupported(angle) else { return }
        connection.videoRotationAngle = angle
    }

    /// The system stops the session when OwnFrame leaves the foreground. If it has not come
    /// back by itself when the app is active again, start it here so the preview never stays dark.
    private func observeSessionLifecycle() {
        guard lifecycleObservers.isEmpty else { return }
        let center = NotificationCenter.default
        let restart: @Sendable (Notification) -> Void = { [weak self] _ in
            Task { @MainActor in self?.restartIfStalled() }
        }
        lifecycleObservers = [
            center.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main, using: restart),
            center.addObserver(forName: AVCaptureSession.runtimeErrorNotification, object: session, queue: .main, using: restart),
            center.addObserver(forName: AVCaptureSession.interruptionEndedNotification, object: session, queue: .main, using: restart)
        ]
    }

    private func restartIfStalled() {
        guard state == .scanning, !session.isRunning else { return }
        log.notice("scan: session stopped while scanning, restarting")
        let session = self.session
        Task.detached(priority: .userInitiated) {
            session.startRunning()
        }
    }

    /// Ends scanning without a code — the view was dismissed (Cancel tapped, or the sheet
    /// was swiped away). Safe to call before the continuation exists (see `cancelRequested`)
    /// and a no-op if the scan already resumed (a code was decoded, or permission/camera
    /// setup already failed synchronously).
    func cancel() {
        if !didResume { log.notice("scan: cancel while \(String(describing: self.state), privacy: .public)") }
        cancelRequested = true
        resume(with: nil)
    }

    private func resume(with value: String?) {
        guard !didResume else { return }
        if let value {
            let host = URL(string: value)?.host ?? "<not a URL>"
            log.notice("scan: decoded a code for host \(host, privacy: .public), \(value.count, privacy: .public) chars")
        }
        didResume = true
        state = .idle
        lifecycleObservers.forEach(NotificationCenter.default.removeObserver)
        lifecycleObservers = []
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
    @Environment(\.dismiss) private var dismiss

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

    // Two literals, not a ternary: `Text(cond ? "a" : "b")` takes a plain String and skips
    // the String Catalog.
    private var fallbackMessage: Text {
        if scanner.state == .permissionDenied {
            Text("Camera access is off. You can still paste the link below.")
        } else {
            Text("The camera couldn't start. Try again, or paste the link below.")
        }
    }

    private var fallback: some View {
        VStack(spacing: 16) {
            Image(systemName: "camera.fill")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
            fallbackMessage
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .accessibilityIdentifier("onboarding.sharedLink.scan.unavailable")
            Button("Done") {
                scanner.cancel()
                dismiss() // the scan already returned, so nothing else closes the cover
            }
            .buttonStyle(.accentProminent)
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
