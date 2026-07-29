# Manual Verification — pending hardware/simulator checks

The host test suites cover all the logic offline (see [testing.md](testing.md)). What remains can only be
confirmed against real hardware: a live MQTT broker + Home Assistant (feature 005) and an on-device
UserDefaults/Keychain inspection on the simulator (feature 006).

This file is the checklist for those steps. Tick the matching tasks in the feature `tasks.md` once each
passes. Nothing here runs in CI.

---

## FINAL DEVICE DAY — consolidated tick-list (added 2026-07-18, everything merged to main)

Everything below is hardware-gated; all sim/host gates are green (2026-07-25, iPad Pro 11-inch
(M4) sim: PurchaseKit 106 host tests, full iOS suite 163/0/5 — the 5 skips are the
ASC-screenshot, live-smoke and 3 device-rig items; tvOS builds). One device day covers it.
Details live in the linked specs —
this list is the single place to tick.

### A. Ken Burns smoothness redesign (needs only eyes + devices)

The micro-judder fix (scoped-animation drift + decode-ahead, see `specs/1000-apple-tv/tasks.md`
Status): the sim proves the mechanics, your eyes prove the elegance.

- [ ] Old iPad (2017/2018 trio, 60 Hz): Ken Burns on, crossfade, 15 s slides — steady drift reads
      buttery at panel distance; **no stutter at photo swaps** (the decode hitch is fixed).
- [ ] Newer/ProMotion iPad: same check (tick-rate beating was a suspected judder source — gone).
- [ ] Apple TV 4K on a real TV: same check (shared modifier, pan 24).
- [ ] Pause via chrome → photo snaps to the calm full frame instantly (no slow settle);
      resume → arc restarts tight at 1.10 (no zoom-in pop, no slow-motion snap).
- [ ] Change photo duration in settings mid-photo → drift rate retunes without a visible jump.
- [ ] Optional numbers: Instruments → **Animation Hitches** during steady drift + across ~10 swaps;
      expect no app-attributable hitches. (Objective sim recipe: memory
      `verify-animations-by-video-luminance` — dot-sawtooth + frame-gap traces.)

### B. 1000 Apple TV hardware gates (real ATV + iCloud account + broker)

- [ ] Add **iCloud entitlements** to both targets AND flip the `SecretSyncStoreFactory` capability
      flag **in the same change** (a unit test asserts it OFF until entitlements exist —
      CKContainer.default() would crash signed-in devices otherwise).
- [ ] **SC-1000-08** CloudKit secret proof: API key published encrypted from the iPad → decrypted on
      the real Apple TV; audit that secrets appear ONLY in CloudKit encrypted fields.
- [ ] KVS non-secret sync on hardware: iPad companion publish → TV restores theme/broker config
      (under 2 min to playing, zero secrets typed on the TV — SC-1000-01 path).
- [ ] Real MQTT broker (`home.kippings.de:8883`): TV appears as its own HA device
      **"OwnFrame (Apple TV)"**; **SC-1000-06** pause/play, source select, dim from HA while the
      iPad frame runs simultaneously — no cross-talk. Include the B8/B9 broker orderings from the
      1000 test review.
- [ ] **SC-1000-02** Siri-Remote-only walkthrough: every function reachable with the remote alone
      (App Review requirement).
- [ ] **SC-1000-05** 24 h soak on the real TV: no screensaver, no suspension while frontmost,
      HA availability truthful, no static UI element ever on screen (burn-in review; Ken Burns +
      pixel-shift are the mitigation — note the tvOS clock overlay + FR-1000-10 pixel-shift are
      still unimplemented, clock stays off).
- [ ] tvOS **device build** signing: fix provisioning (`No profiles for ing.kipp...`) before any of
      the above.

### C. Shared device-day gates from the merged 900/800/220 (already ticked per-spec once done)

- [ ] **SC-220-07**: scan a shared-link QR with the real camera → onboarding completes
      (`specs/220-onboarding-welcome/tasks.md`).
