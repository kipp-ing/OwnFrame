<!--
SYNC IMPACT REPORT
==================
Version change: 1.0.1 → 1.1.0
Bump rationale: MINOR — principle III materially expanded: a single sanctioned channel for
  syncing secrets between the user's own devices (Apple's end-to-end-encrypted CloudKit
  private-database encrypted fields, system-managed keys) is now permitted, motivated by the
  Apple TV target (spec 1000) where iCloud Keychain sync does not exist. At-rest rules are
  unchanged: on every device the keychain remains the only permitted storage. Decided by Jan
  on 2026-07-16 during the 900/1000 roadmap research session.

Principles defined (7, III amended):
  I.   Test-First (NON-NEGOTIABLE)
  II.  Modular Isolation
  III. No Secrets in Plaintext (NON-NEGOTIABLE, amended 1.1.0)
  IV.  Transport-Layer Security
  V.   Respect Platform Boundaries
  VI.  Verifiable Acceptance Criteria
  VII. Plain and Light by Default

Added sections: none

Removed sections: none

Templates requiring updates:
  ✅ .specify/templates/plan-template.md   (no change needed — references principles generically)
  ✅ .specify/templates/spec-template.md   (no change needed)
  ✅ .specify/templates/tasks-template.md  (no change needed)
  ✅ specs/1000-apple-tv/spec.md           (updated in the same change: FR-1000-12)

Follow-up TODOs: none
-->

# ImmichSlideshow Constitution

ImmichSlideshow is a standalone iPad app that uses Immich exclusively as a data source via its
REST API. It is **not a fork** of the official Immich app and maintains no dependency on the
official Immich codebase. The following principles are binding.

## Core Principles

### I. Test-First (NON-NEGOTIABLE)
Every piece of functionality starts with a failing test. NO implementation code is written
before a corresponding test exists and is demonstrably red. The Red → Green → Refactor cycle is
strictly followed: red test first, then the minimal implementation until green, then refactor
while tests stay green.

**Rationale:** A test that was never red proves nothing. Test-First enforces verifiable behavior
and prevents safety nets that were retrofitted after the fact.

### II. Modular Isolation
Every module is decoupled from its dependencies via a protocol — in particular network
(`ImmichAPI`), keychain (`KeychainStore`), MQTT (`MQTTTransport`), and time/timers. Tests run
without a real server, broker, or keychain, against mocks/fakes. Hidden singletons are
prohibited; dependencies are injected.

**Rationale:** Isolation makes every module deterministically testable and keeps the suite fast
and independent of external infrastructure.

### III. No Secrets in Plaintext (NON-NEGOTIABLE)
The Immich API key, MQTT credentials, and shared-link passwords live exclusively in the
keychain at rest, on every device. They never appear in UserDefaults, in source code, in logs,
or in committed files. Exactly one transport between the user's own devices is sanctioned:
Apple's end-to-end-encrypted CloudKit **private-database encrypted fields**
(`CKRecord.encryptedValues`), whose keys are system-managed — the app implements no
cryptography of its own. Secrets never transit or rest in iCloud key-value storage, in
plaintext CloudKit fields, or in any custom encryption scheme; a secret received via the
sanctioned channel is stored into the local keychain and used only from there.

**Rationale:** Plaintext secrets are a permanent leak risk that no later fix can heal; the
keychain is the only permitted storage. Device-to-device sync is confined to the one channel
where key management is the platform's responsibility end to end — hand-rolled crypto or
semi-encrypted stores would reintroduce exactly the risk this principle exists to prevent.

### IV. Transport-Layer Security
TLS validation is never disabled. The Immich server has a valid certificate (standard
URLSession, no TLS exception); MQTT runs over TLS. Self-signed or plaintext connections are
explicitly out of the current scope and are not approximated by bypassing validation.

**Rationale:** A TLS check disabled even once undermines the security of all connections; as
long as a valid certificate is in place, there is no reason for it.

### V. Respect Platform Boundaries
The app does not design features against the boundaries of iOS/iPadOS. It does not physically
turn off the display (only dims brightness toward ~0) and controls brightness and the idle timer
only in the foreground; once the app moves to the background, iOS reclaims control.

**Rationale:** Code written against platform boundaries is fragile and creates false
expectations; features are designed within the control that is actually available.

### VI. Verifiable Acceptance Criteria
Every spec ends with checkable criteria: concrete inputs/outputs and explicit error cases, not
vague quality wishes. Every criterion must be expressible as a test.

**Rationale:** Only verifiable criteria can be signed off; vague wishes produce arguments instead
of a red or green signal.

### VII. Plain and Light by Default
UI defaults are calm and light. Extra features (transitions, Ken Burns, overlays) are opt-in and
are never imposed. Default: light, calm, no overlay.

**Rationale:** A slideshow should show the photos first; effects are seasoning, not the baseline
state.

## Additional Constraints (Tech Stack & Architecture)

- Platform: iPadOS 18+ (iPhone optional). Language: Swift 6. UI: SwiftUI. Architecture: MVVM
  with `@Observable`. Package manager: Swift Package Manager.
- Test framework: Swift Testing (`@Test`); XCTest only where strictly necessary.
- Builds and tests run via XcodeBuildMCP; raw `xcodebuild` output is not parsed by hand.
- API paths are checked against the OpenAPI spec of the running Immich version
  (`/api/server/version`), not taken from old tutorials.

## Development Workflow (TDD & SDD)

- **SDD via Spec Kit:** No feature code without a prior spec + plan + tasks. The loop is
  constitution → specify → clarify → checklist → plan → tasks → analyze → implement.
- **TDD per task:** Red → Green → Refactor (see `tdd-workflow.md`). No skipping across multiple
  tasks.
- **Definition of Done per task:** Tests green via XcodeBuildMCP; no secrets in code; constraints
  from `CLAUDE.md` honored; for UI, the preview renders without crashing.

## Governance

This constitution takes precedence over all other practices. Changes require a documented
rationale in the Sync Impact Report and a version bump following SemVer:

- **MAJOR:** backward-incompatible removal or redefinition of principles/governance.
- **MINOR:** new principle/section or materially expanded requirements.
- **PATCH:** clarifications, wording, typos, non-semantic refinements.

Every spec, plan, and review checks compliance with these principles. Deviations must be
explicitly justified; a NON-NEGOTIABLE violation blocks the merge. Ongoing development
guidelines live in `CLAUDE.md` and `tdd-workflow.md`.

**Version**: 1.1.0 | **Ratified**: 2026-06-17 | **Last Amended**: 2026-07-16
