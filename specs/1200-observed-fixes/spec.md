# Feature Specification: Observed Frame Fixes (1200)

**Feature Branch**: `1200-observed-fixes`
**Created**: 2026-07-22
**Status**: Draft
**Input**: Three issues observed on the running frame:
1. Adding an album with no Immich server configured shows "Couldn't load albums" instead of guiding the user to add a server.
2. The Ken Burns effect ignores the **Fit** setting (it forces Fill framing).
3. MQTT / Home Assistant should also publish the device's battery percentage (and charging state).

## Overview

This is a **work-order bundle**: three small, independent fixes shipped on one branch. Each fix's
durable behavior is defined in its owning module spec — this document carries the user stories,
acceptance scenarios, and the mapping to those module requirements. It defines **no new durable
FR-1200 IDs**; it realizes existing/amended module requirements:

| Fix | Owning module spec | Realizes |
|-----|--------------------|----------|
| 1. Album-tab no-server guidance | `210-shared-link-onboarding` | FR-210-30, SC-210-13 |
| 2. Ken Burns honors Fit | `500-display-options` (+ `300-slideshow` reconcile) | FR-500-20, SC-500-09; FR-300-33, SC-300-13 |
| 3. Battery + charging telemetry | `710-ha-full-control` | FR-710-23, SC-710-07 |

The three fixes touch disjoint packages (OnboardingKit/app UI, SlideshowKit/ThemeKit, HAControlKit),
so they can be implemented and verified independently.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Clear guidance when no server is configured (Priority: P1)

A user who set up the frame with only a shared link (no API key) opens the source picker and
switches to the **Album** tab. Because album listing needs a server API key, the app cannot list
albums — but instead of a dead-end "Couldn't load albums", it explains that a server is needed and
offers to add one.

**Why this priority**: A misleading error on an empty/unconfigured setup is a first-impression
friction point squarely on the "ease of use" primary goal; smallest change, highest polish return.

**Acceptance Scenarios**:

1. **Given** no server URL + API key is stored (shared-link-only setup), **When** the user opens
   the Album tab of the source picker, **Then** an "add a server" prompt is shown that routes into
   the server-connection editor — not a generic "Couldn't load albums" message.
2. **Given** a server **is** configured but the album list fetch fails (server unreachable),
   **When** the Album tab loads, **Then** a distinct, retryable connection error is shown (the
   existing "Couldn't load albums" path), clearly separate from the no-server case.
3. **Given** the same picker is used in onboarding and in Settings → Sources, **When** the
   no-server case occurs in either surface, **Then** both show the same guidance (one shared
   component).

### User Story 2 - Ken Burns respects the Fit setting (Priority: P2)

A user who prefers to see whole photos selects **Fit** and turns on Ken Burns. The photo stays
fully visible (letterboxed) and drifts with a gentle centered zoom, rather than being cropped to
fill the screen.

**Why this priority**: A paid Pro/ambience feature silently overriding a core display choice is a
correctness bug against the user's explicit setting; it touches the shipped motion engine so it
carries more risk than Story 1.

**Acceptance Scenarios**:

1. **Given** fit **Fit** and Ken Burns **on**, **When** a photo whose aspect differs from the
   screen is shown, **Then** the whole photo stays visible (letterboxed), motion is a centered
   slow zoom with no visible pan, and no frame reveals background beyond the fitted letterbox.
2. **Given** fit **Fit**, **When** Ken Burns is toggled on, **Then** the framing does **not** switch
   to Fill.
3. **Given** fit **Fill** and Ken Burns **on**, **When** photos advance, **Then** motion pans and
   zooms exactly as it does today (no regression).
4. **Given** either fit mode, **When** chrome is shown with Ken Burns on vs off, **Then** chrome
   edge insets are pixel-identical (FR-300-33 / SC-300-13 still hold).

### User Story 3 - Battery visible in Home Assistant (Priority: P3)

A user running the frame on an iPad/iPhone sees the device's battery level (%) and whether it is on
power as diagnostic entities in Home Assistant, so they can alert when an always-on frame drops off
AC.

**Why this priority**: Additive telemetry, no behavior change to existing entities; valuable but the
least user-visible of the three, and gated on the HA path being set up.

**Acceptance Scenarios**:

