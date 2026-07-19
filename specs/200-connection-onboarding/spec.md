# Feature Specification: Connection & Onboarding

**Feature Branch**: `200-connection-onboarding`

**Created**: 2026-06-23

**Status**: Active

**Input**: Consolidated from `specs/002-onboarding/spec.md`, `specs/009-connection-settings/spec.md`, and `specs/010-settings-onboarding-ux/spec.md`: first-run Immich connection, album selection, in-place connection editing, Settings structure, reset behavior, and the reserved shared-link seam.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Complete first-run setup from a combined connection screen (Priority: P1)

On first launch the user enters the Immich server URL and API key on one screen, continues only after both are provided, and reaches album selection after a single validation action proves the server is reachable and the key is authorized. The API key is stored only in the Keychain, the selected album is persisted, and the main screen unlocks only after the setup is complete.

**Why this priority**: Without a valid connection and selected album the app has no data source, and the combined screen removes the most visible first-run friction while preserving the security rules.

**Independent Test**: With a mocked Immich data source and fake stores, start from no configuration, enter a valid HTTPS URL and valid API key, press Continue once, verify album selection appears with the key stored in the Keychain, select one album, and verify the main screen appears. Repeat with an unreachable server and with an unauthorized key and verify the screen stays open with values preserved and specific errors.

**Acceptance Scenarios**:

1. **Given** no prior setup, **When** onboarding opens, **Then** the server URL and API-key fields appear together on one screen, each with concise helper text, above one primary Continue action.
2. **Given** the combined connection screen, **When** either the server URL or API-key field is empty, **Then** Continue is unavailable until both fields are non-empty.
3. **Given** a syntactically invalid or non-HTTPS server URL, **When** the user attempts to continue, **Then** an inline URL error is shown before any network request is made.
4. **Given** a valid HTTPS server URL and valid API key, **When** the user presses Continue, **Then** the app validates reachability and authorization in one action, stores the key in the Keychain, and advances to album selection.
5. **Given** the server is unreachable, **When** the user presses Continue, **Then** the screen stays open, the entered values are preserved, and a clear unreachable-server error is shown.
6. **Given** the server is reachable but the API key is unauthorized, **When** the user presses Continue, **Then** the screen stays open, the entered values are preserved, and a clear unauthorized-key error is shown.
7. **Given** a valid connection, **When** album selection opens, **Then** the live list of available albums is shown.
8. **Given** a displayed album list, **When** the user selects exactly one album, **Then** the server URL and album selection are persisted, onboarding completes, and the main screen appears.
9. **Given** the live album list is empty, **When** album selection opens, **Then** a clear empty-state hint is shown instead of a dead end.

### User Story 2 - Resume startup at the correct place (Priority: P2)

On launch the app skips onboarding when a complete valid configuration exists. If setup was aborted or only partially saved, the app resumes at the first missing step and never exposes the main screen from a half-finished configuration.

**Why this priority**: The app is intended for repeated ambient use; returning users must not repeat setup, while incomplete setup must not unlock an invalid slideshow.

**Independent Test**: Start with complete stores and verify the main screen appears with no onboarding. Then remove the Keychain key or album ID and verify the app resumes at the combined connection screen or album selection as appropriate.

**Acceptance Scenarios**:

1. **Given** a complete saved configuration with server URL, Keychain API key, and selected album, **When** the app starts, **Then** onboarding is skipped and the main screen appears.
2. **Given** the API key is missing from secure storage, **When** the app starts, **Then** onboarding resumes at the combined connection step.
3. **Given** the server URL and API key exist but no album is selected, **When** the app starts, **Then** onboarding resumes at album selection.
4. **Given** the app is closed during onboarding before completion, **When** it is launched again, **Then** the main screen is not unlocked and onboarding resumes at the first missing step.

### User Story 3 - Edit the Immich connection from Settings without reset (Priority: P1)

While the slideshow is running, the user can expand the Connection section in Settings, see the current server URL and a "key is set" indicator without revealing the key, edit the URL and/or replace the key, and save only after the candidate connection validates. A rejected save leaves the prior connection active; a successful save applies to the running slideshow without re-onboarding.

**Why this priority**: Rotated keys and moved servers are normal maintenance events. The user needs a safe in-place edit path that does not tear down the album choice or leak secrets.

**Independent Test**: From a working slideshow, change the key to an invalid value and save; verify an unauthorized error and that the slideshow keeps using the old connection. Change to a valid key or URL and verify the new connection persists, survives relaunch, and the slideshow reloads without returning to onboarding.

**Acceptance Scenarios**:

