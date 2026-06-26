# Phase 1 Data Model: Shared-Link Onboarding & iOS Share Sheet

Types are grouped by owning module. **Reused** types come from 100/120; **new/changed** types are
marked. All value types are `Sendable`; nothing here stores a secret outside the Keychain.

## ImmichClient (topic 100)

### `Album` *(changed — add metadata for search)*
| Field | Type | Notes |
|-------|------|-------|
| `id` | `String` | unchanged |
| `name` | `String` | unchanged (`albumName` JSON key) |
| `assetCount` | `Int?` | **new** — photo/asset count from `GET /api/albums`; `nil` if absent |
| `startDate` | `Date?` | **new** — album range start; `nil` if absent |
| `endDate` | `Date?` | **new** — album range end; `nil` if absent |

- Back-compatible: existing `init(id:name:)` retained; new fields default to `nil`. Decoding tolerates
  missing fields (older servers / the shared-link `me` album reference that only carries `id`).
- Validation: none added; metadata is advisory (used only for search/subtitle).

### `SharedLinkResolution` *(unchanged; decode adds an optional album name)*
- Existing: `key`, `albumID`, `expiresAt`.
- The decoder MAY also read `album.albumName` to provide a **default source label** for auto-added
  links (D7). If absent, callers fall back to the slug/host. (No new public field is required if the
  label is derived at the call site.)

## OnboardingKit (config / flow domain)

### `OnboardingStep` *(changed — add `.choice`)*
`choice` → (`connection` | sharedLinkSetup) → … existing `source` → `confirm` → `done`.
- `.choice`: first-run entry; user picks shared-link vs server.
- Shared-link-only path may go `.choice` → (in-place link entry) → `.done` without `.source`/`.confirm`
  when a single link is all that is added.

### `OnboardingPathChoice` *(new — trivial)*
`enum { case sharedLink, server }` — the user's selection on `.choice`.

### `SharedLinkAddState` *(new — two-phase resolve state machine)*
Drives the resolve-first / ask-password-only-when-needed flow (D6), shared by onboarding and Settings.
| State | Meaning |
|-------|---------|
| `idle` | no resolution in flight |
| `resolving` | a resolve call is in flight (spinner) |
| `needsPassword(parsed)` | server returned `passwordRequired`; show the password prompt |
| `resolved(Source, password?)` | ready to persist (password only when one was entered) |
| `error(ConnectionError-classified message)` | malformed / invalid / expired / unreachable / wrong-password |

Transitions:
- `idle → resolving` on submit.
- `resolving → resolved` (200) | `→ needsPassword` (401, no password) | `→ error` (else).
- `needsPassword → resolving` on password submit → `resolved` (200) | `error(wrongPassword)` (401, password) .
- Persisting `resolved` adds the `Source` to the library and, if a password was used, stores it in the
  per-source Keychain secret store (120). Nothing persists in any other state.

### `Source`, `SourceLibrary`, `SourceLibraryStore`, `SharedLinkSecretStore` *(reused from 120)*
- A shared link added here is an ordinary `.sharedLink(baseURL:slug:)` source; activation/restart and
  per-source password storage follow 120 unchanged.
- **Dedup key** for incoming links (D7): `(baseURL, slug)` equality against existing `.sharedLink`
  sources.

### `IncomingSharedLink` *(new — router)*
Input: a non-secret URL handed from the Share Extension. Output: a routing decision.
| Outcome | When | Effect |
|---------|------|--------|
| `prefillOnboarding(url)` | app unconfigured (no active source) | open shared-link setup pre-filled |
| `switchToExisting(sourceID)` | a `.sharedLink` with the same `(baseURL,slug)` exists | setActive (120) |
| `addAndActivate(parsedURL)` | configured, link not present | resolve → add source → setActive |
| `invalid(reason)` | URL not a parseable Immich share link | show error, persist nothing |

### `PendingSharedLinkStore` *(new — protocol; App-Group hand-off)*
```
protocol PendingSharedLinkStore: Sendable {
    func savePendingURL(_ url: URL)      // written by the Share Extension (non-secret only)
    func takePendingURL() -> URL?        // consumed once by the host, then cleared
}
```
- Production impl: `UserDefaults(suiteName: <app-group>)` storing only the URL string under one key.
- **Invariant**: only the non-secret URL is ever written; never a password or API key (Constitution III).
- In-memory fake for tests.

### `StartupGate` *(changed — see research D2)*
Adds shared-link-active ⇒ `.done` (no API key) and empty ⇒ `.choice`.

## App layer (Immich Slideshow)

### Album search *(new — pure predicate, `AlbumSearch`)*
`func filter(_ albums: [Album], query: String) -> [Album]` — case/diacritic-insensitive substring of a
composed haystack (name + formatted date + count). Empty query ⇒ all albums. Pure, no state.

### Share Extension data
- `ShareLinkExtraction.url(from: [NSExtensionItem]) -> URL?` — pure, host-unit-tested.
- The extension writes via `PendingSharedLinkStore.savePendingURL`; the host reads via
  `takePendingURL()` on launch/foreground and feeds it to `IncomingSharedLink`.

## Secret-handling summary (Constitution III)

| Datum | Where it lives | Crosses the App Group? | Logged? |
|-------|----------------|------------------------|---------|
| Shared-link URL (non-secret) | App Group (transient), source library (baseURL+slug) | yes (URL only) | no |
| Shared-link password | Keychain (per-source) only | **no** | no |
| API key | Keychain only | **no** | no |
| Resolved bearer key | in-memory only, never persisted | no | no |
