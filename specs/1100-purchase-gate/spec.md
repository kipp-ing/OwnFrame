# Feature Specification: Purchase Gate & One-Time Unlocks

**Feature Branch**: `1100-purchase-gate`

**Created**: 2026-07-19

**Status**: Draft — amended 2026-07-19: **Ken Burns motion + clock overlay form the Pro launch
composition** (decided with Jan; possible because no version was ever publicly released, so the
never-claw-back rule does not yet bind anything). Locked-row presentation refined the same day:
dimmed is fine, but locked rows must carry a lock/tier badge and stay tappable. Amended
2026-07-20: **Home Assistant telemetry is free, only *control* is gated** — an unentitled frame
with a broker configured connects and publishes read-only sensor entities so HA can see it,
while controllable entities + command handling + App Intents stay behind the Automation unlock
(FR-1100-03 / FR-1100-03a; US5 and SC-1100-06 restated accordingly). This widens the free tier
and never claws anything back.

**Input**: User description: "Monetization / purchase gate (one-time In-App Purchases). Free
tier keeps the full adoption funnel: all photo sources and clean core playback with all
currently-built playback settings. Two paid one-time unlocks — Pro (ambience pack, built from
new not-yet-shipped features) and Automation (HA/MQTT + App Intents/Shortcuts) — plus an
optional everything-bundle. One-time purchases only, no subscriptions ever, never the word
'lifetime'; tip jar allowed; Family Sharing on; never-claw-back; the gated build must be the
first version the public ever sees. Gated features visible but locked, no dark patterns;
entitlements cached locally so an unattended frame works offline; restore supported; universal
purchase across iPad/iPhone/Apple TV; pre-gate broker config degrades gracefully. No price
points in this spec."

> **Scope note (public repository).** This spec deliberately contains **no price points, no
> revenue expectations, and no launch coordination**. Prices are set in App Store Connect at
> submission time and never recorded in this repository. This spec covers only the tier
> boundaries, the gating behaviour, and the binding constraints.

## User Scenarios & Testing *(mandatory)*

### User Story 1 - The free frame stays whole (Priority: P1)

A new user sets up a frame the usual way — scans a shared-link QR, pastes a link (with or
without password), connects a server with an API key, or picks iCloud/device photos — and gets
the complete core slideshow experience without paying, without an account, and without ever
being asked to pay during setup or playback. The free tier is the product's adoption funnel
and must feel like a finished product, not a trial.

**Why this priority**: The free core loop is the only distribution channel this app has
(word of mouth in the self-hosted community). If the gate leaks into the core experience,
the funnel dies and the paid tiers have nothing to convert from.

**Independent Test**: Fresh install with no purchases. Complete each onboarding path, play a
slideshow for an extended period, visit every settings screen reachable in the free flow.
Zero purchase prompts appear without an explicit tap on a locked feature; every free-tier
capability works.

**Acceptance Scenarios**:

1. **Given** a fresh install with no purchases, **When** the user onboards via shared link
   (incl. QR scan and password-protected links), server + API key, or iCloud/device photos,
   **Then** onboarding completes with no purchase prompt, no account requirement, and no
   trial framing.
2. **Given** a free user in a running slideshow, **When** playback runs for hours (transitions,
   shuffle, fit/fill, duration settings, dimming, keep-awake, offline cache, auto-retry all in
   use), **Then** no purchase-related UI ever appears on its own.
3. **Given** a free user browsing settings, **When** they view locked features, **Then** the
   locked features are visible and labelled as one-time unlocks, but nothing blocks or
   overlays the free settings.

---

### User Story 2 - Unlock a paid tier (Priority: P1)

A user who wants remote control (or the ambience pack) taps the locked feature, sees a single
clear unlock screen with the one-time price, buys, and the feature activates immediately —
no restart, no re-onboarding.

**Why this priority**: This is the revenue path; it must work end to end before the gated
build can be the first public release (the sequencing constraint below makes the gate itself
release-blocking).

