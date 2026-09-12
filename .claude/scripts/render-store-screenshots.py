#!/usr/bin/env python3
"""render-store-screenshots.py — turn the App Store manifest into finished slot images.

Manifest + SVG templates + UI captures + scene photos -> one PNG per device x locale x slot,
in one command (FR-9010-32, SC-9010-06). This is AP-3, the real renderer; the throwaway AP-2
spike (`tmp/ap2-spike/render-spike.py`) proved the four hard gates — exact pixel size, no
alpha, sRGB, real SF Pro, byte-identical repeat renders — on a single slot before this script
generalised the recipe to the full manifest.

Zero third-party dependencies (FR-9010-25): stdlib Python 3 only, no pip, no venv. External
work is done by shelling out to binaries already verified present on this machine
(FR-9010-26): headless Chrome for SVG -> PNG (the only installed renderer that resolves SF
Pro correctly — `rsvg-convert`, `resvg`, `inkscape` and `cairosvg` are all absent, and
ImageMagick's own SVG delegate points at the missing `rsvg-convert`), and ImageMagick 7 for
`-distort Perspective`. Installing a different SVG renderer is a fallback that changes the
template contract (FR-9010-15/16) and must be re-specified, not improvised here.

Traps this script exists to not re-learn (each one cost real time in the AP-2 spike):

  * Perspective. A `<clipPath>` only cuts, and SVG transforms are affine, so neither can place a
    capture onto a screen photographed at an angle. The capture is pre-warped with a homography
    BEFORE it is embedded (see "The screen quad and the perspective pre-warp" below); a quad that
    is an axis-aligned rectangle skips that path entirely and stays byte-identical.
  * Namespaces. `ET.register_namespace` for the SVG and xlink namespaces MUST run before any
    parsing/serialising happens, or `xml.etree.ElementTree` emits `ns0:` prefixes on output
    and Chrome renders nothing.
  * Font. The template's `font-family="system-ui, BlinkMacSystemFont, sans-serif"` is the
    only spelling that resolves to real SF Pro in Chrome 151 — `-apple-system`, `"SF Pro
    Display"` and `"SF Pro Text"` all fail to resolve and fall back *silently* to Times. This
    lives in the template (out of scope here); never introduce `-apple-system` in this file.
  * Chrome's stdio. Chrome forks a crashpad/updater child that inherits stdout/stderr and
    never closes them, so `subprocess.run(capture_output=True)` / `.communicate()` blocks
    forever even after the screenshot file has been written. Output is redirected to a log
    FILE instead, and the result is read back off disk.
  * Chrome doesn't exit. Chrome 151 lingers after writing `--screenshot`'s output instead of
    quitting. The fix is to poll the output file until its size is stable for three
    consecutive 0.25s readings, then kill the whole process group ourselves
    (`start_new_session=True` + `os.killpg(..., SIGKILL)`). Killing after size has settled
    cannot truncate the PNG — the FR-9010-29 assertions below would catch it if it somehow did.
  * Determinism (FR-9010-30) vs. metadata (FR-9010-29). `magick -profile <sRGB.icc>` without
    `-strip` embeds `date:create`/`date:modify`/`date:timestamp` tEXt chunks, so two renders a
    second apart differ byte-for-byte. Adding `-strip` afterwards removes the sRGB chunk it
    just wrote. The resolution used here: strip *everything*, then hand-write the one-byte
    sRGB chunk (rendering intent 0, the same value the capture rig's own PNGs carry) directly
    into the PNG bytes, right after IHDR.

Degrading honestly (asset reality, 2026-09): today only `Design/AppStore/templates/ipad/
slot-03.svg` exists and `Design/AppStore/scenes/` is deliberately empty (nothing in `Design/`
is a placeholder, by rule) — so a bare invocation against the real manifest cannot produce the
full six-slot set. The chosen policy is **skip-with-warning, not hard-fail-everything**: every
requested (device, locale, slot) combination is attempted independently; a combination whose
template/scene/capture doesn't resolve is skipped with a named reason on stderr, but a sibling
combination that DOES resolve still renders. The overall exit code is 0 only when every
requested combination actually rendered and passed its FR-9010-29 assertions — so a partial
run can never be mistaken for a complete one, but a narrowed invocation (e.g. `--device ipad
--slot 03-source-choice --scene 03-source-choice=<placeholder>`) can succeed cleanly today.

`--check` (FR-9010-31) reports **every** problem it finds, not just the first, then exits
non-zero — a deliberate superset of the spec's literal "exits on the first problem, naming
it": when six slots are broken, discovering that one message at a time is a rediscovery tax
nobody should pay twice, and reporting the full list is strictly more useful with no downside.

Usage:
  # Full set: every declared device x locale x slot in one invocation (FR-9010-32).
  render-store-screenshots.py

  # Validate the manifest and every referenced asset without rendering (SC-9010-03).
  render-store-screenshots.py --check

  # Narrow to what's actually renderable today, using the sanctioned placeholder-scene escape
  # hatch (scene photographs don't exist yet; Design/ carries no placeholders by rule).
  render-store-screenshots.py --device ipad --slot 03-source-choice \\
      --scene 03-source-choice=tmp/ap2-spike/PLACEHOLDER-scene.jpg

  # List the resolved (device, locale, slot, template, scene, capture) tuples without touching
  # Chrome or ImageMagick at all.
  render-store-screenshots.py --list

Exit codes: 0 ok · 1 --check found problems, or a rendered output failed its FR-9010-29
assertions, or the manifest has schema problems that block rendering · 2 bad invocation
(unknown --device/--locale/--slot/--scene, unreadable or malformed-JSON manifest) · 3 an
external tool (Chrome or ImageMagick) failed or could not be found.
"""

from __future__ import annotations

import argparse
import base64
import hashlib
import json
import mimetypes
import os
import re
import shutil
import signal
import struct
import subprocess
import sys
import time
import zlib
import xml.etree.ElementTree as ET
from pathlib import Path
from typing import NamedTuple

ROOT = Path(__file__).resolve().parents[2]

SVG_NS = "http://www.w3.org/2000/svg"
XLINK_NS = "http://www.w3.org/1999/xlink"
# Must run before any ET.parse/ET.tostring — see the header's "Namespaces" trap.
ET.register_namespace("", SVG_NS)
ET.register_namespace("xlink", XLINK_NS)

CHROME = "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"

# FR-9010-24 / README: fit -> preserveAspectRatio. `fill` stretches; it exists so stretching is
# always an explicit authoring decision, never a silent one.
PAR = {"cover": "xMidYMid slice", "contain": "xMidYMid meet", "fill": "none"}

REQUIRED_SLOT_KEYS = ("id", "type", "template", "capture", "fit", "headline")

# The two slot archetypes (9010, FR-9010-03 amendment 2026-09-10). A `scene` slot composites its
# capture into a photographed room; a `ui` slot drops the room and stands the screen on the
# ground its own template draws. `type` is therefore load-bearing — it decides whether `scene`
# is required — so it is validated against this vocabulary rather than merely being present.
SLOT_TYPES = ("scene", "ui")

HTML = """<!doctype html>
<meta charset="utf-8">
<style>html,body{{margin:0;padding:0;overflow:hidden;background:#000}}svg{{display:block}}</style>
{svg}
"""


class InvocationError(Exception):
    """Bad CLI usage or a manifest reference that cannot even be resolved (exit code 2)."""


