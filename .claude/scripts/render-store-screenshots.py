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

REQUIRED_SLOT_KEYS = ("id", "type", "template", "scene", "capture", "fit", "headline")

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


class SlotPaths(NamedTuple):
    template: Path
    scene: Path
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


def substitute(root: ET.Element, *, scene_uri: str, screenshot_uri: str | None,
               fit: str, lines: list[str]) -> None:
    """Mutates `root` in place: sets `scene` (required), `screenshot` (only if the template
    has one), and rebuilds `headline`'s <tspan> children from `lines` (FR-9010-16/22)."""
    scene_el = by_id(root, "scene")
    if scene_el is None:
        raise ValueError('template has no element id="scene"')
    scene_el.set("href", scene_uri)
    # `fit` governs the capture only, never the scene (README) — scene's own
    # preserveAspectRatio, baked into the template, is deliberately never touched here.

    screenshot_el = by_id(root, "screenshot")
    if screenshot_el is not None:
        if screenshot_uri is None:
            raise ValueError(
                'template has an element id="screenshot" but no capture data was supplied'
            )
        screenshot_el.set("href", screenshot_uri)
        screenshot_el.set("preserveAspectRatio", preserve_aspect_ratio(fit))
    # else: scene-only template — do nothing. Never dereference an id the template lacks.

    text_el = by_id(root, "headline")
    if text_el is None:
        raise ValueError('template has no element id="headline"')
    tspans = [c for c in list(text_el) if c.tag == f"{{{SVG_NS}}}tspan"]
    if len(tspans) < 2:
        raise ValueError('template headline id="headline" must ship at least two <tspan> children')
    first_attrs, rest_attrs = dict(tspans[0].attrib), dict(tspans[1].attrib)
    for child in list(text_el):
        text_el.remove(child)
    text_el.text = None
    for i, line in enumerate(lines):
        t = ET.SubElement(text_el, f"{{{SVG_NS}}}tspan", first_attrs if i == 0 else rest_attrs)
        t.text = line


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
    scene = override if override is not None else (
        root / "Design" / "AppStore" / "scenes" / device / slot["scene"]
    )
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
    return all(isinstance(slot.get(key), str) and slot.get(key)
               for key in ("id", "template", "scene", "capture"))


def combo_problems(device: str, locale: str, slot: dict, paths: SlotPaths) -> list[str]:
    """Asset-existence checks for one (device, locale, slot) combination."""
    sid = slot.get("id", "?")
    label = f"slot {sid!r} device={device} locale={locale}"
    problems = []
    if not paths.template.is_file():
        problems.append(f"{label}: missing template {paths.template}")
    if not paths.scene.is_file():
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


def warp_capture_perspective(capture: Path, perspective: list[list[float]], *,
                              work_dir: Path, tag: str) -> Path:
    """FR-9010-23/26: pre-warps the CAPTURE (never the scene) to the manifest's four
    destination corners before it is embedded. Unexercised end-to-end today — no slot carries
    `perspective` — but the manifest-side validation is unit-tested (_perspective_problems)."""
    facts = parse_png(capture.read_bytes())
    w, h = facts["width"], facts["height"]
    src = [(0, 0), (w, 0), (w, h), (0, h)]
    pairs = " ".join(f"{sx},{sy} {dx},{dy}" for (sx, sy), (dx, dy) in zip(src, perspective))
    dst = work_dir / f"warp-{tag}.png"
    try:
        subprocess.run([
            "magick", str(capture), "-matte", "-virtual-pixel", "transparent",
            "-distort", "Perspective", pairs, str(dst),
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

    capture_for_embed = paths.capture
    if slot.get("perspective") and capture_for_embed is not None:
        capture_for_embed = warp_capture_perspective(
            capture_for_embed, slot["perspective"], work_dir=work_dir, tag=tag,
        )

    tree = ET.parse(paths.template)
    tree_root = tree.getroot()
    scene_uri = data_uri(paths.scene)
    screenshot_uri = data_uri(capture_for_embed) if capture_for_embed is not None else None
    lines = slot["headline"][locale]
    substitute(tree_root, scene_uri=scene_uri, screenshot_uri=screenshot_uri,
               fit=slot["fit"], lines=lines)
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
        asset_problems.extend(combo_problems(d, l, s, paths))

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
        problems = combo_problems(d, l, s, paths)
        if problems:
            for p in problems:
                print(f"skip: {p}", file=sys.stderr)
            skipped.append(f"{d}/{l}/{sid}")
            continue
        try:
            dst = render_combo(device=d, locale=l, slot=s, paths=paths,
                                device_spec=devices_spec[d], out_dir=out_dir, work_dir=work_dir)
        except RenderAssertionError as exc:
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
