"""test_measure_scene_cutout.py — unit tests for measure-scene-cutout.py.

Written FIRST per this repo's TDD policy: at the point this file was created,
`.claude/scripts/measure-scene-cutout.py` did not exist, so every test below failed with an
import error. The implementation was then written until this file went green.

Scope: almost everything here is PURE. The tool's only external dependency is ImageMagick, and
it is confined to exactly one function (`read_alpha`) that turns a file on disk into an
`AlphaMap`. Every geometry, classification, crop-solving, warning and SVG test constructs its
`AlphaMap` in memory instead, so the whole analysis pipeline is exercised without a subprocess.
The handful of tests that *do* need a real file (the reference-fixture regression, the PNG
round trip and the CLI) are guarded by `@needs_magick` and skip cleanly on a machine without it.

Synthetic fixtures are generated programmatically (`quad_alpha`) — no binary fixture is ever
committed. `quad_alpha` renders a convex quad as an alpha ramp across the edge, so a `feather`
of 1.0 is ordinary 1-pixel anti-aliasing, 0 is a hard binary edge, and 6 is a badly feathered
hand-cut selection. Because the ramp is exactly linear in the signed distance to the edge, the
50%-alpha crossing lies exactly on the ideal edge line — which is what makes the sub-pixel
corner assertions below meaningful down to hundredths of a pixel.

Import mechanics: the module under test has a hyphenated filename, so it cannot be imported by
name. It is loaded once, by absolute path, via `importlib.util.spec_from_file_location`; the
real module guards all side effects behind `if __name__ == "__main__"`, so `exec_module` is
inert.

Run with:

    cd /Users/jan/dev/repos/Immich-Slideshow
    python3 -m unittest discover -s .claude/scripts/tests -v
"""

from __future__ import annotations

import contextlib
import io
import json
import math
import re
import shutil
import struct
import unittest
import zlib
from pathlib import Path

import importlib.util
import sys

TEST_FILE = Path(__file__).resolve()
ROOT = TEST_FILE.parents[3]
MODULE_PATH = TEST_FILE.parents[1] / "measure-scene-cutout.py"
SCRATCH = ROOT / "tmp" / "test-measure-scene-cutout"
REFERENCE_PNG = ROOT / "docs" / "design" / "appstore prerenders" / "ipad-mit-freischnitt.png"


def _load_module():
    spec = importlib.util.spec_from_file_location("measure_scene_cutout", MODULE_PATH)
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


msc = _load_module()

needs_magick = unittest.skipUnless(
    shutil.which("magick") or Path("/opt/homebrew/bin/magick").exists(),
    "ImageMagick not installed",
)
needs_reference = unittest.skipUnless(
    REFERENCE_PNG.exists(), f"reference fixture missing: {REFERENCE_PNG}",
)


# --------------------------------------------------------------------------------------
# Synthetic fixture generation (pure Python — nothing binary is committed)
# --------------------------------------------------------------------------------------

def _outward_edges(corners):
    """Unit outward normals for a convex polygon, orientation-agnostic."""
    n = len(corners)
    twice_area = sum(
        corners[i][0] * corners[(i + 1) % n][1] - corners[(i + 1) % n][0] * corners[i][1]
        for i in range(n)
    )
    sign = 1.0 if twice_area > 0 else -1.0
    edges = []
    for i in range(n):
        px, py = corners[i]
        qx, qy = corners[(i + 1) % n]
        dx, dy = qx - px, qy - py
        length = math.hypot(dx, dy)
        edges.append((sign * dy / length, -sign * dx / length, px, py))
    return edges


def quad_alpha(width, height, corners, feather=1.0, specks=()):
    """Render a convex quad as a transparent cut-out in an otherwise opaque alpha channel.

    `feather` is the full width (px) of the alpha ramp across the edge; 0 gives a hard binary
    edge. `specks` are (x0, y0, x1, y1) half-open boxes punched fully transparent, used to
    simulate the stray holes a hand-cut selection leaves behind.
    """
    edges = _outward_edges(corners)
    pad = max(feather, 1.0) + 1.0
    x_lo = min(c[0] for c in corners) - pad
    x_hi = max(c[0] for c in corners) + pad
    y_lo = min(c[1] for c in corners) - pad
    y_hi = max(c[1] for c in corners) + pad
    buf = bytearray(b"\xff" * (width * height))
    for y in range(height):
        if not (y_lo <= y <= y_hi):
            continue
        base = y * width
        for x in range(width):
            if not (x_lo <= x <= x_hi):
                continue
            d = max(nx * (x - px) + ny * (y - py) for nx, ny, px, py in edges)
            if feather <= 0:
                if d < 0:
                    buf[base + x] = 0
                continue
            t = 0.5 + d / feather
            if t <= 0.0:
                buf[base + x] = 0
            elif t < 1.0:
                buf[base + x] = int(round(255 * t))
    for (sx0, sy0, sx1, sy1) in specks:
        for y in range(sy0, sy1):
            for x in range(sx0, sx1):
                buf[y * width + x] = 0
    return msc.AlphaMap(bytes(buf), width, height)


def _png_chunk(tag, payload):
    return (
        struct.pack(">I", len(payload)) + tag + payload
        + struct.pack(">I", zlib.crc32(tag + payload) & 0xFFFFFFFF)
    )


def write_rgb_png(path, width, height):
    """An RGB PNG with no alpha channel at all — the `hund-mit-textflaeche.png` case."""
    raw = bytearray()
    for _ in range(height):
        raw.append(0)
        raw += bytes((90, 110, 130)) * width
    body = (
        b"\x89PNG\r\n\x1a\n"
        + _png_chunk(b"IHDR", struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0))
        + _png_chunk(b"IDAT", zlib.compress(bytes(raw), 6))
        + _png_chunk(b"IEND", b"")
    )
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(body)
    return path


def write_rgba_png(path, alpha_map):
    """Minimal 8-bit RGBA PNG writer, so the magick-backed tests need no committed binary."""
    w, h = alpha_map.width, alpha_map.height
    raw = bytearray()
    for y in range(h):
        raw.append(0)  # filter: none
        row = alpha_map.data[y * w:(y + 1) * w]
        for a in row:
            raw += bytes((0, 0, 0, a))
    body = (
        b"\x89PNG\r\n\x1a\n"
        + _png_chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 6, 0, 0, 0))
        + _png_chunk(b"IDAT", zlib.compress(bytes(raw), 6))
        + _png_chunk(b"IEND", b"")
    )
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(body)
    return path


