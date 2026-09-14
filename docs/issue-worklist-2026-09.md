# Open iOS issues — worklist (2026-09-14)

**Focus (Jan, 2026-09-14):** ASC and the App Store pictures are on hold / frozen. The job now is to polish the app so it
keeps every promise in `product-facts.yaml` and the approved store claims, and to get the human tests in
[`hitl.md`](hitl.md) done.

Approved plan for the issues left by the 2026-09-13 product-facts pass. One work package (WP) per session, each ending at
a commit. tvOS issues (#17 #29 #32 #33 #47 #48 #51) stay deferred per CLAUDE.md. **Store captures in `Design/AppStore/`
are frozen:** fixes land anyway, and small drift between app and screenshots is accepted.

**Jan's decisions (2026-09-14)**
- #60: dark scrim inside the glass card.
- #61: default label is the album name from `shared-links/me`, falling back to "Shared album" / "Geteiltes Album".
- #62: the album's own order (D-16).
- #64: extend `AssetMetadata` with city/state/country.
- #65: add a small in-extension confirmation, "Open OwnFrame to start" (EN + DE); pbxproj in scope.

**Rules:** Claude does everything in `OwnFrameApp.swift`, UI and pbxproj inline. Subagents do package work only (TDD,
`swift test`, explicit file list, no commit, max. 2 rounds), and never two in the same package at once. Every
code WP gets an adversarial verify pass. Fact changes go in the same commit as the code.

Jan's own steps from this list (German string review, push word) are also queued in
[`hitl.md`](hitl.md).

## Checklist

### WP0 — triage
- [x] #54 closed (fixed in e872b90; gate runtimes 18.6 / 26.0 documented)
- [x] #55 empty `ImmichLogo.imageset` deleted, `frame.afdesign` → `Design/AppIcon/` (5781329)
- [x] #56 live ASC API: 1320×2868 in `APP_IPHONE_67`, docs corrected (033eeb7)
- [x] #50 FramePhone check — **already done before this plan** (`docs/testing.md:523-547`): landscape onboarding was a
      harness artifact fixed in 986a21c; the album-card tap was checked by finger on FramePhone/27.0 and works, the
      test wraps that one synthesized tap in `XCTExpectFailure(strict: true)` on iOS ≥ 27. No user-facing bug.

### WP1 — specs first (#69) — ✅ DONE 2026-09-14 (a36fec5)
New IDs for the code work:
- FR-310-15 (#60)
- FR-310-16 (#61)
- FR-500-06 + FR-130-02/12 (#62)
- FR-710-25 (#64)
- FR-210-31 + SC-210-02 (#65)
- FR-9000-38 (#59)

Constitution is 1.2.0. #67 dropped (own spec later). Items below kept for the record.
- [ ] Subagent: #69 "Stale text" fixes (only `specs/**/spec.md`, `docs/spec-overview.md`)
- [ ] Claude: Constitution VII + III (`speckit-constitution`)
- [ ] Claude: new/changed FRs:
  - 400: persist and re-apply brightness, keep the baseline on exit, HA reports the real level
  - 500-06 ↔ 130-12: album order
  - 310-14: scrim + label default
  - 210 US2 / SC-210-02: pick-up on next open + extension confirmation
  - 700/710: metadata follows the active source
  - 9000-14: shared prominent style
- [x] Adversarial verify against `product-facts.yaml` → `check-facts.py` → commit → close #69 (18 findings, all resolved or parked)

### WP-50 — dropped
Not needed: #50 has no product bug (see WP0). What remains is deleting the `XCTExpectFailure` block once iOS 27 synthesized
taps drill in again; the strict expectation fails loudly on that day.

### WP2 — host packages in parallel — ✅ DONE 2026-09-14
Landed #62 (album order), the #61 label source (card, Get Frame State, Shortcuts picker, album picker, onboarding review)
and #73's password lifecycle in one commit. Gate on iOS 18.6: app-hosted 70/0 + 18/0 UI, re-run after the verify fixes;
host ImmichClient 84, OnboardingKit 188, AppIntentsKit 42, SlideshowKit 192. Decisions and parked findings:
`specs/130-immich-api-v3/tasks.md` T026, `specs/120-source-library/tasks.md` Phase 9 "Verify pass". #61 closed, #62
closed, #73 stays open for its item 3 only. Jan confirmed oldest-first live and left the §2b defaults (Reset landing,
album placeholder) as they are.
- [x] S1 ImmichClient + OnboardingKit (#62 + #61):
  - `Album.order`
  - `AlbumReference` order + albumName
  - search uses the album order instead of `"desc"`
  - `uniqueLabel` uses the album name
- [~] ~~S2 PowerKit/ThemeKit (#67)~~ — **deferred (Jan, 2026-09-14):** brightness memory becomes its own feature spec
      (HA, ambient light, auto, night time); recorded in the 400 Roadmap and `hitl.md` §9. Not part of this worklist.
- [x] Claude: #61 comment `OwnFrameApp:777-784`; existing host-labeled sources stay (rename possible)
- [x] Verify + gate (host packages + iOS 18.6 sim) → facts → commit → close #61 #62

### WP3 — #64 HA metadata follows the active source
- [x] S3 PhotoSourceKit + backends: `AssetMetadata` city/state/country
- [x] Claude: red adapter tests first (link source, link-only without API key, no call on the API-key client), then
      neutral path only; drop `api` from makeAdapter
- [x] Adversarial verify: no asset ids/keys to a foreign host → facts REMOTE-03/04 → commit → close #64
- Done 2026-09-14 in `e01495c`. Follow-ups, not part of WP3:
  - **#74**: possible stale-api race in the album browser right after a source switch (pre-existing, unconfirmed,
    red test first).
  - Test gap: since `FakeAPI.failImage` fails only `thumbnail`, nothing covers a failed `.preview` HA image fetch.
  - `check-facts.py` re-verify warnings (21, incl. REMOTE-03/04 evidence) are still open; bump `verified_commit`
    only after re-verifying.

### WP4a — visible UI
- [ ] #60 scrim in `NewPhotosOverlayView.card(for:)`; check via the capture seam over the beach photo (no store re-render)
- [ ] #59 shared near-black prominent style at the 8 call sites (5 app, 3 PurchaseKit); check in the UI rig
- [ ] commit → close #60 #59

### WP4b — #65 share extension
- [ ] remove the dead `extensionContext.open`
- [ ] add the confirmation view + extension String Catalog (EN + DE) + pbxproj
- [ ] fix the comments; red contract test first; share-sheet UITest
- [ ] fact SRC-07 → commit → close #65

### Spec round closed 2026-09-14 — every code package now has spec + tasks
Implementers work from these task phases (TDD order, Claude-only steps marked):

| Issue | Task phase | Must land with / after |
|---|---|---|
| #62 | `specs/130-immich-api-v3/tasks.md` Phase 9 (T026–T035) | with #61 package part (same ImmichClient pass) |
| #61 | `specs/120-source-library/tasks.md` Phase 9 (T037–T039) + `specs/310-slideshow-resilience/tasks.md` Phase 7 (T024–T034) + `specs/800-app-intents/tasks.md` Phase 7 (T030–T036) | close only after all three |
| #73 (passwords) | `specs/120-source-library/tasks.md` Phase 9 (T040–T047) | done in WP2; landing stays (Jan, 2026-09-14) |
| #64 | `specs/710-ha-full-control/tasks.md` Phase 9 (T047–T059) | after the ImmichClient pass |
| #72 | `specs/300-slideshow/tasks.md` (T001–T013) | before or with #60 |
| #60 | `specs/310-slideshow-resilience/tasks.md` Phase 7 (T035–T040) | after 300 T005 (soft-glass tier) |
| #59 | `specs/9000-design-language/tasks.md` (T001–T012) | with #60/#72 (visual package) |
| #65 | `specs/210-shared-link-onboarding/tasks.md` Phase 10 (T057–T064) | — |
| #71 | `specs/210-shared-link-onboarding/tasks.md` Phase 11 (T065–T072) | after #65 (same tasks file, same picker area) |

Revised package order:
- **WP2:** #62 + #61 package part + #73 passwords (ImmichClient + OnboardingKit)
- **WP3:** #64
- **WP4a:** #72 → #60 → #59 (visual, simulator)
- **WP4b:** #65
- **WP4c:** #71
- **WP5:** #66 + gate

### Added 2026-09-14 by the fact check (SRC-09, LOOK-03, SHORTCUT-03, SRC-12)
- [x] **#61 widened:** the host/album-id label also leaks through "Get Frame State". Fix it at the label source per
      FR-120-13 (card + intent), inside WP2 S1 + app wiring. Test: `sourceLabel` is never a host or an id.
- [ ] **#72 chrome below iOS 26** (FR-300-34): implement the quiet-glass softGlass tier plus eased scrims; capture over
      near-white and near-black photos (iOS 17/18 + 26 sims) and on Framepad. Do it **with WP4a** (#60 uses the same glass
      helpers). Fact LOOK-03.
- [ ] **#71 album picker select-then-confirm** (FR-210-28): marking, commit on confirm, Cancel discards; UI tests.
      Own package after WP4b (OnboardingKit + app UI, Claude inline for UI). Fact SRC-09.
- [x] **#73 reset leftovers:** delete Immich-link passwords on Reset (red test first). Landing screen: Jan had no
      preference (2026-09-14), so Reset stays on the connection step and FR-200-24 is unchanged.

### WP5 — #66 + final gate
- [ ] Subagent: #66 comments + "Uhr-Overlay" → "Uhr-Einblendung"
- [ ] App catalog: Xcode's build extraction adds the key **"New photos card"** (older code, not WP2) with no German
      value. Add it with a DE translation and put it on Jan's German string list. Commit only the key, not Xcode's
      reformatting of the whole file (found 2026-09-14 after WP2).
- [ ] Full gate: host packages; iOS suite on 18.6 **and** 26.0 (confirm the runtime from the xcresult, check the
      StoreKit skip count)
- [ ] `check-facts.py`, bump `verified_commit`; list new German strings for Jan; note in `docs/store-story.md` that the
      captures predate #59/#60/#61
- [ ] Push / `publish-public.sh` only on Jan's word