class RenderAssertionError(RuntimeError):
    """A rendered PNG failed an FR-9010-29 assertion (exit code 1)."""


class ExternalToolError(RuntimeError):
    """Chrome or ImageMagick failed, was not found, or produced no output (exit code 3)."""


class GeometryError(ValueError):
    """A template's screen quad cannot be turned into a homography, or is expressed in a shape
    this renderer does not read back (exit code 1). Subclasses ValueError so a caller that only
    wants "bad authoring input" can catch either."""


class SlotPaths(NamedTuple):
    template: Path
    scene: Path | None
    capture: Path | None


# --------------------------------------------------------------------------------------
# Data URIs (FR-9010-27) — images go into the resolved SVG as base64 data URIs, so the
# document handed to Chrome is self-contained and independent of file:// resolution.
# --------------------------------------------------------------------------------------

def data_uri(path: Path) -> str:
    mime = mimetypes.guess_type(path.name)[0] or "application/octet-stream"
    return f"data:{mime};base64," + base64.b64encode(path.read_bytes()).decode("ascii")


# --------------------------------------------------------------------------------------
# Id-based substitution (FR-9010-16). Never string-templating: every id is looked up and
# mutated on the parsed tree. `screenshot` (and, per FR-9010-16, a future `logo`/`qr`) may be
# absent from a template — this function must never dereference an id it hasn't first found.
# --------------------------------------------------------------------------------------

def by_id(root: ET.Element, wanted: str) -> ET.Element | None:
    for el in root.iter():
        if el.get("id") == wanted:
            return el
    return None


def preserve_aspect_ratio(fit: str) -> str:
    try:
        return PAR[fit]
    except KeyError:
        raise ValueError(f"unknown fit {fit!r} (expected one of {sorted(PAR)})") from None


def fill_text_lines(text_el: ET.Element, lines: list[str], *, element_id: str) -> None:
    """Rebuild a text element's <tspan> children from `lines`, keeping the template's own
    attributes: tspan[0]'s for the first line, tspan[1]'s for every line after it (so the
    template owns x and the line spacing, and the manifest owns only the words)."""
    tspans = [c for c in list(text_el) if c.tag == f"{{{SVG_NS}}}tspan"]
    if len(tspans) < 2:
        raise ValueError(f'template {element_id} id="{element_id}" must ship at least two '
                          "<tspan> children")
    first_attrs, rest_attrs = dict(tspans[0].attrib), dict(tspans[1].attrib)
    for child in list(text_el):
        text_el.remove(child)
    text_el.text = None
    for i, line in enumerate(lines):
        t = ET.SubElement(text_el, f"{{{SVG_NS}}}tspan", first_attrs if i == 0 else rest_attrs)
        t.text = line


def substitute(root: ET.Element, *, scene_uri: str | None, screenshot_uri: str | None,
               fit: str, lines: list[str], warped: bool = False,
               subline_lines: list[str] | None = None) -> None:
    """Mutates `root` in place: sets `scene` and `screenshot` (each only if the template has
    one), and rebuilds `headline`'s <tspan> children from `lines` (FR-9010-16/22).

    `subline` is the optional second text block (Jan, 2026-09-12: "text bottom AND top"), filled
    from the manifest exactly as the headline is — store copy lives in content.json and nowhere
    else (FR-9010-20), so a template never carries a sentence of its own. Element and copy must
    agree: an element with no copy, and copy with no element, are both authoring mistakes that
    would otherwise ship silently, the same policy the scene/screenshot pair already enforces.

    `warped=True` means the capture handed in has already been pre-warped onto the screen quad
    and authored in the `screenshot` box's own units, so the <image> must map it 1:1 —
    `preserveAspectRatio="none"`. Any other value would re-fit the bitmap inside the box and
    slide the warp off the quad. `fit` is still validated either way, so a bad value is never
    silently swallowed by a perspective slot; the homography has simply already consumed it."""
    # `scene` is optional in exactly the way `screenshot` is, and the two error cases are the
    # mirror of each other: an id the manifest cannot feed, and an asset no id can consume.
    # Both are authoring mistakes that would otherwise ship as a slot nobody noticed was wrong —
    # a UI slot with a stray room, or a photo slot rendering onto bare ground.
    scene_el = by_id(root, "scene")
    if scene_el is not None:
        if scene_uri is None:
            raise ValueError(
                'template has an element id="scene" but no scene data was supplied'
            )
        scene_el.set("href", scene_uri)
        # `fit` governs the capture only, never the scene (README) — scene's own
        # preserveAspectRatio, baked into the template, is deliberately never touched here.
    elif scene_uri is not None:
        raise ValueError('a scene was supplied but the template has no element id="scene"')

    screenshot_el = by_id(root, "screenshot")
    if screenshot_el is not None:
        if screenshot_uri is None:
            raise ValueError(
                'template has an element id="screenshot" but no capture data was supplied'
            )
        screenshot_el.set("href", screenshot_uri)
        par = preserve_aspect_ratio(fit)
        screenshot_el.set("preserveAspectRatio", "none" if warped else par)
    # else: scene-only template — do nothing. Never dereference an id the template lacks.

    text_el = by_id(root, "headline")
    if text_el is None:
        raise ValueError('template has no element id="headline"')
    fill_text_lines(text_el, lines, element_id="headline")

    subline_el = by_id(root, "subline")
    if subline_el is not None:
        if not subline_lines:
            raise ValueError(
                'template has an element id="subline" but the manifest slot has no subline copy'
            )
        fill_text_lines(subline_el, subline_lines, element_id="subline")
    elif subline_lines:
        raise ValueError('subline copy was supplied but the template has no element id="subline"')


# --------------------------------------------------------------------------------------
# The screen quad and the perspective pre-warp (FR-9010-23/26).
#
# Why this exists at all: a `<clipPath>` only CUTS, it never transforms, and SVG's own
# transforms are affine (`matrix(a,b,c,d,e,f)`) — affine maps cannot express perspective. A
# capture clipped into a screen that was photographed at an angle would therefore show the
# wrong part of itself with the wrong geometry: its straight UI lines would stay parallel while
# the frame around them converges. The fix is to pre-warp the capture with a homography onto
# the target quad BEFORE it is embedded, so by the time the SVG sees it, it is already in the
# scene's perspective and the clipPath is back to doing only what a clipPath can do — the edge
# and the rounded corners.
#
# Where the quad comes from: the TEMPLATE, read back out of the `<clipPath>` the `screenshot`
# element already points at. The quad has to exist there anyway (README, "screenshot is clipped,
# not cropped"), so deriving the warp from it keeps ONE source of truth and needs no manifest
# change. A per-slot key in content.json would be a second copy that can silently drift — and
# drift here is invisible, the render just looks subtly wrong — and, decisively, a slot renders
# against a DIFFERENT template per device class (`templates/ipad/slot-05.svg` vs
# `templates/iphone/slot-05.svg`), so one per-slot quad cannot describe both geometries at all.
# The manifest's `perspective` (FR-9010-23) is kept as an explicit per-slot OVERRIDE for the
# case where the clip shape and the warp target must differ; absent, the template wins.
# --------------------------------------------------------------------------------------

# Canvas pixels. Anything this close to axis-aligned is treated as straight-on and is NOT
# warped — that is the byte-identical path (FR-9010-30) every existing template takes today.
QUAD_TOLERANCE = 0.5

CORNER_NAMES = ("TL", "TR", "BR", "BL")


