#!/usr/bin/env python3
"""strip-refuted.py — remove `@covers` tags an adversarial verifier refuted.

Second half of the tag-then-refute loop documented in `docs/traceability.md`. The
`covers-backfill-verified` workflow produces verdicts; this applies them.

Deliberately a script and not an agent step. Applying verdicts is pure mechanics — locate a
test, drop one id from the comment above it — and mechanics executed by a model is just a
slower, less predictable `sed` that might also "improve" something on the way past. The
judgement already happened in the verify stage; nothing here needs a model.

Matching is STRUCTURAL, not by line number: it finds the test function, then walks up a few
lines to the `@covers` comment. Line numbers reported by the verifier go stale the moment the
first tag is removed, so trusting them would corrupt the file after the first edit.

A tag line can carry several ids (`// @covers FR-100-02, FR-100-04`). Only the refuted id is
removed; the line survives with the rest. It is deleted only when nothing is left.

Usage:
  strip-refuted.py <workflow-result.json> [--dry-run]

Accepts either the raw Workflow task output (an object with a `result` array) or a bare array
of per-module summaries. Each entry needs `pkg` and `refutedDetail[] = {id, testName}`.

`--dry-run` caveat: when two refuted ids share one `@covers` line, each is previewed against
the unmodified file, so both report "kept" the other. A real run writes between steps, so the
second removes the now-empty line. The preview names the right targets; only the per-step
"kept" note is approximate.

Exit codes: 0 applied (or nothing to do) · 1 some refutations could not be located · 2 bad input.
"""

from __future__ import annotations

import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]

ID_RE = re.compile(r"(?:FR|SC)-\d{3,4}-\d{2}[a-z]?")

# How far above a `func` declaration the `@covers` line may sit. Enough to clear an `@Test`
# attribute, a `@MainActor`, and a short doc comment; small enough that it cannot wander into
# the previous test's annotation.
LOOKBACK = 6


def load(path: Path) -> list[dict]:
    try:
        data = json.loads(path.read_text())
    except (OSError, json.JSONDecodeError) as exc:
        sys.exit(f"error: cannot read {path}: {exc}")
    if isinstance(data, dict):
        data = data.get("result", [])
    if not isinstance(data, list):
        sys.exit("error: expected an array of module summaries, or an object with `result`")
    return data


def targets(summaries: list[dict]) -> list[tuple[str, str, str]]:
    """(package, requirement id, bare test function name) for every refuted tag."""
    out = []
    for mod in summaries:
        pkg = mod.get("pkg")
        if not pkg:
            continue
        for ref in mod.get("refutedDetail", []) or []:
            rid = ref.get("id")
            raw = ref.get("testName") or ""
            # Verifiers report names variously: "Class.someTest", "someTest (File.swift:12)".
            name = raw.split("(")[0].strip().split(".")[-1].strip()
            if rid and name:
                out.append((pkg, rid, name))
    return out


def strip_one(pkg: str, rid: str, fn: str, dry_run: bool) -> tuple[str, str]:
    """Remove `rid` from the @covers line above `fn`.

    Returns (status, detail) where status is one of:
      stripped   — the tag claimed `rid` and it was removed
      absent     — the test was found but never claimed `rid` (already stripped: a re-run)
      not-found  — no such test in this package

    `absent` and `not-found` are kept apart on purpose. Both leave the tree unchanged, but
    `absent` is a benign idempotent re-run while `not-found` means a refutation was silently
    dropped — a tag the verifier rejected is still standing somewhere. Collapsing them would
    hide the second behind the first.
    """
    root = ROOT / "Packages" / pkg / "Tests"
    if not root.is_dir():
        return ("not-found", f"{pkg}::{fn} -{rid}  (no such package)")
    decl = re.compile(rf"func\s+{re.escape(fn)}\s*\(")

    for path in sorted(root.rglob("*.swift")):
        lines = path.read_text().split("\n")
        idx = next((i for i, l in enumerate(lines) if decl.search(l)), None)
        if idx is None:
            continue

        for j in range(idx, max(-1, idx - LOOKBACK), -1):
            if "@covers" not in lines[j]:
                continue
            ids = ID_RE.findall(lines[j])
            if rid not in ids:
                return ("absent", f"{pkg}/{path.name}::{fn} -{rid}  (tag does not claim it)")
            keep = [x for x in ids if x != rid]
            if keep:
                indent = re.match(r"\s*", lines[j]).group(0)
                lines[j] = f"{indent}// @covers {', '.join(keep)}"
                action = f"kept {', '.join(keep)}"
            else:
                lines.pop(j)
                action = "line removed"
            if not dry_run:
                path.write_text("\n".join(lines))
            return ("stripped", f"{pkg}/{path.name}::{fn}  -{rid}  ({action})")

        # Test found, no @covers above it at all.
        return ("absent", f"{pkg}/{path.name}::{fn} -{rid}  (no @covers line)")

    return ("not-found", f"{pkg}::{fn} -{rid}  (test not found in package)")


def main() -> int:
    args = [a for a in sys.argv[1:] if a != "--dry-run"]
    dry_run = "--dry-run" in sys.argv[1:]
    if len(args) != 1:
        sys.exit(__doc__.split("Usage:")[1].split("Exit codes:")[0].strip())

    todo = targets(load(Path(args[0])))
    if not todo:
        print("no refuted tags to strip")
        return 0

    buckets: dict[str, list[str]] = {"stripped": [], "absent": [], "not-found": []}
    for pkg, rid, fn in todo:
        status, detail = strip_one(pkg, rid, fn, dry_run)
        buckets[status].append(detail)

    prefix = "would strip" if dry_run else "stripped"
    print(f"{prefix} {len(buckets['stripped'])}/{len(todo)}:")
    for line in buckets["stripped"]:
        print("  ", line)

    if buckets["absent"]:
        print(f"\nalready absent ({len(buckets['absent'])}) — idempotent re-run, no action needed:")
        for line in buckets["absent"]:
            print("  ", line)

    if buckets["not-found"]:
        print(
            f"\nNOT FOUND {len(buckets['not-found'])} — a refutation was dropped, so a tag the "
            "verifier rejected may still stand. Review by hand:",
            file=sys.stderr,
        )
        for line in buckets["not-found"]:
            print("  ", line, file=sys.stderr)
        return 1

    if not dry_run and buckets["stripped"]:
        pkgs = sorted({a.split("/")[0] for a in buckets["stripped"]})
        print("\nNow re-run the affected suites and CHECK THE TEST COUNT, not the exit code:")
        for p in pkgs:
            print(f"  swift test --package-path Packages/{p} 2>&1 | grep 'Test run with'")
    return 0


if __name__ == "__main__":
    sys.exit(main())
