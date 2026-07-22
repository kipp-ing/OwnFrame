# Quickstart & Verification: Apple TV (1000)

## Build / run (simulator)

- tvOS sim: **Apple TV 4K (3rd generation)** `C3A8C51D-0CA6-45B2-BE17-1B11E1BF7AC8`, tvOS 26.5.
- Scheme: `OwnFrameTV`. Build/run/test via XcodeBuildMCP (`build_sim` / `test_sim` /
  `build_run_sim`, `screenshot`, `record_sim_video`).
- iOS regression: existing `OwnFrame` scheme on an iOS 26.x iPad sim stays green.
- Host unit tier: `swift test` in each touched package (esp. `Packages/ConfigSyncKit`).

## Session verification gate (simulator-provable)

- SC-1000-04: tvOS app + all linked package main targets compile for the tvOS destination;
  package unit suites green on host; tvOS-clean suites green on the tvOS destination.
- US1: tvOS app cold-launches into the slideshow (stub API), transitions/Ken Burns render,
  idle timer disabled during playback (screenshot/video).
- FR-1000-03: remote walkthrough on the sim — activity reveals chrome, Play/Pause, directional
  next/prev, Menu hides chrome then exits from the naked slideshow.
- FR-1000-07: brightness read through the seam (no `UIScreen` bypass); HA dim composites black.
- US2: all four acceptance scenarios green against fakes (contracts/config-sync.md).
- SC-1000-07: UserDefaults footprint measured < 100 KB with a realistic library.

## Device gates (real Apple TV — deferred, NOT session blockers)

- **SC-1000-08 spot-check**: audit the real iCloud container shows secrets only in CloudKit
  encrypted fields.
- **CloudKit decrypt on tvOS**: prove `encryptedValues` fetch/decrypt on real hardware (spec
  Assumptions); fallback is manual entry (already the baseline).
- **SC-1000-05**: 24h soak — no screensaver/suspension, truthful HA availability, no static pixel.
- **SC-1000-02**: remote-only walkthrough on a physical Siri Remote.
- **SC-1000-06**: iPad + TV frames as distinct HA devices, live, no cross-talk.