def _fmt(value: float) -> str:
    """Shortest exact-enough decimal for an ImageMagick control point or an error message.
    `%g` would silently round 6 significant digits away from a canvas coordinate like
    1828.1637; this keeps six decimal places and then trims the noise."""
    text = f"{float(value):.6f}".rstrip("0").rstrip(".")
    return "0" if text in ("", "-0") else text


def parse_points(text: str) -> list[tuple[float, float]]:
    """SVG `points` grammar: numbers separated by commas and/or whitespace, in x y pairs."""
    numbers = [n for n in re.split(r"[,\s]+", (text or "").strip()) if n]
    if len(numbers) % 2:
        raise GeometryError(f"points list has an odd number of coordinates: {text!r}")
    try:
        values = [float(n) for n in numbers]
    except ValueError as exc:
        raise GeometryError(f"points list is not numeric: {text!r}") from exc
    return list(zip(values[0::2], values[1::2]))


def clip_path_id(element: ET.Element) -> str | None:
    """`clip-path="url(#screen-quad)"` -> `screen-quad`."""
    match = re.match(r"\s*url\(\s*#([^)\s]+)\s*\)\s*$", element.get("clip-path") or "")
    return match.group(1) if match else None


def quad_from_clip_shape(shape: ET.Element) -> list[tuple[float, float]]:
    """The two clip shapes this renderer reads back, clockwise from top-left.

    A `<path>` is deliberately NOT read: recovering four corners from a rounded-corner path
    means intersecting the straight runs, and the arc endpoints are tangent points rather than
    corners, so a naive read would be quietly wrong by a corner radius. CUTOUT.md's own note
    applies — the sharp-corner polygon is safe to clip with, because the sliver it leaves
    outside the true rounded corner falls on the opaque bezel of the scene photograph anyway.
    """
    tag = shape.tag.split("}")[-1]
    if tag == "rect":
        x, y = float(shape.get("x", 0)), float(shape.get("y", 0))
        w, h = float(shape.get("width", 0)), float(shape.get("height", 0))
        return [(x, y), (x + w, y), (x + w, y + h), (x, y + h)]
    if tag in ("polygon", "polyline"):
        points = parse_points(shape.get("points", ""))
        if len(points) != 4:
            raise GeometryError(
                f"clipPath <{tag}> must carry exactly four points, got {len(points)}")
        return points
    raise GeometryError(
        f"clipPath shape <{tag}> is not readable as a screen quad; "
        "use a <rect> (straight-on) or a four-point <polygon> (perspective)")


def template_screen_quad(root: ET.Element, *, element_id: str = "screenshot"
                          ) -> list[tuple[float, float]] | None:
    """The screen quad in canvas coordinates, or None when the template declares none (no
    `screenshot` element, or one with no `clip-path`) — which means "straight-on, no warp"."""
    element = by_id(root, element_id)
    if element is None:
        return None
    ref = clip_path_id(element)
    if ref is None:
        return None
    clip = by_id(root, ref)
    if clip is None:
        raise GeometryError(f'clip-path url(#{ref}) has no matching element in the template')
    shapes = [child for child in clip if isinstance(child.tag, str)]
    if len(shapes) != 1:
        raise GeometryError(
            f'clipPath id="{ref}" must hold exactly one shape, got {len(shapes)}')
    return quad_from_clip_shape(shapes[0])


def image_box(element: ET.Element) -> tuple[float, float, float, float]:
    """`<image x y width height>` as floats — the box the warped bitmap is authored in."""
    return (float(element.get("x", 0)), float(element.get("y", 0)),
            float(element.get("width", 0)), float(element.get("height", 0)))


def screen_quad_for(root: ET.Element, slot: dict) -> list[tuple[float, float]] | None:
    """Manifest `perspective` wins if present and well-formed; otherwise the template's own
    clipPath. `_perspective_problems` has already reported a malformed one to --check, so a
    bad override falls through to the template rather than crashing the render."""
    override = slot.get("perspective")
    if isinstance(override, list) and len(override) == 4:
        try:
            return [(float(p[0]), float(p[1])) for p in override]
        except (TypeError, ValueError, IndexError):
            pass
    return template_screen_quad(root)


def is_axis_aligned_rect(quad, tol: float = QUAD_TOLERANCE) -> bool:
    """True when the quad is an axis-aligned rectangle to within `tol` canvas px — the
    degenerate case that must skip the warp entirely so straight-on slots keep rendering
    byte-for-byte as they do today (slot 03's a48d6b8c… / d99bb66f… regression gate)."""
    (tlx, tly), (trx, try_), (brx, bry), (blx, bly) = quad
    return (abs(tly - try_) <= tol and abs(bly - bry) <= tol
            and abs(tlx - blx) <= tol and abs(trx - brx) <= tol)


def needs_warp(quad) -> bool:
    return quad is not None and not is_axis_aligned_rect(quad)


def quad_is_degenerate(quad, *, eps_scale: float = 1e-9) -> bool:
    """No three of the four corners may be collinear (which also catches repeated corners) —
    the standard existence condition for a four-point homography. The epsilon is scaled by the
    quad's own extent so it means the same thing at unit-square and canvas scale."""
    extent = max(
        max(p[0] for p in quad) - min(p[0] for p in quad),
        max(p[1] for p in quad) - min(p[1] for p in quad),
        1.0,
    )
    eps = eps_scale * extent * extent
    for i in range(4):
        (ax, ay), (bx, by), (cx, cy) = quad[i], quad[(i + 1) % 4], quad[(i + 2) % 4]
        if abs((bx - ax) * (cy - ay) - (by - ay) * (cx - ax)) <= eps:
            return True
    return False


def _solve(matrix: list[list[float]], rhs: list[float]) -> list[float]:
    """Gaussian elimination with partial pivoting. Stdlib only (FR-9010-25) — numpy is exactly
    the kind of dependency this script exists without."""
    n = len(rhs)
    aug = [row[:] + [rhs[i]] for i, row in enumerate(matrix)]
    for col in range(n):
        pivot = max(range(col, n), key=lambda r: abs(aug[r][col]))
        if abs(aug[pivot][col]) < 1e-12:
            raise GeometryError("singular system: the four corners do not define a homography")
        aug[col], aug[pivot] = aug[pivot], aug[col]
        inv = 1.0 / aug[col][col]
        for row in range(n):
            if row == col:
                continue
            factor = aug[row][col] * inv
            if factor:
                for k in range(col, n + 1):
                    aug[row][k] -= factor * aug[col][k]
    return [aug[i][n] / aug[i][i] for i in range(n)]


def homography(src, dst) -> tuple[float, ...]:
    """The eight coefficients (a…h) of the projective map src -> dst:

        X = (a·x + b·y + c) / (g·x + h·y + 1)
        Y = (d·x + e·y + f) / (g·x + h·y + 1)

    ImageMagick recomputes the very same map from the four point pairs; solving it here buys
    two things a shell-out cannot: a degeneracy check that fails with a named error instead of
    a subprocess crash, and a directly unit-testable seam. `g == h == 0` means the map came out
    affine — i.e. no perspective, which is what a rectangle-to-parallelogram quad gives.
    """
    src, dst = list(src), list(dst)
    if len(src) != 4 or len(dst) != 4:
        raise GeometryError("a homography needs exactly four source and four destination points")
    for label, quad in (("source", src), ("destination", dst)):
        if quad_is_degenerate(quad):
            raise GeometryError(
                f"degenerate {label} quad: three of its four corners are collinear "
                f"(or two coincide), so no homography exists")
    matrix, rhs = [], []
    for (x, y), (bigx, bigy) in zip(src, dst):
        matrix.append([x, y, 1, 0, 0, 0, -x * bigx, -y * bigx])
        rhs.append(bigx)
        matrix.append([0, 0, 0, x, y, 1, -x * bigy, -y * bigy])
        rhs.append(bigy)
    return tuple(_solve(matrix, rhs))


