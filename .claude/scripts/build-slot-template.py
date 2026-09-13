#!/usr/bin/env python3
"""build-slot-template.py — turn a measured scene cut-out into a store slot SVG template.

The third step of the scene pipeline, and until now the missing one:

    generate-scene.py      paint the room, key the screen out to alpha
    measure-scene-cutout.py  measure the cut-out, solve the crop onto the store canvas
    build-slot-template.py   >>> write the template that geometry implies
    render-store-screenshots.py  fill it with a capture and the manifest's copy, render to PNG

Steps one, two and four were tools; step three was a session scratchpad
(`tmp/story-low/build-preview-slots.py`), which the 2026-09-12 handover flagged as the one piece
of the loop that would not survive its own session. It did not. This is that script rewritten
with the geometry it was quietly getting wrong fixed, and with tests.

What it does NOT do, on purpose: it never writes a word of store copy. The two text elements
ship placeholder tspans whose only job is to carry the font, the position and the line spacing;
`render-store-screenshots.py` rebuilds their children from `content.json`, which is the single
source of the copy (FR-9010-20).

Zero third-party Python (FR-9010-25) — it shells out to `measure-scene-cutout.py` for the
measurement and does string formatting for the rest.

The one geometry trap worth naming: the scene `<image>` must be offset by the NEGATED crop on
BOTH axes. The scratchpad version hardcoded `x="0"` and got away with it because a plain cover
fit of a 2064-wide scene onto a 2064-wide canvas has zero horizontal overflow to offset. Zooming
in (`--zoom`, the lever that actually brings the device closer) crops horizontally as well, and
a hardcoded zero then slides the room sideways out from under its own screen cut-out.

    build-slot-template.py <scene.png> --slot 02 --out templates/ipad/slot-02.svg \\
        [--device ipad] [--zoom max] [--min-footroom 500] [--subline-lines 2]

Exit codes: 0 clean · 1 the template was written but a text band is tighter than the type
needs · 2 bad invocation · 3 measure-scene-cutout.py failed.
"""

from __future__ import annotations

import argparse
import json
import subprocess
import sys
from pathlib import Path

TOOL = "build-slot-template"
MEASURE = Path(__file__).resolve().parent / "measure-scene-cutout.py"

# ---- The approved treatment (Jan, 2026-09-12: "text bottom AND top", "light, apple style") ----
# These are a look that was reviewed and accepted, so they are constants rather than flags.
#
# Both blocks are anchored from the canvas edge they sit against, at the same distance as the
# side margin: the headline's CAP TOP sits MARGIN_X from the top edge, the subline's LAST
# baseline sits so its ink clears the bottom edge by MARGIN_X. One number, four margins, and
# the type occupies the same rectangle on every tile in the set.
#
# 2026-09-13, after Jan's "text placement is way off": the old numbers anchored the headline at
# baseline 300 (cap top 209, 69 px lower than the side margin) and the subline at a FIRST-line
# baseline 180 px off the bottom — so a two-line subline grew DOWN to 68 px off the edge, the
# exact trap Design/AppStore/README.md names, and a three-line one ran off the canvas. Measured
# on the round-1 render: top margin 209, bottom margin 68, against a 140 px side margin.
MARGIN_X = 140
HEADLINE_SIZE = 126
HEADLINE_WEIGHT = "300"          # SF Pro Display Light. The 700 bold this replaced was "a disgrace".
HEADLINE_TRACKING = -1
HEADLINE_LINE_HEIGHT = "1.18em"
# Measured in this repo's own render (Chrome 151, SF Pro Display Light): the cap top of a line
# sits 0.722 x font-size above its baseline, and a descender reaches 0.16 x below it.
HEADLINE_CAP_RATIO = 0.722
SUBLINE_DESCENDER_RATIO = 0.16
HEADLINE_BASELINE = round(MARGIN_X + HEADLINE_CAP_RATIO * HEADLINE_SIZE)   # 231
SUBLINE_SIZE = 76
SUBLINE_WEIGHT = "400"
SUBLINE_OPACITY = "0.92"
SUBLINE_LINE_HEIGHT_EM = 1.3
SUBLINE_LINE_HEIGHT = f"{SUBLINE_LINE_HEIGHT_EM}em"
# Distance from the canvas bottom to the LAST subline baseline, so that the lowest ink lands
# MARGIN_X above the edge however many lines the manifest supplies.
SUBLINE_LAST_BASELINE_FROM_BOTTOM = round(MARGIN_X + SUBLINE_DESCENDER_RATIO * SUBLINE_SIZE)  # 152
DEFAULT_SUBLINE_LINES = 2
TOP_SCRIM_HEIGHT = 780
BOTTOM_SCRIM_HEIGHT = 760
FONT_STACK = "system-ui, BlinkMacSystemFont, sans-serif"

