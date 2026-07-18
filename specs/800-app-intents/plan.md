# Implementation Plan: App Intents (Shortcuts, Siri, Apple Automations)

**Branch**: `800-app-intents` | **Date**: 2026-07-17 | **Spec**: `specs/800-app-intents/spec.md`

**Input**: Feature specification from `/specs/800-app-intents/spec.md`

## Summary

Expose the frame's existing remote-control command surface as App Intents: seven
intents (pause, resume, next, previous, set brightness, select source, read state)
that call the **same** `SlideshowRemoteControlAdapter` instance Home Assistant
drives — no second command path. Technical approach (research R1–R9): a new
framework-free `Packages/AppIntentsKit` carries all logic
(`FrameControlRegistry` + `FrameCommandService`, host-tested); the app target adds
only thin `AppIntent`/`AppEntity` shells resolved via `AppDependencyManager`, an
`AppShortcutsProvider` with app-name phrases, and one enabling refactor: the
adapter's construction is hoisted out of the broker-gated HA path so the command
surface exists for every user, HA or not. Control intents foreground the app
(`openAppWhenRun`, unattended-safe); the read intent never does; every failure is
a readable, localized error — never a silent no-op.

## Technical Context

**Language/Version**: Swift 6 (strict concurrency; package is `@MainActor`-typed
like HAControlKit)

**Primary Dependencies**: AppIntents framework (app target only, iOS 16+ API on
the iOS 17 floor — no availability gates); HAControlKit protocols
(`PlaybackControlling`, `PhotoReporting`, `PhotoReport`) — no new third-party
dependencies; no MQTT linkage (HAControlMQTT product not imported)

**Storage**: none new — source options read through an injected closure over the
existing topic-120 source-library store; nothing the intents layer persists

**Testing**: Swift Testing on the host for all package logic (`swift test` in
`Packages/AppIntentsKit`); app-hosted glue suite + existing adapter/HA round-trip
suites via XcodeBuildMCP; manual device gates for Siri/automation surfaces
(quickstart.md)

**Target Platform**: iPadOS/iOS 17+ (iPad-first); `ControlWidget` and other
iOS-18-only surfaces are explicitly Roadmap, not gated in

**Project Type**: mobile app + SPM packages (existing structure; one package added)

**Performance Goals**: intent `perform()` returns promptly on a live engine
(sub-second; no network on any control path — select triggers the same async
restart the HA select does); `awaitReady` cold-launch grace capped at ~5 s

**Constraints**: foreground-only brightness (Constitution V — honesty codified in
FR-800-04); unattended automation compatibility (no confirmation prompts, no
parameter prompts); ≤10 App Shortcuts (7 used); English-only strings (FR-300-30);
no secrets/bytes in intent results (FR-800-07)

**Scale/Scope**: 7 intents, 1 new package (~6 source files), ~4 app-target files,
1 docs page; touches `Immich_SlideshowApp.swift` (hoisting) and
`SlideshowRemoteControlAdapter.swift` (`updateAlbums` post-init injection)

## Constitution Check

*GATE: evaluated pre-Phase-0 and re-checked post-design — PASS (no violations,
one documented note).*

- **I. Test-First (NON-NEGOTIABLE)** — PASS. All logic lands in AppIntentsKit via
  red-first Swift Testing pairs; the hoisting refactor is pinned by the existing
  app-hosted suites staying green plus a new same-instance glue test. Tasks phase
  must emit test-before-implementation pairs per slice.
- **II. Modular Isolation** — PASS with note. Service and registry depend only on
  the HAControlKit protocols; fakes drive every host test; time is injected
  (`awaitReady` clock). Note: `AppDependencyManager` is the platform's mandated
  container for intent structs (the system instantiates them — constructor
  injection is impossible). It is confined to the app-target shells, registered
  once at the composition root, and never touched by the package; this is the
  documented seam, not a hidden singleton.
