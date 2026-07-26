# Handover — Release Prep

> **Historical as of 2026-07-25.** This captured the state on 2026-07-09 and is kept for the
> naming/ASC provenance only. Everything its "Deferred" section lists has since shipped —
> `800-app-intents`, `900-photo-library-source`, the `320` disk image cache, the `510` clock
> overlay, and the German localization (topic 300, 2026-07-23). Do not read the roadmap parts
> as current: start from `docs/spec-overview.md` and the module spec under `specs/Nxx-*/`.

State as of 2026-07-09. Read this first in the next session; the previous handover
(`handover-live-ha-verification.md`) is historical — that work is done.

## Where the project stands

- **Name**: the app is **"OwnFrame"** (renamed 2026-07-22 from "Photo Frame for Immich" —
  the name Alex, the Immich creator, had accepted in direct channel contact 2026-07-05).
  Home-screen/share-sheet/HA-device name is **"OwnFrame"** (8 chars, no icon-label
  truncation). Renamed across the repo, the Xcode project/source-folders/schemes, README, and
  docs; bundle IDs (`ing.kipp.Immich-Slideshow`) are unchanged.
- **ASC**: app id `6784154405`. ~~Name/subtitle still carry the old "Photo Frame for Immich"
  name~~ and ~~description/promo/keywords are not yet pushed~~ — **both resolved 2026-07-26**:
  the iOS **1.1** record (id `49d4c9d6-…`, PREPARE_FOR_SUBMISSION) now carries the current
  name, subtitle, description, promo text, keywords, and What's New in **en-US and de-DE**.
  Source of truth stays `docs/app-store-listing.md`. Privacy policy is live (ASC links
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
- [x] Push listing fields to ASC from `docs/app-store-listing.md`: description, promotional
      text, keywords, What's New — these live on `appStoreVersionLocalizations` (now the **1.1**
      version), *not* `appInfoLocalizations`. **Name and subtitle are the exception** — they sit
      on `appInfoLocalizations`, under the app's PREPARE_FOR_SUBMISSION `appInfo`
      (`b8cb2f74-…`; the READY_FOR_SALE one is not editable). JWT helper:
      `~/.appstoreconnect/asc_jwt.py` (ES256 via openssl, stdlib-only; prints a 15-min token;
      key sits next to it). Done 2026-07-26 for en-US and de-DE.
- [ ] Screenshots (iPad 13" class required, 11" recommended) — landscape slideshow, chrome,
      onboarding, settings, HA dashboard shot.
- [ ] Privacy nutrition label in ASC: "Data Not Collected".
- [ ] Categories: Photo & Video primary, Lifestyle secondary. Age rating questionnaire (4+).
- [ ] **App Review demo access**: reviewers have no Immich server — provide a working demo
      *shared link* (password-free) in the review notes, plus one sentence on what Immich is
      and the naming provenance (accepted by the Immich creator) in case 5.2.1 comes up.
- [x] **Done 2026-07-26** — the `de-DE` ASC localization no longer mirrors the English text.
      Real German copy (subtitle, promo, description, keywords, What's New) is written and
      pushed to 1.1, with terminology matched to the shipped German UI from topic 300. It is
      recorded under "German listing (de-DE)" in `docs/app-store-listing.md`. (Repo policy is
      unchanged: source, specs and docs stay English; German lives in the String Catalogs, and
      for the store in ASC — the listing doc is the one sanctioned exception, since it *is*
      store copy.)

## Deferred (do not start before release)

`800-app-intents` (includes the HomeKit-boundary docs page, FR-800-10), then
`900-photo-library-source`. Also still deferred: disk image cache, clock-overlay renderer,
German translations (topic 300 roadmap).
