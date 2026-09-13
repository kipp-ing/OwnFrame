"""test_build_slot_template.py — unit tests for build-slot-template.py (9010).

Written FIRST, per this repo's TDD policy: at the point this file was created
`.claude/scripts/build-slot-template.py` did not exist and every test below failed on the
import. What it replaces is `tmp/story-low/build-preview-slots.py`, a session scratchpad script
the 2026-09-12 handover called out as "the one piece of this loop living only in a session
scratchpad" and said should be rewritten here with tests the next time the loop ran. It ran.

Scope: PURE logic. ImageMagick and `measure-scene-cutout` are never invoked — the builder takes
an already-measured report dict, which is exactly the seam that makes the geometry testable.
Covered: the scene `<image>` placement under a zoomed crop (the case the scratchpad version got
away with ignoring, because at plain cover fit the horizontal crop offset happened to be zero),
the clip polygon and screenshot box pass-through, the two text bands, and the structural
contract `render-store-screenshots.py` relies on — ids, two tspans per text block, and a
`preserveAspectRatio` the renderer is allowed to override.
"""

from __future__ import annotations

import importlib.util
import re
import sys
import unittest
import xml.etree.ElementTree as ET
from pathlib import Path

TEST_FILE = Path(__file__).resolve()
MODULE_PATH = TEST_FILE.parents[1] / "build-slot-template.py"

_spec = importlib.util.spec_from_file_location("build_slot_template", MODULE_PATH)
bst = importlib.util.module_from_spec(_spec)
sys.modules["build_slot_template"] = bst
_spec.loader.exec_module(bst)

SVG_NS = "http://www.w3.org/2000/svg"


def measurement(*, scaled_width=2400.0, scaled_height=3424.0, crop_x=168.0, crop_y=418.0,
                points="491.06,230.94 1884.25,230.28 1908.81,2132.09 476.55,2134.33",
                bbox=None) -> dict:
    """A measure-scene-cutout report, trimmed to the keys the builder reads.

    The defaults are real: generated scene 02-kitchen at `--zoom max`, where the scene is used
    pixel for pixel (scale 1.0) and BOTH crop offsets are non-zero.
    """
    if bbox is None:
        bbox = {"x": 476.55, "y": 230.28, "width": 1432.26, "height": 1904.05}
    return {
        "canvas": {
            "width": 2064, "height": 2752,
            "scale": 1.0,
            "scaled_width": scaled_width, "scaled_height": scaled_height,
            "crop": {"x": crop_x, "y": crop_y, "zoom": 1.1628, "headroom_px": 418.0,
                     "footroom_px": 430.0},
            "bbox_px": bbox,
        },
        "svg": {"clip_polygon_points": points},
    }


def parse(svg_text: str) -> ET.Element:
    return ET.fromstring(svg_text)


def by_id(root: ET.Element, wanted: str) -> ET.Element:
    for el in root.iter():
        if el.get("id") == wanted:
            return el
    raise AssertionError(f'no element with id="{wanted}"')


class TestSceneImagePlacement(unittest.TestCase):
    """The scene <image> is positioned so the measured crop lands on the canvas.

    The scratchpad version hardcoded x="0". That was true only by luck: at a plain cover fit of
    a 2064-wide scene onto a 2064-wide canvas the horizontal overflow is zero, so there is
    nothing to offset. Zooming in crops horizontally too, and a hardcoded zero then slides the
    whole room sideways out from under its own screen cut-out.
    """

    def test_scene_box_is_the_scaled_size(self):
        root = parse(bst.slot_template_svg(measurement(), slot="02", scene="02-kitchen.png"))
        scene = by_id(root, "scene")
        self.assertAlmostEqual(float(scene.get("width")), 2400.0, places=2)
        self.assertAlmostEqual(float(scene.get("height")), 3424.0, places=2)

    def test_scene_is_offset_by_the_negated_crop_on_both_axes(self):
        root = parse(bst.slot_template_svg(measurement(), slot="02", scene="02-kitchen.png"))
        scene = by_id(root, "scene")
        self.assertAlmostEqual(float(scene.get("x")), -168.0, places=2)
        self.assertAlmostEqual(float(scene.get("y")), -418.0, places=2)

    def test_a_zero_crop_still_places_the_scene_at_the_origin(self):
        root = parse(bst.slot_template_svg(measurement(crop_x=0.0, crop_y=0.0),
                                           slot="01", scene="01-hallway.png"))
        scene = by_id(root, "scene")
        self.assertAlmostEqual(float(scene.get("x")), 0.0, places=6)
        self.assertAlmostEqual(float(scene.get("y")), 0.0, places=6)

    def test_the_scene_box_covers_the_whole_canvas(self):
        root = parse(bst.slot_template_svg(measurement(), slot="02", scene="02-kitchen.png"))
        scene = by_id(root, "scene")
        x, y = float(scene.get("x")), float(scene.get("y"))
        self.assertLessEqual(x, 0.0)
        self.assertLessEqual(y, 0.0)
        self.assertGreaterEqual(x + float(scene.get("width")), 2064.0)
        self.assertGreaterEqual(y + float(scene.get("height")), 2752.0)


