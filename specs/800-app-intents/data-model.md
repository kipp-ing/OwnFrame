# Data Model: App Intents (800)

**Date**: 2026-07-17 | **Spec**: `specs/800-app-intents/spec.md` | **Research**: `research.md`

Everything below lives in `Packages/AppIntentsKit` unless marked *(app target)*.
The package imports Foundation + HAControlKit (protocols only) — no AppIntents.

## FrameControlRegistry (`@MainActor`, class)

The process-stable handle the app registers once in `AppDependencyManager` and the
per-generation adapter plugs into (research R2/R3/R8).

| Member | Type | Notes |
|---|---|---|
| `register(_:)` | `(any PlaybackControlling & PhotoReporting) -> Void` | Called by the slideshow composition point per generation; replaces the previous instance. Held **weak** — a torn-down generation never keeps an engine alive (the 900 no-leaked-timers discipline). |
| `unregister()` | `() -> Void` | Generation teardown. |
| `isConfigured` | `Bool` | Flipped by the app from the existing startup gate; `false` → onboarding incomplete. |
| `sourceOptions` | `() -> [SourceOption]` | Injected closure; the app wires it to the same source-library load the HA select list uses. |
| `state` | `RegistryState` | `.ready(surface)` / `.notConfigured` / `.notLive` (derived: not configured beats not live). |
| `awaitReady(timeout:)` | `async throws -> any PlaybackControlling & PhotoReporting` | Bridges the `openAppWhenRun` cold-launch race; injected `clock` for tests; throws `FrameCommandError.frameNotOpen` on timeout, `.notConfigured` immediately when unconfigured. |

State transitions: `notConfigured → notLive` (onboarding completes) `→ ready`
(adapter registers) `→ notLive` (unregister / generation rebuild) `→ ready` (next
generation). Never back to `notConfigured` except full reset.

## SourceOption (struct, `Sendable`, `Equatable`, `Identifiable`)

The package-neutral projection of topic-120's `Source` (research R4).

| Field | Type | Rule |
|---|---|---|
| `id` | `String` | `Source.id` — stable across renames. |
| `label` | `String` | `Source.label` — what HA's select shows; display name of the entity. |

No `kind`, no URLs, no collection IDs — nothing an automation could leak.

## FrameCommandService (`@MainActor`, struct)

All intent logic; constructed with the registry (shells) or fakes (tests). One
method per intent verb — the shells stay one-call thin (research R2, FR-800-09).

| Method | Contract |
|---|---|
| `pause()` | `awaitReady` → `surface.pause()` — identical call the HA switch makes; idempotent when already paused (adapter guard). |
| `resume()` | → `surface.resume()`. |
| `nextPhoto()` | → `surface.showNext()` — steps without resuming when paused (topic 710 US3 parity). |
| `previousPhoto()` | → `surface.showPrevious()`. |
| `setBrightness(percent: Int)` | Validate `0...100` else throw `.brightnessOutOfRange(percent)` (state untouched); map `percent/100.0` → `surface.setBrightness(_:)` (research R5). |
| `selectSource(id: String, label: String)` | Resolve id in `registry.sourceOptions()` BEFORE `awaitReady` (a stale id fails fast even when the frame is closed); missing → throw `.sourceMissing(label:)` carrying the caller's `label` (error payload only), state untouched; found → `surface.selectAlbum(option.label)` with the label resolved from the library — the byte-identical HA path (research R4). |
| `frameState()` | Build `FrameStateSnapshot` from `surface` (below). Requires `.ready` — never guesses (R1). |

## FrameStateSnapshot (struct, `Sendable`, `Equatable`)

The whitelisted read-model (FR-800-07, research R6). Built exclusively by
`FrameCommandService.frameState()`; the app-target `FrameStateEntity` mirrors it
field-for-field.

| Field | Type | Source | Excluded by construction |
|---|---|---|---|
| `isPlaying` | `Bool` | `surface.playbackState == .playing` | — |
| `brightnessPercent` | `Int` | `round(surface.brightness * 100)` | — |
| `sourceLabel` | `String?` | `surface.currentAlbum` | — |
| `photoDate` | `Date?` | `currentPhotoReport.takenAt` | `assetID`, `imageData` |
| `photoCity` | `String?` | `currentPhotoReport.city` | `state` (region) — coarse means city+country only |
| `photoCountry` | `String?` | `currentPhotoReport.country` | `albumID`, `phase`, `photoCount`, `version` |

Privacy invariant (SC-800-04, host-tested): the snapshot type *has no fields* that
could carry bytes, IDs, URLs, or secrets — exclusion is structural, not a filter
that could regress.

## FrameCommandError (enum, `Error`, `Equatable`)

The closed error taxonomy; shells map cases 1:1 to localized
`AppIntentError`-style messages *(app target owns the copy)*.

| Case | Shell copy (English, FR-300-30) | Trigger |
|---|---|---|
| `.notConfigured` | "Set up the frame first — open Photo Frame and add a source." | Registry unconfigured (spec edge: onboarding). |
| `.frameNotOpen` | "Photo Frame must be open on the frame device for this." | `.notLive` after `awaitReady` timeout (spec edge: backgrounded/killed; FR-800-04). |
| `.brightnessOutOfRange(Int)` | "Brightness must be between 0 and 100 percent." | US1 acceptance 4. |
| `.sourceMissing(label: String)` | "This source no longer exists in the frame's library." | Spec edge: deleted source; state unchanged. |

## App-target shells *(app target, `Immich Slideshow/Intents/`)*

Thin conformances only — no logic, no state (research R2):

- `PauseSlideshowIntent`, `ResumeSlideshowIntent`, `NextPhotoIntent`,
  `PreviousPhotoIntent`, `SetBrightnessIntent` (Int parameter, `inclusiveRange`
  0–100), `SelectSourceIntent` (`SourceEntity` parameter), `GetFrameStateIntent` —
  each: resolve the registry via `FrameIntentContext.requireRegistry()` (the
  composition seam — see research R2 amendment for why not `@AppDependency`),
  call the matching service method, map `FrameCommandError` to localized errors.
  Control intents `openAppWhenRun = true`; the read intent `false` (research R1).
- `SourceEntity: AppEntity` — `id`/`label` from `SourceOption`; query answers
  `entities(for:)` and `suggestedEntities()` from `registry.sourceOptions()`.
- `FrameStateEntity: TransientAppEntity` — mirrors `FrameStateSnapshot`.
- `FrameAppShortcuts: AppShortcutsProvider` — 7 shortcuts, phrases per research R7.

## Relationships

```text
Shortcuts/Siri/Automation
        │  (AppShortcuts phrases, FR-800-03)
        ▼
AppIntent shells (app target) ── @Dependency ──▶ FrameControlRegistry ◀── register/unregister
        │                                              │        ▲            (per connectionGeneration)
        ▼                                              │        │
FrameCommandService ── awaitReady ─────────────────────┘   SlideshowRemoteControlAdapter
        │                                                  (ONE instance, hoisted out of the
        └── PlaybackControlling + PhotoReporting ─────────▶ HA-only path — also serves
            (HAControlKit protocols — same calls HA makes)  HAControlCoordinator when a broker exists)
```
