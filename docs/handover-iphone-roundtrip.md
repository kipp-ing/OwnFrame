# Handover — iPhone Roundtrip (last one before Submit)

> **Historical as of 2026-07-26.** This captured the state on 2026-07-11 and is kept for the
> device-matrix / screenshot / ASC-upload provenance only. It is **not** a session entry point:
> §5's roundtrip is done (see the status block directly below), and everything its closing
> "Deferred after release" note lists has since shipped — `800-app-intents`,
> `900-photo-library-source`, `1000-apple-tv`, the `510` clock overlay, and the German
> localization (topic 300, 2026-07-23). The build staged in ASC is now **v1.0 (8)**, approved
> and **deliberately unreleased**: the purchase-gated build must be the first version the public
> ever sees (FR-1100-17). Do not read the roadmap parts as current: start from
> `docs/spec-overview.md` and the module spec under `specs/Nxx-*/`.

> **STATUS 2026-07-11 (late): the §5 extreme-device roundtrip is DONE — one real bug found
> and fixed, build 1.0 (5) uploaded and selected.**
> All four matrix devices ran the full suite + live noob smoke (all frames eyeballed):
> SE 3rd gen @17.5, iPad 10th gen @17.5, iPhone 16e @18.6, and the stretch iPad mini 6
> @17.5. The mini surfaced a real noob-facing bug: **"Reset Configuration…" presented an
> empty, invisible popover** (the confirmationDialog hung off the NavigationStack — no
> anchor — and the invisible dismiss region swallowed the next tap; deterministic on the
> mini, `testResetFromSettingsReturnsToOnboarding` red). Fix `dbf1e8d`: anchor the dialog
> to the Reset button. Full gate after the fix: SE 17.5 + iPad 10 17.5 + mini 17.5 +
> 16e 18.6 + iPhone 17 Pro Max 26.5 + iPad Pro 13" 26.5 — **80/0 each**. Build bumped to
> **1.0 (5)** (`ec4cb26`, supersedes the never-uploaded b4), archived + uploaded via the
> `appstore-upload-cli` recipe, selected on version `e425bae6-…` after processing. Main
> pushed. Noob-lens observations that are *not* bugs: on the SE 4.7" the error card pushes
> "Start slideshow" below the keyboard (Form scrolls / return dismisses — standard iOS);
> pre-26 chrome material is fainter over bright full-bleed photos but legible and matches
> the 26 glass look.
> **Still to do (Jan, ASC web UI):** privacy label, age rating, Submit (§4).

> Historical status (before §5): the iPhone roundtrip was DONE except the build-4 binary
> upload — b4 was archived but never uploaded; build 5 replaces it.
> Suite green on iPhone (80/0) and iPad (80/0). The live noob smoke
> (`LiveSmokeUITests`, LIVE_SMOKE=1) surfaced and fixed two real bugs (commit `fae606f`):
> a Liquid-Glass chrome held at `.opacity(0)` swallowed the first button tap after reveal
> (now structural insert/remove), and the photo-info card overlapped the top chrome buttons
> in iPhone portrait (now a layout slot under the top bar). 7 iPhone screenshots
> (2868×1320, English, keyboard dismissed) are uploaded to **both** locales as
> **`APP_IPHONE_67`** (the API has no `APP_IPHONE_69`; 6.9" lives in the 6.7" slot), all
> COMPLETE. Build bumped to **1.0 (4)** (`c5e0d88`) and archived
> (`~/Library/Developer/Xcode/ImmichSlideshow-dist/ImmichSlideshow-b4.xcarchive`).
> **Still to do:** export/upload the b4 archive (recipe below/memory `appstore-upload-cli`),
> select build 4 on version `e425bae6-…`, push main (gh account kipp-ing), then Jan's three
> human clicks (privacy label, age rating, Submit).
> **Next session:** the extreme-device noob roundtrip (§5) — iOS 17.5/18.6 + smallest
> screens, same live-smoke method that caught the two chrome bugs.

State as of 2026-07-11 (`handover-release-prep.md` was already historical then). Everything from
here down is the record of that session — sections 1–3 and 5 are done, and the app went through
review; the build now sitting approved in ASC is **v1.0 (8)**, held back on purpose (FR-1100-17).

## Where the project stands

v1.0 is **fully staged in ASC** (app id `6784154405`, version id
`e425bae6-c5cc-4855-a497-7dfdc6688883`, state PREPARE_FOR_SUBMISSION):

- **Build 1.0 (3)** (v3-only client incl. the M2 shared-link fix, iOS 17 floor) is processed
  and **selected on the version**.
- **Review notes** with the demo link are live (`demoAccountRequired: false`).
- **Demo link**: `https://bilder.kippings.de/s/Iceland2021` — password-free album share,
  38 images, expires 2027-07-11. Live-validated against the exact client paths in build 3.
- **7 iPad-13" screenshots** (2752×2064) uploaded to **both** locales, all COMPLETE.

