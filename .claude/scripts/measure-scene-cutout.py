#!/usr/bin/env python3
"""measure-scene-cutout.py — measure a scene photo's transparent screen cut-out ("Freischnitt").

Every App Store scene image has the iPad's screen area cut out (alpha = 0) so a real UI capture
can show through. `render-store-screenshots.py` clips that capture with an SVG `<clipPath>` whose
polygon is the screen quad — and pre-warps the capture by a homography when the quad is a
perspective trapezoid rather than a rectangle. Somebody has to measure that quad. Doing it
ad-hoc per image does not scale past the first scene, and hand-cut alpha is messier than a
generated one, so this tool absorbs both jobs: it measures the cut-out and it *audits* it.

Point it at a cut-out PNG and it prints the corners in three coordinate spaces, the shape
classification, a paste-ready `<clipPath>` + `<image>` block in device-canvas pixels, and a list
of quality problems with what to do about each.

    measure-scene-cutout.py <image.png> [--device ipad|iphone] [--json]

The reference measurement this tool reproduces is `docs/design/appstore prerenders/CUTOUT.md`
(941x1672 scene, hand-measured with numpy/PIL). Its numbers are pinned as regression assertions
in `tests/test_measure_scene_cutout.py`.

Dependencies — a deliberate choice, not an accident:

  * Zero third-party Python. Same posture as `render-store-screenshots.py`: stdlib only, no pip,
    no venv, and the heavy lifting shelled out to a binary already required by this pipeline.
    numpy and PIL happen to be installed on this machine, but importing them would make them a
    hard requirement of the store pipeline for the first time, for work that is a few hundred
    lines of plain Python.
  * ImageMagick supplies the pixels, via `magick <in> -alpha extract -depth 8 gray:-`. It is
    confined to exactly ONE function (`read_alpha`); everything downstream operates on an
    `AlphaMap` of plain bytes, which is why the test suite can exercise the whole analysis
    without a subprocess. Verified against the reference: magick's alpha channel reproduces
    CUTOUT.md's histogram (772,197 / 3,702 / 797,453) exactly.
  * Decoding the PNG in pure Python was measured and rejected: 1,232 of the reference's 1,672
    scanlines use the Paeth filter, and un-filtering 6.3 MB byte-by-byte in CPython costs
    seconds where ImageMagick costs 120 ms — for a decoder that would also have to grow support
    for 16-bit, palette+tRNS and interlaced PNGs to be trustworthy against whatever Jan exports.

Two measurement choices worth knowing about, because they are why the numbers here are good:

  * Sub-pixel edge localisation. Edge samples are not pixel centres — for each scanline the
    50%-alpha crossing is interpolated between the last opaque and first transparent pixel. The
    anti-aliasing ring that makes a hand cut-out look soft is exactly the signal that locates its
    edge to a hundredth of a pixel. Using pixel centres instead biases every edge inward by ~0.5
    px (measured), which is the difference between agreeing with CUTOUT.md and missing it by a
    corner-radius' worth of slop over four corners.
  * The quad is fitted, not read off the hull. Boundary samples -> convex hull -> the four
    dominant hull chains -> a total-least-squares line per edge, iterated with the corner regions
    excluded -> corners are the intersections of adjacent lines. Rounded corners therefore do not
    drag the edges around, and the residual of each line fit becomes a free wobble detector.

Exit codes follow `render-store-screenshots.py`'s convention:
  0  clean — measured, no quality problems
  1  usable, but quality warnings were reported (specks, feathering, wobble, odd proportions)
  2  unusable, or bad invocation — no cut-out found, the quad is degenerate, no crop offset keeps
     it on canvas, the file is missing, or the device is unknown
  3  ImageMagick failed or could not be found
"""

from __future__ import annotations

import argparse
import json
import math
import re
import shutil
import subprocess
import sys
from pathlib import Path
from typing import NamedTuple

TOOL = "measure-scene-cutout"
REPORT_VERSION = 1

# App Store Connect canvases the renderer targets. Cover-fit is the only fit that can fill them
# from a scene photo of a different aspect, so it is the only one solved for here.
DEVICE_CANVASES = {"ipad": (2064, 2752), "iphone": (1320, 2868)}

# A pixel counts as "cut out" below this alpha. 128 is the midpoint, so the boundary it implies
# is the 50%-coverage contour — the same contour the sub-pixel interpolation below solves for.
ALPHA_THRESHOLD = 128
ALPHA_CROSSING = ALPHA_THRESHOLD - 0.5

# ---- Classification tolerances -------------------------------------------------------------
# All three of CUTOUT.md's independent tests are applied, and all three must agree before a quad
# is called a rectangle. They are stated here as named constants rather than buried at the
# comparison site, because the whole point of the classification is that a scene photographed at
# a tilt (a real keystone) must not be waved through as "close enough to a rectangle".
#
# The numbers are set from measurement, not taste. On the reference scene the three tests read
# 9.0% / 6.2 deg / 3.80%, and on a synthetic rotated rectangle rasterised at the same resolution
# they read <0.1% / <0.05 deg / <0.01%. Every tolerance below therefore sits ~20x above the
# rasterisation noise floor and ~10x below the weakest real signal, which is as wide a gap as the
# problem offers.
SQUARE_ANGLE_TOL_DEG = 1.5          # max |interior angle - 90| for "rectangle"
OPPOSITE_SIDE_RATIO_TOL = 0.02      # max |1 - len(a)/len(opposite a)| for "parallelogram"
DIAGONAL_OFFSET_TOL_FRAC = 0.005    # diagonal midpoint offset / mean diagonal length
AXIS_ALIGNED_TOL_DEG = 0.5          # max edge tilt for "axis-aligned" rather than "rotated"

# ---- Quality tolerances --------------------------------------------------------------------
EDGE_RESIDUAL_TOL_PX = 0.5          # line-fit residual above this = a wobbly hand-drawn edge
FEATHER_RATIO_TOL = 2.5             # partial-alpha pixels per perimeter px; ~1.0 is normal AA
MIN_SCREEN_AREA_FRAC = 0.03         # screen quad vs whole frame — below this, wrong region?
MAX_SCREEN_AREA_FRAC = 0.85         # above this, the "cut-out" is probably the whole photo
QUAD_FIT_AREA_TOL = 0.03            # |1 - mask area / quad area|; above this it is not a quad
CORNER_RADIUS_SPREAD_TOL = 0.5      # (max - min) / mean radius across the four corners
ANGLE_ASYMMETRY_TOL_DEG = 20.0      # a corner this far off square is a mis-cut, not perspective

# ---- Fitting parameters --------------------------------------------------------------------
HULL_REDUCTION_TARGET = 20          # cap on hull vertices before the O(n^4) seed search
FIT_TOLERANCE_SCHEDULE = (3.0, 2.0, 1.5, 1.0, 1.0, 1.0)   # px band per refinement pass
EDGE_MARGIN_FRACTION = 0.06         # of edge length, excluded at each end (skips corner arcs)
EDGE_MARGIN_MIN_PX = 3.0
RESIDUAL_WINDOW_PX = 6.0            # band used to *report* straightness (wider than the fit band)
CORNER_FIT_WINDOW_PX = 25.0         # CUTOUT.md's window, kept so radii stay comparable
SHARP_CORNER_TOL_PX = 1.0           # boundary hugging both edge lines this closely = sharp

