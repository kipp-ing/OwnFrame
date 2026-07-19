# Feature Specification: Source Library (multiple switchable slideshow sources)

**Feature Branch**: `120-source-library`

**Created**: 2026-06-24

**Status**: Active — built and merged to main (feat/120, 2026-06-25); US flows covered by host units + XCUITests

**Input**: User request: save several slideshow sources (Immich albums and shared/public album
links) as one library, switch which one is playing, and expose that switch in the Home Assistant
MQTT interface. Distilled with the reserved shared-link source (`110`) and the topic 100 roadmap
("pool assets across multiple albums"), but constrained to **one active source at a time** (no
pooling) per the captured product decision.

This is a sub-spec of the `100` data-access topic: it generalizes today's single
`AppConfiguration.selectedAlbumID` into a persisted library of switchable sources. It consumes the
shared-link source defined in `110` and is **surfaced** by `200` (onboarding/Settings UI) and `700`
(Home Assistant select), which are amended rather than re-specified here.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Save several sources and switch the active one (Priority: P1)

A user saves more than one slideshow source — any mix of their Immich albums and Immich shared
album links — into a single library, and switches which one is currently playing. Exactly one source
is active at a time; switching restarts playback from the newly active source.

**Why this priority**: This is the core capability — a library of sources you can flip between,
generalizing the current single-album setup without losing it.

**Independent Test**: With a mocked data source, seed a library of two sources (one album, one
shared link), verify the slideshow shows only the active source's photos, switch the active source,
and verify playback now shows only the other source's photos.

**Acceptance Scenarios**:

1. **Given** a library with two saved sources, **When** the user selects the inactive one, **Then**
   the slideshow switches to show only that source's photos and the selection persists.
2. **Given** the active source is an Immich album, **When** the user switches to a saved shared-link
   source, **Then** the slideshow plays the shared link's photos without requiring a personal API key.
3. **Given** a single active source, **When** photos are displayed, **Then** only that source's
   assets appear (no merging/pooling of multiple sources).

### User Story 2 - Add the first source in onboarding, manage the library in Settings (Priority: P1)

During first-run onboarding the user adds an initial source (an album after connecting, or a shared
link), and later adds/removes/reorders/relabels sources and picks the active one from Settings. The
confirmation step shows the saved library.

**Why this priority**: The feature must work for first-run setup *and* later changes; the reserved
shared-link placement in `200` becomes functional here.

**Independent Test**: With mock stores, complete onboarding by adding one source, then from Settings
add a second source, switch active, remove one, and verify only validated changes persist.

**Acceptance Scenarios**:

1. **Given** the onboarding flow, **When** the user adds a valid first source (album or shared link),
   **Then** onboarding can complete with that source active.
2. **Given** Settings, **When** the user adds, removes, reorders, or switches sources, **Then** each
   change is validated before persistence and the running slideshow adopts a valid active change.
3. **Given** the confirmation step, **When** it is shown, **Then** it lists the saved sources and
   marks the active one.

### User Story 3 - Switch the active source from Home Assistant (Priority: P2)

The existing Home Assistant select entity lists the saved sources (not the full server album list);
selecting one switches the running slideshow's active source and echoes the new state back.

**Why this priority**: Remote control of the active source is a key reason for the library, but it
depends on the library existing first.

**Independent Test**: Against a mock MQTT transport, publish the select discovery with the saved
sources as options, send a select command for a saved source, and verify the active source changes
and the state topic echoes it; an unknown option is a no-op that still echoes the real state.

**Acceptance Scenarios**:

1. **Given** a library of saved sources, **When** Home Assistant discovery is published, **Then** the
   select options are exactly the saved sources' labels.
2. **Given** a select command naming a saved source, **When** it is received, **Then** the active
   source switches and the state topic echoes the new active source.
3. **Given** a select command naming an unknown option, **When** it is received, **Then** nothing
   changes and the real active source is echoed.

### User Story 4 - Migrate and persist transparently (Priority: P2)

