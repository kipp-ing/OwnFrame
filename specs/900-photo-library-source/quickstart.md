# Quickstart — validating Photo Library Source

Validation scenarios per phase; details live in [contracts](./contracts/photo-source-protocol.md)
and [data-model.md](./data-model.md). Fidelity to FR/SC IDs from [spec.md](./spec.md).

## Prerequisites

- Xcode with iOS 17+ simulators (XcodeBuildMCP session defaults per `sim-build-destination`
  memory), host Swift toolchain for package tests.
- For the final device gates only: an iPad with iCloud photos + a legacy shared album, and
  (at ship time) an iOS 27 beta device.

## Phase-1 gate — refactor holds (no behavior change)

```bash
swift test --package-path Packages/PhotoSourceKit
swift test --package-path Packages/SlideshowKit     # full suite green against StubPhotoSource
swift test --package-path Packages/ImmichClient     # conformance + error-mapping suites
```

Expected: every pre-existing SlideshowKit test passes unmodified in *behavior* (renames
allowed); snapshot round-trip test decodes a checked-in **legacy** `{id,type}` JSON fixture
(R2). App target builds via XcodeBuildMCP (`build_sim`) — proves adapter/HA call sites moved
to neutral types. → SC-900-03 precondition.

## Phase-2 gate — provider logic (host-only)

```bash
swift test --package-path Packages/PhotoLibraryKit
```

Expected green suites: authorization matrix (data-model table — incl. downgrade mid-life →
`.authentication` for album sources, Selected-Photos unaffected: US3-4); vanish →
`.notFound` (FR-900-16); degraded-delivery guard (FR-900-07); Live-Photo → `.image` mapping
(FR-900-08); change-handler → engine refresh (FR-900-09). Plus the seam test: no
`import Photos` outside `PHKitGateway.swift`.

**Dual-fake proof (SC-900-03)**: SlideshowKit engine scenario suite runs parameterized over
`StubPhotoSource` and `PhotoLibraryProvider(gateway: FakePhotoLibraryGateway)` — identical
assertions, both green.

## Phase-3 gate — app integration (simulator)

- XcodeBuildMCP `test_sim` on the app test bundle (whole classes).
- New UITests (hermetic `--uitest` seams, in-memory gateway fake): picker full/limited/denied
  surfaces (SC-900-05), source switch Immich ↔ Photos via Settings → Sources (SC-900-06),
  vanish state copy (FR-900-16).
- Full XCUITest suite before merge (standing rule; broker-toggle flake: rerun that class
  isolated before suspecting the diff).

## Phase-4 / release gates (manual, scheduled — not this session)

- **SC-900-02**: real iPad, optimized storage, cold cache — full album cycle, zero blank
  frames (verify by video luminance method if in doubt).
- **SC-900-04**: add/remove a photo in Photos app → frame updates without restart.
- **SC-900-01**: stopwatch a fresh source-picker → playing flow (< 1 min).
- **SC-900-07** (ship gate): newest iOS beta + real legacy shared album; exercise the
  owner-upgrade vanish drill.

## HA parity spot-check (Phase 4)

With a Photos source active: HA source select lists it, current-photo *metadata* publishes
date (+ coordinates if present, no placeName — R7), image publishing only under the existing
global opt-in (FR-900-11/12).