**Independent Test**: In a sandbox store environment, purchase each product (Pro, Automation,
bundle) from the unlock screens — reached via a locked row or the settings Unlocks section —
and verify immediate activation without app restart.

**Acceptance Scenarios**:

1. **Given** a free user on a locked feature's unlock screen, **When** they complete the
   purchase, **Then** the feature becomes usable immediately (no restart) and the locked
   labels for that tier disappear everywhere in the app.
2. **Given** a user who owns one tier, **When** they view the other tier's unlock screen,
   **Then** owned content is shown as owned and only the missing unlock is offered.
3. **Given** a purchase that fails or is cancelled, **When** the user returns to the app,
   **Then** the app remains fully functional in its free state with no nagging follow-up
   prompt.
4. **Given** a purchase that ends in a pending/approval state (e.g. a family "ask to buy"
   flow), **When** approval arrives later, **Then** the entitlement activates without the
   user repeating the purchase.

---

### User Story 3 - An unattended frame never loses its purchases (Priority: P1)

A frame runs on a wall for months — sometimes offline, sometimes power-cycled. Purchases,
once made, keep working across restarts and arbitrary offline periods without any network
re-validation step that could relock a feature.

**Why this priority**: The product's core promise is unattended operation. A frame that
relocks its paid features because it couldn't phone home is a broken frame — worse than not
selling the feature at all.

**Independent Test**: With entitlements active, disconnect the device from the network,
restart the app and the device repeatedly over a soak period; all owned features stay active
throughout.

**Acceptance Scenarios**:

1. **Given** a device with active entitlements, **When** the app is relaunched with no
   network connectivity, **Then** all owned features are active immediately at launch.
2. **Given** an entitled frame running offline for an extended period (days), **When** it is
   power-cycled, **Then** owned features remain active with no user interaction.
3. **Given** the store reports a refund/revocation of an unlock, **When** the app next
   successfully refreshes entitlements, **Then** the affected features relock gracefully
   (settings and data preserved, no crash, no interruption of a running slideshow beyond the
   feature itself stopping).

---

### User Story 4 - Purchases follow the household, not the device (Priority: P2)

A user buys an unlock on their iPhone and expects it on the family iPad frame and the Apple TV:
restore purchases works on reinstall and new devices, Family Sharing extends unlocks to family
members, and one purchase covers iPad, iPhone, and Apple TV.

**Why this priority**: "Buy on my phone, run on the family's frame iPad" is the literal
primary use case; without it the gate punishes exactly the multi-device household the app is
for. It is P2 only because the mechanics largely ride on platform behaviour once products are
configured correctly.

**Independent Test**: Purchase on one device/account; verify activation via restore on a
second device with the same account, on a family member's account via Family Sharing, and on
Apple TV under the shared app identity.

**Acceptance Scenarios**:

1. **Given** a user who purchased on another device, **When** they install the app on a new
   device and use "Restore Purchases", **Then** all owned unlocks activate with zero
   reconfiguration.
2. **Given** a family member in the same family group, **When** they install the app,
   **Then** Family Sharing grants them the household's unlocks at no charge.
3. **Given** the Apple TV app under the shared app identity, **When** the same store account
   is signed in, **Then** the same unlocks are active on tvOS (universal purchase), and the
   tvOS unlock surface supports purchase and restore natively.
4. **Given** any unlock screen, **Then** a "Restore Purchases" action is present and
   functional.

---

### User Story 5 - Pre-gate configuration degrades gracefully (Priority: P2)

A device that configured Automation features before the gate existed (internal/TestFlight
builds with a working broker connection) updates to the gated build without owning
Automation. Remote *control* stops working, but the frame does not go dark: it keeps
reporting its status to Home Assistant (free telemetry, FR-1100-03a), broker settings and
credentials stay stored, the settings UI shows the control features as clearly locked, and
purchasing re-enables control with zero reconfiguration.