An existing install that had a single selected album keeps playing it after upgrade, now as a
one-entry library. The library and active selection survive relaunch; any shared-link password stays
secret.

**Why this priority**: No existing user should have to reconfigure; persistence is what makes the
library usable day to day.

**Independent Test**: Seed the legacy single-album config, launch, and verify a one-entry library
with that album active; relaunch and verify the library and active selection are restored; verify a
shared-link password never appears in UserDefaults/logs.

**Acceptance Scenarios**:

1. **Given** a legacy `selectedAlbumID` config, **When** the app launches after upgrade, **Then** it
   becomes a one-entry library with that album active and playback continues unchanged.
2. **Given** a saved library, **When** the app relaunches, **Then** the sources and active selection
   are restored.
3. **Given** a saved password-protected shared link, **When** the app relaunches, **Then** the source
   is restored and its password remains in the Keychain only.

### Edge Cases

- **Active source becomes invalid** (album deleted, link expired/revoked): the slideshow surfaces the
  existing calm empty/error state and the user can switch to another saved source or fix the source.
- **Empty active source**: uses the existing empty-source hint (topic 300).
- **Duplicate labels**: two sources with the same display label must still be individually selectable
  in-app; the HA select needs a disambiguation rule (see Open Questions).
- **Removing the active source**: the library promotes another source to active (or returns to an
  empty state if none remain) without crashing.
- **Wrong/missing shared-link password**: a password-specific error is shown and nothing is persisted.
- **Last source removed**: the app falls back to the existing empty/onboarding path rather than a
  blank screen.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-120-01**: The app MUST persist an ordered library of slideshow sources with exactly one marked
  active.
