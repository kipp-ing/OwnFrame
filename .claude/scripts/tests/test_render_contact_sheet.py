"""test_render_contact_sheet.py — unit tests for render-contact-sheet.py (9010).

Written FIRST per this repo's TDD policy: at the point this file was created,
`.claude/scripts/render-contact-sheet.py` did not exist, so every test below failed with an
import error. The implementation was then written until this file went green.

Run with:

    cd /Users/jan/dev/repos/Immich-Slideshow
    python3 -m unittest discover -s .claude/scripts/tests -v

Scope: PURE logic only, same policy as test_render_store_screenshots.py — ImageMagick is never
invoked by these tests. The tool's whole point is to wrap render-store-screenshots.py rather
than reimplement rendering, so what needs covering here is: parsing that renderer's own
stdout/stderr protocol ("rendered: <path>" / "skip: slot '<id>' ... missing <kind> <path>"),
the label/reason text built from the manifest, and the ImageMagick argv construction (captured
via a monkeypatched subprocess.run, never executed) — not pixels.

Import mechanics: hyphenated filename, loaded once by absolute path via
`importlib.util.spec_from_file_location`, exactly as the renderer's own test file does.
"""

from __future__ import annotations

import importlib.util
import sys
import unittest
from pathlib import Path

TEST_FILE = Path(__file__).resolve()
MODULE_PATH = TEST_FILE.parents[1] / "render-contact-sheet.py"


def _load_module():
    spec = importlib.util.spec_from_file_location("render_contact_sheet", MODULE_PATH)
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


rcs = _load_module()


# --------------------------------------------------------------------------------------
# 1. Parsing the renderer's own stdout/stderr protocol.
# --------------------------------------------------------------------------------------

class TestParseRendererOutput(unittest.TestCase):
    def test_rendered_line_maps_slot_id_to_path(self):
        stdout = "summary: 1 rendered, 0 skipped, 1 requested\nrendered: /out/ipad/en/01-drawer.png\n"
        rendered, missing = rcs.parse_renderer_output(stdout, "")
        self.assertEqual(rendered, {"01-drawer": Path("/out/ipad/en/01-drawer.png")})
        self.assertEqual(missing, {})

    def test_skip_line_collects_missing_kind_per_slot(self):
        stderr = (
            "skip: slot '02-favourites' device=ipad locale=en: missing template "
            "/repo/Design/AppStore/templates/ipad/slot-02.svg\n"
            "skip: slot '02-favourites' device=ipad locale=en: missing scene "
            "/repo/Design/AppStore/scenes/ipad/02-favourites.jpg\n"
        )
        rendered, missing = rcs.parse_renderer_output("", stderr)
        self.assertEqual(rendered, {})
        self.assertEqual(missing, {"02-favourites": ["template", "scene"]})

    def test_ignores_unrelated_lines(self):
        stdout = "some other renderer chatter\nsummary: 0 rendered, 1 skipped, 1 requested\n"
        stderr = "a warning that is not a skip line\n"
        rendered, missing = rcs.parse_renderer_output(stdout, stderr)
        self.assertEqual(rendered, {})
        self.assertEqual(missing, {})

    def test_multiple_rendered_and_missing_slots_together(self):
        stdout = "rendered: /out/ipad/en/01-drawer.png\nrendered: /out/ipad/en/03-source-choice.png\n"
        stderr = "skip: slot '05-new-photos' device=ipad locale=en: missing capture /x/05-hero-new-photos.png\n"
        rendered, missing = rcs.parse_renderer_output(stdout, stderr)
        self.assertEqual(set(rendered), {"01-drawer", "03-source-choice"})
        self.assertEqual(missing, {"05-new-photos": ["capture"]})


# --------------------------------------------------------------------------------------
# 2. Label text built from the manifest.
# --------------------------------------------------------------------------------------

