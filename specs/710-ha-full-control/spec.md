# Feature Specification: Home Assistant Full Control (MQTT)

**Feature Branch**: `710-ha-full-control`

**Created**: 2026-07-04

**Status**: Active — built on feat/710 (PR #10); 40/41 tasks done, live-HA confirmation tracked in docs/manual-verification.md

**Input**: Extends `specs/700-ha-control`. Home Assistant can read and set everything over
MQTT — all display settings, playback, the active album, and the currently shown photo (image +
metadata). Existing entities (playback switch, brightness light, album select) stay unchanged;
this spec adds the rest and defines the state/echo model that keeps a dozen+ entities in sync
without loops. Out of scope (deferred): sleep/wake (700's roadmap, reserved as `730`),
starting/stopping the app itself, uploading photos, HA reading/adding sources, authentication
changes.

> **Purchase-gate tiering (per spec 1100, amended 2026-07-20).** The entities defined here
> split across tiers: the **read-only sensor entities** (current photo + metadata, current-photo
> image, playback phase, photo count, version, and — on battery-bearing devices — battery level
> and charging state) plus broker connection + availability (LWT) are
> **free** — an unentitled frame publishes them so Home Assistant can *see* it. The
> **controllable entities** (everything with a `command_topic`: brightness/light, album select,
> playback switch, the settings controls, next/previous) and all command handling require the
> **Automation** unlock. The state/echo model here is unchanged; the gate only decides which
> entities are published and whether command topics are subscribed. See FR-1100-03 / FR-1100-03a.

## Clarifications

### Session 2026-07-04

- Q: FR-710-22 caches `assetInfo` per asset for the session; should that cache be bounded or
  unbounded, given this is an always-on frame that can run for days/weeks? → A: Bounded
  (LRU-ish cap), mirroring the existing bounded image cache.
- Q: FR-710-11 retains every state topic except the image topic (privacy carve-out); should the
  `current_photo` metadata sensor follow the general rule (retained) or match the image topic's
  privacy stance? → A: Not retained — matches the image topic.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Read & set all display settings from HA (Priority: P1)

All slideshow display settings (order, duration, transition, Ken Burns, fit, quality, clock
on/off, clock corner, clock date) appear as individual HA entities. Changing one in HA applies
live to the running slideshow (no restart) and persists exactly like a change made in the app's
own settings UI. Changing one in the app updates HA.

**Why this priority**: This is the core of "set and read everything" and reuses the existing
live-settings mechanism (`ThemeSettingsStore` is read at point of use — spec 500), so it is the
highest-value slice with the lowest architectural risk.

**Independent Test**: With a fake MQTT transport: verify discovery publishes one entity per
setting with correct options/ranges; send each command and verify the setting is validated,
applied to the store, and echoed; change a setting locally and verify the corresponding state
topic is published; send out-of-range/unknown payloads and verify state is unchanged and the
actual value is re-echoed.

**Acceptance Scenarios**:

1. **Given** the app is connected, **When** discovery is published, **Then** it contains
   entities for every `ThemeSettings` field, all bound to the shared availability topic.
2. **Given** the slideshow is running, **When** HA sets `duration` to a value inside 3–600 s,
   **Then** the next auto-advance uses the new duration and the value is echoed on the state
   topic.
3. **Given** HA sets `duration` outside 3–600 s, **Then** the setting is unchanged and the
   actual current value is echoed (self-heal).
4. **Given** HA selects a `transition` option, **Then** the next transition uses it, the choice
   is persisted, and it survives an app restart.
5. **Given** the user changes `fit` in the app's settings UI, **Then** the `fit` state topic
   updates without any inbound command (no drift).
6. **Given** any settings entity echoes its state, **Then** the echo does NOT re-trigger a
   settings write (no echo loop, see FR-710-16).

### User Story 2 - Current photo image + metadata in HA (Priority: P1)

HA shows the photo currently on the frame: an image entity with the picture itself and a sensor
with its metadata (asset ID, taken-at, city, state, country, album). Dashboards can display
"what's on the frame right now" and automations can react to it.

**Why this priority**: The single most-requested "read" for an ambient frame; enables
dashboards and automations ("if photo older than 2010, light candles").

**Independent Test**: With fake MQTT transport and fake `ImmichAPI`: advance the slideshow and
verify the image topic receives the photo bytes (at the configured publish size) and the sensor
topic receives the metadata JSON; verify metadata fetch failure publishes the asset ID with null
attributes and never blocks the slide change; verify payloads above the size cap are downscaled
or skipped.

**Acceptance Scenarios**:

1. **Given** the slideshow shows a photo, **When** the photo changes (auto or manual), **Then**
   the image topic is published with the photo bytes and the current-photo sensor with its
   metadata.
2. **Given** metadata (`assetInfo`) fails to load, **Then** the sensor still publishes the asset
   ID with empty attributes and the slideshow is not delayed or failed.
3. **Given** the configured MQTT image size, **Then** published payloads never exceed the
   configured byte cap (default 512 KB; thumbnail source by default).
4. **Given** the image entity is disabled in options, **Then** no image bytes are ever
   published (metadata sensor may remain).

### User Story 3 - Photo navigation from HA (Priority: P2)

HA exposes Next and Previous buttons that behave exactly like the in-app chrome/swipe: they step
the photo, work while paused (without resuming), and reset the auto-advance timer.

**Independent Test**: With fake transport: press each button command topic and verify the same
code path as the chrome (`showNext`/`showPrevious`) runs; verify the current-photo topics
update; verify pressing while paused steps without resuming.

**Acceptance Scenarios**:

1. **Given** the slideshow is playing, **When** HA presses Next, **Then** the next photo per the
   current play order shows and the auto-advance timer restarts at a full interval.
2. **Given** the slideshow is paused, **When** HA presses Previous, **Then** the previous photo
   shows and playback stays paused.

### User Story 4 - Diagnostics & state on reconnect (Priority: P3)

HA shows diagnostic sensors (slideshow phase, photo count of the active album, app version, and —
on battery-bearing devices — battery level and charging state) and after any reconnect the full
state of *all* entities is re-published, so HA never shows stale values.

**Acceptance Scenarios**:

1. **Given** a reconnect after connection loss, **When** the app reconnects, **Then** discovery,
   availability and the state of every enabled entity are re-published (extends FR-700-05 to the
   full entity set).
2. **Given** the active album changes (from HA or locally), **Then** the photo count sensor
   updates.
3. **Given** the slideshow enters `empty`/`failed`, **Then** the phase sensor reflects it and the
   image/current-photo topics publish an "unknown"/cleared state rather than the stale last
   photo.
4. **Given** the frame runs on a battery-bearing device, **When** the battery level or charging
   state changes, **Then** the battery sensor and the charging binary sensor update (event-driven,
   no polling); on a device without a battery (e.g. Apple TV) these two entities are absent from
   discovery.

### Edge Cases

- **Echo loop**: state echo of a settings entity must never be interpreted as a command
  (commands and state are separate topics; the coordinator must not subscribe to its own state
  topics; `onLocalChange` fired by a remote apply must not re-publish in an infinite cycle — a
  single re-echo is fine, a loop is not).
- **Retained stale state**: retained state topics can survive an app reinstall/album deletion.
  On announce, the app republishes all states, overwriting stale retained values. Album select
  echoes the *actual* album.
- **Broker packet limit**: image publish must respect a configurable byte cap; if the encoded
  image exceeds it, downscale, and if still too large, skip the image publish for that photo
  (log only). Never disconnect-loop on oversized packets.
- **Rapid setting changes** (HA slider drag on duration): apply last-wins; coalesce echoes; no
  per-tick persistence storm (persist after settle or rely on the store's own write path — same
  behavior as the in-app slider).
- **Unknown/invalid payloads**: ignored; actual state re-echoed (existing FR-700-11 pattern,
  extended to all new entities).
- **Backgrounded app**: photo/image topics simply stop updating while the ticker is stopped;
  availability stays online while the connection lives; brightness rules from PowerManager
  (topic 400) are unchanged.
- **Secrets**: unchanged — nothing from this feature may log or publish broker credentials, API
  keys, or share-link passwords. Photo metadata (location names) IS published to the broker by
  design; document this in README as a privacy note.
- **Metadata fetch per photo**: `assetInfo` is one extra HTTP call per slide. It must be
  fire-and-forget relative to the slide change and cached alongside the photo (never delay or
  fail the show).

## Requirements *(mandatory)*

### Functional Requirements

Numbering continues the 700 series in the `710` sub-spec block.

- **FR-710-01**: The app MUST expose every `ThemeSettings` field as its own HA entity via MQTT
  discovery: `order`, `duration`, `transition`, `kenBurns`, `fit`, `quality`, `clock.isOn`,
  `clock.place`, `clock.showDate`, and — once the widened clock model (500, FR-500-17/18/19)
  ships — `clock.style` and `clock.size`. `clock.place` is the widened successor of the
  original `clock.corner` entity: it keeps the entity id and the four corner raw values (so
  retained broker state stays valid) and adds the center and random options.
- **FR-710-02**: Select-type entities MUST list exactly the app's enum cases as options
  (`PlayOrder`, `Transition`, `ImageFit`, `ImageQuality`, and the clock's place/style/size
  enums); the option strings are the enum raw values (stable API, not localized), so new enum
  cases flow into HA discovery automatically.
- **FR-710-03**: The `duration` entity MUST be an HA `number` in seconds with min 3, max 600,
  step 1 (mirrors `ThemeSettings.durationRange`); the value is published in seconds.
- **FR-710-04**: The app MUST expose `next` and `previous` as HA `button` entities that invoke
  the same code paths as the in-app chrome (`showNext`/`showPrevious`), including the
  works-while-paused and timer-reset semantics.
- **FR-710-05**: The app MUST expose the currently shown photo as an HA `image` entity (raw
  bytes on an image topic with `content_type`), publish on every photo change, and clear/mark
  unknown when the slideshow is not showing a photo (`empty`/`failed`/`loading`).
- **FR-710-06**: The app MUST expose a `current_photo` sensor whose state is the asset ID and
  whose attributes carry: `taken_at` (ISO 8601 or null), `city`, `state`, `country` (nullable),
  `album_id`, `album_name`.
- **FR-710-07**: The app MUST expose diagnostic sensors: slideshow `phase`
  (`loading|playing|empty|failed`), `photo_count` of the active album, and app `version`; these
  are `entity_category: diagnostic` in discovery.
- **FR-710-08**: The existing 700 entities (playback switch, brightness light, album select)
  remain unchanged in topics, payloads, and behavior.
- **FR-710-09**: An inbound settings command MUST be validated (enum membership / numeric
  range), applied through the same `ThemeSettingsStore` path as the in-app settings UI (live
  effect, no restart), and persisted identically.
- **FR-710-10**: Invalid inbound values MUST leave the setting unchanged and re-echo the actual
  current value on the state topic.
- **FR-710-11**: Every state topic MUST be published retained; every command topic MUST NOT be
  retained. The current-photo image topic and the `current_photo` metadata sensor's state topic
  are the exceptions: both are published NOT retained, so neither the last photo nor what it
  depicted lingers on the broker.
- **FR-710-12**: After any successful apply (remote or local) the affected entity's state MUST
  be echoed exactly once; the echo path MUST be loop-safe: applying a remote command that fires
  `onLocalChange` MUST NOT create an unbounded publish cycle.
- **FR-710-13**: On (re)connect/announce, the app MUST publish discovery and the current state
  of ALL enabled entities, overwriting any retained stale values on the broker; this includes
  republishing the current photo image so HA recovers it without relying on a retained message.
- **FR-710-14**: Published image payloads MUST respect a byte cap (configurable; default 512 KB)
  sourced from the thumbnail endpoint by default; a `preview`-size option MAY exist. If a payload
  cannot be brought under the cap, the image publish for that photo is skipped with a log entry;
  the slideshow and the metadata sensor are unaffected.
- **FR-710-15**: Image publishing MUST be optional (enable/disable in broker setup or settings),
  disabled by default; when disabled, no image bytes ever leave the device.
- **FR-710-16**: Publishing image/metadata MUST never delay, block, or fail a slide change; both
  are asynchronous side effects of the photo change.
- **FR-710-17**: All new command handling, discovery payloads, topics, and echo behavior MUST be
  testable with the existing fake `MQTTTransport` and a fake `ImmichAPI` (no real broker/server
  in tests) — extends FR-700-10.
- **FR-710-18**: `HAEntity` (or its successor) MUST enumerate the full entity set with stable
  `unique_id`s of the existing form `<deviceID>_<entity.rawValue>`; renames of existing entities
  are forbidden (would duplicate devices in HA).
- **FR-710-19**: `RemoteControlling` MUST be extended (or split into focused protocols) so the
  coordinator stays free of app-type dependencies; the adapter in the app target remains the
  only bridge.
- **FR-710-20**: A remote apply MUST be distinguishable from a genuinely local change in the
  adapter (e.g. suppress-flag or origin token) so echoes are single-shot (supports FR-710-12).
- **FR-710-21**: Rapid repeated commands on the same entity: last valid wins; echoes MAY be
  coalesced; persisted result equals the last applied value (extends FR-700-12).
- **FR-710-22**: Metadata (`assetInfo`) results MUST be cached per asset for the session (bounded,
  evicting least-recently-used entries) so revisiting a photo (previous/shuffle cycle) does not
  re-fetch, without growing unbounded across a multi-day/week session.
- **FR-710-23**: The app MUST expose device power as two read-only diagnostic entities: a **battery
  level** sensor (`battery`, `device_class: battery`, `unit_of_measurement: "%"`,
  `state_class: measurement`, integer 0–100) and a **charging** binary sensor (`charging`,
  `device_class: battery_charging`, `ON` when on external power — charging or full — else `OFF`).
  Both are `entity_category: diagnostic`, publish retained state, carry no `command_topic`, and —
  being read-only sensors — are **free** telemetry an unentitled frame still publishes (tiering
  note; 1100, FR-1100-03a). Battery values MUST be sourced event-driven (battery level/state
  notifications), not by polling. On a device without a battery (e.g. Apple TV) both entities MUST
  be omitted from discovery rather than published with a placeholder.

### Key Entities *(include if feature involves data)*

- **Settings Entity**: one HA entity per `ThemeSettings` field; command topic accepts the raw
  value; state topic echoes the applied value; discovery carries options/min/max.
- **Current Photo**: composite of image bytes (image topic, not retained — republished on
  (re)connect instead) and metadata (sensor state + attributes, also not retained, cached
  per-asset in a bounded LRU for the session); lifecycle bound to `SlideshowViewModel`
  photo-change events.
- **Diagnostics**: read-only sensors (`phase`, `photo_count`, `version`, `battery`) and the
  `charging` binary sensor, marked `entity_category: diagnostic`; `battery`/`charging` appear only
  on battery-bearing devices.
- **Publish Options**: image publishing enabled flag (default off), image source size, byte
  cap — stored with the broker configuration (non-secret part).

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-710-01**: Every setting changeable in the app's settings UI is changeable from HA with
  identical live effect and persistence — verified by a test per entity.
- **SC-710-02**: A settings round-trip (HA command → apply → echo) involves exactly one state
  publish per applied change; a soak test of N rapid commands produces ≤ N+1 publishes (no
  loop).
- **SC-710-03**: After a simulated reconnect, all entity states on the broker match the app's
  actual state (no stale retained values).
- **SC-710-04**: Photo change to image+metadata publish adds zero delay to the visible slide
  transition (side effects are detached tasks).
- **SC-710-05**: No image payload exceeds the configured cap; oversized photos degrade
  gracefully (skip + log), never a broker disconnect.
- **SC-710-06**: All of the above verified with fake transport/API only; the test suite runs
  without any broker or Immich server.
- **SC-710-07**: On a battery-bearing device, HA shows a battery-level sensor (`%`) and a charging
  binary sensor that reflect the device's actual battery level and charging state and update on
  change without polling; on a device without a battery, neither entity is discovered — verified
  with the fake transport (no real broker) and an injected battery source.

## Open Questions

1. **Sub-spec numbering `710`** — RESOLVED: this feature keeps `710`. The numbers `710`/`720`
   were briefly reserved in `700`'s roadmap for brightness/album-select during that spec's
   initial design; both shipped inline as FR-700-13/FR-700-14 instead of as separate sub-specs,
   so `710` was never used as a directory and is free. `700`'s stale footnote referencing
   `710`/`720` is corrected as part of this work to point here instead.
2. **Current-photo image retention** — RESOLVED: not retained (privacy over convenience). The
   broker does not hold the last photo bytes long-term; the app republishes the current image on
   its own reconnect/announce cycle (FR-710-13) instead of relying on a retained MQTT message.
3. **Protocol split of `RemoteControlling`** *(decide in `/speckit-plan`)*: split into focused
   protocols (e.g. `SettingsControlling`, `PhotoReporting`) versus extending one grown protocol.
   Proposal: split, to keep the adapter and fakes small (FR-710-19).
4. **`current_photo` payload shape** *(decide in `/speckit-plan`)*: single JSON state topic with
   a `value_template` extracting the asset ID, versus a separate `json_attributes_topic`.
   Proposal: single JSON state topic (simplest).
5. **Image byte cap / enable flag location** *(decide in `/speckit-plan`)*: broker setup UI
   (topic 600, a transport concern) versus slideshow display settings (topic 500). Proposal:
   broker setup.

## Assumptions

- HA ≥ 2023.7 (MQTT `image` entity support). If older HA must be supported, fall back to the
  MQTT `camera` component (bytes on topic, same transport).
- Per-entity discovery is kept (matches existing code). HA's newer device-based discovery
  (single config payload per device) is a possible later refactor, not part of this spec.
- Enum raw values are treated as a stable external API from now on (HA automations will
  reference them).
- The existing `enabledEntities` mechanism grows to cover the new set; everything is enabled by
  default except the image entity (opt-in, privacy — see FR-710-15).
- Broker credentials/secrets model of spec 700 is unchanged.
