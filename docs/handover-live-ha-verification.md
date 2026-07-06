# Handover — Live Home Assistant Verification, Session 2

Written 2026-07-05 at the end of the **first** live-verification session (the previous version of
this file was the entry point *into* that session; this version supersedes it for the next one).
Session 1 got the app connected to a real broker + real HA instance for the first time, found and
fixed 4 real bugs via TDD, and got most of the 700+710 checklist passing live. **Not finished** —
pick up with the "Open / unresolved" section below.

## Where things stand

- Live verification works and is largely green: the app ran on the user's **physical iPad**
  (not the simulator — see Gotcha below), connected to a real broker (`home.kippings.de:8883`)
  and a real HA instance with the MQTT integration ("Mosquitto broker").
- Found and fixed **4 real bugs**, each via a red test first, each confirmed green
  (80/80 `HAControlKit` host tests, 67/67 full simulator suite) *and* confirmed live against the
  real broker/HA:
  1. **Missing entities in production.** `Immich_SlideshowApp.swift`'s `makeCoordinator` only
     ever enabled 13 of the 18 default entities — `next`, `previous`, `phase`, `photo_count`,
     `version` were fully implemented in `HAControlKit` (discovery, coordinator logic, host
     tests) but never wired into the shipped app. Fixed by adding
     `HAEntity.defaultEnabled` (`HAEntityState.swift`) — all cases except the opt-in
     `currentPhotoImage` — and using it in `Immich_SlideshowApp.swift` instead of a hand-rolled
     subset. Verified: HA now shows 19 entities (was 14).
  2. **In-app pause/resume never reached HA.** `SlideshowChrome`'s play/pause button calls
     `viewModel.togglePause()` directly on `SlideshowViewModel`, never through
     `SlideshowRemoteControlAdapter`. The adapter only fired `onLocalChange` from its own
     `pause()`/`resume()` methods, so a chrome-driven pause was invisible to it. Fixed:
     `SlideshowRemoteControlAdapter` now reactively observes `slideshow.isPaused` via
     `observePlayback()` (mirrors the existing `observeCurrentPhoto`/`observeThemeSettings`
     pattern); `playbackState` is now computed from `slideshow.isPaused` instead of a
     separately-tracked stored property; `pause()`/`resume()` (used for remote/HA commands) now
     go through `slideshow.togglePause()` (guarded) so both origins update the same source of
     truth. Verified live both directions (HA→app and app→HA).
  3. **Backgrounding never actually flipped HA to offline.** `HAControlCoordinator.stop()` (called
     when the app backgrounds) only relied on the MQTT Will/LWT for "offline" — but a clean MQTT
     DISCONNECT *always suppresses the Will* per protocol, so the retained availability topic
     stayed stuck on "online" forever after backgrounding. Fixed: `stop()` now explicitly
     publishes a retained `"offline"` message before disconnecting. Verified live: backgrounding
     now flips HA to offline, foregrounding flips it back to online.
  4. **Brightness light stuck on "unknown" in HA.** The `.brightness` discovery payload carried a
     generic `state_topic` (from the shared base fields) *in addition to*
     `brightness_state_topic`, both pointing at the same topic. HA's MQTT light schema treats a
     present `state_topic` as the authoritative ON/OFF state (expecting `"ON"`/`"OFF"`), so it
     tried to parse the raw numeric brightness value and gave up, showing the light as
     permanently `unknown`. Fixed in `HADiscovery.swift`: removed `state_topic` for `.brightness`
     (kept `command_topic`, which HA's schema requires even with `on_command_type: brightness` —
     an interim mistake that *also* removed `command_topic` made the whole payload schema-invalid,
     so HA silently dropped it and the entity never reappeared no matter how many times we
     reloaded/re-announced; corrected by putting `command_topic` back). Verified live: brightness
     entity now shows correctly, and setting it low from HA visibly dimmed the iPad's screen.