1. **Given** a working connection, **When** Settings opens and the Connection section is expanded, **Then** the current server URL and a key-set indicator are shown, and the API key itself is never rendered in plaintext.
2. **Given** the Connection editor, **When** the user edits the URL or replaces the API key, **Then** each field can be changed independently without re-entering the unchanged value.
3. **Given** a malformed URL, **When** the user saves, **Then** a well-formedness error is shown inline and no network request is made.
4. **Given** a reachable server but wrong API key, **When** the user saves, **Then** the change is rejected with an unauthorized error and the previous URL and key remain active.
5. **Given** an unreachable server or a network drop during validation, **When** the user saves, **Then** the change is rejected with an unreachable error and the previous connection remains active.
6. **Given** validation succeeds for both reachability and authorization, **When** saving completes, **Then** the URL is persisted to app configuration, the key is persisted to the Keychain, and both replace the prior values atomically.
7. **Given** a successful connection change, **When** Settings is dismissed, **Then** the running slideshow adopts the new connection and reloads the current album without a full reset or onboarding.
8. **Given** unsaved edits, **When** the user cancels or dismisses the editor without saving, **Then** the existing connection is unchanged.
9. **Given** the new valid connection no longer contains the previously selected album, **When** saving completes, **Then** the user is prompted to re-select an album instead of being sent back to onboarding.

### User Story 4 - Recover a broken connection in place (Priority: P2)

If the slideshow is already showing a connection error, the user can reach the same Connection editor from that recovery path, correct the URL or key, and resume the previously selected album when possible.

**Why this priority**: A broken ambient frame needs a quiet recovery path; the user should not have to clear every setting just to fix an expired key.

**Independent Test**: Put the slideshow into a connection-error state, open the Connection editor from the error UI, save a valid key for the same server, and verify the slideshow leaves the error state with no onboarding steps.

**Acceptance Scenarios**:

1. **Given** the slideshow is in a connection-error state, **When** the user opens the Connection editor and saves a valid connection, **Then** the slideshow resumes the previously selected album without re-running onboarding.
2. **Given** only the API key changed, **When** the user saves, **Then** saving succeeds without requiring the URL to be re-entered.
3. **Given** only the URL changed, **When** the user saves, **Then** saving succeeds without requiring the API key to be re-entered.

### User Story 5 - Use one scrollable Settings structure (Priority: P2)

Settings presents Connection and Broker as collapsible sections within the main settings screen, defaulted collapsed, while brightness and display options remain reachable in the same screen. Broker setup is no longer hidden in the reset dialog. Every section remains reachable by scrolling in any orientation, width, or keyboard state.

**Why this priority**: This fixes discoverability and reachability without changing backend behavior. It also enforces ownership boundaries by surfacing broker and display controls where they belong without redefining their internals.

**Independent Test**: Open Settings from the running slideshow, verify Connection and Broker sections are collapsed by default, expand each, verify the reset dialog only offers reset/cancel, and confirm the bottom-most section can be scrolled fully into view in portrait, landscape, reduced-width layouts, and with the keyboard open.

**Acceptance Scenarios**:

1. **Given** a running slideshow, **When** Settings opens, **Then** Connection and Broker sections are present as collapsible sections and are collapsed by default.
2. **Given** the Broker section is expanded, **When** the user edits broker details, **Then** the behavior is the broker setup behavior owned by topic 600, surfaced from Settings.
3. **Given** the Connection section is expanded, **When** the user edits URL or key, **Then** the behavior is the validated connection-editing behavior in this spec.
4. **Given** the reset confirmation dialog is shown, **When** the user inspects its actions, **Then** it offers only reset and cancel, with no broker setup entry.
5. **Given** Settings contains all sections, **When** the user scrolls in portrait, landscape, split view, or with the keyboard open, **Then** every section and action can be reached.

### User Story 6 - Reset configuration cleanly (Priority: P3)

The user can still reset the app configuration. Reset removes the server URL, selected album, and Keychain API key, then returns setup to the combined connection step. It does not host broker setup and does not expose secrets.

**Why this priority**: Reset remains the escape hatch for changing ownership or starting over, but it is no longer the normal way to edit a connection.

**Independent Test**: With a complete configuration, invoke reset, verify the server URL and album are cleared, the API key is deleted from Keychain, and the next startup begins at the combined connection step.

**Acceptance Scenarios**:

1. **Given** a complete configuration, **When** reset is confirmed, **Then** the server URL, selected album, and Keychain API key are removed.
2. **Given** reset completed, **When** the app determines the next step, **Then** onboarding starts at the combined connection screen.
3. **Given** reset is canceled, **When** the dialog closes, **Then** no connection, album, or Keychain value is changed.

### Edge Cases