CORNER_NAMES = ("tl", "tr", "br", "bl")
EDGE_NAMES = ("top", "right", "bottom", "left")

_MASK_TABLE = bytes(1 if v < ALPHA_THRESHOLD else 0 for v in range(256))


class InvocationError(Exception):
    """Bad CLI usage: unknown device, unreadable file (exit code 2)."""


class UnusableSceneError(RuntimeError):
    """The image cannot serve as a scene: no cut-out, degenerate quad, off-canvas (exit code 2)."""


class ExternalToolError(RuntimeError):
    """ImageMagick failed or was not found (exit code 3)."""


class AlphaMap(NamedTuple):
    """An 8-bit alpha channel: `data[y * width + x]`. The only thing the analysis ever sees."""
    data: bytes
    width: int
    height: int

    def at(self, x: int, y: int) -> int:
        return self.data[y * self.width + x]


class Region(NamedTuple):
    """One connected run of sub-threshold alpha. `rows` maps y -> [(x_start, x_end_exclusive)]."""
    area: int
    x_min: int
    y_min: int
    x_max: int
    y_max: int
    cx: float
    cy: float
    rows: dict


class Quad(NamedTuple):
    corners: list          # 4 (x, y), ordered TL, TR, BR, BL
    lines: list            # 4 (a, b, c) with a^2 + b^2 = 1; line[i] joins corner[i], corner[i+1]
    samples: list          # 4 lists of boundary points used to report each edge's residual


# --------------------------------------------------------------------------------------
# Pixels in. The ONLY place an external process is touched.
# --------------------------------------------------------------------------------------

def magick_binary() -> str:
    found = shutil.which("magick") or "/opt/homebrew/bin/magick"
    if not Path(found).exists():
        raise ExternalToolError(
            "ImageMagick not found — install it (`brew install imagemagick`) or put `magick` on PATH")
    return found


def read_alpha(path) -> AlphaMap:
    """Extract the 8-bit alpha channel of `path` as a flat byte buffer, via ImageMagick.

    The path is resolved to an absolute one before it is handed over. That is not tidiness: a
    relative name containing a colon reads to ImageMagick as a `format:file` specifier, and an
    absolute path can never be mistaken for one. Spaces and non-ASCII names (`hund-mit-
    textfläche.png`) are safe because the argument vector is passed straight to `execve` with no
    shell in between — there is nothing to quote. An image with no alpha channel at all is not
    an error here; magick reports it fully opaque, and the caller then finds no cut-out and says
    so in those words.
    """
    path = Path(path)
    if not path.is_file():
        raise InvocationError(f"cannot read image: {path}")
    path = path.resolve()
    magick = magick_binary()
    try:
        ident = subprocess.run([magick, "identify", "-format", "%w %h", f"{path}[0]"],
                               check=True, capture_output=True, text=True).stdout.split()
        raw = subprocess.run([magick, f"{path}[0]", "-alpha", "extract", "-depth", "8", "gray:-"],
                             check=True, capture_output=True).stdout
    except FileNotFoundError as exc:
        raise ExternalToolError(f"ImageMagick could not be run: {exc}") from exc
    except subprocess.CalledProcessError as exc:
        detail = (exc.stderr or b"").decode("utf-8", "replace").strip() if isinstance(
            exc.stderr, bytes) else str(exc.stderr or "").strip()
        raise ExternalToolError(f"ImageMagick failed reading {path}: {detail or exc}") from exc

    width, height = int(ident[0]), int(ident[1])
    if len(raw) != width * height:
        raise ExternalToolError(
            f"ImageMagick returned {len(raw)} alpha bytes for a {width}x{height} image "
            f"(expected {width * height}) — is {path} a multi-frame or high-bit-depth file?")
    return AlphaMap(raw, width, height)


# --------------------------------------------------------------------------------------
# Alpha histogram and connected regions
# --------------------------------------------------------------------------------------

def alpha_histogram(alpha_map: AlphaMap) -> dict:
    data = alpha_map.data
    total = len(data)
    transparent = data.count(0)
    opaque = data.count(255)
    masked = sum(data.count(v) for v in range(ALPHA_THRESHOLD))
    return {
        "threshold": ALPHA_THRESHOLD,
        "total": total,
        "transparent": transparent,
        "partial": total - transparent - opaque,
        "opaque": opaque,
        "masked": masked,
    }


def _row_runs(alpha_map: AlphaMap) -> list:
    """Per row, the [start, end) spans of sub-threshold alpha. Run-length is the whole trick that
    keeps connected components cheap in pure Python: ~1,200 runs stand in for 774,017 pixels."""
    width = alpha_map.width
    data = alpha_map.data
    rows = []
    for y in range(alpha_map.height):
        line = data[y * width:(y + 1) * width].translate(_MASK_TABLE)
        rows.append([(m.start(), m.end()) for m in re.finditer(b"\x01+", line)]
                    if b"\x01" in line else [])
    return rows


def find_regions(alpha_map: AlphaMap) -> list:
    """8-connected components of `alpha < ALPHA_THRESHOLD`, largest first."""
    rows = _row_runs(alpha_map)
    parent: dict = {}

    def find(key):
        while parent[key] != key:
            parent[key] = parent[parent[key]]
            key = parent[key]
        return key

    def union(a, b):
        ra, rb = find(a), find(b)
        if ra != rb:
            parent[ra] = rb

    previous: list = []
    for y, runs in enumerate(rows):
        current = []
        for start, end in runs:
            key = (y, start, end)
            parent[key] = key
            current.append((start, end, key))
            for p_start, p_end, p_key in previous:
                if p_start <= end and start <= p_end:   # touching or diagonal => 8-connected
                    union(key, p_key)
        previous = current

    grouped: dict = {}
    for y, runs in enumerate(rows):
        for start, end in runs:
            grouped.setdefault(find((y, start, end)), []).append((y, start, end))

    regions = []
    for members in grouped.values():
        area = sum(end - start for _, start, end in members)
        sum_x = sum((start + end - 1) * (end - start) / 2.0 for _, start, end in members)
        sum_y = sum(y * (end - start) for y, start, end in members)
        by_row: dict = {}
        for y, start, end in members:
            by_row.setdefault(y, []).append((start, end))
        for spans in by_row.values():
            spans.sort()
        regions.append(Region(
            area=area,
            x_min=min(start for _, start, _ in members),
            y_min=min(y for y, _, _ in members),
            x_max=max(end for _, _, end in members) - 1,
            y_max=max(y for y, _, _ in members),
            cx=sum_x / area,
            cy=sum_y / area,
            rows=by_row,
        ))
    regions.sort(key=lambda r: (-r.area, r.y_min, r.x_min))
    return regions


