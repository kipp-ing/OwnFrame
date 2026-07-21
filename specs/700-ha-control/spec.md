# Feature Specification: Home Assistant Control (MQTT)

**Feature Branch**: `700-ha-control`

**Created**: 2026-06-23

**Status**: Active — **amended 2026-07-21** (frame identity, US3 / FR-700-16…22 / SC-700-11…14).
The identity half is **release-blocking for the first public release**; see US3.

**Input**: Consolidated from `specs/005-hacontrol/spec.md`: secure MQTT connection, Home Assistant discovery, availability, and pause/play control for the running slideshow.

**Amendment 2026-07-21 — frame identity.** Live verification on a physical frame
(iPad Pro 10.5 / iOS 17.7.10) showed the shipped implementation **violates FR-700-06**
("stable, duplicate-free device and entity IDs"). US3 and FR-700-16…22 below make that
requirement precise enough to be testable, and separate *identity* from *name*.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Pause/play from Home Assistant with availability (Priority: P1)

When the slideshow starts and broker configuration exists, the app connects to the MQTT broker over TLS, appears in Home Assistant as a device with a pause/play switch, reports availability, and keeps Home Assistant synchronized with the real slideshow state.

**Why this priority**: This is the smallest complete remote-control slice: secure broker connection, credentials from secure storage, discovery, availability, command handling, and state echo.

**Independent Test**: With a fake MQTT transport and no real broker, start the slideshow and verify discovery and online availability are published; send pause/play commands and verify the slideshow state changes and is echoed; simulate disconnect and verify offline availability through LWT behavior.

**Acceptance Scenarios**:

1. **Given** valid broker details are available from secure storage, **When** the slideshow starts, **Then** the app connects securely, publishes Home Assistant discovery for a pause/play switch, and reports online availability.
2. **Given** the app is connected and the slideshow is running, **When** Home Assistant sends the switch `OFF` (pause) command, **Then** the slideshow pauses and the app echoes the paused (`OFF`) state.
3. **Given** the slideshow is paused, **When** Home Assistant sends the switch `ON` (play) command, **Then** the slideshow resumes and the app echoes the running (`ON`) state.
4. **Given** the user pauses the slideshow locally in the app, **When** the state changes, **Then** Home Assistant reflects the new state and does not drift.
5. **Given** the app is connected, **When** the connection drops unexpectedly, **Then** Home Assistant shows the device offline through the Last Will and Testament.
6. **Given** the app was offline or disconnected, **When** it reconnects, **Then** online availability is published again and the discovery configuration is present.

### User Story 2 - Control brightness and album from Home Assistant (Priority: P2)

Alongside pause/play, the app exposes a dimmable light entity for brightness and a select entity for the active album, so the slideshow's brightness and source album can be driven from Home Assistant and stay in sync with the app.

**Why this priority**: Brightness and album control are the next most useful remote controls after pause/play for an ambient frame; both are already wired through the app's own modules (brightness through PowerManager, album through the slideshow source).

**Independent Test**: With a fake MQTT transport, start the slideshow and verify discovery publishes a light entity (brightness scale 255) and a select entity listing album names; send a brightness command and verify it is clamped, applied through PowerManager, and echoed; send a valid album name and verify the active album switches and is echoed; send an unknown album name and verify state is unchanged and the actual album is echoed.

**Acceptance Scenarios**:

1. **Given** the app is connected, **When** discovery is published, **Then** it includes a dimmable light entity (brightness scale 255) and a select entity whose options are the available album names.
2. **Given** the light entity exists, **When** Home Assistant sends a brightness value, **Then** the value is clamped to range, applied through PowerManager (topic 400), and the resulting brightness is echoed.
3. **Given** the select entity exists, **When** Home Assistant selects a valid album name, **Then** the slideshow switches to that album and echoes the new selection.
4. **Given** the select entity exists, **When** Home Assistant selects an album name that is not an available option, **Then** the active album is left unchanged and the app echoes the actual current album.

### User Story 3 - The frame keeps its Home Assistant identity, and the user names it (Priority: P1)

A frame registers in Home Assistant under an identity that belongs to *the frame*, not to a
platform-supplied value that can be regenerated or withheld. Deleting and reinstalling the app,
or reconfiguring the broker, brings the frame back as **itself** — the same device, the same
entities, the same dashboards and automations. Separately, the user gives the frame a
human-readable name, so several frames are tellable apart in Home Assistant, and renaming one
never disturbs anything bound to it.