# What each band actually needs, in canvas px, measured rather than guessed.
#
# A two-line headline's ink runs from MARGIN_X down to ~401; a two-line subline's ink is ~166 px
# tall and ends MARGIN_X above the bottom edge, so it starts ~306 px up from the edge. The
# measurement these thresholds are compared against is to the SCREEN QUAD, but the thing type
# must not touch is the DEVICE — and its bezel stands 40-155 px proud of the screen on the six
# story scenes (measured off the round-1 renders, 2026-09-13). So each threshold carries a
# 100 px bezel allowance plus ~60 px of air. It is a floor, not a guarantee: a close-up scene
# with a fat bezel can pass this and still print type on the aluminium. Look at the render.
#
# The old DEFAULT_HEADROOM_NEEDED of 400 was the number this treatment was NOT built against:
# the headline's own ink already reached 470, so "400 is enough" silently licensed three of the
# six tiles to set their second line across the iPad's top bezel.
BEZEL_ALLOWANCE = 100.0
BAND_AIR = 60.0
DEFAULT_HEADROOM_NEEDED = 560.0
DEFAULT_FOOTROOM_NEEDED = 470.0

# ---- The "AI generated" disclosure mark (Jan, 2026-09-13; quieted 2026-09-13 pm) ----
# The room photograph behind the device is AI-generated; only the capture on the iPad's screen
# is a real app screenshot. This is that disclosure: a small grey pill, bottom-RIGHT, carrying the
# four-point sparkle glyph the platforms (Meta/TikTok/YouTube) use for "AI-generated" labels —
# never an emoji (font fallback would break it) and never the Content Credentials "CR" pin, which
# is reserved for images that actually carry C2PA credentials.
#
# Jan's review of the first pass ("shout it"): bottom-left, one line, 36px, 85% white on 50%
# grey — too loud. Moved to bottom-right, two lines, smaller type, quieter fills:
#   "the 'ai generated' mark: two lines. bottom right. less intrusive. no need to shout it,
#    just to flag as low as possible."
#
# Geometry is now anchored from the canvas's bottom-right CORNER, not from the subline's zone —
# the pill's right edge sits AI_MARK_RIGHT_INSET from the right edge (tighter than the 140px
# text margin, since it no longer has to clear text of its own width) and its bottom edge sits
# AI_MARK_BOTTOM_INSET from the bottom edge. This is deliberately independent of `subline_lines`:
# the subline is left-anchored at MARGIN_X and never reaches the right margin (README: no line is
# wider than canvas minus its side margins), so a mark anchored to the right corner cannot share
# an x-range with it regardless of copy length. The non-overlap guarantee the tests assert is
# vertical instead: the subline's last-line ink bottom sits SUBLINE_INK_BOTTOM_FROM_EDGE above the
# canvas edge, invariant to `subline_lines` (the subline is anchored on its LAST line for exactly
# this reason — see the subline comment above), and the pill is short enough (64.8px against the
# ~99.8px of slack available) that its own top edge still lands BELOW that ink bottom. So the two
# never occupy the same row of pixels, for any copy length. Kept from the first pass because it is
# still correct and still free: SUBLINE_INK_BOTTOM_FROM_EDGE is unchanged.
SUBLINE_INK_BOTTOM_FROM_EDGE = SUBLINE_LAST_BASELINE_FROM_BOTTOM - SUBLINE_DESCENDER_RATIO * SUBLINE_SIZE  # ~139.84
AI_MARK_RIGHT_INSET = 60.0          # pill's right edge from the canvas right edge
AI_MARK_BOTTOM_INSET = 40.0         # pill's bottom edge from the canvas bottom edge
AI_MARK_FONT_SIZE = 26.0            # down from 36 — "less intrusive"
AI_MARK_FONT_WEIGHT = "500"
AI_MARK_TRACKING = 0.4
AI_MARK_LINE_HEIGHT_EM = 1.15
AI_MARK_FILL = "#57606F"           # same neutral grey, a slight cool/blue bias — not pure #808080
AI_MARK_FILL_OPACITY = "0.38"      # down from 0.5 — quieter pill
AI_MARK_LINE1_TEXT = "AI"          # line 1: glyph + "AI"
AI_MARK_LINE2_TEXT = "generated"   # line 2: "generated", aligned under "AI"
AI_MARK_TEXT_OPACITY = "0.7"       # down from 0.85 — both the glyph and the label use this white
AI_MARK_PAD_X = 10.0                # down from 18/20 — horizontal pill padding
AI_MARK_PAD_Y = 6.0                 # vertical pill padding
AI_MARK_CORNER_RADIUS = 14.0        # down from 28 (was height/2, a full stadium pill)
# Cap-height and descender ratios reused from the headline/subline measurement (see above) so the
# glyph scales with the mark's own type instead of carrying a second hand-picked number.
AI_MARK_GLYPH_SIZE = round(HEADLINE_CAP_RATIO * AI_MARK_FONT_SIZE, 2)  # ~18.77
AI_MARK_GLYPH_GAP = round(AI_MARK_GLYPH_SIZE / 2, 2)                   # roughly half the glyph width
AI_MARK_GLYPH_WAIST = 0.33         # how far the concave sides are pulled toward the glyph centre
# A static template cannot measure real glyph widths (that needs a browser, see
# tmp/story-d/measure-text.py) — these are deliberately generous per-line estimates at 26px SF
# Pro Medium so the pill background does not undershoot the live text. Verified against the
# actual render; widen whichever one if a future label text overflows it.
AI_MARK_LINE1_TEXT_WIDTH_ESTIMATE = 34.0    # "AI"
AI_MARK_LINE2_TEXT_WIDTH_ESTIMATE = 150.0   # "generated"