# Shared synthetic geometries. Image 260x360 keeps generation fast while leaving every quad a
# comfortable margin from the border (a border-touching region is itself a warning condition).
AXIS_QUAD = [(40.0, 50.0), (210.0, 50.0), (210.0, 310.0), (40.0, 310.0)]
# Narrower, so it still cover-fits onto the much taller/narrower iPhone canvas (1320x2868),
# where AXIS_QUAD's 170 px width scales past 1320 and is legitimately rejected.
NARROW_QUAD = [(60.0, 50.0), (190.0, 50.0), (190.0, 310.0), (60.0, 310.0)]
PARALLELOGRAM_QUAD = [(40.0, 50.0), (210.0, 50.0), (230.0, 310.0), (60.0, 310.0)]
TRAPEZOID_QUAD = [(40.0, 60.0), (215.0, 80.0), (225.0, 300.0), (35.0, 320.0)]


def rotated_quad(degrees=12.0, cx=125.0, cy=180.0, half_w=85.0, half_h=130.0):
    r = math.radians(degrees)
    cos_r, sin_r = math.cos(r), math.sin(r)
    out = []
    for dx, dy in ((-half_w, -half_h), (half_w, -half_h), (half_w, half_h), (-half_w, half_h)):
        out.append((cx + dx * cos_r - dy * sin_r, cy + dx * sin_r + dy * cos_r))
    return out


ROTATED_QUAD = rotated_quad()

_CACHE = {}


def cached_alpha(key, *args, **kwargs):
    if key not in _CACHE:
        _CACHE[key] = quad_alpha(*args, **kwargs)
    return _CACHE[key]


def axis_map():
    return cached_alpha("axis", 260, 360, AXIS_QUAD)


def rotated_map():
    return cached_alpha("rot", 260, 360, ROTATED_QUAD)


def parallelogram_map():
    return cached_alpha("para", 260, 360, PARALLELOGRAM_QUAD)


def trapezoid_map():
    return cached_alpha("trap", 260, 360, TRAPEZOID_QUAD)


def narrow_map():
    return cached_alpha("narrow", 260, 360, NARROW_QUAD)


def corner_list(report_corners):
    return [tuple(report_corners[k]) for k in ("tl", "tr", "br", "bl")]


# --------------------------------------------------------------------------------------
# Alpha histogram and connected regions
# --------------------------------------------------------------------------------------

class AlphaAndRegionTests(unittest.TestCase):

    def test_histogram_partitions_every_pixel(self):
        am = axis_map()
        hist = msc.alpha_histogram(am)
        self.assertEqual(hist["total"], 260 * 360)
        self.assertEqual(hist["transparent"] + hist["partial"] + hist["opaque"], hist["total"])

    def test_histogram_masked_count_matches_threshold(self):
        am = quad_alpha(60, 60, [(10.0, 10.0), (40.0, 10.0), (40.0, 40.0), (10.0, 40.0)], feather=0)
        hist = msc.alpha_histogram(am)
        self.assertEqual(hist["masked"], sum(1 for v in am.data if v < msc.ALPHA_THRESHOLD))
        self.assertEqual(hist["partial"], 0)

    def test_single_region_found(self):
        regions = msc.find_regions(axis_map())
        self.assertEqual(len(regions), 1)

    def test_region_area_and_bbox(self):
        # A hard-edged 10..40 quad covers pixel centres 11..39: the centres at exactly 10 and 40
        # sit ON the edge, which is 50% coverage, which is not below the threshold.
        am = quad_alpha(60, 60, [(10.0, 10.0), (40.0, 10.0), (40.0, 40.0), (10.0, 40.0)], feather=0)
        region = msc.find_regions(am)[0]
        self.assertEqual(region.x_min, 11)
        self.assertEqual(region.y_min, 11)
        self.assertEqual(region.x_max, 39)
        self.assertEqual(region.y_max, 39)
        self.assertEqual(region.area, 29 * 29)

    def test_regions_sorted_largest_first_and_specks_separate(self):
        am = quad_alpha(260, 360, AXIS_QUAD, specks=((5, 5, 9, 9), (250, 350, 253, 353)))
        regions = msc.find_regions(am)
        self.assertEqual(len(regions), 3)
        self.assertGreater(regions[0].area, regions[1].area)
        self.assertGreaterEqual(regions[1].area, regions[2].area)

    def test_region_centroid(self):
        am = quad_alpha(60, 60, [(10.0, 10.0), (40.0, 10.0), (40.0, 40.0), (10.0, 40.0)], feather=0)
        region = msc.find_regions(am)[0]
        self.assertAlmostEqual(region.cx, 25.0, places=6)   # centre of pixel columns 11..39
        self.assertAlmostEqual(region.cy, 25.0, places=6)

    def test_diagonal_touch_is_one_region_eight_connected(self):
        data = bytearray(b"\xff" * 25)
        data[0 * 5 + 1] = 0
        data[1 * 5 + 2] = 0
        am = msc.AlphaMap(bytes(data), 5, 5)
        self.assertEqual(len(msc.find_regions(am)), 1)

    def test_fully_opaque_image_has_no_regions(self):
        am = msc.AlphaMap(b"\xff" * 100, 10, 10)
        self.assertEqual(msc.find_regions(am), [])


# --------------------------------------------------------------------------------------
# Geometry primitives
# --------------------------------------------------------------------------------------