- [ ] **SC-120-05** *(added 2026-07-19)*: with a library already set up, add a second shared album
      by scanning its QR from **Settings → Sources → + → Shared link** — no typing — and confirm it
      is saved under the name typed in the form beforehand. Same camera hardware as SC-220-07, so
      do both in one pass; also check the camera-denied path still leaves manual entry usable
      (`specs/120-source-library/tasks.md` Phase 8).
- [ ] **800 T029**: Siri phrase checklist on device (`specs/800-app-intents/tasks.md`).
- [ ] **800 + 300 (German Siri)**: on a device set to German, confirm Siri recognises the
      localized spoken phrases (`OwnFrame/AppShortcuts.xcstrings` — e.g. "Pausiere OwnFrame",
      "Nächstes Foto auf OwnFrame") and that **Get Frame State** reads the play state back in
      German ("Läuft"/"Pausiert"). Tip: create a fresh shortcut per check — Siri caches the old
      phrasing. Phrase text only ships in the catalog; recognition itself is device-only.
- [ ] **900 quickstart** device/beta gates: real Photos library end-to-end + the iOS 27 beta
      shared-album rebuild check (`specs/900-photo-library-source/quickstart.md`).

### D. 1100 purchase gate — App Store Connect + sandbox (added 2026-07-19)

Mirrors `specs/1100-purchase-gate/quickstart.md` §5; keep the two in step. Needs a sandbox tester
account, a second device, a family member account, and ASC access. **Nothing here is automatable**
— StoreKit sandbox, Family Sharing, and release sequencing all require a real Apple ID.

**Do this one FIRST — it is release-blocking and cheap to check:**

- [x] **FR-1100-17 / SC-1100-09 sequencing** — **audited via the ASC API 2026-07-29, and the
      mechanism is not what this file assumed.** v1.0 build 8 is **not** in an unreleased state:
      the version reads `READY_FOR_SALE` / `READY_FOR_DISTRIBUTION`, its review completed
      **2026-07-14**, and `releaseType` is `AFTER_APPROVAL`. What actually keeps it off the store
      is **app availability**: all **175 territories** are `available: false`, effective
      **2026-07-22**. So FR-1100-17 is held by a switch, not by a state — and flipping
      availability on before 1.1 ships would publish the ungated build instantly.
      **Update 2026-07-29 (Jan) — both sub-items resolved or improved:**
      - **Zero downloads** in the 07-15 → 07-22 window (App Analytics). The ungated build reached
        nobody, so "Initial release." is honest and **never-claw-back (FR-1100-13) binds to no
        existing user**. The upgrade-path checks below concern only Jan's own frames.
      - `releaseType` was changed **`AFTER_APPROVAL` → `MANUAL`**, so FR-1100-17 is now held by
        **two independent locks**, not one: approval cannot auto-publish, *and* all 175
        territories remain `available: false`. Release order is therefore: approved → click
        *Release this version* → then availability on.