class InvocationError(Exception):
    """Bad CLI usage (exit code 2)."""


class MeasurementError(RuntimeError):
    """measure-scene-cutout.py could not measure this scene (exit code 3)."""


def _fmt(value: float) -> str:
    return f"{float(value):.2f}"


def measure_scene(scene: Path, *, device: str, zoom: str, min_footroom: float) -> dict:
    """Run the measurement tool and parse its JSON. Exit code 1 is a WARNING verdict — the
    cut-out is usable, the warnings are about hand-cut artefacts that are benign on generated
    scenes (handover, 2026-09-12) — so only 2 and 3 are fatal here."""
    argv = [sys.executable, str(MEASURE), str(scene), "--json", "--device", device,
            "--zoom", zoom, "--min-footroom", str(min_footroom)]
    try:
        done = subprocess.run(argv, capture_output=True, text=True)
    except OSError as exc:
        raise MeasurementError(f"cannot run {MEASURE}: {exc}") from exc
    if done.returncode >= 2:
        raise MeasurementError(
            f"measure-scene-cutout.py exited {done.returncode} on {scene}: "
            f"{(done.stderr or done.stdout).strip()}")
    try:
        return json.loads(done.stdout)
    except json.JSONDecodeError as exc:
        raise MeasurementError(f"measure-scene-cutout.py did not return JSON: {exc}") from exc


def band_warnings(measurement: dict, *, headroom_needed: float = DEFAULT_HEADROOM_NEEDED,
                  footroom_needed: float | None = None) -> list[str]:
    """Zoom buys screen share out of the text bands. Say so when the trade has gone too far.

    Both bands are checked against the SCREEN QUAD, which is all the measurement knows about;
    the device's bezel stands proud of it, so these thresholds carry a bezel allowance and are
    still only a floor. `footroom_needed=None` skips the bottom band (the headline-only callers
    that predate the subline).
    """
    crop = measurement["canvas"]["crop"]
    warnings = []
    headroom = crop["headroom_px"]
    if headroom < headroom_needed:
        warnings.append(
            f"headroom is {headroom:.0f} px but a two-line headline wants about "
            f"{headroom_needed:.0f} px — the second line will sit on the device. Zoom less, or "
            f"reserve less footroom")
    if footroom_needed is not None:
        footroom = crop["footroom_px"]
        if footroom < footroom_needed:
            warnings.append(
                f"footroom is {footroom:.0f} px but a two-line subline wants about "
                f"{footroom_needed:.0f} px — it will sit on the device's bottom bezel. Zoom "
                f"less, or reserve more footroom")
    return warnings