class TestLabels(unittest.TestCase):
    SLOT = {
        "id": "01-drawer",
        "headline": {
            "de": ["Dein altes iPad.", "Jetzt ein Bilderrahmen."],
            "en": ["Your old iPad.", "Now a photo frame."],
        },
    }

    def test_short_headline_joins_lines_for_requested_locale(self):
        self.assertEqual(
            rcs.short_headline(self.SLOT, "en"), "Your old iPad. Now a photo frame."
        )
        self.assertEqual(
            rcs.short_headline(self.SLOT, "de"), "Dein altes iPad. Jetzt ein Bilderrahmen."
        )

    def test_short_headline_falls_back_to_english_for_unknown_locale(self):
        self.assertEqual(rcs.short_headline(self.SLOT, "fr"), "Your old iPad. Now a photo frame.")

    def test_short_headline_empty_when_slot_has_no_headline(self):
        self.assertEqual(rcs.short_headline({"id": "x"}, "en"), "")

    def test_missing_reason_dedupes_and_sorts(self):
        self.assertEqual(rcs.missing_reason(["scene", "template", "scene"]), "scene, template")

    def test_missing_reason_unknown_when_empty(self):
        self.assertEqual(rcs.missing_reason([]), "unknown")


# --------------------------------------------------------------------------------------
# 3. ImageMagick argv construction — never executed, only asserted.
# --------------------------------------------------------------------------------------

class TestArgvConstruction(unittest.TestCase):
    def test_thumbnail_command_resizes_and_labels(self):
        cmd = rcs.thumbnail_command(
            Path("/out/01-drawer.png"), Path("/work/tile-01-drawer.png"), label="01-drawer\nHeadline"
        )
        self.assertEqual(cmd[0], "magick")
        self.assertIn(str(Path("/out/01-drawer.png")), cmd)
        self.assertIn(f"{rcs.TILE_WIDTH}x", cmd)
        self.assertEqual(cmd[-1], str(Path("/work/tile-01-drawer.png")))
        self.assertIn("01-drawer\nHeadline", cmd)

    def test_placeholder_command_draws_flat_canvas_with_reason(self):
        cmd = rcs.placeholder_command(
            Path("/work/tile-05-new-photos.png"),
            label="05-new-photos\nHeadline",
            reason="capture, scene, template",
        )
        self.assertEqual(cmd[0], "magick")
        self.assertIn("xc:#2b2b2b", cmd)
        self.assertTrue(any("missing: capture, scene, template" in arg for arg in cmd))
        self.assertEqual(cmd[-1], str(Path("/work/tile-05-new-photos.png")))

    def test_montage_command_tiles_in_given_column_count(self):
        tiles = [Path("/work/a.png"), Path("/work/b.png"), Path("/work/c.png")]
        cmd = rcs.montage_command(tiles, columns=3, out=Path("/work/sheet.png"))
        self.assertEqual(cmd[0], "magick")
        self.assertIn("montage", cmd)
        for tile in tiles:
            self.assertIn(str(tile), cmd)
        self.assertIn("3x", cmd)
        self.assertEqual(cmd[-1], str(Path("/work/sheet.png")))


# --------------------------------------------------------------------------------------
# 4. Tile ordering follows manifest slot order, not renderer output order.
# --------------------------------------------------------------------------------------

class TestTileOrder(unittest.TestCase):
    def test_tiles_built_in_manifest_slot_order(self):
        slots = [{"id": "b", "headline": {}}, {"id": "a", "headline": {}}]
        rendered = {"a": Path("/out/a.png"), "b": Path("/out/b.png")}
        calls = []

        def fake_thumb(src, dst, *, label):
            calls.append(("thumb", dst.name))

        def fake_placeholder(dst, *, label, reason):
            calls.append(("placeholder", dst.name))

        rcs.build_tiles(
            slots, rendered=rendered, missing={}, locale="en", work_dir=Path("/work"),
            make_thumbnail=fake_thumb, make_placeholder=fake_placeholder,
        )
        self.assertEqual([name for _, name in calls], ["tile-b.png", "tile-a.png"])

    def test_missing_slot_uses_placeholder(self):
        slots = [{"id": "05-new-photos", "headline": {}}]
        calls = []
        rcs.build_tiles(
            slots, rendered={}, missing={"05-new-photos": ["capture"]}, locale="en",
            work_dir=Path("/work"),
            make_thumbnail=lambda *a, **k: calls.append("thumb"),
            make_placeholder=lambda *a, **k: calls.append("placeholder"),
        )
        self.assertEqual(calls, ["placeholder"])


if __name__ == "__main__":
    unittest.main()
