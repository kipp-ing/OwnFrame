# Feature Specification: Design Language — Appearance, Type, Layout, Vocabulary

**Feature Branch**: `9000-design-language`

**Created**: 2026-09-01

**Status**: Active — the governing language spec. Written **after** the design canvas, as the record
of what it converged on, not as guesswork ahead of it. Nothing here is implemented yet: the app
forces no color scheme (`preferredColorScheme` and `colorScheme` appear in **zero** Swift files),
`AccentColor.colorset` declares no color, and the album picker is still `.listStyle(.plain)`
(`OwnFrame/Onboarding/AlbumPickerView.swift:49`). Requirement IDs are `FR-9000-NN` / `SC-9000-NN`.
Application to specific screens is **not** owned here — see FR-9000-35.

**Input**: The first four-digit block. `100`–`1200` are product modules mirroring Swift packages; a
design language is not a module, so supporting processes get a clearly separated **9000** block
using the same `N` / `N10` / `N20` sub-spec convention scaled to four digits
([`docs/spec-overview.md`](../../docs/spec-overview.md) § Structure & numbering). Interactive design
record: the **OwnFrame Redesign canvas of 2026-09-01** — seven artboards (Willkommen · Link einfügen
· Server verbinden · Album auswählen · Diashow läuft, plus a *Design Language* sheet and a
*Wortschatz* DE/EN vocabulary table) at
<https://claude.ai/code/artifact/b5f6cd64-2a53-4a8f-85ea-0c2ead63b8bc>, with a phone-readable mirror
(same designs, no canvas editor) at
<https://claude.ai/code/artifact/1992f317-b498-48e0-b725-ca297113abcb>. This is the same
relationship [`docs/design/quiet-glass-2026-07-18.html`](../../docs/design/quiet-glass-2026-07-18.html)
has to specs [500](../500-display-options/spec.md) and [510](../510-clock-overlay/spec.md): the
artifact is the design record, the spec is the binding statement of it. Work-package narrative:
[`docs/presentation-overhaul-plan.md`](../../docs/presentation-overhaul-plan.md) (AP-U, AP-0).
Directional input, explicitly **not** a target:
[`Design/Reference/README.md`](../../Design/Reference/README.md).

## Overview

v1.1 is `READY_FOR_SALE` in **0 of 175 territories** — held back because the app talks like
infrastructure and looks like unfinished software. This spec fixes the language, once, in one place,
for **both** the app UI and the store copy, so the two cannot drift apart. It does not redesign any
screen: the screens are owned by their product specs, and this spec is what they must comply with.

Three things make it binding rather than decorative. It **names real strings** that exist in the
shipped catalogs today, so a requirement can be failed against the tree rather than argued about.
It **fixes numeric tokens** (type scale, surfaces, radii, hit targets, the content-column cap) rather
than adjectives. And it **records what the canvas did not decide** — the accent hue, the empty and
error states — as open items with owners, instead of letting a gap read as a settled answer.

## Clarifications

### Session 2026-09-01

- Q: Does the UI overhaul (AP-U) get its own hundreds-block? → A: **No.** It applies this spec and
  amends the product specs that own the affected screens —
  [`210-shared-link-onboarding`](../210-shared-link-onboarding/spec.md) (the shared album picker) and
  [`220-onboarding-welcome`](../220-onboarding-welcome/spec.md) (the welcome screen). This respects
  the repo's "a single concern lives in exactly one spec" rule. 220's own `Roadmap / Deferred`
  already anticipates this: *"Reskinning downstream steps — … a full onboarding visual refresh is a
  separate, later concern."* Recorded as FR-9000-35. **Those two specs are deliberately not edited
  in this session**; the amendment is downstream work.
- Q: Register — custom visual identity, or stock? → A: **Native, but warm.** Stock iPadOS components
  (inset-grouped lists, SF Symbols, system materials). The warmth comes from vocabulary, whitespace
  and photography, not from custom widgets. This keeps every requirement implementable on the
  **iOS 17** deployment floor (`IPHONEOS_DEPLOYMENT_TARGET = 17.0`).