def _ai_mark_group(width: float, height: float) -> str:
    """The static `ai-mark` group: a grey pill, bottom-right, sparkle glyph + two-line label.

    Anchored to the canvas's bottom-right corner (AI_MARK_RIGHT_INSET / AI_MARK_BOTTOM_INSET) —
    see the constants block above for why that placement never shares an x-range with the
    left-anchored subline, and why the pill's height keeps it clear vertically too. The glyph is
    a four-point sparkle drawn as a single closed cubic-free path (four tips at N/E/S/W joined by
    quadratic curves pulled toward the centre), not a font glyph, so there is no emoji fallback to
    break. Layout reads as a small lockup: the glyph and "AI" on the first line, "generated" on
    the second, left-aligned under "AI" — not flush with the pill's own left padding — so the two
    words visually belong to one phrase.
    """
    line_height_px = AI_MARK_FONT_SIZE * AI_MARK_LINE_HEIGHT_EM
    cap = HEADLINE_CAP_RATIO * AI_MARK_FONT_SIZE
    descender = SUBLINE_DESCENDER_RATIO * AI_MARK_FONT_SIZE
    pill_height = AI_MARK_PAD_Y + cap + line_height_px + descender + AI_MARK_PAD_Y

    text_block_width = AI_MARK_GLYPH_SIZE + AI_MARK_GLYPH_GAP + max(
        AI_MARK_LINE1_TEXT_WIDTH_ESTIMATE, AI_MARK_LINE2_TEXT_WIDTH_ESTIMATE)
    pill_width = AI_MARK_PAD_X + text_block_width + AI_MARK_PAD_X

    pill_x = width - AI_MARK_RIGHT_INSET - pill_width
    pill_y = height - AI_MARK_BOTTOM_INSET - pill_height

    line1_baseline = pill_y + AI_MARK_PAD_Y + cap
    line2_baseline = line1_baseline + line_height_px

    glyph_r = AI_MARK_GLYPH_SIZE / 2
    glyph_cx = pill_x + AI_MARK_PAD_X + glyph_r
    glyph_cy = line1_baseline - cap / 2
    tips = {
        "n": (glyph_cx, glyph_cy - glyph_r),
        "e": (glyph_cx + glyph_r, glyph_cy),
        "s": (glyph_cx, glyph_cy + glyph_r),
        "w": (glyph_cx - glyph_r, glyph_cy),
    }

    def waist(a: tuple[float, float], b: tuple[float, float]) -> tuple[float, float]:
        # The midpoint of two adjacent tips, pulled toward the glyph centre by AI_MARK_GLYPH_WAIST
        # — this is what makes the sides concave instead of a plain diamond.
        return (glyph_cx + (a[0] + b[0] - 2 * glyph_cx) / 2 * AI_MARK_GLYPH_WAIST,
                glyph_cy + (a[1] + b[1] - 2 * glyph_cy) / 2 * AI_MARK_GLYPH_WAIST)

    n, e, s, w = tips["n"], tips["e"], tips["s"], tips["w"]
    ne, es, sw, wn = waist(n, e), waist(e, s), waist(s, w), waist(w, n)
    glyph_path = (
        f"M{_fmt(n[0])},{_fmt(n[1])} "
        f"Q{_fmt(ne[0])},{_fmt(ne[1])} {_fmt(e[0])},{_fmt(e[1])} "
        f"Q{_fmt(es[0])},{_fmt(es[1])} {_fmt(s[0])},{_fmt(s[1])} "
        f"Q{_fmt(sw[0])},{_fmt(sw[1])} {_fmt(w[0])},{_fmt(w[1])} "
        f"Q{_fmt(wn[0])},{_fmt(wn[1])} {_fmt(n[0])},{_fmt(n[1])} Z"
    )

    text_x = pill_x + AI_MARK_PAD_X + AI_MARK_GLYPH_SIZE + AI_MARK_GLYPH_GAP

    return f"""  <g id="ai-mark">
    <rect x="{_fmt(pill_x)}" y="{_fmt(pill_y)}" width="{_fmt(pill_width)}" \
height="{_fmt(pill_height)}" rx="{_fmt(AI_MARK_CORNER_RADIUS)}" \
fill="{AI_MARK_FILL}" fill-opacity="{AI_MARK_FILL_OPACITY}"/>
    <path d="{glyph_path}" fill="#FFFFFF" fill-opacity="{AI_MARK_TEXT_OPACITY}"/>
    <text font-family="{FONT_STACK}"
          font-size="{_fmt(AI_MARK_FONT_SIZE)}" font-weight="{AI_MARK_FONT_WEIGHT}" \
letter-spacing="{AI_MARK_TRACKING}"
          fill="#FFFFFF" fill-opacity="{AI_MARK_TEXT_OPACITY}"><tspan x="{_fmt(text_x)}" \
y="{_fmt(line1_baseline)}">{AI_MARK_LINE1_TEXT}</tspan><tspan x="{_fmt(text_x)}" \
y="{_fmt(line2_baseline)}">{AI_MARK_LINE2_TEXT}</tspan></text>
  </g>
"""