- [ ] **EU trader status — IN PROGRESS with Apple as of 2026-07-29; release-blocking for 27
      territories.** The territory availability records for the EU carry `contentStatuses:
      [TRADER_STATUS_NOT_PROVIDED, CANNOT_SELL]` (27 of 175; the other 148 carry `CANNOT_SELL`
      only, i.e. Jan's own switch). Without trader status the app **cannot be sold in the EU at
      all** — including Germany, the home market the whole de-DE listing was written for. Not
      exposed in the ASC API: set it in the ASC web UI under Business → Trader Status, and expect
      **multi-day verification**. If it has not cleared at release time, ship the non-EU
      territories and add the EU 27 afterwards rather than holding the whole release.

**Store setup — done 2026-07-29 via the ASC API; all four products are `READY_TO_SUBMIT`:**

- [x] IAPs created. **The ids in this repo changed to do it**: ASC rejects a product id containing
      anything but alphanumerics, underscores and periods, so every `ing.kipp.Immich-Slideshow.*`
      id 409'd on the bundle id's hyphen. They are now `ing.kipp.ownframe.*`
      (`ProductCatalog.swift` remains the source of truth, and a test now pins the character set,
      not just the literals). The hyphenated ids never existed in ASC — nothing was migrated.
- [x] Family Sharing **ON** for the Supporter Unlock, OFF for the tips.
- [x] Localized names/descriptions (en-US + de-DE) — one-time framing, no "lifetime", nothing
      implying a subscription (FR-1100-05).
- [x] Prices set in ASC only, never in this repo. The `.storekit` file's values remain placeholder
      fixtures.
- [x] Review screenshots attached (unlock screen for the unlock, tip jar for the three tips),
      captured in English off the hermetic sweep via `SCREENSHOT_LOCALE=en`. Note the tip jar
      shot shows the stub store's placeholder `$1.00` on all three rows, not the real ASC prices —
      harmless for a review screenshot, but re-shoot if a reviewer ever queries it.
- [x] IAP availability set in all 175 territories (they sell wherever the app sells).
- [x] **Build 9 attached to the 1.1 version record** (verified via the ASC API 2026-07-29).
- [ ] **IAPs attached to the 1.1 review submission — STILL OPEN, and the highest-consequence
      item left.** Verified 2026-07-29: all four are `READY_TO_SUBMIT`, but that means *eligible*,
      not *attached*, and **no review submission exists for 1.1 yet** (the only ones on record are
      the COMPLETE v1.0 submissions of 07-12 and 07-14). First-time IAPs are reviewed **only** as
      items in the same review submission as the build. Submitting the version alone leaves them
      unreviewed and ships a purchase-gated app with **no purchasable products** — the Supporter
      Unlock unbuyable for everyone. Add them to the version *before* "Add for Review", then
      confirm the submission lists **five items**: build 9 + the four `ing.kipp.ownframe.*`
      products. Note ASC may also object that no territory is selected — that is the FR-1100-17
      guard, not a metadata fault.

**Sandbox on device:**

- [x] ~~Run `StoreKitClientTests` from the Xcode IDE or on device.~~ **Done 2026-07-21 — no
      longer a device-day item.** The suite never needed the IDE: it skip-guarded itself because
      of two setup bugs in the test (`configurationFileNamed:` resolving against the host app's
      `Bundle.main`, and `disableDialogs` being set before `resetToDefaultState()` cleared it).
      Both fixed; see `docs/testing.md` § "`SKTestSession` serves 0 products". The 7 cases —
      purchase→owned, restore, refund→relock, Ask-to-Buy defer→approve, interrupted purchase owned
      next launch, tips never owned — now execute under plain headless `xcodebuild`, and were
      verified 7/7 on the iOS 18.6 sim, Framepad (17.7.10) and FramePhone (26.0.1). This is the
      runtime proof of the StoreKit adapter (T030); it runs in CI now, not on device day.
- [ ] Products load at all (the id-drift smoke test — if this fails, re-check the ids above).
- [ ] Buy the Supporter Unlock for real; the gated features activate without a relaunch (SC-1100-03).
- [ ] Buy a tip → thank-you state, and **no entitlement change whatsoever** (FR-1100-08).
- [ ] Cancel mid-flow → back to the offer, no charge, no nagging follow-up prompt.
- [ ] Ask-to-Buy with a child test account → pending state; approve later → the entitlement
      arrives over the updates stream without the app being reopened (FR-1100-15).
- [ ] Refund/revoke via ASC or a StoreKitTest session → relocks on the next refresh, and the
      user's stored settings are still intact afterwards (FR-1100-12 + FR-1100-14).
- [ ] **Relock is boundary-aligned, not instant**: with Ken Burns running, trigger the relock and
      watch a photo already on screen — its pan must finish naturally; the gate applies at the
      next photo advance. A pan freezing mid-photo is the bug this checks for (FR-1100-12).

**Household (SC-1100-05 / SC-1100-08 / US4):**

- [ ] Restore on a second device with the same sandbox account repopulates the unlocks.
- [ ] A second Family Sharing member gets the unlocks free, without paying again.
- [ ] Apple TV: universal purchase already active from the iPad purchase, plus native
      purchase/restore **on the TV itself**.

**Unattended-frame behaviour — the reason this feature is cache-first:**

- [ ] **24 h offline entitlement soak** (SC-1100-04): buy, then take the frame fully offline and
      leave it a day. Owned features must still be active at every relaunch. Piggyback the
      existing 1000-series soak.
- [ ] **≥ 4 h free-tier wall-clock playback with zero purchase UI** (SC-1100-02). The XCUITest
      window is ~12 s and is only a hermetic proxy — this is the actual criterion.
- [ ] Airplane mode from a cold boot, already entitled → features active at first render, no
      loading state, no network wait (FR-1100-10).

**Pre-gate upgrade path (SC-1100-06) — Jan's own long-running frames:**

- [ ] On a frame with a broker configured **before** this update: install the gated build and
      confirm the stored config survives byte-for-byte and nothing is cleared or migrated.
- [ ] **Free telemetry (amended 2026-07-20, FR-1100-03a):** confirm at the broker (`mosquitto_sub
      -v`) that an unentitled frame **connects and publishes read-only sensors only** — availability
      + `current_photo`/`phase`/`photo_count`/`version` — so the device appears in HA, but there are
      **zero controllable entities** (no light/select/switch/number/button), **zero command-topic
      subscriptions**, and it acts on **zero** HA commands (SC-1100-06).
- [ ] **Retained-discovery retraction (T056)** — the check that only a frame *upgrading from the
      pre-gate build* can fail, so run it on a frame whose broker already carries the old retained
      configs (Jan's own): after the gated build connects unentitled, the controllable entities must
      **disappear from HA**, not merely go stale. Confirm `light.`/`select.`/`switch.`/`number.`/
      `button.` frame entities are gone while the sensors remain.

      **Premise and mechanism are already verified live (2026-07-21) — only the app-side run is
      left.** Against the real broker: all **19** discovery configs are present with `retain=1`
      (14 controllable), so skipping the publish provably cannot remove them. And on this exact
      Home Assistant, a retained config published under a throwaway device id created a live,
      interactive `switch.` entity, and an **empty retained payload on the same topic removed it**
      (test residue cleaned; the real frame's 19 configs/entities untouched). So what remains is
      narrow: install the gated build on a *configured* frame and confirm the app emits those
      empty retained payloads on connect. Framepad could not do it in that session — its app was
      already unconfigured, see the note at the end of this section.
- [ ] Buy the Supporter Unlock → the controllable entities appear and HA control resumes using the
      previously stored settings with **zero re-entry** (FR-1100-14).

> **Frame state note (2026-07-21).** Framepad (iPad Pro 10.5, iOS 17.7.10 — the deployment floor)
> currently carries a **dev-signed Debug build** and its app is **unconfigured**: no source, no
> broker, which is why its HA entities have been `unavailable` since 07-20 07:05. Reconfigure it
> (and reinstall the App Store build when done) before running the two checks above — both need a
> frame that actually connects.

**Listing:**

- [x] License line is FSL-1.1-MIT (verified 2026-07-19: README §License and
      app-store-listing.md already say "Fair Source, becomes MIT after two years"; no stale
      "Open source (MIT)" claim remains). The ASC listing copy still needs the same wording at
      submission.

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
2. In Home Assistant a device **"OwnFrame"** appears with a Pause/Play switch and an availability
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

Run on the iPad simulator via XcodeBuildMCP (scheme "OwnFrame").

### T014 — US1: persistence + UserDefaults secret boundary
1. Open the slideshow → reveal chrome → **"Broker einrichten"**.
2. Enter valid host / port (default 8883) / username / password and save.
3. Relaunch the app → the saved data is still present (with feature 005 the app now attempts a
   connection). *(SC-001, SC-004)*
4. Inspect the app's `UserDefaults` (keys `mqtt.brokerHost`, `mqtt.brokerPort`) → only **host/port** are
   stored there; **no username/password**. Credentials live in the Keychain only. *(SC-003)*

### T019 — quickstart SC mapping
Confirm SC-600-01…SC-600-06 from [specs/600-broker-setup/spec.md](../specs/600-broker-setup/spec.md)
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
1. **Discovery**: the "OwnFrame" device shows all entities from
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