class TestScreenGeometry(unittest.TestCase):

    def test_clip_polygon_is_the_measured_one_verbatim(self):
        m = measurement()
        root = parse(bst.slot_template_svg(m, slot="02", scene="02-kitchen.png"))
        polygon = root.find(f".//{{{SVG_NS}}}clipPath/{{{SVG_NS}}}polygon")
        self.assertEqual(polygon.get("points"), m["svg"]["clip_polygon_points"])

    def test_screenshot_box_is_the_measured_bbox(self):
        root = parse(bst.slot_template_svg(measurement(), slot="02", scene="02-kitchen.png"))
        shot = by_id(root, "screenshot")
        self.assertAlmostEqual(float(shot.get("x")), 476.55, places=2)
        self.assertAlmostEqual(float(shot.get("y")), 230.28, places=2)
        self.assertAlmostEqual(float(shot.get("width")), 1432.26, places=2)
        self.assertAlmostEqual(float(shot.get("height")), 1904.05, places=2)

    def test_screenshot_is_clipped_to_the_screen_quad(self):
        root = parse(bst.slot_template_svg(measurement(), slot="02", scene="02-kitchen.png"))
        self.assertEqual(by_id(root, "screenshot").get("clip-path"), "url(#screen-quad)")

    def test_screenshot_is_drawn_under_the_scene_so_the_bezel_overlaps_it(self):
        # The scene is the photo WITH a hole in it; it has to paint after the capture or the
        # capture covers the device's own bezel.
        root = parse(bst.slot_template_svg(measurement(), slot="02", scene="02-kitchen.png"))
        order = [el.get("id") for el in root if el.get("id")]
        self.assertLess(order.index("screenshot"), order.index("scene"))


class TestTextBands(unittest.TestCase):
    """Two bands, top and bottom — Jan's 2026-09-12 call, kept intact from the approved look."""

    def test_both_text_elements_exist(self):
        root = parse(bst.slot_template_svg(measurement(), slot="02", scene="02-kitchen.png"))
        by_id(root, "headline")
        by_id(root, "subline")

    def test_each_text_block_ships_two_tspans(self):
        # render-store-screenshots.fill_text_lines takes tspan[0]'s attributes for the first
        # line and tspan[1]'s for every line after, and raises below two.
        root = parse(bst.slot_template_svg(measurement(), slot="02", scene="02-kitchen.png"))
        for element_id in ("headline", "subline"):
            tspans = list(by_id(root, element_id).findall(f"{{{SVG_NS}}}tspan"))
            self.assertGreaterEqual(len(tspans), 2, element_id)

    def test_headline_is_the_light_apple_weight(self):
        root = parse(bst.slot_template_svg(measurement(), slot="02", scene="02-kitchen.png"))
        self.assertEqual(by_id(root, "headline").get("font-weight"), "300")

    def test_subline_sits_in_the_bottom_band(self):
        root = parse(bst.slot_template_svg(measurement(), slot="02", scene="02-kitchen.png"))
        self.assertGreater(float(by_id(root, "subline").get("y")), 2752 * 0.85)

    def test_headline_sits_in_the_top_band(self):
        root = parse(bst.slot_template_svg(measurement(), slot="02", scene="02-kitchen.png"))
        self.assertLess(float(by_id(root, "headline").get("y")), 2752 * 0.2)

    def test_both_scrims_are_present_and_meet_the_canvas_edges(self):
        root = parse(bst.slot_template_svg(measurement(), slot="02", scene="02-kitchen.png"))
        rects = [el for el in root if el.tag == f"{{{SVG_NS}}}rect"
                 and (el.get("fill") or "").startswith("url(")]
        self.assertEqual(len(rects), 2)
        top, bottom = sorted(rects, key=lambda r: float(r.get("y")))
        self.assertAlmostEqual(float(top.get("y")), 0.0, places=6)
        self.assertAlmostEqual(
            float(bottom.get("y")) + float(bottom.get("height")), 2752.0, places=6)

    def test_scrims_paint_over_the_scene_not_under_it(self):
        root = parse(bst.slot_template_svg(measurement(), slot="02", scene="02-kitchen.png"))
        children = list(root)
        scene_at = next(i for i, el in enumerate(children) if el.get("id") == "scene")
        scrim_at = [i for i, el in enumerate(children)
                    if el.tag == f"{{{SVG_NS}}}rect" and (el.get("fill") or "").startswith("url(")]
        self.assertTrue(all(i > scene_at for i in scrim_at))