class PrimitiveTests(unittest.TestCase):

    def test_convex_hull_drops_interior_points(self):
        pts = [(0.0, 0.0), (10.0, 0.0), (10.0, 10.0), (0.0, 10.0), (5.0, 5.0), (3.0, 7.0)]
        hull = msc.convex_hull(pts)
        self.assertEqual(len(hull), 4)
        self.assertEqual(set(hull), {(0.0, 0.0), (10.0, 0.0), (10.0, 10.0), (0.0, 10.0)})

    def test_convex_hull_drops_collinear_points(self):
        pts = [(0.0, 0.0), (5.0, 0.0), (10.0, 0.0), (10.0, 10.0), (0.0, 10.0)]
        self.assertEqual(len(msc.convex_hull(pts)), 4)

    def test_polygon_area_shoelace(self):
        self.assertAlmostEqual(msc.polygon_area(AXIS_QUAD), 170.0 * 260.0, places=6)

    def test_fit_line_recovers_a_known_line(self):
        # y = 0.25x + 3  ->  0.25x - y + 3 = 0, normalised
        pts = [(float(x), 0.25 * x + 3.0) for x in range(0, 100, 5)]
        line = msc.fit_line(pts)
        for p in pts:
            self.assertLess(msc.line_distance(line, p), 1e-9)

    def test_fit_line_handles_a_vertical_line(self):
        pts = [(7.0, float(y)) for y in range(0, 50, 3)]
        line = msc.fit_line(pts)
        self.assertLess(msc.line_distance(line, (7.0, 123.0)), 1e-9)
        self.assertAlmostEqual(msc.line_distance(line, (9.0, 5.0)), 2.0, places=9)

    def test_line_intersection(self):
        a = msc.fit_line([(0.0, 0.0), (10.0, 0.0)])
        b = msc.fit_line([(4.0, -5.0), (4.0, 5.0)])
        x, y = msc.line_intersection(a, b)
        self.assertAlmostEqual(x, 4.0, places=9)
        self.assertAlmostEqual(y, 0.0, places=9)

    def test_fit_circle_recovers_radius(self):
        pts = [(30.0 + 12.0 * math.cos(t / 24 * math.pi / 2), 40.0 + 12.0 * math.sin(t / 24 * math.pi / 2))
               for t in range(25)]
        cx, cy, r = msc.fit_circle(pts)
        self.assertAlmostEqual(cx, 30.0, places=6)
        self.assertAlmostEqual(cy, 40.0, places=6)
        self.assertAlmostEqual(r, 12.0, places=6)

    def test_order_corners_tl_tr_br_bl(self):
        scrambled = [AXIS_QUAD[2], AXIS_QUAD[0], AXIS_QUAD[3], AXIS_QUAD[1]]
        self.assertEqual(msc.order_corners(scrambled), AXIS_QUAD)

    def test_order_corners_on_a_rotated_quad_is_clockwise(self):
        ordered = msc.order_corners(list(reversed(ROTATED_QUAD)))
        self.assertEqual(ordered[0], min(ROTATED_QUAD, key=lambda p: p[0] + p[1]))
        self.assertGreater(msc.signed_area(ordered), 0.0)


# --------------------------------------------------------------------------------------
# Quad fitting — sub-pixel corner recovery
# --------------------------------------------------------------------------------------

class QuadFitTests(unittest.TestCase):

    def assert_corners_close(self, got, want, tol):
        for name, g, w in zip(("tl", "tr", "br", "bl"), got, want):
            self.assertLess(math.hypot(g[0] - w[0], g[1] - w[1]), tol,
                            f"{name}: got {g}, want {w}")

    def test_axis_aligned_corners_subpixel(self):
        report = msc.analyse_alpha(axis_map())
        self.assert_corners_close(corner_list(report["screen"]["corners_px"]), AXIS_QUAD, 0.1)

    def test_rotated_corners_subpixel(self):
        report = msc.analyse_alpha(rotated_map())
        self.assert_corners_close(corner_list(report["screen"]["corners_px"]), ROTATED_QUAD, 0.1)

    def test_trapezoid_corners_subpixel(self):
        report = msc.analyse_alpha(trapezoid_map())
        self.assert_corners_close(corner_list(report["screen"]["corners_px"]), TRAPEZOID_QUAD, 0.15)

    def test_hard_edge_corners_still_within_half_a_pixel(self):
        # With no anti-aliasing there is no sub-pixel information to recover: the best any
        # method can do is place the edge midway between the last opaque and first transparent
        # pixel centre, so half a pixel per axis is the floor, not a defect.
        am = quad_alpha(260, 360, AXIS_QUAD, feather=0)
        report = msc.analyse_alpha(am)
        for name, got, want in zip(("tl", "tr", "br", "bl"),
                                   corner_list(report["screen"]["corners_px"]), AXIS_QUAD):
            self.assertLessEqual(abs(got[0] - want[0]), 0.51, name)
            self.assertLessEqual(abs(got[1] - want[1]), 0.51, name)

    def test_normalised_corners_are_original_over_size(self):
        report = msc.analyse_alpha(axis_map())
        px = report["screen"]["corners_px"]["tl"]
        norm = report["screen"]["corners_normalised"]["tl"]
        self.assertAlmostEqual(norm[0], px[0] / 260.0, places=9)
        self.assertAlmostEqual(norm[1], px[1] / 360.0, places=9)

    def test_bbox_matches_corner_extents(self):
        report = msc.analyse_alpha(rotated_map())
        corners = corner_list(report["screen"]["corners_px"])
        bbox = report["screen"]["bbox_px"]
        self.assertAlmostEqual(bbox["x"], min(c[0] for c in corners), places=6)
        self.assertAlmostEqual(bbox["width"],
                               max(c[0] for c in corners) - min(c[0] for c in corners), places=6)

    def test_mask_over_quad_area_is_one(self):
        report = msc.analyse_alpha(trapezoid_map())
        self.assertAlmostEqual(report["screen"]["mask_over_quad"], 1.0, delta=0.005)

    def test_sharp_corners_report_zero_radius(self):
        report = msc.analyse_alpha(axis_map())
        self.assertAlmostEqual(report["screen"]["corner_radius_px"]["mean"], 0.0, delta=0.3)

    def test_rounded_corners_report_a_radius(self):
        am = octagon_alpha()
        report = msc.analyse_alpha(am)
        self.assertGreater(report["screen"]["corner_radius_px"]["mean"], 6.0)


def octagon_alpha():
    """A rounded-cornered rectangle: the same quad with each corner replaced by a 12 px arc."""
    r = 12.0
    corners = AXIS_QUAD
    pts = []
    n = len(corners)
    for i in range(n):
        prev, cur, nxt = corners[(i - 1) % n], corners[i], corners[(i + 1) % n]
        for other, sign in ((prev, 1), (nxt, 1)):
            dx, dy = other[0] - cur[0], other[1] - cur[1]
            length = math.hypot(dx, dy)
            pts.append((cur[0] + r * dx / length, cur[1] + r * dy / length))
        # midpoint of the arc, pulled toward the centre
        cx = sum(c[0] for c in corners) / n
        cy = sum(c[1] for c in corners) / n
        vx, vy = cx - cur[0], cy - cur[1]
        vlen = math.hypot(vx, vy)
        k = r * (1 - math.sqrt(0.5)) * math.sqrt(2)
        pts.append((cur[0] + k * vx / vlen, cur[1] + k * vy / vlen))
    ordered = sorted(pts, key=lambda p: math.atan2(p[1] - 180.0, p[0] - 125.0))
    return cached_alpha("oct", 260, 360, ordered)


# --------------------------------------------------------------------------------------
# Classification
# --------------------------------------------------------------------------------------

