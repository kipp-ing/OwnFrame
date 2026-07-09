# Feature Specification: Slideshow Resilience (Auto-Retry + Periodic Refresh)

**Feature Branch**: `310-slideshow-resilience`

**Created**: 2026-07-09

**Status**: Planned — pre-release gate; not yet built. Next implementation slice before the
App Store release.

**Input**: Sub-spec of `specs/300-slideshow`. A photo frame runs unattended for weeks: it must
survive network loss without anyone touching it, and newly added photos must enter rotation
without an app restart. This spec promotes two items from topic 300's Roadmap into buildable
requirements: **auto-retry with backoff** (was FR-300-11) and **periodic source refresh**
(was FR-300-12). Out of scope: the disk image cache (+ Clear action) stays deferred in topic
300's Roadmap; a user-facing setting for the refresh interval (fixed default here, see
Assumptions); retry/refresh state as HA diagnostics entities (roadmap note below).

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Unattended recovery from network loss (Priority: P1)

The frame's Wi-Fi drops (router reboot, server restart, brief outage). Nobody is around. When
the network returns, the slideshow recovers by itself: retries happen automatically with growing
intervals, and playback continues where it can.

**Why this priority**: This is the difference between a demo and an appliance. A frame that
strands on an error screen at 3 a.m. until someone taps "Retry" fails its core promise.

**Independent Test**: With a fake `ImmichAPI` and an injected scheduler/clock: make the source
fetch fail, verify retries fire at the specified backoff sequence without user input; make the
fake recover, verify playback resumes within one backoff interval and the backoff resets. No
real timers, no real network.

**Acceptance Scenarios**:

1. **Given** playback is running and the next image fetch fails with a transient error, **When**
   nothing is tapped, **Then** the engine keeps showing the current image and retries in the
   background with exponential backoff.
2. **Given** the source list fetch fails at launch (saved setup, server unreachable), **Then**
   the calm error state from FR-300-10 is shown *and* auto-retry runs behind it; when the server
   returns, playback starts without user input.
3. **Given** retries are failing, **When** the fake source recovers, **Then** playback resumes
   within one (current) backoff interval and the backoff resets to its initial value.
4. **Given** repeated failures, **Then** intervals grow to the cap and stay there — retrying
   never stops while the app is in the foreground.
5. **Given** the user taps the existing manual Retry, **Then** it triggers an immediate attempt
   and resets the backoff; manual retry keeps working exactly as in FR-300-10.
6. **Given** a non-transient failure (401/403 — revoked API key, expired shared link), **Then**
   the calm state names the actionable problem ("check your connection settings") while a slow
   background retry continues (the server may also be misconfigured temporarily).

### User Story 2 - New photos appear without a restart (Priority: P1)

Photos added to the active album (or shared link) on the server show up in the rotation on their
own — the frame is never "frozen in time" at whatever the album contained at launch.

**Why this priority**: The frame's content is the product. "Upload from your phone, see it on
the wall" only works if the frame refreshes itself.

**Independent Test**: With a fake `ImmichAPI` and injected scheduler: start playback, add assets
to the fake source, advance the injected clock past the refresh interval, verify the new assets
enter rotation per the active order without a visible restart; remove assets and verify they
leave rotation without disrupting the current photo.

**Acceptance Scenarios**:

1. **Given** playback is running, **When** the refresh interval elapses, **Then** the active
   source's asset list is re-fetched in the background.
