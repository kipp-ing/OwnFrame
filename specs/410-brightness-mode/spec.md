# Feature Specification: Brightness Mode (Automatic by default, Fixed when the light sensor is covered)

**Feature Branch**: `410-brightness-mode`

**Created**: 2026-09-28

**Status**: Draft — specced 2026-09-28 from Jan's call; not planned, no code yet.

**Next session (handoff, 2026-09-28):** run Spec Kit plan → tasks for this spec, then build it TDD
(PowerKit host tests first: fake screen with iOS-like drift, injected clock for the night window).
Start from the Decisions, then FR-410-01…19. Device rig: `.claude/scripts/brightness-probe/probe.sh`
(runbook in `docs/device-testing.md` "Brightness probe rig"); FramePhone lies on **iPad jk's** light
sensor; jk's Auto-Brightness is on with a manually dimmed slider (curve lit 0.30 / covered 0.20) —
see `docs/hitl.md` §2b before measuring.
Open device check: SC-410-07 (Framepad under a strong light change). Open confirm for Jan: the
assumption that a remote *mode* command is session-only (Assumptions).

**Input**: Sub-spec of topic 400. Resolves the 400 Roadmap item "Brightness memory and automatic
brightness — its own feature spec" (#67, D-08), and removes the cause of #91 (a Home Assistant source
switch reset brightness to 255). Jan, 2026-09-28: *"we need an auto mode from normal iOS, more or less
the default. A preset is only needed when the sensor is blocked. Then the HA remote control will be
handy."* PowerManager (400) keeps owning the mechanics (wake suppression, clamping, soft dim,
baseline/restore, foreground-only). This spec decides **whether and when** OwnFrame writes
brightness at all, what it remembers, and who may change it.

## Decisions (Jan, 2026-09-28)

- **D-410-1 — Automatic is the default.** OwnFrame leaves brightness to iOS unless the user picks a
  fixed level. There are no existing users whose behaviour would change (1.1 sits at 0 territories),
  so there is no migration.
- **D-410-2 — Remote values never become the preset.** A level set from Home Assistant or Shortcuts
  lasts for the running session only; the remembered preset changes only through the in-app control.
  Reason: a night automation setting 0 % must not bring the frame back near black after a morning
  relaunch (the D-08 trap).
- **D-410-3 — A new sub-spec** (this one), not a 400 amendment.
- **D-410-4 — A night window in the app** (Jan, later the same day: *"a blaring display at night is
  awful, bad app"*). The user sets a from–to time; inside it the frame is very dim. This reverses
  the earlier "no in-app scheduler" line in 400 (amended alongside).
- **D-410-5 — Last event wins.** Window start, window end, Home Assistant and Shortcuts commands are
  all events; the most recent one holds until the next. No priority table.
- **D-410-6 — Night means "very dim", not "off".** Photos keep playing at the darkest level; there
  is no black-screen/paused night level (iOS cannot switch the display off anyway).
- **D-410-7 — A tap at night peeks.** It brings the day level for about a minute, then the frame
  fades back to night.
- **D-410-8 — The night window is free.** A blaring display at night is a core quality problem, like
  brightness itself; only Home Assistant *control* stays Supporter-gated (1100).

## Device findings the design rests on (iPad jk, iPad Pro 11-inch M4, iOS 26.6.1, 2026-09-28)

Measured with a throwaway probe app (scratchpad, not in the repo) logging `UIScreen.brightness`
every 0.5 s, and FramePhone lying on jk's ambient light sensor as a switchable light source (white
screen at full brightness vs. black screen).

1. **iOS auto-brightness runs while an app is frontmost, and the app can read the result.**
   With no app write: sensor covered → 0.00; lit → 0.55 within ~3 s; covered again → a slow ramp
   down (0.55 → 0.15 in ~35 s). Reported values move in 0.05 steps.
