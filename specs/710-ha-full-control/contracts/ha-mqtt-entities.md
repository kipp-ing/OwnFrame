# Contracts — HA Full Control (MQTT)

Interface contract this feature exposes: the MQTT topic scheme and Home Assistant discovery
payloads `HAControlKit` publishes/subscribes to. Extends the existing 700 contract (unchanged
topics for `playback`/`brightness`/`album` — FR-710-08).

## 1. Topic scheme

```
ownframe/<deviceID>/availability                  (retained, online|offline, LWT — unchanged)
ownframe/<deviceID>/<entity>/set                  (commands, NOT retained)
ownframe/<deviceID>/<entity>/state                (state, retained — except the two below)
ownframe/<deviceID>/current_photo/state           (JSON: id + attributes, NOT retained)
ownframe/<deviceID>/current_photo_image/state     (raw image bytes, NOT retained)
homeassistant/<component>/<deviceID>/<entity>/config     (discovery, retained — unchanged)
```

The two NOT-retained state topics are the resolved Clarifications: neither the photo nor what it
depicted lingers on the broker; both are republished on (re)connect/announce instead (FR-710-13).

## 2. Entity map

| entity (rawValue)     | HA component        | payload / options                                             | maps to |
|------------------------|----------------------|-----------------------------------------------------------------|---------|
| `playback` (existing)  | switch               | `ON`/`OFF`                                                       | pause/resume |
| `brightness` (existing)| light                | brightness 0–255                                                 | PowerManager |
| `album` (existing)     | select               | album names                                                      | switchAlbum |
| `order`                | select               | `shuffle`, `sequential`                                          | ThemeSettings.order |
| `duration`              | number               | 3–600, step 1, unit `s`                                          | ThemeSettings.duration |
| `transition`            | select               | `crossfade`, `slide`, `dissolve`, `none`                         | ThemeSettings.transition |
| `ken_burns`             | switch               | `ON`/`OFF`                                                       | ThemeSettings.kenBurns |
| `fit`                   | select               | `fit`, `fill`                                                    | ThemeSettings.fit |
| `quality`               | select               | `preview`, `original`                                            | ThemeSettings.quality |
| `clock`                 | switch               | `ON`/`OFF`                                                       | clock.isOn |
| `clock_corner`          | select               | `topLeading`, `topTrailing`, `bottomLeading`, `bottomTrailing`   | clock.corner |
| `clock_date`            | switch               | `ON`/`OFF`                                                       | clock.showDate |
| `next`                  | button               | `PRESS`                                                          | showNext |
| `previous`              | button               | `PRESS`                                                          | showPrevious |
| `current_photo`         | sensor               | state = asset ID (`value_template`); attrs = JSON (§3)           | photo change |
| `current_photo_image`   | image                | raw bytes, `content_type: image/jpeg`                            | photo change |
| `phase`                 | sensor (diagnostic)  | `loading\|playing\|empty\|failed`                                | SlideshowPhase |
| `photo_count`           | sensor (diagnostic)  | integer                                                          | active album asset count |
| `version`               | sensor (diagnostic)  | app version string                                               | bundle |
| `battery`               | sensor (diagnostic)  | integer 0–100, `device_class: battery`, unit `%`                 | UIDevice.batteryLevel |
| `charging`              | binary_sensor (diag) | `ON`/`OFF`, `device_class: battery_charging` (ON = on power)     | UIDevice.batteryState |
| `frame_status`          | sensor (diagnostic)  | `running`\|`inactive`                                            | explicit UI-visibility signal (2026-07-26, FR-710-24) |

Enabled by default: all except `current_photo_image` (opt-in — FR-710-15, `HAPublishOptions`).
`battery` and `charging` are published only on battery-bearing devices (absent on Apple TV, which
has no battery — FR-710-23). `frame_status` is read-only, free-tier telemetry (FR-1100-03a),
orthogonal to `phase` — added 2026-07-26 alongside the 700 amendment FR-700-23, which is what
availability itself now excludes (in-app UI presentation is not a connectivity change).

## 3. `current_photo` payload (research.md §2)

One JSON payload on `current_photo/state`, used as both `state_topic` (via `value_template`) and
`json_attributes_topic` in discovery:

```json
{
  "id": "b3f1...-asset-id",
  "taken_at": "2024-08-11T14:32:00Z",
  "city": "Lisbon",
  "state": null,
  "country": "Portugal",
  "album_id": "a1b2...",
  "album_name": "Summer 2024"
}
```

When `phase != playing` (empty/failed/loading), the topic publishes a cleared payload (`id: null`,
all attributes `null`) rather than leaving the last real photo's data in place (User Story 4,
acceptance scenario 3) — this is the concrete form of the "unknown/cleared" state referenced in
spec.md.

## 4. Command validation matrix

| type   | rule                                   | on violation             |
|--------|-----------------------------------------|---------------------------|
| select | payload ∈ enum raw values               | ignore + re-echo actual  |
| number | 3 ≤ v ≤ 600, integer seconds             | ignore + re-echo actual  |
| switch | payload ∈ {`ON`,`OFF`}                   | ignore + re-echo actual  |
| button | payload == `PRESS` (HA default)          | ignore                   |

## 5. Discovery additions (per entity, beyond the shared fields every entity already carries —
`unique_id`, `availability_topic`, `device`, `name`)

- select: `options: [String]`, `command_topic`, `state_topic`.
- number (`duration`): `min: 3`, `max: 600`, `step: 1`, `unit_of_measurement: "s"`,
  `command_topic`, `state_topic`.
- switch: `payload_on: "ON"`, `payload_off: "OFF"`, `command_topic`, `state_topic`.
- button: `payload_press: "PRESS"`, `command_topic` (no `state_topic`).
- image: `content_type: "image/jpeg"`, `image_topic` (not retained).
- sensor (`current_photo`): `state_topic`, `value_template`, `json_attributes_topic` (same topic).
- sensor (diagnostics): `state_topic`, `entity_category: "diagnostic"`.
- sensor (`battery`): `state_topic`, `entity_category: "diagnostic"`, `device_class: "battery"`,
  `unit_of_measurement: "%"`, `state_class: "measurement"`.
- binary_sensor (`charging`): `state_topic`, `entity_category: "diagnostic"`,
  `device_class: "battery_charging"`, `payload_on: "ON"`, `payload_off: "OFF"`.

## 6. Loop safety (FR-710-12/20)

`HAControlCoordinator` never subscribes to any `.../state` topic, only `.../set` topics — commands
and state are structurally separate, so an echo can never be re-read as a command. For the
`onLocalChange`-style callbacks (renamed `onSettingsChange`/`onPhotoChange` on the split
protocols), the adapter sets a suppress flag around its own application of a remote command before
calling into `ThemeSettingsStore`/`SlideshowViewModel`, so the resulting local-change callback is
swallowed once instead of triggering a second echo (extends the existing `onLocalChange` pattern
already used for `playback`/`brightness`/`album`).