class TestAIMark(unittest.TestCase):
    """The 'AI generated' disclosure mark — bottom-right pill, glyph + two-line label, never
    overlapping the subline however many lines the slot's copy runs.

    Jan's 2026-09-13 pm review of the first pass: bottom-right instead of bottom-left, two lines
    instead of one, quieter (smaller type, lower opacities). The non-overlap guarantee this suite
    asserts is the VERTICAL one — the mark's top sits below the subline's last-line ink bottom
    (SUBLINE_INK_BOTTOM_FROM_EDGE), which is invariant to `subline_lines` — rather than a
    horizontal one: the bottom-right anchor puts the pill's left edge at roughly canvas width
    minus 258px for this measurement's 2064-wide canvas (pill_x ~= 1806), which is LEFT of (not
    clear of) the subline's maximum plausible right extent (canvas width - MARGIN_X = 1924px), so
    the two guarantees are not interchangeable here — only the vertical one holds, and only it is
    asserted below.
    """

    @staticmethod
    def _subline_ink_bottom(height: float = 2752) -> float:
        return (height - bst.SUBLINE_LAST_BASELINE_FROM_BOTTOM
                + bst.SUBLINE_SIZE * bst.SUBLINE_DESCENDER_RATIO)

    def test_ai_mark_group_carries_the_glyph_path_and_the_two_text_lines(self):
        root = parse(bst.slot_template_svg(measurement(), slot="02", scene="02-kitchen.png"))
        group = by_id(root, "ai-mark")
        self.assertEqual(group.tag, f"{{{SVG_NS}}}g")
        path = group.find(f"{{{SVG_NS}}}path")
        self.assertIsNotNone(path, "ai-mark has no glyph <path>")
        self.assertTrue((path.get("d") or "").strip(), "glyph path has no data")
        text = group.find(f"{{{SVG_NS}}}text")
        self.assertIsNotNone(text)
        tspans = list(text.findall(f"{{{SVG_NS}}}tspan"))
        self.assertEqual(len(tspans), 2, "ai-mark label should be exactly two lines")
        self.assertEqual((tspans[0].text or "").strip(), "AI")
        self.assertEqual((tspans[1].text or "").strip(), "generated")

    def test_ai_mark_two_lines_are_left_aligned_to_each_other(self):
        root = parse(bst.slot_template_svg(measurement(), slot="02", scene="02-kitchen.png"))
        tspans = by_id(root, "ai-mark").find(f"{{{SVG_NS}}}text").findall(f"{{{SVG_NS}}}tspan")
        self.assertAlmostEqual(float(tspans[0].get("x")), float(tspans[1].get("x")), places=2)
        # And the second line sits strictly below the first.
        self.assertGreater(float(tspans[1].get("y")), float(tspans[0].get("y")))

    def test_ai_mark_sits_below_the_sublines_ink_regardless_of_line_count(self):
        for lines in (1, 2, 3):
            with self.subTest(lines=lines):
                root = parse(bst.slot_template_svg(measurement(), slot="02",
                                                    scene="02-kitchen.png", subline_lines=lines))
                mark_rect = by_id(root, "ai-mark").find(f"{{{SVG_NS}}}rect")
                self.assertGreaterEqual(float(mark_rect.get("y")), self._subline_ink_bottom())

    def test_ai_mark_sits_in_the_bottom_right_corner(self):
        root = parse(bst.slot_template_svg(measurement(), slot="02", scene="02-kitchen.png"))
        mark_rect = by_id(root, "ai-mark").find(f"{{{SVG_NS}}}rect")
        width, height = 2064.0, 2752.0
        right_edge = float(mark_rect.get("x")) + float(mark_rect.get("width"))
        bottom_edge = float(mark_rect.get("y")) + float(mark_rect.get("height"))
        self.assertAlmostEqual(right_edge, width - bst.AI_MARK_RIGHT_INSET, places=2)
        self.assertAlmostEqual(bottom_edge, height - bst.AI_MARK_BOTTOM_INSET, places=2)
        # Tighter than the 140px side margin the headline/subline use, per brief.
        self.assertLess(bst.AI_MARK_RIGHT_INSET, bst.MARGIN_X)
        self.assertLess(bst.AI_MARK_BOTTOM_INSET, bst.MARGIN_X)
        # In the right half of the canvas, clearly not bottom-left any more.
        self.assertGreater(float(mark_rect.get("x")), width / 2)

    def test_ai_mark_pill_is_quieter_than_the_first_pass(self):
        root = parse(bst.slot_template_svg(measurement(), slot="02", scene="02-kitchen.png"))
        group = by_id(root, "ai-mark")
        mark_rect = group.find(f"{{{SVG_NS}}}rect")
        self.assertEqual(mark_rect.get("fill"), "#57606F")
        self.assertLess(float(mark_rect.get("fill-opacity")), 0.5)
        self.assertLess(float(mark_rect.get("rx")), 28.0)
        text = group.find(f"{{{SVG_NS}}}text")
        self.assertLess(float(text.get("font-size")), 36.0)
        self.assertLess(float(text.get("fill-opacity")), 0.85)