**Why not submitted yet** *(as of 2026-07-11 — since resolved; the status block at the top is
the outcome)*: the app targets **iPhone too** (`TARGETED_DEVICE_FAMILY = "1,2"`, all four
orientations) and iPhone had not been tested at that point — neither the suite nor manually.
One more roundtrip: test on iPhone → fix what surfaces → iPhone screenshots → ASC upload →
then Jan's three human clicks (privacy label, age rating, Submit).

## 1. iPhone testing

- **Sims** (only iOS 26.5 runtimes build the app scheme — pin `simulatorId`,
  `preferXcodebuild`): iPhone 17 Pro Max 26.5 `82562538-A335-47F1-BC0A-84FEF80E2884`
  (primary, 6.9" screenshot class), iPhone 17 Pro 26.5 `1FA95945-B683-4C93-9333-21A001E082CA`
  (secondary). Host `swift test` is device-independent — already green, skip.
- **Run the full sim suite on the iPhone sim** (all 18 UITest classes; 77 tests). They were
  written and only ever verified on the iPad. Expect compact-size-class landmines:
  - onboarding forms + keyboard (`AppSecureField` save-password-sheet quirk),
  - settings sheet presentation, album picker in **landscape = compact height**,
  - chrome insets (`SlideshowChromeUITests.testChromeInsetsStableAcrossOrientationAndKenBurns`),
  - share-sheet incoming flow.
  Per failure, decide: **app bug → fix** (TDD, red test first) vs **iPad-only test
  assumption → parametrize/branch by idiom**, never blanket-skip.
- **Manual smoke with the live demo link** on the iPhone sim, both orientations:
  onboarding choice → shared link → slideshow → swipe → chrome/transport → photo info →
  settings → back. Verify status bar/overlay behavior **by screenshot** (XCUITest cannot see
  the system status bar — false green).
- **If code changes:** full gate (host + iPad sim suite + iPhone suite) → bump
  `CURRENT_PROJECT_VERSION` 3 → 4 (8 occurrences, app + extension × configs) → archive +
  upload (recipe in memory `appstore-upload-cli`: `PATH=/usr/bin:$PATH` for exportArchive,
  never scratchpad paths) → select build 4:
  `PATCH /v1/appStoreVersions/e425bae6-…/relationships/build` `{data:{type:"builds",id:<build-id>}}`.

## 2. iPhone screenshots

Reuse **`AppStoreScreenshotUITests`** (env-gated, commit 2239845) on the iPhone 17 Pro Max
26.5 sim — same flow as the iPad run:

1. `xcrun simctl bootstatus <SIM> -b`, set system language English
   (`defaults write .GlobalPreferences AppleLanguages -array en-US` + `AppleLocale en_US`,
   then shutdown/boot — the sims default to German),
   `xcrun simctl uninstall <SIM> ing.kipp.Immich-Slideshow` (fresh onboarding),
   `xcrun simctl status_bar <SIM> override --time "9:41" --batteryState charged
   --batteryLevel 100 --wifiBars 3 --wifiMode active`.
2. `test_sim` with `extraArgs: ["-only-testing:OwnFrameUITests/AppStoreScreenshotUITests",
   "-parallel-testing-enabled", "NO"]` and `testRunnerEnv: {SCREENSHOT_CAPTURE: "1"}`.
   The test forces landscape (photo-frame story; matches the iPad set) — ASC accepts
   2868×1320 landscape for the 6.9" class. The asset-id oracles (chapel `87b68d06-…`,
   iceberg `a21c487a-…`) are device-independent.
3. Export: `xcrun xcresulttool export attachments --path <bundle>.xcresult --output-path <dir>`;
   the XCUIScreen buffer is portrait → rotate: `sips -r 270 *.png` → 2868×1320. Keep them in
   `~/Library/Developer/Xcode/ImmichSlideshow-dist/screenshots-v1.0-iphone/`.
4. Eyeball every frame (chrome placement and letterboxing differ in compact size classes;
   the settings sheet may cover most of the screen — drop frames that look cramped rather
   than shipping filler).

## 3. ASC upload

`.claude/scripts/asc-upload-screenshots.py` (committed; JWT helper
`~/.appstoreconnect/asc_jwt.py`, key IDs in memory `appstore-upload-cli`):

    python3 .claude/scripts/asc-upload-screenshots.py \
        --dir ~/Library/Developer/Xcode/ImmichSlideshow-dist/screenshots-v1.0-iphone \
        --display-type APP_IPHONE_69 \
        --files 03-hero-chapel.png 05-hero-iceberg.png 07-photo-info.png 04-chrome.png \
                02-onboarding-sharedlink.png 01-onboarding-choice.png 06-settings.png

Uploads to **both** locales (IDs hardcoded in the script) and clears the target set first
(idempotent, safe to re-run). After upload, check `assetDeliveryState == COMPLETE` and look
at the version page — if ASC still flags a missing 6.5" set, re-run with
`--display-type APP_IPHONE_65` and 1284×2778/2778×1284 frames (usually the 6.9" set covers
smaller phones by auto-scaling).