**Why this priority**: Only internal devices are in this state (nothing ungated was ever
publicly released), but silent data loss or a confusing half-broken state on Jan's own
long-running frames would mask real bugs and violate the no-data-loss bar the app holds
elsewhere.

**Independent Test**: On a device with a configured, verified broker connection, install the
gated build unentitled; verify the frame connects and publishes read-only sensor entities but
publishes no controllable entity and acts on no HA command; settings persist; the UI explains
the locked control state; purchase Automation and verify the controllable entities appear and
control resumes with the stored configuration.

**Acceptance Scenarios**:

1. **Given** stored broker configuration and no Automation entitlement, **When** the gated
   build launches, **Then** the app connects to the broker and publishes read-only telemetry
   only (availability + sensor entities, no controllable entity, no command-topic
   subscription), and all stored broker settings and credentials remain intact.
2. **Given** the same state, **When** the user opens the broker/remote-control settings,
   **Then** the broker connection settings are live (secrets masked as usual) and the *control*
   features carry a clear locked banner and one-time unlock offer — not an empty, reset, or
   fully-masked screen.
3. **Given** the same state, **When** the user purchases Automation, **Then** the controllable
   entities are published and remote control resumes with the previously stored configuration,
   with no re-entry of any value.
4. **Given** configured Shortcuts/App Intents and no Automation entitlement, **When** an
   intent runs, **Then** it fails with a clear "requires the Automation unlock" message
   rather than failing silently or crashing the shortcut.

---

### User Story 6 - Tip jar (Priority: P3)

A happy user who wants to support development finds a tip option tucked into settings, tips
once, and gets a thank-you. Tips grant no functionality and are never solicited.

**Why this priority**: Goodwill channel for the audience segment that prefers donations over
purchases; zero coupling to the gate.

**Independent Test**: Locate the tip option (settings only), complete a sandbox tip, verify
the thank-you state, verify no feature or label changes anywhere else, and verify the app
never prompts for tips on its own.

**Acceptance Scenarios**:

1. **Given** any user, **When** they tip, **Then** a thank-you state is shown and no
   functional change occurs.
2. **Given** any user, **When** they use the app indefinitely without tipping, **Then** no
   tip prompt ever appears unprompted.

---

### Edge Cases

- **Store unreachable at paywall time**: the unlock screen cannot fetch prices → it shows an
  informative unavailable state (no placeholder prices, no crash); the rest of the app is
  unaffected. Purchase requires connectivity; nothing else does.
- **Revocation learned while a gated feature is mid-use**: relock takes effect at the next
  natural boundary (e.g. next app foreground or settings visit), never by yanking UI out from
  under a running slideshow.
- **Bundle vs. single-unlock overlap**: the everything-bundle is offered only while the user
  owns neither single unlock; a user owning one tier is offered only the missing tier (the
  store cannot discount a one-time product dynamically, and charging twice for owned content
  is a dark pattern).
- **Clock in time-limited states**: no purchase state in this app is time-based — there are
  no trials, no expiry, no countdowns; any UI implying urgency is a spec violation.
- **Entitlement state vs. config sync**: device-to-device config sync (KVS/CloudKit) must
  never carry entitlement state; each device derives entitlements from its own store account.
  A synced settings payload from an entitled device must not unlock features on an unentitled
  one (it carries the *settings*, which remain stored-but-locked per User Story 5).
- **App Review access**: reviewers exercise gated features via normal sandbox purchases; no
  reviewer backdoor or hidden unlock switch exists (a backdoor would be a fraud/abuse surface
  on an app whose source is public).
- **Interrupted transactions**: a purchase interrupted mid-flight (app killed, network drop)
  completes or rolls back safely on next launch via the store's transaction queue; the user
  is never charged without receiving the entitlement.

## Requirements *(mandatory)*

### Functional Requirements

**Tier boundaries**