- Fully verified live, both directions where applicable: **T019** (pause/play + availability/LWT),
  **T023** (brightness, incl. visual dimming), **T027** (album select + invalid-value no-op), and
  the **9-setting round-trip** (order/duration/transition/ken_burns/fit/quality/clock/
  clock_corner/clock_date) both directions plus validation (out-of-range duration, unknown select
  option both correctly no-op).
- **Confirmed but deliberately NOT fixed** (user chose to defer, see below): the **clock overlay**
  setting has *zero* visual implementation. `ThemeSettings.clock` (isOn/corner/showDate) is fully
  modeled, persisted, exposed in the Settings sheet, and now correctly round-trips through HA (the
  switch + 2 selects all echo correctly) — but no SwiftUI view anywhere actually renders a clock,
  and `SlideshowView` unconditionally hides the system status bar
  (`.statusBarHidden(true)`) with no conditional fallback either. This is a **missing feature**,
  not a bug — needs its own spec/plan + TDD implementation as a follow-up. Do not attempt it as
  part of a "live verification" session again; it needs the normal SDD workflow.

## Open / unresolved — pick up here

- **`next` button / `current_photo` sensor did not update.** Pressed "next" via HA
  (`button.press` on `button.immich_slideshow_slideshow_next`); `sensor.immich_slideshow_
  slideshow_current_photo` kept the exact same asset ID and `last_changed` timestamp, despite
  `photo_count=45`, `phase=playing`, `playback=on` (so it's not an empty-album or paused-state
  issue). **We stopped mid-investigation** — the very next step is confirming whether the photo
  actually advanced *on the iPad's screen* when "next" was pressed:
  - If it advanced visually but the sensor didn't echo: likely another observation/echo gap in
    the same family as bug #2 above — check `SlideshowRemoteControlAdapter.observeCurrentPhoto()`
    and `HAControlCoordinator.schedulePhotoPublish()`, and whether `adapter.showNext()` (used for
    the HA button path, in the `PhotoReporting` extension) actually changes something
    `observeCurrentPhoto` is tracking (`slideshow.currentAssetID`/`slideshow.phase`).
  - If it didn't advance at all: the bug is upstream, in how `HAControlCoordinator.handleIncoming`
    dispatches `.next`/`.previous` button commands to `photoReporter?.showNext()`, or in
    `SlideshowViewModel.showNext()` itself under these specific runtime conditions.