- **FR-120-02**: Each source MUST be one of: an Immich album (API-key access, today's behavior) or an
  Immich shared/public album link (`110`); the model MUST allow additional source kinds later without
  rework.
- **FR-120-03**: The app MUST present only the active source to the slideshow engine through the
  existing image-asset contract (albums → assets → preview/original), with no slideshow engine
  rewrite; switching the active source MUST restart playback from the new source.
- **FR-120-04**: The user MUST be able to add, remove, reorder, and relabel sources and explicitly
  choose the active source; no source is added or activated implicitly.
- **FR-120-05**: Library management MUST be reachable from both onboarding (add the first source) and
  Settings (manage several), and the onboarding confirmation step MUST list the saved sources and mark
  the active one (surfaced via topic `200`).
- **FR-120-06**: On first launch after upgrade, the app MUST migrate an existing single
  `selectedAlbumID` into a one-entry library with that album active, with no user action and no
  playback interruption.
- **FR-120-07**: Home Assistant MUST expose the library as a select entity whose options are the saved
  sources; a valid select command MUST switch the active source and the change MUST be echoed; unknown
  options MUST be a no-op that still echoes the real active source (surfaced via topic `700`).
- **FR-120-08**: Shared-link passwords MUST be treated as secrets stored only in the Keychain and MUST
  never appear in UserDefaults, logs, source, committed files, cache, or plaintext UI. Non-secret
  source metadata (labels, album IDs, server base URL, shared-link slug) MAY live in UserDefaults; a
  resolved shared-link key token MUST be treated as sensitive (never logged).
- **FR-120-09**: The app MUST validate a source before persisting it (the album exists, or the shared
  link resolves) and MUST distinguish invalid/expired link, wrong/missing password, and unreachable
  server where the underlying result allows (consistent with `110`).
- **FR-120-10**: The feature MUST preserve the calm default: switching is an explicit user/HA action;
  it adds no startup interruption, no new always-on overlay, and no background behavior.
- **FR-120-11**: Exactly one source is active at a time; pooling/merging multiple sources into one
  stream is OUT OF SCOPE here (remains the topic 100 roadmap item).
- **FR-120-12** *(added 2026-07-19)*: Wherever a shared link can be added to the library, the user
  MUST be able to supply it by scanning its QR code as an alternative to typing or pasting — that
  is, on the shared add-source form used by Settings → Sources and by the onboarding add-source
  step, not only on the first-run shared-link path (which already has it via FR-220-04). A scanned
  code MUST be handled identically to a typed one: same validation, same resolve-first /
  password-only-when-needed flow, same dedupe and persistence, and the optional name the user typed
  alongside MUST be carried through to the saved source. Camera access follows FR-220-05: if it is
  denied or unavailable, manual entry MUST remain fully usable, and scanning is never the only way
  to add a link.

### Key Entities *(include if feature involves data)*

- **Source**: One saved slideshow source. Has a stable local id, a user-facing label, a kind
  (`album` or `sharedLink`), and kind-specific locator: for `album`, the Immich album id (accessed
  with the configured API key); for `sharedLink`, the server base URL + shared-link slug and an
  optional password reference (Keychain).
- **Source Library**: The ordered list of Sources plus the id of the active source.
- **Active Source**: The single Source currently feeding the slideshow engine.
- **Source Validation Result**: Outcome of validating a candidate source — valid, invalid/expired
  link, missing/incorrect password, unreachable, or unexpected response.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-120-01**: A user can save at least two sources (mixing an album and a shared link) and switch
  between them both in-app and from Home Assistant, and the slideshow shows only the active source.
- **SC-120-02**: After upgrading, an existing single-album user keeps playing that album with zero
  reconfiguration, now represented as a one-entry library.
- **SC-120-03**: The library and active selection survive relaunch, and any shared-link password is
  absent from plaintext UI, UserDefaults, logs, source, and committed files.
- **SC-120-04**: The Home Assistant select lists the saved sources, and selecting one switches the
  active source within a single running slideshow.
- **SC-120-05** *(added 2026-07-19)*: A user who already has a library can add a second shared album
  by scanning its QR code from Settings → Sources — without typing the link — and a name typed in
  the form before scanning is the name the source is saved under. The host tier verifies the
  routing and the name pass-through with no camera; the live camera scan rides the existing
  SC-220-07 device gate.

## Open Questions

1. **Password-protected shared links**: RESOLVED — verified against the running server (Immich 2.7.5,
   see `110`). Both the unprotected and protected paths are confirmed: a protected link's password is
   supplied once as `me?slug=<slug>&password=<pw>` to obtain the key, and all later asset calls use the
   key alone. The remaining questions below are plan-stage design decisions, not blockers.
2. **HA select disambiguation** *(decide in `/speckit-plan`)*: How to make the select options
   unambiguous when two sources share a label (append kind, append an index, or require unique labels
   in the UI).
3. **Slug→key freshness** *(decide in `/speckit-plan`)*: Re-resolve a shared-link slug to its key on
   each launch (tolerates a rotated/expired key) versus caching the resolved key.
4. **Label source of truth** *(decide in `/speckit-plan`)*: Default a source's label from the
   album/shared-link name, with an optional user override — confirm whether overrides are needed for v1.

## Assumptions

- The shared-link source mechanics for the running server are as verified in `110` (slug resolves via
  `GET /api/shared-links/me?slug=`, assets enumerate via `GET /api/albums/{id}?key=`, images fetch via
  `?key=` query auth); this spec consumes that source, it does not redefine it.
- Exactly one active source at a time (product decision); pooling and Memories-as-source stay on the
  topic 100 roadmap.
- Topic 300 consumes the active source unchanged because every source kind presents the same
  image-asset contract.
- Topic 200 provides the onboarding/Settings surface for add/manage/switch; topic 700 provides the
  select entity. Both are amended, not re-specified, by this work.
- Network and persistence stay injected behind protocols so validation and migration are testable
  without a real server or real Keychain.

## Roadmap / Deferred (not yet built)

- **Pooling** multiple sources into one merged stream (topic 100 roadmap) — explicitly out of scope
  here; one active source at a time.
- **Memories** as a source kind (topic 100 roadmap) — fits the extensible Source model but unscheduled.
- **HA per-source enable/disable** (would pair with pooling) — not applicable while one source is
  active at a time.