class ClassificationTests(unittest.TestCase):

    def shape(self, am):
        return msc.analyse_alpha(am)["classification"]["shape"]

    def test_axis_aligned_rectangle(self):
        self.assertEqual(self.shape(axis_map()), "axis-aligned-rectangle")

    def test_rotated_rectangle_is_not_a_trapezoid(self):
        shape = self.shape(rotated_map())
        self.assertEqual(shape, "rotated-rectangle")
        self.assertNotEqual(shape, "perspective-trapezoid")

    def test_parallelogram(self):
        self.assertEqual(self.shape(parallelogram_map()), "parallelogram")

    def test_perspective_trapezoid(self):
        self.assertEqual(self.shape(trapezoid_map()), "perspective-trapezoid")

    def test_classification_reports_all_three_tests(self):
        cls = msc.analyse_alpha(trapezoid_map())["classification"]
        self.assertEqual(set(cls["tests"]), {"opposite_sides", "interior_angles", "diagonal_bisection"})
        for name, result in cls["tests"].items():
            self.assertIn("passed", result, name)
            self.assertIn("measured", result, name)
            self.assertIn("tolerance", result, name)

    def test_classification_publishes_its_tolerances(self):
        cls = msc.analyse_alpha(axis_map())["classification"]
        self.assertEqual(cls["tolerances"]["square_angle_deg"], msc.SQUARE_ANGLE_TOL_DEG)
        self.assertEqual(cls["tolerances"]["opposite_side_ratio"], msc.OPPOSITE_SIDE_RATIO_TOL)
        self.assertEqual(cls["tolerances"]["diagonal_offset_fraction"], msc.DIAGONAL_OFFSET_TOL_FRAC)

    def test_trapezoid_fails_the_diagonal_test(self):
        cls = msc.analyse_alpha(trapezoid_map())["classification"]
        self.assertFalse(cls["tests"]["diagonal_bisection"]["passed"])

    def test_rotated_rectangle_passes_all_three_tests(self):
        cls = msc.analyse_alpha(rotated_map())["classification"]
        for name, result in cls["tests"].items():
            self.assertTrue(result["passed"], f"{name} should pass: {result}")

    def test_interior_angles_sum_to_360(self):
        angles = msc.analyse_alpha(trapezoid_map())["screen"]["interior_angles_deg"]
        self.assertAlmostEqual(sum(angles[k] for k in ("tl", "tr", "br", "bl")), 360.0, places=4)


# --------------------------------------------------------------------------------------
# Cover fit and crop-offset solving
# --------------------------------------------------------------------------------------