- Q: Appearance? → A: **Always dark, app-wide.** Photographs carry every screen and the frame
  recedes; it also matches the slideshow chrome, which is already white-on-dark. Known cost, recorded
  as a risk: a bright room during setup is less legible (FR-9000-07, SC-9000-03).
- Q: Which accent color? → A: **Messing `#E3A857`** — Jan's decision, 2026-09-01. The canvas'
  language sheet said only *"Accent — one warm hue, pick on the artboards"* and offered three
  candidates against today's blue; its artboards all rendered in Messing, and that hint is now the
  decision. Recorded in FR-9000-14, which also carries the contrast consequence.
- Q: The canvas' album-picker artboard shows a checkmark on a row and a pinned bar reading
  *"1 Album ausgewählt"*. Does the picker become multi-select? → A: **No.** The picker's interaction
  model is owned by `210` and is unchanged: sources are added one at a time, and the pinned bar is
  the shape the shipped `AddedSourcesBar` already provides. The artboard is a **restyle**, not an
  interaction change. If implementation concludes the drawn pattern genuinely requires multi-select,
  that is a `210` amendment and must be specced there — never smuggled in as styling (FR-9000-35).
- Q: The canvas contradicts itself on some numbers (headline 40/46 and 36/42 on the artboards vs.
  `largeTitle` 34/41 on its own language sheet; button radius 12 on the sheet vs. 14 on the
  artboards; background `#000000` on the flow screens vs. `#0A0A0B` on the reference sheets). Which
  wins? → A: **The Design Language sheet wins** for every numeric token. The artboards are
  illustrations of the language; the sheet is the statement of it.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - A newcomer reaches a running slideshow without meeting a word they must look up (Priority: P1)

Someone who has never heard of Immich installs the app, is asked *where their photos are* rather than
to *add a source*, picks an album from a list that shows the photographs it contains, and watches the
slideshow start. Nothing on the way there uses a noun they would have to search for.

**Why this priority**: This is the release blocker. The app currently opens with "Add a source" and
explains itself with "server address and API key".

**Independent Test**: Walk the first-run path in both locales and collect every visible string. None
of the terms in FR-9000-23 appears on any screen before the server-connection screen.

**Acceptance Scenarios**:

1. **Given** a clean install, **When** the welcome screen appears, **Then** it asks where the user's
   photos are and offers the three shipped paths in friction order, and the words "API key",
   "server address" and "instance" appear on none of them.
2. **Given** the album picker, **When** it lists albums from a source that supplies covers,
   **Then** each row shows a photograph, the album's name, and a plain photo count.
3. **Given** any first-run screen, **When** it is read in German, **Then** it addresses the user as
   *du* (FR-9000-22) and uses the vocabulary fixed in FR-9000-29.

---

### User Story 2 - The store page and the app say the same words (Priority: P1)

A buyer reads "Album auswählen" on the store page, installs the app, and meets "Album auswählen".
Nothing was renamed between the pitch and the product.

**Why this priority**: A store page written in different words than the app it sells is the drift
this block exists to prevent; it is also why the store spec is a *sub-spec* of this one rather than a
sibling.

**Independent Test**: Take every noun on the shipped store slots and find it, or its deliberate
counterpart, in the vocabulary table.

**Acceptance Scenarios**:

1. **Given** a term retired in FR-9000-29, **When** the store listing is searched, **Then** the
   retired term does not appear there either.

---

### User Story 3 - A reviewer can fail a change against this spec (Priority: P2)

A contributor adds a screen. A reviewer can point at a requirement — a named term, a numeric token,
a named surface color — rather than at taste.

**Why this priority**: A design-language spec that is only adjectives cannot be enforced and rots
into decoration within one session.

**Independent Test**: Every FR in this spec can be checked either by grepping the tree, by reading a
declared asset, or by a screenshot at a stated size. No FR requires a judgement of beauty.

**Acceptance Scenarios**:

1. **Given** a pull request that introduces a hardcoded point size for body text, **When** it is
   reviewed, **Then** FR-9000-10 is the citable ground for rejecting it.

### Edge Cases

- A bright room during setup with an always-dark UI — the recorded cost of FR-9000-05.
- An album with no cover asset, or a Photos source under *Selected Photos* limited access, where a
  photographic row cannot be filled.
