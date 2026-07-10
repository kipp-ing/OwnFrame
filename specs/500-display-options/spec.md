# Feature Specification: Display Options (ThemeSettings)

**Feature Branch**: `500-display-options`

**Created**: 2026-06-23

**Status**: Active

**Input**: Consolidated from `specs/008-display-options/spec.md`: persistent, live display and playback preferences for the slideshow, replacing placeholder settings rows with working controls.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Adjust order and timing, persisted and applied live (Priority: P1)

The user can change slideshow order and per-photo duration from settings. The running slideshow applies the change without restart, and the choices survive app relaunch.

**Why this priority**: Order and duration are the highest-value day-to-day controls and establish the settings store and live-update path used by every other option.

**Independent Test**: Change order and duration in settings, verify the running slideshow uses the new interval and ordering behavior, relaunch the app, and verify the choices remain active.

**Acceptance Scenarios**:

1. **Given** a default install, **When** the slideshow first runs, **Then** order is shuffle and duration is 15 seconds without user configuration.
2. **Given** the settings screen, **When** the user changes the duration, **Then** the running slideshow's auto-advance uses the new duration without a restart.
3. **Given** order is shuffle, **When** the slideshow runs a full cycle, **Then** every photo is shown once before any repeats, and the next cycle uses a fresh shuffle.
4. **Given** order is sequential, **When** the slideshow runs, **Then** photos appear in the source's album order — i.e. capture-date order, newest first (see FR-500-06 note; 130).
5. **Given** any changed option, **When** the app is relaunched, **Then** the previously chosen values are still in effect.

---

### User Story 2 - Choose transition and Ken Burns motion (Priority: P2)

The user can choose the transition between photos and can opt into Ken Burns pan/zoom motion. Defaults preserve the current calm behavior.

**Why this priority**: Motion and transitions shape the slideshow feel, but the slideshow remains useful at the defaults.

**Independent Test**: Select each transition and toggle Ken Burns, then verify the running slideshow applies the selected behavior on the next applicable display or advance and persists the choice.

**Acceptance Scenarios**:

1. **Given** a default install, **When** the slideshow advances, **Then** a crossfade is used and no Ken Burns motion is applied.
2. **Given** a selected transition, **When** the slideshow advances, **Then** that transition is used.
3. **Given** Ken Burns is enabled, **When** a photo is shown, **Then** a slow pan/zoom is applied for the duration of that photo; disabling it returns to a static image.

---

### User Story 3 - Choose image fit and quality (Priority: P2)

The user can choose whether each photo is fitted or filled on screen and whether the app fetches preview or original-quality image data.

**Why this priority**: Fit and quality improve presentation on large or high-DPI displays while keeping the default lightweight.

**Independent Test**: Set fit to Fill and verify mismatched-aspect photos crop to fill without letterbox bars; set quality to Original and verify full-resolution image data is fetched instead of preview data; relaunch and verify both choices persist.

**Acceptance Scenarios**:

1. **Given** a default install, **When** a photo is shown, **Then** it is fitted with letterboxing as needed and the preview-size image is used.
2. **Given** fit is Fill, **When** a photo's aspect differs from the screen, **Then** it is cropped to fill with no letterbox bars.
3. **Given** quality is Original, **When** a photo loads, **Then** the full-resolution original is fetched and displayed; quality Preview uses the preview-size image.

---

### User Story 4 - Optional clock overlay (Priority: P3)

The user can enable an unobtrusive clock overlay, choose its corner, and optionally include the date. The overlay is off by default.

**Why this priority**: A clock is useful for a photo frame, but it must remain opt-in so photos stay primary by default.

**Independent Test**: Enable the clock, choose a corner, toggle date display, then disable the clock and verify the overlay appears, updates, disappears, and persists as configured.

**Acceptance Scenarios**:

1. **Given** a default install, **When** the slideshow runs, **Then** no clock is shown.
2. **Given** the clock is enabled with a chosen corner, **When** the slideshow runs, **Then** the current time and, if enabled, the date appear in that corner.
3. **Given** the clock is disabled, **When** the slideshow runs, **Then** the overlay is gone.

### Edge Cases

