# Open iOS issues — worklist (2026-09-14)

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

## Checklist

### WP0 — triage
- [x] #54 closed (fixed in e872b90; gate runtimes 18.6 / 26.0 documented)
- [x] #55 empty `ImmichLogo.imageset` deleted, `frame.afdesign` → `Design/AppIcon/` (5781329)
- [x] #56 live ASC API: 1320×2868 in `APP_IPHONE_67`, docs corrected (033eeb7)
- [ ] **Jan, FramePhone (iOS 27), #50:** (a) does tapping an album card drill in? (b) landscape onboarding: does the
      confirm step scroll to "Start slideshow"? Post the result in #50.

### WP1 — specs first (#69)
- [ ] Subagent: #69 "Stale text" fixes (only `specs/**/spec.md`, `docs/spec-overview.md`)
- [ ] Claude: Constitution VII + III (`speckit-constitution`)
- [ ] Claude: new/changed FRs:
  - 400: persist and re-apply brightness, keep the baseline on exit, HA reports the real level
  - 500-06 ↔ 130-12: album order
  - 310-14: scrim + label default
  - 210 US2 / SC-210-02: pick-up on next open + extension confirmation
  - 700/710: metadata follows the active source
  - 9000-14: shared prominent style
- [ ] Adversarial verify against `product-facts.yaml` → `check-facts.py` → commit → close #69

### WP-50 — conditional on the FramePhone result
- [ ] Finger fails too → product bug: fix right after WP1 (landscape confirm form; `NavigationLink` in the `LazyVGrid` sheet)
- [ ] Finger works → XCUITest artifact: rework the test interaction after WP5

### WP2 — host packages in parallel
- [ ] S1 ImmichClient + OnboardingKit (#62 + #61):
  - `Album.order`
  - `AlbumReference` order + albumName
  - search uses the album order instead of `"desc"`
  - `uniqueLabel` uses the album name
- [ ] S2 PowerKit/ThemeKit (#67): brightness store + re-apply API
- [ ] Claude: wire #67 (`SlideshowView:184/285`, settings slider, `initialBrightness` in makeAdapter)
- [ ] Claude: #61 comment `OwnFrameApp:777-784`; existing host-labeled sources stay (rename possible)
- [ ] Verify + gate (host packages + iOS 18.6 sim) → facts → commit → close #61 #62; #67 stays open until the Framepad check

### WP3 — #64 HA metadata follows the active source
- [ ] S3 PhotoSourceKit + backends: `AssetMetadata` city/state/country
- [ ] Claude: red adapter tests first (link source, link-only without API key, no call on the API-key client), then
      neutral path only; drop `api` from makeAdapter
- [ ] Adversarial verify: no asset ids/keys to a foreign host → facts REMOTE-03/04 → commit → close #64

### WP4a — visible UI
- [ ] #60 scrim in `NewPhotosOverlayView.card(for:)`; check via the capture seam over the beach photo (no store re-render)
- [ ] #59 shared near-black prominent style at the 8 call sites (5 app, 3 PurchaseKit); check in the UI rig
- [ ] commit → close #60 #59

### WP4b — #65 share extension
- [ ] remove the dead `extensionContext.open`
- [ ] add the confirmation view + extension String Catalog (EN + DE) + pbxproj
- [ ] fix the comments; red contract test first; share-sheet UITest
- [ ] fact SRC-07 → commit → close #65

### WP5 — #66 + final gate
- [ ] Subagent: #66 comments + "Uhr-Overlay" → "Uhr-Einblendung"
- [ ] Full gate: host packages; iOS suite on 18.6 **and** 26.0 (confirm the runtime from the xcresult, check the
      StoreKit skip count); Framepad #67 (dim → lock/unlock → relaunch, the level holds) → close #67
- [ ] `check-facts.py`, bump `verified_commit`; list new German strings for Jan; note in `docs/store-story.md` that the
      captures predate #59/#60/#61
- [ ] Push / `publish-public.sh` only on Jan's word
