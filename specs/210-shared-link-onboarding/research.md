# Phase 0 Research: Shared-Link Onboarding & iOS Share Sheet

All decisions below resolve the Technical Context. No `NEEDS CLARIFICATION` remain — the three
user-facing ambiguities (entry-flow shape, Share Sheet hook, album-search scope) were resolved with
the user before the spec was written (see spec *Clarifications*).

## D1 — Onboarding entry flow: add a `.choice` step

**Decision**: Add `OnboardingStep.choice` as the first step when nothing is configured. From it:
- **"Use a shared link"** → a shared-link-only path (new `SharedLinkSetupView`): enter link → resolve
  → (password sheet only if `passwordRequired`) → save as the active source → `.done`. The `.connection`
  (server URL + API key) step is **never** shown on this path.
- **"Connect to server"** → existing `.connection` → `.source` → `.confirm` → `.done` (unchanged 200/120).

**Rationale**: A clean fork at the top is the lowest-friction way to let link-only users skip the API
key entirely (user-chosen "choice screen first"), without disturbing the proven server path.

**Alternatives considered**: One combined screen with optional fields (rejected — clutters the common
case, ambiguous validation); shared-link-as-default with server "Advanced" (rejected — the user picked
an explicit two-way choice).

## D2 — StartupGate: a shared-link active source is complete without an API key

**Decision**: Relax `StartupGate.initialStep()`:
- If an **active source** exists and it is a **shared link** → `.done` (self-contained: baseURL+slug
  carry their own auth; no API key needed).
- If an active source exists and it is an **album** → `.done` when the API key + base URL are present,
  else `.connection` (album needs the server connection).
- No active source, but API key + base URL present → `.source`.
- Otherwise → `.choice` (was `.connection`).

**Rationale**: Shared-link-only setups have no API key by design; the current gate's
`keychain.read() != nil` guard would wrongly bounce them to onboarding. The 120 migration of a legacy
`selectedAlbumID` into a one-entry album library still resolves to `.done` under the album branch.

