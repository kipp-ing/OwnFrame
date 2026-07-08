# Manual Verification — pending hardware/simulator checks

The host test suites cover all the logic offline (see [testing.md](testing.md)). What remains can only be
confirmed against real hardware: a live MQTT broker + Home Assistant (feature 005) and an on-device
UserDefaults/Keychain inspection on the simulator (feature 006).

This file is the checklist for those steps. Tick the matching tasks in the feature `tasks.md` once each
passes. Nothing here runs in CI.

---

## Feature 005 — HAControl (real broker + Home Assistant)

**✅ VERIFIED LIVE 2026-07-08** — `T019` (US1), `T023` (US2), `T027` (US3) all pass against a real
broker (`home.kippings.de:8883`) + real Home Assistant. See the 710 section below for the full
session detail.

### Prerequisites
- A reachable MQTT broker over **TLS** (port 8883) with Home Assistant's MQTT integration connected to it.
- Valid broker credentials saved in the app (use the "Broker einrichten" sheet from the slideshow chrome,
  feature 006 US1) — host, TLS port, username, password.
- App running the slideshow in the foreground.

### Optional: automated TLS transport check first
Before touching Home Assistant, the real `NIOMQTTTransport` can be exercised against a local mosquitto
broker (connect + LWT, retained publish, subscribe round-trip, reconnect after a drop). Trust is anchored
to a local test CA with verification left **on**:

```sh
MQTT_INTEGRATION=1 Packages/HAControlKit/Scripts/mqtt-integration.sh
```

### T019 — US1: Pause/Play + availability
1. Start the slideshow with valid broker credentials present.
2. In Home Assistant a device **"Immich Slideshow"** appears with a Pause/Play switch and an availability
   (online/offline) indicator. *(SC-001)*
3. Toggle the switch in HA → the slideshow pauses / resumes; the HA state mirrors the app. *(SC-002)*
4. Pause/resume **in the app** → the HA switch reflects it. *(SC-003)*
5. Send the app to the background / leave the slideshow → the device goes **"offline"** in HA (LWT);
   return to the foreground → **"online"**. *(SC-004)*
6. Confirm the connection uses the **TLS port only** — no plaintext. *(SC-007)*
7. Sanity: trigger a broker drop/restart → the entity recovers without duplicate devices (stable
   `unique_id`). *(SC-005)*

### T023 — US2: Brightness from HA
1. With `.brightness` enabled, HA shows a **dimmable light** for the device. *(SC-008)*
2. Change brightness from HA → the iPad screen brightness follows, and the applied value is echoed back.
3. Background the app → HA cannot force brightness (foreground-gated); no crash.

### T027 — US3: Album from HA
1. With `.album` enabled, HA shows a **select** whose options are the album list. *(SC-009)*
2. Pick a valid album in HA → the slideshow switches album and echoes the new selection.
3. Pick an unknown/invalid value → no-op; the echoed state stays unchanged.

---

## Feature 006 — Broker setup (simulator persistence + secret boundary)

**Open tasks:** `T014` (US1), `T019` (quickstart SC mapping).

US2 (change / remove) is now covered automatically by
`BrokerSetupUITests.testExistingBrokerPrefillsFieldsMasksPasswordAndRemoves` (prefill, masked password,
remove → dismiss). What's left here is the **real-Keychain** round-trip, which the XCUITests deliberately
skip (they use an in-memory store), plus the quickstart SC walkthrough.

Run on the iPad simulator via XcodeBuildMCP (scheme "Immich Slideshow").

### T014 — US1: persistence + UserDefaults secret boundary
1. Open the slideshow → reveal chrome → **"Broker einrichten"**.
2. Enter valid host / port (default 8883) / username / password and save.
3. Relaunch the app → the saved data is still present (with feature 005 the app now attempts a
   connection). *(SC-001, SC-004)*
4. Inspect the app's `UserDefaults` (keys `mqtt.brokerHost`, `mqtt.brokerPort`) → only **host/port** are
   stored there; **no username/password**. Credentials live in the Keychain only. *(SC-003)*

### T019 — quickstart SC mapping
Confirm SC-001…SC-006 from [specs/006-broker-setup/quickstart.md](../specs/006-broker-setup/quickstart.md)
on the simulator. The host-side criteria are already covered by `BrokerSetupKit` tests; this step is the
simulator-side confirmation (form validation hints, persistence, secret boundary). US2's change/remove UI
(SC-005/SC-006/FR-009) is already covered automatically by `BrokerSetupUITests`.

---

## Topic 710 — HA Full Control (live Home Assistant)

**✅ VERIFIED LIVE across two sessions (2026-07-05 + 2026-07-08).** All 7 checklist items below pass
against a real broker (`home.kippings.de:8883`) + real Home Assistant. Session 1 found and fixed 4
real bugs via TDD (`c179840`); session 2 confirmed the last open item (`next`/`current_photo`, which
turned out to be a false alarm — also pinned by a committed host characterization test) plus image
rendering, offline-on-background, diagnostics-vs-connection-state, reconnect-without-duplicate-device,
and non-retention of the photo topics. This also retires the 700 T019/T023/T027 checks above.

**Merged 2026-07-05 (PR #10).** All host units, XCUITests, and env-gated broker transport tests are
green.

### Prerequisites
Same as topic 700 above (TLS broker + HA MQTT integration + saved credentials + slideshow in the
foreground). Photo image publishing: Settings → MQTT → "Publish photo image to Home Assistant"
(off by default, FR-710-07).

### Checklist
1. **Discovery**: the "Immich Slideshow" device shows all entities from
   [the 710 contract](../specs/710-ha-full-control/contracts/ha-mqtt-entities.md) — the 3 existing
   (playback switch, brightness light, album select) plus order/transition/fit/quality/clock-corner
   selects, duration number, Ken Burns/clock/clock-date switches, next/previous buttons, and the
   current-photo sensor. The image entity appears only while the image toggle is on. *(SC-710-01)*
2. **Settings round-trip**: change each of the 9 settings from HA → the running slideshow applies it
   and HA shows the echoed state exactly once (no echo loops). Change the same settings in the app →
   HA follows. *(SC-710-02/03)*
3. **Validation**: send an out-of-range duration or unknown select option → no-op, state unchanged.
4. **Next/Previous**: button presses advance/rewind the photo. *(SC-710-04)*
5. **Current photo**: the sensor updates per photo with asset ID + metadata attributes; with the
   image toggle on, the image entity shows the downscaled photo. Both topics are **not retained** —
   after the app goes offline, no photo lingers on the broker (check with `mosquitto_sub -v`).
   *(SC-710-05/06, FR-710-13)*
6. **Reconnect republish**: restart the broker (or drop the connection) → after reconnect the full
   state (all settings + current photo) is republished without duplicate devices. *(US4)*
7. **Diagnostics**: the diagnostics surface reflects the connection state per spec 710 US4.

**All 7 passed live (2026-07-08).** Sections ticked above; the README banner's "live Home-Assistant
confirmation is still pending" caveat has been removed.