- **FR-1100-01**: The free tier MUST permanently include: every photo source (shared link
  incl. QR scan and password-protected links, server + API key, iCloud/device photos) and the
  complete core playback experience — duration, shuffle, fit/fill, all basic transitions
  (crossfade, slide, dissolve, none), dimming/keep-awake, offline disk cache, resilience
  (auto-retry, periodic refresh) — with no purchase, account, or trial, on every supported
  platform (iPad, iPhone, Apple TV). A free frame must look finished, not crippled: the calm
  default experience (constitution VII — effects off by default) is identical free and paid.
- **FR-1100-02**: The **Pro** unlock (working name; ambience pack) MUST be composed
  exclusively of features that have never shipped in a publicly released version. **Launch
  composition: Ken Burns motion and clock overlay rendering** (both implemented, neither ever
  publicly released — FR-1100-17 keeps that true). Future candidates joining the same
  purchase at no extra charge: weather overlay, sleep/wake scheduling, premium transitions,
  burn-in protection, video playback, multi-source pooling. Tier membership of each future
  feature is decided in that feature's own spec, bound by FR-1100-13.
- **FR-1100-03**: The **Automation** unlock MUST gate *remote control* — the controllable
  Home Assistant entities (brightness/light, album select, playback switch, the settings
  controls, and the next/previous buttons — everything carrying a `command_topic`), the act of
  subscribing to and handling any HA command, and Shortcuts/App Intents (topic 800). When
  unentitled, the app MUST NOT publish any controllable entity, MUST NOT subscribe to or act on
  any HA command, and intents MUST fail with an explicit "requires the Automation unlock" error.
  Remote *control* is the gated capability; the broker connection itself is not (see
  FR-1100-03a).
- **FR-1100-03a** *(free telemetry)*: Publishing read-only status to Home Assistant is part of
  the **free** tier. With a broker configured, an unentitled frame MUST connect to the broker
  and publish, via HA MQTT discovery, availability (LWT) and the read-only sensor entities only
  — the current-photo sensor (asset id + metadata), the current-photo image sensor when its
  opt-in toggle is on (FR-710-07), the playback phase, the photo count, and the app version — so
  Home Assistant can *see* the frame. In this state the frame MUST publish no controllable
  entity and subscribe to no command topic. Because discovery configs are published
  **retained**, "publish no controllable entity" is not satisfied by silence on a frame
  upgrading from a pre-gate build: the broker replays the old configs indefinitely, and all
  entities share the one availability topic telemetry mode still sets to `online`, so Home
  Assistant would show live-looking controls the frame no longer listens to. An unentitled
  frame MUST therefore actively **retract** every controllable entity's discovery config with
  an empty retained payload, so HA ends up with zero controllable entities rather than dead
  ones. The broker connection, its stored credentials (in
  the keychain), and TLS are free-tier capabilities; only *control* is gated. Making telemetry
  free never conflicts with FR-1100-13 — it widens the free tier, it does not claw anything
  back.
- **FR-1100-04**: An optional **everything-bundle** product MAY unlock both tiers in one
  purchase. It is offered only while the user owns neither single unlock; a user owning one
  tier is offered only the missing tier at its normal price.

**Purchase model constraints**

- **FR-1100-05**: All functional unlocks MUST be one-time purchases. Subscriptions are
  prohibited — now and for any future tier. Time-limited access, trials, expiring unlocks,
  and rental framing are prohibited. The word "lifetime" MUST NOT appear in any UI string,
  store listing, or user-facing document; the sanctioned term is "one-time purchase".
- **FR-1100-06**: Family Sharing MUST be enabled on every functional unlock (not on tips).
- **FR-1100-07**: Purchases MUST carry across iPad, iPhone, and Apple TV via universal
  purchase under the shared app identity. Each device MUST derive entitlements solely from
  its own store account; entitlement state MUST NOT be transmitted through the app's own
  config-sync channels or any other side channel.
