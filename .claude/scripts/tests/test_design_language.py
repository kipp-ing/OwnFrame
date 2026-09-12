"""test_design_language.py — guards for the 9000 design language's checkable claims.

Written FIRST per this repo's TDD policy: at the point this file was created,
`AccentColor.colorset` declared no color at all (issue #58) and `SourceLibraryView.swift`
hardcoded `.tint(.blue)`, so the two tests below failed. The implementation was then written
until this file went green.

Scope: only the parts of `specs/9000-design-language/spec.md` that a file can actually be
checked against without a running app — SC-9000-04's two halves:

  1. `AccentColor.colorset` declares Messing `#E3A857` (FR-9000-13 + FR-9000-14).
  2. No view sets a tint that does not derive from it — i.e. no Swift source hardcodes a
     SwiftUI system color as a `.tint(...)`.

Deliberately NOT covered here, because a static check cannot see it: FR-9000-14's contrast
consequence (an accent-filled control must carry a near-black label). SwiftUI decides that
foreground at render time, so it is a simulator/visual check, recorded in the spec's SC list
rather than guarded here. Do not add a grep for `.borderedProminent` pretending otherwise — a
prominent button is legal, it is the *label color* that is constrained, and that is not in the
source text.

Run with:

    cd /Users/jan/dev/repos/Immich-Slideshow
    python3 -m unittest discover -s .claude/scripts/tests -v
"""

from __future__ import annotations

import json
import re
import unittest
from pathlib import Path

TEST_FILE = Path(__file__).resolve()
REPO_ROOT = TEST_FILE.parents[3]
ACCENT_COLORSET = REPO_ROOT / "OwnFrame" / "Assets.xcassets" / "AccentColor.colorset" / "Contents.json"

# FR-9000-14. Messing, decided 2026-09-01. sRGB.
MESSING = (0xE3, 0xA8, 0x57)

# The Swift trees a store screenshot can actually show. PurchaseKit ships its own UI and is
# swept too; test/preview material is excluded, since a preview tint is not a shipped tint.
SWIFT_ROOTS = (
    REPO_ROOT / "OwnFrame",
    REPO_ROOT / "Packages",
)

# `.tint(.blue)`, `.tint(.red)`, … — a system color passed straight to `tint`. `.tint(.white)`
# is exempt: white-on-photo chrome is FR-9000-19 territory (legibility over a photograph), not
# an accent, and the slideshow chrome depends on it.
HARDCODED_TINT = re.compile(
    r"\.tint\(\s*\.(?!white\b)(blue|red|green|orange|yellow|pink|purple|teal|indigo|mint|cyan|brown|gray|grey)\b"
)


def _swift_sources():
    for root in SWIFT_ROOTS:
        for path in sorted(root.rglob("*.swift")):
            parts = {p.lower() for p in path.parts}
            if any("test" in p for p in parts):
                continue
            yield path


def _parse_srgb_components(color_entry):
    """Return (r, g, b) as 0-255 ints from an asset-catalog color entry, or None."""
    components = color_entry.get("color", {}).get("components")
    if not components:
        return None
    out = []
    for key in ("red", "green", "blue"):
        raw = str(components.get(key, "")).strip()
        if raw.startswith("0x"):
            out.append(int(raw, 16))
        elif "." in raw:
            # Float form, 0.0-1.0. Round to the nearest 8-bit value.
            out.append(round(float(raw) * 255))
        elif raw:
            out.append(int(raw))
        else:
            return None
    return tuple(out)


class AccentColorTests(unittest.TestCase):
    """SC-9000-04, first half: the colorset declares Messing."""

    def test_colorset_file_exists(self):
        self.assertTrue(
            ACCENT_COLORSET.is_file(),
            f"AccentColor.colorset/Contents.json is missing at {ACCENT_COLORSET}",
        )

    def test_colorset_declares_messing(self):
        data = json.loads(ACCENT_COLORSET.read_text())
        colors = data.get("colors", [])
        self.assertTrue(colors, "AccentColor.colorset declares no colors at all (issue #58)")

        declared = [_parse_srgb_components(entry) for entry in colors]
        self.assertNotIn(
            None,
            declared,
            "every AccentColor entry must carry explicit sRGB components; an entry with only an "
            "`idiom` key is the empty colorset that made the app tint iOS blue (issue #58)",
        )
        for rgb in declared:
            self.assertEqual(
                rgb,
                MESSING,
                f"FR-9000-14 fixes the accent at Messing #E3A857; found "
                f"#{rgb[0]:02X}{rgb[1]:02X}{rgb[2]:02X}",
            )

    def test_colorset_is_srgb(self):
        data = json.loads(ACCENT_COLORSET.read_text())
        for entry in data.get("colors", []):
            color = entry.get("color", {})
            self.assertEqual(
                color.get("color-space"),
                "srgb",
                "the accent must be declared in sRGB — the store canvas is sRGB (FR-9010) and a "
                "display-P3 declaration would render a different hue there than on device",
            )


class TintDerivationTests(unittest.TestCase):
    """SC-9000-04, second half: no view sets a tint that does not derive from the accent."""

    def test_no_hardcoded_system_color_tint(self):
        offenders = []
        for path in _swift_sources():
            for lineno, line in enumerate(path.read_text().splitlines(), start=1):
                if HARDCODED_TINT.search(line):
                    rel = path.relative_to(REPO_ROOT)
                    offenders.append(f"{rel}:{lineno}: {line.strip()}")
        self.assertEqual(
            offenders,
            [],
            "FR-9000-13 requires every tint to derive from AccentColor; these hardcode a system "
            "color instead:\n  " + "\n  ".join(offenders),
        )


if __name__ == "__main__":
    unittest.main()
