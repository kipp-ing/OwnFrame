# Tasks: Slideshow Resilience (Auto-Retry + Periodic Refresh)

**Input**: Design documents from `/specs/310-slideshow-resilience/`

**Prerequisites**: plan.md, spec.md, research.md, data-model.md,
contracts/slideshow-resilience-api.md, quickstart.md

**Tests**: MANDATORY — constitution principle I (Test-First, NON-NEGOTIABLE). Every
implementation task is preceded by a task that lands its tests red. "Red" includes
does-not-compile against the not-yet-added API (see `tdd-workflow.md`).

**Organization**: Grouped by user story from spec.md. US1 (auto-retry) is the MVP; US2
(refresh) and US3 (foreground return) build on the same foundation but are independently
testable.

## Format: `[ID] [P?] [Story] Description`

- **[P]**: Can run in parallel (different files, no dependencies)
- **[Story]**: US1 / US2 / US3 from spec.md
- All package paths relative to repo root

## Path Conventions

- Engine: `Packages/SlideshowKit/Sources/SlideshowKit/`
- Host tests: `Packages/SlideshowKit/Tests/SlideshowKitTests/` (Swift Testing, `swift test`)
- App target: `Immich Slideshow/` (verified via XcodeBuildMCP, never raw `xcodebuild`)

---

## Phase 1: Setup

No setup tasks — `SlideshowKit` exists with a green suite; no new dependencies, no scaffolding
(plan.md: no new external dependencies, no storage).

---

## Phase 2: Foundational (Blocking Prerequisites)

**Purpose**: The time seam every story schedules against, plus source-compatible view-model
plumbing. No story work before this is done.

- [x] T001 Add `SlideshowClock` protocol (monotonic `now: Duration`, `sleep(for:) async throws`)
      and `ContinuousSlideshowClock` production impl in
      `Packages/SlideshowKit/Sources/SlideshowKit/SlideshowClock.swift` (contract:
      contracts/slideshow-resilience-api.md; trivial wrapper, same no-unit-test precedent as
      `RealTicker`)
- [x] T002 Add `TestClock` fake (deterministic `advance(by:)` releases due sleepers; pending
      sleep throws `CancellationError` on task cancellation) to
      `Packages/SlideshowKit/Tests/SlideshowKitTests/Fakes.swift`, with red-first sanity tests
      (sleep blocks until advanced past deadline, multiple sleepers release in deadline order,
      cancellation propagates) at the top of new
      `Packages/SlideshowKit/Tests/SlideshowKitTests/SlideshowResilienceTests.swift`