- **FR-1100-08**: A tip jar MAY exist: optional, reachable only via settings, granting no
  functionality, never prompted for by the app, with a simple thank-you state after tipping.

**Gating behaviour**

- **FR-1100-09**: Gated features MUST remain visible in the UI in a clearly locked state.
  The standard settings pattern applies: the row MAY be visually de-emphasized (dimmed), but
  it MUST carry a lock indicator + tier badge and MUST remain tappable — a dimmed appearance
  alone is insufficient, because a plainly dimmed iOS control reads as "disabled" and is
  never tapped. Tapping a locked row leads to a single unlock screen answering "what do I
  get" (the tier's contents, with a live demo where the feature is visual — e.g. a looping
  Ken Burns motion sample) and "how do I get it" (the one-time price, purchase, restore).
  Prohibited everywhere: nag loops, recurring or unprompted purchase prompts, interstitials,
  fake urgency or countdowns, and any purchase UI appearing during slideshow playback without
  an explicit user action.
- **FR-1100-10**: Entitlement state MUST be cached on-device after every successful purchase,
  restore, or refresh. Owned features MUST activate from the cache at launch with no network
  access and keep working across app restarts, device restarts, and unbounded offline
  periods. No network re-validation may ever block, delay, or degrade an owned feature.
- **FR-1100-11**: A "Restore Purchases" action MUST be available on every unlock screen and
  in settings, and MUST recover all owned unlocks on a reinstalled or new device with zero
  reconfiguration.
- **FR-1100-12**: On a store-reported refund or revocation, the affected features MUST relock
  at the next entitlement refresh, gracefully: all user configuration and data are preserved
  (per FR-1100-14), no crash, and no disruption of a running slideshow beyond the gated
  capability itself stopping at the next natural boundary.
- **FR-1100-13** *(never claw back)*: Any capability that has been available without payment
  in any publicly released App Store version MUST remain free permanently. Moving a
  previously-free-in-public capability behind any gate is prohibited, regardless of tier
  restructuring.
- **FR-1100-14** *(graceful degrade, no data loss)*: When a device holds configuration for a
  gated capability but no entitlement (pre-gate internal builds, revocation, Family Sharing
  departure), that configuration — including secrets in the keychain — MUST be preserved
  untouched (never reset or deleted). For **Automation** the gated capability is *control*: an
  unentitled device with a stored broker keeps its broker connection settings live, keeps
  reading its stored broker credential to publish free telemetry (FR-1100-03a), and shows a
  locked banner + one-time unlock offer on the *control* surface only — not an empty, reset, or
  fully-masked screen. Purchasing the tier MUST re-enable control with the stored configuration
  and zero re-entry. (App Intents hold no per-user config; they simply fail locked per
  FR-1100-03.)
- **FR-1100-15**: Purchase edge states MUST be handled without data loss or double charging:
  pending/deferred approval flows activate the entitlement when approval arrives;
  interrupted transactions complete or roll back safely on next launch; failed or cancelled
  purchases leave the app fully functional with no follow-up prompt.
- **FR-1100-16**: When the store is unreachable, unlock screens MUST show an informative
  unavailable state (no cached/placeholder prices presented as live, no crash). Only the act
  of purchasing requires connectivity.

**Sequencing (release-blocking)**

- **FR-1100-17**: The first publicly released App Store version MUST include the purchase
  gate. The approved-but-unreleased v1.0 build 8 (ungated) MUST NOT be released to the
  public; release remains developer-controlled until a gated build has passed review and
  takes its place. Consequently, at first public release the never-claw-back set (FR-1100-13)
  starts exactly at the FR-1100-01 free tier.

### Key Entities

- **Unlock product**: a one-time purchasable item — Pro, Automation, everything-bundle, and
  tip(s). Functional unlocks are permanent and family-shareable; tips are one-off and grant
  nothing.
