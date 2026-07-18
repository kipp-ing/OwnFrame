# Feature Specification: Apple TV (tvOS Target)

**Feature Branch**: `1000-apple-tv`

**Created**: 2026-07-16

**Status**: Deferred — roadmap alongside `900-photo-library-source` (post-release, after
`800-app-intents`). Specced now because the platform constraints (storage, credentials,
input) shape decisions the iPad app should make early — most of all the config-sync channel.

**Input**: New platform target (new hundreds-block). The photo frame comes to the living-room
TV: a tvOS app in the same app record (universal purchase, same bundle ID) that reuses every
SPM package and plays the same sources — Immich albums and shared links — with the same
engine, transitions, and Home Assistant control surface. The port is *feasibility-verified*
(2026-07): all packages are UI-framework-free, the one iOS-only API (screen brightness) is
already behind PowerKit's `ScreenControlling` seam, and the MQTT stack (mqtt-nio 2.x) declares
tvOS support using Network-framework TLS. Out of scope: the Photos/iCloud source on tvOS
(unverified platform exposure — topic 900 roadmap), the Share Extension (no tvOS extension
point), Top Shelf (Roadmap), any control of TV panel power or brightness (no API — delegated
to Home Assistant and the TV), iPhone/iPad behavior changes.

## Platform constraints (verified 2026-07, design against these)

These are tvOS facts, not choices:

- **Persistent local storage is 500 KB of UserDefaults — everything else is purgeable.**
  There is no usable Documents directory on device; Caches and tmp can be wiped between
  launches. iCloud Drive/ubiquity containers do not exist on tvOS; the sanctioned cloud
  stores are iCloud key-value storage (≤ 1 MB, unencrypted) and CloudKit.
- **The Keychain exists locally but never syncs**: Apple documents that tvOS keychain items
  never leave the device and items from other devices never arrive. Credentials cannot ride
  iCloud Keychain from the iPad.
- **No panel control**: no brightness API, no HDMI-CEC access for third-party apps. The TV's
  power and backlight belong to the TV and (optionally) Home Assistant.
- **Foreground-only, like iOS**: `isIdleTimerDisabled` prevents screensaver and sleep while
  the app is frontmost; backgrounded apps suspend.
- **Siri-Remote-only operation is an App Review requirement**; the Menu/Back button at the
  app's root must go to the tvOS Home screen — never trapped.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - The frame plays on the TV (Priority: P1)

A user with a configured source watches the same calm slideshow on the Apple TV: same
transitions, same Ken Burns drift, same display options, no blank frames — the living-room
version of the wall frame.

**Why this priority**: This is the feature. Everything else is how it gets configured and
kept alive.

**Independent Test**: All SPM packages build and their unit suites pass for a tvOS
destination; the tvOS app target renders the slideshow with a stub `ImmichAPI` on the tvOS
simulator with transitions and options applying live.

**Acceptance Scenarios**:

1. **Given** an active Immich source, **When** the tvOS app launches, **Then** it resumes
   straight into the slideshow (startup parity with the iPad app) and plays with the
   topic-500 options applying live.
2. **Given** the slideshow is playing, **Then** the screensaver and device sleep never
   interrupt it (idle timer disabled during playback, released when playback stops — the
   topic-400 rule, brightness aside).
3. **Given** transitions/Ken Burns settings, **Then** they render with the same timing
   semantics as on the iPad (same engine, same shared drift modifier — since the 2026-07-18
   smoothness redesign both platforms run `KenBurnsMotionModifier`, one scoped linear
   animation per photo).
4. **Given** the app is at its root with chrome hidden, **When** Menu is pressed, **Then**
   the app returns to the tvOS Home screen (never trapped).

### User Story 2 - Set up without typing a novel with the remote (Priority: P1)

