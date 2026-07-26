# Next session: requirement traceability backfill

Written 2026-07-21 for a session starting with none of the preceding context. Read
[traceability.md](traceability.md) for the method and [testing.md](testing.md) for the traps;
this file is only the current state and the next moves.

> **Executed 2026-07-22 (PR #34).** All seven entries ran; traceable 38% → 57%, `@covers`
> 65 → 196; 24 of 448 verdicts refuted and stripped; the audit stage fired for the first time
> (8 rulings, 4 upheld additions adopted). Findings filed as issues #28–#33 — six more of the
> #26 shape. The per-requirement gap backlog lives in the seven commit messages on that PR.
> What remains from this file (as of 2026-07-26): from the "Do not do these unattended" list
> below, only **test repair** — #21, #22 and #26 were fixed in PRs #35/#36, as were #28, #30 and
> #31 of the new batch. Still open are **#29, #32 and #33**, all tvOS-side and therefore deferred
> under the iOS-first policy. The write-a-test gap backlog also stands. The pipeline itself is
> done; do not re-run it wholesale.

## Where things stand

CI is **green on `main`** for the first time in months (#20 closed 2026-07-21) — it was pinned to
Xcode 16 while the project ships on Xcode 26/Swift 6.3.3, so it had been failing the code for not
compiling under a toolchain nobody uses. `main` now has a real merge gate: 852 host tests across
12 packages, and the job asserts a per-package test-count line so a green check cannot mean
"nothing ran".

Requirement traceability, from `.claude/scripts/coverage.py`:

```text
467 requirements defined across 20 spec modules
  ~65 with an explicit @covers annotation
  ~38% traceable at all (the rest is untraceable, NOT untested — see below)
```

Six modules have been backfilled: `400`, `320`, `100`, `600`, `800`, `500`, `510`.

**Read the percentage correctly.** It measures whether a requirement can be *traced* to a test,
not whether it is tested. `ImmichClient` had 73 passing tests and cited zero requirement ids. The
number says how much of the suite is auditable.

## The next job

Run the tag → verify → audit pipeline over the remaining modules, **partitioned by package**.
Modules are not 1:1 with packages, and two agents in one package overwrite each other's edits.

| Entry | Package | Modules | ~Reqs |
|---|---|---|---|
| 1 | OnboardingKit | 120, 200, 210, 220 | 115 |
| 2 | SlideshowKit | 300, 310, 320 | 80 |
| 3 | HAControlKit | 700, 710 | 64 |
| 4 | ImmichClient | 100, 110, 130 | 49 |
| 5 | PurchaseKit | 1100 | 27 |
| 6 | PhotoLibraryKit | 900 | 23 |
| 7 | ConfigSyncKit | 1000 | 20 |

```js
Workflow({
  scriptPath: "/Users/jan/dev/repos/Immich-Slideshow/.claude/workflows/covers-backfill-verified.js",
  args: [{ id: "200-connection-onboarding", pkg: "OnboardingKit",
           alsoModules: ["120-source-library", "210-shared-link-onboarding",
                         "220-onboarding-welcome"] }]
})
```

Invoke by `scriptPath`. Name-based lookup does not resolve `.claude/workflows/` until the session
restarts. Confirm the package mapping before dispatching — modules with no existing id mentions
cannot be found by grep, so infer from the package name and verify.

Then apply and check:

```bash
.claude/scripts/strip-refuted.py <workflow-result.json> --dry-run   # preview
.claude/scripts/strip-refuted.py <workflow-result.json>             # apply
swift test --package-path Packages/<Pkg> 2>&1 | grep 'Test run with'
.claude/scripts/coverage.py                                        # delta
```

Budget roughly **2M tokens** for all seven. Observed rate was ~122k per module on small ones;
these entries are much larger, so budget above that, not below.

## What matters more than the tags

**Dead wiring.** The single most valuable output so far was not a tag — it was issue **#26**:
FR-510-03 requires the random clock to "never land on the caption's place". The picker honours an
`occupied` set and had a green test for it, but `SlideshowView.relocateRandomClockIfNeeded()`
passed `occupied: []`, hardcoded. The feature did not work in the shipping app, and every test
passed. (Fixed in PR #35; kept here because the *shape* is the point.)

That is the shape to hunt: **a correct component, a green component test, and an app that does
not wire it.** All three verifier prompts now instruct agents to follow app-behaviour
requirements to their production call site in `OwnFrame/` and check what is actually
passed. Ten more findings like #26 would be a better night's work than three hundred more tags.

The second most valuable output is the **gap list** — requirements with no covering test, each
naming the layer that would own one. Tags say where you are exposed; gaps say what to write.

## Rules that are load-bearing

- **A wrong tag is worse than no tag.** It launders an unproven requirement into "traceable" and
  gets committed where the next session trusts it. Under-tagging is a visible backlog;
  over-tagging is an invisible lie.
- **Never trust a bare exit 0.** A `-only-testing` filter matching nothing exits 0; piping
  `xcodebuild` into `head`/`tail` replaces its exit code with the filter's. Both produced a
  convincing false "all green" *while the anti-false-green tooling was being built*. Assert on
  observed test counts.
- **Refutation rate is the health check.** ~10–35% is normal (measured: 0/0/10/14/14/33/36%
  across seven modules). Near 0% on a large batch means the verifier is rubber-stamping — read
  its evidence strings and check they contain real quoted assertions. Very high means the
  partition is wrong: the package probably cannot prove that module.
- **Adopt only `UPHELD` additions.** `missedCoverage` is the verifier's own unrefuted output; the
  audit stage exists to attack it.

## Known caveats

- **The audit stage has never executed.** On the `510` smoke test `missedCoverage` came back
  empty, so only its skip path ran. Its agent is unexercised. Entries 1 and 4 (OnboardingKit,
  ImmichClient) are the shapes that produced `missedCoverage` before — expect it to fire there,
  and read its first output carefully rather than trusting it.
- **`coverage.py` is static.** It reads annotations and spec files and runs nothing. After a
  regression it reports the same percentage. Traceability is a map, not an alarm — CI is the
  alarm, and it works again now.
- **`@covers` records intent.** A tag means someone believed a test proves a requirement and a
  second agent could not refute it. Nothing stops a tag that is wrong in a way neither caught.

## Do not do these unattended

Real logic changes need review; a comment-only backfill does not. Leave these for a session with
a human in the loop:

- ~~**#26** — FR-510-03 dead wiring. Pass the caption's place into
  `relocateRandomClockIfNeeded()`. Test the *wiring*, not the picker; the picker already has a
  green test and it did not help.~~ **Closed in PR #35.**
- ~~**#21** — `BrokerSetupUITests` fails on a clean simulator on stock `main` (`broker.username`
  never appears).~~ **Closed in PR #36.** The suspicion recorded here — that the 1100
  free-telemetry rework (T046–T048) moved the field or changed its gate state — was wrong: the
  field was merely off-screen, and the fix scrolls it into view.
- ~~**#22** — `ShareSheetIncomingUITests` is order-dependent: passes alone, fails in the full
  suite, reading `https://host/s/slug` where it expects `https://demo.example.com/s/abc123`.
  Grep that literal to find the leaking test.~~ **Closed in PR #36.**
- **Test repair** — the `FR-600-02` class: tests that pass while proving nothing (replacing
  `validate()` with `return nil` keeps it green). Strengthening those changes assertions, not
  comments, and belongs in its own reviewed run.

## Session hygiene

Commit to a branch, PR, and let CI gate it — do not merge unattended. Record the refuted tags and
the gaps in the commit message: the tags are the artifact, but the refutations and gaps are the
durable knowledge, and they are lost if they live only in a workflow transcript.