**Why this priority**: P1 and release-blocking. This is a defect against the existing FR-700-06,
not a new capability — and the window to fix it for free is closing. Per FR-1100-17 the gated
build is the **first** version the public ever sees, so today no released frame carries an
identity that a fix could orphan. Once that build ships, any later change to the identity scheme
inflicts exactly the failure being fixed — every user's entities orphaned once — on the whole
installed base.

**What was actually observed** (physical frame, 2026-07-21): the identity was
`UIDevice.current.identifierForVendor`. Reinstalling the app regenerated it, so the frame
re-registered as a new Home Assistant device; its previous 19 entities were left permanently
`unavailable` and had to be cleaned up by hand against the broker — something no user can do.
A probe on the same device also confirmed `UIDevice.current.name` returns `"iPad"`, not the
user-assigned device name, because the app does not hold (and cannot casually obtain) the
`com.apple.developer.device-information.user-assigned-device-name` entitlement. Device name is
therefore **not** a usable identity source: it is the same string on every iPad.

**Independent Test**: With an injected identity store, verify the identity is generated once and
returned unchanged across repeated reads and simulated relaunches; verify a store that reports
"nothing persisted" yields a fresh unique value rather than a shared constant; verify a frame
whose stored identity is absent but whose legacy platform identifier is present adopts the
legacy value rather than minting a new one. On hardware, verify across a real delete/reinstall
that Home Assistant shows the same device and entity IDs.

**Acceptance Scenarios**:

1. **Given** a frame registered in Home Assistant, **When** the app is deleted and reinstalled and the broker reconfigured, **Then** the frame re-registers under its previous identity, with no orphaned entities and no duplicate device.
2. **Given** a frame that has never registered, **When** it registers for the first time, **Then** it receives an identity unique to that frame, and no two frames ever share one.
3. **Given** the platform identifier is unavailable (app runs before first unlock after a reboot — the normal case for a frame recovering from a power cut), **When** the frame registers, **Then** it uses its own persisted identity and never a value shared with other installations.
4. **Given** a frame already registered by a build predating this amendment, **When** the user updates to a build implementing it, **Then** the frame keeps the identity it already had and its Home Assistant entities are untouched.
5. **Given** a registered frame, **When** the user changes its name, **Then** Home Assistant shows the new display name while every entity ID, dashboard binding, and automation continues to work unchanged.
6. **Given** an iPad frame and an Apple TV frame on one broker, **When** both register, **Then** they appear as two distinct devices with non-colliding topics and entity IDs (FR-1000-08).

### Edge Cases