def apply_homography(coeffs, x: float, y: float) -> tuple[float, float]:
    a, b, c, d, e, f, g, h = coeffs
    w = g * x + h * y + 1.0
    if abs(w) < 1e-12:
        raise GeometryError(f"point ({x}, {y}) maps to the horizon line of this homography")
    return ((a * x + b * y + c) / w, (d * x + e * y + f) / w)


def perspective_control_points(src_size, dst_quad) -> str:
    """The argument ImageMagick's `-distort Perspective` takes: four `sx,sy dx,dy` pairs. The
    source corners are the capture's own rectangle, clockwise from top-left — the homography
    maps the whole capture onto the quad, which is exactly the projective image a real screen
    of that content would have. `fit` is therefore already consumed by the warp."""
    w, h = src_size
    src = [(0, 0), (w, 0), (w, h), (0, h)]
    return "  ".join(
        f"{_fmt(sx)},{_fmt(sy)} {_fmt(dx)},{_fmt(dy)}"
        for (sx, sy), (dx, dy) in zip(src, dst_quad)
    )


def screen_quad_problems(label: str, quad, box, canvas) -> list[str]:
    """--check rules that only apply once a quad actually needs warping.

    A straight-on quad is exempt from the containment rules on purpose: slot 03's device body
    (and its screen rect) bleeds off the bottom edge BY DESIGN, because the template draws that
    device itself. A perspective quad is different in kind — it is the screen of a device that
    lives inside the photograph, so a corner off the canvas means the scene's crop is wrong and
    the frame is cut off. CUTOUT.md measured exactly that: under a centred cover fit the
    bottom-left corner lands at y = 2802.79 on a 2752-tall canvas.
    """
    problems: list[str] = []
    if not needs_warp(quad):
        return problems

    if quad_is_degenerate(quad):
        problems.append(
            f"{label}: degenerate screen quad {[(_fmt(x), _fmt(y)) for x, y in quad]} — three "
            "corners are collinear (or two coincide), so no perspective warp exists")
        return problems

    cw, ch = canvas
    for name, (x, y) in zip(CORNER_NAMES, quad):
        if not (-QUAD_TOLERANCE <= x <= cw + QUAD_TOLERANCE
                and -QUAD_TOLERANCE <= y <= ch + QUAD_TOLERANCE):
            problems.append(
                f"{label}: screen quad corner {name} ({_fmt(x)}, {_fmt(y)}) is off-canvas on a "
                f"{cw}x{ch} artboard — the scene's framing cuts the screen off. Reframe the "
                f'<image id="scene"> box (oversize it and offset y) instead of centring it.')

    if box is not None:
        bx, by, bw, bh = box
        for name, (x, y) in zip(CORNER_NAMES, quad):
            if not (bx - QUAD_TOLERANCE <= x <= bx + bw + QUAD_TOLERANCE
                    and by - QUAD_TOLERANCE <= y <= by + bh + QUAD_TOLERANCE):
                problems.append(
                    f"{label}: screen quad corner {name} ({_fmt(x)}, {_fmt(y)}) is outside the "
                    f'<image id="screenshot"> box ({_fmt(bx)}, {_fmt(by)}, {_fmt(bw)} x '
                    f"{_fmt(bh)}) — the pre-warped capture is rendered into that box, so the "
                    "warp would be silently clipped. Set the box to the quad's bounding box.")
    return problems


def template_geometry_problems(label: str, template: Path, slot: dict, *, canvas) -> list[str]:
    """Parses one template and reports what --check can only learn from its geometry. Every
    failure mode here is a report, never a traceback: a template is authored by hand."""
    try:
        root = ET.parse(template).getroot()
    except ET.ParseError as exc:
        return [f"{label}: cannot parse template {template}: {exc}"]
    except OSError as exc:  # pragma: no cover — existence was checked by the caller
        return [f"{label}: cannot read template {template}: {exc}"]
    try:
        quad = screen_quad_for(root, slot)
    except GeometryError as exc:
        return [f"{label}: {template.name}: {exc}"]
    if quad is None:
        return []
    element = by_id(root, "screenshot")
    try:
        box = image_box(element) if element is not None else None
    except (TypeError, ValueError):
        box = None
    return screen_quad_problems(label, quad, box, canvas)


def canvas_for(manifest, device: str):
    """(width, height) of a device class, or None when the manifest's own spec is unusable —
    `manifest_problems` has already named that defect, so geometry checks just stand down."""
    spec = (manifest.get("devices") or {}).get(device)
    if not isinstance(spec, dict):
        return None
    w, h = spec.get("width"), spec.get("height")
    if isinstance(w, int) and isinstance(h, int) and w > 0 and h > 0:
        return (w, h)
    return None


# --------------------------------------------------------------------------------------
# Path resolution (binding contract from the README/manifest).
# --------------------------------------------------------------------------------------

def expand_capture_root(raw: str) -> Path:
    """captureRoot needs os.path.expanduser (README) — captures live outside the repo. Also
    resolved to absolute: a relative captureRoot would otherwise be interpreted against
    whatever the process's cwd happens to be at each individual file access, which is fragile
    and inconsistent with everything else `main()` resolves up front."""
    return Path(raw).expanduser().resolve()


def resolve_output_dirs(out: str, work: str) -> tuple[Path, Path]:
    """Resolves `--out`/`--work` to absolute paths against the current working directory.

    Found by an independent review pass, not by the unit tests: `chrome_shot` hands its HTML
    path to `Path.as_uri()`, which raises `ValueError: relative path can't be expressed as a
    file URI` on anything relative. The defaults are already ROOT-based absolute paths, so the
    bare invocation never hit this — but a user typing a perfectly natural relative `--out
    tmp/x` from the repo root did. Resolving here, once, up front, means every downstream user
    of these two paths can assume "absolute" and never has to think about cwd again. Pure and
    Chrome-free, so it is directly unit-testable (SlotPaths/data_uri never touch a directory
    path's text, only file contents, so this has no effect on rendered pixels or determinism).
    """
    return Path(out).expanduser().resolve(), Path(work).expanduser().resolve()


def resolve_slot_paths(*, root: Path, capture_root: Path, device: str, locale: str,
                        slot: dict, scene_overrides: dict[str, Path]) -> SlotPaths:
    template = root / "Design" / "AppStore" / "templates" / device / slot["template"]
    override = scene_overrides.get(slot.get("id"))
    scene_name = slot.get("scene")
    if override is not None:
        scene = override
    elif scene_name:
        scene = root / "Design" / "AppStore" / "scenes" / device / scene_name
    else:
        # A sceneless UI slot (FR-9010-03 amendment): its template draws its own ground.
        scene = None
    capture_name = slot.get("capture")
    capture = capture_root / device / locale / capture_name if capture_name else None
    return SlotPaths(template=template, scene=scene, capture=capture)


