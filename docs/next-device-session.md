# Next Device Session — plan

> **Scope policy (2026-07-21, until further notice): iOS first, Framepad is the target, tvOS is
> deferred.** See CLAUDE.md § Testing Target. Nothing in this plan should block on tvOS or on
> owning a second device; where a check needs either, it is listed under *Deferred* at the bottom
> rather than scheduled.

**Precondition that defines this session: an Apple ID signed in to the App Store on the test
device.** That single change unblocks everything below that today cannot run at all. Sign in
*before* starting; it is the one thing that cannot be done from the CLI.

Read [device-testing.md](device-testing.md) first for the rig, the recipes, and the traps.
Drive everything through `.claude/scripts/framepad.sh`.

## Pre-flight (5 min, do these first)

Two device settings, neither settable from the CLI, both of which have already cost a session:

- [ ] **Settings → Developer → Enable UI Automation** — without it *no* test bundle runs.
- [ ] **Settings → Display & Brightness → Auto-Lock → Never** — a locked device parks a run at
      destination preflight and waits indefinitely rather than failing.
- [ ] **App Store: signed in** (Settings → App Store). Sandbox tester account if testing IAP.
- [ ] `xcrun devicectl list devices` shows Framepad `connected`.
- [ ] `.claude/scripts/framepad.sh build` succeeds.

## Priority 1 — the account-gated work (the reason for this session)

### 1a. ~~StoreKitTest, the seven skipped cases (issue #16)~~ — DONE 2026-07-21

**Resolved; needs no device time.** The cases never needed an account, a device, or the Xcode
IDE — they were defeated by two setup bugs in the test itself (see `docs/testing.md`
§ "`SKTestSession` serves 0 products"). Both the "0 products under headless `xcodebuild`" and
the `ASDErrorDomain 509 "No active account"` observations were symptoms of the same root cause:
the config file was never found, so StoreKit fell through to the real store.

Fixed and verified 7/7 on the iOS 18.6 simulator, Framepad (17.7.10) and FramePhone (26.0.1).
The skip-guard is now a hard assertion, so a regression fails loudly. Issue #16 closed.

They run anywhere, including CI:

```bash
xcodebuild -project "OwnFrame.xcodeproj" -scheme "OwnFrame" \
  -destination "id=$FRAMEPAD_DEVICE_ID" -configuration Debug \
  -derivedDataPath ~/Library/Developer/Xcode/DerivedData/FramepadRig \
  -allowProvisioningUpdates -test-timeouts-enabled YES \
  -only-testing:"OwnFrameTests/StoreKitClientTests" \
  test-without-building
```

The remaining T042 work is ASC-gated only (1b below).

### 1b. Sandbox purchase flows (T042)

Needs IAPs created in App Store Connect first — blocked on Jan's ASC access, so confirm that is
done before planning this leg.

- [ ] Purchase Pro; verify the Ken Burns + clock gates unlock at the point of effect.
- [ ] Purchase Automation; verify HA control entities appear (telemetry → full).
- [ ] Restore on a second install; verify entitlements return.
- [ ] Family Sharing; universal purchase (iOS purchase unlocks tvOS).
- [ ] **Never-claw-back (FR-1100-13)**: with the frame offline for a long period, entitlements
      must persist. Airplane-mode the device, relaunch, confirm paid features still render.

## Priority 2 — confirm the frame-identity fix in the wild (#15)

Already verified once on hardware (SC-700-11/14). Re-run after any identity-adjacent change,
and cover the cases the first pass could not:

- [ ] **Reinstall keeps identity** — `framepad.sh` uninstall/install/rig, then confirm the
      `start: connecting (device=…)` log line is unchanged and HA shows no `_2` duplicates.
- [ ] **Rename is safe (FR-700-22)** — change the frame name in Settings, confirm HA shows the
      new display name while every `entity_id` and binding still works.

*(SC-700-12 "two frames never collide" and the tvOS identity path both need hardware this policy
defers — see Deferred below. The resolver logic behind both is covered by host tests.)*

## Priority 3 — FINAL DEVICE DAY leftovers

From `manual-verification.md`. Triage against
[device-testing.md](device-testing.md#what-only-hardware-can-prove) first — several of these are
*not* actually hardware-blocked:

- [ ] Real CloudKit / KVS config sync (1000) — genuinely hardware, and needs iCloud signed in.
- [ ] 24 h soak — genuinely hardware. Start it early in the session and let it run.
- [ ] Camera QR scan (220 / SC-220-07) — genuinely hardware.
- [ ] Siri phrases (800) — genuinely hardware.
- [ ] Real Photos library (900) — genuinely hardware.
- [ ] Ken Burns smoothness on a real panel — hardware; the luma/kinematics traces in
      `testing.md` are the objective method, not eyeballing.

## Deferred (not this session, not cancelled)

Per the scope policy: **iOS first, tvOS later, no second-device work for now.** These stay on the
list so they are not lost, but nothing above should wait on them.

- **All tvOS gates** — SC-1000-02/05/06/08, tvOS clock + FR-1000-10 pixel-shift, CloudKit-decrypt
  on tvOS, tvOS identity on hardware. Revisit when the iOS side is ready.
- **Issue #17 — the tvOS test target + hermetic seam.** Still the right diagnosis (these gates are
  blocked by missing infrastructure, not by hardware, so building it *shrinks* the device day),
  but deferred under the current policy. It is not device work and can be picked up any time
  without a frame.
- **SC-700-12 — two frames never collide.** Needs a second device. The resolver's uniqueness is
  covered by host tests (`FrameIdentityResolverTests`), including an explicit guard that a fresh
  identity is never one of the retired shared constants; what is missing is only the live
  two-device proof.

## Session hygiene

- Take the device id from the `start: connecting (device=…)` log line before verifying anything
  in HA — never assume it.
- `framepad.sh logs` is the only way to see what the app thinks; there is no other log route.
- Screenshots come out of the `.xcresult`; the UI-hierarchy dump in the same bundle is often
  faster than a screenshot for "why did this assertion fail".
- A first `rig` run failing with **"Server not reachable."** has twice been transient. Retry once
  before investigating.
- Leave the frame as a **test rig** (dev build, configured). Do not restore the App Store build.
- If the session ends with the frame gated, its HA controls will be absent — that is correct
  behaviour, not a fault. Relaunch with `--uitest-entitlements=all` to leave the controls live.

## Open questions to settle with Jan

- Should Framepad keep a **sandbox Apple ID permanently**? It would make every StoreKit gate
  re-runnable instead of once-per-session, at the cost of a signed-in account on the frame.
  Under the current iOS-first policy this is the single highest-leverage change to the rig.
- Are the orphaned-entity semantics in #15 fully settled, or does the rename path need a
  migration story of its own?
- What signals "iOS is ready" and re-opens tvOS? Suggested bar: v1.1 shipped, T042 closed, and no
  open iOS device gates — at which point #17 becomes the natural next piece of work.