class CoverFitTests(unittest.TestCase):

    def test_scale_is_the_cover_max(self):
        fit = msc.solve_cover_fit(941, 1672, 2064, 2752, AXIS_QUAD)
        self.assertAlmostEqual(fit["scale"], max(2064 / 941, 2752 / 1672), places=9)

    def test_crop_is_pinned_to_the_max_headroom_end(self):
        corners = [(400.0, 700.0), (600.0, 700.0), (600.0, 1000.0), (400.0, 1000.0)]
        fit = msc.solve_cover_fit(941, 1672, 2064, 2752, corners)
        self.assertEqual(fit["policy"], "max-headroom")
        self.assertEqual(fit["y_end_of_range"], "low")
        self.assertAlmostEqual(fit["y"], fit["y_range"][0], places=9)
        self.assertTrue(fit["centered_feasible"])

    def test_reference_geometry_crop_range(self):
        # The reference geometry: a centred crop pushes BL 51 px off the bottom of the canvas.
        corners = [(129.50, 291.50), (795.52, 353.51), (833.48, 1449.50), (147.50, 1486.49)]
        fit = msc.solve_cover_fit(941, 1672, 2064, 2752, corners)
        lo, hi = fit["y_range"]
        self.assertAlmostEqual(lo, 508.5, delta=0.2)
        self.assertAlmostEqual(hi, 639.4, delta=0.2)
        self.assertAlmostEqual(fit["y"], lo, places=9)
        self.assertFalse(fit["centered_feasible"])
        self.assertGreater(fit["y"], fit["y_centered"])

    def test_headroom_is_maximised_over_the_feasible_range(self):
        corners = [(129.50, 291.50), (795.52, 353.51), (833.48, 1449.50), (147.50, 1486.49)]
        fit = msc.solve_cover_fit(941, 1672, 2064, 2752, corners)
        low_headroom, high_headroom = fit["headroom_range_px"]
        self.assertLess(low_headroom, high_headroom)
        self.assertAlmostEqual(fit["headroom_px"], high_headroom, places=9)
        self.assertAlmostEqual(fit["headroom_fraction"], fit["headroom_px"] / 2752, places=12)
        # the cost of maximum headroom: the screen is flush with the bottom of the canvas
        self.assertAlmostEqual(fit["footroom_px"], 0.0, places=6)

    def test_headroom_is_the_gap_above_the_topmost_corner(self):
        corners = [(129.50, 291.50), (795.52, 353.51), (833.48, 1449.50), (147.50, 1486.49)]
        fit = msc.solve_cover_fit(941, 1672, 2064, 2752, corners)
        self.assertAlmostEqual(fit["headroom_px"], min(c[1] for c in fit["corners"]), places=9)

    def test_headroom_is_computed_against_the_selected_canvas(self):
        report = msc.analyse_alpha(narrow_map(), device="iphone")
        crop = report["canvas"]["crop"]
        self.assertAlmostEqual(crop["headroom_fraction"], crop["headroom_px"] / 2868, places=12)
        self.assertAlmostEqual(
            crop["headroom_px"], min(c[1] for c in report["canvas"]["corners_px"].values()),
            places=9)

    def test_solved_crop_keeps_every_corner_on_canvas(self):
        corners = [(129.50, 291.50), (795.52, 353.51), (833.48, 1449.50), (147.50, 1486.49)]
        fit = msc.solve_cover_fit(941, 1672, 2064, 2752, corners)
        for x, y in fit["corners"]:
            self.assertGreaterEqual(x, -1e-9)
            self.assertGreaterEqual(y, -1e-9)
            self.assertLessEqual(x, 2064 + 1e-9)
            self.assertLessEqual(y, 2752 + 1e-9)

    def test_centred_crop_would_have_clipped_the_reference(self):
        corners = [(129.50, 291.50), (795.52, 353.51), (833.48, 1449.50), (147.50, 1486.49)]
        fit = msc.solve_cover_fit(941, 1672, 2064, 2752, corners)
        scale = fit["scale"]
        bl_centered = corners[3][1] * scale - fit["y_centered"]
        self.assertGreater(bl_centered, 2752)

    # ---------------------------------------------------------------------------------
    # Zoom: a scene generated LARGER than the canvas has room to crop in, not just fit.
    # ---------------------------------------------------------------------------------

    def test_zoom_one_is_the_plain_cover_fit(self):
        a = msc.solve_cover_fit(2400, 3424, 2064, 2752, AXIS_QUAD)
        b = msc.solve_cover_fit(2400, 3424, 2064, 2752, AXIS_QUAD, zoom=1.0)
        self.assertEqual(a, b)

    def test_zoom_above_one_scales_the_scene_up_beyond_the_cover_minimum(self):
        corners = [(476.6, 648.9), (1884.2, 648.3), (1908.8, 2550.1), (476.6, 2552.3)]
        cover = msc.solve_cover_fit(2400, 3424, 2064, 2752, corners)
        zoomed = msc.solve_cover_fit(2400, 3424, 2064, 2752, corners, zoom=1.1)
        self.assertAlmostEqual(zoomed["scale"], cover["scale"] * 1.1, places=9)
        self.assertGreater(zoomed["scaled_width"], cover["scaled_width"])

    def test_zoom_is_capped_so_the_scene_is_never_upscaled_past_its_own_pixels(self):
        # The whole point of generating at 2400x3424 is to spend real pixels on a closer
        # crop. Scaling past 1:1 would spend invented ones — the softness trap the scene
        # tooling exists to avoid — so the cap is a hard refusal, not a silent clamp.
        with self.assertRaises(msc.UnusableSceneError) as ctx:
            msc.solve_cover_fit(2400, 3424, 2064, 2752, AXIS_QUAD, zoom=1.5)
        self.assertIn("upscale", str(ctx.exception).lower())

    def test_max_zoom_reports_the_headroom_a_one_to_one_crop_would_give(self):
        # 2400 -> 2064 is a 0.86 cover scale, so 1/0.86 = 1.1628 is the most zoom this
        # scene has to give before a single pixel would have to be invented.
        self.assertAlmostEqual(
            msc.max_zoom_without_upscaling(2400, 3424, 2064, 2752), 2400 / 2064, places=9)

    def test_max_zoom_is_one_when_the_scene_only_just_covers(self):
        self.assertAlmostEqual(msc.max_zoom_without_upscaling(2064, 2752, 2064, 2752), 1.0,
                               places=9)

    def test_zoom_at_the_cap_uses_the_scene_pixel_for_pixel(self):
        corners = [(476.6, 648.9), (1884.2, 648.3), (1908.8, 2550.1), (476.6, 2552.3)]
        zoom = msc.max_zoom_without_upscaling(2400, 3424, 2064, 2752)
        fit = msc.solve_cover_fit(2400, 3424, 2064, 2752, corners, zoom=zoom)
        self.assertAlmostEqual(fit["scale"], 1.0, places=9)
        self.assertAlmostEqual(fit["scaled_width"], 2400.0, places=6)

    def test_zooming_in_makes_the_screen_a_bigger_share_of_the_canvas(self):
        corners = [(476.6, 648.9), (1884.2, 648.3), (1908.8, 2550.1), (476.6, 2552.3)]
        cover = msc.solve_cover_fit(2400, 3424, 2064, 2752, corners)
        zoomed = msc.solve_cover_fit(2400, 3424, 2064, 2752, corners,
                                     zoom=msc.max_zoom_without_upscaling(2400, 3424, 2064, 2752))
        def area(fit):
            xs = [c[0] for c in fit["corners"]]
            ys = [c[1] for c in fit["corners"]]
            return (max(xs) - min(xs)) * (max(ys) - min(ys))
        self.assertGreater(area(zoomed), area(cover) * 1.25)

    # ---------------------------------------------------------------------------------
    # Reserved footroom: the bottom band the subline lives in (the two-band treatment).
    # ---------------------------------------------------------------------------------

    def test_min_footroom_zero_is_the_historical_max_headroom_policy(self):
        corners = [(129.50, 291.50), (795.52, 353.51), (833.48, 1449.50), (147.50, 1486.49)]
        a = msc.solve_cover_fit(941, 1672, 2064, 2752, corners)
        b = msc.solve_cover_fit(941, 1672, 2064, 2752, corners, min_footroom_px=0.0)
        self.assertEqual(a, b)

    def test_min_footroom_pushes_the_screen_up_to_reserve_the_band(self):
        corners = [(476.6, 648.9), (1884.2, 648.3), (1908.8, 2550.1), (476.6, 2552.3)]
        fit = msc.solve_cover_fit(2400, 3424, 2064, 2752, corners, zoom=msc.max_zoom_without_upscaling(2400, 3424, 2064, 2752),
                                  min_footroom_px=400.0)
        self.assertAlmostEqual(fit["footroom_px"], 400.0, delta=0.5)
        self.assertEqual(fit["policy"], "reserved-footroom")

    def test_reserved_footroom_never_leaves_the_feasible_range(self):
        # Asking for more bottom band than the scene can give crops as far as it legally can
        # and says so, rather than sliding the screen off the top of the canvas.
        corners = [(476.6, 648.9), (1884.2, 648.3), (1908.8, 2550.1), (476.6, 2552.3)]
        fit = msc.solve_cover_fit(2400, 3424, 2064, 2752, corners, zoom=msc.max_zoom_without_upscaling(2400, 3424, 2064, 2752),
                                  min_footroom_px=2000.0)
        lo, hi = fit["y_range"]
        self.assertLessEqual(fit["y"], hi + 1e-9)
        self.assertGreaterEqual(fit["y"], lo - 1e-9)
        self.assertLess(fit["footroom_px"], 2000.0)
        self.assertTrue(fit["footroom_short_px"] > 0)

    def test_reserved_footroom_still_keeps_every_corner_on_canvas(self):
        corners = [(476.6, 648.9), (1884.2, 648.3), (1908.8, 2550.1), (476.6, 2552.3)]
        fit = msc.solve_cover_fit(2400, 3424, 2064, 2752, corners, zoom=msc.max_zoom_without_upscaling(2400, 3424, 2064, 2752),
                                  min_footroom_px=400.0)
        for x, y in fit["corners"]:
            self.assertGreaterEqual(y, -1e-9)
            self.assertLessEqual(y, 2752 + 1e-9)

    def test_quad_too_wide_for_canvas_raises(self):
        # A 400x200 source cover-fits to 5504x2752; a quad spanning 360 source px spans
        # 4954 canvas px, so no horizontal offset can keep it on a 2064-wide canvas.
        corners = [(20.0, 40.0), (380.0, 40.0), (380.0, 160.0), (20.0, 160.0)]
        with self.assertRaises(msc.UnusableSceneError) as ctx:
            msc.solve_cover_fit(400, 200, 2064, 2752, corners)
        message = str(ctx.exception)
        self.assertIn("2064", message)
        matched = re.search(r"misses by ([\d.]+) px", message)
        self.assertIsNotNone(matched, message)
        expected = (380.0 - 20.0) * max(2064 / 400, 2752 / 200) - 2064
        self.assertAlmostEqual(float(matched.group(1)), expected, delta=0.1)

    def test_iphone_canvas_dimensions(self):
        self.assertEqual(msc.DEVICE_CANVASES["iphone"], (1320, 2868))
        self.assertEqual(msc.DEVICE_CANVASES["ipad"], (2064, 2752))

    def test_device_selects_the_canvas(self):
        report = msc.analyse_alpha(narrow_map(), device="iphone")
        self.assertEqual(report["canvas"]["width"], 1320)
        self.assertEqual(report["canvas"]["height"], 2868)

    def test_a_quad_that_fits_ipad_can_still_be_too_wide_for_iphone(self):
        self.assertIsNotNone(msc.analyse_alpha(axis_map(), device="ipad")["canvas"])
        self.assertIsNone(msc.analyse_alpha(axis_map(), device="iphone")["canvas"])

    def test_unknown_device_is_an_invocation_error(self):
        with self.assertRaises(msc.InvocationError):
            msc.analyse_alpha(axis_map(), device="watch")

    def test_unusable_scene_is_reported_not_raised_by_analyse(self):
        corners = [(20.0, 40.0), (380.0, 40.0), (380.0, 160.0), (20.0, 160.0)]
        am = quad_alpha(400, 200, corners, feather=1.0)
        report = msc.analyse_alpha(am)
        self.assertIsNone(report["canvas"])
        self.assertIsNone(report["svg"])
        self.assertEqual(report["exit_code"], 2)
        self.assertIn("off-canvas", [e["code"] for e in report["errors"]])