def slot_template_svg(measurement: dict, *, slot: str, scene: str,
                      subline_lines: int = DEFAULT_SUBLINE_LINES) -> str:
    """The slot template this measurement implies. Pure string formatting, no I/O.

    `subline_lines` is how many lines of subline the manifest will pour in. Lines flow
    DOWNWARD from the <text> element's y, so the element is placed for the LAST of them
    (Design/AppStore/README.md, "The <tspan> pattern"): otherwise a two-line subline ends
    up one line closer to the canvas edge than a one-line one, the bottom margin wanders
    tile to tile, and a three-line one runs off the canvas.
    """
    canvas = measurement["canvas"]
    width, height = canvas["width"], canvas["height"]
    crop, bbox = canvas["crop"], canvas["bbox_px"]
    subline_baseline = round(height - SUBLINE_LAST_BASELINE_FROM_BOTTOM
                             - (max(1, subline_lines) - 1) * SUBLINE_SIZE * SUBLINE_LINE_HEIGHT_EM)
    bottom_scrim_y = height - BOTTOM_SCRIM_HEIGHT
    ai_mark = _ai_mark_group(width, height)

    return f"""<svg xmlns="http://www.w3.org/2000/svg" width="{width}" height="{height}" \
viewBox="0 0 {width} {height}">
  <title>OwnFrame store slot {slot} — scene {scene} — {width}x{height}</title>
  <desc>Generated by {TOOL} from measure-scene-cutout geometry. Never hand-edit the numbers:
  re-run the builder against the scene instead, or the clip polygon and the crop drift apart.</desc>

  <defs>
    <clipPath id="screen-quad">
      <polygon points="{measurement['svg']['clip_polygon_points']}"/>
    </clipPath>
    <linearGradient id="top-scrim" x1="0" y1="0" x2="0" y2="1">
      <stop offset="0"    stop-color="#000000" stop-opacity="0.78"/>
      <stop offset="0.55" stop-color="#000000" stop-opacity="0.42"/>
      <stop offset="1"    stop-color="#000000" stop-opacity="0"/>
    </linearGradient>
    <linearGradient id="bottom-scrim" x1="0" y1="1" x2="0" y2="0">
      <stop offset="0"    stop-color="#000000" stop-opacity="0.82"/>
      <stop offset="0.55" stop-color="#000000" stop-opacity="0.44"/>
      <stop offset="1"    stop-color="#000000" stop-opacity="0"/>
    </linearGradient>
  </defs>

  <rect x="0" y="0" width="{width}" height="{height}" fill="#000000"/>

  <image id="screenshot" x="{_fmt(bbox['x'])}" y="{_fmt(bbox['y'])}" \
width="{_fmt(bbox['width'])}" height="{_fmt(bbox['height'])}"
         preserveAspectRatio="none" clip-path="url(#screen-quad)" href=""/>

  <image id="scene" x="{_fmt(-crop['x'])}" y="{_fmt(-crop['y'])}" \
width="{_fmt(canvas['scaled_width'])}" height="{_fmt(canvas['scaled_height'])}"
         preserveAspectRatio="none" href=""/>

  <rect x="0" y="0" width="{width}" height="{TOP_SCRIM_HEIGHT}" fill="url(#top-scrim)"/>
  <rect x="0" y="{bottom_scrim_y}" width="{width}" height="{BOTTOM_SCRIM_HEIGHT}" \
fill="url(#bottom-scrim)"/>

  <text id="headline" x="{MARGIN_X}" y="{HEADLINE_BASELINE}"
        font-family="{FONT_STACK}"
        font-size="{HEADLINE_SIZE}" font-weight="{HEADLINE_WEIGHT}" \
letter-spacing="{HEADLINE_TRACKING}"
        fill="#FFFFFF" xml:space="preserve"><tspan x="{MARGIN_X}" dy="0">Headline line one\
</tspan><tspan x="{MARGIN_X}" dy="{HEADLINE_LINE_HEIGHT}">Headline line two</tspan></text>

  <text id="subline" x="{MARGIN_X}" y="{subline_baseline}"
        font-family="{FONT_STACK}"
        font-size="{SUBLINE_SIZE}" font-weight="{SUBLINE_WEIGHT}" letter-spacing="0"
        fill="#FFFFFF" fill-opacity="{SUBLINE_OPACITY}" xml:space="preserve">\
<tspan x="{MARGIN_X}" dy="0">Subline line one</tspan>\
<tspan x="{MARGIN_X}" dy="{SUBLINE_LINE_HEIGHT}">Subline line two</tspan></text>

{ai_mark}</svg>
"""


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog=TOOL, description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("scene", help="keyed scene PNG (the screen area is alpha 0)")
    parser.add_argument("--slot", required=True, help="slot number as it appears in the title")
    parser.add_argument("--out", required=True, help="where the slot SVG template lands")
    parser.add_argument("--device", default="ipad", help="store canvas: ipad or iphone")
    parser.add_argument("--zoom", default="1.0", metavar="FACTOR|max",
                        help="passed through to measure-scene-cutout: how far past a plain "
                             "cover fit to crop in. `max` spends every surplus pixel the scene "
                             "has and never invents one")
    parser.add_argument("--min-footroom", type=float, default=0.0, metavar="PX",
                        help="canvas pixels reserved below the screen for the subline")
    parser.add_argument("--headroom-needed", type=float, default=DEFAULT_HEADROOM_NEEDED,
                        metavar="PX", help="warn below this much room above the screen")
    parser.add_argument("--footroom-needed", type=float, default=DEFAULT_FOOTROOM_NEEDED,
                        metavar="PX", help="warn below this much room below the screen")
    parser.add_argument("--subline-lines", type=int, default=DEFAULT_SUBLINE_LINES,
                        metavar="N", help="how many lines of subline the manifest supplies "
                             "for this slot; the block is anchored on its LAST line so the "
                             "bottom margin is the same whatever N is")
    return parser


