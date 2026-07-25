# Feature Specification: Onboarding Welcome Overhaul (iCloud, Shared-Link QR, One Welcoming Screen)

**Feature Branch**: `220-onboarding-welcome`

**Created**: 2026-07-17

**Status**: Implemented + merged to main (2026-07-18, after 900) — *(sub-spec of 200
connection-onboarding)*. Specced 2026-07-17; branch `220-onboarding-welcome` was cut from the
`900-photo-library-source` tip (this feature surfaces the 900 iCloud/Photos source, so it needs
that code). Host + UI-sim gates are green (OnboardingKit host suites; `WelcomeICloudUITests` and
the extended onboarding UITests; full XCUITest suite before merge); the camera QR end-to-end +
camera-denied fallback remains a manual device gate (SC-220-07), riding the 900/800 device day.

**Input**: User description: "Initial-onboarding gap — no iCloud on the welcome screen. Overhaul
the first-run welcome into an explaining, noob-welcoming screen offering, in friction order: an
iCloud album (top, easiest), an Immich shared album link (with a camera QR-read option, since
Immich provides a QR for shared albums), and — lowest — connect with an Immich server + API key.
Decorate it a little and make it welcoming to non-technical users."

## Clarifications

### Session 2026-07-17

- Q: How deep should the "overhaul" go? → A: Welcome screen only. Add the three first-class,
  friction-ordered paths + light decoration + QR scanning; the downstream connection / source /
  album-picker / confirm steps are unchanged.
- Q: What is the "server + API key" ("PAI") path? → A: The existing Immich server-URL + API-key
  connection flow — the advanced option, at the bottom of the welcome screen.
- Q: What does the camera QR option scan? → A: Immich's shared-album QR only. It decodes to the
  same shared-link URL a user would otherwise type or paste, and flows through the identical
  parse → resolve → (password-only-if-needed) path. QR for server/API-key setup is out of scope
  (Roadmap).
- Q: After a user picks an iCloud album from the welcome screen, where do they land? → A: Straight
  to the running slideshow, mirroring the shared-link-only path's lowest-friction "reach the
  slideshow immediately" behaviour — no server, no API key, no extra confirm step.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - Start from an iCloud album, chosen on the first screen (Priority: P1)

On first launch the user is offered a welcoming screen whose **top, recommended** choice is "Use
an iCloud album". Choosing it, the app asks for Photos access and shows the album picker; the user
picks an album and reaches the running slideshow — with no Immich server and no API key. This is
the gap this feature closes: today the iCloud/Photos source is reachable only *after* connecting a
server, so a user who only wants their own iCloud photos cannot start that way.

**Why this priority**: It is the headline gap and the lowest-friction path for the largest
audience — people who keep photos in Apple Photos/iCloud and have no Immich server at all. Without
it, those users cannot onboard on their own terms.

**Independent Test**: From no configuration, with the Photos source behind its existing seam and a
fake photo library, choose the iCloud path on the welcome screen and verify the app enters the
Photos-permission + album-picker flow and, on album selection, saves it as the active source and
reaches the slideshow — with no connection or API key persisted. Repeat with limited access
(Selected Photos offered) and denied access (calm message, setup not dead-ended).

**Acceptance Scenarios**:

1. **Given** no prior setup, **When** the welcome screen opens, **Then** its first (top) option is
   "Use an iCloud album", clearly labeled as the easiest way to start, with concise helper text.
2. **Given** the iCloud path, **When** the user grants Photos access and selects an album, **Then**
   that album is saved as the active source and the slideshow starts — no server URL or API key is
   requested or stored.
3. **Given** the iCloud path, **When** access is limited to Selected Photos, **Then** the app
   offers the Selected-Photos source exactly as the existing photoLibrary flow does today.
4. **Given** the iCloud path, **When** Photos access is denied, **Then** the app shows a calm
   message with a path to Settings and the user can still return and pick another way to start —
   setup is never dead-ended.
5. **Given** a completed iCloud-only setup, **When** the app relaunches, **Then** it routes
   straight to the slideshow without re-onboarding.

### User Story 2 - Add a shared album by scanning its QR code (Priority: P1)

The user chooses "Use a shared album link from Immich" and, instead of typing a long URL, taps
**Scan QR** and points the camera at the QR code Immich shows for a shared album. The app reads the
link, resolves it, and starts playing — asking for the album password only if the link needs one.
A scanned link and a typed link behave identically from that point on.

**Why this priority**: The user explicitly asked for this. Typing an Immich share URL on an iPad is
error-prone; scanning the QR Immich already provides is the natural, low-friction capture. It makes
the shared-link path genuinely easy.

**Independent Test**: The camera itself cannot run in the simulator, so the scanner is behind a
seam that yields a decoded string. Feed a valid shared-link string through the seam and verify it
parses (HTTPS-only, slug after `/s/`), resolves, and reaches the slideshow with no API key; feed a
password-protected link and verify exactly one password prompt; feed a non-Immich / malformed
string and verify a clear rejection with nothing persisted and no network call. End-to-end camera
capture is a manual device gate.

