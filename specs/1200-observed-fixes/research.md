# Research: Observed Frame Fixes (1200)

Three decisions, one per fix. No open NEEDS-CLARIFICATION remains.

## R1 — Album-tab failure: distinguish "no server" from "network error"

**Decision**: Split the picker's single `.failed` phase into `noServer` and `failed`. The no-server
branch shows an "add a server" prompt that opens the shared server-connection editor (FR-210-29); the
network branch keeps the existing retryable "Couldn't load albums".

**Rationale**: The data flow already separates them — `makeServerAPI()` returns `nil` with *no
network call* when no base URL + API key is stored, vs. `api.albums()` throwing. Collapsing both into
one message is the whole bug. The predicate ("is a server configured?") is a pure function of the
UserDefaults base URL + Keychain key presence, so it lifts cleanly into an `OnboardingKit` helper for
host testing.

**Alternatives considered**: (a) Reword the single message to mention both causes — rejected: still a
dead-end, doesn't route to the fix. (b) Hide the Album tab entirely when no server — rejected: the
tab is a legitimate discovery affordance; guidance is friendlier than absence.

## R2 — Ken Burns under Fit: centered zoom, pan suppressed

**Decision**: When fit is Fit, render `scaledToFit` and drive Ken Burns as a **centered zoom with
pan = 0**. When fit is Fill, keep today's pan+zoom. Remove the `|| effectiveKenBurns` clause from
`fillsScreen` at both renderer sites.

**Rationale**: The old fill-forcing existed because a *pan* on a fitted (letterboxed) image slides it
and exposes background. Removing the pan removes the reason to force fill: a centered zoom on a fitted
image only shrinks the letterbox bars as it scales up — it never reveals a side gap. `KenBurnsDrift`'s
`startScale = 1.10 → floorScale = 1.0` is safe centered because at 1.0 the image is exactly fitted and
at 1.10 it is slightly larger, still centered. This honors the user's explicit Fit choice (Principle
VII faithfulness) while preserving the judder-free decode-ahead pipeline.

**Alternatives considered**: (a) Keep fill-forcing, document it — rejected by the product decision
(honor Fit). (b) Compute a per-photo pan envelope that stays within the fitted bounds — rejected:
more geometry, more risk, and the aesthetic ("whole photo, gentle zoom") is better served by no pan.
(c) Make Fit and Ken Burns mutually exclusive — rejected: removes a valid combination.

**Risk**: This changes a *shipped* behavior (fill-forced since the 1000 Ken Burns redesign) for the
Fit + Ken Burns case only. Automated tests cover the decision + geometry; perceived motion is a
Framepad manual gate (out of scope for the automated suite).

## R3 — Battery telemetry: event-driven, injected, battery-devices-only

**Decision**: Two read-only diagnostic entities — `battery` (`sensor`, `device_class: battery`, `%`,
`state_class: measurement`) and `charging` (`binary_sensor`, `device_class: battery_charging`). Source
via a new `BatteryReporting` protocol so `HAControlKit` stays UIKit-free; the app adapter reads
`UIDevice.current` with battery monitoring enabled and observes the level/state change notifications.
Both classified read-only (free tier, FR-1100-03a). Added to `enabledEntities` only when a battery is
present → omitted on tvOS.

**Rationale**: Mirrors the existing diagnostic-sensor pattern (`phase`/`photo_count`/`version`,
FR-710-07) and the Modular-Isolation rule (Principle II) — no `UIDevice` in the pure package, so the
discovery payloads and echo are host-testable with a fake transport + injected battery source.
Event-driven avoids a polling loop (Principle V, no wasteful background work). `charging` ON = on
external power (`.charging` or `.full`), which is the useful "is the frame powered?" signal for an
always-on frame.

**Alternatives considered**: (a) Poll battery on a timer — rejected: unnecessary; iOS posts change
notifications. (b) Read `UIDevice` directly in the coordinator — rejected: breaks Modular Isolation
and host testability. (c) `device_class: plug`/`power` for charging — considered; `battery_charging`
chosen to match the literal "charging state" ask, with ON defined as on-power so it still answers the
AC-drop alert use case.

## Cross-cutting

- **Testing seam**: all three fixes are TDD-able on the host (picker predicate, drift/`fillsScreen`
  decision, `HAControlKit` discovery/echo). Only the UI-inset regression (SC-300-13) and the perceived
  Ken Burns motion need the simulator/device.
- **No secret surface changes**: Fix 1 only reads key *presence*; Fixes 2/3 touch no secrets.
- **Existing HA entities untouched** (FR-710-08): battery/charging are additive.