2. **Given** new assets arrived, **When** the order is *sequential*, **Then** they appear at
   their album position; **When** the order is *shuffle*, **Then** they join no later than the
   next shuffle cycle (FR-300-05's "every photo once per cycle" invariant holds).
3. **Given** a refresh completes, **Then** the currently displayed photo is not interrupted, the
   auto-advance timer is not reset, and no blank/loading state appears (SC-300-03 holds during
   refresh).
4. **Given** a refresh fails, **Then** playback continues on the stale list and the failure is
   handled by User Story 1's retry — no error surface replaces a working slideshow.
5. **Given** assets were removed on the server, **Then** they leave the rotation; if the current
   photo was removed, it stays visible until the next advance and is then skipped.
6. **Given** the source became empty on the server, **Then** the next refresh moves to the
   existing empty-state message (edge case already defined in topic 300).

### User Story 3 - Coming back to the foreground stale (Priority: P2)

The app was backgrounded (or the iPad slept) for hours. On return, the frame notices it is stale
and refreshes promptly instead of waiting out a full interval.

**Independent Test**: With injected clock and lifecycle signals: simulate background → long time
passage → foreground, verify an immediate refresh triggers when the last successful refresh is
older than the interval; verify no refresh/retry timers fire while backgrounded.

**Acceptance Scenarios**:

1. **Given** the app returns to the foreground and the last successful refresh is older than the
   refresh interval, **Then** a refresh is triggered immediately.
2. **Given** the app is in the background, **Then** no retry or refresh timers fire (consistent
   with FR-300-14's foreground-only rule).
3. **Given** a retry was pending when the app was backgrounded, **Then** it resumes (or fires
   immediately if overdue) on foreground return.

### Edge Cases

- **Server unreachable at launch with saved setup**: calm state + auto-retry (US1 scenario 2) —
  never a dead end.
- **API key revoked / shared-link password changed or link expired**: actionable calm message;
  background retry continues at the backoff cap only (no hot loop against an auth error).
- **Album deleted server-side**: treated as the empty/failed source case — calm message + retry.
- **Refresh while the album browser sheet is open**: rotation updates apply; the open browser is
  unaffected (it fetches its own data on demand).
- **Refresh returns the same list**: no-op — no reshuffle, no timer reset, no visible effect.
- **Refresh during a transition/Ken Burns motion**: list swap happens between advances; the
  running animation is never interrupted.
- **Clock changes / time zone jumps**: intervals are measured with a monotonic reference, not
  wall-clock time.
- **Retry storm protection**: backoff has jitter so many frames behind one server do not
  synchronize their retries.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-310-01**: Transient source-fetch and image-load failures MUST auto-retry with exponential
  backoff, without user interaction, while the app is in the foreground.
- **FR-310-02**: The backoff MUST start at ~1 s, double per attempt, cap at 5 minutes, apply
  ±20 % jitter, and reset after any successful fetch.
- **FR-310-03**: While retrying, the engine MUST keep showing the current image if one exists;
  the calm error state (FR-300-10) appears only when there is nothing to show.
- **FR-310-04**: Manual retry (FR-300-10) MUST remain available, trigger an immediate attempt,
  and reset the backoff.
- **FR-310-05**: Non-transient auth failures (401/403, expired shared link) MUST surface an
  actionable calm message and continue retrying only at the backoff cap.
- **FR-310-06**: The active source's asset list MUST be re-fetched periodically at a fixed
  default interval of 60 minutes (foreground-only).
- **FR-310-07**: A completed refresh MUST NOT interrupt the current photo, reset the auto-advance
  timer, restart the shuffle cycle mid-cycle, or produce any visible loading state.
- **FR-310-08**: Added assets MUST enter rotation per the active order (sequential: album
  position; shuffle: no later than the next cycle). Removed assets MUST leave rotation; a removed
  current photo finishes its slot and is skipped afterwards.
- **FR-310-09**: A failed refresh MUST leave the existing rotation playing (stale-but-working
  beats fresh-but-broken) and defer to FR-310-01's retry handling.
- **FR-310-10**: On foreground return, a refresh MUST trigger immediately when the last
  successful refresh is older than the refresh interval; no retry/refresh timers fire in the
  background (FR-300-14 alignment).
- **FR-310-11**: Retry and refresh MUST work identically for both source kinds (API-key album
  and shared link) through topic 100 data access, and MUST survive an active-source switch
  (timers rebind to the new source; no timers leak from the old one).
- **FR-310-12**: Scheduling MUST be driven by injected clock/scheduler protocols so all backoff
  and interval behavior is unit-testable on the host without real timers (constitution:
  testability).
- **FR-310-13**: Failure paths MUST NOT log secrets (API key, shared-link password, broker
  credentials) — consistent with FR-300-32.

### Key Entities

- **Retry Policy**: Backoff parameters (initial ~1 s, factor 2, cap 5 min, jitter ±20 %) and the
  current attempt state; reset on success or manual retry.
- **Refresh Schedule**: Fixed 60-minute foreground interval plus the "stale on foreground
  return" trigger; tracks the last successful refresh with a monotonic reference.
- **Rotation Reconciliation**: The diff between the playing asset list and a freshly fetched one
  — additions, removals, and the rule for the currently displayed asset.

### Roadmap / Deferred (not yet built)

- **Refresh interval as a setting** (app Settings and/or an HA number entity via topic 710) —
  only if users ask; the fixed default keeps setup friction at zero.
- **Retry/refresh status in HA diagnostics** (last refresh time, current backoff state) as
  additional 710 diagnostics attributes.
- **Disk image cache** stays where it is: topic 300 Roadmap. It complements this spec (photos
  keep showing across a relaunch while offline) but is not required by it.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-310-01**: With a mocked network outage and recovery, playback resumes without any user
  interaction within one current-backoff interval of the recovery.
- **SC-310-02**: A photo added to the active source appears in rotation within one refresh
  interval (plus at most one shuffle cycle in shuffle order) without an app restart.
- **SC-310-03**: A removed photo no longer appears after the refresh that dropped it; removing
  the currently displayed photo never crashes or blanks the frame.
- **SC-310-04**: Under an injected clock, observed retry intervals follow the specified sequence
  (initial → doubling → cap, with jitter bounds) and reset after success.
- **SC-310-05**: During a refresh, the current photo's on-screen time is unaffected (timer not
  reset, no visible stall or flicker).
- **SC-310-06**: A simulated long run (injected clock, repeated network flaps and refreshes)
  ends with the slideshow still advancing and memory within the existing cache bounds.

## Assumptions

- The 60-minute default refresh interval is deliberate: hourly is fresh enough for a wall frame,
  cheap for the server, and avoids adding a setting nobody should need to think about
  (ease-of-use goal). It can move to Settings/HA later (Roadmap) without spec surgery.
- Topic 100 already distinguishes transport errors from HTTP status errors well enough to
  classify transient vs. auth failures; if not, that classification is in scope for this spec's
  implementation as a topic-100 amendment.
- Foreground-only is acceptable: the frame use case keeps the app foregrounded (Guided Access /
  dedicated device), and iOS reclaims background control anyway (constitution constraint).
- The existing bounded in-memory cache and prefetch (FR-300-06/07) are unchanged; refresh only
  swaps the asset list feeding them.