def boundary_points(alpha_map: AlphaMap, region: Region) -> list:
    """Sub-pixel samples of the region's outline.

    One sample per scanline on the left and right, one per column on the top and bottom, each
    placed where alpha crosses `ALPHA_CROSSING` by linear interpolation between the last opaque
    pixel and the first transparent one. That is the 50%-coverage contour, which is where the
    edge actually is; taking the transparent pixel's centre instead would bias every edge inward
    by up to half a pixel.
    """
    width, height = alpha_map.width, alpha_map.height
    at = alpha_map.at
    points = set()

    def crossing(a_value: float, b_value: float, a_pos: float, b_pos: float) -> float:
        if a_value == b_value:
            return (a_pos + b_pos) / 2.0
        return a_pos + (a_value - ALPHA_CROSSING) / (a_value - b_value) * (b_pos - a_pos)

    ys = sorted(region.rows)
    for y in ys:
        spans = region.rows[y]
        left = spans[0][0]
        right = spans[-1][1] - 1
        points.add((crossing(at(left - 1, y), at(left, y), left - 1.0, float(left))
                    if left > 0 else float(left), float(y)))
        points.add((crossing(at(right + 1, y), at(right, y), right + 1.0, float(right))
                    if right < width - 1 else float(right), float(y)))

    for downward in (True, False):
        pending = bytearray(b"\x01" * width)
        for y in (ys if downward else reversed(ys)):
            for start, end in region.rows[y]:
                segment = pending[start:end]
                if b"\x01" not in segment:
                    continue
                for offset, flag in enumerate(segment):
                    if not flag:
                        continue
                    x = start + offset
                    pending[x] = 0
                    if downward:
                        pos = (crossing(at(x, y - 1), at(x, y), y - 1.0, float(y))
                               if y > 0 else float(y))
                    else:
                        pos = (crossing(at(x, y + 1), at(x, y), y + 1.0, float(y))
                               if y < height - 1 else float(y))
                    points.add((float(x), pos))
    return sorted(points)


# --------------------------------------------------------------------------------------
# Geometry primitives
# --------------------------------------------------------------------------------------

def _cross(o, a, b) -> float:
    return (a[0] - o[0]) * (b[1] - o[1]) - (a[1] - o[1]) * (b[0] - o[0])


def convex_hull(points) -> list:
    """Andrew's monotone chain. Collinear points are dropped, so a straight edge is one segment."""
    ordered = sorted(set(points))
    if len(ordered) < 3:
        return ordered
    lower = []
    for p in ordered:
        while len(lower) >= 2 and _cross(lower[-2], lower[-1], p) <= 0:
            lower.pop()
        lower.append(p)
    upper = []
    for p in reversed(ordered):
        while len(upper) >= 2 and _cross(upper[-2], upper[-1], p) <= 0:
            upper.pop()
        upper.append(p)
    return lower[:-1] + upper[:-1]


def signed_area(polygon) -> float:
    n = len(polygon)
    return sum(polygon[i][0] * polygon[(i + 1) % n][1] - polygon[(i + 1) % n][0] * polygon[i][1]
               for i in range(n)) / 2.0


def polygon_area(polygon) -> float:
    return abs(signed_area(polygon))


def fit_line(points):
    """Total-least-squares line as (a, b, c) with a^2 + b^2 = 1 and a*x + b*y + c = 0.

    Orthogonal (not vertical-offset) regression, so a near-vertical edge is fitted as accurately
    as a near-horizontal one — which matters because two of the four edges always are.
    """
    n = len(points)
    mean_x = sum(p[0] for p in points) / n
    mean_y = sum(p[1] for p in points) / n
    sxx = sum((p[0] - mean_x) ** 2 for p in points)
    syy = sum((p[1] - mean_y) ** 2 for p in points)
    sxy = sum((p[0] - mean_x) * (p[1] - mean_y) for p in points)
    theta = 0.5 * math.atan2(2.0 * sxy, sxx - syy)   # direction of maximum variance
    dx, dy = math.cos(theta), math.sin(theta)
    a, b = -dy, dx
    return (a, b, -(a * mean_x + b * mean_y))


def line_distance(line, point) -> float:
    return abs(line[0] * point[0] + line[1] * point[1] + line[2])


def line_intersection(line_a, line_b):
    a1, b1, c1 = line_a
    a2, b2, c2 = line_b
    det = a1 * b2 - a2 * b1
    if abs(det) < 1e-12:
        raise UnusableSceneError("two edges of the cut-out are parallel — this is not a quadrilateral")
    return ((b1 * c2 - b2 * c1) / det, (a2 * c1 - a1 * c2) / det)


def fit_circle(points):
    """Kasa algebraic circle fit. Returns (cx, cy, r), or None if the system is degenerate."""
    n = len(points)
    sx = sum(p[0] for p in points)
    sy = sum(p[1] for p in points)
    sxx = sum(p[0] * p[0] for p in points)
    syy = sum(p[1] * p[1] for p in points)
    sxy = sum(p[0] * p[1] for p in points)
    sz = sum(p[0] ** 2 + p[1] ** 2 for p in points)
    sxz = sum(p[0] * (p[0] ** 2 + p[1] ** 2) for p in points)
    syz = sum(p[1] * (p[0] ** 2 + p[1] ** 2) for p in points)
    matrix = [[2 * sxx, 2 * sxy, sx, sxz],
              [2 * sxy, 2 * syy, sy, syz],
              [2 * sx, 2 * sy, n, sz]]
    for col in range(3):
        pivot = max(range(col, 3), key=lambda r: abs(matrix[r][col]))
        if abs(matrix[pivot][col]) < 1e-12:
            return None
        matrix[col], matrix[pivot] = matrix[pivot], matrix[col]
        for row in range(3):
            if row == col:
                continue
            factor = matrix[row][col] / matrix[col][col]
            for k in range(col, 4):
                matrix[row][k] -= factor * matrix[col][k]
    cx = matrix[0][3] / matrix[0][0]
    cy = matrix[1][3] / matrix[1][1]
    c = matrix[2][3] / matrix[2][2]
    radius_sq = c + cx * cx + cy * cy
    return (cx, cy, math.sqrt(radius_sq)) if radius_sq > 0 else None


def order_corners(corners) -> list:
    """Return the four corners as TL, TR, BR, BL (clockwise on screen, y pointing down)."""
    cx = sum(c[0] for c in corners) / 4.0
    cy = sum(c[1] for c in corners) / 4.0
    ordered = sorted(corners, key=lambda p: math.atan2(p[1] - cy, p[0] - cx))
    start = min(range(4), key=lambda i: ordered[i][0] + ordered[i][1])
    return ordered[start:] + ordered[:start]


def reduce_hull(hull, target=HULL_REDUCTION_TARGET) -> list:
    """Indices of a `target`-vertex subset of `hull`, dropping the least significant vertices.

    Repeatedly removes whichever vertex sits closest to the chord between its neighbours, i.e.
    contributes least to the outline. It exists purely to bound the seed search below: a clean
    cut-out gives a 24-vertex hull, but a wobbly hand-drawn one can give hundreds, and an O(n^4)
    search over hundreds does not terminate in useful time.
    """
    indices = list(range(len(hull)))
    while len(indices) > target:
        worst = None
        for position in range(len(indices)):
            prev = hull[indices[position - 1]]
            here = hull[indices[position]]
            nxt = hull[indices[(position + 1) % len(indices)]]
            base = math.hypot(nxt[0] - prev[0], nxt[1] - prev[1])
            error = abs(_cross(prev, nxt, here)) / base if base > 1e-12 else 0.0
            if worst is None or error < worst[0]:
                worst = (error, position)
        indices.pop(worst[1])
    return indices