- **App deleted and reinstalled**: The frame returns under its previous identity; Home Assistant sees the same device rather than a second one.
- **Platform identifier withheld or regenerated**: Identity does not depend on it. No shared-constant fallback exists, so two frames in this state can never collide.
- **Frame renamed**: Display name changes; identity, entity IDs, and everything bound to them do not.
- **Two frames of the same model with the same name**: Still distinct identities — name is never part of the key.
- **Broker reconfigured or moved to a different broker**: Identity is a property of the frame, not of the broker configuration, so it survives.
- **Broker unreachable or connection fails**: The slideshow continues to run locally; remote control is simply unavailable, with no crash and no blocked image display.
- **Missing or invalid credentials**: If no valid broker configuration exists, no connection is attempted and the app continues locally.
- **Connection drop during operation**: LWT marks the device offline; after reconnect, the app republishes online availability and the current state.
- **App in the background**: Commands requiring foreground-only capabilities are not forced in the background; platform boundaries are respected through the relevant module.
- **Conflicting or rapid commands**: The last valid command wins, and echoed state always reflects the real app state.
- **Duplicate discovery**: Repeated discovery publication does not create duplicate Home Assistant devices or entities because IDs are stable and unique.
- **Secret leak**: Broker username and password never appear in logs, UserDefaults, cache, source code, or committed files.
- **Invalid or unknown command payloads**: Unknown payloads are ignored safely and do not crash the app or create inconsistent state.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-700-01**: The app MUST connect to the configured MQTT broker as a client over TLS, and TLS validation MUST remain enabled.
- **FR-700-02**: Broker credentials MUST come from the Keychain-backed broker configuration only and MUST never be logged, cached, committed, or stored in UserDefaults.
- **FR-700-03**: If broker configuration is missing, invalid, or connection fails, the app MUST keep running locally without crashing or blocking the slideshow.
- **FR-700-04**: On connect, the app MUST publish online availability and register a Last Will and Testament so the broker marks the device offline on unexpected disconnect.
- **FR-700-05**: After disconnect, the app MUST attempt reconnect and, on success, reannounce online availability and current state.
- **FR-700-06**: The app MUST register through Home Assistant MQTT discovery using stable, duplicate-free device and entity IDs.
- **FR-700-07**: The app MUST expose a pause/play switch entity whose availability follows the app's online/offline availability.
- **FR-700-08**: The pause/play switch MUST use Home Assistant switch payloads (`ON` = playing/running, `OFF` = paused); an inbound `OFF` MUST pause the running slideshow and an inbound `ON` MUST resume it.
- **FR-700-09**: The app MUST echo the current pause/play state after remote commands and after local state changes, so Home Assistant mirrors the real app state.
- **FR-700-10**: MQTT transport MUST be behind an injectable protocol so discovery payloads, topics, state, availability, and command handling are testable without a real broker.
- **FR-700-11**: Invalid or unknown command payloads MUST be ignored safely without crashing or changing to an inconsistent state.
- **FR-700-12**: For conflicting or rapid valid commands, the latest valid command MUST determine the result, and echoed state MUST match the actual app state.
- **FR-700-13**: The app MUST expose a dimmable light entity for brightness via discovery (brightness scale 255); an inbound brightness command MUST be clamped to range, applied through PowerManager (topic 400), and the resulting brightness MUST be echoed.
- **FR-700-14**: The app MUST expose a select entity for the active album via discovery, with the available album names as options; a valid selection MUST switch the active album and be echoed, while an unknown album MUST leave state unchanged and echo the actual current album.
- **FR-700-15**: The set of entities enabled in the current app is pause/play, brightness, and album select; sleep/wake remains deferred (see Roadmap).