- **Invalid URL format or non-HTTPS URL**: The app shows a client-side error before any network call and does not persist anything.
- **Server unreachable, timeout, or network drop**: The user sees an unreachable-server error, can retry without restarting, and any prior working connection stays active.
- **Unauthorized API key**: The user sees an unauthorized-key error distinct from reachability failures and can retry without restarting.
- **Unexpected or malformed server response**: The app shows a general unexpected-response error without crashing and keeps the step repeatable.
- **Empty album list**: Album selection shows a clear empty-state hint and a way to correct connection values, not an inert selection screen.
- **Interrupted setup**: A partial or aborted setup never unlocks the main screen.
- **Secure storage write failure**: If saving the API key to the Keychain fails, the step is not marked successful and a user-visible error is shown.
- **New server lacks selected album**: A successful connection change prompts album re-selection rather than resetting all onboarding.
- **URL path, trailing slash, and whitespace variants**: URL normalization is consistent between onboarding and Settings so the same server is treated consistently.
- **Empty URL or empty key on save**: Inline validation prevents network calls and persistence.
- **Partial validation success**: If either reachability or authorization fails, saving is all-or-nothing and neither URL nor key is persisted.
- **Save tapped while validation is in flight**: Only one validation runs and the UI shows an in-progress state rather than double-persisting.
- **Collapse or expand with unsaved Settings input**: Unsaved text in an open Settings session is preserved when a section is collapsed and re-expanded.
- **Reserved shared-link seam**: The shared-link placeholder is visible but inert and clearly not yet available; no tap performs connection behavior in this spec.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-200-01**: On launch, the app MUST detect whether server URL, Keychain API key, and selected album are all present and valid enough to start, and MUST skip onboarding only when the configuration is complete.
- **FR-200-02**: If configuration is incomplete, the app MUST resume onboarding at the first missing step and MUST NOT unlock the main screen from a partial setup.
- **FR-200-03**: First-run onboarding MUST present server URL and API-key entry on one combined screen with one primary Continue action and concise helper text for both fields.
- **FR-200-04**: The combined screen MUST require a non-empty server URL and non-empty API key before Continue is enabled.
- **FR-200-05**: Server URL input MUST be validated as a well-formed HTTPS URL before any network request; TLS validation MUST NOT be disabled.
- **FR-200-06**: Continue MUST validate server reachability and API-key authorization in one action before advancing to album selection.
- **FR-200-07**: On combined validation failure, the app MUST preserve entered values and show an error that distinguishes unreachable server, unauthorized key, and unexpected server response where the underlying result allows.
- **FR-200-08**: The API key MUST be persisted only in the Keychain and MUST never appear in UserDefaults, plaintext UI, logs, cache, source code, or committed files.
- **FR-200-09**: Server URL and selected album ID MUST persist across app launches in non-secret configuration storage.
- **FR-200-10**: After a successful connection, the app MUST load the live album list and require the user to select exactly one album before onboarding completes.
- **FR-200-11**: An empty album list MUST be reported clearly and MUST NOT leave the user in a dead-end step.
- **FR-200-12**: Settings MUST present the current server URL and a key-set indicator in a collapsible Connection section without revealing the key.
- **FR-200-13**: Settings MUST allow the server URL and API key to be changed independently, with a masked or secure API-key entry field.
- **FR-200-14**: Saving connection edits MUST validate reachability and authorization before persisting anything, and malformed URLs MUST fail client-side before network access.
- **FR-200-15**: Failed connection-edit validation MUST persist no changes, keep the prior connection active, and show a specific failure classification where possible.
- **FR-200-16**: Successful connection-edit validation MUST persist the URL and Keychain key atomically and make the running slideshow adopt the new connection without a full reset.
- **FR-200-17**: Canceling or dismissing the Connection editor without a successful save MUST have no side effects.
- **FR-200-18**: The Connection editor MUST be reachable both proactively from Settings and from the slideshow connection-error recovery path.
- **FR-200-19**: If the selected album no longer exists after a successful connection change, the app MUST prompt for album re-selection rather than falling back to onboarding.
- **FR-200-20**: Settings MUST surface a Broker section owned by topic 600 as a collapsible section and MUST NOT duplicate broker validation or storage rules here.
- **FR-200-21**: Connection and Broker sections MUST be collapsed by default; display-option controls are owned by topic 500 and brightness behavior is owned by topic 400.
- **FR-200-22**: Every Settings section and action MUST be reachable by scrolling in portrait, landscape, reduced-width layouts, and while the keyboard is open.
- **FR-200-23**: The reset confirmation dialog MUST offer only reset and cancel; broker setup MUST be reachable from Settings instead.
- **FR-200-24**: Reset MUST clear server URL, selected album, and the Keychain API key, then return onboarding to the combined connection step.
- **FR-200-25**: The combined onboarding screen MUST reserve a visible, non-functional shared-link placeholder owned by reserved sub-spec `110-shared-album-link`. (A matching placeholder in Settings is deferred — see Roadmap.)
- **FR-200-26**: This topic MUST add no new Immich backend behavior or REST endpoints; it reuses topic 100 data access and validates paths against the running server's OpenAPI when planning implementation.
- **FR-200-27**: Connection, Keychain, configuration, and client dependencies MUST remain injected behind protocols so the flows are testable without a real server or real Keychain, in alignment with Modular Isolation.