- **Remaining 710 checklist** (`docs/manual-verification.md`, "Topic 710" section):
  - Non-retention proof for `current_photo`/`current_photo_image`: re-confirm explicitly with
    `mosquitto_sub -v` bracketing a live photo change (we only confirmed "didn't show up in one
    broad subscribe", not a rigorous check).
  - `current_photo_image`: the image toggle is on and the HA `image` entity exists, but we never
    confirmed an actual image renders in HA's image entity card.
  - Reconnect republish: drop/restart the broker connection → confirm full state (all 18 settings
    + current photo) republishes without creating a duplicate HA device. Not started.
  - Diagnostics: `phase`/`photo_count` were spot-checked correct as a side effect of other tests;
    `version` was never checked; the general "diagnostics reflect connection state" (spec 710 US4)
    wasn't explicitly exercised (e.g. what do these sensors show while disconnected/reconnecting).
- Once all of the above pass: tick `docs/manual-verification.md` (700's T019/T023/T027 + the 710
  section), remove the "live Home-Assistant confirmation is still pending" line from the README
  banner (per the original handover's closing instructions), and reconsider tagging the first
  release (version is still 1.0 (1)).

## Repo state — uncommitted

Nothing from this session has been committed. `git status --short`:

```
 M Immich Slideshow/Immich_SlideshowApp.swift
 M Immich Slideshow/Localizable.xcstrings
 M Immich Slideshow/Slideshow/SlideshowRemoteControlAdapter.swift
 M Immich SlideshowTests/HAControlRoundTripTests.swift
 M Packages/HAControlKit/Sources/HAControlKit/HAControlCoordinator.swift
 M Packages/HAControlKit/Sources/HAControlKit/HADiscovery.swift
 M Packages/HAControlKit/Sources/HAControlKit/HAEntityState.swift
 M Packages/HAControlKit/Tests/HAControlKitTests/HAControlCoordinatorTests.swift
 M Packages/HAControlKit/Tests/HAControlKitTests/HADiscoveryTests.swift
?? Packages/HAControlKit/Tests/HAControlKitTests/HAEntityDefaultsTests.swift
```

The `Localizable.xcstrings` change is incidental — Xcode auto-registered a few new UI strings
(English source only, `isCommentAutoGenerated: true`) while building from Xcode directly; not
something we edited, safe to include, nothing to review there.

All 4 fixes are covered by tests and green (80/80 `HAControlKit`, 67/67 full simulator suite as of
the last full run this session). Suggest committing (one commit per fix, or logically grouped) at
the start of next session before continuing — ask the user first, per normal workflow.

## How to resume

- **Access**: broker `home.kippings.de:8883`, user `car` (password was shared verbally in-session,
  marked by the user as to-be-rotated — get a fresh one if it's since changed; never stored in
  this repo). HA via `hactl` pointed at `/Users/jan/dev/repos/hactl-dev/jansHA`
  (`HA_URL=https://home.kippings.de`, token in that dir's `.env`).
- **Simulator can't be used for this.** The real broker's TLS cert chain (ZeroSSL leaf →
  `ZeroSSL ECC DV SSL CA 2` → `Sectigo Public Server Authentication Root E46`, cross-signed by the
  long-established `USERTrust ECC Certification Authority`) fails TLS with `NIOCore.ChannelError`
  / `"Invalid certificate format"` **specifically inside the iOS Simulator runtime** — not on the
  host Mac (`swift test --filter RealBrokerIntegrationTests` passes fine) and not on the real
  iPad. Always use the physical iPad for live HA verification work.
- **Useful commands**:
  - `cd /Users/jan/dev/repos/hactl-dev/jansHA && hactl ent show <entity_id> --full` /
    `hactl svc call <domain.service> -d '{...}'` — query/drive HA directly.
  - `mosquitto_sub -h home.kippings.de -p 8883 --cafile /etc/ssl/cert.pem -u car -P '<pass>' -t '...' -v -W <secs>`
    — inspect raw MQTT topics (macOS has no `/etc/ssl/certs` dir; use the `/etc/ssl/cert.pem`
    bundle file, not a `--capath` directory).
- **Reconnect gotcha**: saving broker credentials or changing settings from within the app does
  **not** itself trigger a (re)connect attempt — only app launch or a foreground `scenePhase`
  transition does (`SlideshowView`'s `.task`/`.onChange(of: scenePhase)`). Background+foreground
  the app to force a reconnect/re-announce when testing a fix that needs one.
- **Stale-discovery-entity gotcha**: if HA shows a wrong/stuck entity from an old discovery
  payload (like the brightness saga), the reliable reset sequence is: (1) clear the retained
  discovery config topic with `mosquitto_pub -r -n -t 'homeassistant/<component>/<deviceID>/<entity>/config'`
  to force HA to remove the entity, (2) reload the MQTT config entry —
  `curl -X POST -H "Authorization: Bearer $HA_TOKEN" "$HA_URL/api/config/config_entries/entry/<entry_id>/reload"`
  (get `<entry_id>` via `hactl config entries --domain mqtt`), (3) background+foreground the app
  for a fresh discovery announce.
- **Diagnostic-print technique**: when something completes successfully in code but the live
  effect isn't visible, temporary `print("[DIAG] ...")` statements + asking the user to read
  Xcode's console after acting is faster than guessing — remove them once the chain is confirmed
  (used successfully to rule out the playback-echo fix as broken; it wasn't, the issue was just
  live-watch timing).