First-run setup on the TV is not a text-entry punishment. If the user has the iPad/iPhone
app, the frame's non-secret configuration (server URL, sources, display options) arrives via
iCloud key-value sync and secrets arrive through Apple's end-to-end-encrypted CloudKit
channel — in the best case the TV needs zero typing. Every text field supports the system's
"Type with iPhone" continuation. A user without the iOS app can still set up entirely on the
TV (the shared-link path needs only one URL).

**Why this priority**: Ease of use is this product's primary goal; a painful tvOS onboarding
kills adoption on the platform where input is hardest.

**Independent Test**: With fake sync stores (non-secret KVS + secret channel) and a fake
keychain: verify that synced non-secret config appears as prefilled onboarding state; that a
synced secret lands in the (fake) local keychain with no entry step; that the manual
secret-entry step stores into the keychain; and that the manual path completes with no
synced data present at all.

**Acceptance Scenarios**:

1. **Given** the iPad app has synced non-secret config (server URL, source list, options),
   **When** the tvOS app first launches, **Then** onboarding offers those as prefilled
   choices — the user confirms rather than re-enters.
2. **Given** the iPad app has published secrets through the end-to-end-encrypted channel
   (FR-1000-12) and the TV is signed into the same iCloud account, **Then** onboarding
   completes without typing a single secret: the secret is fetched once, stored into the
   local tvOS keychain, and used only from there.
3. **Given** no synced secret is available (no iCloud, sync unavailable, standalone TV),
   **Then** the secret is entered on the TV (system keyboard with "Type with iPhone"
   continuation) and stored only in the local tvOS keychain — key-value-synced config never
   contains secrets.
4. **Given** no iOS device and no synced data, **Then** the complete onboarding (choice-first,
   shared-link-only fast path — topic 210 semantics) works standalone on the TV.
5. **Given** the shared-link path, **Then** setup needs exactly one URL (plus password only
   when the link demands it) — the lowest-friction path stays the lowest-friction path.
6. **Given** onboarding is done once, **When** the app cold-starts later, **Then** it goes
   straight to the slideshow (config in UserDefaults/keychain survives; only caches are
   purgeable).

### User Story 3 - Survives tvOS storage reality unattended (Priority: P2)

tvOS may wipe everything but UserDefaults and the keychain between launches. The frame
tolerates that invisibly: a cold start after a purge re-hydrates from the server without user
input, and nothing the app needs to *function* lives in purgeable storage.

**Independent Test**: With the disk-cache root pointed at a temp directory: delete it
entirely, relaunch the engine, verify playback reaches the first photo with no user input and
the cache re-fills (existing 320 purge-tolerance paths, exercised as the *normal* case, not
the edge case).

**Acceptance Scenarios**:

1. **Given** the system purged Caches (image cache + source snapshots) while the app was not
   running, **When** the app launches with network available, **Then** playback starts
   normally — re-download is silent, no error surface, no onboarding re-entry.
