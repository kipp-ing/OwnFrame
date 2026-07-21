#!/usr/bin/env python3
"""coverage.py — map requirement IDs (FR-NNN-NN / SC-NNN-NN) to the tests that prove them.

Answers the question the markdown status lines cannot: *which requirements are actually
covered, and at which layer?* Prose status ("153/0/9 green") rots silently — on 2026-07-21 a
recorded gate was false and a skip-guard had hidden a bug for a day. This script derives the
answer from the tree every time it runs, so it cannot go stale.

  Definitions   specs/*/spec.md            — the authoritative statement of a requirement
  Coverage      test sources + manual doc  — who claims to prove it, and where

Layers, cheapest first. The point of the tiering is to push each requirement DOWN to the
cheapest layer that can genuinely prove it (see docs/testing.md):

  host        Packages/*/Tests/**          swift test, seconds, no simulator
  app         Immich SlideshowTests/       app-hosted, simulator
  ui          Immich SlideshowUITests/     XCUITest, simulator, slow
  manual      docs/manual-verification.md  human, scarce — the tier to empty

Two grades of coverage, because the tree is mid-migration:

  strong   an explicit `@covers FR-1100-12` annotation — machine-checkable intent
  weak     a bare mention in a comment/string, today's informal convention

Weak references are counted so the baseline is truthful on day one instead of after
backfilling ~140 annotations. Treat `weak` as a backlog, not as coverage you can trust:
a mention proves someone thought about the requirement, not that the test asserts it.

ID grammar, all forms verified present in this repo:

  FR-1100-12     canonical                  SC-310-01
  FR-1100-03a    letter-suffixed amendment
  FR-1000-01…12  inclusive range            (also `...`) — expands to 12 ids
  FR-1000-05/06  slash-combined             — shares the feature root

The feature segment is 3 OR 4 digits. A `[0-9]{3}` regex silently misses every 1000/1100-series
id and reports already-covered files as untested — that mistake is why this is spelled out here.

Deliberately NOT matched: `T034` (task ids), `US2` (user stories), `R11` (risk register). They
sit adjacent to real ids in the same comments and look similar.

Usage:
  coverage.py                 human-readable report
  coverage.py --json          machine-readable, for CI
  coverage.py --uncovered     just the uncovered ids, one per line
  coverage.py --check         exit 1 if any requirement has no coverage at all (CI gate)

Exit codes: 0 ok · 1 --check found uncovered requirements · 2 bad invocation.
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from collections import defaultdict
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]

# --- ID grammar -------------------------------------------------------------------------

# Canonical single id. Feature segment is 3-4 digits; optional lowercase amendment suffix.
ID_RE = re.compile(r"\b(FR|SC)-([0-9]{3,4})-([0-9]{2})([a-z]?)\b")

# `FR-1000-01…12` / `FR-1000-01...12` — inclusive range over the last segment.
RANGE_RE = re.compile(r"\b(FR|SC)-([0-9]{3,4})-([0-9]{2})[a-z]?\s*(?:…|\.\.\.|\.\.)\s*([0-9]{2})\b")

# `FR-1000-05/06` — slash-combined, sharing kind + feature.
SLASH_RE = re.compile(r"\b(FR|SC)-([0-9]{3,4})-([0-9]{2})[a-z]?((?:/[0-9]{2}[a-z]?)+)\b")

# Explicit annotation: `@covers FR-1100-12, SC-1100-03`. Everything up to end of line is
# scanned for ids, so any separator style works.
COVERS_RE = re.compile(r"@covers\b([^\n]*)")

# A requirement DEFINITION, as opposed to a mention. Verified to match all 467 definitions
# across the 20 spec modules, in exactly this shape:
#
#     - **FR-100-01**: The client MUST accept an HTTPS server base URL...
#     - **FR-1100-03a** *(free telemetry)*: Publishing read-only status...
#
# The trailing colon is load-bearing. Without it this also matches inline cross-references
# such as `Binding: **SC-500-07** (never co-visible with chrome)`, which are citations of a
# requirement defined elsewhere — counting those would inflate the denominator and, worse,
# attribute a requirement to whichever module happened to mention it first.
DEFINITION_RE = re.compile(
    r"^\s*-\s*\*\*(FR|SC)-([0-9]{3,4})-([0-9]{2})([a-z]?)\*\*"
    r"(?:\s*\*\([^)]*\)\*)?"  # optional italic annotation, e.g. *(added 2026-07-19)*
    r"\s*:",
    re.MULTILINE,
)


def canonical(kind: str, feature: str, num: str, suffix: str = "") -> str:
    return f"{kind}-{feature}-{num}{suffix}"


def extract_ids(text: str) -> set[str]:
    """Every requirement id in `text`, with ranges and slash-groups expanded.

    Order matters: ranges and slash-groups are expanded first, because the plain-id regex
    would otherwise capture only their leading id and silently drop the rest.
    """
    found: set[str] = set()

    for kind, feature, start, end in RANGE_RE.findall(text):
        lo, hi = int(start), int(end)
        if lo <= hi and hi - lo < 100:  # guard against a typo'd range exploding the set
            for n in range(lo, hi + 1):
                found.add(canonical(kind, feature, f"{n:02d}"))

    for kind, feature, first, rest in SLASH_RE.findall(text):
        found.add(canonical(kind, feature, first))
        for part in rest.split("/"):
            if part:
                m = re.fullmatch(r"([0-9]{2})([a-z]?)", part)
                if m:
                    found.add(canonical(kind, feature, m.group(1), m.group(2)))

    for kind, feature, num, suffix in ID_RE.findall(text):
        found.add(canonical(kind, feature, num, suffix))

    return found


# --- layers -----------------------------------------------------------------------------

LAYERS = ("host", "app", "ui", "manual")

# Ordered cheapest-first; first match wins.
LAYER_GLOBS: tuple[tuple[str, str], ...] = (
    ("host", "Packages/*/Tests/**/*.swift"),
    ("app", "Immich SlideshowTests/*.swift"),
    ("ui", "Immich SlideshowUITests/*.swift"),
)

MANUAL_DOC = Path("docs/manual-verification.md")


def test_files() -> list[tuple[str, Path]]:
    """(layer, path) for every test source, excluding vendored `.build` trees.

    Every package carries a populated `.build` with its dependencies' own tests; scanning
    those would attribute other projects' code to our requirements.
    """
    out: list[tuple[str, Path]] = []
    for layer, glob in LAYER_GLOBS:
        for path in sorted(ROOT.glob(glob)):
            if ".build" in path.parts:
                continue
            out.append((layer, path))
    return out


def spec_files() -> list[Path]:
    return sorted(p for p in ROOT.glob("specs/*/spec.md") if p.is_file())


# --- scanning ---------------------------------------------------------------------------


def scan_definitions() -> dict[str, str]:
    """id -> defining module (the spec directory name).

    Only `specs/*/spec.md` defines requirements; plan/tasks/research/quickstart merely cite
    them. `1000-apple-tv/quickstart.md` in particular restates three SC ids in byte-identical
    definition shape, so globbing by shape instead of by filename would invent duplicates.
    """
    defined: dict[str, str] = {}
    for spec in spec_files():
        module = spec.parent.name
        text = spec.read_text(encoding="utf-8", errors="replace")
        for kind, feature, num, suffix in DEFINITION_RE.findall(text):
            defined.setdefault(canonical(kind, feature, num, suffix), module)
    return defined


def scan_coverage() -> tuple[dict[str, dict[str, set[str]]], dict[str, set[str]]]:
    """Returns (coverage, layers_by_id).

    coverage: id -> {"strong": {paths}, "weak": {paths}}
    layers_by_id: id -> {layers it is covered at}
    """
    coverage: dict[str, dict[str, set[str]]] = defaultdict(lambda: {"strong": set(), "weak": set()})
    layers: dict[str, set[str]] = defaultdict(set)

    for layer, path in test_files():
        text = path.read_text(encoding="utf-8", errors="replace")
        rel = str(path.relative_to(ROOT))

        strong: set[str] = set()
        for annotation in COVERS_RE.findall(text):
            strong |= extract_ids(annotation)

        for rid in strong:
            coverage[rid]["strong"].add(rel)
            layers[rid].add(layer)

        # Everything else mentioned in the file is a weak reference.
        for rid in extract_ids(text) - strong:
            coverage[rid]["weak"].add(rel)
            layers[rid].add(layer)

    manual = ROOT / MANUAL_DOC
    if manual.exists():
        for rid in extract_ids(manual.read_text(encoding="utf-8", errors="replace")):
            coverage[rid]["weak"].add(str(MANUAL_DOC))
            layers[rid].add("manual")

    return coverage, layers


# --- reporting --------------------------------------------------------------------------


def build_report() -> dict:
    defined = scan_definitions()
    coverage, layers = scan_coverage()

    rows = []
    for rid, module in sorted(defined.items(), key=_sort_key):
        cov = coverage.get(rid, {"strong": set(), "weak": set()})
        lay = sorted(layers.get(rid, set()), key=LAYERS.index)
        rows.append(
            {
                "id": rid,
                "module": module,
                "strong": sorted(cov["strong"]),
                "weak": sorted(cov["weak"]),
                "layers": lay,
                # "manual only" is the interesting failure mode: a requirement whose sole
                # proof is a human remembering to check it.
                "manual_only": lay == ["manual"],
                "covered": bool(cov["strong"] or cov["weak"]),
            }
        )

    # Ids cited by tests/docs that no spec.md defines — typos, or requirements that were
    # renamed/removed while their tests kept the old citation.
    orphans = sorted(set(coverage) - set(defined), key=_sort_key)

    return {
        "defined": len(defined),
        "rows": rows,
        "orphans": orphans,
        "totals": _totals(rows),
    }


def _sort_key(item):
    """Sort by feature number NUMERICALLY — string order puts 1000 and 1100 before 110."""
    rid = item[0] if isinstance(item, tuple) else item
    m = ID_RE.match(rid)
    if not m:
        return (0, rid, 0, "")
    return (int(m.group(2)), m.group(1), int(m.group(3)), m.group(4))


def _module_key(module: str):
    """Order modules by their numeric prefix — `1000-apple-tv` sorts after `900-…`, not after `100-…`."""
    head = module.split("-", 1)[0]
    return (int(head), module) if head.isdigit() else (1 << 30, module)


def _totals(rows: list[dict]) -> dict:
    return {
        "covered": sum(1 for r in rows if r["covered"]),
        "strong": sum(1 for r in rows if r["strong"]),
        "weak_only": sum(1 for r in rows if r["weak"] and not r["strong"]),
        "uncovered": sum(1 for r in rows if not r["covered"]),
        "manual_only": sum(1 for r in rows if r["manual_only"]),
        "automated": sum(1 for r in rows if set(r["layers"]) & {"host", "app", "ui"}),
    }


def render(report: dict) -> str:
    t = report["totals"]
    n = report["defined"]
    lines = [
        "Requirement TRACEABILITY",
        "=" * 64,
        "This measures whether a requirement can be TRACED to a test, not whether it is",
        "tested. `uncovered` means no test or checklist cites the id — the code is very",
        "likely tested anyway. ImmichClient, for example, has 73 tests and cites no ids at",
        "all. Read these numbers as 'how much of the suite can we audit', not as risk.",
        "",
        f"{n} requirements defined in specs/*/spec.md",
        "",
        f"  traceable          {t['covered']:>4}  ({_pct(t['covered'], n)})",
        f"    @covers          {t['strong']:>4}  machine-checkable intent",
        f"    mention only     {t['weak_only']:>4}  a mention is not an assertion — backfill target",
        f"  untraceable        {t['uncovered']:>4}  ({_pct(t['uncovered'], n)})",
        "",
        f"  automated          {t['automated']:>4}  cited at host/app/ui",
        f"  manual only        {t['manual_only']:>4}  sole cited proof is a human remembering",
        "",
    ]

    by_module: dict[str, list[dict]] = defaultdict(list)
    for row in report["rows"]:
        by_module[row["module"]].append(row)

    lines.append("Per module")
    lines.append("-" * 64)
    lines.append(f"{'module':<28}{'total':>6}{'traced':>9}{'@covers':>9}{'manual':>8}")
    for module in sorted(by_module, key=_module_key):
        rs = by_module[module]
        lines.append(
            f"{module:<28}{len(rs):>6}"
            f"{sum(1 for r in rs if r['covered']):>9}"
            f"{sum(1 for r in rs if r['strong']):>9}"
            f"{sum(1 for r in rs if r['manual_only']):>8}"
        )

    uncovered = [r for r in report["rows"] if not r["covered"]]
    if uncovered:
        lines += ["", "Uncovered — no test or checklist item cites these", "-" * 64]
        cur = None
        for row in uncovered:
            if row["module"] != cur:
                cur = row["module"]
                lines.append(f"  {cur}")
            lines.append(f"    {row['id']}")

    manual_only = [r for r in report["rows"] if r["manual_only"]]
    if manual_only:
        lines += [
            "",
            "Manual only — candidates to push down a tier",
            "-" * 64,
            "  (StoreKitClientTests moved manual->app on 2026-07-21 once the real blocker was",
            "   found; assume others are similarly reducible until proven otherwise)",
        ]
        for row in manual_only:
            lines.append(f"    {row['id']:<16}{row['module']}")

    if report["orphans"]:
        lines += [
            "",
            "Orphan citations — cited by tests/docs, defined by no spec.md",
            "-" * 64,
            "  (a typo, or a requirement renamed while its citation was left behind)",
        ]
        for rid in report["orphans"]:
            lines.append(f"    {rid}")

    return "\n".join(lines) + "\n"


def _pct(part: int, whole: int) -> str:
    return f"{(100.0 * part / whole):.0f}%" if whole else "n/a"


def main() -> int:
    ap = argparse.ArgumentParser(description="Requirement -> test coverage matrix.")
    ap.add_argument("--json", action="store_true", help="machine-readable output")
    ap.add_argument("--uncovered", action="store_true", help="uncovered ids only, one per line")
    ap.add_argument("--check", action="store_true", help="exit 1 if anything is uncovered")
    args = ap.parse_args()

    report = build_report()

    if args.json:
        print(json.dumps(report, indent=2, default=list))
    elif args.uncovered:
        for row in report["rows"]:
            if not row["covered"]:
                print(row["id"])
    else:
        sys.stdout.write(render(report))

    if args.check and report["totals"]["uncovered"]:
        print(
            f"\ncoverage: {report['totals']['uncovered']} requirement(s) with no coverage",
            file=sys.stderr,
        )
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
