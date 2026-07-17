# Phase 0 Research: Onboarding Welcome Overhaul

All decisions below are settled — no `NEEDS CLARIFICATION` remains. Each records what was chosen,
why, and what was rejected, grounded in the existing code (verified 2026-07-17).

## R1 — QR capture technology

**Decision**: `AVFoundation` `AVCaptureMetadataOutput` with `metadataObjectTypes = [.qr]`, wrapped
in a `UIViewControllerRepresentable` (`QRScannerView`), one shot: on the first recognised code the
session stops and the decoded `stringValue` is handed back.

**Rationale**: QR-only, minimal, universally available on the iOS 17 floor with no device-capability
branching; a single delegate callback yields the string. It is the least code for a one-shot "read
a link" interaction and keeps the camera surface tiny (isolatable behind the seam, R2).

**Alternatives considered**: VisionKit `DataScannerViewController` — nicer built-in guidance UI, but
iOS 16+ *and* gated by `isSupported`/`isAvailable` (extra device branching) for marginal gain on a
one-shot scan. Vision `VNDetectBarcodesRequest` over a custom capture pipeline — more control, far
more boilerplate, unwarranted for QR-only. Both rejected as heavier than the need.

## R2 — The `CodeScanning` seam (keeping AVFoundation out of the tested logic)

**Decision**: A small protocol in OnboardingKit (Foundation-only) abstracting "produce a decoded
string": the app-target `QRScannerView` is the real implementation; a fake supplies scripted strings
in host tests. The decoded string is routed through `ScannedShareLink.validate` (R3), never through
bespoke per-scan logic.

**Rationale**: Constitution II. The camera is untestable on the host; everything downstream of "we
got a string" must be. This mirrors the house pattern — PhotoKit behind `PHKitGateway`, `UIScreen`
outside PowerKit. FR-220-12 is satisfied because the parse/route path is exercised by feeding the
fake, no camera involved.

**Alternatives considered**: Putting AVFoundation directly in the view with no seam — rejected: it
would leave the scanned-code handling untestable and violate II.

## R3 — Scanned link == typed link (reuse, don't fork)

**Decision**: Add a pure `ScannedShareLink.validate(_ decoded: String) -> Result<ParsedSharedLink,
InvalidCodeReason>` that wraps the existing `SharedLinkURL.parse` (HTTPS-only; slug after `/s/`,
last-segment fallback). A valid result is handed to the **same** `SourceLibraryViewModel`
resolve-first / password-when-needed path that manual entry uses; an invalid result surfaces a calm
"that isn't an Immich share link" message with nothing persisted and no network call.

**Rationale**: FR-220-04/06 require scanned and typed links to be indistinguishable downstream and
invalid codes rejected client-side. Reusing `SharedLinkURL.parse` and the existing resolver means
the only new logic is the thin validator — small, host-tested, and automatically consistent with the
typed path (and its dedupe, R6).

**Alternatives considered**: Resolving the scanned URL through a new code path — rejected: divergence
risk and duplicate validation.

## R4 — iCloud path routing and the new step

**Decision**: `choosePath(.photoLibrary)` routes to a new `OnboardingStep.photoLibrarySetup`, which
renders the **reused** `PhotoAlbumPickerView`; on album selection the source is added via
`SourceLibraryViewModel.addPhotoLibrarySource` and onboarding calls `finish()` → `.done` (straight
to the slideshow). `canGoBack`/`back` treat `.photoLibrarySetup` like `.sharedLinkSetup` — a Back
that folds to `.choice`.

**Rationale**: The clarified behaviour is "iCloud lands straight in the slideshow" — the shared-link-
only lowest-friction shape, not the server branch's `.source`→`.confirm`. A dedicated step avoids
dragging the connection-scoped `.source` step (which assumes `submitConnection` ran). `finish()`
already no-ops its `.album` config-write for a `.photoLibrary` active source (verified: the `if case
.album` guard is skipped), so no change to `finish()` is needed.

**Alternatives considered**: Reusing `.source` with only the Photos tab — rejected: `.source`
presumes a validated connection and pulls in album/shared-link tabs and `.confirm`, contradicting
the connectionless, straight-to-slideshow intent.

## R5 — Startup parity for a connectionless iCloud-only install

**Decision**: No change required. `StartupGate.initialStep()` already returns `.done` for an active
`.photoLibrary` source with no Immich connection (900, R5 — verified at
`Packages/OnboardingKit/Sources/OnboardingKit/StartupGate.swift`).

**Rationale**: US1 acceptance #5 (relaunch routes straight to the slideshow with no re-onboarding) is
satisfied by existing, tested behaviour. A host test in this feature asserts the parity explicitly so
it is pinned against regression.

## R6 — Duplicate / already-present scanned link

**Decision**: Route scanned links through the same add path that manual entry and the Share Sheet
use, inheriting the existing 210 dedupe — a link already in the library switches to the existing
source rather than creating a duplicate.

**Rationale**: FR-220-04's "identical downstream" makes dedupe automatic; no new dedupe logic.

## R7 — Where the "Scan QR" affordance lives (scope discipline)

**Decision**: Add Scan QR to the **onboarding** shared-link entry (`SharedLinkSetupView`) only. The
reusable Settings add-source form (`SharedLinkAddForm`) is left unchanged in this feature.

**Rationale**: The spec is welcome-screen-only (FR-220-07); surfacing QR in Settings would change the
downstream/Settings surface. Adding QR to Settings is a natural, low-risk follow-up recorded in the
spec's Roadmap, not this slice. Keeps the blast radius on the welcome path.

**Alternatives considered**: Putting Scan QR in the shared `SharedLinkAddForm` so Settings gets it
"for free" — rejected for this slice as an unrequested scope expansion; revisit later.

## R8 — Camera permission & no-camera handling

**Decision**: Before presenting the scanner, check `AVCaptureDevice.authorizationStatus(for: .video)`
and request when `.notDetermined`. On `.denied`/`.restricted`, or when no capture device exists, show
a one-line calm explanation and keep the manual link field fully usable — Scan QR is an accelerator,
never the only way in (FR-220-05, SC-220-05). The `NSCameraUsageDescription` string states the camera
is used only to read a shared-album QR code.

**Rationale**: Constitution V — design within the granted capability; never dead-end setup. Parity
with how 900 treats denied Photos access as a calm state.

**Alternatives considered**: Blocking the shared-link path on camera access — rejected: it would
strand users who decline the camera or lack one.