def _seed_corner_indices(hull) -> tuple:
    """The four hull vertices spanning the largest quadrilateral — the corner seeds."""
    candidates = reduce_hull(hull)
    if len(candidates) < 4:
        raise UnusableSceneError(
            f"the cut-out's outline has only {len(candidates)} distinct corners — not a quadrilateral")
    best = None
    n = len(candidates)
    for i in range(n):
        for j in range(i + 1, n):
            for k in range(j + 1, n):
                for m in range(k + 1, n):
                    quad = [hull[candidates[t]] for t in (i, j, k, m)]
                    area = polygon_area(quad)
                    if best is None or area > best[0]:
                        best = (area, (candidates[i], candidates[j], candidates[k], candidates[m]))
    return best[1]


def _edge_span(corner_a, corner_b):
    dx, dy = corner_b[0] - corner_a[0], corner_b[1] - corner_a[1]
    length = math.hypot(dx, dy)
    if length < 1e-9:
        raise UnusableSceneError("the fitted quadrilateral is degenerate — two corners coincide")
    return length, dx / length, dy / length


def _edge_margin(length: float) -> float:
    return max(EDGE_MARGIN_MIN_PX, min(EDGE_MARGIN_FRACTION * length, 0.25 * length))


def _select_edge_points(points, line, corner_a, corner_b, band):
    length, ux, uy = _edge_span(corner_a, corner_b)
    margin = _edge_margin(length)
    selected = []
    for p in points:
        if line_distance(line, p) > band:
            continue
        t = (p[0] - corner_a[0]) * ux + (p[1] - corner_a[1]) * uy
        if margin <= t <= length - margin:
            selected.append(p)
    return selected


def fit_quad(points) -> Quad:
    """Fit a quadrilateral to sub-pixel boundary samples: hull -> seeds -> refined edge lines."""
    hull = convex_hull(points)
    if len(hull) < 4:
        raise UnusableSceneError("the cut-out's outline is not a closed quadrilateral")
    seeds = order_corners([hull[i] for i in _seed_corner_indices(hull)])
    corners = seeds
    lines = [fit_line([corners[i], corners[(i + 1) % 4]]) for i in range(4)]

    for band in FIT_TOLERANCE_SCHEDULE:
        refitted = []
        for i in range(4):
            chosen = _select_edge_points(points, lines[i], corners[i], corners[(i + 1) % 4], band)
            refitted.append(fit_line(chosen) if len(chosen) >= 2 else lines[i])
        lines = refitted
        # corner i is where the edge arriving at it meets the edge leaving it
        corners = [line_intersection(lines[(i - 1) % 4], lines[i]) for i in range(4)]

    # Straightness is reported over a wider band than the fit used, and by nearest-line
    # assignment, so a wobbly edge is measured by how far it actually strays rather than by how
    # much of it happened to fall inside the final fitting band.
    samples = []
    for i in range(4):
        length, ux, uy = _edge_span(corners[i], corners[(i + 1) % 4])
        margin = _edge_margin(length)
        chosen = []
        for p in points:
            d = line_distance(lines[i], p)
            if d > RESIDUAL_WINDOW_PX or any(line_distance(lines[j], p) < d for j in range(4) if j != i):
                continue
            t = (p[0] - corners[i][0]) * ux + (p[1] - corners[i][1]) * uy
            if margin <= t <= length - margin:
                chosen.append(p)
        samples.append(chosen)
    return Quad(corners=corners, lines=lines, samples=samples)


def corner_radii(quad: Quad, points) -> list:
    """Per-corner rounding radius in original pixels; 0.0 for a sharp corner."""
    corners, lines = quad.corners, quad.lines
    edge_lengths = [_edge_span(corners[i], corners[(i + 1) % 4])[0] for i in range(4)]
    window = min(CORNER_FIT_WINDOW_PX, 0.2 * min(edge_lengths))
    radii = []
    for i in range(4):
        corner = corners[i]
        incoming, outgoing = lines[(i - 1) % 4], lines[i]
        nearby = [p for p in points if math.hypot(p[0] - corner[0], p[1] - corner[1]) <= window]
        if len(nearby) < 5:
            radii.append(0.0)
            continue
        departure = max(min(line_distance(incoming, p), line_distance(outgoing, p)) for p in nearby)
        if departure < SHARP_CORNER_TOL_PX:
            radii.append(0.0)
            continue
        fit = fit_circle(nearby)
        limit = 0.5 * min(edge_lengths)
        radii.append(fit[2] if fit and 0.0 < fit[2] < limit else 0.0)
    return radii


# --------------------------------------------------------------------------------------
# Classification — CUTOUT.md's three independent tests, all of which must agree
# --------------------------------------------------------------------------------------

def interior_angles(corners) -> list:
    angles = []
    for i in range(4):
        a, b, c = corners[(i - 1) % 4], corners[i], corners[(i + 1) % 4]
        v1 = (a[0] - b[0], a[1] - b[1])
        v2 = (c[0] - b[0], c[1] - b[1])
        cosine = ((v1[0] * v2[0] + v1[1] * v2[1])
                  / (math.hypot(*v1) * math.hypot(*v2)))
        angles.append(math.degrees(math.acos(max(-1.0, min(1.0, cosine)))))
    return angles


def side_lengths(corners) -> list:
    return [math.hypot(corners[(i + 1) % 4][0] - corners[i][0],
                       corners[(i + 1) % 4][1] - corners[i][1]) for i in range(4)]


def diagonal_report(corners) -> dict:
    mid_a = ((corners[0][0] + corners[2][0]) / 2.0, (corners[0][1] + corners[2][1]) / 2.0)
    mid_b = ((corners[1][0] + corners[3][0]) / 2.0, (corners[1][1] + corners[3][1]) / 2.0)
    len_a = math.hypot(corners[2][0] - corners[0][0], corners[2][1] - corners[0][1])
    len_b = math.hypot(corners[3][0] - corners[1][0], corners[3][1] - corners[1][1])
    offset = math.hypot(mid_a[0] - mid_b[0], mid_a[1] - mid_b[1])
    return {
        "midpoint_tl_br": list(mid_a),
        "midpoint_tr_bl": list(mid_b),
        "length_tl_br": len_a,
        "length_tr_bl": len_b,
        "offset_px": offset,
        "offset_fraction": offset / ((len_a + len_b) / 2.0),
    }