## 4. Then submit (human, ASC web UI — Jan)

Privacy label "Data Not Collected" → age rating confirm (all-NONE = 4+) → **Submit for
Review**. What's New is N/A for a first version.

## 5. Extreme-device noob roundtrip (iOS 17/18 floor + newest) — **DONE 2026-07-11**

Ran as planned below; the outcome (one real bug found and fixed, build bumped to 1.0 (5)) is in
the status block at the top of this file. The plan text is kept as the recipe, not as a to-do.

**Why:** every test so far ran on iOS 26.5 flagships. The iOS 17 floor (View+Compat shims,
no Liquid Glass pre-26) is a **different rendering and interaction path that has never been
exercised** — and this roundtrip proved a green suite can hide broken chrome (the swallowed
tap passed every existing test). Old-OS devices are exactly the "old iPad on the shelf"
audience the floor targets. Method: same as this session — full suite + the live noob smoke
(`LiveSmokeUITests`, LIVE_SMOKE=1, uninstall first, export attachments, **eyeball every
frame** — both bugs this round were only visible in pixels).

**Device × OS matrix** (all sims already exist; runtimes 17.5 and 18.6 are installed;
`sim-build-destination` memory was stale — the app scheme **builds for iOS 17.5, verified
2026-07-11** on the SE):

| # | Device (why) | Runtime | simulatorId |
|---|---|---|---|
| 1 | iPhone SE 3rd gen — smallest screen (4.7"), home button, no Dynamic Island | 17.5 | `9FABBA82-A611-4A13-8373-D4926763EB22` |
| 2 | iPad (10th gen) — floor-era iPad class | 17.5 | `CEE64420-AED5-4DD2-BD86-D8B4FDEDC2BE` |
| 3 | iPhone 16e — the mid ring, budget hardware | 18.6 | `652549F1-06F1-45DF-B23C-C38FA1711D29` |
| 4 | (stretch) iPad mini 6th gen — smallest iPad | 17.5 | `A935E5B0-0552-46A6-9EC7-CC4CA7FFC550` |
| 5 | 26.5 flagships (iPhone `82562538-…`, iPad `CA71157B-…`) — regression re-run **only if fixes land** | 26.5 | — |

(`iPad-iOS17-test` `20AEB1AE-…` from the floor audit also exists on 17.5.)

**Per device:** pin `simulatorId` + `preferXcodebuild`, full suite (`-parallel-testing-enabled
NO` for the live runs; old runtimes are slower), then the noob smoke, then eyeball. The
env-gated rigs (screenshot capture, live smoke) auto-skip inside suite runs.

**Noob-lens watchpoints on the floor path:**
- **View+Compat fallbacks**: chrome buttons, info glass card, settings sheet use pre-26
  materials — legibility over bright photos (scrims), and the first-tap regression tests
  (`testFirstTapOnRevealedChromeNextAdvances` + pinned variant + info-card clearance) must
  pass on this rendering path too.
- **iPhone SE 4.7"**: shared-link form with the keyboard up — is "Start slideshow" still
  tappable (no auto-scroll)? Landscape = very little height: password sheet
  (`.presentationDetents([.medium])`), album picker, settings sheet.
- **Home-button device**: no Dynamic Island insets — chrome top spacing; `statusBarHidden` /
  `persistentSystemOverlays` behave differently pre-26; verify by screenshot (XCUITest
  can't see the system status bar).
- **AppSecureField** exists as an iOS 26 save-password workaround — make sure it doesn't
  misbehave on 17/18 (password prompt flow of the protected-link path).
- **Ken Burns + crossfade** on the old renderer — toggle them live in settings during the
  smoke.
- No new ASC screenshots needed — the 6.9" + 13" sets cover smaller devices by auto-scaling.

**If fixes land:** TDD (red test first) → full gate = SE 17.5 + 16e 18.6 + both 26.5
flagships → bump `CURRENT_PROJECT_VERSION` 4 → 5 (8 occurrences) → archive/upload → re-select
the build on version `e425bae6-…`. Whether Submit waits for this roundtrip is Jan's call —
build 4's upload is pending anyway.

## Notes

- gh account: `gh auth switch -u kipp-ing` before pushing (main is pushed as of 2239845…).
- iPad sim `CA71157B-…` was switched to English system language for the shots and has the
  app installed with the demo-link source — reset to German only if Jan asks. The iPhone
  26.5 sim `82562538-…` is English too (keeps a German QWERTZ keyboard; the capture rig
  dismisses the keyboard, so it doesn't matter).
- ~~Deferred after release: `800-app-intents` → `900-photo-library-source`; clock overlay.~~
  **All three shipped and are merged to main** (800 + 900 in July 2026, the `510` clock overlay
  on 2026-07-18) — as did `1000-apple-tv` and the German localization (topic 300, 2026-07-23).
  See `docs/spec-overview.md`.