def main(argv: list[str] | None = None) -> int:
    args = build_parser().parse_args(argv)
    scene = Path(args.scene).expanduser()
    if not scene.is_file():
        print(f"error: no such scene {args.scene!r}", file=sys.stderr)
        return 2
    try:
        measurement = measure_scene(scene, device=args.device, zoom=args.zoom,
                                    min_footroom=args.min_footroom)
    except MeasurementError as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 3

    out = Path(args.out).expanduser()
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(slot_template_svg(measurement, slot=args.slot, scene=scene.name,
                                     subline_lines=args.subline_lines),
                   encoding="utf-8")

    crop = measurement["canvas"]["crop"]
    bbox = measurement["canvas"]["bbox_px"]
    canvas_area = measurement["canvas"]["width"] * measurement["canvas"]["height"]
    print(f"{out}  scene {scene.name}  zoom {crop.get('zoom', 1.0):.3f} "
          f"scale {measurement['canvas']['scale']:.3f}  "
          f"screen {bbox['width'] * bbox['height'] / canvas_area * 100:.1f}% of canvas  "
          f"headroom {crop['headroom_px']:.0f}px  footroom {crop['footroom_px']:.0f}px")

    warnings = band_warnings(measurement, headroom_needed=args.headroom_needed,
                             footroom_needed=args.footroom_needed)
    for warning in warnings:
        print(f"  WARNING {warning}", file=sys.stderr)
    return 1 if warnings else 0


if __name__ == "__main__":
    sys.exit(main())
