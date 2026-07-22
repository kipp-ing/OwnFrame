# Feature Specification: Slideshow (engine + UI)

**Feature Branch**: `300-slideshow`

**Created**: 2026-06-23

**Status**: Active

**Input**: Consolidated from `specs/003-slideshow/spec.md` and `specs/007-slideshow-ui/spec.md`: fullscreen playback engine, calm slideshow UI, chrome and gestures, album browser, info overlay, cache behavior, resilience, clock rendering, and localization.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Run the selected source as a calm fullscreen slideshow (Priority: P1)

After onboarding, the app opens directly into a fullscreen slideshow from the configured Immich source. It shows one image at a time, advances forward after the configured duration, transitions smoothly, loops forever, and starts with no chrome, overlay, clock, or system status UI visible.

**Why this priority**: This is the core product: a quiet photo frame that shows photos first and controls only when requested.

**Independent Test**: With a mocked source containing multiple images, start the app and verify the first image fills the fullscreen presentation area with no chrome, that the next image appears after the configured duration with a transition, and that the show loops from the last image back to the first.

**Acceptance Scenarios**:

1. **Given** a configured source with at least one image, **When** the slideshow starts, **Then** the first image is displayed fullscreen, fitted according to the active display option, with no chrome, clock, info overlay, or status bar visible.
2. **Given** an image is displayed, **When** the configured display duration elapses, **Then** the slideshow advances forward to the next image using the active transition.
3. **Given** the last image in the active order is displayed, **When** the display duration elapses, **Then** the slideshow continues from the first image in a new loop.
4. **Given** the source contains exactly one image, **When** the display duration elapses or next/previous is invoked, **Then** the same image remains visible without error or flicker.
5. **Given** display options from topic 500 change while the slideshow is running, **When** the relevant advance or render point is reached, **Then** the engine applies the new order, duration, transition, Ken Burns, fit, quality, and clock settings without an app restart.

### User Story 2 - Keep transitions smooth with bounded caching (Priority: P2)

The engine prefetches the next images and keeps a bounded in-memory cache so normal advances do not show blank loading states. (The size-limited disk cache that survives relaunch/offline plus the Clear-cache action are built — sub-spec [320-disk-image-cache](../320-disk-image-cache/spec.md).)

**Why this priority**: A photo frame must feel stable in 24/7 use. Smooth playback and a bounded cache avoid both flicker and unbounded memory growth.

**Independent Test**: With a mocked delayed image source, verify at least the next image is prefetched before advance and cache entries are evicted oldest-first past the limit.

**Acceptance Scenarios**:

1. **Given** a running slideshow, **When** the current image is displayed, **Then** the next one to two images are prefetched in the background.
2. **Given** the next image has already been prefetched, **When** advance is triggered, **Then** it appears without a visible loading roundtrip.
3. **Given** many images have been loaded, **When** the in-memory cache reaches its limit, **Then** the oldest entries are evicted and the cache stays within its bound.

### User Story 3 - Recover from empty sources and failures (Priority: P2)

The slideshow skips individual broken images, reports empty sources and fetch failures calmly, and offers a manual retry. (Automatic retry with backoff and periodic source refresh are deferred — see Roadmap.)

**Why this priority**: Unattended playback should not be permanently blocked by one bad asset or a temporary network issue.

**Independent Test**: Use a mocked source where one image fails, the source list is empty, and the asset list fetch fails. Verify a broken image is skipped, and empty and failed source states show a calm message with manual retry.

**Acceptance Scenarios**:

1. **Given** a running slideshow, **When** a single image cannot be loaded, **Then** that image is skipped and the next loadable image is displayed without a crash.
2. **Given** the active source has no displayable images, **When** the slideshow starts, **Then** a calm empty-state message is shown instead of a blank or crashed screen.
3. **Given** the source asset list cannot be fetched, **When** the failure occurs, **Then** a clear error message with manual retry is shown.
4. **Given** the source includes videos, Live Photos, or other non-image assets, **When** the display order is built, **Then** those assets are skipped and only still images are shown.

### User Story 4 - Reveal controls only on intent (Priority: P1)

A tap reveals Liquid Glass chrome with top navigation/actions and bottom transport controls. The chrome hides after a short idle. Swipes move through images without revealing chrome. Pause/play stops or resumes auto-advance while manual navigation remains available.

