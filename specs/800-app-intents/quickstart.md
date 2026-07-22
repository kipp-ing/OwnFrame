# Quickstart: Validating App Intents (800)

**Date**: 2026-07-17 | **Spec**: `spec.md` | **Contract**: `contracts/app-intents-surface.md`

Runnable proof that the feature works, gate by gate. Prerequisites: the repo on
branch `800-app-intents`; XcodeBuildMCP session defaults pointing at the project +
an iOS ≥17 simulator (pin `simulatorId`, clear `simulatorName`).

## Phase-1 gate — package logic (host-only)

```bash
cd Packages/AppIntentsKit && swift test
```

Green means (SC-800-01, SC-800-04, SC-800-05):

- Every service verb, run against recording fakes of
  `PlaybackControlling`/`PhotoReporting`, produced **exactly** the call sequence
  the corresponding HA entity command produces — the parity suite lists the
  expected sequences inline next to their HAControlKit counterparts.
- Brightness 0/100 pass and map to 0.0/1.0; −1/101 throw with state untouched.
- Select with a live id applies via `selectAlbum(label)`; a stale id throws and
  the recording fake shows zero calls.
- The snapshot built from a fully-populated fake `PhotoReport` (bytes, IDs, URLs
  planted in every field) contains the six whitelisted fields and nothing else.
- Registry: unconfigured → `.notConfigured` immediately; configured-but-empty →
  `awaitReady` throws `.frameNotOpen` after the test clock passes the timeout;
  register mid-wait → the waiter resumes with the adapter.

## Phase-2 gate — app integration (simulator)

Via XcodeBuildMCP (`test_sim`, whole classes — never a single `@Test`):

- The new app-hosted glue suite: each `AppIntent` shell forwards to the service;
  error cases map to the contract copy; **HA and the intents resolve the same
  adapter instance** (the hoisting invariant).
- `SlideshowRemoteControlAdapterTests` and `HAControlRoundTripTests` stay green —
  the hoisting refactor must not move observable HA behavior.
- Full XCUITest suite before merge (standing rule; broker-toggle flake: rerun that
  class isolated before suspecting the diff).

## Manual device checklist (real hardware)

- [ ] **SC-800-03**: fresh install → Shortcuts app lists all 7 actions with no
      setup; each Siri phrase ("Pause OwnFrame", …) resolves and executes.
- [ ] **US1 sweep**: from Shortcuts — pause, resume, next, previous while paused
      (must step, not resume), brightness 0/40/100; each behaves exactly like the
      chrome / HA equivalent.
- [ ] **FR-800-04 honesty**: run Pause with the app backgrounded → app foregrounds,
      then pauses. Kill the app, run Get Frame State → readable "must be open"
      error, app stays closed.
- [ ] **Edge**: delete a source an automation references → run it → "no longer
      exists" error, slideshow unaffected. Run any intent on a freshly reset app →
      "set up the frame first".
- [ ] **SC-800-02 (ship gate)**: on the frame iPad (Guided Access, never locked):
      personal automations "22:00 → Set Brightness 0 % + Pause" and "07:00 →
      Brightness 60 % + Resume", Ask-Before-Running off → one full overnight cycle
      unattended; log the run like the 710 live-HA verification.
- [ ] **FR-800-10**: `docs/automation-recipes.md` walks through both recipes,
      states the foreground + unlocked assumptions plainly, and draws the HomeKit
      boundary (HA HomeKit Bridge yes; accessory events / hub-run intents no).

## Rollback

The feature is additive: no stored data formats change. Reverting the branch
restores the HA-only adapter construction; saved user shortcuts referencing the
removed intents fail gracefully in Shortcuts (missing action), touching no app
state.