**Acceptance Scenarios**:

1. **Given** the shared-link path, **When** the user opens it, **Then** both manual entry and a
   "Scan QR" option are offered.
2. **Given** the user taps Scan QR the first time, **When** the camera permission prompt appears
   and is granted, **Then** the live camera view opens ready to read a code.
3. **Given** the camera reads a valid, non-protected Immich shared-link QR, **When** it decodes,
   **Then** the app resolves the link, saves it as the active source, requires no API key, and
   reaches the slideshow — identically to typing that link.
4. **Given** the scanned link is password-protected, **When** it resolves, **Then** the app asks
   for the password once and, on success, starts playing.
5. **Given** the scanned code is not a valid Immich shared link (wrong host/shape, non-HTTPS, or
   not a URL at all), **When** it decodes, **Then** the app shows a clear message, persists
   nothing, makes no network request, and lets the user retry or type the link.
6. **Given** camera permission is denied or the device has no usable camera, **When** the user is
   on the shared-link path, **Then** manual link entry remains fully available — scanning is an
   accelerator, never the only way in.

### User Story 3 - One welcoming screen a non-technical user understands (Priority: P2)

A first-time user who knows nothing about Immich, servers, or API keys opens the app and
immediately understands their three ways to start, ordered from easiest to most advanced, each with
one plain sentence of explanation and light visual polish. They pick with confidence rather than
bouncing off jargon.

**Why this priority**: Ease of use is a primary product goal. The structural paths (US1/US2) can
ship functionally without polish, but the welcoming, explained, friction-ordered presentation is
what makes the app approachable to the target audience — hence P2, layered on the P1 mechanics.

**Independent Test**: Render the welcome screen and verify exactly three options appear in friction
order (iCloud, shared link, server+key), each exposes concise non-technical helper text, the screen
has no Back affordance, and the existing choice-screen behavioural contract still holds.

**Acceptance Scenarios**:

1. **Given** the welcome screen, **When** it renders, **Then** it shows exactly three clearly
   labeled options in this top-to-bottom order: iCloud album, shared album link, server + API key.
