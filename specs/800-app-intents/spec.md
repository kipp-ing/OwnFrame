# Feature Specification: App Intents (Shortcuts, Siri, Apple Automations)

**Feature Branch**: `800-app-intents`

**Created**: 2026-07-09

**Status**: Implemented on branch `800-app-intents` (2026-07-17) — T001–T028 complete;
all automated gates green (40 AppIntentsKit tests, 13 `FrameIntentGlueTests`,
`build_sim` clean, full XCUITest suite 108 passed / 0 failed / 2 intentional skips).
Remaining before ship: T029 only — the quickstart manual device checklist (SC-800-02
overnight automation, SC-800-03 Siri/Shortcuts discovery, honesty/edge drills) on the
real frame iPad — then merge.

**Input**: New module (next free hundreds-block). Expose the slideshow's existing remote-control
command surface as **App Intents**, so Shortcuts, Siri, and on-device personal automations can
control the frame without Home Assistant: "At 22:00 → dim to 0 and pause; at 07:00 → brightness
60 % and play." This is the Apple-native counterpart to topic 700 — same commands, second
front-end. Out of scope: HomeKit accessory exposure (an iOS app cannot be a HomeKit accessory —
HAP is for certified hardware/bridges; users who want Apple Home / Siri-via-Home control get it
today through Home Assistant's HomeKit Bridge re-exposing the topic-700 MQTT entities, which is a
documentation task, not code), hub-executed Home automations calling intents (Apple does not run
third-party intents on home hubs), background brightness changes (foreground-only, constitution
constraint), starting/stopping the app, source management beyond selecting an existing source.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Control playback and brightness from Shortcuts/Siri (Priority: P1)

The user runs "Pause Slideshow", "Resume Slideshow", "Next Photo", "Previous Photo", or "Set
Frame Brightness to 40 %" from the Shortcuts app or via Siri, and the running frame obeys —
with exactly the same semantics as the in-app chrome and the HA entities.

**Why this priority**: This is the core value: the frame becomes scriptable with zero extra
infrastructure. Everything else builds on these verbs.

**Independent Test**: With the remote-control command surface behind its existing protocol and a
fake implementation injected: invoke each intent handler directly (host unit test, no Siri/UI),
verify it calls the same command path as topic 700 (validation, clamping, persistence), and
verify out-of-range parameters are rejected with a clear error, not silently clamped to garbage.

**Acceptance Scenarios**:

1. **Given** the slideshow is running in the foreground, **When** the Pause intent runs, **Then**
   auto-advance stops exactly as if the chrome pause was tapped (user-pause semantics of
   FR-300-18, including surviving background/foreground).
2. **Given** the slideshow is paused, **When** Next Photo runs, **Then** the photo steps without
   resuming — identical to the HA button behavior (topic 710, US3).
3. **Given** a Set Brightness intent with a value in 0–100 %, **Then** brightness applies through
   topic 400 exactly like the HA light entity (foreground-only; same clamping).
4. **Given** a Set Brightness intent with an out-of-range value, **Then** the intent fails with a
   readable error and state is unchanged.
5. **Given** the app is not running (or backgrounded), **When** an intent that needs the live
   slideshow runs, **Then** the intent either foregrounds the app first (`openAppWhenRun` /
   foreground continuation) or fails with a message that says the frame must be open — never a
   silent no-op.

### User Story 2 - Scheduled automations on the frame itself (Priority: P1)

On the dedicated frame iPad, the user creates Shortcuts **personal automations**: time-of-day
(night dim / morning wake), charger connected, or Focus changes, running the intents from User
Story 1 — no Home Assistant, no network dependency.

**Why this priority**: This is the "HomeKit-ish control without HA" answer for the majority who
don't run a broker: the frame dims and pauses at night on its own.

**Independent Test**: Intent-level only (automation triggers are OS-owned and not testable in
CI): verify each intent used in the recipes runs unattended — no confirmation dialogs, no
parameter prompts when fully configured (`AppShortcuts` phrases resolve; intents declare they
run without foreground *confirmation* even when they require the app to be foregrounded).

**Acceptance Scenarios**:

1. **Given** a personal automation "At 22:00: Set Brightness 0 %, Pause" with Ask-Before-Running
   off, **Then** both intents execute unattended with the app in the foreground (the frame's
   normal state).
2. **Given** the docs recipe page, **Then** it walks through night/morning automation setup on
   the frame iPad, states the foreground requirement plainly, and names what does *not* work
   (HomeKit accessory events cannot trigger third-party intents; hub automations cannot call
   them — time/charger/NFC/Focus triggers can).

### User Story 3 - Select the source and read frame state (Priority: P2)

Shortcuts can switch the active source ("Set Frame Source to *Vacation 2025*") from the saved
source library, and read basic state (playing/paused, brightness, active source, current photo's
date/location) to branch automations on it.

**Independent Test**: With a fake source library: verify the source-select intent enumerates
exactly the saved sources (topic 120) as its options, switching uses the same restart strategy
as the HA select (topic 700/120), and the read intent returns the documented fields — never
secrets, never server URLs with credentials, no photo bytes.

**Acceptance Scenarios**:

1. **Given** saved sources exist, **When** the source parameter is resolved, **Then** the options
   list matches the source library labels (topic 120) — the same list the HA select shows.