### Key Entities *(include if feature involves data)*

- **Connection Configuration**: The active Immich server URL plus the secret API key. The URL is non-secret app configuration; the key lives only in the Keychain.
- **Setup Progress**: The startup decision state that determines whether the app can show the main screen, needs the combined connection step, or needs album selection.
- **Album Selection**: The single selected Immich album ID and display name used as the slideshow source after onboarding.
- **Connection Validation Result**: A candidate connection outcome classified as malformed, unreachable, unauthorized, invalid response, or valid.
- **Settings Section State**: The collapsible layout state for Connection and Broker sections during a Settings session, including unsaved field values.

### Roadmap / Deferred (not yet built)

- ~~Reserved sub-spec `110-shared-album-link`: a visible, non-functional placeholder for future
  shared-link entry, with the matching Settings placeholder deferred.~~ **Superseded — no longer
  deferred (reconciled 2026-07-19, task 120/T030).** The placeholders were replaced by real
  surfaces: [`110`](../110-shared-album-link/spec.md) shipped shared/public link playback (with
  optional password), and [`120`](../120-source-library/spec.md) shipped the Settings **Sources**
  manager (`Immich Slideshow/Slideshow/SourceLibraryView.swift`) plus the onboarding add-source
  step — both Active. [`210`](../210-shared-link-onboarding/spec.md) then made the choice-first
  onboarding and shared-link-only setup the default path, and
  [`220`](../220-onboarding-welcome/spec.md) added the welcome screen and camera QR scan.

  **Known gap, unspecified:** the QR scan lives only on the onboarding shared-link entry
  (`SharedLinkSetupView`). The shared `SharedLinkAddForm` used by Settings → Sources → + *and* by
  onboarding step 2 has no scan affordance — deliberately out of scope for 220 (FR-220-07,
  research R7), and never picked up by a later spec. Belongs in `120` when scheduled.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-200-01**: A new user can enter server URL and API key on one screen, press Continue once, and reach album selection with one fewer pre-album screen than the original flow.
- **SC-200-02**: 100% of unreachable-server and unauthorized-key failures on the combined screen keep the screen open, preserve entered values, and show distinct errors.
- **SC-200-03**: A returning user with complete configuration reaches the main screen with zero onboarding steps; an incomplete setup never reaches the main screen.
- **SC-200-04**: A user can change server URL or API key from Settings and return to a working slideshow in under 60 seconds without onboarding.
- **SC-200-05**: 100% of failed connection-edit saves leave the prior working connection fully intact and persist no partial candidate values.
- **SC-200-06**: After a successful connection edit, the slideshow reloads under the new connection within 5 seconds and the new URL/key survive relaunch.
- **SC-200-07**: The API key is absent from plaintext UI, UserDefaults, logs, cache, source files, and committed files, and is verifiable only in the Keychain.
- **SC-200-08**: Broker setup is reachable from Settings in at most two taps and is no longer present in the reset confirmation dialog.
- **SC-200-09**: 100% of Settings sections are reachable by scrolling in portrait, landscape, reduced-width layouts, and with the keyboard presented.
- **SC-200-10**: After reset, server URL and album are absent from configuration, the API key is absent from the Keychain, and the next launch starts at the combined connection step.

## Assumptions

- Topic 100 supplies the Immich data access and error categories used to validate reachability, authorization, album lists, and selected-album existence.
- Topic 600 owns broker field validation, secure broker credential storage, and broker provisioning; this topic only defines its Settings placement and reset-dialog removal.
- Topic 500 owns display-option values and controls; topic 400 owns live brightness behavior.
- The Immich server has a valid TLS certificate. Plain HTTP, self-signed certificates, and disabled TLS validation are out of scope.
- The app remains a foreground iPadOS slideshow app; this topic adds no background connection or Settings behavior, and platform boundaries from the constitution are respected by the owning modules.
- The default user experience remains calm and light: advanced Connection and Broker sections are discoverable but collapsed by default.
