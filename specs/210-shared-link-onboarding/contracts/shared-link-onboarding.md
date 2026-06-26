# Contracts: Shared-Link Onboarding & iOS Share Sheet

Interface contracts for the new/changed surfaces. Signatures are indicative Swift; the binding
behavior is the contract. Existing protocols (`SharedLinkResolving`, `SourceLibraryStore`,
`SharedLinkSecretStore`, `KeychainStore`, `ConfigStore`, `ImmichAPI`) are reused unchanged unless noted.

## C1 — `PendingSharedLinkStore` (App-Group hand-off)

```swift
public protocol PendingSharedLinkStore: Sendable {
    /// Persist the non-secret share URL for the host to consume. Called by the Share Extension.
    func savePendingURL(_ url: URL)
    /// Return and clear the pending URL, or nil if none. Called once by the host on launch/foreground.
    func takePendingURL() -> URL?
}
```
**Contract**:
- `savePendingURL` MUST store **only** the URL (no password, no API key). [III]
- `takePendingURL` MUST return the most recently saved URL exactly once, then clear it (idempotent
  consumption — a second call returns `nil`).
- The production implementation uses an App Group shared by host + extension; a wrong/missing App Group
  MUST degrade to "no pending link" (return `nil`), never crash.

## C2 — Shared-link resolve state machine (`SourceLibraryViewModel` additions)

```swift
@MainActor func resolveSharedLink(urlString: String, label: String) async   // → updates addState
@MainActor func confirmSharedLinkPassword(_ password: String) async         // valid only in .needsPassword
var addState: SharedLinkAddState { get }
```
**Contract**:
- `resolveSharedLink` parses + normalizes the URL (HTTPS-only); a malformed/non-HTTPS URL ⇒
  `addState == .error(...)` with **no** network call. [IV]
- A successful resolve with no password ⇒ source saved + `addState == .resolved`; `passwordRequired`
  ⇒ `addState == .needsPassword`; other errors ⇒ `.error(classified)` and **nothing persisted**. [VI]
- `confirmSharedLinkPassword` is a no-op unless `addState == .needsPassword`; a correct password ⇒
  source saved + password written to the Keychain secret store; `wrongPassword` ⇒ `.error` and nothing
  persisted. [III]
- Identical behavior whether invoked from onboarding or Settings → Sources. (FR-210-11)

## C3 — Incoming link router (`IncomingSharedLink`)

```swift
enum IncomingSharedLinkOutcome {
    case prefillOnboarding(URL)
    case switchToExisting(sourceID: String)
    case addAndActivate(baseURL: URL, slug: String)
    case invalid(reason: ConnectionErrorKind)
}
func route(_ url: URL, library: SourceLibrary, isConfigured: Bool) -> IncomingSharedLinkOutcome
```
**Contract**:
- A URL that does not parse as an Immich share link ⇒ `.invalid`. [VI]
- Unconfigured ⇒ `.prefillOnboarding`. Configured + `(baseURL,slug)` already present ⇒
  `.switchToExisting`. Configured + absent ⇒ `.addAndActivate`. (FR-210-14/15/16)
- The router is pure (no I/O); resolution + persistence happen in the caller using C2 + 120.

## C4 — `Album` metadata (ImmichClient)

```swift
public struct Album { public let id, name: String
                      public let assetCount: Int?; public let startDate, endDate: Date? }
```
**Contract**:
- Decoding `GET /api/albums` populates `assetCount`/`startDate`/`endDate` when present and tolerates
  their absence (older servers, the shared-link `me` album reference). [back-compat]
- The existing `init(id:name:)` and `albums()` callers continue to compile and behave unchanged.

## C5 — Album search predicate (`AlbumSearch`)

```swift
func filter(_ albums: [Album], query: String) -> [Album]
```
**Contract**:
- Empty/whitespace query ⇒ returns `albums` unchanged (stable order).
- Non-empty query ⇒ keeps albums whose composed haystack (name + formatted date + count) contains the
  query, case- and diacritic-insensitively. Albums with `nil` date/count still match on name. (FR-210-19/20)
- Pure and deterministic (no network, no shared state) — unit-testable in isolation. [I/II]

## C6 — `StartupGate.initialStep()` (changed)

**Contract** (additions to 200 behavior):
- Active source is a `.sharedLink` ⇒ `.done`, even with no API key and no separately saved base URL. [D2]
- Active source is an `.album` ⇒ `.done` iff API key + base URL present, else `.connection`.
- No active source + API key + base URL ⇒ `.source`; otherwise ⇒ `.choice`.
- Legacy `selectedAlbumID` migration (120) still resolves to `.done` via the album branch.

## C7 — Share Extension activation (Info.plist / build)

**Contract**:
- The extension's `NSExtensionActivationRule` MUST accept exactly one URL (`public.url`) so Immich share
  links appear in the Share Sheet and unrelated content does not. (FR-210-12)
- The extension MUST perform no network and reference no secret; it MUST only extract the URL and call
  `PendingSharedLinkStore.savePendingURL`, then hand off to the host. (FR-210-13) [III/V]
- Host + extension share the same App Group entitlement; both target iOS/iPadOS 18+.

## Notes
- `[I]…[VII]` reference constitution principles the contract upholds.
- No existing public protocol signatures are broken; `Album` gains fields additively.