def parse_scene_overrides(pairs: list[str]) -> dict[str, Path]:
    """--scene SLOT_ID=PATH (repeatable): use this file instead of Design/AppStore/scenes/...
    Exists because scene photographs don't exist yet and Design/ carries no placeholders by
    rule — this is the sanctioned way to render end-to-end before the photographs land."""
    overrides: dict[str, Path] = {}
    for pair in pairs or []:
        if "=" not in pair:
            raise InvocationError(f"--scene must be SLOT_ID=PATH, got {pair!r}")
        slot_id, _, raw_path = pair.partition("=")
        slot_id = slot_id.strip()
        if not slot_id:
            raise InvocationError(f"--scene missing SLOT_ID in {pair!r}")
        path = Path(raw_path).expanduser()
        if not path.is_file():
            raise InvocationError(f"--scene override for {slot_id!r} does not exist: {path}")
        # Resolved to absolute for the same reason as resolve_output_dirs: consistency, not a
        # correctness requirement here (data_uri() embeds file contents, never the path text).
        overrides[slot_id] = path.resolve()
    return overrides


def resolve_filters(manifest: dict, device_filter: list[str], locale_filter: list[str],
                     slot_filter: list[str]) -> tuple[list[str], list[str], list[dict]]:
    """Validates --device/--locale/--slot against the manifest; unknown values are invocation
    errors (exit 2), not --check findings. Slot order always follows the manifest's own array
    order — that order IS App Store display order (content.json's own comment) — regardless of
    the order --slot flags were given in."""
    all_devices = list(manifest.get("devices") or {})
    all_locales = list(manifest.get("locales") or [])
    all_slots = [s for s in (manifest.get("slots") or []) if isinstance(s, dict)]
    slot_by_id = {s.get("id"): s for s in all_slots}

    devices = device_filter or all_devices
    for d in device_filter:
        if d not in all_devices:
            raise InvocationError(f"unknown --device {d!r} (known: {sorted(all_devices)})")

    locales = locale_filter or all_locales
    for loc in locale_filter:
        if loc not in all_locales:
            raise InvocationError(f"unknown --locale {loc!r} (known: {sorted(all_locales)})")

    for sid in slot_filter:
        if sid not in slot_by_id:
            raise InvocationError(f"unknown --slot {sid!r} (known: {sorted(slot_by_id)})")
    if slot_filter:
        wanted = set(slot_filter)
        slots = [s for s in all_slots if s.get("id") in wanted]
    else:
        slots = all_slots

    return devices, locales, slots


# --------------------------------------------------------------------------------------
# Manifest validation (FR-9010-31 / SC-9010-03). Pure — no filesystem access — so it can run
# against any parsed manifest dict, real or a deliberately-broken test fixture.
# --------------------------------------------------------------------------------------

def _perspective_problems(label: str, value) -> list[str]:
    """FR-9010-23: a malformed perspective is a manifest error, caught here so --check finds
    it. No slot carries one today, so this path is otherwise unexercised end to end."""
    if not isinstance(value, list) or len(value) != 4:
        return [f"{label}: perspective must be an array of exactly 4 [x, y] points"]
    problems = []
    for i, point in enumerate(value):
        ok = (
            isinstance(point, list) and len(point) == 2
            and all(isinstance(n, (int, float)) and not isinstance(n, bool) for n in point)
        )
        if not ok:
            problems.append(f"{label}: perspective point {i} must be exactly [x, y], numeric")
    return problems


def manifest_problems(manifest) -> list[str]:
    """Structural/schema problems only — never touches the filesystem. See combo_problems for
    per (device, locale, slot) asset-existence checks."""
    if not isinstance(manifest, dict):
        return ["manifest: root must be a JSON object"]

    problems: list[str] = []

    locales = manifest.get("locales")
    if not isinstance(locales, list) or not locales or not all(isinstance(l, str) for l in locales):
        problems.append("manifest.locales: must be a non-empty array of strings")
        locales = []

    devices = manifest.get("devices")
    if not isinstance(devices, dict) or not devices:
        problems.append("manifest.devices: must be a non-empty object")
    else:
        for name, spec in devices.items():
            if (not isinstance(spec, dict) or not isinstance(spec.get("width"), int)
                    or not isinstance(spec.get("height"), int)):
                problems.append(f"manifest.devices.{name}: must declare integer width and height")

    slots = manifest.get("slots")
    if not isinstance(slots, list):
        problems.append("manifest.slots: must be an array")
        return problems

    seen_ids: set[str] = set()
    for idx, slot in enumerate(slots):
        label = f"slots[{idx}]"
        if not isinstance(slot, dict):
            problems.append(f"{label}: not an object")
            continue
        sid = slot.get("id")
        if isinstance(sid, str) and sid:
            label = f"slot {sid!r}"

        for key in REQUIRED_SLOT_KEYS:
            if key not in slot:
                problems.append(f"{label}: missing required key {key!r}")

        # `scene` is required for, and only for, a `scene` slot. Omitting it on a UI slot is the
        # archetype working as intended; omitting it on a photo slot is a slot that would render
        # onto bare ground, which is precisely the defect this pair of rules exists to catch.
        slot_type = slot.get("type")
        if slot_type is not None and slot_type not in SLOT_TYPES:
            problems.append(
                f"{label}: type {slot_type!r} is not one of {sorted(SLOT_TYPES)}")
        elif slot_type == "scene" and "scene" not in slot:
            problems.append(f"{label}: missing required key 'scene' for a slot of type 'scene'")

        # Presence is not enough. A key whose value is the wrong TYPE used to sail through
        # --check and blow up later: `id: null` rendered to a file called `None.png`, a
        # non-string `template`/`scene`/`capture` raised a raw TypeError out of path building
        # (so --check printed nothing at all), and a non-string headline line passed --check
        # clean and then killed the render on ET serialisation. A green --check is exactly
        # what a person trusts before a long Chrome batch, so it validates types too.
        if "id" in slot and not (isinstance(sid, str) and sid):
            problems.append(f"{label}: id must be a non-empty string, got {sid!r}")

        for key in ("template", "scene", "capture"):
            if key in slot and not (isinstance(slot[key], str) and slot[key]):
                problems.append(f"{label}: {key} must be a non-empty string, got {slot[key]!r}")

        if isinstance(sid, str) and sid:
            if sid in seen_ids:
                problems.append(f"slot {sid!r}: duplicate slot id")
            seen_ids.add(sid)

        if "fit" in slot and slot["fit"] not in PAR:
            problems.append(f"{label}: fit {slot['fit']!r} is not one of {sorted(PAR)}")

        if "captureCrop" in slot:
            problems.extend(capture_crop_problems(label, slot["captureCrop"]))

        headline = slot.get("headline")
        if isinstance(headline, dict):
            for loc in locales:
                lines = headline.get(loc)
                if lines is None:
                    problems.append(f"{label}: headline missing locale {loc!r}")
                elif not isinstance(lines, list) or len(lines) == 0:
                    problems.append(f"{label}: headline[{loc!r}] must be a non-empty array of lines")
                elif not all(isinstance(line, str) for line in lines):
                    problems.append(
                        f"{label}: headline[{loc!r}] must contain only strings, got {lines!r}")
        elif "headline" in slot:
            problems.append(f"{label}: headline must be an object keyed by locale")

        # `subline` (the optional second text block) is per-slot optional but, once present,
        # required in EVERY locale: a slot carrying it only in `de` renders fine in English and
        # then dies mid-run on the German pass, which is the expensive way to find a typo.
        subline = slot.get("subline")
        if isinstance(subline, dict):
            for loc in locales:
                lines = subline.get(loc)
                if lines is None:
                    problems.append(f"{label}: subline missing locale {loc!r}")
                elif not isinstance(lines, list) or len(lines) == 0:
                    problems.append(f"{label}: subline[{loc!r}] must be a non-empty array of lines")
                elif not all(isinstance(line, str) for line in lines):
                    problems.append(
                        f"{label}: subline[{loc!r}] must contain only strings, got {lines!r}")
        elif "subline" in slot:
            problems.append(f"{label}: subline must be an object keyed by locale")

        if "perspective" in slot:
            problems.extend(_perspective_problems(label, slot["perspective"]))

    return problems


