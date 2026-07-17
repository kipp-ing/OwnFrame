# Contract: The App Intents Surface (800)

**Date**: 2026-07-17 | **Spec**: `specs/800-app-intents/spec.md`

What Shortcuts, Siri, and personal automations can see and rely on. This is the
externally observable contract; internal types are in `data-model.md`. Changing
anything below is a breaking change for users' saved shortcuts and automations —
treat titles, parameter shapes, phrases, result fields, and error behavior as API.

## Intents

| Intent | Title | Parameters | Foreground | Result | HA-parity anchor |
|---|---|---|---|---|---|
| `PauseSlideshowIntent` | Pause Slideshow | — | opens app | done | pause switch → `PlaybackControlling.pause()` |
| `ResumeSlideshowIntent` | Resume Slideshow | — | opens app | done | play switch → `resume()` |
| `NextPhotoIntent` | Next Photo | — | opens app | done | HA next button → `showNext()`; steps without resuming when paused |
| `PreviousPhotoIntent` | Previous Photo | — | opens app | done | HA previous button → `showPrevious()` |
| `SetBrightnessIntent` | Set Frame Brightness | `brightness: Int`, UI range 0–100, required | opens app | done | HA light → `setBrightness(percent/100)` |
| `SelectSourceIntent` | Set Frame Source | `source: SourceEntity`, required, dynamic options | opens app | done | HA select → `selectAlbum(label)` |
| `GetFrameStateIntent` | Get Frame State | — | **never opens app** | `FrameStateEntity` | read-only over the same surface |

Rules every intent obeys:

- **No confirmation prompts, ever** (FR-800-05): no `requestConfirmation`, all
  parameters fully specifiable in the automation editor, `ParameterSummary`
  provided so nothing prompts at run time.
- **No silent no-ops** (FR-800-04): every path either performs the command on the
  live engine or throws one of the errors below.
- **Validation before effect** (FR-800-08): a thrown error leaves frame state
  bit-identical.

## Errors (observable copy, English-only)

| Condition | Error shown in Shortcuts |
|---|---|
| Onboarding never completed | "Set up the frame first — open Photo Frame and add a source." |
| App not running / slideshow not live after the open-app grace (~5 s) | "Photo Frame must be open on the frame device for this." |
| Brightness outside 0–100 (e.g. via a Shortcuts variable) | "Brightness must be between 0 and 100 percent." |
| Source id no longer in the library | "This source no longer exists in the frame's library." |

## `SourceEntity`

- `id`: the topic-120 `Source.id` (opaque string, stable across renames).
- Display: the source **label** — the same string the HA select lists (FR-800-06).
- Options/suggestions: exactly the saved source library at query time — every kind
  (Immich album, shared link, Photos), no filtering, no extras.
- Duplicate labels resolve like HA: first match wins on apply (documented parity).

## `FrameStateEntity` (result of Get Frame State)

Exactly six properties — additions require a spec change; removals are breaking:

| Property | Type |
|---|---|
| `isPlaying` | Bool |
| `brightnessPercent` | Int (0–100) |
| `sourceLabel` | String? |
| `photoDate` | Date? |
| `photoCity` | String? (nil for Photos-backed sources — no geocoding) |
| `photoCountry` | String? (ditto) |

**Never present** (FR-800-07 / SC-800-04): image bytes, asset/album IDs, server
URLs, filenames, credentials, photo counts, app version.

## App Shortcuts & Siri phrases (FR-800-03)

7 shortcuts (platform cap 10 — 3 slots deliberately kept free for the Roadmap
display-settings intents). Every phrase contains `\(.applicationName)`; verb-first
so they stay clear of HomeKit's device-control namespace:

- "Pause \(.applicationName)" / "Resume \(.applicationName)"
- "Next photo on \(.applicationName)" / "Previous photo on \(.applicationName)"
- "Set \(.applicationName) brightness"
- "Set \(.applicationName) source"
- "Get \(.applicationName) state"

## Dependency contract (app ↔ package seam)

The app target must, in this order:

1. Register the one `FrameControlRegistry` in `AppDependencyManager` at app init,
   wiring `sourceOptions` to the source-library store and `isConfigured` to the
   startup gate.
2. On every slideshow generation (the `connectionGeneration`-keyed rebuild):
   build the **single** `SlideshowRemoteControlAdapter` (hoisted, broker or not),
   `registry.register(adapter)`, and hand the same instance to
   `HAControlCoordinator` when a broker is configured.
3. `registry.unregister()` on generation teardown.

Violating 2's "single instance" re-introduces the split command path FR-800-02
forbids; a package-side host test cannot see this, so the app-hosted glue suite
asserts HA and the intents observe the same object.
