# Device Testing — real hardware ("Framepad")

Layer 4 of the pyramid in [testing.md](testing.md): the checks that a simulator
**cannot** perform. Everything here is about driving a physical iPad from the CLI.

Use `.claude/scripts/framepad.sh` rather than typing these commands by hand — every
trap below is already encoded in it.

## The device

**Framepad** — iPad Pro 10.5-inch (A1701, iPad7,3), **iOS 17.7.11** (factory-restored and
re-commissioned 2026-09-25; it was 17.7.10 before). This is the app's
exact deployment floor, which makes it the most valuable device available: anything that
works here works on everything newer.

```bash
xcrun devicectl list devices     # UDID 12865abf7eec21ea87485b4b2e84a4811453cb1a
```

Developer mode is enabled and signing works out of the box (Apple Development,
mobil@kippings.de). Installing a dev build over the existing one **preserves the data
container**.

### The other paired devices

| Name | Model | OS | Role |
|---|---|---|---|
| **Framepad** | iPad Pro 10.5 (iPad7,3) | 17.7.11 | the deployment floor; **caps at iOS 17 forever** |
| **FramePhone** | iPhone 13 mini (iPhone14,4) | **27.0** | the iOS 27 beta device (see below) |
| iPad jk | iPad Pro 11-inch (M4) | 26.6.1 | modern iPad, real hardware |
| jk in da house | iPhone 16 Pro | 26.6.1 | modern iPhone, real hardware |

Framepad can never run iOS 27, so **the frame Jan actually runs is unaffected by the iOS 27
release.** iOS 27 is a *customer* risk (users on modern iPads auto-update), not a rig risk.

## FramePhone — the iOS 27 device

```bash
xcrun devicectl list devices     # UDID 00008110-000568303444801E
```

`framepad.sh` drives it unchanged via `FRAMEPAD_DEVICE_ID=00008110-000568303444801E`.

**Xcode 26.6 (SDK 26.5) drives an iOS 27 device without the Xcode 27 beta.** Build, install,
`devicectl process launch --console`, and full XCUITest all work. Expect two harmless log lines
— `DVTDevice: Error locating DeviceSupport directory … nilError` and
`IDELaunchParametersSnapshot: no debugger version`. **LLDB attach does not work** (no iOS 27
DeviceSupport); interactive debugging needs the Xcode 27 beta, test runs do not.

**Trap — `TEST_RUNNER_` prefix.** On a device, env vars only reach the test runner when
prefixed. `SCREENSHOT_CAPTURE=1 xcodebuild …` silently *skips* the test;
`TEST_RUNNER_SCREENSHOT_CAPTURE=1` runs it. Same for `SCREENSHOT_DE`, `LIVE_SMOKE`,
`DEVICE_RIG`.