**Why this priority**: The slideshow needs local control without compromising the calm default.

**Independent Test**: In a hermetic UI run, verify the default state shows only the image, tap reveals chrome, a second tap hides it, idle hides it after about 4.5 seconds, swipes navigate without chrome, and play/pause controls auto-advance without disabling manual previous/next.

**Acceptance Scenarios**:

1. **Given** the slideshow runs by default, **When** the user does nothing, **Then** no chrome or system status UI is visible.
2. **Given** the slideshow runs, **When** the user taps the image, **Then** the top bar with exit, info, albums, and settings and the bottom bar with previous, play/pause, and next appear.
3. **Given** the chrome is visible, **When** the user taps the image again, **Then** the chrome hides.
4. **Given** the chrome is visible, **When** no interaction occurs for about 4.5 seconds, **Then** the chrome auto-hides; any control interaction resets the countdown.
5. **Given** the slideshow runs, **When** the user swipes left or right, **Then** the image advances forward or backward without revealing chrome.
6. **Given** the chrome is visible, **When** the user taps play/pause, **Then** auto-advance stops or resumes; manual previous and next still work while paused.
7. **Given** the user paused playback, **When** the app moves to background and returns to foreground, **Then** the slideshow stays paused until the user resumes it.
8. **Given** auto-advance is running, **When** it advances, **Then** it only advances forward; backward navigation is available only through previous or a right swipe.

### User Story 5 - Browse albums and jump to a photo (Priority: P2)

From the chrome, the user opens an album browser as a sheet over the running slideshow. They can choose an album, see cheap thumbnails, tap a photo, and return to fullscreen at exactly that photo. Switching to a different album changes the active single album source at runtime.

**Why this priority**: Local source and photo selection are the next most useful controls after basic transport.

**Independent Test**: Open chrome, open Albums, select an album, tap a thumbnail, and verify the sheet closes and fullscreen playback starts at that photo; repeat with a different album and verify the active source switches.

**Acceptance Scenarios**:

1. **Given** the slideshow runs, **When** the user chooses Albums in the chrome, **Then** an album browser sheet appears while the slideshow keeps running behind it.
2. **Given** the album grid is open, **When** the user taps an album, **Then** its photo thumbnail grid appears.
3. **Given** the thumbnail grid is open, **When** the user taps a photo, **Then** the sheet closes and fullscreen playback starts at exactly that photo.
4. **Given** the tapped photo belongs to a different album than the active one, **When** it is selected, **Then** that album becomes the active runtime source and the show jumps to the selected photo.
5. **Given** thumbnails are rendered, **When** the grid loads images, **Then** it uses a cheap dedicated thumbnail endpoint rather than full preview or original image data.

### User Story 6 - Show photo information only when useful (Priority: P3)

From the chrome, the user can toggle an info overlay showing only capture date/time and location from Immich EXIF. The overlay updates as photos change and renders nothing for photos without usable info.

**Why this priority**: Context is useful, but it should never dominate the photo or show irrelevant metadata.

**Independent Test**: Show the overlay on a photo with EXIF date/location and verify both appear; advance to a photo without EXIF and verify no placeholder content appears; inspect the overlay and verify no filename or album name is shown.

**Acceptance Scenarios**:

1. **Given** the current photo has EXIF date/time and location, **When** the user opens Info, **Then** an overlay shows date/time and location.
2. **Given** the info overlay is visible, **When** the slideshow advances, **Then** the overlay reloads information for the new photo.
3. **Given** the current photo has no usable EXIF information, **When** the info overlay is active, **Then** it shows no content, no empty card, and no placeholder.
4. **Given** the info overlay shows content, **When** it is inspected, **Then** it contains only date/time and location, not filename or album name.

### User Story 7 - Reach settings, brightness, reset, and localization (Priority: P3)

From the chrome, the user reaches Settings with a live brightness slider and display-option controls owned by topic 500. Reset is reachable from Settings. All slideshow UI strings ship in English through localizable string catalogs; other device languages fall back to English. (German translations are deferred — see Roadmap; the clock overlay is implemented per `510-clock-overlay`.)

**Why this priority**: These controls round out a usable frame while keeping feature ownership clear and the default overlay-free.

