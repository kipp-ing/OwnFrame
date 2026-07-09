# Spec Overview

The map to `specs/`. Each module spec is the **source of truth** for its area — this page is the
map, not the territory.

## Structure & numbering

Specs are organized as **one durable spec per module**, mirroring the Swift packages. There is no
chronological feature numbering anymore; a single concern lives in exactly one spec.

- **Hundreds-block per topic.** Each module owns a `Nxx` block: `100`, `200`, … `700`.
- **Sub-spec room.** `N10`, `N20`, … inside a block are reserved for sub-specs (a deferred or
  spun-off capability of that topic). Example: `110-shared-album-link` is a sub-spec of the
  `100` data-access topic.
- **Requirement IDs carry the full spec number:** `FR-<specnum>-NN` and `SC-<specnum>-NN`
  (e.g. `FR-700-03`, `SC-200-05`). This keeps a sub-spec's IDs from colliding with its parent
  block and makes any ID self-locating.
- **Deferred capabilities** are not deleted: each topic spec ends with a `Roadmap / Deferred`
  section, and substantial future work gets a reserved sub-spec number (and, where it already has
  a real outline, its own `Status: Deferred` spec).

When a genuinely new module appears, give it the next free hundreds-block. A new capability of an
existing module becomes a sub-spec (`N10`, `N20`, …) or amends the module spec directly.

## Topics

| #   | Spec                                                              | Package          | Purpose                                                                                  | Status   |
|-----|-------------------------------------------------------------------|------------------|------------------------------------------------------------------------------------------|----------|
| 100 | [immich-client](../specs/100-immich-client/spec.md)               | ImmichClient     | REST data access: albums, album assets, preview/original/thumbnail image data, errors.   | Active   |
| 110 | [shared-album-link](../specs/110-shared-album-link/spec.md)       | ImmichClient     | *(sub-spec of 100)* Play a shared/public Immich link (+ optional password) as a source.  | Active |
| 120 | [source-library](../specs/120-source-library/spec.md)             | ImmichClient     | *(sub-spec of 100)* Save several switchable sources (albums + shared links); one active. | Active |
| 200 | [connection-onboarding](../specs/200-connection-onboarding/spec.md) | OnboardingKit  | First-run setup, in-place connection editing, and the Settings-screen structure.         | Active   |
| 210 | [shared-link-onboarding](../specs/210-shared-link-onboarding/spec.md) | OnboardingKit | *(sub-spec of 200)* Choice-first onboarding, shared-link-only setup (no API key), iOS Share Sheet acceptance, resolve-first/password-when-needed, one searchable/subscrollable album picker shared by onboarding + Settings. | Active |
| 300 | [slideshow](../specs/300-slideshow/spec.md)                       | SlideshowKit     | Fullscreen playback engine + Liquid Glass UI: chrome, gestures, album browser, info.     | Active   |
| 310 | [slideshow-resilience](../specs/310-slideshow-resilience/spec.md) | SlideshowKit     | *(sub-spec of 300)* Auto-retry with backoff + periodic source refresh — unattended frame survival. | Active |
| 320 | [disk-image-cache](../specs/320-disk-image-cache/spec.md)         | SlideshowKit     | *(sub-spec of 300)* Byte-capped disk cache + remembered source list — whole-album offline survival incl. relaunch; budget in Settings (500 MB default). | Active |
| 400 | [power-manager](../specs/400-power-manager/spec.md)               | PowerKit         | Keep the display awake and dim brightness while the slideshow runs in the foreground.     | Active   |
| 500 | [display-options](../specs/500-display-options/spec.md)           | ThemeKit         | User-configurable order/duration/transition/Ken Burns/fit/quality/clock, applied live.   | Active   |
| 600 | [broker-setup](../specs/600-broker-setup/spec.md)                 | BrokerSetupKit   | Enter and persist MQTT broker credentials (Keychain) so 700 has something to connect to. | Active   |
| 700 | [ha-control](../specs/700-ha-control/spec.md)                     | HAControlKit     | Remote control via MQTT/HA: availability + pause/play + brightness + album (730 deferred). | Active   |
| 710 | [ha-full-control](../specs/710-ha-full-control/spec.md)           | HAControlKit     | *(sub-spec of 700)* Read/set every display setting, next/previous, current-photo image + metadata, and diagnostics over MQTT. | Active |
| 800 | [app-intents](../specs/800-app-intents/spec.md)                   | app target (+ AppIntentsKit) | Shortcuts/Siri/personal-automation control via App Intents — second front-end to 700's command surface. | Deferred (v1.1) |
| 900 | [photo-library-source](../specs/900-photo-library-source/spec.md) | PhotoLibraryKit (new) | Apple Photos / iCloud albums as a source, behind a backend-neutral source protocol.       | Deferred (v1.x) |

