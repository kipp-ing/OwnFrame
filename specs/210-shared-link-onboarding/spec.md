# Feature Specification: Shared-Link Onboarding & iOS Share Sheet

**Feature Branch**: `210-shared-link-onboarding`

**Created**: 2026-06-25

**Status**: Active — built and merged to main (PR #9, 2026-06-26); remaining polish tracked in tasks.md Phase 8

**Input**: User description: "Onboarding & shared-link UX overhaul. Choice-first onboarding (shared link vs server); shared-link-only setup (no API key); concise step descriptions; searchable album picker (name + date + photo count) for 50+ albums; subscrollable album list with an always-reachable primary action; iOS Share Sheet acceptance so an Immich share link can be sent into the app and auto-starts or asks for a password; ask for a shared-link password only when the link needs one. Ease of use is a primary goal."

## Clarifications

### Session 2026-06-25

- Q: How should the first onboarding screen branch for shared-link-only use? → A: Choice screen first — "Use a shared link" vs "Connect to server"; the shared-link path never asks for an API key.
- Q: How should a shared link get into the app (the "hook")? → A: The app appears in the iOS Share Sheet as a recipient for URLs; sharing an Immich link into it hands the link to the app, which auto-starts or asks for a password.
- Q: What should album search cover beyond the album name? → A: Name + date + photo count.

### Session 2026-06-26 (manual-test findings)

- Q: How does the user go back during onboarding (e.g. from the shared-link path back to the path choice)? → A: Every onboarding step after the choice screen MUST offer a Back affordance that returns to the previous step in-place, without restarting the app. (Today there is no back from the shared-link / connection / source steps — the only way back is to kill the app.)
- Q: Should the album/source picker in onboarding and in Settings → Sources be the same screen? → A: Yes — one reusable picker is used identically in both: Album / Shared-link tabs, a search field, an internally-scrollable album list, and a pinned confirm action, all simultaneously visible on a single screen.
- Q: In Settings → Sources, how does adding an album behave with the reused picker? → A: Select-then-confirm — tap albums to mark them, then a pinned confirm commits (multiple albums may be added in one pass), matching the onboarding picker rather than the old tap-to-add-and-close behavior.
- Q: Should the server connection be editable after onboarding, and how should the connection UI be unified? → A: One reusable connection editor (server URL + API key, validated before saving, stored key never shown) is used by onboarding, Settings, and the slideshow's connection-error recovery. Settings → Connection opens that editor (showing the current server) as a pushed page, not a separate inline form.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Set up with a shared link alone, no API key (Priority: P1)

On first launch the user is offered a choice between "Use a shared link" and "Connect to server". Choosing the shared link, the user enters (or pastes) an Immich share link. The app resolves it; if the link is not password-protected the user reaches the running slideshow with no API key required, and if it is protected the user is asked for the password once and then reaches the slideshow. The shared link becomes the active source and is the only thing needed to run.

**Why this priority**: This is the lowest-friction path to a working photo frame and the primary ease-of-use goal. A user who was given only a public/shared album link must be able to use the app without creating an API key.

**Independent Test**: With a mocked resolver and fake stores, start from no configuration, choose the shared-link path, enter a valid link, and verify the slideshow starts with no API key stored. Repeat with a password-protected link and verify exactly one password prompt precedes the slideshow, and with an invalid/expired link and verify a clear error with nothing persisted.

**Acceptance Scenarios**:

1. **Given** no prior setup, **When** onboarding opens, **Then** the first screen presents two clearly labeled choices — "Use a shared link" and "Connect to server" — with concise helper text.
2. **Given** the shared-link path, **When** the user enters a valid non-protected Immich share link and continues, **Then** the app resolves the link, saves it as the active source, requires no API key, and reaches the slideshow.
3. **Given** the shared-link path, **When** the entered link is password-protected, **Then** the app asks for the password only after detecting it is required, validates it, and then reaches the slideshow.
4. **Given** the shared-link path, **When** the link is malformed or non-HTTPS, **Then** a client-side error is shown before any network request and nothing is persisted.
5. **Given** the shared-link path, **When** the link is invalid, expired, or the server is unreachable, **Then** a clear, distinct error is shown and no source or secret is persisted.
6. **Given** a completed shared-link-only setup, **When** the app relaunches, **Then** it routes straight to the slideshow without re-onboarding and without prompting for an API key.

### User Story 2 - Send an Immich link into the app from the Share Sheet (Priority: P1)

From Safari, the Immich app, or anywhere a link can be shared, the user taps Share and selects ImmichSlideshow. The app receives the link, resolves it, and starts playing right away — or asks for a password first if the link needs one. If the app is not yet configured, the shared link drives the shared-link-only setup, pre-filled. If the app is already configured, the link is added as a source and becomes active.

**Why this priority**: This is the "easiest way of use" the user called out as a main goal: hand the app a link and watch. It removes manual typing/pasting entirely.

**Independent Test**: Simulate an incoming shared link handed from the share extension via the App Group. Verify that, when unconfigured, the app lands in shared-link setup pre-filled; when configured, the link is resolved and added as the active source and playback switches to it; a password-protected link prompts once; an invalid link errors cleanly; a link already present is switched to rather than duplicated.

**Acceptance Scenarios**:

1. **Given** ImmichSlideshow is installed, **When** the user shares a URL from another app, **Then** ImmichSlideshow appears as a recipient in the iOS Share Sheet.
2. **Given** the app is not yet configured, **When** an Immich share link is sent in, **Then** the app opens into the shared-link-only setup pre-filled with that link.
3. **Given** the app is already configured, **When** a valid non-protected Immich link is sent in, **Then** the app resolves it, adds it as a source, makes it active, and starts playing it.
4. **Given** a password-protected link is sent in, **When** the app receives it, **Then** the app asks for the password once and, on success, starts playing it.
5. **Given** a link that is already present in the source library is sent in, **When** the app receives it, **Then** the app switches to the existing source rather than creating a duplicate.
6. **Given** a malformed, non-Immich, or unreachable link is sent in, **When** the app receives it, **Then** a clear error is shown and nothing is persisted.

### User Story 3 - Find an album fast in a long list (Priority: P2)

A user who connected to a server and has many albums (50+) sees a searchable album list. Typing filters albums by name, date, and photo count. The list scrolls within its own region while the primary action (Continue/Add) stays pinned and always reachable, so the user never has to scroll past dozens of albums to proceed.

**Why this priority**: With 50+ albums the current single-Form layout buries the primary action and makes finding an album tedious. Search and a pinned action make album selection usable at scale.

**Independent Test**: Seed 50+ albums with names, dates, and photo counts. Verify typing a name fragment, a date, or a count narrows the list; verify a no-match state is shown clearly; verify the primary action stays visible while the list scrolls in portrait and landscape.

**Acceptance Scenarios**:

1. **Given** a connected server with many albums, **When** album selection opens, **Then** a search field is shown above an independently scrollable album list with the primary action pinned and visible.
2. **Given** the album search field, **When** the user types a fragment of an album name, **Then** the list narrows to matching albums as they type.
3. **Given** the album search field, **When** the user types a date or a photo count, **Then** albums are matched on their date and photo-count metadata in addition to name.
4. **Given** a search with no matches, **When** results are empty, **Then** a clear no-results state is shown rather than a blank list.
5. **Given** a long album list, **When** the user scrolls the list in any supported orientation, **Then** the Continue/Add action remains reachable without scrolling past the whole list.

### User Story 4 - Be asked for a password only when the link needs one (Priority: P2)

Wherever the user adds a shared link in the app — the onboarding source step and Settings → Sources — the app resolves the link first and asks for a password only if the server reports the link is password-protected. There is no always-visible optional-password field.

**Why this priority**: The current "optional password" field adds friction and confusion for the common case of non-protected links. Resolving first and asking only when required is simpler and consistent across the app.

**Independent Test**: In both the onboarding source step and Settings → Sources, add a non-protected link and verify no password is requested; add a protected link and verify exactly one password prompt before the source is saved; enter a wrong password and verify a distinct wrong-password error with nothing persisted.

**Acceptance Scenarios**:

1. **Given** the add-shared-link flow (onboarding or Settings), **When** the user submits a non-protected link, **Then** no password is requested and the source is saved after resolution.
2. **Given** the add-shared-link flow, **When** the submitted link is password-protected, **Then** the user is prompted for a password only after the requirement is detected.
3. **Given** a password prompt for a protected link, **When** the user enters a wrong password, **Then** a distinct wrong-password error is shown and nothing is persisted.
4. **Given** a password prompt for a protected link, **When** the user enters the correct password, **Then** the link is saved and the password is stored only in the Keychain.

### User Story 5 - Understand each onboarding step (Priority: P3)

Every onboarding screen carries concise helper text that explains what to do on that screen and why, so a first-time user is never guessing.

**Why this priority**: Small descriptions remove confusion at low cost and reinforce the ease-of-use goal, but they do not block any functional flow.

**Independent Test**: Walk each onboarding screen (choice, shared link, server connection, album selection, confirm) and verify each shows concise, accurate helper text.

**Acceptance Scenarios**:

1. **Given** any onboarding screen, **When** it appears, **Then** it shows a short description of the step's purpose and the expected action.
2. **Given** the choice screen, **When** it appears, **Then** each path option is accompanied by a one-line explanation of when to use it.

### Edge Cases

- **Malformed / non-HTTPS link**: client-side error before any network call; nothing persisted (in-app and shared-in).
- **Expired or revoked share link**: distinct expired/invalid error; nothing persisted.
- **Wrong password vs password-required**: the two are distinguishable to the user; a wrong password persists nothing.
- **Non-Immich or unrelated URL via Share Sheet**: clear "not a supported link" error; no crash, no persistence.
- **Shared-in link while a slideshow is already running**: resolved, added as a source, made active, and playback switches to it.
- **Shared-in link already in the library**: switched to, never duplicated.
- **Offline / unreachable server when resolving (in-app or shared-in)**: unreachable error, retryable, nothing persisted.
- **Share Sheet hand-off to a not-yet-launched or unconfigured app**: the link survives the cold start and lands in shared-link setup pre-filled.
- **Album search with zero matches**: explicit no-results state.
- **Album tab with no server configured**: in a shared-link-only setup, opening the picker's Album tab shows an add-a-server prompt (routing into the connection editor), not a generic "couldn't load albums" failure.
- **Albums missing date or count metadata**: such albums still appear and remain matchable by name; missing fields simply do not match date/count queries.
- **Very long album list with the keyboard open**: the primary action remains reachable and the list scrolls independently.
- **Going back during onboarding**: from any step after the choice screen the user can step back to the previous screen (e.g. shared-link setup → choice, source → connection) without restarting the app; the choice screen itself has nowhere further back.
- **Same picker in two places**: the album/source picker behaves identically in onboarding and in Settings → Sources (same tabs, search, internal scroll, and pinned confirm); a fix to one is a fix to both.
- **Secret hygiene across the app boundary**: the share extension passes only the non-secret link; the password (entered later, in the host app) is never written to the App Group container or logs.

## Requirements *(mandatory)*

### Functional Requirements

#### Choice-first onboarding & shared-link-only setup

- **FR-210-01**: First-run onboarding MUST present a choice between a shared-link path and a server-connection path, each clearly labeled with concise helper text.
- **FR-210-02**: The shared-link path MUST allow completing onboarding with only a shared link and MUST NOT require or request an API key.
- **FR-210-03**: A shared-link-only configuration MUST run the slideshow from the shared link's base address and slug as the active source, with no server API key required or stored.
- **FR-210-04**: Startup MUST treat a source library whose active source is a shared link as a complete configuration and route straight to the slideshow, without prompting for an API key.
- **FR-210-05**: The server-connection path MUST preserve the existing combined server-URL + API-key onboarding behavior owned by topic 200.
- **FR-210-26**: Every onboarding step after the choice screen (shared-link setup, server connection, source/album, confirm) MUST provide a Back affordance that returns to the immediately preceding step in-place — without requiring an app restart and without discarding already-entered configuration. The choice screen is the first step and has no further back.

#### Shared-link resolution & password-when-needed

- **FR-210-06**: When resolving a shared link, the app MUST request a password only after the server reports the link is password-protected, and MUST NOT present an always-visible password field before resolution.
- **FR-210-07**: The app MUST distinguish, to the user, between a malformed link, an invalid/expired link, an unreachable server, a password-required result, and a wrong-password result.
- **FR-210-08**: A shared link (and any entered password) MUST be validated against the server before anything is persisted; on any failure nothing is saved (no half-written source or secret).
- **FR-210-09**: Shared-link addresses MUST be HTTPS and validated/normalized before any network request; TLS validation MUST NOT be disabled.
- **FR-210-10**: A shared-link password MUST be stored only in the Keychain and MUST never appear in UserDefaults, logs, the App Group container, source code, or committed files.
- **FR-210-11**: The resolve-first / password-only-when-needed behavior MUST apply consistently to every in-app add-shared-link surface, including the onboarding source step and Settings → Sources.

#### iOS Share Sheet acceptance

- **FR-210-12**: The app MUST register as a recipient for URLs in the iOS Share Sheet so an Immich share link can be shared into it from other apps.
- **FR-210-13**: The share extension MUST pass only the non-secret shared-link URL to the host app via a shared App Group, and MUST NOT perform network resolution or handle secrets.
- **FR-210-14**: When the host app receives a shared-in link and is not yet configured, it MUST route into the shared-link-only setup pre-filled with that link.
- **FR-210-15**: When the host app receives a shared-in link and is already configured, it MUST resolve the link and, on success, add it as a source and make it active so playback switches to it (prompting for a password only if required).
- **FR-210-16**: If a shared-in link is already present in the source library, the app MUST switch to the existing source rather than create a duplicate.
- **FR-210-17**: If a shared-in link is malformed, not a supported Immich link, invalid/expired, or unreachable, the app MUST show a clear error without crashing and persist nothing.
- **FR-210-18**: An incoming shared link MUST survive a cold start of the host app (handed off via the App Group) and reach the correct destination after launch.

#### Searchable, subscrollable album picker

- **FR-210-19**: The album picker MUST provide a search field that filters albums by name, date, and photo count.
- **FR-210-20**: Album search MUST rely on album name, date, and photo/asset count being available from topic 100 Immich data access; albums lacking date or count MUST still appear and remain matchable by name.
- **FR-210-21**: The album list MUST scroll within its own region while the primary action (Continue/Add) remains pinned and reachable regardless of list length, orientation, reduced width, or keyboard state.
- **FR-210-22**: Album search results MUST update as the user types, and a no-match state MUST be shown clearly rather than as a blank list.
- **FR-210-27**: The album/source picker MUST be a single reusable component used identically in onboarding and in Settings → Sources: Album / Shared-link tabs, a search field, an internally-scrollable album list, and a pinned confirm action, all simultaneously visible on one screen. The two surfaces MUST NOT diverge into separate album-picker implementations.
- **FR-210-28**: In every surface that uses the picker (onboarding and Settings → Sources), adding an album MUST be select-then-confirm: tapping albums marks them and a pinned confirm commits, allowing one or more albums to be added in a single pass; tapping an album MUST NOT immediately add it and dismiss the picker.
- **FR-210-30**: The album tab of the picker MUST distinguish, to the user, two reasons it cannot show albums: (a) **no server configured** — the Album tab was reached with no server URL + API key stored (e.g. a shared-link-only setup) — MUST show guidance to add a server and route into the server-connection editor (FR-210-29), not a generic load failure; (b) a genuine **network / load error** against a configured server MUST show a distinct, retryable connection error. The two MUST NOT collapse into the same message. This applies identically in onboarding and Settings → Sources (FR-210-27).

#### Descriptions & cross-cutting

- **FR-210-23**: Every onboarding screen MUST display concise helper text describing the step's purpose and the expected action.
- **FR-210-24**: Network, keychain, shared-link resolver, and album-data dependencies MUST remain injected behind protocols so all new flows are testable without a real server, real Share Sheet, or real Keychain (Modular Isolation).
- **FR-210-25**: This feature MUST add no Immich backend behavior beyond reusing topic 100 data access and the topic 120 source library; new album-metadata reads MUST be validated against the running server's OpenAPI and MUST NOT bypass TLS.
- **FR-210-29**: The server-connection editor (server URL + API key, validated before persisting, stored key never displayed, "key is set" indicator) MUST be a single reusable component used identically in onboarding, Settings, and the slideshow's connection-error recovery. The server connection MUST be editable after onboarding via Settings → Connection, which opens that editor showing the current server; there MUST NOT be divergent connection-form implementations.

### Key Entities *(include if feature involves data)*

- **Onboarding Path Choice**: The user's selection between the shared-link path and the server-connection path on the first screen.
- **Shared-Link Source**: An active or saved source identified by a non-secret base address + slug, with an optional password held only in the Keychain (owned by topic 120; reused here).
- **Album Metadata**: Album name, date (or date range), and photo/asset count exposed for search and display (extends topic 100 album data).
- **Incoming Shared Link**: A non-secret URL captured by the share extension and handed to the host app via the App Group, then resolved.
- **Shared-Link Resolution Result**: A resolution outcome classified as malformed, invalid/expired, unreachable, password-required, wrong-password, or resolved.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-210-01**: A new user with only a non-protected shared link can reach a running slideshow without entering or storing an API key.
- **SC-210-02**: Sharing an Immich link from another app into ImmichSlideshow starts the slideshow — or asks for a password once and then starts — in at most two taps after selecting the app in the Share Sheet.
- **SC-210-03**: A password prompt appears only for links that are actually password-protected; non-protected links never show a password prompt.
- **SC-210-04**: In a library of 50+ albums, a user can narrow to a target album within a few keystrokes of search, and the primary action stays visible the entire time in portrait and landscape.
- **SC-210-05**: 100% of malformed, invalid/expired, or unreachable shared links (in-app or shared-in) show a clear, classified error and persist no source or secret.
- **SC-210-06**: The shared-link password and any API key are absent from UserDefaults, logs, the App Group container, source files, and committed files, and are verifiable only in the Keychain.
- **SC-210-07**: A shared link already in the library is never duplicated when shared in again.
- **SC-210-08**: Every onboarding screen shows concise, accurate helper text describing its purpose.
- **SC-210-09**: A shared-link-only setup routes straight to the slideshow on relaunch with zero onboarding steps and zero API-key prompts.
- **SC-210-10**: From any onboarding step after the choice screen, the user can return to the previous step (and ultimately to the path choice) using an in-app Back affordance, without ever needing to kill and relaunch the app.
- **SC-210-11**: Album selection looks and behaves identically in onboarding and Settings → Sources (one shared picker: tabs, search, internal scroll, pinned select-then-confirm); there is no second, unsearchable album-add screen anywhere in the app.
- **SC-210-12**: The server URL and API key can be changed after onboarding via Settings → Connection using the same editor as first-run; a successful change reconnects the running slideshow without re-onboarding, and the same editor appears in the slideshow's connection-error recovery.
- **SC-210-13**: Opening the picker's Album tab with no server configured shows an add-a-server prompt that routes into the server-connection editor, never a bare "couldn't load albums" message; a load failure against a configured server shows a distinct, retryable connection error.

## Assumptions

- The topic 120 source library, shared-link resolver, and Keychain secret store are reused; a shared link added here is an ordinary source in that library and follows its active-source/restart rules.
- Topic 100 album data can expose album name, date (or date range), and photo/asset count from the existing Immich album endpoints; if a field is unavailable from the running server it simply does not participate in search.
- The Share Sheet capability is implemented as an iOS Share Extension plus an App Group shared with the host app; the extension is thin (captures the URL only, no network, no secrets).
- When a link is shared in while the app is already configured, the intended behavior is to add it as a source and make it active (start playing it), consistent with the topic 120 set-active/restart behavior.
- HTTPS only with a valid TLS certificate (Constitution IV); self-signed/plaintext is out of scope.
- Target platform is iPadOS 18+ (iPhone optional); Share Sheet acceptance applies on both.
- Ease of use is a primary design goal: the shared-link and Share Sheet paths minimize taps and never ask for more than the link (plus a password only when required).

### Dependencies

- **Topic 100 (Immich client)**: album metadata (name, date, count) and shared-link resolution/auth error categories.
- **Topic 120 (Source library)**: persisted sources, active-source switching/restart, shared-link secret storage.
- **Topic 200 (Connection & onboarding)**: the onboarding structure this feature evolves (choice-first entry, server path, descriptions, album selection).