- A German string that is materially longer than its English source and breaks a fixed-width row.
- An accessibility text size that turns a two-line headline into five.
- A term retired in `OwnFrame/Localizable.xcstrings` but still alive in one of the four other
  catalogs.

## Requirements *(mandatory)*

### Functional Requirements

#### Scope and authority

- **FR-9000-01**: This spec is the single governing design language for **both** the app UI and all
  public store copy. Any surface that a user or a buyer reads is in scope.
- **FR-9000-02**: This spec governs *appearance, type, layout, tone and vocabulary*. It MUST NOT
  define or change any interaction model, navigation structure or feature behaviour — those remain
  owned by the product specs (`100`–`1200`). Where this spec and a product spec appear to conflict on
  behaviour, the product spec wins and this spec MUST be amended.
- **FR-9000-03**: Every requirement here MUST be checkable against the tree, a declared asset, or a
  screenshot at a stated size. Requirements phrased only as adjectives ("warm", "clean", "modern")
  MUST NOT be added to this spec.
- **FR-9000-04**: The design record for this language is the **OwnFrame Redesign canvas of
  2026-09-01** cited in `Input`. Where this spec states a value, this spec is binding; where it is
  silent, the canvas is the reference — and where the canvas is silent (see FR-9000-31), the gap MUST
  be recorded rather than filled by improvisation.

#### Appearance

- **FR-9000-05**: The app MUST present a **dark appearance app-wide**, on every screen and every
  platform target, regardless of the system setting. "App-wide" reaches only surfaces the app itself
  draws: system-rendered UI — permission alerts, the share sheet, the system photo picker — follows
  the *system* appearance and cannot be forced. Those are out of scope, not violations.
- **FR-9000-06**: The dark appearance MUST be declared at an **app root**, never per-screen —
  exactly one declaration per `@main` entry point. There are **two** entry points, so there are two
  declarations, not one: `OwnFrame/OwnFrameApp.swift:26` (iOS/iPadOS) and
  `OwnFrameTV/TVRootView.swift:28` (tvOS). Today no Swift file references `preferredColorScheme` or
  `colorScheme` at all, so both are new.
- **FR-9000-07**: Because a photo frame is set up in daylight, onboarding screens MUST meet at least
  **WCAG AA contrast (4.5:1 for body text, 3:1 for large text and meaningful icons)** against their
  own background. This is the specific mitigation for the known cost of FR-9000-05.
- **FR-9000-08**: Photographs MUST never be tinted, dimmed or overlaid by the appearance choice
  beyond what a legibility gradient behind overlaid text requires.

#### Typography

- **FR-9000-09**: Type MUST be **SF Pro**, the system face. SF Pro **Rounded** MUST NOT be used —
  the design record names plain SF Pro only.
- **FR-9000-10**: Text MUST use **stock Dynamic Type text styles**, not hardcoded point sizes, so
  Dynamic Type stays intact. The role scale recorded by the design record is: `largeTitle` 34/41
  bold (screen headline), `title2` 22/28 semibold (section headline), `headline` 17/22 semibold (row
  title), `body` 17/22 regular (explanatory copy), `subheadline` 15/20 regular, muted (row detail).
- **FR-9000-11**: Only these five roles are defined. A screen needing a sixth role MUST amend this
  spec rather than invent one locally.
- **FR-9000-12**: Muted secondary text MUST be a single defined level (the design record uses 60%
  white on the dark ground), applied consistently — not an ad-hoc opacity per screen.

#### Color and tint

- **FR-9000-13**: The app MUST declare **exactly one accent color** in
  `OwnFrame/Assets.xcassets/AccentColor.colorset`, and every tint MUST derive from it. Today that
  colorset declares **no** color, so the app's blue is an omission rather than a decision — that is
  the defect this requirement closes.
