#!/usr/bin/env python3
"""render-contact-sheet.py — one glance at every App Store slot, rendered or not.

Wraps `render-store-screenshots.py` (AP-3) rather than reimplementing rendering: shells out to
it once per requested (device, locale), reads back its own stdout "rendered: <path>" lines and
stderr "skip: slot '<id>' device=... locale=...: missing <kind> <path>" lines — the
skip-with-reason protocol that renderer already implements for exactly this purpose — and tiles
the result into one PNG contact sheet via ImageMagick, in the manifest's own slot order (App
Store display order). A slot with no template/scene/capture yet gets a labelled grey placeholder
tile instead of failing the whole sheet: this is a review tool for a set that is still being
built, not a release gate, so "5 of 6 done" must stay a normal, legible result.

Zero third-party Python dependencies (matches the renderer's own rule, FR-9010-25). ImageMagick
is the only external tool touched directly (already verified present, FR-9010-26); Chrome is
never invoked here — that stays entirely inside the wrapped renderer.

Usage:
  # Full matrix: every declared device x locale, one contact sheet PNG each.
  render-contact-sheet.py

  # Narrow to what you actually want to look at.
  render-contact-sheet.py --device ipad --locale en

Output: tmp/store-contact-sheet/<device>-<locale>.png (FR-9010-28: a diagnostic, not a shipped
asset, so it lives in the sanctioned in-repo scratch dir, not Design/).

Exit codes: 0 always, unless ImageMagick itself is missing or fails (2) or the manifest can't be
read (2). A slot being unrendered is reported ON the sheet, not treated as a script failure —
that is the entire point of this tool.
"""

from __future__ import annotations

import argparse
import json
import re
import subprocess
import sys
from pathlib import Path
from typing import Callable

ROOT = Path(__file__).resolve().parents[2]
RENDERER = Path(__file__).resolve().parent / "render-store-screenshots.py"
DEFAULT_MANIFEST = ROOT / "Design" / "AppStore" / "content.json"
DEFAULT_OUT_DIR = ROOT / "tmp" / "store-contact-sheet"

TILE_WIDTH = 420
LABEL_HEIGHT = 90
COLUMNS = 3
# ImageMagick's own font config resolves nothing on this machine (`magick -list font` is empty,
# same underlying gap the renderer's docstring notes for its SVG delegate) — point at a system
# font file directly rather than relying on a font *name* lookup.
LABEL_FONT = "/System/Library/Fonts/Helvetica.ttc"

RENDERED_RE = re.compile(r"^rendered:\s+(?P<path>.+)$")
SKIP_RE = re.compile(
    r"^skip:\s+slot\s+'(?P<slot>[^']+)'\s+device=(?P<device>\S+)\s+locale=(?P<locale>\S+):"
    r"\s+missing\s+(?P<kind>\S+)\s+(?P<path>.+)$"
)


# --------------------------------------------------------------------------------------
# Pure logic: parsing the renderer's protocol, labels, argv construction, tile ordering.
# --------------------------------------------------------------------------------------

def parse_renderer_output(stdout: str, stderr: str) -> tuple[dict[str, Path], dict[str, list[str]]]:
    """Read back the renderer's own "rendered:"/"skip:" lines. Any other line is ignored —
    the renderer's summary/progress chatter is not this function's concern."""
    rendered: dict[str, Path] = {}
    for line in stdout.splitlines():
        m = RENDERED_RE.match(line)
        if m:
            path = Path(m.group("path"))
            rendered[path.stem] = path

    missing: dict[str, list[str]] = {}
    for line in stderr.splitlines():
        m = SKIP_RE.match(line)
        if m:
            missing.setdefault(m.group("slot"), []).append(m.group("kind"))
    return rendered, missing


def short_headline(slot: dict, locale: str) -> str:
    headline = slot.get("headline") or {}
    lines = headline.get(locale) or headline.get("en") or []
    return " ".join(lines)


def missing_reason(kinds: list[str]) -> str:
    if not kinds:
        return "unknown"
    return ", ".join(sorted(set(kinds)))


def tile_label(slot: dict, locale: str) -> str:
    headline = short_headline(slot, locale)
    return f"{slot['id']}\n{headline}" if headline else slot["id"]


# --------------------------------------------------------------------------------------
# ImageMagick argv construction. Never executed by tests — only asserted.
# --------------------------------------------------------------------------------------

def thumbnail_command(src: Path, dst: Path, *, label: str) -> list[str]:
    return [
        "magick", str(src),
        "-resize", f"{TILE_WIDTH}x",
        "-background", "white", "-gravity", "North", "-splice", f"0x{LABEL_HEIGHT}",
        "-font", LABEL_FONT, "-gravity", "North", "-pointsize", "20", "-fill", "black",
        "-annotate", "+0+10", label,
        str(dst),
    ]


