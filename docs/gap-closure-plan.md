# Gap-Closure Plan

> **Historical / superseded as of 2026-07-26.** This captured the state on 2026-07-19 and is kept
> for the sequencing provenance only. Much of what it lists as open has since shipped — the `1100`
> purchase gate is specced, implemented and merged (one **Supporter Unlock**, not the two tiers
> proposed below, with a real StoreKit 2 adapter in `Packages/PurchaseKit`; only the manual App
> Store Connect day, `1100/T042`, is left), German localization shipped 2026-07-23 across iOS +
> tvOS via the String Catalogs, and `docs/app-store-listing.md` carries the unlock copy. Do not
> read the open checkboxes below as current work: start from
> [`spec-overview.md`](spec-overview.md) and the module spec under `specs/Nxx-*/`.

**Written**: 2026-07-19. **Scope**: everything known-but-unfinished *except* the Apple TV /
tvOS work (topic `1000`), which is tracked separately — see
[`specs/1000-apple-tv/tasks.md`](../specs/1000-apple-tv/tasks.md) and the FINAL DEVICE DAY
section of [`manual-verification.md`](manual-verification.md).

This is a sequencing document, not a source of truth. Each spec under `specs/Nxx-*/spec.md`
remains authoritative for its own area; [`spec-overview.md`](spec-overview.md) is the map.

## Why this exists

A survey on 2026-07-19 found that most apparent "open work" was bookkeeping drift, since
reconciled (commit `353a529`). What survived that reconciliation is listed below. Two items are
**at risk of being lost entirely** — they are recorded nowhere durable — and they are the first
thing to fix.

---

## 0. Rescue the at-risk records — do this first

Both are single points of failure. Neither takes long.

- [ ] **Monetization research** lives only in `tmp/monetization-research-2026-07-18.md` — 489
      lines, gitignored via `.gitignore:85`, untracked. `git clean -x` destroys it. It is the
      only record of a fully-formed, release-blocking product decision.

      **Do not simply commit it.** This repository is public (Fair Source, contributor-facing,
      headed for awesome.immich.app and r/selfhosted). The document contains pricing strategy,
      competitor assessments, press/outreach contacts, and pre-launch coordination notes — none
      of which should be published. Back it up *outside* the repo, and separately distil into
      the `1100` spec only what belongs in the open: the tier boundaries, the gating behaviour,
      and the no-subscription / never-claw-back constraints. Leave prices, competitor analysis
      and launch tactics out of version control.
- [X] ~~**The "Quiet Glass" design artifact** is cited as the design source of truth by four specs
      and does not exist in the repo.~~ **Done 2026-07-19** — recovered from the published artifact
      and committed at [`design/quiet-glass-2026-07-18.html`](design/quiet-glass-2026-07-18.html).
      The citing lines in `510/spec.md`, `510/research.md` and `500/spec.md` now link to it.
      It covers considerably more than the clock round that became `510`: *Glass, soft glass, focus
      glass*, *Scrims that whisper*, *Captions, not metadata*, *Readable on white, grey and black
      alike*, *The same design at ten feet*, and a *How the mocks map to the code* section — i.e.
      most of the `330` scope below is already designed.

---

## 1. Critical path to first public release

Two things blocked shipping publicly when this was written. §1a has since been built and merged —
only its manual App Store Connect day (`1100/T042`) is left — so what remains is execution: that
day plus the device day in §1b. Everything in sections 2–5 is post-release.

### 1a. Monetization → new spec `1100`

Next free hundreds-block (`1000` is taken). This is a new module — a new gating seam that every
paid capability area reads — not an amendment.

**State on 2026-07-19**: no spec, no plan, no tasks, **no StoreKit code of any kind** (no
`StoreKit` import, no `.storekit` config, no IAP entitlement). `docs/app-store-listing.md` had no
IAP section and read as a free app throughout. The legal half of the plan *did* ship — `LICENSE`
is FSL-1.1-MIT and the README/listing carry the Fair Source line.

**Superseded**: `specs/1100-purchase-gate/` holds spec, plan and tasks; `Packages/PurchaseKit`
ships the entitlement model and a real StoreKit 2 adapter against
`OwnFrameTests/Configuration.storekit`; and the listing carries the Supporter Unlock section.

**Sequencing constraint (from the research, and the reason this is urgent):** v1.0 build 8 is
approved-but-unreleased and includes HA/MQTT for free. Never claw back a shipped-free feature —
so the gated build must be the *first version the public ever sees*. Releasing b8 as-is forecloses
the option.