def slot_paths_resolvable(slot) -> bool:
    """Whether `resolve_slot_paths` can run on this slot at all. A slot whose id or asset
    references are not non-empty strings cannot be turned into paths — `Path / 7` raises
    TypeError — and `manifest_problems` has already named that defect, so the per-combo asset
    pass skips it instead of dying and printing nothing (which is what it used to do)."""
    if not isinstance(slot, dict):
        return False
    if not all(isinstance(slot.get(key), str) and slot.get(key)
               for key in ("id", "template", "capture")):
        return False
    # `scene` may be absent (a sceneless UI slot). Present-but-not-a-usable-string is still
    # unresolvable — omitted and wrong are different things, and only the first one is legal.
    return "scene" not in slot or bool(isinstance(slot["scene"], str) and slot["scene"])


def combo_problems(device: str, locale: str, slot: dict, paths: SlotPaths,
                    *, canvas=None) -> list[str]:
    """Asset-existence checks for one (device, locale, slot) combination, plus — when the
    device's canvas size is known — the template's own screen-quad geometry. The geometry pass
    is here rather than in `manifest_problems` because it needs the template FILE, which is a
    per-combination fact (`templates/<device>/<slot.template>`) and not a manifest one."""
    sid = slot.get("id", "?")
    label = f"slot {sid!r} device={device} locale={locale}"
    problems = []
    if not paths.template.is_file():
        problems.append(f"{label}: missing template {paths.template}")
    elif canvas is not None:
        problems.extend(template_geometry_problems(label, paths.template, slot, canvas=canvas))
    if paths.scene is not None and not paths.scene.is_file():
        problems.append(f"{label}: missing scene {paths.scene}")
    if paths.capture is not None and not paths.capture.is_file():
        problems.append(f"{label}: missing capture {paths.capture}")
    return problems


# --------------------------------------------------------------------------------------
# PNG facts (FR-9010-29) — read straight from the file's own bytes, never from a tool's
# opinion (e.g. `magick identify`'s stdout parsing, which could itself be lying).
# --------------------------------------------------------------------------------------

PNG_SIGNATURE = b"\x89PNG\r\n\x1a\n"


def parse_png(data: bytes) -> dict:
    if data[:8] != PNG_SIGNATURE:
        raise ValueError("not a PNG file (bad signature)")
    width, height, bit_depth, color_type = struct.unpack(">IIBB", data[16:26])
    i, chunks = 8, []
    while i < len(data):
        if i + 8 > len(data):
            break
        length = struct.unpack(">I", data[i:i + 4])[0]
        tag = data[i + 4:i + 8].decode("latin1")
        if tag != "IDAT":
            chunks.append(tag)
        i += 12 + length
        if tag == "IEND":
            break
    return {"width": width, "height": height, "bit_depth": bit_depth,
            "color_type": color_type, "chunks": chunks}


def png_facts(path: Path) -> dict:
    data = path.read_bytes()
    facts = parse_png(data)
    facts["sha256"] = hashlib.sha256(data).hexdigest()
    return facts


def add_srgb_chunk(data: bytes, *, rendering_intent: int = 0) -> bytes:
    """Hand-writes the 1-byte sRGB chunk right after IHDR. See the header's "Determinism vs.
    metadata" trap for why this exists instead of `magick -profile <sRGB.icc>`. Rendering
    intent 0 matches the value the screenshot rig's own captures carry, so the shipped set
    stays internally consistent."""
    if data[:8] != PNG_SIGNATURE:
        raise ValueError("not a PNG file (bad signature)")
    ihdr_len = struct.unpack(">I", data[8:12])[0]
    end_of_ihdr = 8 + 12 + ihdr_len
    tag, payload = b"sRGB", bytes([rendering_intent])
    chunk = (
        struct.pack(">I", len(payload)) + tag + payload
        + struct.pack(">I", zlib.crc32(tag + payload) & 0xFFFFFFFF)
    )
    return data[:end_of_ihdr] + chunk + data[end_of_ihdr:]


# --------------------------------------------------------------------------------------
# External tools (FR-9010-26). Not covered by unit tests — Chrome/ImageMagick are never
# required to run `python3 -m unittest discover ...` per the brief.
# --------------------------------------------------------------------------------------

def chrome_shot(html: Path, out: Path, width: int, height: int, profile: Path) -> None:
    cmd = [
        CHROME, "--headless=new", "--disable-gpu", "--no-sandbox", "--no-first-run",
        "--no-default-browser-check", "--disable-crash-reporter", "--disable-extensions",
        f"--user-data-dir={profile}", "--hide-scrollbars",
        "--force-device-scale-factor=1", f"--window-size={width},{height}",
        f"--screenshot={out}", html.as_uri(),
    ]
    out.unlink(missing_ok=True)
    log = out.with_suffix(".chrome.log")
    try:
        with log.open("wb") as fh:
            proc = subprocess.Popen(cmd, stdout=fh, stderr=fh, start_new_session=True)
            try:
                deadline, stable, last = time.monotonic() + 120, 0, -1
                while time.monotonic() < deadline:
                    if proc.poll() is not None:
                        break
                    size = out.stat().st_size if out.exists() else -1
                    stable = stable + 1 if size > 0 and size == last else 0
                    last = size
                    if stable >= 3:
                        break
                    time.sleep(0.25)
            finally:
                if proc.poll() is None:
                    os.killpg(os.getpgid(proc.pid), signal.SIGKILL)
                    proc.wait(timeout=20)
    except FileNotFoundError as exc:
        raise ExternalToolError(f"Chrome not found at {CHROME}: {exc}") from exc
    if not out.exists():
        raise ExternalToolError(f"chrome produced no screenshot; see {log}")


def flatten(src: Path, dst: Path) -> None:
    """FR-9010-29 (no alpha, sRGB) without breaking FR-9010-30 (byte-identical repeats)."""
    try:
        subprocess.run([
            "magick", str(src), "-background", "black", "-alpha", "remove", "-alpha", "off",
            "-colorspace", "sRGB", "-strip", f"PNG24:{dst}",
        ], check=True, capture_output=True)
    except (subprocess.CalledProcessError, FileNotFoundError) as exc:
        raise ExternalToolError(f"ImageMagick failed flattening {src}: {exc}") from exc
    dst.write_bytes(add_srgb_chunk(dst.read_bytes()))


CROP_KEYS = ("x", "y", "width", "height")