1. **Given** the frame runs on a battery-bearing device with HA configured, **When** discovery is
   published, **Then** HA gains a battery-level sensor (%) and a charging binary sensor.
2. **Given** the battery level or charging state changes, **When** the OS reports it (event-driven),
   **Then** the corresponding entity's state updates without polling.
3. **Given** the frame runs on a device without a battery (Apple TV), **When** discovery is
   published, **Then** neither entity is discovered.
4. **Given** an unentitled (no-Automation) frame, **When** it publishes, **Then** the battery and
   charging sensors are still published (they are free read-only telemetry).

### Edge Cases

- **Album tab, no server, then user adds a server**: after adding a server via the routed editor,
  returning to the Album tab lists albums normally (no stuck error state).
- **Fit + Ken Burns on a photo that already matches the screen aspect**: centered zoom with no
  letterbox is correct (no background to reveal); behavior is stable.
- **Battery level unavailable / `-1` (monitoring not yet ready)**: the battery sensor publishes no
  misleading value until a real reading is available; charging reflects `unknown` as OFF/absent, not
  a false ON.
- **Device with battery reports `.full` while on AC**: charging binary sensor reads ON (on external
  power), matching the "is it powered" intent.

## Requirements *(mandatory)*

### Functional Requirements (realized from module specs)

- **FR-210-30** (owning: 210) — album tab distinguishes "no server configured" from a network/load
  error and routes the no-server case into the server-connection editor (FR-210-29).
- **FR-500-20** (owning: 500) — Ken Burns honors the active fit option; with Fit it is a centered
  zoom, pan suppressed, no Fill substitution.
- **FR-300-33** (owning: 300, reconciled) — chrome insets stable across framing; Ken Burns does not
  by itself switch fit/fill.
- **FR-710-23** (owning: 710) — battery-level sensor + charging binary sensor as free, event-driven,
  battery-device-only diagnostic entities.

### Key Entities

- **Server-configured state**: presence of a stored server base URL (UserDefaults) **and** API key
  (Keychain); the discriminator for Story 1. Owned by OnboardingKit config/keychain stores.
- **Battery reading**: level (0–100 integer, or unavailable) + on-power flag, sourced event-driven
  from the device behind an injectable protocol (Modular Isolation). Absent on non-battery devices.

## Success Criteria *(mandatory)*

- **SC-210-13** (210) — no-server case shows add-a-server routing, never a bare "couldn't load"; a
  configured-server failure shows a distinct retryable error.
- **SC-500-09** (500) — Fit + Ken Burns renders fitted with centered zoom and no visible pan, never
  reveals background beyond the letterbox, never switches to Fill; Fill + Ken Burns unchanged.
- **SC-300-13** (300) — chrome insets pixel-identical Ken-Burns-on vs off in both Fit and Fill.
- **SC-710-07** (710) — battery + charging entities reflect real state, update without polling on a
  battery device, and are absent on a non-battery device; verified with the fake transport and an
  injected battery source.

## Assumptions

- Story 1's two failure modes are already separable in the data flow (the no-server branch does not
  perform a network call), so the fix is a UI state split, not new networking.
- Story 2's motion honors Fit via a centered, pan-suppressed zoom; the geometry keeps the whole
  fitted photo visible. This changes a shipped behavior (previously fill-forced) but only for the
  Fit + Ken Burns combination.
- Story 3 sources battery state behind an injectable protocol so `HAControlKit` stays host-testable
  with no real device; the real device read (UIKit) lives in the app adapter.

## Dependencies

- 210 depends on OnboardingKit's config/keychain stores and the shared server-connection editor
  (FR-210-29) already existing.
- 710 depends on the existing `HAControlKit` diagnostic-sensor pattern (FR-710-07) and the
  `PhotoReporting`/read-only-sensor tiering (1100, FR-1100-03a).
- 500/300 depend on the shared `KenBurnsMotionModifier` / `KenBurnsDrift` motion engine and the
  `fillsScreen` decision sites in both the iPad and tvOS renderers.

## Out of Scope

- Live end-to-end MQTT verification against a real broker (device-day item).
- On-device visual confirmation of the Ken Burns motion (Framepad verification, tracked as a manual
  gate — the automated tests cover the geometry/decision, not the perceived motion).
- Any change to pricing/tiering beyond classifying battery/charging as free read-only telemetry.
