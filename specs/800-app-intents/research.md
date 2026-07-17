# Research: App Intents (800)

**Date**: 2026-07-17 | **Spec**: `specs/800-app-intents/spec.md` | **Plan**: `plan.md`

Phase 0 output. Every unknown from the Technical Context is resolved here as
Decision / Rationale / Alternatives. Platform statements were verified against the
App Intents framework as of the current SDK (App Intents is iOS 16+; the app's floor
is iOS 17, so nothing here needs an availability gate — the one iOS-18-only surface,
`ControlWidget`, is explicitly Roadmap and out of scope).

---

## R1 — Where intents execute, and the foreground mechanic per intent

**Decision**: All `AppIntent` conformances live in the **app target**, so intents run
**in the app's process**. The six control intents (pause, resume, next, previous,
set brightness, select source) declare `static let openAppWhenRun = true`. The
state-read intent declares `openAppWhenRun = false`. `ForegroundContinuableIntent`
is **not** used.

**Rationale**:

- In-app intents execute in the app process: when the app is running, `perform()`
  can touch the live `@MainActor` engine directly — exactly what "same command path
  as topic 700" (FR-800-02) needs. When the app is *not* running, the system launches
  it in the background to run the intent — which is precisely the state where the
  live slideshow does not exist; the handler then fails readably (FR-800-04).