**Independent Test**: Open Settings from chrome, adjust brightness and verify the control is live through topic 400, change display options and verify the slideshow applies them through topic 500, invoke reset from Settings, and confirm a non-English device language falls back to English strings.

**Acceptance Scenarios**:

1. **Given** the slideshow runs, **When** the user opens Settings from chrome, **Then** a settings screen appears with a live brightness slider and display-option controls.
2. **Given** Settings is open, **When** the brightness slider changes, **Then** screen brightness changes immediately in the foreground through topic 400.
3. **Given** Settings is open, **When** the user changes display options, **Then** those topic 500 options persist and apply to the running slideshow.
4. **Given** the user opens Settings, **When** reset is selected, **Then** reset is reachable without a long-press and delegates connection clearing to topic 200.
5. **Given** any device language, **When** the slideshow UI is shown, **Then** all visible strings come from localizable resources and render in English until further languages ship (see Roadmap).

### Edge Cases

- **Empty album or load failure after switching albums**: The browser and slideshow show calm "no albums", "no photos", or "could not be loaded" states instead of a blank surface.
- **Photo without EXIF**: The info overlay renders no content and no placeholder.
- **App backgrounded**: Auto-advance pauses and foreground-only power behavior is released; on foreground return, playback resumes unless the user had paused it.
- **Jump to unknown asset**: If the active album does not contain the requested photo, the jump is a no-op with no crash or invalid phase.
- **Single-image source**: Tick, previous, next, order, and transitions remain stable on the one image.
- **Backward navigation**: Only manual previous and right swipe go backward; auto-advance is forward-only.
- **Very large source**: Memory stays bounded and the engine does not load every image at once.
- **Source becomes empty after playback started**: The next refresh or cycle moves to the empty-state message.
- **Very slow connection**: If the next image is not ready, the current image remains displayed until a valid next image is available; no blank or frozen transition is shown.
- **Original-quality image is slow or fails**: It is handled like any image-load failure and must not blank or freeze the frame.
- **Duration changed mid-photo**: The new duration applies from the next advance; the current photo is not cut short or frozen.
- **Order switched mid-show**: The change takes effect without restarting the app or losing the current photo.
- **Ken Burns with fitted images**: With fit Fit, motion is a centered zoom (no pan) that keeps the whole photo visible with no exposed background beyond the letterbox and no jarring jump (honors 500, FR-500-20).
- **Chrome across orientation and fit/fill switches**: Chrome bar insets stay stable in both orientations and across any fit/fill framing; controls never crowd or clip at the screen edges. Ken Burns honors the active fit option (500, FR-500-20) rather than forcing fill.
- **Bright or near-white photo behind chrome**: Legibility is guaranteed by a fixed contrast backing independent of image content.
- **Corrupt cached image or settings data**: Bad cache entries are skipped or evicted, and invalid settings fall back to topic 500 defaults without blocking startup.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-300-01**: The app MUST open directly into the running slideshow after setup, showing one image fullscreen with no chrome, clock, info overlay, or status UI until explicit user action.
- **FR-300-02**: The engine MUST load the configured source's image assets through topic 100 data access; the current active source is a single selected album, while future source types are owned by topic 100 and `110-shared-album-link`.
- **FR-300-03**: The engine MUST show exactly one image at a time, advance after the active duration, transition using the active transition, and loop indefinitely.
- **FR-300-04**: The engine MUST consume topic 500 display options for order, duration, transition, Ken Burns, fit, quality, and clock settings, and MUST apply changes live without duplicating the settings catalogue in this topic.
- **FR-300-05**: Shuffle order, when supplied by topic 500, MUST show every photo once per cycle before repeats and reshuffle for the next cycle; sequential order MUST follow album order.
- **FR-300-06**: The engine MUST prefetch the next one to two images and avoid visible blank loading states during normal advances.
- **FR-300-07**: The in-memory image cache MUST have a fixed bound and evict oldest entries first.
- **FR-300-09**: A single broken or unloadable image MUST be skipped without crashing or stopping the slideshow.
- **FR-300-10**: Empty sources and failed source fetches MUST show calm messages with manual retry rather than a blank or crashed screen.
- **FR-300-13**: Videos, Live Photos, and other non-image assets MUST be skipped; this topic displays still images only.
- **FR-300-14**: The slideshow timer MUST be foreground-only: it pauses in the background and resumes in the foreground, respecting user pause state and iPadOS platform boundaries.
- **FR-300-15**: A tap MUST reveal Liquid Glass chrome with top actions info, albums, and settings, and bottom controls previous, play/pause, and next; another tap MUST hide it.
- **FR-300-16**: Revealed chrome MUST auto-hide after about 4.5 seconds of idle, and control interaction MUST reset the countdown.
- **FR-300-17**: Horizontal swipes MUST move forward or backward without revealing chrome.
- **FR-300-18**: Play/pause MUST stop or resume auto-advance while leaving manual previous/next available; user pause MUST survive background to foreground.
- **FR-300-19**: Auto-advance MUST be forward-only; backward navigation is manual only.
- **FR-300-20**: The album browser MUST open from chrome as a sheet over the running slideshow and present album and photo thumbnail grids.
- **FR-300-21**: The album browser MUST use a cheap dedicated thumbnail endpoint for grid thumbnails.
- **FR-300-22**: Selecting a thumbnail MUST close the sheet and start fullscreen playback at that photo; selecting a photo from another album MUST switch the active runtime album and jump to it.
- **FR-300-23**: Jumping to an unknown asset MUST be a no-op rather than a crash or invalid state.
- **FR-300-24**: The info overlay MUST show only EXIF date/time and location, update on photo change, and render no content when no usable data exists.
- **FR-300-25**: The info overlay MUST NOT show filename, album name, secrets, or credentials.
- **FR-300-26**: Settings MUST be reachable from chrome with a live brightness slider whose behavior is owned by topic 400.
- **FR-300-27**: Settings MUST surface topic 500 display-option controls, and those changes MUST affect the running slideshow.
- **FR-300-28**: Reset MUST be reachable from Settings (not the chrome) and MUST delegate connection clearing to topic 200.
- **FR-300-30**: All slideshow UI strings MUST be localizable (string catalog, no hardcoded user-facing strings in views); the app ships English. Additional languages (German first) are deferred — see Roadmap.
- **FR-300-31**: Slideshow state, timers, image loading, cache, and data access MUST remain testable behind injected protocols, with no real server, clock, cache, or display hardware required for unit tests.
- **FR-300-32**: The UI MUST never reveal or log API keys, broker credentials, shared-link passwords, or other secrets.
- **FR-300-33**: Chrome bar insets from the screen edges MUST remain stable across device orientation and MUST NOT shift with the rendered image's framing — whether the photo is fit or fill, and whether Ken Burns is on or off. Ken Burns honors the active fit option (500, FR-500-20) and does not by itself switch fit/fill framing.
- **FR-300-34**: Chrome controls MUST remain legible against their icon/text regardless of the underlying photo's brightness or color, including near-white or near-black images.