def capture_crop_problems(label: str, crop) -> list[str]:
    """Validate an optional `captureCrop` rect. Fractions of the capture, not pixels.

    Fractions deliberately: capture size varies by rig (1488x2266 on an iPad mini vs 2064x2752
    on a 13-inch), so a pixel rect authored against one device silently mis-crops on another.

    Unknown keys are an error rather than ignored — a `hieght` typo would otherwise leave the
    slot rendering full-frame while --check reported everything clean, which is the same
    "green means nothing happened" failure class this script already guards elsewhere.
    """
    if not isinstance(crop, dict):
        return [f"{label}: captureCrop must be an object with {list(CROP_KEYS)}, got {crop!r}"]

    problems = []
    unknown = sorted(set(crop) - set(CROP_KEYS))
    if unknown:
        problems.append(f"{label}: captureCrop has unknown key(s) {unknown}; "
                        f"expected exactly {list(CROP_KEYS)}")
    for key in CROP_KEYS:
        if key not in crop:
            problems.append(f"{label}: captureCrop is missing required key {key!r}")
            continue
        value = crop[key]
        # bool is an int subclass; `true` must not read as 1.
        if isinstance(value, bool) or not isinstance(value, (int, float)):
            problems.append(
                f"{label}: captureCrop.{key} must be a number in 0..1, got {value!r}")
            continue
        if key in ("x", "y") and not 0 <= value <= 1:
            problems.append(f"{label}: captureCrop.{key} must be in 0..1, got {value!r}")
        if key in ("width", "height") and not 0 < value <= 1:
            problems.append(
                f"{label}: captureCrop.{key} must be greater than 0 and at most 1, got {value!r}")

    if problems:
        return problems

    if crop["x"] + crop["width"] > 1:
        problems.append(f"{label}: captureCrop x+width is {crop['x'] + crop['width']}, "
                        "which runs past the right edge of the capture")
    if crop["y"] + crop["height"] > 1:
        problems.append(f"{label}: captureCrop y+height is {crop['y'] + crop['height']}, "
                        "which runs past the bottom edge of the capture")
    return problems


def crop_capture(capture: Path, crop: dict, *, work_dir: Path, tag: str) -> Path:
    """Zoom a capture into its own content before it is composited.

    The app uses a centred content column (FR-9000-17), so a full-screen iPad capture carries
    large dead margins. Compositing the whole frame reproduces that emptiness faithfully, and at
    App Store carousel width the UI slots then read as black tiles. Cropping to the content
    roughly doubles apparent text size with no new material and no re-capture.

    `+repage` is load-bearing, not decoration: without it the cropped PNG keeps the original
    canvas geometry, and `warp_capture_perspective` would then read the FULL frame back out of
    the header and map that onto the quad — silently undoing the zoom while looking like it
    worked. `-strip` keeps the intermediate byte-stable so FR-9010-30 still holds.
    """
    facts = parse_png(capture.read_bytes())
    cw, ch = facts["width"], facts["height"]
    x = min(round(crop["x"] * cw), cw - 1)
    y = min(round(crop["y"] * ch), ch - 1)
    w = max(1, min(round(crop["width"] * cw), cw - x))
    h = max(1, min(round(crop["height"] * ch), ch - y))
    dst = work_dir / f"crop-{tag}.png"
    try:
        subprocess.run([
            "magick", str(capture), "-crop", f"{w}x{h}+{x}+{y}", "+repage",
            "-strip", str(dst),
        ], check=True, capture_output=True)
    except (subprocess.CalledProcessError, FileNotFoundError) as exc:
        raise ExternalToolError(f"ImageMagick failed cropping {capture}: {exc}") from exc
    return dst


def prepare_capture(capture: Path, *, crop, quad, box, work_dir: Path, tag: str
                     ) -> tuple[Path, bool]:
    """Crop then (only if the quad demands it) warp. Returns the capture to embed, and whether
    it was warped — `substitute` needs that to drop `preserveAspectRatio`.

    Order is load-bearing. The homography maps the capture's OWN rectangle onto the screen quad,
    so cropping AFTER the warp would cut the already-placed screen instead of zooming it.

    A slot with no `captureCrop` and a straight-on quad passes through untouched, so every
    existing template keeps its byte-identical output (FR-9010-30).
    """
    src = capture
    if crop is not None:
        src = crop_capture(src, crop, work_dir=work_dir, tag=tag)
    if needs_warp(quad):
        return warp_capture_perspective(src, quad, box=box, work_dir=work_dir, tag=tag), True
    return src, False


def warp_capture_perspective(capture: Path, quad, *, box, work_dir: Path, tag: str) -> Path:
    """FR-9010-23/26: pre-warps the CAPTURE (never the scene) onto the screen quad.

    The four source points are the capture's own rectangle; the four destination points are the
    quad, in absolute canvas coordinates. `distort:viewport` is what lets those stay absolute:
    it fixes the output raster to the `screenshot` <image> box's own region of the canvas, so
    the resulting bitmap drops straight into that box at `preserveAspectRatio="none"` with no
    coordinate translation anywhere. Verified against the installed ImageMagick 7.1.2:
    `-list distort` names `Perspective`, and `-matte` warns "option has been replaced, use
    -alpha Set" — hence `-alpha set`. `-strip` keeps the intermediate byte-stable, so a repeat
    run is identical all the way down the pipeline and not just at the flattened output.

    The homography is solved here first, purely to fail with a named GeometryError on a
    degenerate quad instead of handing ImageMagick a system it cannot solve either.
    """
    facts = parse_png(capture.read_bytes())
    w, h = facts["width"], facts["height"]
    homography([(0, 0), (w, 0), (w, h), (0, h)], quad)
    pairs = perspective_control_points((w, h), quad)
    bx, by, bw, bh = box
    viewport = f"{max(1, round(bw))}x{max(1, round(bh))}+{round(bx)}+{round(by)}"
    dst = work_dir / f"warp-{tag}.png"
    try:
        subprocess.run([
            "magick", str(capture), "-alpha", "set", "-virtual-pixel", "transparent",
            "-background", "none", "-set", "option:distort:viewport", viewport,
            "-distort", "Perspective", pairs, "-strip", str(dst),
        ], check=True, capture_output=True)
    except (subprocess.CalledProcessError, FileNotFoundError) as exc:
        raise ExternalToolError(f"ImageMagick perspective warp failed for {capture}: {exc}") from exc
    return dst


# --------------------------------------------------------------------------------------
# Render pipeline for one (device, locale, slot) combination.
# --------------------------------------------------------------------------------------