- **Entitlement**: the derived per-device ownership state (Pro yes/no, Automation yes/no);
  the bundle grants both. Sourced from the device's store account only; cached locally for
  offline operation (FR-1100-10).
- **Locked-feature surface**: the visible locked representation of a gated feature plus its
  unlock screen (tier contents, one-time price, purchase, restore).
- **Pre-gate configuration**: stored settings/credentials for a gated feature on an
  unentitled device; preserved and dormant per FR-1100-14.

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-1100-01**: On a fresh install with no purchases, every onboarding path (QR shared
  link, pasted/password link, server + API key, iCloud/device photos) completes to a running
  slideshow with **zero** purchase-related UI shown.
- **SC-1100-02**: Over ≥ 4 hours of continuous free-tier playback, zero purchase-related UI
  appears without explicit user action.
- **SC-1100-03**: Completing a purchase activates the tier's features in under 10 seconds
  with no app restart; the locked labels for that tier disappear app-wide.
- **SC-1100-04**: With entitlements active and the network disconnected, a 24-hour soak
  including at least 3 app relaunches and 1 device restart shows all owned features active
  the entire time (may piggyback on the existing 24 h device soak).
- **SC-1100-05**: After deleting and reinstalling the app, "Restore Purchases" recovers every
  owned unlock, and a previously configured broker connection resumes with zero re-entered
  values.
- **SC-1100-06**: On a device with pre-gate broker configuration and no entitlement: the frame
  connects and publishes read-only sensor entities only — verifiable at the broker as
  availability + sensors present, **zero** controllable entities, **zero** command topics
  subscribed, and **zero** commands acted on — and every stored broker setting survives the
  update byte-for-byte.
- **SC-1100-07**: A copy audit of all user-facing strings and the store listing finds zero
  occurrences of "lifetime" or subscription terminology for the unlocks; paid items are
  described as one-time purchases.
- **SC-1100-08**: A family member's device (same family group, own account) shows the
  household's unlocks active without payment.
- **SC-1100-09**: The App Store release history shows the gated version as the first version
  ever released to the public (v1.0 build 8 never released).

## Assumptions

- **Nothing has shipped publicly yet.** v1.0 (build 8) is approved but unreleased and will
  stay unreleased (FR-1100-17). Therefore features already merged internally — HA/MQTT
  remote control, App Intents, the clock overlay renderer, **and Ken Burns motion** — are
  eligible for gating: the never-claw-back rule binds from the first *public* release onward.
  Gating Ken Burns was decided deliberately (2026-07-19): it is opt-in seasoning per
  constitution VII (the default frame never shows it), it gives the Pro pack real day-one
  content alongside the clock, and it is the app's most demoable premium asset. The free tier
  keeps all basic transitions so a free frame still looks polished.
- **Price points are out of scope by design** and are configured in App Store Connect at
  submission time; this public repository records no prices.
- **Tier composition is a living boundary**: the FR-1100-02 candidate list is the current
  plan, not a commitment; each future feature's spec assigns its tier, constrained by
  FR-1100-13 and the "never shipped free publicly" rule.
- **The Pro features themselves are separate specs** (weather, scheduling, video, burn-in
  protection, etc. — e.g. reserved topic 730 for scheduling); this spec covers only the gate,
  the tiers, and the purchase/entitlement behaviour. Where a launch-composition feature is
  already implemented (clock overlay 510, Ken Burns motion), wiring it behind the gate is in
  scope here.
- **Tips are consumable-style products** with no entitlement effect; one or a small set of
  fixed tip sizes.
- **The repository remains public** (Fair Source). The gate's integrity rests on goodwill and
  honest framing, not on code secrecy — which is why the no-dark-patterns rules (FR-1100-05,
  FR-1100-09) are hard requirements, not style preferences.
- **Store infrastructure is Apple's** (App Store purchases, Family Sharing, universal
  purchase, sandbox review flows); the app performs no custom payment processing and runs no
  server of its own for entitlements.
