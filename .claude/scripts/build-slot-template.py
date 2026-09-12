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
        [--device ipad] [--zoom max] [--min-footroom 380]

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
# These are a look that was reviewed and accepted, so they are constants rather than flags. The
# headline is anchored to its FIRST line, so every tile's top edge of type lines up; the subline
# sits on a fixed baseline near the bottom. Both are in canvas pixels.
MARGIN_X = 140
HEADLINE_BASELINE = 300
HEADLINE_SIZE = 126
HEADLINE_WEIGHT = "300"          # SF Pro Display Light. The 700 bold this replaced was "a disgrace".
HEADLINE_TRACKING = -1
HEADLINE_LINE_HEIGHT = "1.18em"
SUBLINE_BASELINE_FROM_BOTTOM = 180
SUBLINE_SIZE = 76
SUBLINE_WEIGHT = "400"
SUBLINE_OPACITY = "0.92"
SUBLINE_LINE_HEIGHT = "1.3em"
TOP_SCRIM_HEIGHT = 780
BOTTOM_SCRIM_HEIGHT = 760
FONT_STACK = "system-ui, BlinkMacSystemFont, sans-serif"

# A two-line headline occupies the baseline plus one line of leading, and wants a little air
# under it before it reaches the device. Below this much headroom the type starts sitting on the
# bezel — legible, because the scrim is dark and so is the bezel, but no longer deliberate.
DEFAULT_HEADROOM_NEEDED = 400.0


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


def band_warnings(measurement: dict, *, headroom_needed: float = DEFAULT_HEADROOM_NEEDED
                   ) -> list[str]:
    """Zoom buys screen share out of the text bands. Say so when the trade has gone too far."""
    headroom = measurement["canvas"]["crop"]["headroom_px"]
    if headroom >= headroom_needed:
        return []
    return [f"headroom is {headroom:.0f} px but a two-line headline wants about "
            f"{headroom_needed:.0f} px — the second line will sit on the device. Zoom less, or "
            f"reserve less footroom"]


def slot_template_svg(measurement: dict, *, slot: str, scene: str) -> str:
    """The slot template this measurement implies. Pure string formatting, no I/O."""
    canvas = measurement["canvas"]
    width, height = canvas["width"], canvas["height"]
    crop, bbox = canvas["crop"], canvas["bbox_px"]
    subline_baseline = height - SUBLINE_BASELINE_FROM_BOTTOM
    bottom_scrim_y = height - BOTTOM_SCRIM_HEIGHT

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
</svg>
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
    out.write_text(slot_template_svg(measurement, slot=args.slot, scene=scene.name),
                   encoding="utf-8")

    crop = measurement["canvas"]["crop"]
    bbox = measurement["canvas"]["bbox_px"]
    canvas_area = measurement["canvas"]["width"] * measurement["canvas"]["height"]
    print(f"{out}  scene {scene.name}  zoom {crop.get('zoom', 1.0):.3f} "
          f"scale {measurement['canvas']['scale']:.3f}  "
          f"screen {bbox['width'] * bbox['height'] / canvas_area * 100:.1f}% of canvas  "
          f"headroom {crop['headroom_px']:.0f}px  footroom {crop['footroom_px']:.0f}px")

    warnings = band_warnings(measurement, headroom_needed=args.headroom_needed)
    for warning in warnings:
        print(f"  WARNING {warning}", file=sys.stderr)
    return 1 if warnings else 0


if __name__ == "__main__":
    sys.exit(main())