def classify_quad(corners) -> dict:
    """Axis-aligned rectangle / rotated rectangle / parallelogram / perspective trapezoid."""
    angles = interior_angles(corners)
    sides = side_lengths(corners)
    diagonals = diagonal_report(corners)

    side_error = max(abs(1.0 - sides[0] / sides[2]), abs(1.0 - sides[1] / sides[3]))
    angle_error = max(abs(angle - 90.0) for angle in angles)
    diagonal_error = diagonals["offset_fraction"]

    tests = {
        "opposite_sides": {
            "measured": side_error, "tolerance": OPPOSITE_SIDE_RATIO_TOL,
            "passed": side_error <= OPPOSITE_SIDE_RATIO_TOL,
            "description": "opposite side lengths equal (fails => perspective)",
        },
        "interior_angles": {
            "measured": angle_error, "tolerance": SQUARE_ANGLE_TOL_DEG,
            "passed": angle_error <= SQUARE_ANGLE_TOL_DEG,
            "description": "all interior angles 90 deg (fails => not a rectangle)",
        },
        "diagonal_bisection": {
            "measured": diagonal_error, "tolerance": DIAGONAL_OFFSET_TOL_FRAC,
            "passed": diagonal_error <= DIAGONAL_OFFSET_TOL_FRAC,
            "description": "diagonals bisect each other (fails => not a parallelogram)",
        },
    }

    if not (tests["opposite_sides"]["passed"] and tests["diagonal_bisection"]["passed"]):
        shape = "perspective-trapezoid"
    elif not tests["interior_angles"]["passed"]:
        shape = "parallelogram"
    else:
        tilt = max(min(abs(edge_angle(corners, i)) % 90.0,
                       90.0 - abs(edge_angle(corners, i)) % 90.0) for i in range(4))
        shape = "axis-aligned-rectangle" if tilt <= AXIS_ALIGNED_TOL_DEG else "rotated-rectangle"

    return {
        "shape": shape,
        "tests": tests,
        "tolerances": {
            "square_angle_deg": SQUARE_ANGLE_TOL_DEG,
            "opposite_side_ratio": OPPOSITE_SIDE_RATIO_TOL,
            "diagonal_offset_fraction": DIAGONAL_OFFSET_TOL_FRAC,
            "axis_aligned_deg": AXIS_ALIGNED_TOL_DEG,
        },
    }


def edge_angle(corners, i) -> float:
    """Signed tilt of edge i in degrees, measured from the +x axis."""
    a, b = corners[i], corners[(i + 1) % 4]
    return math.degrees(math.atan2(b[1] - a[1], b[0] - a[0]))


# --------------------------------------------------------------------------------------
# Cover fit — and solving the crop offset instead of merely reporting it
# --------------------------------------------------------------------------------------

def solve_cover_fit(image_w, image_h, canvas_w, canvas_h, corners) -> dict:
    """Scale the scene to cover the canvas, then choose a crop offset that keeps the quad on it.

    A centred cover crop is what everyone reaches for and it is wrong here often enough to
    matter: on the reference scene the screen sits low in the frame, so a symmetric top/bottom
    crop eats 51 px off the bottom of the screen before it touches the background at the top.
    The offset range that keeps all four corners on canvas is computed exactly, and the choice
    inside it is not a shrug:

      * Vertically the crop is pinned to the LOW end of the range. These scenes are deliberately
        extended upward to make room for the headline, and a cover fit onto a store canvas is
        exactly what throws that extra height away. Cropping as little as possible off the top
        leaves the screen sitting as low on the canvas as it can, which is the most headroom the
        headline can get. The cost is stated rather than hidden: at that end the bottom of the
        screen is flush with the canvas edge (`footroom_px` ~ 0), and `headroom_range_px` shows
        the whole trade-off — crop more from the top and the screen rises, headroom shrinks.
      * Horizontally there is no headline to protect, so the crop stays centred, clamped into
        the feasible range only if centring would push the screen off the side.

    When the range is empty the scene cannot be cover-fitted at this aspect at all, and the
    error says by how many pixels it misses rather than fudging a value.
    """
    scale = max(canvas_w / image_w, canvas_h / image_h)
    scaled_w, scaled_h = image_w * scale, image_h * scale
    overflow_x = max(0.0, scaled_w - canvas_w)
    overflow_y = max(0.0, scaled_h - canvas_h)

    def feasible(values, canvas_extent, overflow, axis):
        lo = max(0.0, max(values) - canvas_extent)
        hi = min(overflow, min(values))
        if lo > hi + 1e-9:
            span = max(values) - min(values)
            shortfall = span - canvas_extent
            raise UnusableSceneError(
                f"no {axis} crop offset keeps the screen on canvas: after the cover fit the "
                f"cut-out spans {span:.1f} px but the canvas is only {canvas_extent} px "
                f"{'wide' if axis == 'x' else 'tall'} — it misses by {shortfall:.1f} px. This "
                f"scene cannot be used at {canvas_w}x{canvas_h}; re-shoot or re-crop the photo "
                f"so the screen takes up less of the frame")
        return lo, hi

    xs = [c[0] * scale for c in corners]
    ys = [c[1] * scale for c in corners]
    lo_x, hi_x = feasible(xs, canvas_w, overflow_x, "x")
    lo_y, hi_y = feasible(ys, canvas_h, overflow_y, "y")
    centered_x, centered_y = overflow_x / 2.0, overflow_y / 2.0

    crop_x = min(max(centered_x, lo_x), hi_x)
    crop_y = lo_y                                  # low end of the range == maximum headroom

    headroom = min(ys) - crop_y
    footroom = canvas_h - (max(ys) - crop_y)
    centered_feasible = (lo_x - 1e-9 <= centered_x <= hi_x + 1e-9
                         and lo_y - 1e-9 <= centered_y <= hi_y + 1e-9)

    return {
        "scale": scale,
        "scaled_width": scaled_w,
        "scaled_height": scaled_h,
        "x": crop_x,
        "y": crop_y,
        "x_centered": centered_x,
        "y_centered": centered_y,
        "x_range": [lo_x, hi_x],
        "y_range": [lo_y, hi_y],
        "policy": "max-headroom",
        "y_end_of_range": "low",
        "policy_reason": (
            "vertical crop pinned to the low end of the feasible range: the smallest crop off "
            "the top leaves the screen as low on the canvas as it can go, which is the most "
            "headroom the headline can have without the bottom of the screen leaving the canvas"),
        "centered_feasible": centered_feasible,
        "headroom_px": headroom,
        "headroom_fraction": headroom / canvas_h,
        "footroom_px": footroom,
        # Headroom at each end of the feasible range, so the trade-off is legible: crop more
        # from the top (hi) and the screen rises until it touches the canvas top.
        "headroom_range_px": [min(ys) - hi_y, min(ys) - lo_y],
        "corners": [(c[0] * scale - crop_x, c[1] * scale - crop_y) for c in corners],
    }


# --------------------------------------------------------------------------------------
# SVG emission
# --------------------------------------------------------------------------------------

def _fmt(value: float) -> str:
    return f"{value:.2f}"