2. **Given** a source-select intent for a shared-link source, **Then** the switch uses the
   rebuild strategy exactly like an in-app switch (`SourceRestartStrategy` semantics preserved).
3. **Given** the state-read intent runs, **Then** it returns playback state, brightness, active
   source label, and current-photo metadata (date/city/country) and nothing else — no asset
   bytes, no credentials, no URLs containing secrets (FR-300-25/32 discipline).

### Edge Cases

- **Intent runs during onboarding (no configured source)**: fails with a clear "set up the frame
  first" error.
- **Two intents race (automation fires while the user taps chrome)**: last write wins through the
  same serialized command surface topic 700 uses; no crash, no divergent state.
- **Brightness intent while backgrounded**: iOS owns brightness in the background — the intent
  foregrounds the app or fails readably; it never pretends success.
- **Siri phrase collisions**: `AppShortcuts` phrases include the app name and stay distinct from
  common HomeKit phrases.
- **Source deleted after an automation referenced it**: the intent fails with "source no longer
  exists", the slideshow keeps its current source.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-800-01**: The app MUST expose App Intents for: play, pause, next photo, previous photo,
  set brightness (0–100 %), select active source, and read frame state.
- **FR-800-02**: Every intent MUST route through the same remote-control command surface as
  topic 700 (the adapter behind `SlideshowRemoteControlAdapter`) — identical validation,
  clamping, persistence, and side effects; no second command path.
- **FR-800-03**: Intents MUST be exposed as `AppShortcuts` with Siri phrases so they work
  without manual Shortcuts setup.
- **FR-800-04**: Intents that require the live slideshow MUST either foreground the app or fail
  with an explicit, localized error — never a silent no-op (foreground-only constraint is stated,
  not hidden).
- **FR-800-05**: Fully configured intents MUST run unattended in personal automations (no
  confirmation prompts), enabling time-of-day night/morning recipes on the frame device.
- **FR-800-06**: The source-select intent's options MUST come from the topic-120 source library
  and switching MUST reuse its restart strategy — parity with the HA album select.
- **FR-800-07**: The state-read intent MUST expose only: playback state, brightness, active
  source label, current photo date and coarse location — never credentials, asset bytes, server
  URLs, or filenames (consistent with FR-300-25/FR-300-32).
- **FR-800-08**: Parameter validation MUST mirror the HA ranges (brightness 0–100 % mapping to
  topic 400's 0.0–1.0; unknown source → error + unchanged state, the topic-700 self-heal
  stance).
- **FR-800-09**: Intent handlers MUST be host-unit-testable behind injected protocols (fake
  command surface, fake source library) — no Siri, simulator, or UI required for logic tests.
- **FR-800-10**: A docs page MUST ship with the feature: automation recipes (night dim/morning
  wake), the foreground requirement, and the explicit HomeKit boundary (what works via HA's
  HomeKit Bridge today, what iOS does not allow).

### Key Entities

- **Frame Command Surface**: The existing single entry point for remote commands (shared with
  topic 700); intents are a second caller, not a second implementation.
- **Source Entity**: The App Intents entity representing a saved source (id + label from topic
  120), used for parameter resolution in the select intent.
- **Frame State Snapshot**: The read-model returned by the state intent (playing/paused,
  brightness, source label, current-photo date/location).

### Roadmap / Deferred (not yet built)

- **Display-settings intents** (duration, transition, Ken Burns, …): the command surface already
  supports them (topic 710); exposed as intents only if demand shows — each intent is App
  Shortcuts UI surface area, and Shortcuts users can already reach these via HA if they run it.
- **Control Center / Lock Screen controls and widgets** (iOS 18+ `ControlWidget`): same verbs,
  more surfaces; separate slice.
- **Interactive snippet/result UI** for the state intent (photo preview snippet).

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-800-01**: Every P1 intent, invoked against a fake command surface, produces exactly the
  same command-path calls as the corresponding HA entity command (verified by unit test).
- **SC-800-02**: A time-of-day personal automation running "brightness 0 % + pause" then
  "brightness 60 % + play" works unattended on a foregrounded frame across at least one
  overnight cycle (manual verification on the device, documented like the 710 live-HA run).
- **SC-800-03**: Intents appear in Shortcuts and respond to their Siri phrases on a device with
  the app installed, without prior manual configuration.
- **SC-800-04**: The state intent's output contains no secret, URL, or byte payload under test
  with a fully populated fake state.
- **SC-800-05**: All intent logic tests run on the host (`swift test`) with no simulator.

## Assumptions

- The frame device runs the app foregrounded (Guided Access or dedicated use) — the automations
  story leans on this and says so in the docs; this spec does not fight iOS background limits.
- `SlideshowRemoteControlAdapter` (or its protocol) is injectable from the app target where the
  intents live; if intents need a package home, an `AppIntentsKit` package wraps the logic while
  the `AppIntent` conformances stay in the app target.
- Minimum OS for intents matches the app's iOS 17 floor (App Intents is iOS 16+); iOS-18-only
  surfaces (Control Center controls) are Roadmap, gated at runtime.
- Localization: intent titles/phrases ship English-only like the rest of the app (FR-300-30
  policy).
