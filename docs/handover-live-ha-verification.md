# Handover — Live Home Assistant Verification Session

Written 2026-07-05 at the end of the maturity-hardening session. This is the entry point for the
next session, whose single goal is: **confirm topics 700 + 710 against the real broker and a live
Home Assistant, then close the last open verification caveat.**

## Where the repo stands

- `main` is green and current: spec 710 (HA full control) merged via PR #10, maturity hardening
  (CI, Swift 6, shared scheme, pinned dependencies, privacy manifest, spec-drift fixes) via PR #12.
  All module specs are **Active**; 710 is 41/41 tasks.
- Verified state: 305 host unit tests across 7 packages, 66/66 simulator tests (app-hosted +
  XCUITest) on iPad Pro 11-inch (M5), iOS 26.5. GitHub Actions runs the package suites per push/PR.
- The **only unverified surface** is live Home Assistant behavior. Everything up to the broker is
  covered by automated tests (see below); HA's interpretation of discovery/state is not.

## What to do

Work through **[manual-verification.md](manual-verification.md)** — specifically:

1. **Topic 700 section** (T019 pause/play + availability/LWT, T023 brightness, T027 album select).
2. **Topic 710 section** (added 2026-07-05): full entity discovery, 9-settings round-trip + echo,
   validation no-ops, next/previous, current-photo sensor + opt-in image, non-retained photo
   topics, reconnect republish, diagnostics.

One live session covers both. When everything passes: tick the checklist items, then remove the
"live Home-Assistant confirmation is still pending" sentence from the README banner.

## How to run

- **App side**: run the slideshow in the **foreground** (broker connection, brightness, and idle
  control are foreground-only by design). Broker credentials: slideshow chrome → Settings → MQTT.
  The photo-image entity needs Settings → MQTT → "Publish photo image to Home Assistant" (off by
  default).
- **Entity/topic reference**: `specs/710-ha-full-control/contracts/ha-mqtt-entities.md` — topic
  scheme, all 16+3 entities, payload options, retention rules.
- **Automated pre-checks** (already green in CI/local, rerun if the broker changed):
  - Local mosquitto TLS transport check: `MQTT_INTEGRATION=1 Packages/HAControlKit/Scripts/mqtt-integration.sh`
  - Real broker (production TLS path, disposable device ID, cleans up after itself):
    `cd Packages/HAControlKit && MQTT_REAL=1 MQTT_HOST=<host> MQTT_PORT=8883 MQTT_USER=<user> MQTT_PASS=<pass> swift test --filter RealBrokerIntegrationTests`
- **Debugging**: `mosquitto_sub -v -t 'immichslideshow/#' -t 'homeassistant/#'` against the broker
  shows discovery, state, and retention behavior directly.

## Gotchas (hard-won, see memory + engineering-notes)

- Simulator builds: only **iOS 26.5** destinations build the app scheme; pin `simulatorId`
  (not `simulatorName`) in XcodeBuildMCP session defaults, `preferXcodebuild: true`.
- The gh CLI has two accounts on this machine; pushes need `gh auth switch -u kipp-ing`.
- On device, backgrounding the app must flip availability to `offline` (LWT) — that is expected
  behavior, not a bug (constraint: iOS reclaims control in the background).
- Broker credentials never appear in UserDefaults or logs — if a debugging session needs them,
  read from the Keychain UI path, don't add logging (constitution III/IV).

## After the session

- Tick `manual-verification.md`, update the README banner.
- If HA shows issues (entity naming, device grouping, value templates), the discovery payloads
  live in `HAControlKit` (`HAEntity` / discovery builders) — fixes are host-unit-testable; follow
  TDD and rerun the full simulator gate before merging (see CLAUDE.md working method).
- Consider tagging the first release once live verification passes (version is still 1.0 (1)).
