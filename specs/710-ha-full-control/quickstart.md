# Quickstart — HA Full Control validation

How to prove the feature end-to-end. Logic via `swift test` (host, fake `MQTTTransport` + fake
`ImmichAPI` + fakes for `SettingsControlling`/`PhotoReporting`); UI (broker-setup toggle) via
XcodeBuildMCP/XCUITest on the pinned iOS 26.5 simulator. Each scenario maps to FR/SC in `spec.md`.

## Prerequisites

- Build/test through XcodeBuildMCP (no hand-parsed `xcodebuild`).
- Fakes: extend `Fakes.swift` in `HAControlKitTests` with an in-memory `HAPublishOptionsStore` and
  split fakes for `PlaybackControlling`/`SettingsControlling`/`PhotoReporting`. No live broker or
  Immich server needed for the suite.
- No real HA instance required — discovery/state/echo are asserted against the fake transport's
  captured publishes.

## Logic scenarios (Swift Testing, host)

1. **Discovery completeness** (FR-710-01/02/03/07/18) — `announce()` with all entities enabled
   publishes exactly one discovery config per `HAEntity` case, each with the right component
   (select/number/switch/button/image/sensor), the enum's raw values as `options` where
   applicable, `duration`'s min/max/step, and diagnostic entities carrying
   `entity_category: diagnostic`.
2. **Settings round-trip** (FR-710-09/10/12 / SC-710-01/02) — for each of the 9 settings entities:
   valid command → applied through `SettingsControlling.apply(_:)` → persisted → echoed exactly
   once; out-of-range/invalid payload → setting unchanged, actual value re-echoed; a local change
   (mutate `ThemeSettingsStore` directly, as the in-app UI would) publishes the new state without
   any inbound command.
3. **Echo-loop safety** (FR-710-12/20 / SC-710-02) — apply a remote settings command; assert the
   resulting local-change callback does not trigger a second echo cycle; a soak of N rapid valid
   commands on one entity produces ≤ N+1 publishes.
4. **Navigation** (FR-710-04) — `next`/`previous` button commands call `showNext()`/
   `showPrevious()`; pressing while paused steps without resuming; the timer-reset/works-while-
   paused semantics are asserted the same way the existing chrome tests assert them.
5. **Current photo** (FR-710-05/06/13 / SC-710-04) — a `PhotoReport` with `phase: .playing`
   publishes the image topic (bytes present) and the `current_photo` topic (JSON with all fields);
   a `PhotoReport` with `phase: .empty`/`.failed`/`.loading` publishes the cleared/null form on
   both topics; the publish call is a detached side effect that returns before the image bytes are
   ready (no delay to the caller).
6. **Metadata cache** (FR-710-22) — the same asset ID requested twice does not call `assetInfo`
   twice; a cache built past its limit evicts the least-recently-used entry; a fetch failure is not
   cached (the next visit retries).
7. **Image cap** (FR-710-14/15 / SC-710-05) — payload under the cap publishes as-is; over the cap
   triggers a downscale attempt; still-over-cap after downscale skips the publish with a log call
   and leaves the metadata sensor unaffected; `imageEnabled = false` never calls the image
   publisher at all.
8. **Reconnect/announce** (FR-710-13 / SC-710-03) — simulate a reconnect: discovery, availability,
   and the state of every enabled entity (including a republish of the current photo) are
   published again, overwriting any stale retained value a prior test left on the fake transport.
9. **Diagnostics** (FR-710-07) — `phase`/`photo_count`/`version` echo the coordinator's actual
   values and update when the active album (and thus asset count) changes.

## UI scenario (XCUITest, `--uitest`)

10. **Broker-setup image toggle** (FR-710-15) — open the broker-setup Settings screen; the image-
    publishing toggle is off by default; toggling it on persists through `HAPublishOptionsStore`
    and survives a relaunch.

## Definition of done

- All logic scenarios green on host `swift test`; UI scenario green via XcodeBuildMCP/XCUITest;
  full XCUITest run before merge (screenshots miss UI-test regressions — see project memory).
- No broker credential, API key, or share-link password in any log, UserDefaults entry, or test
  fixture (SC-710-06 extends the existing secrets guarantee).
- Entire suite (all 9 logic scenarios) runs with no real broker or Immich server reachable.