def rounded_clip_path(corners, radii) -> str:
    """The cut-out's outline as an SVG path, with a real arc at each rounded corner.

    Tangent lengths come from each corner's measured interior angle, not an assumed 90 deg — on a
    keystoned screen they differ by a third between the sharpest and bluntest corner.
    """
    angles = interior_angles(corners)
    arc_in, arc_out = [], []
    for i in range(4):
        radius = radii[i]
        tangent = 0.0 if radius <= 0 else radius / math.tan(math.radians(angles[i] / 2.0))
        for other, bucket in ((corners[(i - 1) % 4], arc_in), (corners[(i + 1) % 4], arc_out)):
            dx, dy = other[0] - corners[i][0], other[1] - corners[i][1]
            length = math.hypot(dx, dy)
            bucket.append((corners[i][0] + tangent * dx / length,
                           corners[i][1] + tangent * dy / length))
    sweep = 1 if signed_area(corners) > 0 else 0
    parts = [f"M {_fmt(arc_in[0][0])} {_fmt(arc_in[0][1])}"]
    for i in range(4):
        if radii[i] > 0:
            parts.append(f"A {_fmt(radii[i])} {_fmt(radii[i])} 0 0 {sweep} "
                         f"{_fmt(arc_out[i][0])} {_fmt(arc_out[i][1])}")
        nxt = arc_in[(i + 1) % 4]
        parts.append(f"L {_fmt(nxt[0])} {_fmt(nxt[1])}")
    parts.append("Z")
    return " ".join(parts)


def svg_geometry(canvas_corners, canvas_radii) -> dict:
    polygon = " ".join(f"{_fmt(x)},{_fmt(y)}" for x, y in canvas_corners)
    xs = [c[0] for c in canvas_corners]
    ys = [c[1] for c in canvas_corners]
    image = {"x": min(xs), "y": min(ys), "width": max(xs) - min(xs), "height": max(ys) - min(ys)}
    rounded = rounded_clip_path(canvas_corners, canvas_radii)
    snippet = (
        "<defs>\n"
        "  <clipPath id=\"screen\">\n"
        f"    <polygon points=\"{polygon}\"/>\n"
        "  </clipPath>\n"
        "</defs>\n"
        "<image id=\"screenshot\" clip-path=\"url(#screen)\"\n"
        f"       x=\"{_fmt(image['x'])}\" y=\"{_fmt(image['y'])}\" "
        f"width=\"{_fmt(image['width'])}\" height=\"{_fmt(image['height'])}\"\n"
        "       href=\"\" preserveAspectRatio=\"xMidYMid slice\"/>"
    )
    return {
        "clip_polygon_points": polygon,
        "clip_path_rounded": rounded,
        "image": image,
        "perspective": [list(c) for c in canvas_corners],
        "snippet": snippet,
    }


# --------------------------------------------------------------------------------------
# Quality warnings — the part that earns the tool its keep on hand-cut alpha
# --------------------------------------------------------------------------------------

def _warn(code, message, fix):
    return {"code": code, "message": message, "fix": fix}


def collect_warnings(*, alpha_map, regions, screen, classification) -> list:
    warnings = []

    specks = regions[1:]
    if specks:
        total = sum(r.area for r in specks)
        biggest = specks[0]
        warnings.append(_warn(
            "stray-specks",
            f"{len(specks)} stray transparent region(s) outside the screen, {total} px in total; "
            f"largest is {biggest.area} px at ({biggest.cx:.0f}, {biggest.cy:.0f})",
            "these are eraser slips or leftover selection crumbs — the renderer will show the "
            "screenshot through them; flatten them back to opaque in the source image"))

    softness = screen["edge_softness"]
    if softness["verdict"] == "feathered":
        warnings.append(_warn(
            "feathered-edge",
            f"the cut-out edge is soft: {softness['partial_pixels']} partial-alpha pixels for a "
            f"{softness['perimeter_px']:.0f} px perimeter ({softness['ratio']:.1f} px wide, vs "
            f"~1.0 for normal anti-aliasing)",
            "a feathered edge lets the room bleed over the screenshot; re-cut with a hard "
            "selection (feather 0, anti-alias on) instead of a blurred or softened one"))

    wobbly = [e for e in screen["edges"] if e["residual_max_px"] > EDGE_RESIDUAL_TOL_PX]
    if wobbly:
        worst = max(wobbly, key=lambda e: e["residual_max_px"])
        warnings.append(_warn(
            "wobbly-edge",
            f"{len(wobbly)} of 4 edges are not straight (worst: {worst['name']}, "
            f"{worst['residual_max_px']:.2f} px off its best-fit line, tolerance "
            f"{EDGE_RESIDUAL_TOL_PX} px)",
            "a real screen edge is dead straight — this looks like a freehand lasso; re-cut the "
            "screen with a four-point polygonal selection"))

    fit_error = abs(1.0 - screen["mask_over_quad"])
    if fit_error > QUAD_FIT_AREA_TOL:
        warnings.append(_warn(
            "not-a-quadrilateral",
            f"the transparent region fills {screen['mask_over_quad']:.3f} of the quadrilateral "
            f"fitted to it (tolerance {1 + QUAD_FIT_AREA_TOL:.2f})",
            "the cut-out is not a convex four-sided shape — check for a bite taken out of an "
            "edge, an unclosed selection, or a second shape merged into the screen"))

    angles = screen["interior_angles_deg"]
    worst_angle = max(abs(angles[k] - 90.0) for k in CORNER_NAMES)
    radii = screen["corner_radius_px"]
    spread = 0.0
    if radii["mean"] > 1.0:
        spread = (max(radii[k] for k in CORNER_NAMES) - min(radii[k] for k in CORNER_NAMES)) / radii["mean"]
    if worst_angle > ANGLE_ASYMMETRY_TOL_DEG or spread > CORNER_RADIUS_SPREAD_TOL:
        warnings.append(_warn(
            "asymmetric-corners",
            f"the quad's corners are lopsided: worst interior angle is {worst_angle:.1f} deg off "
            f"square (tolerance {ANGLE_ASYMMETRY_TOL_DEG}), corner-radius spread is "
            f"{spread:.2f} of the mean (tolerance {CORNER_RADIUS_SPREAD_TOL})",
            "camera perspective skews a screen by a few degrees, not this much — check that all "
            "four corners of the screen were actually caught by the selection"))

    fraction = screen["area_fraction_of_image"]
    if fraction < MIN_SCREEN_AREA_FRAC:
        warnings.append(_warn(
            "screen-too-small",
            f"the cut-out is only {fraction * 100:.1f}% of the frame (expected at least "
            f"{MIN_SCREEN_AREA_FRAC * 100:.0f}%)",
            "either the wrong region was measured, or the screen is too small in this photo to "
            "carry a readable screenshot at store resolution — re-shoot closer"))
    elif fraction > MAX_SCREEN_AREA_FRAC:
        warnings.append(_warn(
            "screen-too-large",
            f"the cut-out is {fraction * 100:.1f}% of the frame (expected at most "
            f"{MAX_SCREEN_AREA_FRAC * 100:.0f}%)",
            "almost nothing of the room is left — check that the alpha was punched through the "
            "screen only, not the whole photo"))

    screen_region = regions[0]
    if (screen_region.x_min <= 0 or screen_region.y_min <= 0
            or screen_region.x_max >= alpha_map.width - 1
            or screen_region.y_max >= alpha_map.height - 1):
        warnings.append(_warn(
            "region-touches-border",
            "the cut-out runs into the edge of the image, so at least one screen corner is "
            "outside the photo",
            "the measured corner there is an artefact of the crop, not the real screen corner — "
            "use a scene photo that contains the whole device"))

    return warnings