- [X] ~~Spec + plan + tasks: which capability areas gate (research proposes a polish tier and an
      automation tier), the purchase / restore / Family-Sharing surface, and the entitlement
      seam.~~ **Done** — `specs/1100-purchase-gate/`. The two-tier shape proposed here was
      **abandoned**: the polish and automation tiers and the bundle were collapsed into a single
      **Supporter Unlock** on 2026-07-23 (PR #40).
- [X] ~~Implement TDD-first behind a `PurchaseGating`-style protocol with an in-memory fake, so
      the gating logic is host-testable without StoreKit — same pattern as `ImmichAPI` and
      `CodeScanning`.~~ **Done** — `StoreClient` + `StubStoreClient` in `Packages/PurchaseKit`,
      with `StoreKitClient` as the real adapter.
- [ ] ~~Update `docs/app-store-listing.md` (price + IAP)~~ — **done**, the listing carries the
      Supporter Unlock and the ASC IAP-metadata notes. Still open: the live ASC description,
      which says "Open source (MIT)" after the FSL switch — it must ride along with the next
      version's metadata (part of `1100/T042`).

### 1b. The shared device day

One hardware session closes every remaining non-tvOS gate. All four already have written
checklists; this is execution, not planning.

- [ ] **220/T021** — camera QR scan end-to-end, invalid-code rejection, camera-denied fallback,
      `NSCameraUsageDescription` copy (SC-220-01/02/04/05).
- [ ] **800/T029** — Siri phrase discovery, overnight personal automation (SC-800-02/03).
- [ ] **900/T036** — real Photos library, shared albums, full-access gate (SC-900-01/02/04).
- [ ] **210** — T003 (live server), T025 (real iOS Share Sheet round trip), T051 (device re-test).

**SC-900-07 never completes**: the iOS 27 shared-album rebuild has to be re-checked each beta
cycle. Treat it as recurring, not as a task to tick.

---

## 2. Real gaps in shipped code

Small, well-understood, cheap to close.

- [ ] **`120/T028` — secret-hygiene test.** The highest-value item here. Constitution III
      prohibits secrets in UserDefaults, but today that is only a *manual* audit gate in
      `spec-traceability.md`; no test asserts it. Dump the UserDefaults suite and the encoded
      source library, assert no password or API key appears.
- [ ] **`120/T027`** — mixed-library relaunch persistence (incl. a password-protected shared
      link). **`120/T032`** — secret grep over the suite + manual log check. **`120/T033`** —
      changelog.
- [X] ~~**QR when adding a source later.**~~ **Done 2026-07-19.** Specced as **FR-120-12** /
      **SC-120-05**, implemented in `SharedLinkAddForm.swift`, and covered by
      `SourceLibraryUITests.testAddSharedLinkFormOffersQRScanAlongsideManualEntry` plus two host
      pins in `ScannedLinkRoutingTests`. Settings → Sources and onboarding step 2 both gained it
      from the one change, and the typed name now rides along instead of being discarded. The
      live camera scan rides the existing SC-220-07 device gate.

---

## 3. Unspecified features

Roughly by value. All need SDD artifacts before any code.

- [ ] **Quiet Glass → new sub-spec `330`** (of topic 300, following 510's precedent). Blocked on
      recovering the design artifact (section 0). Covers the ambient caption / "Always" mode
      (`510/spec.md:105`), the soft-glass fallback re-tint (`510/spec.md:82`), and the
      bright-backdrop label flip (`510/spec.md:10`). Note 510 already shipped the caption-*yield*
      rule (FR-500-18) with nothing to collide with — `330` supplies the collider.
- [ ] **"Set up another frame" QR screen** — display the active source's link as a QR on the frame
      itself, turning each install into an onboarding kiosk for the next. Pairs with the QR work
      in section 2; recorded only in the gitignored research doc. Sub-spec of `120` or `220`.
- [ ] **`730` HA presence-driven sleep/wake** — number already reserved in three places
      (`spec-overview.md`, `400/spec.md:97`, `700/spec.md:86`) with acceptance criteria written.
      Only needs a directory when scheduled.
- [X] ~~**German localization (FR-300-30)** — `300/spec.md:191` requires each roadmap item to be
      scheduled as its own Spec Kit feature. Translation pass over the existing string
      catalogs.~~ **Shipped 2026-07-23** across iOS + tvOS via the String Catalogs (PR #40);
      `300/spec.md` carries the amendment. Repo policy is unchanged — Swift source, comments,
      specs and docs stay English, and German lives only in the catalogs.
- [ ] **Pre-explain permission prompts** — amendment to `220` (`220/spec.md:257`). Low-priority
      polish that directly serves the ease-of-use goal.

---

## 4. Docs debt

- [ ] `spec-traceability.md` has **no sections for 110, 210, or 710**, all shipped — `120` gained
      one on 2026-07-19 (FR-120-12 only), after this line was written. (1000's is owned by task
      `1000/T025`; `1100` has no section either.) No task owns the rest.
- [ ] The traceability tables still mark FR-300-08, FR-300-29 and others `missing` although they
      shipped as 320/510 — the header now warns about this, but the rows themselves are stale.

---

## 5. Explicitly out of scope here

Apple TV (`1000`) work — the iCloud entitlements + `SecretSyncStoreFactory` flag flip, the
SC-1000-08 CloudKit decrypt proof, KVS restore on hardware, real-broker HA parity, the 24 h soak,
the tvOS device-signing fix, the tvOS clock overlay + FR-1000-10 pixel-shift contract, the tvOS
UI-test harness (`XCUIRemote` + a `--uitest` seam — currently no FR covers it), the
`config-sync.md` contract drift, and the review's cleanup tail. See `specs/1000-apple-tv/`.

---

## Recommended order

1. **Section 0** — rescue both at-risk documents. Twenty minutes; removes two single points of
   failure.
2. **`1100` monetization** — spec, then implement. Nothing ships publicly until this exists.
3. **Device day** — one session, four specs' gates.
4. **Section 2** — the secret-hygiene test and the QR-in-Settings FR; both small enough to ride
   alongside other work.
5. **Section 3** — post-release, in listed order.
