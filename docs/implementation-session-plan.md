# Implementation Session Plan — Roadmap Majors (900 first)

> **Historical as of 2026-07-26.** Phases 0–4 below are **executed history**, still written in
> the imperative: `900-photo-library-source`, `800-app-intents`, and `1000-apple-tv` are all
> implemented and merged to main. Kept for the delegation model and the Phase-1 leak table, which
> record how the source-protocol refactor was shaped. The one part that is still live is the
> "Ship gate" section — and it is tracked more accurately in `docs/manual-verification.md`
> ("FINAL DEVICE DAY", §C). Current truth: `docs/spec-overview.md` and the module spec under
> `specs/Nxx-*/`. The 2026-07-09 Codex ruling noted below still stands.

**Created**: 2026-07-16 · **Orchestrator**: Claude Fable (this harness) · **Implementers**:
Opus subagents (Agent tool, `model: opus`) · Codex remains disabled (2026-07-09 ruling).

**Target**: `900-photo-library-source`. Rationale: its source-protocol refactor (FR-900-01)
is the architectural core of 900 *and* the load-bearing base 1000 reuses — it unblocks both
majors. `800-app-intents` stays ahead of 900 in the release queue (Jan's confirmed order
800 → 900 → 1000); this plan is for whichever of the two Jan starts, and 800 would follow
the same delegation model. Two cheap 1000 de-risk spikes piggyback at the end.

---

## Phase 0 — Spec Kit formalities (Fable inline, ~start of session)

Constitution: no feature code without spec + plan + tasks.

1. `/speckit-plan` for 900 → `specs/900-photo-library-source/plan.md` + research/data-model/
   contracts. The 2026-07-16 research is already encoded in the spec; the plan phase mostly
   formalizes the protocol design (below) rather than re-researching.
2. `/speckit-tasks` → dependency-ordered `tasks.md`.
3. `/speckit-analyze` → consistency gate before any code.

## Phase 1 — Source-protocol refactor (the load-bearing slice)

Generalize the engine's seam from Immich-shaped to backend-neutral. The audit (2026-07-16)
mapped every leak; these are the work items:

| Leak (file:symbol) | Neutralization |
|---|---|
| `SlideshowViewModel.api: any ImmichAPI` | New `PhotoSourceProviding` protocol (enumerate, image data by quality tier, metadata); `ImmichAPI` becomes one conformer |
| `Asset` (`{id, type}`) + `type == "IMAGE"` string filter | Neutral asset type with a media-kind enum (`stillCapable` covers Live Photos per FR-900-08) |
| `SourceSnapshotStoring.save([Asset])` — persisted JSON format | Neutral snapshot type **with a decode-tolerant migration** for existing on-disk snapshots (frames in the field have them) |
| `ImmichError` in `RetryPolicy.classify` + 4 call sites | Neutral error classification protocol (transient/auth/permanent); ImmichError maps in |
| `api.serverVersion()`/`ensureServerSupported()` | Backend capability/readiness check on the protocol; PhotoKit conformer = authorization check |
| `ImageQuality` → endpoint switch (`preview`/`original`) | Quality-tier request stays on the protocol; each backend maps tiers itself |

**Delegation**: 2 sequential Opus subagents (protocol shape decided by Fable first, inline —
this is the cross-package architecture call). Subagent A: SlideshowKit refactor + snapshot
migration, red tests first, all existing suites stay green against the Immich conformer.
Subagent B: ImmichClient conformance + RetryPolicy/error mapping. Sequential, not parallel —
they share the protocol boundary.

**Gate**: SC-900-03's precondition — the full SlideshowKit suite passes against `StubImmichAPI`
through the *new* protocol with zero behavior diffs. XcodeBuildMCP build + test, plus app
target build (the adapter/HA surfaces compile against renamed types).

## Phase 2 — PhotoLibraryKit (new package, cleanest delegation target)

Pure new code behind the Phase-1 protocol; zero PhotoKit in unit tests (FR-900-13).

- Slice C (Opus, parallelizable with nothing — Phase 1 must be merged): package scaffold,
  fake-provider test kit, `PhotoSourceProviding` conformance against a fake PhotoKit seam.
- Slice D (Opus): authorization state machine — `.readWrite` access-level API only
  (FR-900-04), full/limited/denied/downgrade transitions, Selected-Photos source under
  limited (collection-less `SourceKind` variant).
- Slice E (Opus): change observation + foreground refetch + 310 reconciliation wiring
  (FR-900-09), vanish handling (FR-900-16).
- **Fable inline**: the thin real-PhotoKit adapter (authorization prompts, PHImageManager
  degraded-delivery filtering per FR-900-07, `includeAssetSourceTypes` for global fetches) —
  small, security/privacy-adjacent, needs device/simulator sanity checks.

**Gate**: package suite green on host; SC-900-03 (same engine tests pass against Immich fake
AND photo-library fake).

## Phase 3 — App integration (Fable-heavy, simulator required)

Source picker (albums + shared albums, full-access gate, honest limited-mode UI — FR-900-03),
onboarding/Settings surfaces (210 picker pattern), 120 source-kind persistence + rebuild
restart strategy, info overlay metadata (FR-900-10). Opus subagents draft view/viewmodel
slices; Fable verifies every surface on the simulator (XcodeBuildMCP + screenshots) and owns
keychain/authorization wiring. Full XCUITest run before merge (standing rule).

## Phase 4 — Parity + polish

HA select/metadata for Photos sources (FR-900-11/12, Opus slice against HAControlKit fakes),
image-publishing opt-in copy, quality-ceiling honesty in Settings (FR-900-15). Device
spot-check with real iCloud content (SC-900-02), authorization UI paths (SC-900-05).

## Ship gate (still open — tracked elsewhere)

SC-900-07: US1/US2 on the newest iOS beta with a real legacy shared album + the
upgraded-album vanish drill. Schedule when a 27 beta is on the test iPad.
**Tick it in `docs/manual-verification.md` ("FINAL DEVICE DAY", §C — "900 quickstart device/beta
gates"), not here** — that list is the single place device gates are tracked.

---

## 1000 de-risk spikes (piggyback, cheap)

1. **tvOS compile check** (~30 min, Opus): add `.tvOS(.v17)` to the seven package manifests
   on a branch, `swift build`/`swift test` per package for a tvOS destination → pre-verifies
   SC-1000-04 and the mqtt-nio claim. No app target yet.
2. **`encryptedValues` on real hardware** (needs the Apple TV + iCloud account, manual):
   throwaway CloudKit container, write encrypted field on iPad, read on tvOS. Proves the
   FR-1000-12 assumption before 1000 is scheduled.

## Subagent operating rules (adapted house rules)

- Every delegation gets a written briefing: task, in-scope files (only those may be touched),
  the relevant FR IDs quoted, the red-test-first requirement, verification command.
  `.claude/scripts/codex-brief.sh` renders this format — reuse it for Opus prompts.
- **TDD is non-negotiable for subagents too**: briefing requires the failing test shown
  before implementation in the report.
- Parallel subagents only on disjoint packages; use worktree isolation when two run at once.
- Two-round limit per delegation (implement + one fix round); after that Fable finishes
  inline.
- Subagents never touch `.specify/**`, `specs/**`, `project.pbxproj`; stage with explicit
  paths only; no secrets, no TLS changes (constitution III/IV).
- Fable owns every gate: XcodeBuildMCP build/test/UI-test, simulator verification, review of
  each diff before commit. Bulk diff reading goes to an Explore subagent, not raw `Read`.