Current iOS 27 status and the controls that closed the simulator-vs-hardware confound live in
[testing.md](testing.md#ios-27-on-real-hardware-session-2026-07-27) and issue #50. Short version:
iOS 27 was the variable, the six red UI tests were harness/synthesis artifacts, and all six run
green on FramePhone since 2026-07-28.

## Prerequisites (one-time, physical)

Two device settings must be on, and **neither can be set from the CLI**:

1. **Settings → Developer → UI AUTOMATION → Enable UI Automation.** Without it *no* test
   bundle runs. UI tests fail `Timed out while enabling automation mode`; app-hosted unit
   tests fail `The test runner hung before establishing connection`. Note this is a
   *separate* switch from Developer Mode, which reports `enabled` regardless.
2. **Settings → Display & Brightness → Auto-Lock → Never.** A locked device parks a run at
   `Run Destination Preflight … "Unlock Framepad to Continue"` — it *waits* rather than
   failing, so a run can hang indefinitely mid-suite.

### Commissioning a restored device (2026-09-25, Framepad after a factory restore)

The UDID survives a restore; the pairing does not. Finder showing the device as connected
means nothing for Xcode, which uses a separate CoreDevice pairing:

1. `xcrun devicectl manage pair --device <udid>` and tap **Trust** on the device. Until this
   runs, `devicectl` lists it `available` without `(paired)`, Xcode ignores it, and
   **Privacy & Security → Developer Mode is not offered at all**.
2. Turn on Developer Mode (the device restarts; confirm with "Turn On").
3. `xcrun devicectl device info ddiServices --device <udid>` mounts the developer disk
   image. Only after that does **Settings → Developer** (holding the UI Automation switch)
   appear on iOS 17. `devicectl` then reports `connected`.
4. Enable UI Automation and set Auto-Lock → Never (above). The device name `devicectl` shows
   can lag behind a rename in Settings until the next reconnect.

## Build/run traps

Each of these cost a real debugging cycle at least once.

- **Xcode 27 cannot run device tests on iOS 17 (issue #84).** Its developer-disk-image
  `testmanagerd` crashes on an actor-isolation assertion in `_IDE_deleteAttachments`
  whenever Xcode deletes a passed or skipped test's attachments. The runner restarts after
  every other test, and you get ~17 fake red tests plus `Lost connection to testmanagerd`.
  Crash reports: `xcrun devicectl device info files --device <udid> --domain-type
  systemCrashLogs | grep testmanagerd`. **No workaround works** (all tried 2026-09-25):
  Xcode 26.6 side by side mounts the same system-wide DDI (`/Library/Developer/
  DeveloperDiskImages`, owned by the newest Xcode); one test per launch still crashes when the
  launch ends and hangs the next one; `keepAlways` attachment lifetimes don't stop it either.
  Only the first test after the daemon (re)starts is trustworthy, so single-test rig runs
  (`framepad.sh rig/gates/diag`) work and a full suite doesn't. The iOS 17 gate leg is the 17.5
  simulator plus hand checks until Apple fixes it. iOS 26.6 devices are unaffected.
- **`framepad.sh` said "not connected" for a connected device** (fixed 2026-09-25):
  `devicectl … | grep -q` under `set -o pipefail` fails the pipeline through the SIGPIPE,
  because `grep -q` exits on the first match. Capture the output first, then grep.

- **`-allowProvisioningUpdates` is required.** The UI-test runner needs its own profile
  (`ing.kipp.Immich-SlideshowUITests.xctrunner`) and automatic signing is off. Without the
  flag: `No profiles for '…xctrunner' were found`.
- **`-derivedDataPath` must not be under `/private/tmp`** (i.e. never the agent scratchpad).
  CoreDevice fails with `unable to create bookmark data … denied by this process' sandbox`.
  Use `~/Library/Developer/Xcode/DerivedData/…`. Same family as the App Store export trap
  in [handover-release-prep.md](handover-release-prep.md).
- **Never pipe `xcodebuild` into `tail`/`head`.** The pipeline's exit code becomes the
  *filter's*, so a failed build reports `exit 0`. Redirect to a log and check `$?`.
- **Expect slowness.** A 2017 iPad is not a simulator; simulator-calibrated timeouts
  produce flakes that look like product bugs. The rig uses 90 s waits.
- **Source-tree guard tests are simulator-only.** `AppearanceRootTests`,
  `AccentFilledControlGuardTests`, `DeviceNeutralCopyTests` and `NewPhotosCardCopyTests` read the
  repo via `#filePath`, which a device cannot reach (`NSCocoaErrorDomain 260`). Since WP5
  (2026-09-15) they are compile-time disabled off the simulator, so on a device they show as
  skipped, not failed. A new test that reads the repo needs the same gate.
- **An OS update can switch UI Automation off.** FramePhone's move to 27.0 did: the full suite then
  ran the app-hosted tests and failed `OwnFrameUITests-Runner … Timed out while enabling automation
  mode` with **zero** UI tests executed. Re-check the switch after every device OS update.
- **A device OS update can break Xcode's pairing while Finder still trusts the device.** Framepad
  came back from 17.7.11 in `xctrace list devices` under `Devices Offline`, `devicectl` showed
  `Pairing State: unsupported` and only a `RestorableDeviceRefDeviceRepresentation`, yet Finder
  listed it as trusted (Finder uses the old lockdown trust; Xcode uses CoreDevice remote pairing).
  The Mac-side log (`/usr/bin/log show --predicate 'process == "remotepairingd"'`) shows
  `CSSMERR_CSP_INVALID_KEY` in `SecKeyCreateSignature` on every attach, then `awaitingUserConsent`
  and `failure … Code=89 "Operation canceled"` ~0.9 s later — the Trust prompt flashes for half a
  second and **the Mac** withdraws it. Tapping Trust cannot win that race. Not fixed by: re-plugging,
  restarting the Mac, clearing the iPad's Settings → Developer → Clear Trusted Computers, or
  `devicectl manage unpair`/`manage pair --device <udid>` (error 1000 "not found" — this subcommand
  pair doesn't even reach devices in this broken state, unlike the automatic background attempt).
  Xcode 27's device window (renamed from "Devices and Simulators"; no "Unpair Device" entry
  surfaced for Framepad at all) didn't help either. **What actually worked (2026-09-15):** run
  `xcrun devicectl manage pair --device <udid>` **repeatedly back-to-back** (a `for` loop, ~1 attempt/
  sec) while watching the iPad for the Trust flash — most attempts still hit the same
  `CSSMERR_CSP_INVALID_KEY`/cancel race, but one attempt in the burst got through to `available
  (paired)` → `connected (no DDI)` → `connected`. Unclear why that one attempt didn't race-cancel;
  worth trying the burst-loop first before escalating next time. Pairing records live in the
  SIP-protected `/var/db/lockdown/RemotePairing`, not in the login Keychain.

## Reading the device's logs — this DOES work

Earlier notes claimed app logs could not be read off this device. **That is wrong**, and
this is the single most useful capability here:

```bash
xcrun devicectl device process launch \
  --device <id> --console --terminate-existing \
  --environment-variables '{"OS_ACTIVITY_DT_MODE":"enable"}' \
  ing.kipp.Immich-Slideshow [--app-args...]
```

`OS_ACTIVITY_DT_MODE=enable` routes `os.Logger` output to stderr, which `--console`
captures — full `[HAControl] announce: published … [full]` lines and everything else the
app logs.

- **`--terminate-existing` is mandatory.** Launching against an already-running app merely
  re-activates it, so new launch arguments are **silently ignored**.
- Arguments after the bundle id are passed to the app, so DEBUG seams
  (`--uitest-entitlements=all`) can be driven this way.
- `xcrun devicectl device info apps` fails on this device (`CoreDevice.ActionError error 3`).
- `log stream --device-name` does not work — this macOS `log` binary has no `--device*`
  options despite its man page. Also, `log` is shadowed by a zsh function; use `/usr/bin/log`.

## Seeing the screen

There is **no** `devicectl` screenshot and no MCP device UI automation. XCUITest is the only
eye *and* the only hand. Screenshots come out of the result bundle:

```bash
xcrun xcresulttool export attachments --path <bundle>.xcresult --output-path <dir>
# then read <dir>/manifest.json to map suggestedHumanReadableName → exportedFileName
```

The rig attaches a screenshot per step with `lifetime = .keepAlways`, so failures are
diagnosable after the fact. The result bundle also contains an **App UI hierarchy** `.txt`
dump — grep it for `label:` to see exactly what was on screen when an assertion failed.
That is how `Server not reachable.` was found without any logs.

## The device rig

`OwnFrameUITests/DeviceRigConfigUITests.swift`. Unlike every other test in that
target it launches with **no launch arguments**, i.e. the real production path: real
network, real Keychain, real broker, real StoreKit. Opt-in only:

```bash
.claude/scripts/framepad.sh rig            # configure source + broker
.claude/scripts/framepad.sh gates          # T056 telemetry/full round trip
```

Environment (forwarded by `xcodebuild` with the prefix stripped):

- `TEST_RUNNER_DEVICE_RIG=1` — required, else every rig test skips. Keeps a normal suite
  run from ever touching the live broker.
- `TEST_RUNNER_MQTT_PASSWORD=…` — the broker password is **never** hard-coded (Konstitution III).
  `framepad.sh` takes it from `MQTT_PASSWORD`, or else from the login Keychain item `ownframe-mqtt`
  (account `car`, stored by Jan 2026-09-14), so it never passes through a chat.

### Why the rig can't use `--uitest`

The hermetic branch wires `makeCoordinator: { _ in nil }` — under `--uitest` there is **no
MQTT broker in the process at all**. So the hermetic suite is structurally incapable of
exercising the HA contract; that is exactly what hardware is for.

## MQTT / Home Assistant on device

- **MQTT is foreground-only**, the same class of constraint as `isIdleTimerDisabled` and
  `UIScreen.brightness` (see CLAUDE.md "Constraints"). A `devicectl process launch` against
  a sleeping screen never foregrounds the app, so it never connects and publishes nothing.
  Hold the app foreground under XCUITest (`testHoldForegroundSoCoordinatorAnnounces`) or
  wake the device.
- **The device identity is not stable.** `HAControlCoordinator.ensureDeviceID()` reads
  `deviceID` from the **broker config**, so configuring a broker from scratch mints a brand
  new HA identity. Symptom: the retraction fires correctly against the *new* id while the
  broker still shows the old id's configs untouched — which reads as "nothing happened".
  **Always take the device id from the `start: connecting (device=…)` log line before
  verifying anything.** Consequence for users: reconfiguring a broker orphans the previous
  entities (they stay `unavailable` forever) and breaks dashboards bound to the old
  `entity_id`s.
- Verify against Home Assistant, not just the broker — HA is the actual contract:

  ```bash
  .claude/scripts/framepad.sh ha-check <device-id>
  hactl --dir /Users/jan/dev/repos/hactl-dev/jansHA ent ls --pattern '*photo_frame*'
  ```

  **The `*photo_frame*` pattern is right for the existing rig and wrong for a new one.** HA
  freezes an `entity_id` at first discovery, so the Framepad's entities keep the
  `photo_frame_slideshow_*` slugs minted under the pre-OwnFrame device name; renaming the frame
  changes only the display name (FR-700-22), and the identity survives delete+reinstall (#15),
  so those slugs will not change on their own. A **freshly configured** frame registers under
  today's default name `OwnFrame` (`OwnFrame (Apple TV)` on tvOS) and slugs to `*ownframe*` —
  match on that instead. Broker-side topic greps are unaffected by either: the root is
  `ownframe/<device-id>` for every frame since the `immichslideshow/` → `ownframe/` rename
  (2026-07-22).

  `hactl` needs no MQTT credentials. Broker: `home.kippings.de:8883`, user `car`,
  `--cafile /etc/ssl/cert.pem` (publicly-trusted ZeroSSL chain, no TLS exception). A lone
  `Connection Refused: not authorised` is **transient — retry** before concluding the
  credentials are stale.
- **Retained MQTT state is a persistence channel independent of UserDefaults** and survives
  delete+reinstall. It also carries values the app UI may not be able to represent (HA's
  duration entity is min 3 / max 600 / step 1 versus six UI presets) — any HA-settable
  setting must render off-menu values.

## What only hardware can prove

Keep this list honest — it decides what needs a scarce device day versus what can be
automated (compare `docs/manual-verification.md`).

**Irreducibly hardware:** real MQTT/TLS against the live broker, real CloudKit/KVS sync,
24 h soak/burn-in, real-panel Ken Burns smoothness, camera (QR scan), Siri phrases,
real Photos library.

**Needs an account, not hardware:** StoreKit sandbox purchase/restore/Family Sharing — i.e.
buying against the *real* sandbox store. This does not include `SKTestSession`.

> **Corrected 2026-07-21.** This section used to say `SKTestSession` fails on Framepad with
> `ASDErrorDomain 509 "No active account"`, so the device was "not a substitute for the Xcode
> IDE runner". Both halves were wrong. The 509 was a *symptom*: the session was being created
> from a config the initializer never found (it resolves against the host app's `Bundle.main`),
> so with no test store active StoreKit fell through to the **real** store — which of course
> has no account. With the fixture actually loaded, `SKTestSession` needs no App Store account
> at all and the seven cases pass 7/7 on Framepad (17.7.10) and FramePhone (26.0.1) — and
> headlessly on the simulator, so they no longer need a device *or* the IDE. Details in
> `docs/testing.md` § "`SKTestSession` serves 0 products".

**Only blocked by missing infrastructure (build it, don't schedule a device day):** the
tvOS gates — `OwnFrameTV.xcscheme` has an empty `<Testables>` and the TV app has no
hermetic `--uitest` seam. `XCUIRemote.shared.press(…)` runs fine in the tvOS Simulator; it
is `simctl` that cannot send Siri-Remote events, not XCUITest.

> **Deferred as of 2026-07-21** (CLAUDE.md § Testing Target): tvOS is out of scope until the iOS
> side is ready, so none of the above is scheduled. The diagnosis stands for when it returns — it
> is buildable work, not device work, and doing it shrinks the device day rather than consuming
> it. Framepad (iOS) is the only hardware target for now.