- **Duration changed while a photo is mid-display**: The new duration applies from the next advance; the current photo is not cut short or frozen.
- **Order switched between shuffle and sequential mid-show**: The change takes effect without restarting the slideshow or losing the current photo; the next advance follows the new order.
- **Ken Burns with Fit**: Ken Burns must behave gracefully with fitted images, without a jarring jump or revealed background.
- **Original quality fails or is slow**: Failed or slow original loads are handled like existing image-load failures; the frame must not blank or freeze.
- **Single-image album**: Order and transitions remain stable on the one image, with no crash and no flicker.
- **Corrupt or missing stored settings**: Unreadable or partial stored values fall back to documented defaults rather than preventing startup.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-500-01**: The system MUST provide a persistent settings store for display and playback preferences behind an injectable protocol, with no hidden singleton.
- **FR-500-02**: The settings store MUST use non-secret storage such as UserDefaults and MUST NOT store API keys, broker credentials, or any other secret.
- **FR-500-03**: The system MUST apply these defaults on first run or after invalid storage fallback: order shuffle, duration 15 seconds, transition crossfade, Ken Burns off, fit Fit, quality Preview, and clock off.
- **FR-500-04**: Settings changes MUST apply to the already-running slideshow without requiring an app or slideshow restart.
- **FR-500-05**: Settings changes MUST persist across app launches.
- **FR-500-06**: The system MUST support photo order options shuffle and sequential. Shuffle MUST show every photo once per cycle before any repeat, then reshuffle for the next cycle. **"Album order" (sequential) is the source's capture-date order, newest first** — under Immich v3 (130) an API-key album is fetched via `POST /api/search/metadata` with `order: desc` (which reproduces the album's own date sort), and a shared link plays the order returned by `/api/shared-links/me`; the offline snapshot (320) replays that same stored order.
- **FR-500-07**: The system MUST support configurable per-photo duration and MUST clamp out-of-range values to the documented valid range.
- **FR-500-08**: The system MUST support transition options crossfade, slide, dissolve, and none.
- **FR-500-09**: The system MUST support an optional Ken Burns slow pan/zoom toggle, default off.
- **FR-500-10**: The system MUST support image fit options Fit and Fill.
- **FR-500-11**: The system MUST support image quality options Preview and Original; Original uses the original-quality fetch provided by the Immich client, while Preview remains the default.
- **FR-500-12**: The system MUST support an optional clock overlay with configurable corner and optional date line.
- **FR-500-13**: The settings screen MUST replace disabled placeholder rows for duration, transition, Ken Burns, order, fit, and quality with live controls bound to the settings store.
- **FR-500-14**: The existing brightness control MUST continue to work after display options are enabled.
- **FR-500-15**: The default experience MUST remain calm and overlay-free, in alignment with Plain and Light by Default; every visual effect or overlay is either current behavior or opt-in.
- **FR-500-16**: Invalid, partial, or unreadable stored settings MUST fall back to the documented defaults without blocking startup.

### Key Entities *(include if feature involves data)*

- **ThemeSettings**: The user's non-secret display and playback preferences: order, duration, transition, Ken Burns enabled, fit, quality, clock enabled, clock corner, and show-date.
- **ThemeSettingsStore**: The injectable persistence boundary that reads and writes ThemeSettings and supplies documented defaults when no valid stored value exists.
- **Clock Overlay Settings**: The subset of ThemeSettings controlling time visibility, date visibility, and corner placement.

### Roadmap / Deferred (not yet built)

- Disk-persistent image cache settings, automatic retry/backoff, periodic source refresh, cache size, and clear-cache controls remain deferred to the slideshow resilience milestone.
- Presence-driven sleep/wake and Home Assistant motion integration remain deferred to topic 400 and reserved sub-spec `730` under topic 700.
- Multi-source albums, Memories, and shared-link mode remain deferred to Immich data-source roadmap specs.
- Localization, video playback, and Live Photo playback are outside this milestone.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-500-01**: A change to any supported option is reflected by the running slideshow within one advance cycle, without app restart.
- **SC-500-02**: 100% of supported settings survive app relaunch and resume with the user's choices.
- **SC-500-03**: On a fresh install with no interaction, the slideshow uses shuffle, 15 seconds, crossfade, no Ken Burns, Fit, Preview, and no clock.
- **SC-500-04**: Over a full shuffle cycle, no photo repeats before every other photo has been shown.
- **SC-500-05**: With quality Original, the slideshow displays original-quality image data; with Preview, it displays preview-size image data.
- **SC-500-06**: Settings persistence contains no API key, broker credential, or other secret, and none are written to logs.

## Assumptions

- ThemeSettings is implemented as a small isolated module or clearly isolated unit consumed by SlideshowKit and app settings UI through dependency injection.
- The Immich client provides both preview and original-quality image fetches behind the image-source boundary; TLS remains enabled.
- The exact valid duration range is a plan detail, but the default is 15 seconds and out-of-range values are clamped.
- If Ken Burns is enabled while fit is Fit, the rendering design must avoid revealing empty background or visibly broken movement.
- This milestone keeps the current single active album source.