- `openAppWhenRun = true` is the only foreground mechanic that is **unattended-safe**:
  when the app is already frontmost (the frame's normal state) it is a no-op, and
  when it is not, the system brings the app forward *without a confirmation prompt* —
  so the 22:00 automation runs with zero interaction (FR-800-05, US2).
  `ForegroundContinuableIntent.needsToContinueInForegroundError` by contrast requires
  a user tap to continue — it would silently break unattended automations, so it is
  rejected.
- The read intent must never yank the frame to the foreground just to answer a
  question; with `openAppWhenRun = false` it answers in-process when the engine is
  live and throws a readable "the frame isn't open" error otherwise — never a
  guessed answer (honesty over convenience, Constitution V).
- Locked-device caveat for the docs page (FR-800-10): opening an app from an
  automation requires the device to be unlocked. The frame's documented operating
  mode (dedicated device, Guided Access, never locked) already satisfies this; the
  recipe page states it plainly.

**Alternatives considered**:

- *App-Intents extension target*: runs without the app, but then there is no live
  engine at all — every control intent would need an IPC bridge back into the app
  (a second command path, forbidden by FR-800-02). Rejected.
- *`ForegroundContinuableIntent` for brightness only*: prompts on continuation —
  breaks US2 unattended requirement. Rejected.
- *Silently succeeding while backgrounded* (mirror the target, apply later): the
  PowerManager already mirrors the requested target and applies it on next
  foreground, but *pretending* success while the panel stays bright is exactly what
  FR-800-04 forbids. With `openAppWhenRun = true` the app is foregrounded first, so
  the brightness genuinely applies; the mirror only papers over the (rare) window
  while the foregrounding animation completes.

## R2 — Package home, DI, and how thin shells reach the live adapter

**Decision**: A new SPM package **`Packages/AppIntentsKit`** holds *all* intent
logic, framework-free (no `import AppIntents`): a `FrameControlRegistry` (the
handle to the live command surface), a `FrameCommandService` (validation, error
taxonomy, snapshot building), and the value/error types. The app target keeps only
thin `AppIntent`/`AppEntity` shells that resolve the registry via App Intents'
`@Dependency` (registered once in `AppDependencyManager` at app start) and forward
to the service. AppIntentsKit depends on **HAControlKit** (the `PlaybackControlling`
and `PhotoReporting` protocols plus `PhotoReport`) and nothing else.

**Rationale**:

- FR-800-09 / SC-800-05 demand host-`swift test`ability of all intent logic; the
  AppIntents framework's structs are awkward to instantiate under test and drag
  metadata extraction into the package build. Keeping the package framework-free
  makes every behavior a plain unit test — the spec's own assumption ("an
  `AppIntentsKit` package wraps the logic while the `AppIntent` conformances stay
  in the app target").
- Reusing HAControlKit's protocols is the literal enforcement of "no second command
  path": the intents see the **same** `SlideshowRemoteControlAdapter` instance,
  through the same protocol methods HA calls. The `HAControlKit` *product* is
  protocol + coordinator logic only — MQTT (mqtt-nio/NIOSSL) links solely into the
  separate `HAControlMQTT` product, so AppIntentsKit inherits no transport.
- `AppDependencyManager` is the platform's sanctioned way to hand dependencies to
  intent structs (the system instantiates them; init injection is impossible).
  Constitution II's "no hidden singletons" is honored by registering exactly one
  object — the `FrameControlRegistry` — at the app's composition root, and by the
  package never touching `AppDependencyManager` at all (shells pass the registry
  into the service; tests inject fakes directly).
- The registry (not the adapter) is registered because the adapter is **per
  slideshow generation** (see R3): `SlideshowView` is keyed by
  `connectionGeneration`, and every source switch/connection change rebuilds it.
  The registry is process-stable; the adapter registers/unregisters into it.

**Alternatives considered**:

- *Intents + logic all in the app target*: no host tests (app-hosted tests need the
  simulator) — violates SC-800-05. Rejected.
- *AppIntent conformances inside the package* (`AppIntentsPackage` metadata
  extraction works in SPM packages on current Xcode): possible, but it forces
  `import AppIntents` into the package, couples host tests to the framework, and
  buys nothing — the shells are ~10 lines each. Rejected.
- *A new neutral protocol in AppIntentsKit that the adapter also conforms to*:
  duplicates `PlaybackControlling` verbatim and invites drift; the HAControlKit
  dependency is cheaper than a parallel protocol surface. Rejected.

## R3 — The command surface must exist without a broker (refactor delta)

**Decision**: Hoist construction of `SlideshowRemoteControlAdapter` **out of
`makeCoordinator`** (today it is built inside the HA path and only when a broker
config exists — `Immich_SlideshowApp.swift:329-388`). The slideshow composition
point builds **one** adapter per slideshow generation unconditionally (synchronous —
sources come from the already-loaded library), registers it with the
`FrameControlRegistry`, and passes it *into* `makeCoordinator(adapter:)`, which
keeps its broker gate and its async best-effort `albums()` fetch. The album list
becomes a post-init injection (`adapter.updateAlbums(_:)`) instead of an init
parameter fed by the async fetch.

**Rationale**:

- Without this, App Intents would only work for users who configured MQTT — absurd
  for the "HomeKit-ish control without HA" story (US2). The adapter itself has no
  broker dependency; only its construction site does.
- One shared instance is load-bearing, not cosmetic: the adapter mirrors state
  (brightness target, `currentAlbum`, pause observation). Two instances would
  answer HA and Siri with diverging state — the exact drift FR-800-02 exists to
  prevent.
- `updateAlbums(_:)` is additive; the existing `albums:` init parameter keeps its
  default so `SlideshowRemoteControlAdapterTests` and `HAControlRoundTripTests`
  compile unchanged. In the 900 world the select options come from `sources`
  anyway; `albums` only enriches photo reports (name/count) and the legacy
  no-library fallback.

**Alternatives considered**:

- *Second adapter for intents*: state divergence (above). Rejected.
- *Registry falls back to a lazily-built adapter when HA never ran*: two
  construction paths, subtle ordering bugs. Rejected.
- *Move the adapter into a package*: it imports UIKit/ImmichClient/SlideshowKit and
  is deliberately the app-side bridge; moving it is churn with no testability gain
  (its logic is already covered app-hosted). Rejected.

## R4 — Source entity, options, and select parity

**Decision**: `SourceEntity` (app target, `AppEntity`) is `id` + `label`, backed by
a query that reads the registry's injected `sourceOptions` closure — the app wires
it to the same source library load the HA select list uses. Selection resolves the
entity id against the *current* library; a missing id throws
`.sourceMissing` ("This source no longer exists…") and changes nothing; a found
source is applied by calling **`selectAlbum(label)`** — the byte-identical HA path
(label → `onSelectSource(source.id)` → app-level switch with
`SourceRestartStrategy`).

**Rationale**: FR-800-06 demands the options equal the HA select's list and the
switch reuse its restart strategy; the cheapest correct way is to *call the same
method*. Selecting by entity **id** (not label) at the Shortcuts layer makes saved
automations robust against renames-with-same-id, while the final hop stays
label-based for parity. Label collisions behave exactly like HA (first match wins) —
documented, not "fixed", to keep one behavior.

**Alternatives considered**: adding a `selectSource(id:)` to the adapter — a second
select path with its own edge cases; rejected for parity. Depending on OnboardingKit
from AppIntentsKit just to see `Source` — pulls ImmichClient into the package for
two fields; an injected `(id, label)` pair list keeps the package lean. Rejected.

## R5 — Brightness semantics at the intent boundary

**Decision**: The parameter is an **Int percent, declared 0–100** in the Shortcuts
UI (`inclusiveRange`), and `FrameCommandService.setBrightness(percent:)`
**rejects** out-of-range values (readable error, state untouched) rather than
clamping, then maps valid input to topic 400's `0.0–1.0` and calls the adapter's
`setBrightness` (which clamps redundantly, as it does for HA).

**Rationale**: US1 acceptance 4 explicitly wants out-of-range → error, not silent
clamping — Shortcuts variables can carry any Int regardless of the UI range, so the
service must validate. Inside the valid range the mapping and side effects are
bit-identical to the HA light entity (FR-800-08).

## R6 — Frame state result shape

**Decision**: The read intent returns a **transient entity** (`TransientAppEntity`)
`FrameStateEntity` with exactly: `isPlaying: Bool`, `brightnessPercent: Int`,
`sourceLabel: String?`, `photoDate: Date?`, `photoCity: String?`,
`photoCountry: String?` — built in the package as `FrameStateSnapshot` from
`PlaybackControlling` state + `PhotoReporting.currentPhotoReport`, **dropping**
`imageData`, `assetID`, `albumID`, `state` (region), `phase`, and `photoCount`.

**Rationale**: A transient entity gives Shortcuts named, typed properties to branch
on (US3) without persisting anything. The field whitelist is FR-800-07 verbatim
(playback, brightness, source label, date, coarse location); everything else in
`PhotoReport` — above all the image bytes — is filtered in the package, where a
host test (SC-800-04) locks it: a fully-populated fake report in, snapshot out,
assert the six fields and *only* the six fields. City/country stay coarse and are
`nil` for Photos-backed sources by construction (900, R7 — no geocoding upstream).

**Alternatives considered**: returning a dictionary/string — loses typed branching;
returning `PhotoReport` — leaks bytes and IDs. Both rejected.

## R7 — App Shortcuts and Siri phrases

**Decision**: One `AppShortcutsProvider` in the app target with **7 App Shortcuts**
(one per intent — under the platform cap of 10), every phrase containing
`\(.applicationName)` ("Pause \(.applicationName)", "Set \(.applicationName)
brightness", …). English-only (FR-300-30 policy). The select-source and brightness
shortcuts use parameterized phrases where supported but resolve fine without.

**Rationale**: FR-800-03 (works with zero manual setup) is exactly what
`AppShortcutsProvider` exists for; the mandatory app-name token plus verb phrasing
("Pause Photo Frame") keeps clear of HomeKit's "pause the living room" namespace
(edge case: phrase collisions).

## R8 — Onboarding / not-running / timing edge cases

**Decision**: The registry distinguishes three answers when a shell asks for the
command surface: `.ready(adapter)`, `.notConfigured` (app has never completed
onboarding — the app flips a flag on the registry from its existing startup gate),
and `.notLive` (configured but no slideshow generation registered). Shells map these
to two localized errors: "Set up the frame first…" and "Open Photo Frame on the
frame device…". After `openAppWhenRun` foregrounds a cold-launched app, the
slideshow needs a beat to build; the registry exposes
`awaitReady(timeout:)` (default ~5 s, injected clock, host-tested) so a control
intent issued at cold start lands instead of racing — on timeout it throws the
`.notLive` error rather than pretending.

**Rationale**: the spec's edge cases demand distinct, honest copy for "never set
up" vs "not open"; the await bridges the openAppWhenRun launch race without any
polling loop in the shells. An injected clock keeps it deterministic under
`swift test` (Constitution II).

## R9 — Test strategy

**Decision**:

- **Package (host, Swift Testing — the bulk)**: `FrameCommandService` parity tests
  against recording fakes of `PlaybackControlling`/`PhotoReporting` — each intent
  verb produces exactly the call sequence the corresponding HA command produces
  (SC-800-01); brightness validation/mapping; select resolution incl. missing-id;
  snapshot privacy whitelist (SC-800-04); registry states + `awaitReady` timing
  via a test clock.
- **App-hosted (simulator, existing pattern)**: one glue suite proving each
  `AppIntent` shell forwards to the service and maps errors — the same style as
  `SlideshowRemoteControlAdapterTests`. Plus the hoisting refactor keeps
  `HAControlRoundTripTests` green (the round-trip now runs over the hoisted
  adapter).
- **Manual device gates (quickstart)**: SC-800-02 overnight automation, SC-800-03
  Shortcuts/Siri discovery — like the 710 live-HA run.

**Rationale**: matches the constitution's test-first split (logic on host, glue
app-hosted, OS-owned surfaces manual) — automation *triggers* are untestable in CI
by design, so the boundary is drawn at "intent runs unattended", which *is*
testable (no confirmation APIs invoked, parameters fully specified).