- **III. No Secrets in Plaintext (NON-NEGOTIABLE)** — PASS. The read-model is a
  structural whitelist (six fields, no byte/URL/ID-capable members); host test
  locks it (SC-800-04). Nothing is written anywhere by the intents layer.
- **IV. Transport-Layer Security** — PASS (n/a — no new transport; no network in
  the intents layer).
- **V. Respect Platform Boundaries** — PASS. Foreground-only brightness is stated,
  not fought: control intents foreground the app; failures are explicit; the docs
  page names the unlocked-device assumption. No background-execution tricks.
- **VI. Verifiable Acceptance Criteria** — PASS. SC-800-01/04/05 are host tests;
  SC-800-03 and SC-800-02 are scripted manual gates in quickstart.md.
- **VII. Plain and Light by Default** — PASS. No UI/default changes; intents are
  an opt-in control surface.

## Project Structure

### Documentation (this feature)

```text
specs/800-app-intents/
├── plan.md              # This file
├── research.md          # Phase 0 — R1..R9 decisions
├── data-model.md        # Phase 1 — registry, service, snapshot, errors, shells
├── quickstart.md        # Phase 1 — validation gates incl. manual device checklist
├── contracts/
│   └── app-intents-surface.md   # The externally observable Shortcuts/Siri contract
└── tasks.md             # Phase 2 (/speckit-tasks — NOT created by /speckit-plan)
```

### Source Code (repository root)

```text
Packages/AppIntentsKit/
├── Package.swift                          # deps: ../HAControlKit (protocols only)
├── Sources/AppIntentsKit/
│   ├── FrameControlRegistry.swift         # register/unregister, isConfigured, awaitReady(clock)
│   ├── FrameCommandService.swift          # the 7 verbs; validation; error taxonomy
│   ├── FrameStateSnapshot.swift           # structural whitelist read-model
│   ├── SourceOption.swift                 # id+label projection of topic-120 Source
│   └── FrameCommandError.swift            # closed error enum
├── Sources/AppIntentsTestSupport/
│   └── RecordingControlSurface.swift      # recording fake: PlaybackControlling + PhotoReporting
└── Tests/AppIntentsKitTests/
    ├── FrameCommandServiceTests.swift     # HA-parity call sequences (SC-800-01)
    ├── BrightnessValidationTests.swift    # reject-not-clamp; % → 0…1 mapping
    ├── SourceSelectTests.swift            # resolve, stale id, label parity
    ├── FrameStateSnapshotTests.swift      # privacy whitelist (SC-800-04)
    └── RegistryTests.swift                # states, awaitReady + test clock

Immich Slideshow/Intents/                  # (synchronized group — no pbxproj edit)
├── FrameIntents.swift                     # 7 thin AppIntent shells + localized error mapping
├── SourceEntity.swift                     # AppEntity + query over registry.sourceOptions
├── FrameStateEntity.swift                 # TransientAppEntity mirror of the snapshot
└── FrameAppShortcuts.swift                # AppShortcutsProvider, 7 phrases

Immich Slideshow/Immich_SlideshowApp.swift # hoist adapter out of makeCoordinator;
                                           # registry registration per connectionGeneration;
                                           # AppDependencyManager.register at init
Immich Slideshow/Slideshow/SlideshowRemoteControlAdapter.swift
                                           # + updateAlbums(_:) post-init injection
Immich SlideshowTests/
└── FrameIntentGlueTests.swift             # shells→service forwarding; same-instance invariant

docs/automation-recipes.md                 # FR-800-10 — night/morning recipes, boundaries
```

**Structure Decision**: mirrors the established package pattern (logic in an SPM
package with test support + host tests; the app target holds only platform glue).
AppIntentsKit sits beside HAControlKit as the second consumer of the same control
protocols — the dependency arrow goes intents → HAControlKit-protocols, never the
reverse, and BrokerSetupKit/HAControlMQTT stay untouched.

## Complexity Tracking

No constitution violations — table intentionally empty.
