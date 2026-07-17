# Phase 1 Data Model: Onboarding Welcome Overhaul

This feature adds almost no data — it extends two existing enums and introduces one pure value type
for scanned-code validation. No persisted shape changes. Source persistence, secret storage, and the
`Source`/`SourceKind`/`SourceLibrary` model are reused unchanged (120 / 110 / 900).

## Extended types

### `OnboardingPathChoice` (OnboardingKit) — third case

```
enum OnboardingPathChoice { case photoLibrary, sharedLink, server }   // was { sharedLink, server }
```

- `.photoLibrary` is the new, top-ranked iCloud/Apple Photos path.
- Ordering in the choice enum is not the UI order; the view presents them iCloud → sharedLink →
  server (friction order, FR-220-01). The enum simply gains the case.

### `OnboardingStep` (OnboardingKit) — new step

```
enum OnboardingStep { case choice, photoLibrarySetup, sharedLinkSetup, connection, source, confirm, done }
```

- `.photoLibrarySetup` renders the reused `PhotoAlbumPickerView` (connectionless).
- Adding the case deliberately breaks the **exhaustive** switches in `choosePath`, `canGoBack`,
  `back`, and `OnboardingFlowView` — the compile-red that drives the TDD steps.

## New type

### `ScannedShareLink` (OnboardingKit) — pure validator

Turns a decoded QR string into a routing decision, wrapping the existing `SharedLinkURL.parse`.

| Element | Shape | Notes |
|---|---|---|
| `validate(_ decoded: String)` | `-> Result<ParsedSharedLink, InvalidCodeReason>` | Pure, synchronous, no network, no camera. |
| `ParsedSharedLink` | `(baseURL: URL, slug: String)` | The same tuple `SharedLinkURL.parse` already returns. |
| `InvalidCodeReason` | `enum { notAURL, notHTTPS, notAShareLink }` | Maps to the calm rejection copy; nothing is persisted for any case. |

**Validation rules** (all from existing behaviour): HTTPS-only; a shared-link shape (`/s/<slug>` or
last-path-segment fallback); anything else → `InvalidCodeReason`. A valid result is handed to the
existing `SourceLibraryViewModel` resolver (resolve-first, password-only-when-needed, dedupe).

## Seam (protocol, not data)

### `CodeScanning` (OnboardingKit)

Abstracts "produce a decoded string from the camera". Real implementation is the app-target
`QRScannerView` (AVFoundation); the host-test fake yields scripted strings. Carries no logic itself —
its output flows into `ScannedShareLink.validate`.

## Reused, unchanged

- `Source { id, label, kind }`, `SourceKind { .album, .sharedLink, .photoLibrary }`, `SourceLibrary`,
  `UserDefaultsSourceLibraryStore` — every welcome path adds one source here (one active).
- `SharedLinkSecretStore` (keychain) for shared-link passwords.
- `StartupGate.initialStep()` — already routes `.photoLibrary`-only and `.sharedLink`-only active
  sources to `.done` (no change; pinned by a parity test).
- `SourceLibraryViewModel.addPhotoLibrarySource`, `.resolveSharedLink`, `PhotoAlbumPickerView`.

## State transitions (onboarding step machine)

```
choice ──choose(.photoLibrary)──> photoLibrarySetup ──pick album──> done
choice ──choose(.sharedLink)────> sharedLinkSetup ──resolve ok──> done
                                        │
                                        ├─ scan QR → decoded string → ScannedShareLink.validate
                                        │     ├─ valid   → same resolve path → done
                                        │     └─ invalid → calm error, stay, nothing persisted
                                        └─ (password-protected) → prompt once → done
choice ──choose(.server)────────> connection ──> source ──> confirm ──> done   (unchanged)

Back: photoLibrarySetup → choice ;  sharedLinkSetup → choice ;  connection → choice ;
      source → connection ;  confirm → source ;  choice / done → (no back)
```

Relaunch (via `StartupGate`): active `.photoLibrary` or `.sharedLink` source → `.done`; active
`.album` → `.done` only with key + base URL, else `.connection`; no active source → `.source` if a
validated connection exists, else `.choice`.
