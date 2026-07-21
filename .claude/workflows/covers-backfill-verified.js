export const meta = {
  name: 'covers-backfill-verified',
  description: 'Backfill @covers requirement tags per module, then adversarially verify each tag',
  whenToUse:
    'Raising requirement traceability for one or more spec modules. Pass args as ' +
    '[{id:"300-slideshow", pkg:"SlideshowKit"}, ...]. One agent per entry tags, a second ' +
    'independently tries to refute every tag. Refuted tags are reported, NOT auto-stripped — ' +
    'the caller decides. Partition by PACKAGE, never by module: two agents in the same package ' +
    'will collide. SlideshowKit alone owns 300/310/320, so those three go in ONE entry.',
  phases: [
    { title: 'Tag', detail: 'one agent per entry adds @covers annotations' },
    { title: 'Verify', detail: 'independent agent refutes each tag, requirement-first' },
  ],
}

// args: [{ id: "300-slideshow", pkg: "SlideshowKit", alsoModules: ["310-…","320-…"] }, …]
const MODULES = Array.isArray(args) && args.length ? args : []
if (!MODULES.length) {
  throw new Error(
    'covers-backfill-verified needs args: [{id, pkg, alsoModules?}, …]. ' +
      'See docs/traceability.md.',
  )
}

const TAG_SCHEMA = {
  type: 'object',
  additionalProperties: false,
  required: ['module', 'tagged', 'gaps', 'testsGreen'],
  properties: {
    module: { type: 'string' },
    tagged: {
      type: 'array',
      items: {
        type: 'object',
        additionalProperties: false,
        required: ['id', 'tests', 'justification'],
        properties: {
          id: { type: 'string' },
          tests: { type: 'array', items: { type: 'string' } },
          justification: { type: 'string' },
        },
      },
    },
    gaps: {
      type: 'array',
      items: {
        type: 'object',
        additionalProperties: false,
        required: ['id', 'why'],
        properties: { id: { type: 'string' }, why: { type: 'string' } },
      },
    },
    misleadingMentions: { type: 'array', items: { type: 'string' } },
    testsGreen: { type: 'boolean' },
    notes: { type: 'string' },
  },
}

const VERDICT_SCHEMA = {
  type: 'object',
  additionalProperties: false,
  required: ['module', 'verdicts'],
  properties: {
    module: { type: 'string' },
    verdicts: {
      type: 'array',
      items: {
        type: 'object',
        additionalProperties: false,
        required: ['id', 'verdict', 'evidence'],
        properties: {
          id: { type: 'string' },
          verdict: { type: 'string', enum: ['CONFIRMED', 'REFUTED'] },
          evidence: { type: 'string' },
          testName: { type: 'string' },
        },
      },
    },
    missedCoverage: {
      type: 'array',
      items: {
        type: 'object',
        additionalProperties: false,
        required: ['id', 'test'],
        properties: { id: { type: 'string' }, test: { type: 'string' } },
      },
    },
    notes: { type: 'string' },
  },
}

function moduleList(m) {
  return [m.id].concat(m.alsoModules || []).join(', ')
}

function tagPrompt(m) {
  return `Repo: /Users/jan/dev/repos/Immich-Slideshow

Backfill \`@covers\` requirement annotations for module(s) **${moduleList(m)}**, scoped strictly
to \`Packages/${m.pkg}/Tests/\`.

## The one rule that matters

**A wrong tag is worse than no tag.** An over-tag launders an unproven requirement into
"traceable", which is exactly the false-green this tooling exists to eliminate. Tag a test with
a requirement ONLY if the test genuinely asserts that requirement's substance. If unsure, DO NOT
TAG — record it as a gap. Under-tagging is a cheap visible backlog; over-tagging is an invisible
lie.

A separate agent will independently try to REFUTE every tag you add, working requirement-first
without seeing your reasoning. Tags you cannot defend with a specific quoted assertion get
stripped. Do not pad. Subject-matter adjacency ("this test is about brightness and so is the
requirement") is NOT sufficient — the test must verify what the requirement states.

A useful self-check before you commit to a tag: if the production code implementing this
requirement were replaced with a trivial stub, would this test go red? If not, it does not
prove the requirement.

## Steps

1. Read \`specs/<module>/spec.md\` for each module in scope. Requirement definitions have the
   exact shape \`- **FR-300-01**: text\` (bullet, bold id, optional \`*(annotation)*\`, colon).
   Ids referenced elsewhere without that shape are citations, not definitions.
2. Read every test file under \`Packages/${m.pkg}/Tests/\`. \`Fakes.swift\` and similar helpers
   are not tests — never tag them.
3. For each test, decide which requirement(s), if any, it actually asserts.
4. Annotate: a line \`// @covers FR-300-01\` (comma-separated for multiple) IMMEDIATELY ABOVE the
   \`@Test\` attribute (or \`func test…\` for XCTest). If a doc comment (\`///\`) is present, put
   \`@covers\` directly below it and above \`@Test\`. Match surrounding indentation exactly.

## Constraints

- ONLY touch files under \`Packages/${m.pkg}/Tests/\`. Other agents edit other packages
  concurrently; straying WILL corrupt their work.
- Add ONLY comment lines. Never modify test logic, names, imports, or assertions. Do not
  reformat or "improve" anything you pass by.
- Every id must exist verbatim as a definition in the relevant spec.md. Do not invent ids.
- Requirements provable only in the app target or UI tests are OUT of scope. Record them as gaps
  naming the layer that would prove them — do not tag them here.
- Verify green: \`swift test --package-path Packages/${m.pkg} 2>&1 | tail -20\`. You add only
  comments, so it must stay green. If it does not, you changed something you should not have —
  revert and say so. Confirm the test COUNT, not just the exit code: a filter that matches
  nothing still exits 0.

## Return

\`tagged\`: each id, the test function name(s), and a one-line justification naming the assertion.
\`gaps\`: requirements with no covering test here, each noting what a test would need to assert
(or which layer owns it). Do NOT shrink this list by padding \`tagged\`.
\`misleadingMentions\`: existing prose citing a requirement id where the test does not prove it —
quote the line. High value: that is a live false-green.
\`testsGreen\`: whether swift test passed, with counts observed.`
}