- [x] T003 [P] Add `refreshInterval: Duration` (default `.seconds(3600)`, precondition > 0) to
      `Packages/SlideshowKit/Sources/SlideshowKit/SlideshowConfig.swift` (FR-310-06; asserted
      in use by T013's default-interval test)
- [x] T004 Add injected `clock: any SlideshowClock = ContinuousSlideshowClock()` parameter to
      `SlideshowViewModel.init` in
      `Packages/SlideshowKit/Sources/SlideshowKit/SlideshowViewModel.swift` — store only, no
      behavior change; existing suites stay green (`cd Packages/SlideshowKit && swift test`)

**Checkpoint**: `swift test` green with the new seam in place — story phases can begin.

---

## Phase 3: User Story 1 — Unattended recovery from network loss (Priority: P1) 🎯 MVP

**Goal**: Transient failures auto-retry with exponential backoff (1 s → ×2 → 5 min cap, ±20 %
jitter, reset on success); the current image stays up while retrying; auth failures get the
actionable calm message and cap-only retry. The frame recovers from outages with nobody home.

**Independent Test**: quickstart.md scenarios 1–5 — fake `ImmichAPI` fails, `TestClock`
advances, retries fire on the specified schedule; fake recovers, playback resumes within one
backoff interval without user input. No real timers, no real network.

> Codex delegation (CLAUDE.md): T005+T006 are a well-scoped pure-logic pair — brief via
> `.claude/scripts/codex-brief.sh`. T007–T010 stay inline: timer/backoff/race test design and
> SwiftUI are explicitly non-delegable.

### Tests for User Story 1 (red first) ⚠️

- [x] T005 [P] [US1] Red: `Packages/SlideshowKit/Tests/SlideshowKitTests/RetryPolicyTests.swift`
      — delay sequence `initial × factor^(n-1)` capped at 300 s with each delay inside ±20 %
      jitter bounds (seeded `SeededRandomNumberGenerator`, numeric assertions); `reset()`
      returns to ~1 s; auth errors (`.unauthorized`, `.shareLinkExpired`, `.wrongPassword`,
      `.passwordRequired`) yield cap-only delays from attempt 1; `classify` table incl.
      non-`ImmichError` → `.transient` (FR-310-02/05, SC-310-04)
- [x] T007 [US1] Red: US1 scenarios in
      `Packages/SlideshowKit/Tests/SlideshowKitTests/SlideshowResilienceTests.swift` —
      (a) mid-playback image-load failure: current image + `phase == .playing` retained,
      re-attempts observed at backoff schedule under `TestClock` (US1-1, FR-310-03);
      (b) dead server at `start()`: `.failed` + `failureReason == .transient`, then fake
      recovers → `.playing` within one current-backoff interval, no user input (US1-2,
      SC-310-01); (c) recovery resets backoff — fail, recover, fail: next delay ~1 s
      (US1-3/4); (d) `retry()` during a pending 5-min backoff: immediate attempt + reset
      (US1-5, FR-310-04); (e) `.unauthorized`: `failureReason == .authentication`, observed
      delays ≈ cap (US1-6, FR-310-05). **Test design inline — do not delegate (CLAUDE.md:
      shared/concurrent state, timing).**

### Implementation for User Story 1

- [x] T006 [US1] Green: `RetryPolicy` + `Configuration` + `SlideshowFailureReason` + `classify`
      in `Packages/SlideshowKit/Sources/SlideshowKit/RetryPolicy.swift` per
      contracts/slideshow-resilience-api.md (depends on T005)
- [x] T008 [US1] Green: retry loop in
      `Packages/SlideshowKit/Sources/SlideshowKit/SlideshowViewModel.swift` — `retryPolicy`
      init param (default `RetryPolicy()`), `failureReason` published property,
      `retryTask` (weak-self detached, `runTask` style), pending-retry context (source reload
      vs reload-from-cursor, research R4), failure paths in `start()`/`step()` keep the
      current image when one exists (FR-310-03) instead of unconditional `.failed`, manual
      `retry()` also allowed while a retry is pending + resets backoff, `pause()` cancels /
      `start()` rebinds the retry task (depends on T006, T007)
- [x] T009 [US1] Auth-actionable message variant (FR-310-05: "check your connection settings"
      copy) behind a failure-reason input in
      `Immich Slideshow/Slideshow/SlideshowErrorView.swift`; keep accessibility IDs
      `slideshow.error`/`slideshow.retry` stable; `#Preview` renders both variants
- [x] T010 [US1] Pass `viewModel.failureReason` into `SlideshowErrorView` at
      `Immich Slideshow/Slideshow/SlideshowView.swift` (error-state branch, ~line 199)

**Checkpoint**: `cd Packages/SlideshowKit && swift test` green; error view preview shows both
variants. US1 fully functional — this is the release-gate core.

---

## Phase 4: User Story 2 — New photos appear without a restart (Priority: P1)

**Goal**: The active source's asset list re-fetches hourly (foreground); additions enter
rotation per the active order, removals leave it, the on-screen photo and cycle are never
disturbed; a failed refresh leaves the stale rotation playing and hands over to US1's retry.

**Independent Test**: quickstart.md scenarios 6–10 — start playback against the fake, mutate
the fake's asset list, advance `TestClock` past `refreshInterval`, assert rotation contents,
cursor stability, and exactly-one-fetch; empty list → `.empty`.

> Codex delegation: T011+T012 are the second well-scoped pure-logic pair (handover explicitly
> names rotation reconciliation as a good briefing). T013–T014 inline (engine concurrency).

### Tests for User Story 2 (red first) ⚠️

- [x] T011 [P] [US2] Red:
      `Packages/SlideshowKit/Tests/SlideshowKitTests/RotationReconcilerTests.swift` — the six
      data-model.md invariants: output always a full permutation of the new list; identical
      list ⇒ inputs returned unchanged; sequential ⇒ identity order, cursor anchored on
      `currentAssetID`; shuffle ⇒ played prefix and pending suffix preserve relative order,
      removed assets drop out, additions land only in the unplayed remainder (seeded RNG),
      exactly-once-per-cycle holds; removed current ⇒ cursor before its successor (next
      advance shows the successor; at cycle end, a new cycle starts) (FR-310-07/08,
      SC-310-02/03)
- [x] T013 [US2] Red: US2 scenarios in
      `Packages/SlideshowKit/Tests/SlideshowKitTests/SlideshowResilienceTests.swift` —
      (a) advancing 60 min triggers exactly one `assets()` re-fetch; `currentAssetID`, the
      pending tick deadline, and the cursor are untouched (US2-1/3, FR-310-06/07, SC-310-05);
      (b) added asset enters per order — sequential at album position, shuffle within the
      current cycle's remainder (US2-2, SC-310-02); (c) removed asset never shown again;
      removed *current* stays until next advance, then skipped, no crash/blank (US2-5,
      SC-310-03); (d) refresh failure: stale rotation keeps playing, retry loop engages, no
      error surface (US2-4, FR-310-09); (e) refresh returns empty ⇒ `.empty` (US2-6).
      **Inline — timing/concurrent state.**

### Implementation for User Story 2

- [x] T012 [US2] Green: `RotationReconciler.reconcile(...)` in
      `Packages/SlideshowKit/Sources/SlideshowKit/RotationReconciler.swift` per
      contracts/slideshow-resilience-api.md (depends on T011)
- [x] T014 [US2] Green: refresh loop in
      `Packages/SlideshowKit/Sources/SlideshowKit/SlideshowViewModel.swift` — `refreshTask`
      sleeping to `lastSuccessfulRefresh + config.refreshInterval` on the injected clock;
      success ⇒ reconcile via `RotationReconciler` + stamp `lastSuccessfulRefresh` + reset
      backoff + re-point prefetch, no phase/ticker/image writes (FR-310-07); failure ⇒ hand
      to retry loop, whose success is itself the refresh (research R4); empty ⇒ `.empty`;
      runs across `.playing`/`.empty`/`.failed`; `start()` rebinds (depends on T012, T013;
      same file as T008 — sequential after Phase 3)

**Checkpoint**: `swift test` green — both P1 stories done; the release gate's functional scope
is complete.

---

## Phase 5: User Story 3 — Coming back to the foreground stale (Priority: P2)

**Goal**: No retry/refresh timer fires while backgrounded; on foreground return, a stale list
refreshes immediately and a pending retry resumes (immediately if overdue).

**Independent Test**: quickstart.md scenario 11 — `pause()`, advance `TestClock` hours (zero
fetches), `resume()` ⇒ immediate refresh and overdue retry fires.

### Tests for User Story 3 (red first) ⚠️

- [x] T015 [US3] Red: US3 scenarios in
      `Packages/SlideshowKit/Tests/SlideshowKitTests/SlideshowResilienceTests.swift` —
      (a) after `pause()`, advancing the clock far past both deadlines produces zero API
      calls (US3-2, FR-310-10); (b) `resume()` with `now - lastSuccessfulRefresh >
      refreshInterval` triggers an immediate refresh (US3-1); (c) a retry pending at
      `pause()` resumes on `resume()` — remaining delay if not due, immediately if overdue
      (US3-3); (d) re-arm happens even while `isPaused == true` (user-paused frame still
      refreshes/recovers; ticker stays stopped — research R7). **Inline.**

### Implementation for User Story 3

- [x] T016 [US3] Green: `pause()` cancels `retryTask`/`refreshTask` (due instants survive as
      stored monotonic state); `resume()` re-arms both with overdue-fires-immediately,
      independent of `isPaused`, in
      `Packages/SlideshowKit/Sources/SlideshowKit/SlideshowViewModel.swift` (depends on T015)

**Checkpoint**: all three stories green on the host suite.

---

## Phase 6: Polish & Cross-Cutting Concerns

- [x] T017 Red+Green: source-switch rebind test in
      `Packages/SlideshowKit/Tests/SlideshowKitTests/SlideshowResilienceTests.swift` —
      `switchAlbum` while a retry is pending: old timers dead (no fetch against the old
      album), new source fetched fresh, backoff and `lastSuccessfulRefresh` reset
      (FR-310-11, quickstart 12); fix `start()` teardown if red reveals a leak
- [x] T018 [P] Long-run soak test (SC-310-06) in
      `Packages/SlideshowKit/Tests/SlideshowKitTests/SlideshowResilienceTests.swift` —
      scripted loop of network flaps + refreshes + advances under `TestClock`; ends
      `.playing`, `ImageCache` count within `cacheLimit`
- [x] T019 [P] Secret audit of every new failure path (FR-310-13): grep/review the 310 diff in
      `Packages/SlideshowKit/Sources/SlideshowKit/` — no API key, shared-link password, or
      URL query secrets in log/error strings (existing `ImmichClient` status+path style only)
- [x] T020 Verification gate (Claude-owned): XcodeBuildMCP build of the app scheme + `test_sim`
      on the app-hosted test classes (whole classes — memory
      `xcodebuildmcp-single-test-false-green`); confirm the two `SlideshowViewModel` build
      sites in `Immich Slideshow/Immich_SlideshowApp.swift` need no change (clock default
      parameter) or inject `ContinuousSlideshowClock()` explicitly if the team prefers it
      visible
- [x] T021 Full XCUITest suite via XcodeBuildMCP `test_sim` (SwiftUI files touched — repo
      rule, memory `run-full-xcuitest-before-merge`); screenshot-verify the auth-variant
      error state if a `--uitest` seam reaches it, else preview evidence from T009
- [x] T022 [P] Docs: add FR-310-*/SC-310-* → test mapping to `docs/spec-traceability.md`;
      flip `specs/310-slideshow-resilience/spec.md` Status from "Planned" to reflect
      implementation; note the delivered scope in `docs/spec-overview.md` if it lists 310's
      state
- [x] T023 Run the quickstart.md validation pass end-to-end (host gate + simulator gates);
      optional live smoke per its "Manual smoke" section on the real frame

---

## Dependencies & Execution Order

### Phase Dependencies

- **Phase 2 (Foundational)**: starts immediately (no setup phase) — BLOCKS all stories.
  Internal order: T001 → T002 (TestClock conforms to the protocol); T003 [P] anytime;
  T004 after T001.
- **Phase 3 (US1)**: after Phase 2. MVP — the release gate's heart.
- **Phase 4 (US2)**: after Phase 2 for T011/T012 (pure logic, could start in parallel with
  US1); T013/T014 after Phase 3 (same `SlideshowViewModel.swift` + refresh hands failures to
  the retry loop).
- **Phase 5 (US3)**: after Phase 4 (re-arms both task kinds).
- **Phase 6 (Polish)**: after Phase 5; T018/T019/T022 parallel; T021 last before merge.

### Within Each User Story

Red before green, always: T005→T006, T007→T008, T011→T012, T013→T014, T015→T016. UI tasks
(T009, T010) after T008 (they render state the engine must produce).

### Parallel Opportunities

- T003 alongside T001/T002 (different files).
- T005 (RetryPolicyTests) ∥ T011 (RotationReconcilerTests) — both pure-logic red suites, both
  Codex-delegable with their green counterparts as two independent briefings.
- T018 ∥ T019 ∥ T022 in Polish.

### Codex Delegation Map (CLAUDE.md orchestration)

| Slice | Tasks | Why delegable |
|---|---|---|
| Retry-policy type | T005+T006 | Pure value math, no concurrency, self-contained file pair |
| Rotation reconciliation | T011+T012 | Pure diff logic, exhaustive host tests, named in the handover |
| Everything else | T001–T004, T007–T010, T013–T023 | Timer/race test design, engine concurrency, SwiftUI/simulator, verification gate — inline per house rules |

---

## Implementation Strategy

### MVP First (US1 only)

1. Phase 2 (foundation) → Phase 3 (US1 auto-retry).
2. **STOP and VALIDATE**: host suite green; a frame that survives outages is already the
   critical release property (spec: "the difference between a demo and an appliance").

### Incremental Delivery

US1 → US2 (both P1, together they close the pre-release gate) → US3 (P2 polish of the same
machinery) → Phase 6 gates → then the release checklist in
`docs/handover-release-prep.md` (version bump, archive, upload).

---

## Notes

- Both P1 stories must land before the App Store submission (spec: pre-release gate); US3 is
  strongly recommended (frames sleep every night) but is a P2 by spec.
- Commit after each red+green pair or logical group; stage with explicit paths, never `-A`.
- `SlideshowResilienceTests.swift` is shared by T002/T007/T013/T015/T017/T018 — those tasks
  are deliberately sequential; only the two pure-logic suites fan out.
