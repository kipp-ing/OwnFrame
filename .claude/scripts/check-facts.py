#!/usr/bin/env python3
"""Check product-facts.yaml (and, when present, Design/AppStore/copy-rules.yaml).

Fails on:
  - schema violations (unknown verdict/gated/implementation values, duplicate or malformed ids)
  - evidence that points at a missing file or past the end of it
  - intent ids naming a spec requirement (FR-/SC-) that no spec defines
  - copy rules citing a fact id that does not exist

Warns (exit 0, or 1 with --strict) when a file cited as evidence changed since
`verified_commit`: the fact behind it has to be re-checked against the code.

Usage: .claude/scripts/check-facts.py [--strict]
"""
import os
import re
import subprocess
import sys
from pathlib import Path

import yaml

ROOT = Path(os.environ.get("OWNFRAME_ROOT", Path(__file__).resolve().parents[2]))
FACTS = Path(os.environ.get("FACTS_FILE", ROOT / "product-facts.yaml"))
COPY_RULES = Path(os.environ.get("COPY_RULES_FILE", ROOT / "Design/AppStore/copy-rules.yaml"))

VERDICTS = {"does", "does_not", "partial", "deferred", "planned"}
GATED = {"free", "supporter", "n/a"}
IMPLEMENTATION = {"verified", "mismatch", "unverified", "n/a"}
PREFIXES = {"SRC", "PLAY", "LOOK", "UNATT", "REMOTE", "SHORTCUT", "PRIV", "PAY", "PLAT"}
ID_RE = re.compile(r"^([A-Z]+)-\d{2,3}$")
EVIDENCE_RE = re.compile(r"^(?P<path>[^:\s]+)(?::(?P<line>\d+))?")
REQ_RE = re.compile(r"\b(?:FR|SC)-\d{3,4}-\d{2,3}\b")


def spec_requirement_ids():
    ids = set()
    for spec in (ROOT / "specs").glob("*/spec.md"):
        ids.update(REQ_RE.findall(spec.read_text(encoding="utf-8")))
    return ids


def changed_since(commit, paths):
    if not commit or not paths:
        return set()
    out = subprocess.run(
        ["git", "-C", str(ROOT), "diff", "--name-only", f"{commit}..HEAD", "--", *sorted(paths)],
        capture_output=True, text=True,
    )
    if out.returncode != 0:
        raise SystemExit(f"verified_commit {commit!r} is not a valid commit: {out.stderr.strip()}")
    return set(out.stdout.split())


def main():
    strict = "--strict" in sys.argv[1:]
    errors, warnings = [], []
    doc = yaml.safe_load(FACTS.read_text(encoding="utf-8"))
    facts = doc.get("facts") or []
    if not facts:
        errors.append("product-facts.yaml has no facts")
    if not doc.get("principles"):
        errors.append("product-facts.yaml has no principles")
    if not doc.get("verified_commit"):
        errors.append("product-facts.yaml has no verified_commit")

    known_reqs = spec_requirement_ids()
    ids, evidence_files = set(), {}
    line_counts = {}

    for fact in facts:
        fid = fact.get("id", "<missing id>")
        m = ID_RE.match(str(fid))
        if not m or m.group(1) not in PREFIXES:
            errors.append(f"{fid}: malformed id or unknown prefix")
        if fid in ids:
            errors.append(f"{fid}: duplicate id")
        ids.add(fid)
        if not str(fact.get("fact", "")).strip():
            errors.append(f"{fid}: empty fact")
        for key, allowed in (("verdict", VERDICTS), ("gated", GATED), ("implementation", IMPLEMENTATION)):
            if fact.get(key) not in allowed:
                errors.append(f"{fid}: {key}={fact.get(key)!r} not in {sorted(allowed)}")
        if fact.get("implementation") == "mismatch" and not fact.get("mismatch"):
            errors.append(f"{fid}: implementation is mismatch but no mismatch text")
        # An absence ("does_not") has no line to point at; everything else verified needs one.
        if fact.get("implementation") == "verified" and not fact.get("evidence") and fact.get("verdict") != "does_not":
            errors.append(f"{fid}: verified without evidence")
        for ref in fact.get("intent") or []:
            for req in REQ_RE.findall(str(ref)):
                if req not in known_reqs:
                    errors.append(f"{fid}: intent {req} is not defined in any spec")
        for ev in fact.get("evidence") or []:
            em = EVIDENCE_RE.match(str(ev))
            path = ROOT / em.group("path")
            if not path.is_file():
                errors.append(f"{fid}: evidence file missing: {em.group('path')}")
                continue
            if em.group("line"):
                if path not in line_counts:
                    line_counts[path] = sum(1 for _ in path.open(encoding="utf-8", errors="replace"))
                if int(em.group("line")) > line_counts[path]:
                    errors.append(f"{fid}: evidence {ev} is past the end of the file")
            evidence_files.setdefault(em.group("path"), set()).add(fid)

    for path in sorted(changed_since(doc.get("verified_commit"), evidence_files)):
        warnings.append(f"re-verify {', '.join(sorted(evidence_files[path]))}: {path} changed since verified_commit")

    if COPY_RULES.is_file():
        rules = yaml.safe_load(COPY_RULES.read_text(encoding="utf-8"))
        for section in ("banned_claims", "allowed_claims"):
            for entry in rules.get(section) or []:
                for cited in entry.get("fact_ids") or []:
                    if cited not in ids:
                        errors.append(f"copy-rules {section}: cites unknown fact {cited}")

    for w in warnings:
        print(f"warning: {w}")
    for e in errors:
        print(f"error: {e}")
    print(f"{len(facts)} facts, {len(errors)} errors, {len(warnings)} re-verify warnings")
    return 1 if errors or (strict and warnings) else 0


if __name__ == "__main__":
    sys.exit(main())
