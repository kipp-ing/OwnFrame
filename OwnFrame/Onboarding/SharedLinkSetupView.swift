//
//  SharedLinkSetupView.swift
//  OwnFrame
//
//  Shared-link-only onboarding (210, US1): the lowest-friction path. Paste a link and
//  Start — the link is resolved first and a password is asked for **only** when the
//  server reports one is required. On success the link becomes the active source (no API
//  key) and onboarding finishes straight to the slideshow. Drives the SourceLibraryViewModel
//  two-phase resolve engine and the OnboardingViewModel's completion.
//

import OnboardingKit
import SwiftUI

struct SharedLinkSetupView: View {
    let onboarding: OnboardingViewModel
    @Bindable var sourceLibrary: SourceLibraryViewModel

    @State private var urlText: String
    @State private var passwordText = ""
    @State private var showPasswordPrompt = false
    @State private var qrScanner: QRScanner?

    /// `prefill` seeds the link field — used when a link is shared into the app while it
    /// is still unconfigured (210, US2 → `IncomingSharedLink.prefillOnboarding`).
    init(onboarding: OnboardingViewModel, sourceLibrary: SourceLibraryViewModel, prefill: String = "") {
        self.onboarding = onboarding
        self.sourceLibrary = sourceLibrary
        _urlText = State(initialValue: prefill)
    }

    var body: some View {
        Form {
            Section {
                Text("Set up a slideshow from just an Immich link — no account or API key needed.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("onboarding.sharedLink.description")
            }

            Section {
                TextField("https://host/s/slug", text: $urlText)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .keyboardType(.URL)
                    .disabled(isResolving)
                    .accessibilityIdentifier("onboarding.sharedLink.url")

                Button {
                    startScan()
                } label: {
                    Label("Scan QR", systemImage: "qrcode.viewfinder")
                }
                .disabled(isResolving)
                .accessibilityIdentifier("onboarding.sharedLink.scan")
            } header: {
                Text("Immich link")
            } footer: {
                Text("Paste the Immich link someone sent you, or scan its QR code. You'll only be asked for a password if the link needs one.")
            }

            if !showPasswordPrompt, case let .error(message) = sourceLibrary.addState {
                Section {
                    Label(message, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.red)
                        .accessibilityIdentifier("onboarding.sharedLink.error")
                }
            }

            Section {
                Button {
                    start()
                } label: {
                    HStack {
                        Text("Start slideshow")
                        if isResolving {
                            Spacer()
                            ProgressView()
                        }
                    }
                }
                .disabled(isStartDisabled)
                .accessibilityIdentifier("onboarding.sharedLink.start")
            }
        }
        .navigationTitle("Immich link")
        .onAppear { sourceLibrary.resetSharedLinkAdd() }
        .sheet(isPresented: $showPasswordPrompt, onDismiss: { passwordText = "" }) {
            passwordPrompt
        }
        // `item:`, not `isPresented:` + `if let` — with the Bool, the cover's content read a
        // stale `qrScanner` (still nil), rendered empty and black, and its `.task` never ran,
        // so the camera was never even requested (issue #82, found on device 2026-09-25).
        .fullScreenCover(item: $qrScanner) { scanner in
            QRScannerView(scanner: scanner)
                .task { await driveScan(scanner) }
        }
    }

    private var isResolving: Bool {
        if case .resolving = sourceLibrary.addState { return true }
        return false
    }

    private var isStartDisabled: Bool {
        isResolving || urlText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Phase 1: resolve the pasted link. `.needsPassword` opens the prompt; `.resolved`
    /// makes the link active and finishes onboarding; `.error` is shown inline.
    private func start() {
        Task {
            await sourceLibrary.resolveSharedLink(urlString: urlText, label: "")
            switch sourceLibrary.addState {
            case .needsPassword:
                showPasswordPrompt = true
            case .resolved:
                onboarding.finish()
            default:
                break
            }
        }
    }

    /// Presents the camera QR scanner. Only creates the scanner and requests the cover — the
    /// scan itself starts from `driveScan(_:)`, run via `.task` on the presented cover's
    /// content (see the `.fullScreenCover` below), never from here (issue #82).
    private func startScan() {
        sourceLibrary.resetSharedLinkAdd()
        let scanner = QRScanner()
        qrScanner = scanner
    }

    /// Routes a decoded code through the same resolve-first flow `start()` uses (220,
    /// FR-220-04) — `addScannedSharedLink` calls `scanner.scan()` itself, so this drives the
    /// whole scan, not just its result. A cancelled scan (dismiss, or no usable
    /// camera/permission) is a silent no-op that leaves manual entry untouched; an invalid
    /// code shows the same inline error surface `start()` uses, via `addState`.
    ///
    /// Run via `.task` on the presented `QRScannerView`, not fired from `startScan()`:
    /// `scan()`'s first suspension point requests camera permission,
    /// which shows a system alert — starting that race against the `.fullScreenCover`
    /// transition still animating in stalled the cover on a black screen after granting
    /// access (issue #82). `.task` only runs once the cover has actually finished presenting.
    private func driveScan(_ scanner: QRScanner) async {
        await sourceLibrary.addScannedSharedLink(using: scanner, label: "")
        // Camera denied or missing: the cover stays on its fallback until Done (SC-220-05).
        guard !scanner.showsFallback else { return }
        qrScanner = nil
        switch sourceLibrary.addState {
        case .needsPassword:
            showPasswordPrompt = true
        case .resolved:
            onboarding.finish()
        default:
            break
        }
    }

    /// Phase 2: confirm a password for a protected link. Success dismisses the prompt and
    /// finishes onboarding; a wrong password keeps the prompt open with the error shown.
    private func confirmPassword() {
        Task {
            await sourceLibrary.confirmSharedLinkPassword(passwordText)
            if case .resolved = sourceLibrary.addState {
                showPasswordPrompt = false
                onboarding.finish()
            }
        }
    }

    private var passwordPrompt: some View {
        NavigationStack {
            Form {
                Section {
                    AppSecureField("Password", text: $passwordText)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .disabled(isResolving)
                        .accessibilityIdentifier("onboarding.sharedLink.password")
                } header: {
                    Text("Password required")
                } footer: {
                    Text("This Immich link is password-protected. Enter the password to continue.")
                }

                if case let .error(message) = sourceLibrary.addState {
                    Section {
                        Label(message, systemImage: "exclamationmark.triangle")
                            .foregroundStyle(.red)
                            .accessibilityIdentifier("onboarding.sharedLink.password.error")
                    }
                }

                Section {
                    Button {
                        confirmPassword()
                    } label: {
                        HStack {
                            Text("Continue")
                            if isResolving {
                                Spacer()
                                ProgressView()
                            }
                        }
                    }
                    .disabled(passwordText.isEmpty || isResolving)
                    .accessibilityIdentifier("onboarding.sharedLink.password.continue")
                }
            }
            .navigationTitle("Password")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        showPasswordPrompt = false
                        sourceLibrary.resetSharedLinkAdd()
                    }
                    .accessibilityIdentifier("onboarding.sharedLink.password.cancel")
                }
            }
        }
        .presentationDetents([.medium])
    }
}