### Key Entities *(include if feature involves data)*

- **Slideshow Source**: The configured provider of image assets. The active source is currently one selected album from topic 100; future multi-album, Memories, and shared-link sources are deferred to topic 100 and sub-spec 110.
- **Slideshow Asset**: A still image asset with ID, display metadata, image data, and optional EXIF date/location.
- **Slideshow State**: Current asset, playback order, current index, running or user-paused state, visible chrome state, active album, and transient empty/error phase.
- **Image Cache**: Bounded in-memory image storage (built). Disk-persistent storage with size enforcement and a clear action is built — sub-spec [320-disk-image-cache](../320-disk-image-cache/spec.md).
- **Album Browser Selection**: The album and asset chosen from the browser, used to switch the active runtime album and jump to an image.
- **Info Overlay Data**: Date/time and location derived from Immich EXIF, empty when unavailable.
- **Clock Overlay Rendering**: The rendered time and optional date at the corner configured by topic 500. Deferred (see Roadmap) — the settings exist in topic 500 but the renderer is not yet built.

### Roadmap / Deferred (not yet built)

These are specified intent but not implemented today; the engine currently uses an in-memory cache
only and forward playback without unattended retry/refresh. Each should be scheduled as its own
Spec Kit feature.

- **Disk image cache + Clear cache** (was FR-300-08 / part of FR-300-27): **implemented** as
  sub-spec [320-disk-image-cache](../320-disk-image-cache/spec.md) (2026-07-09) — size-limited
  disk cache surviving relaunch/offline with LRU eviction, budget configurable in Settings
  (default 500 MB), Clear action, plus a remembered source list for offline launches. No longer
  deferred; FR-320-01…12 are the binding requirements.