# --------------------------------------------------------------------------------------
# SVG emission
# --------------------------------------------------------------------------------------

class SvgTests(unittest.TestCase):

    def report(self):
        return msc.analyse_alpha(trapezoid_map())

    def test_polygon_has_four_points_matching_canvas_corners(self):
        report = self.report()
        pairs = report["svg"]["clip_polygon_points"].split()
        self.assertEqual(len(pairs), 4)
        first = [float(v) for v in pairs[0].split(",")]
        self.assertAlmostEqual(first[0], report["canvas"]["corners_px"]["tl"][0], places=2)
        self.assertAlmostEqual(first[1], report["canvas"]["corners_px"]["tl"][1], places=2)

    def test_image_box_is_the_canvas_bbox(self):
        report = self.report()
        image = report["svg"]["image"]
        bbox = report["canvas"]["bbox_px"]
        for key in ("x", "y", "width", "height"):
            self.assertAlmostEqual(image[key], bbox[key], places=6)

    def test_rounded_path_shape(self):
        report = msc.analyse_alpha(octagon_alpha())
        path = report["svg"]["clip_path_rounded"]
        self.assertTrue(path.startswith("M "))
        self.assertTrue(path.rstrip().endswith("Z"))
        self.assertEqual(path.count(" A "), 4)

    def test_sharp_quad_rounded_path_has_no_arcs(self):
        report = msc.analyse_alpha(axis_map())
        self.assertEqual(report["svg"]["clip_path_rounded"].count(" A "), 0)

    def test_perspective_is_four_xy_pairs_in_corner_order(self):
        report = self.report()
        persp = report["svg"]["perspective"]
        self.assertEqual(len(persp), 4)
        for point in persp:
            self.assertEqual(len(point), 2)
        self.assertEqual(persp[0], list(report["canvas"]["corners_px"]["tl"]))

    def test_snippet_is_paste_ready(self):
        report = self.report()
        snippet = report["svg"]["snippet"]
        self.assertIn("<clipPath id=\"screen\">", snippet)
        self.assertIn("id=\"screenshot\"", snippet)
        self.assertIn(report["svg"]["clip_polygon_points"], snippet)


# --------------------------------------------------------------------------------------
# Quality warnings
# --------------------------------------------------------------------------------------

class WarningTests(unittest.TestCase):

    def codes(self, report):
        return [w["code"] for w in report["warnings"]]

    def test_clean_synthetic_has_no_warnings(self):
        report = msc.analyse_alpha(axis_map())
        self.assertEqual(report["warnings"], [])
        self.assertEqual(report["exit_code"], 0)

    def test_specks_are_detected_and_located(self):
        am = quad_alpha(260, 360, AXIS_QUAD, specks=((5, 5, 9, 9), (250, 350, 253, 353)))
        report = msc.analyse_alpha(am)
        self.assertIn("stray-specks", self.codes(report))
        specks = report["regions"]["specks"]
        self.assertEqual(len(specks), 2)
        self.assertEqual(specks[0]["area"], 16)
        self.assertEqual(specks[0]["bbox"], [5, 5, 8, 8])
        self.assertEqual(report["exit_code"], 1)

    def test_speck_warning_names_the_fix(self):
        am = quad_alpha(260, 360, AXIS_QUAD, specks=((5, 5, 9, 9),))
        warning = next(w for w in msc.analyse_alpha(am)["warnings"] if w["code"] == "stray-specks")
        self.assertTrue(warning["fix"])
        self.assertIn("1", warning["message"])

    def test_feathered_edge_detected(self):
        am = quad_alpha(260, 360, AXIS_QUAD, feather=7.0)
        report = msc.analyse_alpha(am)
        self.assertIn("feathered-edge", self.codes(report))
        self.assertEqual(report["screen"]["edge_softness"]["verdict"], "feathered")

    def test_hard_edge_not_reported_as_feathered(self):
        for feather in (0.0, 1.0):
            with self.subTest(feather=feather):
                am = quad_alpha(260, 360, AXIS_QUAD, feather=feather)
                report = msc.analyse_alpha(am)
                self.assertNotIn("feathered-edge", self.codes(report))
                self.assertEqual(report["screen"]["edge_softness"]["verdict"], "hard")

    def test_wobbly_edge_detected(self):
        am = wobbly_alpha()
        report = msc.analyse_alpha(am)
        self.assertIn("wobbly-edge", self.codes(report))

    def test_straight_edges_not_reported_as_wobbly(self):
        report = msc.analyse_alpha(rotated_map())
        self.assertNotIn("wobbly-edge", self.codes(report))

    def test_implausibly_small_region_warns(self):
        small = [(120.0, 170.0), (145.0, 170.0), (145.0, 200.0), (120.0, 200.0)]
        report = msc.analyse_alpha(quad_alpha(260, 360, small))
        self.assertIn("screen-too-small", self.codes(report))

    def test_implausibly_large_region_warns(self):
        big = [(2.0, 2.0), (257.0, 2.0), (257.0, 357.0), (2.0, 357.0)]
        report = msc.analyse_alpha(quad_alpha(260, 360, big))
        self.assertIn("screen-too-large", self.codes(report))

    def test_region_touching_the_border_warns(self):
        edge = [(-5.0, 60.0), (200.0, 60.0), (200.0, 300.0), (-5.0, 300.0)]
        report = msc.analyse_alpha(quad_alpha(260, 360, edge, feather=0))
        self.assertIn("region-touches-border", self.codes(report))

    def test_wildly_asymmetric_quad_warns(self):
        skewed = [(30.0, 40.0), (225.0, 130.0), (215.0, 320.0), (45.0, 200.0)]
        report = msc.analyse_alpha(quad_alpha(260, 360, skewed))
        self.assertIn("asymmetric-corners", self.codes(report))

    def test_every_warning_carries_code_message_and_fix(self):
        am = quad_alpha(260, 360, AXIS_QUAD, feather=7.0, specks=((5, 5, 9, 9),))
        report = msc.analyse_alpha(am)
        self.assertTrue(report["warnings"])
        for warning in report["warnings"]:
            self.assertTrue(warning["code"])
            self.assertTrue(warning["message"])
            self.assertTrue(warning["fix"])

    def test_no_transparent_pixels_is_an_error(self):
        report = msc.analyse_alpha(msc.AlphaMap(b"\xff" * (40 * 40), 40, 40))
        self.assertEqual(report["exit_code"], 2)
        self.assertIn("no-cutout", [e["code"] for e in report["errors"]])