- **FR-9000-14**: The accent hue is **Messing `#E3A857`** (decided 2026-09-01). It MUST be the value
  declared in `AccentColor.colorset` per FR-9000-13. Recorded for provenance: it was chosen over
  *Terrakotta* `#E08C6A` and *Gletscher* `#5AC8C8`, against today's default `#0A84FF`.
  **Consequence, binding on FR-9000-19:** Messing is a *light* hue — relative luminance 0.45 — so it
  carries **10:1 against the `#000000` ground**, comfortably past FR-9000-07, but only **2.1:1 under
  white text**, which fails AA. A filled control tinted Messing MUST therefore carry a **near-black
  label**, never a white one. Messing as text, icon or stroke *on* the dark ground is unrestricted.
- **FR-9000-15**: Surfaces MUST come from the named system-role palette recorded by the design
  record: `systemBackground` `#000000`, `secondarySystemGroupedBackground` `#1C1C1E`, the tertiary
  grouped surface `#2C2C2E`, and `quaternaryFill` `rgba(118,118,128,0.24)`. Arbitrary greys MUST NOT
  be introduced.
- **FR-9000-16**: Separators MUST use the recorded hairline (`rgba(84,84,88,0.55)`) and MUST be
  **inset to the text column**, not run edge to edge.

#### Layout, hierarchy and photography

- **FR-9000-17**: Text and form content MUST be constrained to a centred content column of
  **640–720pt**. Today nothing constrains width, so fields stretch the full 1032pt of a 13" iPad —
  the single largest contributor to the "unfinished software" impression.
- **FR-9000-18**: Lists of content MUST be **inset-grouped, never plain**. The shipped album picker
  is `.listStyle(.plain)` (`OwnFrame/Onboarding/AlbumPickerView.swift:49`), which is why it runs edge
  to edge.
- **FR-9000-19**: A screen's primary action MUST be a **filled, pinned** control. A primary action
  MUST NOT be rendered as plain text in a row, where it reads as a placeholder.
- **FR-9000-20**: Wherever a list of **photo containers** (albums, sources) is presented, each row
  MUST show a photograph of its contents when the source can supply one. Covers arrive as **3:2
  landscape WebP** (verified against the live server, API v3.1.0: `album.albumThumbnailAssetId`,
  `image/webp`, 375×250, ~18 KB) and MUST be **aspect-filled into a 68pt rounded square** — the
  square is a crop, not a native size. Covers MUST load per row with caching and scroll
  cancellation, and a row whose cover is missing or not yet loaded MUST render a neutral placeholder
  of the same geometry rather than collapse the layout. **This requirement is not satisfiable
  today**: `Album` (`Packages/ImmichClient/Sources/ImmichClient/Models.swift:3-73`) decodes only
  `id`, `albumName`, `assetCount`, `startDate` and `endDate` — it does **not** carry
  `albumThumbnailAssetId`. Adding that field is part of satisfying this requirement; the fetch path
  it feeds already exists (`ImmichClient.swift:91-95`).
- **FR-9000-21**: Interactive targets MUST be **at least 44pt**; corner radii MUST come from the
  set **12 / 14 / 18**; the album row's cover is 68pt with its separator inset past it.

#### Vocabulary and register

- **FR-9000-22**: German MUST address the user informally as **du**, and English in the second
  person, consistently across app and store — matching what already ships in the listing.
- **FR-9000-23**: **No first-run screen** — welcome, source choice, shared-link entry, album picker,
  Photos picker, confirm — may contain any of these terms in either locale: **"API key" /
  "API-Schlüssel"**, **"server address" / "Serveradresse"**, **"instance" / "Instanz"**, **"Add a
  source" / "Quelle hinzufügen"**. All four are shipped strings today
  (`Onboarding/ConnectionFieldsView.swift:43,61`, `Onboarding/ConnectionStepView.swift:19,30,31`,
  `Onboarding/OnboardingChoiceView.swift:53`, `Onboarding/SourceStepView.swift:78`). The single
  exemption is the server-connection screen, per FR-9000-24.
- **FR-9000-24**: The **server-connection screen is the one screen permitted to carry technical
  vocabulary**, and even there each term MUST be framed as *where to find something*, not as assumed
  knowledge — an address field labelled plainly, an access-key field that says where in Immich the
  key lives. Protocol-level words such as "HTTPS" MUST appear only on that screen and only as a
  constraint on what may be typed there; they MUST NOT appear in a first-run validation error shown
  before that screen is reached.