# --------------------------------------------------------------------------------------
# The analysis
# --------------------------------------------------------------------------------------

def _empty_report(source, alpha_map, histogram, regions, errors) -> dict:
    return {
        "tool": TOOL,
        "version": REPORT_VERSION,
        "image": {"path": str(source), "width": alpha_map.width, "height": alpha_map.height},
        "alpha": histogram,
        "regions": {"count": len(regions), "largest_area": regions[0].area if regions else 0,
                    "specks": []},
        "screen": None,
        "classification": None,
        "canvas": None,
        "svg": None,
        "notes": [],
        "warnings": [],
        "errors": errors,
        "exit_code": 2,
    }


def analyse_alpha(alpha_map: AlphaMap, *, device: str = "ipad", source: str = "<memory>") -> dict:
    """Measure the cut-out and return the full report. Never raises for a bad *image* — image
    problems come back as `errors` with `exit_code` 2 — but does raise `InvocationError` for a
    bad *request*, because an unknown device is the caller's bug, not the scene's."""
    if device not in DEVICE_CANVASES:
        raise InvocationError(
            f"unknown device {device!r}; known: {', '.join(sorted(DEVICE_CANVASES))}")
    canvas_w, canvas_h = DEVICE_CANVASES[device]

    histogram = alpha_histogram(alpha_map)
    regions = find_regions(alpha_map)
    if not regions:
        return _empty_report(source, alpha_map, histogram, regions, [_warn(
            "no-cutout",
            f"no pixels below alpha {ALPHA_THRESHOLD} — this image has no screen cut-out",
            "cut the screen area out of the scene photo (alpha 0) before measuring it")])

    screen_region = regions[0]
    points = boundary_points(alpha_map, screen_region)
    try:
        quad = fit_quad(points)
    except UnusableSceneError as exc:
        return _empty_report(source, alpha_map, histogram, regions, [_warn(
            "degenerate-quad", str(exc),
            "the transparent region cannot be reduced to four corners — re-cut it as a simple "
            "four-sided screen shape")])

    corners = quad.corners
    radii = corner_radii(quad, points)
    angles = interior_angles(corners)
    sides = side_lengths(corners)
    quad_area = polygon_area(corners)
    perimeter = sum(sides)
    image_area = alpha_map.width * alpha_map.height
    bbox_w = max(c[0] for c in corners) - min(c[0] for c in corners)
    bbox_h = max(c[1] for c in corners) - min(c[1] for c in corners)

    edges = []
    for i in range(4):
        chosen = quad.samples[i] or [corners[i], corners[(i + 1) % 4]]
        distances = [line_distance(quad.lines[i], p) for p in chosen]
        edges.append({
            "name": EDGE_NAMES[i],
            "length_px": sides[i],
            "angle_deg": edge_angle(corners, i),
            "residual_rms_px": math.sqrt(sum(d * d for d in distances) / len(distances)),
            "residual_max_px": max(distances),
            "sample_count": len(quad.samples[i]),
        })

    softness_ratio = histogram["partial"] / perimeter if perimeter else 0.0
    screen = {
        "corners_px": {name: list(c) for name, c in zip(CORNER_NAMES, corners)},
        "corners_normalised": {
            name: [c[0] / alpha_map.width, c[1] / alpha_map.height]
            for name, c in zip(CORNER_NAMES, corners)},
        "bbox_px": {"x": min(c[0] for c in corners), "y": min(c[1] for c in corners),
                    "width": bbox_w, "height": bbox_h},
        "mask_area_px": screen_region.area,
        "quad_area_px": quad_area,
        "fill_ratio": screen_region.area / ((screen_region.x_max - screen_region.x_min + 1)
                                            * (screen_region.y_max - screen_region.y_min + 1)),
        "mask_over_quad": screen_region.area / quad_area,
        "corner_radius_px": dict(zip(CORNER_NAMES, radii), mean=sum(radii) / 4.0),
        "interior_angles_deg": dict(zip(CORNER_NAMES, angles)),
        "side_lengths_px": dict(zip(EDGE_NAMES, sides)),
        "edges": edges,
        "diagonals": diagonal_report(corners),
        "edge_softness": {
            "partial_pixels": histogram["partial"],
            "perimeter_px": perimeter,
            "ratio": softness_ratio,
            "verdict": "feathered" if softness_ratio > FEATHER_RATIO_TOL else "hard",
        },
        "area_fraction_of_image": quad_area / image_area,
    }
    classification = classify_quad(corners)

    notes = []
    errors = []
    canvas = None
    svg = None
    try:
        fit = solve_cover_fit(alpha_map.width, alpha_map.height, canvas_w, canvas_h, corners)
    except UnusableSceneError as exc:
        errors.append(_warn(
            "off-canvas", str(exc),
            f"no cover-fit crop of this photo puts the whole screen inside {canvas_w}x{canvas_h}"))
    else:
        canvas_corners = fit["corners"]
        canvas = {
            "device": device,
            "width": canvas_w,
            "height": canvas_h,
            "scale": fit["scale"],
            "scaled_width": fit["scaled_width"],
            "scaled_height": fit["scaled_height"],
            "crop": {k: fit[k] for k in (
                "x", "y", "x_centered", "y_centered", "x_range", "y_range", "policy",
                "y_end_of_range", "policy_reason", "centered_feasible", "headroom_px",
                "headroom_fraction", "footroom_px", "headroom_range_px")},
            "corners_px": {name: list(c) for name, c in zip(CORNER_NAMES, canvas_corners)},
            "bbox_px": {
                "x": min(c[0] for c in canvas_corners), "y": min(c[1] for c in canvas_corners),
                "width": max(c[0] for c in canvas_corners) - min(c[0] for c in canvas_corners),
                "height": max(c[1] for c in canvas_corners) - min(c[1] for c in canvas_corners)},
        }
        svg = svg_geometry(canvas_corners, [r * fit["scale"] for r in radii])
        notes.append(
            f"headline headroom: {fit['headroom_px']:.1f} canvas px above the screen "
            f"({fit['headroom_fraction'] * 100:.1f}% of the {canvas_h} px canvas), with "
            f"{fit['footroom_px']:.1f} px left below it. Crop y={fit['y']:.2f} sits at the "
            f"{fit['y_end_of_range']} end of the feasible range "
            f"[{fit['y_range'][0]:.2f}, {fit['y_range'][1]:.2f}]: {fit['policy_reason']}. "
            f"Across that whole range the headline gets between "
            f"{fit['headroom_range_px'][0]:.1f} and {fit['headroom_range_px'][1]:.1f} px")
        if not fit["centered_feasible"]:
            notes.append(
                f"a centred cover crop (y={fit['y_centered']:.2f}) would push the screen off the "
                f"{canvas_w}x{canvas_h} canvas — the renderer must use this asymmetric offset, "
                f"not a centred one")
        if classification["shape"] == "perspective-trapezoid":
            notes.append(
                "genuine perspective: clip alone will look flat against the frame's converging "
                "edges — feed `svg.perspective` to the renderer's per-slot `perspective` field so "
                "the capture is pre-warped")

    warnings = collect_warnings(alpha_map=alpha_map, regions=regions, screen=screen,
                                classification=classification)

    return {
        "tool": TOOL,
        "version": REPORT_VERSION,
        "image": {"path": str(source), "width": alpha_map.width, "height": alpha_map.height},
        "alpha": histogram,
        "regions": {
            "count": len(regions),
            "largest_area": screen_region.area,
            "specks": [{"area": r.area, "bbox": [r.x_min, r.y_min, r.x_max, r.y_max],
                        "centroid": [r.cx, r.cy]} for r in regions[1:]],
        },
        "screen": screen,
        "classification": classification,
        "canvas": canvas,
        "svg": svg,
        "notes": notes,
        "warnings": warnings,
        "errors": errors,
        "exit_code": 2 if errors else (1 if warnings else 0),
    }


