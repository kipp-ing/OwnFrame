# Data Model: Apple TV (1000)

## SyncedConfig — the non-secret snapshot (KVS payload)

Mirrors exactly the non-secret UserDefaults surface (recon-verified). **No secrets.** Codable,
Sendable, Equatable. Versioned (`schema: Int`) for forward tolerance. Last-writer-wins per key.

| Field | Source of truth (UserDefaults key) | Type | Secret? |
|---|---|---|---|
| `baseURL` | `immich.baseURL` | URL? | no |
| `sourceLibrary` | `immich.sourceLibrary` (SourceLibrary JSON) | Data/JSON | no (passwords are out-of-band) |
| `theme` | `theme.*` (order/duration/transition/kenBurns/fit/quality/clock.*) | ThemeSettings JSON | no |
| `cacheBudgetBytes` | `slideshow.cacheBudgetBytes` | Int64 | no |
| `haPublish` | `haPublish.options` | HAPublishOptions JSON | no |
| `brokerHost` | `mqtt.brokerHost` | String? | no |
| `brokerPort` | `mqtt.brokerPort` | Int? | no |

Explicitly **excluded** (secret, never in KVS): Immich API key, shared-link passwords, MQTT
credentials. `SourceKind.sharedLink` carries only `baseURL + slug` (password is keyed by
`Source.id` in the keychain, synced only via `SecretSyncStore`).

## SyncedSecret — the CloudKit encrypted payload (secret channel)

One private-DB record (`type = "FrameSecrets"`), all values in `encryptedValues` only:

| Encrypted field | Origin keychain (service / account) |
|---|---|
| `immichApiKey` | `de.kippings.ImmichSlideshow.apiKey` / `immich-api-key` |
| `mqttCredentials` | `de.kippings.ImmichSlideshow.mqttCredentials` / `mqtt-credentials` (JSON) |
| `sharedLinkPasswords` | `de.kippings.ImmichSlideshow.sharedLinkPassword` / per `Source.id` → `[id: password]` JSON |

Consumer fetches once, writes each secret into the local tvOS keychain via the existing three
seams, then reads only from the keychain. Unavailable iCloud ⇒ silent degrade to manual entry.

## Software-dim model

`SoftwareDimModel` (pure, host-testable): input `brightness ∈ [0,1]` → `overlayOpacity =
1 − clamp(brightness)`. Idle-timer state is a separate boolean forwarded to
`UIApplication.isIdleTimerDisabled` in the tvOS impl (not host-tested).

## Remote-chrome interaction model

`TVChromeModel` (pure, host-testable) states: `hidden` / `visible(autoHideDeadline)`.
Transitions: any remote activity ⇒ `visible` + arm auto-hide (4.5s, matches iOS
`chromeAutoHide`); auto-hide fires ⇒ `hidden`; Play/Pause ⇒ toggle pause (independent of
chrome); Menu ⇒ if `visible` → `hidden` (consumed), else → not consumed (system exits to Home).
Directional press ⇒ next/previous (maps the iOS swipe semantics) without revealing chrome.

## HA identity

`FrameIdentity { deviceID: String, deviceName: String }`. iOS: `identifierForVendor` +
"OwnFrame". tvOS: distinct stable id (`identifierForVendor` on tvOS, own fallback literal) +
"OwnFrame (Apple TV)". Distinct ⇒ own MQTT base topic, discovery identifiers, unique_ids.