2. **Given** the purge happened *and* the server is unreachable, **Then** the calm error
   state with auto-retry (topic 310) shows — offline survival guarantees that depend on
   purgeable storage (320's offline relaunch) are explicitly weaker on tvOS and degrade to
   this state.
3. **Given** normal operation, **Then** persistent app state in UserDefaults (settings,
   source list, budget) stays far below the 500 KB ceiling — image data and asset lists
   never migrate there.

### User Story 4 - Home Assistant parity in the living room (Priority: P2)

The TV frame is a first-class HA device like the wall frame: pause/play, source select,
availability, and diagnostics work identically; "brightness" dims the picture in software
(compositing toward black); actually powering the TV on/off stays HA's job (TV integration),
not the app's.

**Independent Test**: HAControlKit unit suite green for a tvOS destination; with a fake
transport: discovery announces a distinct device identity for the TV frame, pause/source/dim
commands round-trip, and the brightness entity drives the software-dim value.

**Acceptance Scenarios**:

1. **Given** broker credentials on the TV app, **Then** MQTT-over-TLS connects and HA
   discovery announces the TV frame as its **own device** (distinct identity — a household
   can run the iPad and the TV frame side by side).
2. **Given** an HA brightness command, **Then** the tvOS app applies it as a software dim
   (black compositing over the slideshow, 1.0 = no dim, near-0 = near-black; on
   self-emissive panels this genuinely reduces emitted light); the topic-400 engine
   semantics (ramps, sleep/wake roadmap) apply to this dim value.
3. **Given** pause/play/next/source-select commands (topics 700/710), **Then** they behave
   exactly as on the iPad.
4. **Given** the app is not frontmost or the Apple TV sleeps, **Then** LWT/availability
   reports the frame unavailable — same honesty as the iPad app in the background.

### Edge Cases

- **Menu vs. chrome**: with chrome visible, Menu/Back hides the chrome; only at the naked
  slideshow does Menu leave the app (standard tvOS layering, FR-1000-03).
- **Cache purge mid-session**: does not occur while the app runs (tvOS purges only when the
  app is not running) — no in-session handling needed beyond existing 320 tolerance.
- **KVS sync conflicts** (iPad and TV both edit sources/options): last-writer-wins at the
  key level is acceptable; the slideshow never interrupts playback on an incoming sync — 310
  reconciliation rules apply to source-list changes.
- **No Apple ID / iCloud disabled on the Apple TV**: sync silently unavailable; manual
  onboarding path carries everything (US2-3).
- **Same-model coexistence**: iPad and TV frame publish distinct HA devices; neither steals
  the other's discovery topics or retained state.
- **OLED burn-in**: playback has no static pixels — Ken Burns stays always-moving (existing
  behavior), chrome auto-hides, and any future clock overlay must pixel-shift (constraint
  recorded for topic 300/500's clock roadmap).
- **Older boxes**: tvOS 17 floor reaches Apple TV HD (2015) and later; tvOS 27 reportedly
  drops pre-2021 boxes — floor stays 17 regardless; nothing in this spec requires 26+ APIs
  (Liquid Glass is availability-gated exactly like on iOS via the existing compat shims).

## Requirements *(mandatory)*

### Functional Requirements

- **FR-1000-01**: The tvOS app MUST reuse the existing SPM packages unchanged (platform
  declarations extended to tvOS 17); package code MUST NOT fork per platform — platform
  differences live in the app targets behind the existing seams (constitution II).
- **FR-1000-02**: Deployment floor is tvOS 17. Anything newer (Liquid Glass at 26+) MUST be
  availability-gated through the same compat-shim pattern the iPad app uses (`View+Compat`).
- **FR-1000-03**: The slideshow MUST be fully operable with the Siri Remote alone: any remote
  interaction reveals the chrome (focus-driven), Play/Pause pauses/resumes, directional
  input/swipe advances photos, chrome auto-hides on idle, and Menu hides chrome first / exits
  to the Home screen from the naked slideshow — never trapped.
- **FR-1000-04**: Purgeable storage discipline: image data, snapshots, and anything
  re-creatable MUST live only in purgeable locations (Caches); persistent state
  (settings, source list, non-secret config) MUST live in UserDefaults and stay far below
  the 500 KB platform ceiling; nothing may assume a Documents directory exists. A cold start
  after a full purge MUST reach playback with no user input while the server is reachable
  (320's purge tolerance becomes the normal case).
- **FR-1000-05**: Secrets (Immich API key, shared-link passwords, MQTT credentials) MUST be
  stored only in the local tvOS keychain at rest (constitution III). Because tvOS keychain
  items never sync via iCloud Keychain, secrets arrive either through FR-1000-12's encrypted
  channel or by manual entry — and manual entry MUST always remain possible (the standalone
  guarantee). Secrets MUST NOT appear in iCloud key-value storage (unencrypted), UserDefaults,
  or plaintext CloudKit fields — the non-secret/secret split between the two sync channels is
  a hard boundary.
- **FR-1000-06**: Non-secret configuration (server URL, source library minus secrets, display
  options) MUST sync between the iPad and TV apps via iCloud key-value storage under the
  shared bundle identity, prefilling tvOS onboarding when present; sync MUST be additive
  convenience — the standalone manual path (with "Type with iPhone" continuation on every
  text field) MUST remain complete and equivalent.
- **FR-1000-07**: PowerKit's engine MUST drive a tvOS `ScreenControlling` whose "brightness"
  is a software dim (black compositing over the slideshow); idle-timer control maps to the
  tvOS idle timer (screensaver/sleep prevention during playback only). PowerKit itself MUST
  need zero changes (the seam holds); the one existing seam bypass
  (`SlideshowSettingsView.currentScreenBrightness()` reading `UIScreen` directly) MUST be
  eliminated rather than duplicated.
- **FR-1000-08**: The HA/MQTT surface (topics 600/700/710) MUST work identically on tvOS
  with a distinct per-device identity (own discovery entities, availability, retained
  state); the brightness entity maps to FR-1000-07's software dim. The MQTT dependency
  stays on the mqtt-nio 2.x line (the next major raises the floor to tvOS 18).
- **FR-1000-09**: The Share-Extension ingestion path does not exist on tvOS: shared links
  arrive via the synced source library (FR-1000-06) or manual entry; no code may depend on
  App-Group hand-off or `onOpenURL` on tvOS.
- **FR-1000-10**: Playback MUST leave no static pixels on screen: chrome auto-hides,
  transitions/drift keep motion (existing engine behavior suffices today); any future static
  overlay (clock) MUST pixel-shift on tvOS.
- **FR-1000-11**: All tvOS-specific logic (sync stores, software-dim screen controller,
  remote-interaction chrome triggers) MUST be host-unit-testable behind protocols with
  fakes — no tvOS device/simulator needed for the unit tier (constitution I/II).
- **FR-1000-12**: Secret sync iPad → TV MUST use exclusively Apple's end-to-end-encrypted
  CloudKit **private-database encrypted fields** (`CKRecord.encryptedValues`, system-managed
  keys — constitution III as amended, v1.1.0): the iPad app mirrors keychain secrets into
  encrypted fields; the TV app fetches them once, stores them in its local keychain, and
  reads them only from there. The app implements **no cryptography of its own** — no key
  generation, exchange, rotation, or recovery flows. Unavailable iCloud (no account,
  disabled, fetch failure) MUST degrade silently to the manual path (US2-3), never block
  onboarding. All sync logic sits behind a protocol with fakes (FR-1000-11); the CloudKit
  adapter stays thin.

### Key Entities

- **tvOS App Target**: second app target in the same project/app record (universal
  purchase, same bundle ID family), composing the same packages with tvOS implementations
  of the existing seams.
- **Config Sync Channel**: iCloud key-value store carrying only non-secret config
  (URL, sources sans secrets, options); last-writer-wins; absent on devices without iCloud.
- **Secret Sync Channel**: CloudKit private database, encrypted fields only — the single
  sanctioned secret transport (constitution III v1.1.0); write-through from the iPad's
  keychain stores, fetch-once-then-local-keychain on the TV.
- **Software-Dim Screen Controller**: the tvOS `ScreenControlling` — brightness as
  composited dim, idle timer as screensaver/sleep prevention.
- **Remote Chrome Model**: the interaction mapping — remote activity reveals chrome, focus
  navigates it, Play/Pause transport, Menu layering (hide chrome → exit).

### Roadmap / Deferred (not yet built)

- **Top Shelf extension**: album covers / "resume slideshow" above the top app row —
  nice-to-have after the MVP.
- **Photos/iCloud source on tvOS**: gated on prototyping PhotoKit's real third-party
  exposure on tvOS (topic 900 roadmap owns the source; this topic owns the platform).
- **DeviceDiscoveryUI pairing** (tvOS 16+, Apple TV 4K only): a local hand-off alternative
  for households without iCloud sync, deliberately not the primary path because it excludes
  Apple TV HD. (The primary secret path is FR-1000-12; this would be its offline cousin.)
- **Off-hours schedule via HA** (with topic 400's sleep/wake + reserved 730): the sanctioned
  "turn the TV off at night" story — the TV's power is HA's job.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-1000-01**: With the iPad app already configured and iCloud active, TV setup from
  first launch to playing slideshow takes under 2 minutes with **zero secrets typed on the
  TV** (FR-1000-12 path); the standalone shared-link path takes under 5 minutes with no iOS
  device involved.
- **SC-1000-02**: Every app function is reachable with the Siri Remote alone (App Review
  requirement) — verified by a remote-only walkthrough checklist.
- **SC-1000-03**: After a simulated full purge of purgeable storage, a cold start reaches
  the first photo with zero user interactions and zero error surfaces (server reachable).
- **SC-1000-04**: All existing package unit suites pass built for a tvOS destination with
  no package-code changes beyond platform declarations.
- **SC-1000-05**: A 24-hour soak on real hardware: no screensaver interruptions, no
  suspension while frontmost, HA availability stays truthful, and no static UI element was
  on screen at any point (burn-in review of recorded output).
- **SC-1000-06**: The TV frame appears in Home Assistant as its own device; pause/play,
  source select, and dim work from HA while the iPad frame runs simultaneously with no
  cross-talk.
- **SC-1000-07**: UserDefaults footprint on tvOS stays under 100 KB with a realistic source
  library (measured), leaving 5× headroom to the platform's 500 KB ceiling.
- **SC-1000-08**: An audit of everything the app writes to iCloud shows secret material
  exclusively inside CloudKit encrypted fields — never in key-value storage, plaintext
  record fields, or UserDefaults (asserted against the fake stores in unit tests,
  spot-checked once against the real container during the first spike).

## Assumptions

- Universal purchase (same app record, tvOS platform added) is the distribution model; the
  same bundle-ID family also unlocks iCloud KVS sharing and, if ever wanted, later
  DeviceDiscoveryUI pairing.
- mqtt-nio 2.x declares tvOS 12+ and on Apple platforms performs TLS through
  Network.framework (NIOSSL is not even linked there) — verified against the pinned
  checkout (2.13.0). HAControlKit therefore ports without dependency changes.
- The 500 KB / purgeable-storage rules stem from Apple's tvOS App Programming Guide
  (archived but never superseded) and are still enforced per 2024–2025 reporting; the spec
  treats them as binding. If Apple ever relaxes them, FR-1000-04 only gets easier.
- tvOS keychain non-sync is documented behavior (`kSecAttrSynchronizable` docs), not
  folklore — the secret-entry UX is designed around it, not in denial of it.
- The engine's existing purge tolerance (FR-320-09, SC-320-06) and resilience (topic 310)
  are the load-bearing base for US3; this spec adds no new engine behavior, only platform
  wiring.
- `CKRecord.encryptedValues` is available from iOS 15 / tvOS 15 — inside both floors. Its
  key hierarchy is system-managed (the user's iCloud infrastructure, 2FA-backed) and is
  separate from the third-party keychain-item sync that tvOS lacks; Apple TV already
  participates in Apple's end-to-end-encrypted services (e.g. HomeKit). Decryption on tvOS
  is therefore expected to work but MUST be proven by the first implementation spike — if
  it fails on real hardware, the fallbacks are manual entry (already the baseline) and the
  DeviceDiscoveryUI roadmap item.
- The iPad app will need a small companion change when FR-1000-06/FR-1000-12 land (writing
  non-secret config to iCloud KVS, mirroring keychain secrets into CloudKit encrypted
  fields) — specced then as 120/200/600-side amendments, not silently here.
