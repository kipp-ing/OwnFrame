# Gap-Closure Plan

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
      only record of a fully-formed, release-blocking product decision. Commit it under `docs/`
      or distil it into the `1100` spec below.
- [ ] **The "Quiet Glass" design artifact** is cited as the design source of truth by four specs
      — `510/spec.md:18`, `510/research.md:3`, `500/spec.md:69`, `510/tasks.md:82` — and does not
      exist in the repo. It lives in a chat artifact. Recover and commit it before speccing `330`.

---

## 1. Critical path to first public release

Only two things block shipping publicly. Everything in sections 2–5 is post-release.

### 1a. Monetization → new spec `1100`

Next free hundreds-block (`1000` is taken). This is a new module — a new gating seam that every
paid capability area reads — not an amendment.

**Current state**: no spec, no plan, no tasks, **no StoreKit code of any kind** (no `StoreKit`
import, no `.storekit` config, no IAP entitlement). `docs/app-store-listing.md` has no price or
IAP section and reads as a free app throughout. The legal half of the plan *did* ship — `LICENSE`
is FSL-1.1-MIT and the README/listing carry the Fair Source line.

**Sequencing constraint (from the research, and the reason this is urgent):** v1.0 build 8 is
approved-but-unreleased and includes HA/MQTT for free. Never claw back a shipped-free feature —
so the gated build must be the *first version the public ever sees*. Releasing b8 as-is forecloses
the option.

- [ ] Spec + plan + tasks: which capability areas gate (research proposes a polish tier and an
      automation tier), the purchase / restore / Family-Sharing surface, and the entitlement seam.
- [ ] Implement TDD-first behind a `PurchaseGating`-style protocol with an in-memory fake, so the
      gating logic is host-testable without StoreKit — same pattern as `ImmichAPI` and
      `CodeScanning`.
- [ ] Update `docs/app-store-listing.md` (price + IAP), and the live ASC description, which still
      says "Open source (MIT)" after the FSL switch — it must ride along with the next version's
      metadata.

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
- [ ] **QR when adding a source later.** The scanner is complete and unguarded; it is simply only
      wired to one view. `SharedLinkSetupView` has the Scan-QR button; the shared
      `SharedLinkAddForm` — used by Settings → Sources → + *and* by onboarding step 2 — does not.
      Deliberately out of scope for 220 (FR-220-07; `220/research.md` R7) and never picked up
      since, so it needs **a new FR in `120`** before implementation.
      Lift the scanner state, button, `.fullScreenCover`, and `startScan()` from
      `SharedLinkSetupView.swift:22-23,50-56,92-96,130-147` into `SharedLinkAddForm.swift`,
      calling the already-public `SourceLibraryViewModel.addScannedSharedLink(using:label:)`.
      One design decision: `SharedLinkAddForm` offers an optional name field while `startScan()`
      hardcodes `label: ""` — thread the typed label through instead of discarding it.

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
- [ ] **German localization (FR-300-30)** — `300/spec.md:191` requires each roadmap item to be
      scheduled as its own Spec Kit feature. Translation pass over the existing string catalogs.
- [ ] **Pre-explain permission prompts** — amendment to `220` (`220/spec.md:257`). Low-priority
      polish that directly serves the ease-of-use goal.

---

## 4. Docs debt

- [ ] `spec-traceability.md` has **no sections for 110, 120, 210, or 710**, all shipped. (1000's
      is owned by task `1000/T025`.) No task owns these four.
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
