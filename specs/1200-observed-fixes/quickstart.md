# Quickstart / Validation: Observed Frame Fixes (1200)

How to verify each fix. Host tests run via `swift test`; app-target + UI checks via XcodeBuildMCP on
the iOS 18.x simulator (and Framepad 17.7.10 for the manual Ken Burns gate).

## Prerequisites

- Swift 6 toolchain; XcodeBuildMCP configured (see `docs/testing.md`).
- No real Immich server, broker, or device required for the automated suite (all behind protocols).

## Fix 1 — Album-tab no-server guidance (FR-210-30 / SC-210-13)

**Host test (red first)** — the no-server predicate in `OnboardingKit`:
- Given no base URL and no key → `serverConfigured == false`.
- Given base URL + key → `true`. Given only one → `false`.

**Simulator check**:
1. Launch with a shared-link-only setup (no API key). Open source picker → **Album** tab.
   - Expected: "Add a server" prompt with an action that opens the connection editor — **not**
     "Couldn't load albums".
2. Configure a server, then break connectivity (unreachable host), open the Album tab.
   - Expected: the distinct retryable "Couldn't load albums" error.

## Fix 2 — Ken Burns honors Fit (FR-500-20 / SC-500-09, FR-300-33 / SC-300-13)

**Host test (red first)** — `SlideshowKit`:
- `fillsScreen` is `false` when `fit == .fit` regardless of Ken Burns on/off.
- `fillsScreen` is `true` when `fit == .fill`.
- Ken Burns pan input is `0` under Fit, `basePan` under Fill.

**UI regression test** (XCUITest): chrome edge insets pixel-identical Ken-Burns-on vs off, in both
Fit and Fill, portrait + landscape (SC-300-13).

**Manual Framepad gate** (perceived motion, out of automated scope):
- Fit + Ken Burns on, mismatched-aspect photo → whole photo stays visible, gentle centered zoom, no
  side background revealed, no jump on advance.
- Fill + Ken Burns on → unchanged from today.

## Fix 3 — Battery + charging telemetry (FR-710-23 / SC-710-07)

**Host test (red first)** — `HAControlKit` with fake `MQTTTransport` + injected `BatteryReporting`:
- Discovery for `battery`: `device_class: battery`, `unit_of_measurement: "%"`,
  `state_class: measurement`, `entity_category: diagnostic`, no `command_topic`.
- Discovery for `charging`: `binary_sensor`, `device_class: battery_charging`,
  `payload_on/off: ON/OFF`, `entity_category: diagnostic`.
- Echo: `level = 87` → `battery/state` publishes `"87"`; `isOnPower = true` → `charging/state`
  publishes `"ON"`.
- `hasBattery == false` → neither entity appears in discovery/announce.
- Both are read-only → published under the unentitled (telemetry-only) coordinator mode.

**Manual/device check** (device-day): confirm HA shows the battery % and charging entities and they
track the real device; confirm Apple TV shows neither.

## Full gate (owned by Claude)

- `swift test` green for `OnboardingKit`, `SlideshowKit`, `HAControlKit` (host).
- XcodeBuildMCP: `OwnFrame` + `OwnFrameTV` build; iOS test suite green incl. the inset regression.
- No secrets in code/UserDefaults/logs (unchanged surfaces).