class TestHeadroomWarning(unittest.TestCase):
    """Zooming in buys screen share out of the text bands, so the squeeze has to be visible."""

    def test_ample_headroom_reports_no_squeeze(self):
        self.assertEqual(bst.band_warnings(measurement(), headroom_needed=400.0), [])

    def test_headroom_below_what_the_headline_needs_is_reported(self):
        m = measurement()
        m["canvas"]["crop"]["headroom_px"] = 220.0
        warnings = bst.band_warnings(m, headroom_needed=400.0)
        self.assertEqual(len(warnings), 1)
        self.assertIn("220", warnings[0])
        self.assertIn("400", warnings[0])


class TestStructuralContract(unittest.TestCase):

    def test_canvas_size_comes_from_the_measurement(self):
        root = parse(bst.slot_template_svg(measurement(), slot="02", scene="02-kitchen.png"))
        self.assertEqual(root.get("width"), "2064")
        self.assertEqual(root.get("height"), "2752")
        self.assertEqual(root.get("viewBox"), "0 0 2064 2752")

    def test_the_title_names_the_scene_it_was_measured_from(self):
        svg = bst.slot_template_svg(measurement(), slot="02", scene="02-kitchen.png")
        self.assertIn("02-kitchen.png", parse(svg).find(f"{{{SVG_NS}}}title").text)

    def test_neither_image_carries_an_href_so_the_renderer_fills_them(self):
        root = parse(bst.slot_template_svg(measurement(), slot="02", scene="02-kitchen.png"))
        for element_id in ("scene", "screenshot"):
            self.assertEqual(by_id(root, element_id).get("href"), "")

    def test_output_is_deterministic_for_the_same_measurement(self):
        a = bst.slot_template_svg(measurement(), slot="02", scene="02-kitchen.png")
        b = bst.slot_template_svg(measurement(), slot="02", scene="02-kitchen.png")
        self.assertEqual(a, b)

    def test_no_template_ever_ships_a_sentence_of_store_copy(self):
        # FR-9010-20: the words live in content.json. A template carrying real copy would
        # render fine and silently outrank the manifest for anyone reading the repo. Scoped to
        # headline/subline only — the ai-mark's tspans ("AI" / "generated") are a fixed static
        # disclosure label, not manifest-sourced copy, so they are exempt from this pattern.
        root = parse(bst.slot_template_svg(measurement(), slot="02", scene="02-kitchen.png"))
        for element_id in ("headline", "subline"):
            for tspan in by_id(root, element_id).findall(f"{{{SVG_NS}}}tspan"):
                self.assertRegex(tspan.text or "", r"(?i)^(headline|subline) line (one|two)$")

    def test_coordinates_are_written_at_two_decimals_not_full_float_noise(self):
        svg = bst.slot_template_svg(measurement(), slot="02", scene="02-kitchen.png")
        for value in re.findall(r'(?:x|y|width|height)="(-?\d+\.\d+)"', svg):
            self.assertLessEqual(len(value.split(".")[1]), 2, value)


if __name__ == "__main__":
    unittest.main()