def analyse_file(path, *, device: str = "ipad") -> dict:
    return analyse_alpha(read_alpha(path), device=device, source=path)


# --------------------------------------------------------------------------------------
# Human-readable output
# --------------------------------------------------------------------------------------

def format_report(report: dict) -> str:
    out = []
    image = report["image"]
    out.append(f"{TOOL}: {image['path']}  ({image['width']} x {image['height']})")
    alpha = report["alpha"]
    out.append(f"  alpha        transparent {alpha['transparent']}  partial {alpha['partial']}  "
               f"opaque {alpha['opaque']}  (masked < {alpha['threshold']}: {alpha['masked']})")
    out.append(f"  regions      {report['regions']['count']} "
               f"(screen = {report['regions']['largest_area']} px, "
               f"{len(report['regions']['specks'])} stray)")

    if report["errors"]:
        for err in report["errors"]:
            out.append(f"  ERROR [{err['code']}] {err['message']}")
            out.append(f"        fix: {err['fix']}")

    screen = report["screen"]
    if screen:
        out.append("")
        out.append(f"  shape        {report['classification']['shape']}")
        for name, test in report["classification"]["tests"].items():
            mark = "ok  " if test["passed"] else "FAIL"
            out.append(f"    {mark} {name:<19} {test['measured']:.5f} "
                       f"(tolerance {test['tolerance']})")
        out.append("")
        out.append("  corners (original px / normalised)")
        for key in CORNER_NAMES:
            px = screen["corners_px"][key]
            nm = screen["corners_normalised"][key]
            out.append(f"    {key.upper()}  {px[0]:10.2f} {px[1]:10.2f}    "
                       f"{nm[0]:.4f} {nm[1]:.4f}")
        out.append(f"  bbox         {screen['bbox_px']['width']:.2f} x "
                   f"{screen['bbox_px']['height']:.2f}   fill ratio {screen['fill_ratio']:.4f}   "
                   f"{screen['area_fraction_of_image'] * 100:.1f}% of frame")
        out.append(f"  radius       mean {screen['corner_radius_px']['mean']:.2f} px   "
                   + "  ".join(f"{k.upper()} {screen['corner_radius_px'][k]:.2f}"
                               for k in CORNER_NAMES))
        out.append("  edges        " + "  ".join(
            f"{e['name']} {e['angle_deg']:+.2f}deg res {e['residual_max_px']:.3f}"
            for e in screen["edges"]))
        out.append(f"  edge         {screen['edge_softness']['verdict']} "
                   f"({screen['edge_softness']['ratio']:.2f} partial px per perimeter px)")

    canvas = report["canvas"]
    if canvas:
        crop = canvas["crop"]
        out.append("")
        out.append(f"  canvas       {canvas['device']} {canvas['width']} x {canvas['height']}   "
                   f"cover scale {canvas['scale']:.6f}   "
                   f"scaled {canvas['scaled_width']:.1f} x {canvas['scaled_height']:.1f}")
        out.append(f"  crop         x {crop['x']:.2f}  y {crop['y']:.2f}   [{crop['policy']}, "
                   f"y at the {crop['y_end_of_range']} end]   centred would be "
                   f"x {crop['x_centered']:.2f} y {crop['y_centered']:.2f}"
                   f"{'' if crop['centered_feasible'] else '  (centred CLIPS the screen)'}")
        out.append(f"  crop range   x [{crop['x_range'][0]:.2f}, {crop['x_range'][1]:.2f}]   "
                   f"y [{crop['y_range'][0]:.2f}, {crop['y_range'][1]:.2f}]")
        out.append(f"  headroom     {crop['headroom_px']:.1f} px "
                   f"({crop['headroom_fraction'] * 100:.1f}% of {canvas['height']})   "
                   f"footroom {crop['footroom_px']:.1f} px   "
                   f"range over the crop window "
                   f"{crop['headroom_range_px'][0]:.1f}..{crop['headroom_range_px'][1]:.1f} px")
        out.append("  corners (canvas px)")
        for key in CORNER_NAMES:
            c = canvas["corners_px"][key]
            out.append(f"    {key.upper()}  {c[0]:10.2f} {c[1]:10.2f}")
        out.append("")
        out.append("  paste into the slot template:")
        out.append("")
        for line in report["svg"]["snippet"].splitlines():
            out.append(f"    {line}")
        out.append("")
        out.append(f"    rounded alternative: <path d=\"{report['svg']['clip_path_rounded']}\"/>")
        out.append(f"    manifest perspective: "
                   f"{json.dumps([[round(v, 2) for v in p] for p in report['svg']['perspective']])}")

    for note in report["notes"]:
        out.append("")
        out.append(f"  note: {note}")

    if report["warnings"]:
        out.append("")
        for warning in report["warnings"]:
            out.append(f"  WARNING [{warning['code']}] {warning['message']}")
            out.append(f"          fix: {warning['fix']}")

    out.append("")
    verdict = {0: "clean", 1: "usable, with warnings", 2: "unusable"}[report["exit_code"]]
    out.append(f"  verdict      {verdict}")
    return "\n".join(out)


# --------------------------------------------------------------------------------------
# CLI
# --------------------------------------------------------------------------------------

def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog=TOOL, description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("image", help="scene PNG whose screen area has been cut out (alpha 0)")
    parser.add_argument("--device", default="ipad",
                        help=f"store canvas to map onto: {', '.join(sorted(DEVICE_CANVASES))}")
    parser.add_argument("--json", action="store_true",
                        help="emit the full measurement as JSON on stdout and nothing else")
    return parser


def main(argv: list | None = None) -> int:
    args = build_parser().parse_args(argv)
    try:
        report = analyse_file(Path(args.image), device=args.device)
    except InvocationError as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 2
    except ExternalToolError as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 3

    if args.json:
        print(json.dumps(report, indent=2))
    else:
        print(format_report(report))
    return report["exit_code"]


if __name__ == "__main__":
    sys.exit(main())
