# Feature Specification: Home Assistant Control (MQTT)

**Feature Branch**: `700-ha-control`

**Created**: 2026-06-23

**Status**: Active

**Input**: Consolidated from `specs/005-hacontrol/spec.md`: secure MQTT connection, Home Assistant discovery, availability, and pause/play control for the running slideshow.

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

### Edge Cases

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

### Key Entities *(include if feature involves data)*

- **Broker Configuration**: Host, port, username, password, and stable device ID supplied by broker setup; credentials originate from the Keychain.
- **Device Identity**: Stable unique identity for the iPad in Home Assistant, used by all discovery payloads, entities, and availability topics.
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

## Assumptions

- A reachable MQTT broker with a valid TLS certificate exists when remote control is expected; self-signed and plaintext MQTT are out of scope.
- Broker configuration is supplied by topic 600 through an injectable provisioning interface.
- Home Assistant has MQTT integration and MQTT discovery enabled.
- The concrete MQTT client may come from an SPM library, but Home Assistant logic remains in the app's own testable module behind `MQTTTransport`.
- Remote control is designed for the foreground-running slideshow; platform boundaries for brightness and idle behavior are enforced by their owning modules.