2. **A written value is not held.** iOS treats an app write like a user nudge on the
   auto-brightness curve: after writing 0.80, covering the sensor drifted it 0.80 → 0.15 in ~45 s,
   and light brought it back to exactly 0.80. **So a "fixed" level only stays fixed if the app
   keeps re-applying it.**
3. **Re-applying once per second holds it.** Target 0.80, sensor covered for 75 s: 211 of 213
   samples read 0.80, two read 0.75 (one 0.05 step, re-corrected within a second).
4. **An app cannot detect a covered sensor** — there is no public ambient-light API, and a dark
   reading is indistinguishable from a dark room. The choice is the user's.
5. **An app cannot switch the system Auto-Brightness setting**, and the app has no reliable way to
   know whether it is on.

**Framepad (iPad Pro 10.5, iOS 17.7, the deployment floor), same rig, 2026-09-28:** auto-brightness
also runs while the app is frontmost and is readable, but it reacted only weakly to the phone (lit
0.15, covered 0.05–0.10, vs. 0.55/0.00 on jk). A written 0.80 **held for 60 s covered and 40 s lit**
(no drift). That is not proof that iOS 17 never drifts, because the light change the sensor saw was
small. It does not change the design either: the hold loop (FR-410-04) only writes when the value it
reads differs from the target, so where iOS does not drift it never writes.

6. **An app write outlives the app and moves the whole auto-brightness curve** (jk, later the same
   night). After tests 2–3 had written 0.80, a probe that wrote nothing read lit 0.85 / covered 0.40
   (first run: 0.55 / 0.00). After writing 0.20 and killing the app, a fresh read-only probe read
   lit 0.20 / covered 0.00. iOS keeps adapting to light, but around the app's last value, and it does
   not restore anything when the app goes away. On Framepad (iOS 17.7) the level even stayed frozen
   at the written 0.80 for 105 s after the app was killed, covered and lit, while before the write it
   still moved in 0.05 steps (weak stimulus, see below).