def wobbly_alpha():
    """A hand-drawn-looking selection: the axis quad with a sinusoidal ripple on the left edge."""
    if "wobbly" in _CACHE:
        return _CACHE["wobbly"]
    width, height = 260, 360
    buf = bytearray(b"\xff" * (width * height))
    for y in range(50, 311):
        left = 40.0 + 2.5 * math.sin(y / 7.0)
        for x in range(width):
            if left <= x <= 210.0:
                buf[y * width + x] = 0
    _CACHE["wobbly"] = msc.AlphaMap(bytes(buf), width, height)
    return _CACHE["wobbly"]


# --------------------------------------------------------------------------------------
# JSON shape and CLI
# --------------------------------------------------------------------------------------

class JsonShapeTests(unittest.TestCase):

    def test_top_level_keys_are_stable(self):
        report = msc.analyse_alpha(trapezoid_map())
        self.assertEqual(list(report), [
            "tool", "version", "image", "alpha", "regions", "screen",
            "classification", "canvas", "svg", "notes", "warnings", "errors", "exit_code",
        ])

    def test_report_is_json_serialisable(self):
        report = msc.analyse_alpha(trapezoid_map())
        round_tripped = json.loads(json.dumps(report))
        self.assertEqual(round_tripped["classification"]["shape"], "perspective-trapezoid")

    def test_screen_section_keys(self):
        screen = msc.analyse_alpha(trapezoid_map())["screen"]
        for key in ("corners_px", "corners_normalised", "bbox_px", "mask_area_px",
                    "quad_area_px", "fill_ratio", "mask_over_quad", "corner_radius_px",
                    "interior_angles_deg", "side_lengths_px", "edges", "diagonals",
                    "edge_softness", "area_fraction_of_image"):
            self.assertIn(key, screen)

    def test_edges_carry_residuals(self):
        edges = msc.analyse_alpha(trapezoid_map())["screen"]["edges"]
        self.assertEqual([e["name"] for e in edges], ["top", "right", "bottom", "left"])
        for edge in edges:
            for key in ("angle_deg", "length_px", "residual_rms_px", "residual_max_px",
                        "sample_count"):
                self.assertIn(key, edge)

    def test_canvas_section_keys(self):
        canvas = msc.analyse_alpha(trapezoid_map())["canvas"]
        for key in ("device", "width", "height", "scale", "scaled_width", "scaled_height",
                    "crop", "corners_px", "bbox_px"):
            self.assertIn(key, canvas)


class CliTests(unittest.TestCase):

    @classmethod
    def setUpClass(cls):
        SCRATCH.mkdir(parents=True, exist_ok=True)
        cls.clean = write_rgba_png(SCRATCH / "clean.png", quad_alpha(260, 360, AXIS_QUAD))
        cls.dirty = write_rgba_png(
            SCRATCH / "dirty.png", quad_alpha(260, 360, AXIS_QUAD, specks=((5, 5, 9, 9),)))
        # A name with a space and a non-ASCII character, matching the real scene folder.
        cls.awkward = write_rgba_png(
            SCRATCH / "hund-mit-textfläche 2.png", quad_alpha(260, 360, AXIS_QUAD))
        cls.opaque = write_rgba_png(SCRATCH / "opaque.png", msc.AlphaMap(b"\xff" * (60 * 80), 60, 80))
        cls.no_alpha = write_rgb_png(SCRATCH / "no-alpha.png", 60, 80)

    @classmethod
    def tearDownClass(cls):
        shutil.rmtree(SCRATCH, ignore_errors=True)

    def run_main(self, argv):
        out, err = io.StringIO(), io.StringIO()
        with contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
            code = msc.main(argv)
        return code, out.getvalue(), err.getvalue()

    def test_missing_file_exits_two(self):
        code, _, err = self.run_main([str(SCRATCH / "nope.png")])
        self.assertEqual(code, 2)
        self.assertIn("error:", err)

    def test_unknown_device_exits_two(self):
        code, _, err = self.run_main([str(self.clean), "--device", "watch"])
        self.assertEqual(code, 2)

    @needs_magick
    def test_clean_image_exits_zero(self):
        code, out, _ = self.run_main([str(self.clean)])
        self.assertEqual(code, 0)
        self.assertIn("axis-aligned-rectangle", out)

    @needs_magick
    def test_warned_image_exits_one(self):
        code, out, _ = self.run_main([str(self.dirty)])
        self.assertEqual(code, 1)
        self.assertIn("stray-specks", out)

    @needs_magick
    def test_json_flag_emits_only_json(self):
        code, out, _ = self.run_main([str(self.clean), "--json"])
        self.assertEqual(code, 0)
        payload = json.loads(out)
        self.assertEqual(payload["tool"], "measure-scene-cutout")
        self.assertEqual(payload["image"]["width"], 260)

    @needs_magick
    def test_read_alpha_round_trips_the_written_png(self):
        am = msc.read_alpha(self.clean)
        self.assertEqual((am.width, am.height), (260, 360))
        self.assertEqual(len(am.data), 260 * 360)

    @needs_magick
    def test_text_report_names_the_crop_policy(self):
        _, out, _ = self.run_main([str(self.clean)])
        self.assertIn("crop", out.lower())
        self.assertIn("headroom", out.lower())
        self.assertIn("max-headroom", out)

    @needs_magick
    def test_filename_with_space_and_umlaut(self):
        code, out, _ = self.run_main([str(self.awkward)])
        self.assertEqual(code, 0)
        self.assertIn("hund-mit-textfläche 2.png", out)

    @needs_magick
    def test_fully_opaque_image_exits_two_with_a_clear_message(self):
        code, out, _ = self.run_main([str(self.opaque)])
        self.assertEqual(code, 2)
        self.assertIn("no-cutout", out)
        self.assertIn("no screen cut-out", out)

    @needs_magick
    def test_image_without_an_alpha_channel_exits_two(self):
        code, out, _ = self.run_main([str(self.no_alpha)])
        self.assertEqual(code, 2)
        self.assertIn("no-cutout", out)

    @needs_magick
    def test_json_still_emitted_for_an_unusable_image(self):
        code, out, _ = self.run_main([str(self.opaque), "--json"])
        self.assertEqual(code, 2)
        payload = json.loads(out)
        self.assertIsNone(payload["screen"])
        self.assertEqual(payload["errors"][0]["code"], "no-cutout")


