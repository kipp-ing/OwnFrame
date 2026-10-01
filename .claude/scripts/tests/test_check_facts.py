"""test_check_facts.py — check-facts.py must still run where `verified_commit` is unknown.

Written FIRST per this repo's TDD policy. The public mirror is rebuilt by
`publish-public.sh` with git-filter-repo, which rewrites every commit hash, so the
private repo's `verified_commit` never exists there. check-facts.py used to abort with
"is not a valid commit" in the mirror; it must instead skip only the staleness check,
say so in a warning, and keep every other check (schema, evidence, intent ids).

Run with:

    python3 -m unittest discover -s .claude/scripts/tests -v
"""

from __future__ import annotations

import os
import subprocess
import sys
import tempfile
import textwrap
import unittest
from pathlib import Path

SCRIPT = Path(__file__).resolve().parents[1] / "check-facts.py"

FACTS = textwrap.dedent("""\
    schema: 1
    verified_commit: {commit}
    principles:
      - id: P-01
        principle: "Shows photos."
    facts:
      - id: SRC-01
        fact: "Shows an album."
        verdict: does
        gated: free
        implementation: verified
        evidence: ["src.txt"]
        intent: {intent}
    """)


def git(root: Path, *args: str) -> str:
    return subprocess.run(["git", "-C", str(root), *args], check=True,
                          capture_output=True, text=True).stdout.strip()


class RepoCase(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.root = Path(self.tmp.name)
        git(self.root, "init", "-q")
        git(self.root, "config", "user.email", "t@example.invalid")
        git(self.root, "config", "user.name", "t")
        (self.root / "specs").mkdir()
        (self.root / "src.txt").write_text("one\n")
        git(self.root, "add", "src.txt")
        git(self.root, "commit", "-q", "-m", "init")

    def tearDown(self):
        self.tmp.cleanup()

    def run_check(self, commit: str, intent: str = "[]") -> subprocess.CompletedProcess:
        (self.root / "product-facts.yaml").write_text(FACTS.format(commit=commit, intent=intent))
        env = dict(os.environ, OWNFRAME_ROOT=str(self.root),
                   COPY_RULES_FILE=str(self.root / "missing-copy-rules.yaml"))
        return subprocess.run([sys.executable, str(SCRIPT)], env=env,
                              capture_output=True, text=True)

class CheckFactsCommitTests(RepoCase):
    def test_unknown_commit_skips_staleness_check_with_a_warning(self):
        result = self.run_check("8315d36")  # not in this history, as in the public mirror
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("staleness check skipped", result.stdout)
        self.assertIn("1 facts, 0 errors", result.stdout)

    def test_unknown_commit_fails_under_strict(self):
        result = self.run_check("8315d36")
        env_strict = subprocess.run(
            [sys.executable, str(SCRIPT), "--strict"],
            env=dict(os.environ, OWNFRAME_ROOT=str(self.root),
                     COPY_RULES_FILE=str(self.root / "missing-copy-rules.yaml")),
            capture_output=True, text=True)
        self.assertEqual(env_strict.returncode, 1, env_strict.stdout + env_strict.stderr)

    def test_known_commit_still_reports_changed_evidence(self):
        base = git(self.root, "rev-parse", "--short", "HEAD")
        (self.root / "src.txt").write_text("two\n")
        git(self.root, "commit", "-qam", "change")
        result = self.run_check(base)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("re-verify SRC-01: src.txt changed since verified_commit", result.stdout)


class CheckFactsIntentTests(RepoCase):
    """The mirror also lacks specs/9010-store-presentation (excluded by publish-public.sh)."""

    def head(self) -> str:
        return git(self.root, "rev-parse", "--short", "HEAD")

    def test_intent_in_a_spec_absent_from_this_repo_is_a_warning(self):
        result = self.run_check(self.head(), '["FR-9010-10"]')
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("spec 9010 is not in this repo", result.stdout)

    def test_unknown_intent_in_a_present_spec_is_still_an_error(self):
        spec = self.root / "specs" / "9010-store-presentation"
        spec.mkdir()
        (spec / "spec.md").write_text("- **FR-9010-01**: something\n")
        result = self.run_check(self.head(), '["FR-9010-10"]')
        self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
        self.assertIn("intent FR-9010-10 is not defined in any spec", result.stdout)


if __name__ == "__main__":
    unittest.main()