7. **Apple's primary source agrees and names the reset** ([`UIScreen.brightness`](https://developer.apple.com/documentation/uikit/uiscreen/brightness),
   read 2026-09-28): *"Brightness changes remain in effect until the person locks their device, even
   if the person closes your app before then. The next time the person unlocks the device, the
   system restores the brightness setting to the original value in Settings or Control Center."*
   So an app write acts like moving the Control Center slider until the next lock. Apple does not
   document any learning beyond that; its support page only advises turning Auto-Brightness off and
   on again if it "isn't adapting correctly" ([support.apple.com/109351](https://support.apple.com/en-us/109351)).

8. **A lock/unlock undid only the last write** (jk, Jan locked and unlocked by hand). Afterwards, with
   nothing written: lit 0.75–0.85, covered 0.40 — the 0.20 write was gone, but the curve did not go
   back to the first run's 0.55 / 0.00; it matched the state after the 0.80 writes. So "restores the
   original value" (finding 7) does not mean "as before the app's first write". Whether iOS restores
   a value saved at some earlier point or keeps an undocumented learned preference is open. Either
   way, OwnFrame cannot rely on the lock to undo its writes.

9. **With system Auto-Brightness off, nothing moves** (jk, Jan switched it off). With nothing written,
   0.65 stayed 0.65 through covered and lit phases; a written 0.60 then held for 85 s through
   lit/covered/lit with no drift. So for a covered-sensor frame, turning Auto-Brightness off is the
   clean fix on the iOS side, and Fixed mode's hold loop then simply never needs to write. Fixed
   still matters for users who leave it on (Apple warns that turning it off "may increase power
   consumption"), and the in-app hint may name the iOS setting as the alternative (FR-410-11).

10. **Framepad (iOS 17.7) barely follows the light while it stays still.** With Auto-Brightness
    confirmed on, a read-only run sat at 0.20 for 95 s through lit/covered/lit. Jan's hand check:
    it seems to adjust only once the iPad is physically moved. Probe run with timed moves (3 min):
    covered for 40 s → no change (0.25); move 1 while covered → no change; lit for 40 s → no
    change; move 2 while lit → about 14 s later the first and only reaction of the run (0.25 → 0.60,
    then a ramp down to 0.10). So the only adjustment followed a move, but the first move changed
    nothing: the motion idea is plausible, not proven. The cause (hardware generation, iOS 17, or a
    motion trigger) stays unknown. If it holds, a
    wall-mounted frame of that generation hardly adjusts in Automatic. Automatic stays the default
    (it is what iOS does), but it makes Fixed plus Home Assistant/Shortcuts the practical path on
    such frames, and the Fixed hint should also cover "brightness does not follow the room".

## Research (2026-09-28, primary sources first)

- **No way to read the light or the Auto-Brightness state.** `UIScreen` has `brightness`,
  `brightnessDidChangeNotification` and `wantsSoftwareDimming`, nothing about the sensor
  ([UIScreen](https://developer.apple.com/documentation/uikit/uiscreen)); `UIAccessibility` has no
  Auto-Brightness, True Tone, Night Shift or Reduce White Point status. SensorKit's ambient light
  sensor needs `com.apple.developer.sensorkit.reader.allow`, granted only for an Apple-approved
  research study ([entitlement](https://developer.apple.com/documentation/bundleresources/entitlements/com.apple.developer.sensorkit.reader.allow),
  verified). The camera could be a light proxy, but at the cost of a camera permission and the
  in-use indicator on a frame that should just show photos — out of scope.
- **Learning:** Apple documents none; "auto-brightness learns you" claims are blog-only.
- **`UIScreen.main` is deprecated since iOS 26.0** ([doc](https://developer.apple.com/documentation/uikit/uiscreen/main),
  verified); Apple points to the window scene's screen. The plan should reach the screen through the
  scene, not `UIScreen.main`.
- **`wantsSoftwareDimming`** lets the system dim "lower than the hardware is normally capable of"
  in software ([doc](https://developer.apple.com/documentation/uikit/uiscreen/wantssoftwaredimming),
  verified) — a candidate for 400's below-minimum dim instead of more `brightness` writes.
- **Only the user can set** Auto-Brightness, Reduce White Point, True Tone, Night Shift and Low Power
  Mode (readable, not settable). Apple warns turning Auto-Brightness off "may increase power
  consumption" ([iPad guide](https://support.apple.com/guide/ipad/adjust-screen-brightness-color-balance-ipad997d972d/ipados)).
- **Comparable apps (secondary):** Kiosk Pro's night mode dims to minimum on a schedule and restores
  "the previously-set brightness level" at wake; photo-frame apps offer scheduled dimming and tell
  users to set Auto-Lock to Never. None documents holding a level against auto-brightness. A Home
  Assistant kiosk discussion (July 2026, a user, not a maintainer) reports that setting a brightness
  "inhibits" iPadOS auto-brightness and proposes exactly our split: leave the system default, or a
  fixed brightness ([discussion](https://github.com/orgs/home-assistant/discussions/2403)).
- **Known issues:** only user bug reports on Apple's forums (e.g. iOS 18 beta dimming to minimum
  after unlock); no Apple engineer statement on app writes and auto-brightness.

**What this means for the design.** A frame never locks (the idle timer is off), so without OwnFrame's
own restore, a Fixed session or a remote 0 % would keep shifting the iPad's brightness after leaving
the slideshow, until the next lock. That makes FR-400-11 (restore the session baseline on exit) and
FR-410-10 (restore once when going back to Automatic) load-bearing, not cosmetic. It is also one more
reason for D-410-1: in Automatic nothing is written, so nothing needs undoing.

**Framepad (iPad Pro 10.5, iOS 17.7, the deployment floor), same rig, 2026-09-28:** auto-brightness
also runs while the app is frontmost and is readable, but it reacted only weakly to the phone (lit
0.15, covered 0.05–0.10, vs. 0.55/0.00 on jk). A written 0.80 **held for 60 s covered and 40 s lit**
(no drift). That is not proof that iOS 17 never drifts, because the light change the sensor saw was
small. It does not change the design either: the hold loop (FR-410-04) only writes when the value it
reads differs from the target, so where iOS does not drift it never writes. Framepad was left at the
written 0.80 at the end of the run.

Still to measure (device checks, see SC-410-07): Framepad with a stronger light change (phone placed exactly
over the sensor next to the front camera); (Auto-Brightness off: done, finding 9).

## User Scenarios & Testing *(mandatory)*

### User Story 1 - A frame that behaves like any iPad (Priority: P1)

A user sets up OwnFrame and starts the slideshow. Brightness follows the room exactly as iOS
auto-brightness would — brighter by day, dimmer at night — and OwnFrame never writes brightness.

**Why this priority**: This is the default for every new frame. It needs no setup, and a whole class
of bugs (resets on source switch, relaunch, foreground return — #91) cannot occur when nothing is
written.

**Independent Test**: With a fake screen controller, run the slideshow in Automatic through start,
source switch, pause/resume, foreground return and exit; assert zero brightness writes.

**Acceptance Scenarios**:

1. **Given** a fresh install, **When** the slideshow runs, **Then** the mode is Automatic and
   OwnFrame performs no brightness write.
2. **Given** Automatic mode, **When** the active source changes (in-app, Home Assistant or
   Shortcuts), the slideshow is paused/resumed, or the app returns to the foreground, **Then** no
   brightness write happens.
3. **Given** Automatic mode, **When** the slideshow is left, **Then** nothing is restored, because
   nothing was changed.

### User Story 2 - A fixed level when the light sensor is covered (Priority: P1)

The frame sits in a case or mount that covers the iPad's light sensor, so iOS drives it to black.
The user switches Brightness to **Fixed** and sets a level. The frame holds that level and still
holds it after a relaunch.

**Why this priority**: This is the case the in-app setting exists for. Without it such a frame is
unusable, and without re-applying (finding 2) the level would drift away anyway.

**Independent Test**: With a fake screen controller that drifts its value like iOS, set Fixed 0.8
and assert the value is re-applied back to 0.8; relaunch and assert 0.8 is applied again.

**Acceptance Scenarios**:

1. **Given** the user selects Fixed and sets a level, **When** the slideshow runs in the
   foreground, **Then** brightness reaches that level (400 soft dim) and is held there: whenever
   the read value differs from the target, OwnFrame re-applies the target.
2. **Given** Fixed mode with a remembered level, **When** the app is relaunched or returns to the
   foreground, **Then** the remembered level is applied again, with the baseline captured anew for
   this foreground session (FR-400-10).
3. **Given** Fixed mode, **When** the slideshow is left or the app goes to the background,
   **Then** re-applying stops at once and 400's restore rules apply.
4. **Given** Fixed mode, **When** the user switches back to Automatic, **Then** OwnFrame stops
   writing and restores the session baseline once (FR-400-11), after which iOS is in control.
5. **Given** the Fixed control, **When** it is shown, **Then** it explains when to use it, in
   positive words ("For a frame whose light sensor is covered — keeps the level you set").

### User Story 3 - Home Assistant and Shortcuts take over for a while (Priority: P2)

An automation dims the frame to 0 % at 23:00 and hands it back at 07:00 — either to a level or to
Automatic.

**Why this priority**: This is where remote control earns its place: night-time and presence rules
live in Home Assistant or Shortcuts, not in the app (400 Roadmap, `730`).

**Independent Test**: With a fake MQTT transport and a fake screen controller: send a brightness
command in Automatic → mode becomes a session override at that level; send mode `auto` → writes
stop; relaunch → the in-app setting is back and the preset is unchanged.

**Acceptance Scenarios**:

1. **Given** any mode, **When** Home Assistant (light brightness) or the Set Brightness intent sets
   a level, **Then** the frame holds that level for this session exactly like Fixed (re-applied),
   and the remembered preset is **not** changed (D-410-2).
2. **Given** a session override, **When** Home Assistant selects mode `auto`, **Then** OwnFrame
   stops writing and restores the session baseline once; **When** it selects `fixed`, **Then** the
   remembered preset applies.
3. **Given** a session override, **When** the app is relaunched, **Then** the in-app setting (mode
   and preset) applies again; the override is gone.
4. **Given** the user moves the in-app control during a session override, **Then** the override
   ends and the in-app choice applies (and is remembered).
5. **Given** any mode, **Then** Home Assistant's light state and the Get Frame State intent report
   the **effective** brightness — the value read from the screen in Automatic, the held target
   otherwise — never a hard-coded value.

### User Story 4 - Dark at night, without any automation (Priority: P1)

A user sets a night window, say 23:00–07:00. At 23:00 the frame fades to very dim and the photos
keep playing; at 07:00 it goes back to its day mode. If it crashes or relaunches at 02:00, it comes
up dim, never blaring. Home Assistant can still brighten it for a movie night, until the next
window event.

**Why this priority**: A frame that lights up a dark bedroom or living room at night is a bad app,
whatever the day mode is — and on frames whose auto-brightness barely reacts (finding 10) it is the
only thing that keeps nights dark without Home Assistant.

**Independent Test**: With an injected clock, a fake screen controller and a fake MQTT transport:
cross the window start and end, relaunch inside the window, send a Home Assistant level inside the
window and cross the end; assert the levels and the order of writes.

**Acceptance Scenarios**:

1. **Given** a night window is set, **When** its start time passes while the slideshow runs in the
   foreground, **Then** brightness fades softly (400 soft dim) to the night level and the photos
   keep playing.
2. **Given** the night window is active, **When** its end time passes, **Then** the frame returns to
   its day mode: in Fixed to the preset; in Automatic to the brightness from before the night, after
   which OwnFrame stops writing.
3. **Given** a time inside the window, **When** the app launches or returns to the foreground,
   **Then** the night level applies at once (the window is a state, not only two moments).
4. **Given** the night window is active, **When** Home Assistant or Shortcuts sets a level, **Then**
   that level holds (last event wins) until the next window event, a relaunch, or the in-app control.
5. **Given** a Home Assistant level set during the day, **When** the window starts, **Then** the night
   level applies (the window start is the newer event).
6. **Given** the night window is active, **When** the user taps the screen, **Then** the day level
   shows for about a minute and the frame then fades back to night; repeated taps extend the peek.
7. **Given** the night window is active, **Then** Home Assistant sees it (a "night active" state), and
   an entitled Home Assistant can switch the app's window on or off (for people who schedule in HA).

### Edge Cases

- **Crash or relaunch at night after an Automatic day**: the night write outlives the app until the
  next lock (finding 6/7), so a baseline captured at a night relaunch would be the night level. The
  brightness to return to at window end is therefore the one captured **before the night began**,
  and it is remembered across launches (FR-410-17). Otherwise the frame would stay dark all day.
- **Window across midnight, DST and time-zone changes**: the window is evaluated in local wall-clock
  time on every check; a start equal to the end means no window.
- **App not frontmost at the window start**: nothing happens (foreground-only, FR-400-09); the night
  level applies as soon as the app is foreground inside the window.
- **Peek while a Home Assistant level holds**: the peek shows the day level and returns to the
  *current* holder (the Home Assistant level), not to the night level.

- **Night 0 % then a crash/relaunch**: the frame comes up in its in-app setting (Automatic or the
  preset), not at 0 %. Home Assistant may re-send its value; OwnFrame does not remember it.
- **Source switch in Fixed or override** (#91): a source switch never writes brightness itself; the
  hold loop is the only writer, so any stray reset is corrected within one interval.
- **Fixed level below the hardware minimum**: the software dim (400 seam) covers the part below the
  hardware floor; the hold loop keeps the hardware part at its floor.
- **Automatic telemetry**: iOS may move brightness continuously; the Home Assistant state is
  published only on a meaningful change and rate-limited, so a slow auto ramp does not flood the
  broker.
- **User changes brightness in Control Center while Fixed**: the hold loop re-applies the target.
  The in-app control is the way to change a fixed level; this is the price of holding it.
- **Background**: no reads-and-writes loop runs in the background (FR-400-09); iOS owns brightness.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-410-01**: The frame MUST have a brightness mode, **Automatic** or **Fixed**, remembered across
  launches; the default MUST be Automatic.
- **FR-410-02**: In Automatic, OwnFrame MUST NOT write screen brightness at any point of the
  slideshow's life, including start, source switch, pause/resume, foreground return and exit.
- **FR-410-03**: In Fixed, the remembered preset level MUST be applied when the slideshow runs in the
  foreground and MUST be re-applied at every foreground return and relaunch.
- **FR-410-04**: While a level is held (Fixed or a session override) and the app is foreground,
  OwnFrame MUST re-apply the target whenever the read brightness differs from it, checking at least
  once per second (finding 3). The check MUST stop at once on background or slideshow exit.
- **FR-410-05**: The hold loop MUST be the only brightness writer outside explicit user/remote
  commands; source switches, playback changes and view lifecycle MUST NOT write brightness (#91).
- **FR-410-06**: The preset level MUST change only through the in-app control (D-410-2).
- **FR-410-07**: A brightness value from Home Assistant or Shortcuts MUST start a **session override**:
  the level is held like Fixed until the in-app control is used, a remote mode command arrives, or
  the app relaunches. It MUST NOT change the remembered mode or preset.
- **FR-410-08**: Home Assistant MUST get a `brightness_mode` select entity (`auto` / `fixed`) whose
  commands act as session overrides (FR-410-07); it is part of the Supporter-gated control set, like
  the existing brightness light (1100). Telemetry of the effective mode stays free.
- **FR-410-09**: The Home Assistant light state and the Get Frame State intent MUST report the
  effective brightness (FR-410 US3-5). In Automatic the published state MUST be rate-limited and only
  sent on a change of at least one step.
- **FR-410-10**: Switching from a held level back to Automatic (in-app or remote) MUST stop writing
  and restore the session baseline once (FR-400-11).
- **FR-410-11**: The in-app Fixed control MUST explain its purpose (a covered light sensor) and MUST
  NOT claim OwnFrame measures the room or detects a covered sensor (finding 4).
- **FR-410-12**: The mode, preset and night window are ordinary settings (UserDefaults, like 500's
  display options); they are not secrets.
- **FR-410-13**: The user MUST be able to set a night window (start and end in local time, off by
  default) and a night level from the dark end of the range; the default night level MUST be the
  darkest the frame can show (hardware minimum plus 400's software dim).
- **FR-410-14**: Brightness MUST follow **last event wins** over these events: window start, window
  end, a Home Assistant or Shortcuts command, and the in-app control. The newest event's level holds
  (with the hold loop, FR-410-04) until the next event.
- **FR-410-15**: At launch and at every foreground return, the frame MUST derive its level from the
  current time: inside the window the night level, outside it the day mode (Automatic or the preset).
  A session override does not survive a relaunch (D-410-2).
- **FR-410-16**: The night window MUST keep the slideshow running (D-410-6) and MUST fade into and out
  of the night level (FR-400-07).
- **FR-410-17**: When the night begins in Automatic, the brightness at that moment MUST be captured
  and remembered across launches; at window end in Automatic, OwnFrame MUST restore it once and then
  stop writing.
- **FR-410-18**: A tap during the window MUST show the day level for about one minute (repeated taps
  extend it), then fade back to the level of the current event holder. A peek is not an event.
- **FR-410-19**: Home Assistant MUST get a free "night active" state and a Supporter-gated switch that
  turns the app's night window on or off. The night window itself is free (D-410-8).

### Key Entities

- **Brightness Mode**: Automatic or Fixed, remembered.
- **Preset Level**: The remembered fixed level, 0.0–1.0, set only in-app.
- **Session Override**: An in-memory level (or mode) from Home Assistant/Shortcuts, gone on relaunch.
- **Night Window**: Start and end in local time plus a night level; off by default.
- **Event Holder**: The newest of window start/end, remote command or in-app control — whose level
  currently holds.
- **Pre-Night Baseline**: The brightness captured when a night began in Automatic, remembered across
  launches, restored once at window end.
- **Effective Brightness**: What the frame shows now — read from the screen in Automatic, the held
  target otherwise; the single value every surface reports.

## Success Criteria *(mandatory)*

- **SC-410-01**: In Automatic, host tests covering start, source switch (all three paths),
  pause/resume, foreground return and exit record zero brightness writes.
- **SC-410-02**: In Fixed with a drifting fake screen, the value returns to the target within one
  check interval; on the device (sensor covered for ≥ 60 s) at least 95 % of 0.5 s samples read the
  target.
- **SC-410-03**: After relaunch, Fixed applies the preset; a prior remote 0 % is not applied.
- **SC-410-04**: A Home Assistant brightness command holds its level for the session and leaves the
  stored preset unchanged; `brightness_mode = auto` stops all writes.
- **SC-410-05**: Home Assistant's light state equals the effective brightness at connect and after
  every change (no hard-coded 1.0).
- **SC-410-06**: #91's reproduction (`device-accept.sh … ha-parity` rapid source switches) ends with
  brightness unchanged in Automatic and at the held target in Fixed.
- **SC-410-07** *(device check)*: Findings 1–3 reproduced on Framepad (iOS 17.7) — findings 1 and
  the no-drift case recorded 2026-09-28, drift under a strong light change still open; a check that
  leaving the app after Fixed leaves no lasting shift on the iOS auto-brightness curve; behaviour
  with system Auto-Brightness off recorded.

- **SC-410-08**: With an injected clock, crossing the window start fades to the night level and the
  window end returns to the day mode; a launch inside the window starts at the night level.
- **SC-410-09**: A relaunch inside the window after an Automatic day, followed by the window end,
  restores the remembered pre-night brightness — never the night level.
- **SC-410-10**: A Home Assistant level inside the window holds until the window end and no longer; a
  daytime Home Assistant level is replaced by the night level at the window start.
- **SC-410-11**: A tap at night shows the day level and the frame is back at the holder's level
  within 70 s of the last tap.

## Assumptions

- A remote **mode** command is a session override too (D-410-2 extended from the level to the mode,
  for one consistent rule: remote is for now, in-app is for keeps).
- The hold loop may react to `brightnessDidChangeNotification` in addition to (or instead of) the
  1 s check; the plan decides, SC-410-02 is the bar.
- The hold interval of 1 s is the measured-good value on jk; the plan may pick a shorter one if
  Framepad needs it.
- 400's software dim below the hardware minimum stays as it is and is only used when a level is held
  (Fixed, override or night).
- The night level is adjustable within the dark end of the range; the plan fixes the exact bounds.
- The peek length of about one minute is a starting value; the plan may tune it.

## Out of Scope

- Detecting a covered sensor, or reading the ambient light sensor (no public API).
- Toggling the system Auto-Brightness setting.
- A black-screen or paused night level (D-410-6), and more than one night window per day.
- Presence-driven sleep/wake (`730`), which will build on the session override.