2. **Given** each option, **When** the user reads it, **Then** a one-line, jargon-light description
   explains what it is and who it suits (e.g. "Easiest — play photos from an album on this iPad or
   in iCloud").
3. **Given** the welcome screen, **When** the user looks for a way back, **Then** there is none (it
   is the first screen) — consistent with today's choice screen.

### Edge Cases

- **Camera permission denied / restricted / no camera**: Scan QR is unavailable or disabled, a
  calm one-line explanation is shown, and manual link entry still works (US2 #6).
- **Valid URL but not an Immich share link** (wrong host or missing `/s/` slug, or a non-HTTPS
  URL): rejected client-side before any network call; nothing persisted.
- **Scanned link already in the source library**: the app switches to the existing source rather
  than creating a duplicate (existing 210 / Share-Sheet dedupe behaviour).
- **iCloud path with no albums / an empty album**: reuse the existing photoLibrary empty-state
  handling; the user is not stranded on a blank screen.
- **User backgrounds the app mid-scan**: the camera session stops and resumes cleanly; no partial
  source is written.
- **Photos access later revoked** (iCloud source already active): unchanged from 900 — revocation
  is surfaced calmly and never masked.

## Requirements *(mandatory)*

### Functional Requirements

- **FR-220-01**: The first-run welcome screen MUST present three first-class starting paths in
  friction order, top to bottom: (1) iCloud/Apple Photos album, (2) Immich shared album link,
  (3) Immich server + API key.
- **FR-220-02**: Selecting the iCloud path MUST enter the Apple Photos / iCloud album flow directly
  from the welcome screen (Photos-permission request + album picker) and, on album selection, reach
  a playing slideshow with the album as the active source — WITHOUT requiring a server connection or
  API key.
- **FR-220-03**: The iCloud path MUST reuse the existing photoLibrary source behaviour unchanged —
  full-access gate, limited-access "Selected Photos" fallback, denied-access calm messaging, and
  revocation handling — adding only the welcome-screen entry point, not new Photos behaviour.
- **FR-220-04**: The shared-link path MUST offer a camera "Scan QR" option alongside manual entry.
  A code scanned from an Immich shared-album QR MUST be handled identically to a typed/pasted link:
  same parsing, same resolve-first / password-only-when-needed flow, same source persistence.
- **FR-220-05**: QR scanning MUST request camera access with a clear, purpose-stating permission
  string. If access is denied or unavailable, the app MUST show a calm message AND keep manual link
  entry fully available — scanning is never the only way in.
- **FR-220-06**: A scanned code that is not a valid Immich shared link (not a URL, non-HTTPS, or
  missing the shared-link shape) MUST be rejected with a clear message, MUST make no network
  request, and MUST persist nothing.
- **FR-220-07**: The server + API-key path MUST invoke the existing connection flow unchanged, and
  all downstream onboarding steps (connection, source, album picker, confirm) MUST remain as they
  are today — this feature changes only the welcome screen and adds QR capture.
- **FR-220-08**: Each welcome option MUST carry concise, non-technical explanatory copy; the screen
  MUST be understandable to a user with no knowledge of Immich, servers, or API keys.
- **FR-220-09**: The welcome screen MUST preserve its existing behavioural contract: it has no Back
  affordance; the shared-link-only path still reaches the slideshow with no API key; each option
  still exposes concise helper text; iOS Share-Sheet acceptance is unaffected.
- **FR-220-10**: Sources added via any welcome path MUST land in the same source library (one
  active source) so that downstream slideshow, Settings → Sources, HA source-select, and App-Intent
  behaviour are unchanged.
- **FR-220-11**: No secrets in code, UserDefaults, or logs — the API key and any shared-link
  password stay in the keychain / secret store; a scanned URL carries no secret (a required
  password is still prompted, never embedded).
- **FR-220-12**: The QR scan MUST feed the decoded string through a host-testable seam so that
  parsing, validation, and routing are unit-tested without a camera; camera capture itself is
  verified only on a physical device.
- **FR-220-13**: All new user-facing strings MUST be English (the project is English-only).

### Key Entities *(include if feature involves data)*

- **Welcome path choice**: the user's selection among three starting paths — iCloud album, shared
  link, server + API key. Extends today's two-way choice (shared link / server) with a third,
  top-ranked iCloud case.
- **Scanned code result**: a decoded string produced by the camera scanner, handed to the existing
  shared-link parse/validate/resolve pipeline; indistinguishable downstream from a typed link.
- **Source / source library** *(reused, unchanged)*: the persisted list of switchable sources with
  one active — album, shared link, or photoLibrary kinds — the single destination for every welcome
  path.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-220-01**: A brand-new user with no Immich server can start a slideshow from an iCloud album
  chosen on the very first screen, without entering a server URL or API key.
- **SC-220-02**: A brand-new user can start a slideshow from an Immich shared album by scanning its
  QR code, being asked for a password only if the album requires one.
- **SC-220-03**: The first screen presents exactly three clearly labeled, friction-ordered options,
  each with one plain-language line of help; a non-technical user can tell which to pick without
  outside guidance.
- **SC-220-04**: An invalid or non-Immich scanned code never starts playback and never persists
  data; the user sees a clear message and can retry or type the link instead.
- **SC-220-05**: Denied or unavailable camera access never blocks setup — manual link entry remains
  available on the shared-link path.
- **SC-220-06**: Every pre-existing onboarding behaviour continues to pass its current tests —
  shared-link-only reaches the slideshow with no API key, the server path is unchanged, welcome-
  screen Back rules and helper-text expectations hold, and Share-Sheet acceptance still works.
- **SC-220-07**: The QR parse/validate/routing logic is verified by host tests with no camera; the
  end-to-end camera scan is verified on a physical device (manual gate, like the 900 Photos flows).

## Assumptions

- The 900 photoLibrary source (permission handling, album picker, Selected-Photos fallback,
  revocation surfacing) is present on this branch and is reused as-is; this feature only adds its
  welcome-screen entry point.
- Immich's shared-album QR encodes exactly the shared-link URL a user would otherwise type or
  paste — no Immich-proprietary payload beyond that URL.
- The camera is used solely to read a QR code into a URL string; no photo is captured, stored, or
  uploaded (the camera-usage string states this).
- The iCloud path lands the user straight in the slideshow after album selection (mirroring the
  shared-link-only path's lowest-friction behaviour), not through the server branch's confirm step.
- Downstream onboarding steps are unchanged; this is a welcome-screen overhaul only.
- Camera capture cannot be exercised in the iOS simulator, so its end-to-end verification is a
  manual device gate; all non-camera logic stays host-testable.
- iOS 17+ deployment floor, iPad-first, SwiftUI + `@Observable` MVVM (per the constitution/tech
  stack), and TDD (host test first) throughout.

## Dependencies

- **900 photo-library-source** — the photoLibrary `SourceKind` and its permission/album-picker
  surfaces (this branch is based on the 900 tip; 220 cannot merge ahead of 900).
- **110 / 120 / 210** — shared-link resolution, the source-library store/model, and the choice-
  first onboarding + reusable pickers that 220 extends.
- **New platform capability** — camera access (an `NSCameraUsageDescription` purpose string; none
  exists today) for QR reading only.

## Roadmap / Deferred

- **QR for server setup** — reading a server URL (and/or API key) from a QR is out of scope; QR is
  shared-link-only for now.
- **Rich welcome decoration** — beyond light polish (illustration, animation, per-option imagery)
  is deferred; this spec asks only for a welcoming, clearly explained screen.
- **Reskinning downstream steps** — the connection / source / confirm steps keep today's look; a
  full onboarding visual refresh is a separate, later concern.
- **Pre-explain each system permission prompt** — before iOS raises a permission alert, the
  welcome should calmly explain *why* it pops up and *what it is used for*: local network (reach
  the Immich server), photos (read an iCloud album), camera (scan a shared-link QR). Include a
  link to the privacy policy. Low-priority polish, but directly serves the ease-of-use goal.