def render_combo(*, device: str, locale: str, slot: dict, paths: SlotPaths,
                  device_spec: dict, out_dir: Path, work_dir: Path) -> Path:
    tag = f"{device}-{locale}-{slot['id']}"
    work_dir.mkdir(parents=True, exist_ok=True)

    tree = ET.parse(paths.template)
    tree_root = tree.getroot()

    # Perspective decision (see the screen-quad section): the quad comes out of the template's
    # own clipPath unless the slot overrides it, and an axis-aligned quad skips ImageMagick
    # entirely so every straight-on template keeps its byte-identical output.
    capture_for_embed, warped = paths.capture, False
    screenshot_el = by_id(tree_root, "screenshot")
    if capture_for_embed is not None and screenshot_el is not None:
        capture_for_embed, warped = prepare_capture(
            capture_for_embed,
            crop=slot.get("captureCrop"),
            quad=screen_quad_for(tree_root, slot),
            box=image_box(screenshot_el),
            work_dir=work_dir, tag=tag,
        )

    scene_uri = data_uri(paths.scene) if paths.scene is not None else None
    screenshot_uri = data_uri(capture_for_embed) if capture_for_embed is not None else None
    lines = slot["headline"][locale]
    subline = slot.get("subline") or {}
    substitute(tree_root, scene_uri=scene_uri, screenshot_uri=screenshot_uri,
               fit=slot["fit"], lines=lines, warped=warped,
               subline_lines=subline.get(locale))
    svg_text = ET.tostring(tree_root, encoding="unicode")

    html_path = work_dir / f"{tag}.html"
    html_path.write_text(HTML.format(svg=svg_text), encoding="utf-8")

    profile = work_dir / f"chrome-profile-{tag}"
    shutil.rmtree(profile, ignore_errors=True)
    raw_path = work_dir / f"{tag}-raw.png"
    chrome_shot(html_path, raw_path, device_spec["width"], device_spec["height"], profile)

    dst = out_dir / device / locale / f"{slot['id']}.png"
    dst.parent.mkdir(parents=True, exist_ok=True)
    flatten(raw_path, dst)

    facts = png_facts(dst)
    issues = []
    if facts["width"] != device_spec["width"] or facts["height"] != device_spec["height"]:
        issues.append(f"size {facts['width']}x{facts['height']} != "
                       f"expected {device_spec['width']}x{device_spec['height']}")
    if facts["color_type"] != 2:
        issues.append(f"color_type {facts['color_type']} != 2 (truecolour, no alpha)")
    if "sRGB" not in facts["chunks"]:
        issues.append("sRGB chunk missing")
    if issues:
        dst.unlink(missing_ok=True)
        raise RenderAssertionError(f"{tag}: " + "; ".join(issues))
    return dst


# --------------------------------------------------------------------------------------
# CLI
# --------------------------------------------------------------------------------------

def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    parser.add_argument("--check", action="store_true",
                         help="validate the manifest and every referenced asset; render nothing")
    parser.add_argument("--manifest", default=str(ROOT / "Design/AppStore/content.json"))
    parser.add_argument("--device", action="append", default=[],
                         help="repeatable filter; default is every declared device class")
    parser.add_argument("--locale", action="append", default=[],
                         help="repeatable filter; default is every declared locale")
    parser.add_argument("--slot", action="append", default=[],
                         help="repeatable filter by slot id; default is every slot")
    parser.add_argument("--capture-root", default=None,
                         help="override the manifest's captureRoot (captures live outside the repo)")
    parser.add_argument("--scene", action="append", default=[], metavar="SLOT_ID=PATH",
                         help="repeatable dev override; use PATH as SLOT_ID's scene photograph")
    parser.add_argument("--out", default=str(ROOT / "tmp/store-screenshots"))
    parser.add_argument("--work", default=str(ROOT / "tmp/store-screenshots-work"))
    parser.add_argument("--list", action="store_true",
                         help="print resolved (device, locale, slot, template, scene, capture) "
                              "tuples and exit; touches no external tool")
    return parser


def main(argv: list[str] | None = None, *, root: Path = ROOT) -> int:
    """`root` is a testability seam, not a CLI flag: the README's path contract fixes
    templates/scenes under `Design/AppStore/` (only `captureRoot` and per-slot `--scene` are
    meant to be overridable), so unit tests inject a fixture tree here instead of writing into
    the real `Design/` (out of scope, FR-9010-28). Production callers never pass it."""
    args = build_parser().parse_args(argv)

    manifest_path = Path(args.manifest).expanduser().resolve()
    try:
        raw_text = manifest_path.read_text(encoding="utf-8")
    except OSError as exc:
        print(f"error: cannot read manifest {manifest_path}: {exc}", file=sys.stderr)
        return 2
    try:
        manifest = json.loads(raw_text)
    except json.JSONDecodeError as exc:
        print(f"error: malformed JSON in {manifest_path}: {exc}", file=sys.stderr)
        return 2

    try:
        scene_overrides = parse_scene_overrides(args.scene)
        devices, locales, slots = resolve_filters(manifest, args.device, args.locale, args.slot)
    except InvocationError as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 2

    schema_problems = manifest_problems(manifest)

    capture_root = (
        Path(args.capture_root).expanduser().resolve() if args.capture_root
        else expand_capture_root(str(manifest.get("captureRoot", "")))
    )

    combos = [(d, l, s) for d in devices for l in locales for s in slots]
    combo_paths: dict[tuple[str, str, str], SlotPaths] = {}
    asset_problems: list[str] = []
    for d, l, s in combos:
        if not slot_paths_resolvable(s):
            continue  # already reported by manifest_problems; paths cannot be built at all
        paths = resolve_slot_paths(root=root, capture_root=capture_root, device=d, locale=l,
                                    slot=s, scene_overrides=scene_overrides)
        combo_paths[(d, l, s.get("id"))] = paths
        asset_problems.extend(combo_problems(d, l, s, paths, canvas=canvas_for(manifest, d)))

    if args.list:
        for d, l, s in combos:
            paths = combo_paths.get((d, l, s.get("id")))
            if paths is None:
                print(f"{d}\t{l}\t{s.get('id')!r}\tunresolvable — run --check")
                continue
            print(f"{d}\t{l}\t{s.get('id')}\t{paths.template}\t{paths.scene}\t{paths.capture}")
        return 0

    all_problems = schema_problems + asset_problems

    if args.check:
        if all_problems:
            for p in all_problems:
                print(f"check: {p}")
            print(f"check: {len(all_problems)} problem(s) found across "
                  f"{len(combos)} combination(s)", file=sys.stderr)
            return 1
        print(f"check: ok — {len(combos)} combination(s), no problems found")
        return 0

    # Render mode. Schema problems make the manifest untrustworthy as a whole: refuse to
    # render anything until it is fixed, rather than guessing which slots are "probably fine".
    if schema_problems:
        for p in schema_problems:
            print(f"error: {p}", file=sys.stderr)
        print("error: manifest has schema problems; rendering nothing until they are fixed",
              file=sys.stderr)
        return 1

    out_dir, work_dir = resolve_output_dirs(args.out, args.work)
    devices_spec = manifest["devices"]

    rendered: list[Path] = []
    skipped: list[str] = []
    tool_failure = False
    for d, l, s in combos:
        sid = s.get("id")
        paths = combo_paths[(d, l, sid)]
        problems = combo_problems(d, l, s, paths, canvas=canvas_for(manifest, d))
        if problems:
            for p in problems:
                print(f"skip: {p}", file=sys.stderr)
            skipped.append(f"{d}/{l}/{sid}")
            continue
        try:
            dst = render_combo(device=d, locale=l, slot=s, paths=paths,
                                device_spec=devices_spec[d], out_dir=out_dir, work_dir=work_dir)
        except (RenderAssertionError, GeometryError) as exc:
            print(f"error: {exc}", file=sys.stderr)
            skipped.append(f"{d}/{l}/{sid}")
            continue
        except ExternalToolError as exc:
            print(f"error: {exc}", file=sys.stderr)
            skipped.append(f"{d}/{l}/{sid}")
            tool_failure = True
            continue
        print(f"rendered: {dst}")
        rendered.append(dst)

    print(f"summary: {len(rendered)} rendered, {len(skipped)} skipped, "
          f"{len(combos)} requested", file=sys.stderr)

    if tool_failure:
        return 3
    return 0 if rendered and not skipped else 1


if __name__ == "__main__":
    sys.exit(main())