# --------------------------------------------------------------------------------------
# Reference-fixture regression — the numbers CUTOUT.md measured by hand
# --------------------------------------------------------------------------------------

@needs_magick
@needs_reference
class ReferenceFixtureTests(unittest.TestCase):

    KNOWN_CORNERS = [(129.50, 291.50), (795.52, 353.51), (833.48, 1449.50), (147.50, 1486.49)]

    @classmethod
    def setUpClass(cls):
        cls.report = msc.analyse_file(REFERENCE_PNG)

    def test_image_size(self):
        self.assertEqual((self.report["image"]["width"], self.report["image"]["height"]),
                         (941, 1672))

    def test_alpha_histogram_matches_cutout_md(self):
        alpha = self.report["alpha"]
        self.assertEqual(alpha["transparent"], 772197)
        self.assertEqual(alpha["partial"], 3702)
        self.assertEqual(alpha["opaque"], 797453)

    def test_exactly_one_region_of_the_known_area(self):
        self.assertEqual(self.report["regions"]["count"], 1)
        self.assertEqual(self.report["regions"]["largest_area"], 774017)
        self.assertEqual(self.report["regions"]["specks"], [])

    def test_corners_match_cutout_md(self):
        got = corner_list(self.report["screen"]["corners_px"])
        for name, g, w in zip(("tl", "tr", "br", "bl"), got, self.KNOWN_CORNERS):
            self.assertLess(math.hypot(g[0] - w[0], g[1] - w[1]), 0.1,
                            f"{name}: got {g}, want {w}")

    def test_interior_angles_match_cutout_md(self):
        angles = self.report["screen"]["interior_angles_deg"]
        for key, want in (("tl", 83.82), ("tr", 97.30), ("br", 91.10), ("bl", 87.78)):
            self.assertAlmostEqual(angles[key], want, delta=0.05)

    def test_opposite_side_ratio_is_nine_percent(self):
        sides = self.report["screen"]["side_lengths_px"]
        self.assertAlmostEqual(sides["left"] / sides["right"], 1.090, delta=0.005)

    def test_diagonal_midpoints_are_fifty_px_apart(self):
        diag = self.report["screen"]["diagonals"]
        self.assertAlmostEqual(diag["offset_px"], 50.5, delta=0.2)

    def test_classified_as_perspective_trapezoid(self):
        self.assertEqual(self.report["classification"]["shape"], "perspective-trapezoid")

    def test_corners_are_sharp_not_rounded(self):
        """CUTOUT.md reports a 14.20 px corner radius. That number is an artefact and this test
        pins the correction.

        Its method was a Kasa circle fit over every boundary pixel within 25 px of each corner.
        A circle fitted to two straight perpendicular arms always returns a radius of roughly
        the window size whether or not a fillet exists — which is why its four "radii" (13.2,
        15.8, 14.2, 13.6) cluster around 0.6 x the 25 px window rather than around anything in
        the image. The raw alpha settles it: at the TL corner the transparent region runs into
        the corner with a single anti-aliased pixel on each edge and no arc at all, and there
        are boundary samples 0.51 px from the fitted corner, which a 14 px fillet would have
        pushed 7 px away. This tool checks whether the boundary actually departs from the two
        edge lines before it fits anything, so it reports the corners as sharp.
        """
        radii = self.report["screen"]["corner_radius_px"]
        for key in ("tl", "tr", "br", "bl"):
            self.assertEqual(radii[key], 0.0, key)
        self.assertEqual(radii["mean"], 0.0)

    def test_sharp_corners_make_the_rounded_path_a_plain_polygon(self):
        self.assertEqual(self.report["svg"]["clip_path_rounded"].count(" A "), 0)

    def test_fill_ratio_matches_cutout_md(self):
        self.assertAlmostEqual(self.report["screen"]["fill_ratio"], 0.9200, delta=0.001)

    def test_edges_are_straight(self):
        for edge in self.report["screen"]["edges"]:
            self.assertLess(edge["residual_max_px"], msc.EDGE_RESIDUAL_TOL_PX, edge["name"])

    def test_crop_range_matches_cutout_md(self):
        crop = self.report["canvas"]["crop"]
        self.assertAlmostEqual(crop["y_range"][0], 508.5, delta=0.2)
        self.assertAlmostEqual(crop["y_range"][1], 639.4, delta=0.2)
        self.assertAlmostEqual(crop["y_centered"], 457.69, delta=0.05)
        self.assertEqual(crop["policy"], "max-headroom")
        self.assertFalse(crop["centered_feasible"])
        self.assertAlmostEqual(crop["y"], crop["y_range"][0], places=9)

    def test_headroom_reported_for_the_reference(self):
        crop = self.report["canvas"]["crop"]
        self.assertAlmostEqual(crop["headroom_px"], 130.9, delta=0.5)
        self.assertAlmostEqual(crop["headroom_fraction"] * 100, 4.8, delta=0.1)
        self.assertAlmostEqual(crop["footroom_px"], 0.0, places=6)

    def test_notes_explain_the_headroom_trade_off(self):
        joined = " ".join(self.report["notes"])
        self.assertIn("headroom", joined)
        self.assertIn("centred cover crop", joined)

    def test_scale_matches_cutout_md(self):
        self.assertAlmostEqual(self.report["canvas"]["scale"], 2.193411, places=5)

    def test_solved_crop_keeps_the_quad_on_canvas(self):
        for x, y in self.report["svg"]["perspective"]:
            self.assertGreaterEqual(y, 0.0)
            self.assertLessEqual(y, 2752.0)
            self.assertGreaterEqual(x, 0.0)
            self.assertLessEqual(x, 2064.0)

    def test_reference_is_clean(self):
        self.assertEqual(self.report["warnings"], [])
        self.assertEqual(self.report["exit_code"], 0)


if __name__ == "__main__":
    unittest.main()