- **FR-9000-25**: On the Settings surface, **"Broker" and "MQTT" MUST be demoted behind a
  recognisable noun** ("Smart Home" / "Smart home"), with the protocol name available only where a
  user is actually configuring it (`Slideshow/SlideshowSettingsView.swift:312,316,318,328,336,339`,
  `Slideshow/BrokerSetupView.swift`, and the tvOS equivalents). *Note of record:* the phrase
  **"Storage budget" does not exist** as a shipped string — the audit of 2026-09-01 refuted it. The
  real labels are the section **"Storage"** and the row **"Maximum size"**
  (`Slideshow/SlideshowSettingsView.swift:401,410`); "budget" survives only in an accessibility
  identifier and in code comments. No requirement may be written against the non-existent phrase.
- **FR-9000-26**: **One concept, one name.** The Apple Photos source is currently called three
  different things depending on entry point — "iCloud album" (`Onboarding/OnboardingFlowView.swift:46`),
  "Photos album" (`Onboarding/SourceStepView.swift:44`, `Slideshow/SourceLibraryView.swift:159`) and
  bare "Photos" (`Slideshow/SourceLibraryView.swift:324`). Exactly one MUST survive, used everywhere
  including the store listing. Where the underlying capability is PhotoKit, copy MUST say "albums
  from your Photos library, including iCloud Shared Albums" and MUST NOT say "connects to iCloud".
- **FR-9000-27**: **Screen titles MUST name the user's goal, not the system's operation.** The
  mechanical half: each of the titles named below MUST change, and its replacement MUST appear as a
  row in the vocabulary table (FR-9000-29) before it ships. Today's
  titles include "Add a source", "Get started", "Setup", "Confirm", "Sources", "Add source"
  (`Onboarding/SourceStepView.swift:78,166`, `Onboarding/OnboardingChoiceView.swift:59`,
  `Onboarding/OnboardingFlowView.swift:61`, `Slideshow/SourceLibraryView.swift:66,199`). A title that
  describes what the software does to its own data model MUST be replaced by one that describes what
  the person is doing.
- **FR-9000-28**: Row detail lines MUST carry only what a person chooses by. The album picker's
  subtitle is built at `OwnFrame/Onboarding/AlbumPickerView.swift:105-114` as an optional year or
  year-range joined to a photo count by `" · "` (e.g. `2019 · 3 photos`); the **bare year MUST be
  dropped** and the plain photo count kept, since the photograph now carries recognition.