def placeholder_command(dst: Path, *, label: str, reason: str) -> list[str]:
    height = round(TILE_WIDTH * 2752 / 2064)
    return [
        "magick", "-size", f"{TILE_WIDTH}x{height}", "xc:#2b2b2b",
        "-background", "white", "-gravity", "North", "-splice", f"0x{LABEL_HEIGHT}",
        "-font", LABEL_FONT, "-gravity", "North", "-pointsize", "20", "-fill", "black",
        "-annotate", "+0+10", label,
        "-gravity", "Center", "-pointsize", "26", "-fill", "#999999",
        "-annotate", "+0+0", f"not yet rendered\nmissing: {reason}",
        str(dst),
    ]


def montage_command(tiles: list[Path], *, columns: int, out: Path) -> list[str]:
    # `-label ""` suppresses montage's own default per-tile filename caption (which needs a
    # font just like our own annotate calls do) — every tile already carries its own label,
    # baked in by thumbnail_command/placeholder_command.
    return [
        "magick", "montage", *[str(t) for t in tiles],
        "-tile", f"{columns}x", "-geometry", "+16+16", "-background", "#111111",
        "-font", LABEL_FONT, "-label", "",
        str(out),
    ]


# --------------------------------------------------------------------------------------
# Orchestration.
# --------------------------------------------------------------------------------------

def build_tiles(
    slots: list[dict],
    *,
    rendered: dict[str, Path],
    missing: dict[str, list[str]],
    locale: str,
    work_dir: Path,
    make_thumbnail: Callable[..., None],
    make_placeholder: Callable[..., None],
) -> list[Path]:
    """One tile per slot, in manifest order (= App Store display order), regardless of the
    order the renderer happened to report things in."""
    tiles = []
    for slot in slots:
        slot_id = slot["id"]
        tile_path = work_dir / f"tile-{slot_id}.png"
        label = tile_label(slot, locale)
        if slot_id in rendered:
            make_thumbnail(rendered[slot_id], tile_path, label=label)
        else:
            make_placeholder(tile_path, label=label, reason=missing_reason(missing.get(slot_id, [])))
        tiles.append(tile_path)
    return tiles


def run_renderer(*, manifest: Path, device: str, locale: str, out_dir: Path,
                  capture_root: str | None) -> tuple[dict[str, Path], dict[str, list[str]]]:
    cmd = [sys.executable, str(RENDERER), "--manifest", str(manifest),
           "--device", device, "--locale", locale, "--out", str(out_dir)]
    if capture_root:
        cmd += ["--capture-root", capture_root]
    result = subprocess.run(cmd, capture_output=True, text=True)
    return parse_renderer_output(result.stdout, result.stderr)


def make_thumbnail(src: Path, dst: Path, *, label: str) -> None:
    subprocess.run(thumbnail_command(src, dst, label=label), check=True)


def make_placeholder(dst: Path, *, label: str, reason: str) -> None:
    subprocess.run(placeholder_command(dst, label=label, reason=reason), check=True)


def make_montage(tiles: list[Path], *, columns: int, out: Path) -> None:
    subprocess.run(montage_command(tiles, columns=columns, out=out), check=True)


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description="Render every App Store slot and tile the result into one contact sheet PNG."
    )
    parser.add_argument("--manifest", default=str(DEFAULT_MANIFEST))
    parser.add_argument("--device", action="append", help="repeatable; default is every declared device")
    parser.add_argument("--locale", action="append", help="repeatable; default is every declared locale")
    parser.add_argument("--capture-root", help="override the manifest's captureRoot")
    parser.add_argument("--out-dir", default=str(DEFAULT_OUT_DIR))
    parser.add_argument("--columns", type=int, default=COLUMNS)
    return parser


def main(argv: list[str] | None = None, *, root: Path = ROOT) -> int:
    args = build_parser().parse_args(argv)
    manifest_path = Path(args.manifest)
    try:
        manifest = json.loads(manifest_path.read_text())
    except (OSError, json.JSONDecodeError) as exc:
        print(f"error: cannot read manifest {manifest_path}: {exc}", file=sys.stderr)
        return 2

    devices = args.device or list(manifest["devices"])
    locales = args.locale or list(manifest["locales"])
    slots = manifest["slots"]
    out_dir = Path(args.out_dir)
    out_dir.mkdir(parents=True, exist_ok=True)

    sheets = []
    for device in devices:
        for locale in locales:
            work_dir = out_dir / f"work-{device}-{locale}"
            work_dir.mkdir(parents=True, exist_ok=True)
            render_out = work_dir / "rendered"
            rendered, missing = run_renderer(
                manifest=manifest_path, device=device, locale=locale,
                out_dir=render_out, capture_root=args.capture_root,
            )
            tiles = build_tiles(
                slots, rendered=rendered, missing=missing, locale=locale, work_dir=work_dir,
                make_thumbnail=make_thumbnail, make_placeholder=make_placeholder,
            )
            sheet_path = out_dir / f"{device}-{locale}.png"
            make_montage(tiles, columns=args.columns, out=sheet_path)
            done = sum(1 for slot in slots if slot["id"] in rendered)
            print(f"{device}/{locale}: {done}/{len(slots)} rendered -> {sheet_path}")
            sheets.append(sheet_path)

    return 0


if __name__ == "__main__":
    sys.exit(main())
