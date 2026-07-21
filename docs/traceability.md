# Requirement Traceability — the map, and how it gets built

Two things live here:

1. **`.claude/scripts/coverage.py`** — derives, from the tree, which requirements can be traced
   to a test. Covered in [testing.md](testing.md#requirement-traceability--claudescriptscoveragepy).
2. **The tag → adversarially-verify method** used to raise that number without lying. That is
   what this document is for.

## Why the method exists

The obvious approach — point an agent at a module and let it add `@covers` annotations — fails
in a way that is worse than doing nothing. An over-eager tag *launders an unproven requirement
into "traceable"*. The number goes up, the map becomes fiction, and the fiction is now checked
into git where the next session will trust it.

That is the same failure this repo has already been bitten by twice:

- A `setUp` skip-guard that turned a bug into a documented platform limitation, believed for a
  day and written into four documents (see [testing.md](testing.md) § "`SKTestSession` serves 0
  products").
- `FR-320-11` ("disk work MUST never delay the visible transition"), which read as *traced*
  because the id appeared in doc comments on a **private test helper**. No test asserted
  display-path latency at all.

So the method's core assumption is: **the tagger will be wrong some of the time, and its own
confidence is not evidence.** Everything below follows from that.

## The method

Two agents per unit of work, run as a pipeline (`.claude/workflows/covers-backfill-verified.js`):

```text
Tag  ──►  Verify  ──►  human strips refuted tags, commits the rest
```

**Stage 1 — tag.** One agent per package. Reads the spec, reads the tests, adds
`// @covers FR-XXX-NN` above tests that genuinely assert the requirement. Told explicitly that
a wrong tag is worse than no tag, that a second agent will attack its work, and that gaps are a
first-class deliverable rather than a failure.

**Stage 2 — verify.** A second agent tries to **refute every tag**. Four design choices carry
the weight:

- **Requirement-first, not tag-first.** It works out which test proves each requirement *before*
  reading the tags, then compares. Tag-first invites rationalising whatever it is shown.
- **Never sees stage 1's reasoning.** Same model plus same argument produces the same blind
  spot. Independence is the only thing that makes agreement meaningful.
- **Defaults to REFUTED.** `CONFIRMED` requires quoting the literal assertion that constrains
  the requirement. A tag it merely finds *plausible* is refuted. Without this the stage
  degenerates into rubber-stamping.
- **Read-only.** A verifier that can edit will quietly fix what it finds, and the finding is the
  product.

**Stage 3 — a human decides.** Refuted tags are reported, never auto-stripped. Stripping is
mechanical once the verdicts exist; the judgement of whether a refutation is *correct* is not.

### The sharpest tool: mutation arguments

Prose refutation is the weak form — well-written wrong things read as fine. The strong form is:
*if the production code were replaced with a trivial stub, would this test go red?* That yields
a fact rather than an opinion. The single best catch so far was exactly this shape:

> `FR-600-02` was tagged onto `validationAcceptsCompleteSettings`, whose only assertion is
> `#expect(settings.validate() == nil)` for valid input. Replacing `validate()` with
> `return nil` keeps the test green. It is a no-false-rejection control, not proof that
> validation happens.

Both prompts now instruct the agents to reach for this whenever it applies.

## Calibration — what a healthy run looks like

Measured over 6 modules, 2026-07-21:

| Module | Tags claimed | Refuted | Rate |
|---|---|---|---|
| 400-power-manager (pilot, hand-checked) | 17 | 0 | 0% |
| 320-disk-image-cache (pilot, hand-checked) | 16 | 0 | 0% |
| 800-app-intents | 21 | 2 | 10% |
| 100-immich-client | 28 | 4 | 14% |
| 600-broker-setup | 14 | 2 | 14% |
| 500-display-options | 25 | 9 | **36%** |

**Read the rate as a health check on the verifier, not only on the tagger.** ~10–20% is the
healthy band. Near 0% across a batch means the verifier is rubber-stamping — re-read its
evidence strings and check they contain real quoted assertions. Near 100% means the bar has
drifted somewhere unusable.

The 36% outlier was diagnostic rather than alarming: `ThemeKit` holds the settings *model*, but
most `FR-500` requirements describe what the **slideshow** does with those settings, which
ThemeKit structurally cannot observe. A high rate usually means *the package cannot prove this
module*, which is worth knowing on its own.

The two pilots scoring 0% is consistent, not suspicious — they were hand-verified before the
adversarial stage existed, on the two easiest module shapes (small, single-package, clear
ownership).

## Partition by package, never by module

Modules and packages are not 1:1. `SlideshowKit` alone owns `300`, `310` and `320`; two agents
pointed at it concurrently will corrupt each other's edits. Give one agent the package and all
the modules it owns (`alsoModules`), rather than one agent per module.

Modules with no existing id mentions cannot be mapped by grep — infer from the package name and
confirm before dispatching.

## Known limitations — read before trusting the number

- **`@covers` records intent, not proof.** It says a human-or-agent believed this test proves
  this requirement, and that a second agent could not refute it. Nothing stops a tag that is
  wrong in a way neither caught.
- **`missedCoverage` is unverified.** The verifier also reports requirements that *do* have a
  proving test but no tag. Those are its own unrefuted suggestions — adopting them directly
  reintroduces exactly the trust problem this method exists to solve. They need their own
  adversarial pass.
- **Traceability is not regression protection.** See below. This is the most commonly assumed
  and most wrong inference about what this tooling does.

## What this does NOT do

`coverage.py` is **static**. It reads annotations and spec files. It does not run anything.

If the production code breaks tomorrow, `coverage.py` still reports the same percentage. A tag
does not notice a regression; only a *running test* does, and only if something runs it and
someone reads the result.

So traceability is a **map**, not an alarm. It makes these questions answerable —

- which requirements have no test at all (the `gaps` output)
- which requirements are proven only by a human remembering (`manual only`)
- which tests must run for a change to a given spec area

— and none of those are "did this change break something". That is CI's job, and
[#20](https://github.com/kipp-ing/Immich-Slideshow/issues/20) records that CI has been red for
months. **Until that is fixed, 100% traceability would still gate nothing.**

## Running it

```bash
# See where the gaps are first — pick targets by size and package ownership.
.claude/scripts/coverage.py

# Then, from Claude Code (multi-agent; costs real tokens — see the budget note below):
#   Workflow({ name: "covers-backfill-verified",
#              args: [{ id: "300-slideshow", pkg: "SlideshowKit",
#                       alsoModules: ["310-slideshow-resilience", "320-disk-image-cache"] }] })
```

Then: strip refuted tags, re-run the affected `swift test` packages **checking the test count
rather than the exit code**, re-run `coverage.py` for the delta, and commit — recording the
refuted tags and the gaps in the commit message, since that is the durable part.

**Budget.** The verified batch of 4 modules cost ~489k subagent tokens across 8 agents
(~122k/module) — roughly double the unverified rate. Worth it for tags, which are trusted
silently for a long time afterwards. Not worth it for output a human is about to read anyway.
The remaining large modules (`300`, `200`, `210`) span packages and layers and should be
budgeted higher than the observed average, not lower.