- **FR-9000-29**: The vocabulary recorded on the canvas' *Wortschatz* sheet is the **binding
  DE/EN table** for the terms it covers. Its rows are grouped by surface (welcome, album picker,
  shared link, server, settings, shared) and each carries today's German, the proposed German, the
  proposed English, and a status of *new* (`neu`), *retired* (`entfällt`) or *unchanged* (`bleibt`).
  **Three** rows are marked *unchanged* because they are already right — "Alben durchsuchen" /
  "Search albums", "Weiter" / "Continue", and "Diashow starten" / "Start slideshow". *(The
  record's own footnote says "two"; the table says three. The table wins, per FR-9000-04.)* A term
  marked **retired** MUST NOT reappear anywhere in app or store copy.

#### Empty and error states

- **FR-9000-30**: Empty and error states MUST use the same register as the rest of the app: state
  plainly what happened, say what the person can do next, and never expose a protocol name, status
  code or internal identifier. Existing calm examples that already satisfy this — "No albums on this
  server" plus "Add a shared link instead."
  (`Onboarding/AlbumPickerView.swift:36,38`) — are the model, not the exception.
- **FR-9000-31**: **Recorded gap:** the design record shows **no** empty state and **no** error state
  across its seven artboards. Empty and error visuals are therefore specified here only as the tone
  rule above; their layout MUST be designed before the screens that need them are reworked, and the
  result recorded against this spec (see `Roadmap / Deferred`).

#### Localization mechanics

- **FR-9000-32**: English is the source language. All specs, docs, code comments and **Swift string
  literals MUST be English**; German ships **only** through String Catalogs. This is enforced by
  `.claude/scripts/check-english-only.sh` and MUST NOT be relaxed to make a German mock literal.
- **FR-9000-33**: A vocabulary change is a **two-locale change**, and the German is **authored, not
  translated**. Because "authored" cannot be read off an artefact, the checkable proxy is this: every
  German term for a concept this spec governs MUST appear in the vocabulary table (FR-9000-29)
  *before* it appears in a catalog, and the table's DE column — not the EN column — is the source for
  it. A change that lands an English string without a table row for its German counterpart is
  incomplete.
- **FR-9000-34**: A vocabulary change MUST be swept across **all five** shipped catalogs, not only
  the main one: `OwnFrame/Localizable.xcstrings` (**229** keys), `OwnFrameTV/Localizable.xcstrings`
  (57), `OwnFrame/AppShortcuts.xcstrings` (7),
  `Packages/PurchaseKit/Sources/PurchaseKit/Localizable.xcstrings` (45), and
  `Packages/OnboardingKit/Sources/OnboardingKit/Localizable.xcstrings` (13) — **351 keys total**. A
  term retired on one surface MUST NOT survive on another.

#### Governance

- **FR-9000-35**: **AP-U — the UI overhaul — does not get its own spec block.** It applies this spec
  and amends the product specs that own the affected screens: `210-shared-link-onboarding` for the
  shared album picker (which owns its search and interaction contract, FR-210-19) and
  `220-onboarding-welcome` for the welcome screen. New *behaviour* discovered while applying this
  language MUST be specced in the owning product spec, never absorbed here as "styling".
- **FR-9000-36**: Store copy is governed by this spec through its sub-spec
  [`9010-store-presentation`](../9010-store-presentation/spec.md). A term retired here is retired in
  the listing; a term introduced in the listing MUST exist in the app.
- **FR-9000-37**: When the language itself changes, the **design record MUST be updated or
  superseded** and this spec's `Input` re-pointed. A language change that lives only in a commit
  message is not a language change.

### Key Entities

- **Design record**: the OwnFrame Redesign canvas of 2026-09-01 (seven artboards; phone-readable
  mirror). The source of truth this spec transcribes, in the same relationship `quiet-glass` has to
  500/510.
- **Type scale**: five Dynamic Type roles (`largeTitle`, `title2`, `headline`, `body`,
  `subheadline`) with recorded sizes and weights.
- **Surface palette**: four named system-role surfaces plus one separator hairline.
- **Accent**: the single declared tint in `AccentColor.colorset`. Currently undeclared; hue pending.
- **Vocabulary table**: the DE/EN *Wortschatz* sheet, grouped by surface, statuses *new* / *retired*
  / *unchanged*.
- **String catalogs**: the five shipped `.xcstrings` files, 351 keys, `sourceLanguage: en`.

## Success Criteria *(mandatory)*

- **SC-9000-01**: Walking the first-run path end to end in **both** locales, no screen before the
  server-connection screen contains "API key" / "API-Schlüssel", "server address" / "Serveradresse",
  "instance" / "Instanz", or "Add a source" / "Quelle hinzufügen" — verifiable by collecting the
  screens' strings, not by opinion.
- **SC-9000-02**: A grep of the tree finds exactly one dark-appearance declaration per `@main` app
  root — two in total, iOS and tvOS — and no per-screen appearance overrides.
- **SC-9000-03**: Onboarding screens measure at least 4.5:1 contrast for body text and 3:1 for large
  text and meaningful icons against their own background.
- **SC-9000-04**: `AccentColor.colorset` declares `#E3A857`, no view sets a tint that does not derive
  from it, and no accent-filled control renders a white label.
- **SC-9000-05**: No shipped view hardcodes a point size for text; every text role resolves through a
  stock Dynamic Type style, and the first-run path shows no truncation at an accessibility text size.
- **SC-9000-06**: On a 13" iPad, no text or form field on a first-run screen exceeds the 640–720pt
  content column, and no content list uses `.listStyle(.plain)`.
- **SC-9000-07**: In the album picker, every row whose source supplies a cover shows a photograph;
  rows without one show a same-geometry placeholder; scrolling a 16-album list cancels in-flight
  cover loads and does not stall.
- **SC-9000-08**: Every term marked *retired* in the vocabulary table returns **zero** hits across
  all five string catalogs **and** across `docs/app-store-listing.md`.
- **SC-9000-09**: The Apple Photos source is referred to by exactly one name across onboarding,
  Settings and the store listing; the phrase "connects to iCloud" appears nowhere.
- **SC-9000-10**: Every user-visible German string that changed has an authored German value present
  in its catalog, with no key left carrying only its English source text where German is expected.
- **SC-9000-11**: `check-english-only.sh` passes — no German in any Swift source — with all
  vocabulary changes landed.
- **SC-9000-12**: A reviewer can reject a non-conforming change by citing an FR number here, without
  appealing to taste; every FR in this spec is checkable by grep, by a declared asset, or by a
  screenshot at a stated size.

## Assumptions

- Stock iPadOS components carry the whole language. No custom control is needed, and therefore
  nothing here forces work above the **iOS 17** floor.
- The canvas' `Wortschatz` sheet reports today's German accurately; the audit of 2026-09-01 confirmed
  its key count (229 in the main catalog) and its `.listStyle(.plain)` and album-subtitle claims
  against the tree.
- Album covers remain available from Immich as `albumThumbnailAssetId` and remain cheap
  (~18 KB apiece, so a 16-album picker costs ~300 KB). WebP decodes natively via `UIImage` since
  iOS 14, below our floor.
- QR scanning already ships (`Onboarding/SharedLinkSetupView.swift:53`, `Onboarding/QRScannerView.swift`),
  so the canvas' "QR-Code scannen" affordance is a **rename of an existing feature**, not a new
  capability — it introduces no new API requirement against the iOS 17 floor.
- The always-dark decision is a product decision, not a user setting. No appearance toggle is
  assumed, offered, or reserved.

## Dependencies

- **[210-shared-link-onboarding](../210-shared-link-onboarding/spec.md)** — owns the shared album
  picker, including its search contract (FR-210-19: filter by name, date and photo count). FR-9000-28
  changes what a row *displays*; any change to what it *filters on* is a 210 amendment.
- **[220-onboarding-welcome](../220-onboarding-welcome/spec.md)** — owns the welcome screen and its
  three friction-ordered paths (FR-220-01). Its `Roadmap / Deferred` already reserves the visual
  refresh this spec governs.
- **[900-photo-library-source](../900-photo-library-source/spec.md)** — owns the Photos/iCloud source
  whose naming FR-9000-26 unifies, including the limited-access behaviour that can leave a
  photographic row unfillable.
- **[1100-purchase-gate](../1100-purchase-gate/spec.md)** — owns the commercial language constraints
  that store copy inherits through `9010`.
- **[9010-store-presentation](../9010-store-presentation/spec.md)** — the sub-spec that applies this
  language to the App Store asset set.

## Roadmap / Deferred

- **Empty and error state layouts** — the design record covers none (FR-9000-31). Only the tone rule
  is binding today; the visual pattern is unspecified and must be designed before the screens that
  need it are reworked.
- **Surfaces the canvas never drew** — Settings, the source library, broker setup, the unlock and tip
  screens, the slideshow chrome, and the whole tvOS surface. FR-9000-05's "app-wide" is binding for
  all of them, but their type, layout and vocabulary detail is extrapolated rather than recorded, and
  each will need a pass of its own.
- **Fixture album names** — the store capture shows `Album 1 … Album 16`
  (`OwnFrame/OwnFrameApp.swift:947`), which reads as unfinished software. Believable German names
  cannot be Swift literals under FR-9000-32 and would have to enter the shipping String Catalog as
  test-fixture data. The trade-off is unresolved; likely folded into the AP-U picker rework.
- **A tokens artefact** — the numeric values here (type scale, surfaces, radii, the content-column
  cap) live only as prose. Promoting them to a single shared Swift constants surface, so a reviewer
  can diff a value rather than a paragraph, is deferred.
- **Motion and haptics** — deliberately out of scope. The design record says nothing about
  transitions between onboarding screens, and this spec does not invent them.