function verifyPrompt(m) {
  return `Repo: /Users/jan/dev/repos/Immich-Slideshow

You are an ADVERSARIAL VERIFIER for requirement traceability in module(s) **${moduleList(m)}**.
Test files live in \`Packages/${m.pkg}/Tests/\`.

Another agent added \`// @covers FR-XXX-NN\` annotations claiming certain tests prove certain
requirements. **Your job is to refute them.** You are deliberately NOT shown that agent's
reasoning, so you cannot anchor on it.

## Method — requirement-first, deliberately not tag-first

1. Read the relevant \`specs/<module>/spec.md\` and note what each requirement actually demands.
2. Read the test files under \`Packages/${m.pkg}/Tests/\`.
3. For each requirement, independently work out which test — if any — proves it, BEFORE looking
   at what the tags claim.
4. Only then read the \`@covers\` tags and compare against your own conclusion.

## Verdict rules

- **CONFIRMED** — only if you can quote the SPECIFIC assertion (the \`#expect(...)\` /
  \`XCTAssert...\` line, or the precise observable state check) that constrains the requirement.
  Put that literal line in \`evidence\`. "The test looks related" is not evidence.
- **REFUTED** — everything else. Default to REFUTED. Refute when: the test asserts something
  adjacent but not the requirement's substance; it proves a mechanism where the requirement
  states an outcome (or vice versa); it proves only part of a multi-clause requirement while the
  tag implies the whole; the assertion is vacuous or tautological; or the requirement belongs to
  another layer. In \`evidence\`, state what the test actually asserts instead.

The sharpest refutation is a mutation argument: "replacing X with a trivial stub keeps this test
green, therefore it does not constrain the requirement." Prefer that whenever it applies — it is
a fact rather than an opinion.

Being unable to find fault is a valid outcome — do not manufacture objections. But a tag you
merely find plausible is REFUTED, not CONFIRMED. The standard is a quotable assertion.

Also report \`missedCoverage\`: requirements you found a genuinely proving test for that carry no
tag — the opposite error, equally worth knowing.

## Constraints

- **READ ONLY.** Do not edit, add, or remove anything. Do not fix what you find. Report only.
- Judge only the in-scope modules' requirements. Ignore tags for other modules.

Be concrete and terse. Every CONFIRMED must carry a literal quoted assertion.`
}

phase('Tag')

const results = await pipeline(
  MODULES,
  (m) =>
    agent(tagPrompt(m), { label: `tag:${m.id}`, phase: 'Tag', schema: TAG_SCHEMA }),
  (tagResult, m) =>
    agent(verifyPrompt(m), { label: `verify:${m.id}`, phase: 'Verify', schema: VERDICT_SCHEMA })
      .then((v) => ({ module: m.id, pkg: m.pkg, tag: tagResult, verify: v })),
)

const summary = results.filter(Boolean).map((r) => {
  const verdicts = (r.verify && r.verify.verdicts) || []
  const refuted = verdicts.filter((v) => v.verdict === 'REFUTED')
  return {
    module: r.module,
    pkg: r.pkg,
    claimed: ((r.tag && r.tag.tagged) || []).length,
    confirmed: verdicts.length - refuted.length,
    refuted: refuted.length,
    refutedDetail: refuted,
    missedCoverage: (r.verify && r.verify.missedCoverage) || [],
    gaps: (r.tag && r.tag.gaps) || [],
    misleadingMentions: (r.tag && r.tag.misleadingMentions) || [],
    testsGreen: r.tag && r.tag.testsGreen,
  }
})

log(`tagged+verified ${summary.length} entries`)
for (const s of summary) {
  const rate = s.confirmed + s.refuted ? Math.round((100 * s.refuted) / (s.confirmed + s.refuted)) : 0
  log(`${s.module}: claimed ${s.claimed}, confirmed ${s.confirmed}, refuted ${s.refuted} (${rate}%)`)
}

return summary
