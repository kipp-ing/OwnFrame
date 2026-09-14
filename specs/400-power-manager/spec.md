# Feature Specification: PowerManager (display wake and brightness)

**Feature Branch**: `400-power-manager`

**Created**: 2026-06-23

**Status**: Active — text aligned 2026-09-14 (#69: deployment floor). Remembered brightness (#67, D-08) is
**deferred to its own feature spec** by Jan's call the same day — see Roadmap.

**Input**: Consolidated from `specs/004-power-manager/spec.md`: keep the display awake during foreground slideshow use, control brightness within iPadOS limits, and restore normal device behavior when the slideshow exits.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Keep the display awake during the slideshow (Priority: P1)

While the slideshow is running in the foreground, the iPad must not automatically dim or lock because of the system idle timeout.

**Why this priority**: A photo-frame app fails its core purpose if the screen sleeps after the system idle interval.

**Independent Test**: Start the slideshow, wait longer than the system idle interval, and verify the display remains on; exit the slideshow and verify normal idle behavior returns.

**Acceptance Scenarios**:

1. **Given** the slideshow is running in the foreground, **When** the system idle interval is exceeded, **Then** the display stays on and the device does not lock.
2. **Given** the slideshow is running with the idle timer suppressed, **When** the slideshow is left or stopped, **Then** the normal idle and lock behavior is restored.
3. **Given** the slideshow is keeping the display awake, **When** the app moves to the background, **Then** the module hands control back to iOS and no longer forces the device awake.
4. **Given** the app was in the background, **When** it returns to the foreground and the slideshow is still running, **Then** display wake suppression is re-armed.

---

### User Story 2 - Set and softly dim brightness (Priority: P2)

The app can set screen brightness to a target between 0.0 and 1.0 and can transition gradually to that value. Dimming to near zero acts as the platform-approved display-off substitute.

**Why this priority**: Brightness control makes the frame usable at night and in different rooms, while still respecting iPadOS limits.

**Independent Test**: Set a target brightness and verify the screen reaches it; request soft dimming and verify intermediate values; dim near zero and verify the display remains technically on.

**Acceptance Scenarios**:

1. **Given** the slideshow is running in the foreground, **When** a target brightness between 0.0 and 1.0 is set, **Then** the screen brightness reaches that target.
2. **Given** a target brightness outside 0.0 to 1.0 is requested, **When** it is applied, **Then** the value is clamped to the valid range instead of producing an error.
3. **Given** soft dimming is requested, **When** a target brightness is set, **Then** brightness changes gradually without a hard jump until it reaches the target.
4. **Given** brightness was dimmed to near zero, **When** brightness is raised again, **Then** it reaches the new target and the display was technically on throughout.
---

### User Story 3 - Restore brightness and idle behavior on exit (Priority: P3)

When the slideshow exits, the app restores the idle timer and, if it changed brightness, restores the brightness baseline captured before the app's first brightness change.

**Why this priority**: The app must not leave the device in a surprising dimmed, bright, or always-awake state after the slideshow ends.

**Independent Test**: Capture an initial brightness, start the slideshow, change brightness, exit the slideshow, and verify brightness and idle behavior are restored. Repeat without changing brightness and verify no unnecessary brightness write occurs.

**Acceptance Scenarios**:

1. **Given** the app changed brightness during the slideshow, **When** the slideshow is left or stopped, **Then** brightness is restored to the value measured before the slideshow's first app-driven brightness change.
2. **Given** the app did not change brightness, **When** the slideshow is left, **Then** brightness remains unchanged.
3. **Given** the app moves to the background, **When** the user changes brightness outside the app, **Then** the app does not overwrite that value while in the background.

### Edge Cases

- **Backgrounding during a soft dim**: If the app enters the background during a gradual brightness change, the in-flight change is stopped and not continued in the background; iOS takes control.
- **Rapid target changes**: If a new brightness target is set while a soft change is in flight, the newest target wins and the old transition is replaced rather than queued.
- **Baseline cannot be read**: If the brightness baseline cannot be reliably read, the app does not force a restore value on exit; doing nothing is safer than writing a wrong value.
- **Hard app termination instead of orderly exit**: If the app is killed, it may be unable to restore the baseline; this is an accepted platform boundary, not an app error.
- **Repeated activate/deactivate cycles**: Repeated wake/release cycles, such as foreground/background changes, end in a consistent state without a stuck disabled idle timer.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-400-01**: While the slideshow is active in the foreground, the system MUST suppress automatic idle, dimming, and lock behavior so the display remains on.
- **FR-400-02**: When the slideshow is left or stopped, the system MUST restore normal idle and lock behavior.
- **FR-400-03**: Wake suppression MUST be foreground-only; when the app moves to the background, the system MUST hand control back to iOS.
- **FR-400-04**: When the app returns to the foreground while the slideshow is still running, the system MUST re-arm wake suppression.
- **FR-400-05**: The system MUST set a target brightness in the range 0.0 to 1.0 and move screen brightness to that target.
- **FR-400-06**: Requested brightness values outside 0.0 to 1.0 MUST be clamped to the valid range.
- **FR-400-07**: The system MUST support soft dimming, where brightness changes gradually to the target rather than jumping directly.
- **FR-400-08**: The system MUST support dimming to near zero as a display-off substitute, while explicitly not claiming to physically power off the display.
- **FR-400-09**: Brightness changes MUST be foreground-only; the app MUST NOT change brightness while in the background.
- **FR-400-10**: Before the first app-driven brightness change, the system MUST capture the current brightness baseline if it can be read reliably.
- **FR-400-11**: On slideshow exit, the system MUST restore brightness to the captured baseline only if the app changed brightness; if the app did not change brightness, it MUST leave brightness unchanged.
- **FR-400-12**: A new soft-dim target MUST preempt any in-flight soft dim, and backgrounding MUST stop any in-flight dim.
- **FR-400-13**: Power behavior MUST be encapsulated behind an injectable interface so it is testable without real display hardware, in alignment with Modular Isolation.
- **FR-400-14**: The module MUST respect iPadOS platform boundaries: display and idle-timer control are only guaranteed while the app is foregrounded.
### Key Entities *(include if feature involves data)*

- **Power State**: Whether wake suppression is active, whether the app changed brightness, the captured baseline, and any in-flight dim target.- **Brightness Target**: A requested brightness value clamped to 0.0 to 1.0, plus whether the transition is immediate or gradual.
- **Screen Controller**: The injectable boundary that applies idle-timer and brightness effects in production and can be replaced by a fake in tests.

### Roadmap / Deferred (not yet built)

- Expose a sleep/wake capability where "sleep" softly dims to near black and "wake" restores prior brightness, driven by an external, source-agnostic presence signal. The app must not include an in-app scheduler; schedule and sensor logic live outside this module.
- **Brightness memory and automatic brightness — its own feature spec, not yet written** *(recorded 2026-09-14, #67; Jan: "a new feature, new spec needed")*. Decision D-08 (a dimmed frame should hold its level) stands, but *which* level to remember is a design question: the in-app slider, Home Assistant and Shortcuts can all set brightness, and a night automation that sets 0 % must not bring the frame up near black after a morning relaunch. The spec is to cover together: remembered level and who may set it, the ambient light sensor / automatic brightness, night-time behaviour, and the relation to presence sleep/wake (`730`). Findings to carry over from the 2026-09-14 review: re-applying on foreground must re-capture the baseline per foreground session (FR-400-10/11, SC-400-05), and the Home Assistant light reports a hard-coded 1.0 at start instead of the applied level (`SlideshowRemoteControlAdapter` `initialBrightness`).
- Reserved sub-spec `730` under topic 700: Home Assistant control surface for presence-driven sleep/wake. Acceptance preserved from the source: given a sleep/no-presence command, when it arrives, then brightness ramps to near black without stopping playback; given wake/presence returns, when it arrives, then brightness restores; HA/MQTT now and possible later on-device camera input must drive the same engine boundary.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-400-01**: During a foreground slideshow, the display remains on after the system idle interval would normally dim or lock it.
- **SC-400-02**: After slideshow exit, normal idle and lock behavior is active again.
- **SC-400-03**: Brightness targets inside 0.0 to 1.0 are reached, and out-of-range values are clamped to 0.0 or 1.0.
- **SC-400-04**: A soft dim reaches the target through at least one observable intermediate brightness value between start and target.
- **SC-400-05**: After slideshow exit, brightness equals the captured pre-change baseline whenever the app changed brightness.
- **SC-400-06**: In the background, the app performs no brightness or idle-timer writes, and a user-set background brightness remains untouched.
## Assumptions

- The slideshow feature provides lifecycle signals for start, exit, foreground, and background.
- Brightness baseline means the system value immediately before the app's first brightness write.
- Soft dimming uses calm fixed defaults for duration and step cadence; user configuration of those details belongs to display options.
- The app targets iPadOS/iOS 17+ (the deployment floor), where brightness and idle-timer control are foreground-only capabilities.