*(FR-700-16…22, added 2026-07-21, make FR-700-06's "stable, duplicate-free" precise. They
describe required behaviour, not a storage mechanism — the mechanism is a plan decision, subject
to the constitution's rule that nothing secret enters UserDefaults.)*

- **FR-700-16**: Frame identity MUST survive app deletion and reinstall. A reinstalled frame MUST re-register under its previous identity so existing Home Assistant entity IDs, dashboards, and automations keep working.
- **FR-700-17**: Frame identity MUST NOT be derived from any value the platform may regenerate or withhold (notably `identifierForVendor`), nor from any user-visible, user-editable, or non-unique value (notably the device name).
- **FR-700-18**: Frame identity MUST be unique per frame and per platform. There MUST be no shared-constant fallback: when no identity is stored, the app MUST generate a fresh unique value. The iPad and Apple TV frames MUST remain distinct (FR-1000-08).
- **FR-700-19**: Frame identity MUST NOT be synchronised between devices by any channel, so two frames can never come to share one identity.
- **FR-700-20**: Frame identity MUST be opaque and MUST NOT be shown to the user as the frame's name.
- **FR-700-21**: On the first run of a build implementing FR-700-16, a frame that is already registered MUST adopt its current identity rather than minting a new one, so no existing Home Assistant entity is orphaned by the upgrade itself.
- **FR-700-22**: The user MUST be able to set a human-readable frame name that determines the Home Assistant display name. Changing it MUST NOT change frame identity, and MUST NOT orphan, duplicate, or rename any entity ID.

### Key Entities *(include if feature involves data)*

- **Broker Configuration**: Host, port, username, and password supplied by broker setup; credentials originate from the Keychain. It carries the frame identity for convenience but is **not its owner** — identity outlives any broker configuration (FR-700-16).
- **Frame Identity**: The opaque, per-frame, per-platform value that anchors every discovery payload, entity `unique_id`, topic namespace, and availability topic. Generated once, never derived from a platform identifier or a name, never displayed, never synchronised (FR-700-16…21). *(Previously "Device Identity"; renamed to make the split from Frame Name explicit.)*
- **Frame Name**: The human-readable label the user gives a frame, determining only its Home Assistant display name. Free-form, non-unique, changeable at any time, and never part of any key (FR-700-22).
- **Home Assistant Entity**: A remotely controllable capability with discovery configuration, command topic, state topic, and availability binding. In this active spec, the entities are pause/play (switch), brightness (dimmable light), and album select.
- **Remote Control State**: The app state echoed to Home Assistant, including running or paused and online or offline.
- **MQTT Transport**: The injectable protocol boundary for publishing, subscribing, connecting, reconnecting, and LWT behavior.

### Roadmap / Deferred (not yet built)

- Reserved sub-spec `730`: Sleep/wake control through Home Assistant discovery, driven by an inbound presence signal from Home Assistant. Acceptance preserved from the source: discovery publishes sleep/wake control; no-presence or sleep dims to near black; presence or wake restores; schedules and sensors live in Home Assistant, not in the app. Pairs with the topic 400 sleep/wake roadmap item.

*(Brightness and album-select were briefly reserved as `710`/`720` during this spec's initial
design; they shipped inline instead as FR-700-13 / FR-700-14, so those directory numbers were
never used. `710` has since been repurposed for a real sub-spec — see
[`710-ha-full-control`](../710-ha-full-control/spec.md), which covers the rest of `ThemeSettings`,
photo navigation, current-photo image/metadata, and diagnostics.)*

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-700-01**: After slideshow start with valid broker details, Home Assistant can discover the app as a device with a pause/play switch and online availability.
- **SC-700-02**: A "pause" command from Home Assistant pauses the slideshow, a "play" command resumes it, and each echoed state matches the real slideshow state.
- **SC-700-03**: A local pause/play change is reflected in Home Assistant within a short interval and does not permanently drift.
- **SC-700-04**: A simulated or real connection drop causes Home Assistant to show offline, and reconnect returns the device to online.
- **SC-700-05**: Repeated discovery publication produces no duplicate Home Assistant devices or entities.
- **SC-700-06**: With unreachable broker or missing credentials, the slideshow continues locally without crashing or visibly blocking image display.
- **SC-700-07**: Broker username and password appear in no log, UserDefaults entry, cache, source file, or committed file.
- **SC-700-08**: All discovery, topic, availability, state, and command behavior can be tested through the injected MQTT transport without a real broker.
- **SC-700-09**: A brightness command from Home Assistant is clamped, applied through PowerManager, and the resulting brightness is echoed back.
- **SC-700-10**: Selecting a valid album from Home Assistant switches the active album and echoes it; an unknown album leaves the active album unchanged.
- **SC-700-11**: After deleting the app, reinstalling it, and reconfiguring the broker on real hardware, Home Assistant shows the **same** device and the same entity IDs as before — zero orphaned entities, no duplicate device, no `_2`-suffixed entity IDs.
- **SC-700-12**: No two frames ever share a topic namespace or an entity `unique_id`, including when the platform identifier is unavailable to both.
- **SC-700-13**: Renaming a frame changes only its Home Assistant display name: every entity ID, dashboard binding, and automation referencing it keeps working.
- **SC-700-14**: Updating a frame from a build predating FR-700-16 leaves its existing Home Assistant entities in place and unchanged.

## Assumptions

- A reachable MQTT broker with a valid TLS certificate exists when remote control is expected; self-signed and plaintext MQTT are out of scope.
- Broker configuration is supplied by topic 600 through an injectable provisioning interface.
- Home Assistant has MQTT integration and MQTT discovery enabled.
- The concrete MQTT client may come from an SPM library, but Home Assistant logic remains in the app's own testable module behind `MQTTTransport`.
- Remote control is designed for the foreground-running slideshow; platform boundaries for brightness and idle behavior are enforced by their owning modules.
- Frame identity is not a secret; it is protected for *durability*, not confidentiality. FR-700-16 therefore constrains only that it outlive reinstall, and does not by itself require Keychain storage — but the constitution's no-secrets-in-UserDefaults rule still governs whatever the plan picks.
- Home Assistant treats `unique_id` as the anchor and the device/entity name as cosmetic: renaming through discovery updates the friendly name without reassigning `entity_id`. FR-700-22 depends on this behaviour.
- SC-700-11 and SC-700-14 are only meaningful on real hardware (an install/reinstall cycle against a live broker) and are covered by the device rig — see `docs/device-testing.md`.