**Alternatives considered**: A separate "shared-link-only configured" flag (rejected — the active
source's kind already carries the needed information).

## D3 — Album metadata for search: extend `Album` with `assetCount` + date

**Decision**: Extend `ImmichClient.Album` with optional `assetCount: Int?` and date fields
(`startDate`/`endDate`, falling back to `createdAt`), decoded from the existing
`GET /api/albums` list response. Keep `id`/`name` and the public initializer back-compatible
(new fields default to `nil`). Album **search** is a pure predicate: the query matches when it is a
case/diacritic-insensitive substring of a composed haystack = album name + a formatted date (e.g.
year, "2024", month names) + the photo-count string. Albums missing date/count still match by name.

**Rationale**: The Immich album-list endpoint already returns `assetCount` and album dates, so no new
endpoint is needed (Constitution: validate field names against the running server's OpenAPI during
implementation). A substring-over-composed-haystack predicate covers "name + date + count" without a
query parser and is trivially unit-testable.

**Alternatives considered**: A structured query language (rejected — overkill); fetching per-album
detail for counts (rejected — the list endpoint already carries `assetCount`).

**Action item (implementation)**: confirm `assetCount`, `startDate`, `endDate`, `createdAt` field
names against `/api/server/version`'s OpenAPI before wiring decode.

## D4 — Searchable + subscrollable album picker with a pinned action

**Decision**: Replace the single-`Form` album step with a layout where the album list lives in its own
scrollable region (a `List`/`ScrollView`) under a search field, and the primary action
(Continue/Add) is **pinned** outside the scroll region (e.g. `safeAreaInset(edge: .bottom)` or a fixed
bottom bar). The list shows name + a small metadata subtitle (date · count).

**Rationale**: Today the album list and the Continue button share one Form, so with 50+ albums the
action is unreachable without scrolling the whole list (Bug from the spec). A pinned action + an
independently scrolling list fixes reachability in every orientation/keyboard state.

**Alternatives considered**: Keeping the Form but moving Continue to the navigation bar (rejected —
less discoverable, cramped on iPad); paginating albums (rejected — search is the better lever).

## D5 — iOS Share Sheet: thin Share Extension + App Group hand-off

**Decision**: Add a **Share Extension** target that declares it accepts URLs
(`NSExtensionActivationRule` for `public.url`, count 1). Its only job: extract the URL from the
extension item, write it to a shared **App Group** (`UserDefaults(suiteName:)` under a dedicated key),
then hand off to the host by opening a custom URL scheme (`immichslideshow://shared-link`). The **host
app** consumes the pending URL from the App Group on launch / `scenePhase == .active` and routes it via
`IncomingSharedLink`. The extension performs **no network and touches no secrets** — only the
non-secret URL crosses the boundary.

**Rationale**: An app-extension is the only supported way to appear in the iOS Share Sheet. Keeping it
thin (URL capture only) preserves Constitution III: the password is entered later in the host and goes
straight to the Keychain, never into the App Group container. Writing to the App Group + reading on
host foreground makes the hand-off **cold-start safe** (works whether or not the host was running);
the custom-scheme open just brings the host forward promptly.

**Alternatives considered**: Universal Links (rejected — needs `apple-app-site-association` hosted on
every user's Immich domain, not feasible per-instance); resolving the link inside the extension
(rejected — would pull network + secrets into the extension, violating the thin-boundary rule and
III); passing the URL only via the custom scheme without the App Group (rejected — fragile on cold
start / long URLs).

## D6 — Resolve-first / ask-password-only-when-needed (two-phase add)

**Decision**: Replace the always-visible optional-password field with a two-phase flow in
`SourceLibraryViewModel` (and the shared-link-only onboarding path):
1. `resolveSharedLink(urlString)` → calls `SharedLinkResolver.resolve(..., password: nil)`.
   - success → `.resolved` (save the source)
   - `ImmichError.passwordRequired` → `.needsPassword` (reveal a password prompt)
   - other `ImmichError` → `.error(classified)` (nothing persisted)
2. `confirmSharedLinkPassword(_:)` → re-resolves with the password.
   - success → save the source + store the password in the Keychain
   - `wrongPassword` → distinct error, stay on the prompt
The view model exposes a small pending state machine so onboarding, the onboarding source step, and
Settings → Sources all share one behavior.

**Rationale**: `SharedLinkResolver` already returns `passwordRequired` vs `wrongPassword`, so the
"ask only when needed" UX is a resolve-with-nil-then-prompt state machine — no new network shape.
Centralizing it in the view model keeps all three add surfaces consistent (FR-210-11) and unit-testable.

**Alternatives considered**: Keep the optional-password field but hide it until a failure (rejected —
still shows a field most users never need and complicates validation); a transport-level retry
(rejected — the requirement is a user prompt, not an automatic retry).

## D7 — Incoming link while already configured: add + activate, dedup by baseURL+slug

**Decision**: `IncomingSharedLink` routing:
- **Unconfigured** (gate would return `.choice`/`.connection`/`.source` with no active source) → route
  into the shared-link-only setup pre-filled with the URL.
- **Configured** → resolve; if a source with the same `baseURL` + `slug` already exists, **switch to
  it** (setActive); otherwise **add** it as a new source and **make it active** (reusing 120's
  add + setActive + restart). A password is requested only if `passwordRequired`.
The default source **label** is the resolved album name (decode `albumName` from the shared-link `me`
response) when available, else the slug/host.

**Rationale**: Matches the user's "start right away" intent and reuses 120 set-active/restart so the
running slideshow switches to the shared photos immediately. Dedup avoids piling up duplicates from
repeated shares.

**Alternatives considered**: Play the link ephemerally without saving (rejected — inconsistent with the
source library; the user would lose it on relaunch); always add even if duplicate (rejected — clutters
the library).

## D8 — Testing strategy for the Share Sheet boundary

**Decision**: Factor the extension's URL extraction into a pure `ShareLinkExtraction` function and the
hand-off into the `PendingSharedLinkStore` protocol so both are host-unit-tested without launching the
extension. The end-to-end Share Sheet round trip (extension → App Group → host routes the link) is
covered by an XCUITest that seeds a pending link via the App Group store (or the custom scheme) and
asserts the host's resulting state, plus a manual human-test step for the real Share Sheet UI.

**Rationale**: XCUITest cannot reliably drive the system Share Sheet from a third-party app, but the
app-group hand-off and routing — where the logic actually lives — are fully testable. Keeps
Constitution I satisfied for the boundary code.
