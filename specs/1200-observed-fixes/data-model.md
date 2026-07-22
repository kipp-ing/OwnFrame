# Data Model: Observed Frame Fixes (1200)

Only two small data shapes are introduced; the rest reuses existing models.

## 1. Album picker load state (Fix 1)

The picker's load phase gains a third case to carry the no-server distinction.

```
enum AlbumLoadPhase {
    case loading
    case loaded
    case noServer   // NEW — reached the album tab with no base URL + API key stored
    case failed     // network / API error against a configured server (existing message)
}
```

**Discriminator** — "is a server configured?" (pure, host-testable):

```
serverConfigured == (config.loadBaseURL() != nil) && (keychain.read() != nil)
```

- `loadBaseURL()` already requires `https` scheme + non-nil host (OnboardingKit `ConfigStore`).
- Evaluated **before** any network call; `noServer` never involves the network.
- Lives in an `OnboardingKit` helper/VM (not the view) for host testing.

**Rendering**:
- `noServer` → `ContentUnavailableView` "Add a server" + action → server-connection editor (FR-210-29).
- `failed` → existing retryable "Couldn't load albums".

## 2. BatteryReading + BatteryReporting (Fix 3)

Injectable seam keeping `HAControlKit` free of UIKit.

```
struct BatteryReading {
    let level: Int?      // 0–100 percent, or nil when unavailable/monitoring-not-ready
    let isOnPower: Bool  // true when charging or full-on-power
}

protocol BatteryReporting {           // implemented by the app adapter
    var hasBattery: Bool { get }      // false on tvOS → entities omitted
    var current: BatteryReading { get }
    // change signal: adapter pushes updates into the coordinator's echo path
}
```

**Mapping to MQTT** (per amended `specs/710-*/contracts/ha-mqtt-entities.md`):

| field | entity | HA component | payload |
|-------|--------|--------------|---------|
| `level` | `battery` | sensor (diagnostic) | integer 0–100, `device_class: battery`, unit `%`, `state_class: measurement` |
| `isOnPower` | `charging` | binary_sensor (diagnostic) | `ON`/`OFF`, `device_class: battery_charging` |

- `level == nil` → publish nothing misleading (skip/empty) until a real reading exists.
- `hasBattery == false` → `battery` and `charging` are **not** in `enabledEntities` (no discovery).
- Both are **read-only** → published by unentitled frames (free tier).

**Device → payload rules** (app adapter):
- `UIDevice.batteryLevel` (0.0–1.0) × 100, rounded → `level`; `-1.0` (unknown) → `nil`.
- `UIDevice.batteryState ∈ {.charging, .full}` → `isOnPower = true`; `.unplugged` → `false`;
  `.unknown` → `false` (not a false ON).

## 3. Ken Burns framing decision (Fix 2)

No new type — a change to the existing decision and the motion input.

```
fillsScreen := (settings.fit == .fill)          // was: || effectiveKenBurns
kenBurnsPan := (settings.fit == .fill) ? basePan : 0   // basePan = 16 (iPad) / 24 (tvOS)
```

- Fit → `scaledToFit`, `pan = 0` (centered zoom only).
- Fill → `scaledToFill`, `pan = basePan` (unchanged).
- `KenBurnsDrift` scale envelope unchanged.
