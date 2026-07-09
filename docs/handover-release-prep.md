# Handover — Release Prep

State as of 2026-07-09. Read this first in the next session; the previous handover
(`handover-live-ha-verification.md`) is historical — that work is done.

## Where the project stands

- **Name**: the app is **"Photo Frame for Immich"** (accepted by Alex, the Immich creator,
  direct channel contact 2026-07-09). Home-screen/share-sheet/HA-device name is
  **"Photo Frame"** (the full name truncates under the icon). Renamed everywhere: repo
  (commit 4f56d16), README, and App Store Connect (name + subtitle, both locales, via API).
- **ASC**: app id `6784154405`, state PREPARE_FOR_SUBMISSION. Name/subtitle are set;
  description/promo/keywords are **not** yet pushed — source of truth is
  `docs/app-store-listing.md`. Privacy policy is live (ASC links
  `docs/privacy-policy.md` on GitHub; was a 404 until 2026-07-09, now fixed and agreed).
  Contact for anything published: **app@kipp.ing**.
- **Specs**: three new ones, all committed. `310-slideshow-resilience` (auto-retry +
  periodic refresh) is the **pre-release gate**; `800-app-intents` (v1.1) and
  `900-photo-library-source` (iCloud albums, v1.x) are specced and deferred, in that order.
- **Uploaded build 1.0 (1)** still carries the old display name — a fresh archive/upload is
  needed before submission anyway (see checklist).

## Next session: implement spec 310

`specs/310-slideshow-resilience/spec.md` — auto-retry with backoff + hourly source refresh.
TDD per the constitution. Notes:

- The timer/backoff/race test *design* stays inline (CLAUDE.md rule for concurrent state);
  well-scoped slices (e.g. the retry-policy type, rotation reconciliation) are good Codex
  briefings via `.claude/scripts/codex-brief.sh`.
- Everything is specced to run against injected clock/scheduler protocols — no real timers
  in tests (FR-310-12).
- Gates: `swift test` (host) + XcodeBuildMCP `test_sim` (whole test classes — single-@Test
  runs are a false green), full XCUITest before merging SwiftUI changes.

## Release scope update (2026-07-09)

**310 is implemented** (branch `310-slideshow-resilience`, all gates green) and **320
(disk image cache) ships in v1.0 too** — Jan's call: the release waits for 320.
Build order: merge 310 → build 320 (spec/plan/tasks ready in `specs/320-disk-image-cache/`,
feature.json already points there) → then the checklist below. Before every release run the
**Release gate** section in `docs/testing.md` (host suites, full sim suite incl. the
`SlideshowResilienceUITests` failure-seam tests, error-state screenshots, manual smoke).

## Release checklist (after 310 is green)

- [ ] Bump `CURRENT_PROJECT_VERSION`, archive + upload (recipe in memory
      `appstore-upload-cli`: `PATH=/usr/bin:$PATH` for exportArchive, never use the session
      scratchpad for archive/export paths).
- [ ] Push listing fields to ASC from `docs/app-store-listing.md`: description, promotional
      text, keywords, What's New — these live on `appStoreVersionLocalizations` (the 1.0
      version), *not* `appInfoLocalizations`. JWT helper: `~/.appstoreconnect/asc_jwt.py`
      (ES256 via openssl, stdlib-only; prints a 15-min token; key sits next to it).
- [ ] Screenshots (iPad 13" class required, 11" recommended) — landscape slideshow, chrome,
      onboarding, settings, HA dashboard shot.
- [ ] Privacy nutrition label in ASC: "Data Not Collected".
- [ ] Categories: Photo & Video primary, Lifestyle secondary. Age rating questionnaire (4+).
- [ ] **App Review demo access**: reviewers have no Immich server — provide a working demo
      *shared link* (password-free) in the review notes, plus one sentence on what Immich is
      and the naming provenance (accepted by the Immich creator) in case 5.2.1 comes up.
- [ ] The `de-DE` ASC localization exists and mirrors the English text — fine (repo policy is
      English-only); just keep both locales in sync when patching.

## Deferred (do not start before release)

`800-app-intents` (includes the HomeKit-boundary docs page, FR-800-10), then
`900-photo-library-source`. Also still deferred: disk image cache, clock-overlay renderer,
German translations (topic 300 roadmap).
