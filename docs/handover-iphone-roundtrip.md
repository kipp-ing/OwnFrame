# Handover — iPhone Roundtrip (last one before Submit)

State as of 2026-07-11. Read this first in the next session; `handover-release-prep.md` is
historical — everything in it is done.

## Where the project stands

v1.0 is **fully staged in ASC** (app id `6784154405`, version id
`e425bae6-c5cc-4855-a497-7dfdc6688883`, state PREPARE_FOR_SUBMISSION):

- **Build 1.0 (3)** (v3-only client incl. the M2 shared-link fix, iOS 17 floor) is processed
  and **selected on the version**.
- **Review notes** with the demo link are live (`demoAccountRequired: false`).
- **Demo link**: `https://bilder.kippings.de/s/Iceland2021` — password-free album share,
  38 images, expires 2027-07-11. Live-validated against the exact client paths in build 3.
- **7 iPad-13" screenshots** (2752×2064) uploaded to **both** locales, all COMPLETE.

**Why not submitted yet:** the app targets **iPhone too** (`TARGETED_DEVICE_FAMILY = "1,2"`,
all four orientations) and **iPhone has never been tested** — not the suite, not manually.
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
2. `test_sim` with `extraArgs: ["-only-testing:Immich SlideshowUITests/AppStoreScreenshotUITests",
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

## Notes

- gh account: `gh auth switch -u kipp-ing` before pushing (main is pushed as of 2239845…).
- iPad sim `CA71157B-…` was switched to English system language for the shots and has the
  app installed with the demo-link source — reset to German only if Jan asks.
- Deferred after release: `800-app-intents` → `900-photo-library-source`; clock overlay.