- **Auto-retry with backoff** (was FR-300-11): load/connection failures auto-retry with backoff for
  unattended recovery, beyond the existing manual retry. **Now specced** as sub-spec
  `310-slideshow-resilience` (FR-310-01…05) — planned pre-release.
- **German translations** (part of FR-300-30): a `de` localization for the string catalogs. All
  source strings stay English (repo policy: English-only source); German ships as a translation
  pass over the existing catalogs once scheduled.
- **Periodic source refresh** (was FR-300-12): the active source asset list refreshes periodically
  so newly added Immich photos enter rotation without an app restart. **Now specced** as sub-spec
  `310-slideshow-resilience` (FR-310-06…11) — planned pre-release.
- **Rendered clock overlay** (was FR-300-29): render the optional clock per the topic 500
  settings contract — design agreed 2026-07-18 ("Quiet Glass" clock round, FR-500-12/17/18/19):
  three styles (Digits default / Pill / Analog), six places plus Random, Room/Cozy sizes,
  optional date line. The clock is ambient-layer: it hides whenever the chrome is visible and
  returns on auto-hide, and the photo-details caption yields its place rather than overlap.
  **Implemented in `510-clock-overlay`** (iOS/iPadOS; tvOS rendering rides topic 1000). Off
  by default.
- Multi-album source pooling and Memories source selection belong to topic 100. Acceptance
  preserved from the source: selecting multiple albums pools photos from all of them, and selecting
  Memories plays that source when topic 100 supports it.
- Shared-link source selection belongs to reserved sub-spec `110-shared-album-link`. Acceptance
  preserved from the source: a stubbed shared-link entry is present in future source pickers until
  the shared-link source is implemented.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-300-01**: In the default state, only the current image is visible until the user taps; no chrome, clock, info overlay, or status UI appears.
- **SC-300-02**: Over at least one full source cycle, every displayable image advances according to the active duration and the loop continues after the final image.
- **SC-300-03**: During normal advances with prefetched images, no blank intermediate state or visible loading flicker appears.
- **SC-300-04**: In long-running playback, the in-memory cache remains within its configured limit.
- **SC-300-05**: A single unloadable image is skipped and the slideshow continues to the next loadable image.
- **SC-300-06**: Empty source and failed source-fetch states show a readable message with retry and do not crash.
- **SC-300-07**: A failed source fetch surfaces a manual retry that recovers playback when the mocked or real source becomes available. *(Automatic backoff retry is deferred — see Roadmap.)*
- **SC-300-08**: Tap reveals chrome, idle hides it after about 4.5 seconds, and swipes navigate without chrome appearing.
- **SC-300-09**: Selecting a different album and photo in the browser resumes fullscreen playback at that photo in the now-active album.
- **SC-300-10**: The info overlay shows date and location when EXIF exists and nothing when it is absent.
- **SC-300-11**: Brightness and display options are reachable from chrome; reset is reachable from Settings; all apply through their owning topics.
- **SC-300-12**: Every user-facing slideshow string resolves through the string catalog (no hardcoded strings in views); non-English device languages fall back to English.
- **SC-300-13**: Chrome control edge insets are pixel-identical between Ken Burns on and off (in both Fit and Fill) and stable across portrait/landscape, guarded by an automated UI test.

## Assumptions

- Topic 100 supplies album, asset, preview, original-quality, thumbnail, and EXIF data access behind injected transports, with TLS validation enabled.
- Topic 500 owns the stored values and controls for order, duration, transition, Ken Burns, fit, image quality, and clock configuration; this topic owns consuming and rendering their effects (the clock renderer is deferred — see Roadmap).
- Topic 400 owns brightness and idle-timer behavior; this topic only surfaces the live brightness slider and respects foreground-only lifecycle signals.
- Topic 200 owns reset of connection, API key, and selected album; this topic only provides the chrome exit entry point.
- The default remains plain, light, and overlay-free in alignment with the constitution; visual effects and overlays are opt-in except for the active transition default supplied by topic 500.
- The app targets foreground iPadOS slideshow use. Background timers, brightness, and idle behavior respect platform boundaries and do not claim capabilities iOS does not provide.