## How they connect

```
100 ImmichClient ──> 200 Connection & Onboarding ──> 300 Slideshow (engine + UI)
        │                                                  │
        │                          400 PowerManager <──────┤  (foreground brightness / idle)
        │                          500 Display Options <───┘  (order/duration/transition/clock)
        │
       110 Shared Album Link (source kind) ──┐
       120 Source Library (switchable list) ─┴─> surfaced in 200 (onboarding/Settings) + 700 (select)

600 Broker Setup ──> 700 HA Control (MQTT remote control)
                              ├─ active: pause/play, brightness, source-select (120)
                              ├─ active: 710 full control (settings, photo, diagnostics)
                              └─ reserved: 730 sleep/wake

310 Slideshow Resilience ──> 300 (auto-retry + periodic refresh; implemented 2026-07-09)
320 Disk Image Cache ─────> 300 + 310 (offline photo survival; implemented 2026-07-09)
800 App Intents ──> 700's command surface (Shortcuts/Siri/automations, no MQTT; deferred v1.1)
900 Photo Library Source ──> 120 source library (new kind) + a source-neutral data
                             protocol that 100 and PhotoKit both implement (deferred v1.x)
```

- **200** owns the Settings-screen surface; it *surfaces* the 600 (Broker) and 500 (Display)
  sections and the 400 (brightness) control without re-specifying their behavior.
- **210** evolves 200's onboarding (choice-first entry, shared-link-only path, Share Sheet, the
  searchable album picker) and *reuses* 120's source library + shared-link secret store and 100/110's
  shared-link resolution; it adds no new backend behavior.
- **300** *consumes* 500 (option values), 400 (brightness), 100/110 (sources) and *delegates*
  reset to 200 — it does not redefine them.

## Reading order

Core path: **100 → 200 → 300**, then **400 / 500** as the slideshow's foreground-power and
display layers, then **600 → 700 → 710** for the Home Assistant remote-control path. `110` feeds `120`'s
source kinds — read it alongside `120`.

## Reserved / deferred (roadmap)

Recorded in each owning topic's `Roadmap / Deferred` section. `110`/`120`/`710` shipped and are
Active above. `310` and `320` are **implemented** (the two pre-release gates); `800`/`900` are
specced and deferred (post-release, in that order); the rest remain unscheduled.

**Reserved sub-specs / future sources:**
- `730` HA sleep/wake driven by an HA presence signal (pairs with the 400 sleep/wake roadmap item).
- Multi-source **pooling** (merge into one stream) and Memories as sources (topic 100 roadmap) —
  `120` covers switching between sources, not pooling.

**Specified but not yet built** (carried over from old "extended/added" notes, deferred during the
overhaul so every Active requirement maps to real, tested code):
- ~~Disk image cache + size limit + Clear-cache action~~ — promoted to sub-spec
  [320-disk-image-cache](../specs/320-disk-image-cache/spec.md), implemented 2026-07-09.
- ~~Auto-retry with backoff~~ / ~~periodic source refresh~~ — promoted to sub-spec
  [310-slideshow-resilience](../specs/310-slideshow-resilience/spec.md), implemented 2026-07-09.
- Rendered clock overlay — settings are stored (500), renderer deferred (topic 300).
- Settings/onboarding source management — now built: `120` owns the source library and `210`
  delivers the choice-first onboarding, shared-link-only setup, iOS Share Sheet acceptance, and the
  shared searchable album picker (onboarding + Settings). Remaining 210 work is polish + a device
  Share-Sheet pass, not new surface.
