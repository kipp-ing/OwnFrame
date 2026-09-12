#!/usr/bin/env python3
"""generate-scene.py — generate an App Store room scene and cut the iPad's screen out as alpha.

Hand-cutting the iPad screen out of each App Store scene photo is the current bottleneck
(`docs/design/scene-brief.md`): six scenes, each needing a clean, hard-edged transparent hole
where `render-store-screenshots.py` later warps a real UI capture in. This tool removes the
hand-cutting step entirely by asking the image model itself to paint the screen as a flat,
solid, impossible-in-a-real-photo colour — magenta, `#FF00FF` — and then keying that exact
colour to full transparency with ImageMagick. A generated photo needs no scissors; it needs one
`-transparent` call.

Zero third-party Python dependencies (FR-9010-25, same posture as every other script in this
directory): stdlib `urllib.request` talks to the OpenAI Images API directly, and ImageMagick 7
(`magick`) does every pixel operation, exactly as `render-store-screenshots.py` and
`measure-scene-cutout.py` already do. Nothing here reimplements image processing in Python.

API facts this tool is built against (verified against the primary source, 2026-09-12 — do not
re-derive or "correct" these from an old tutorial; re-check `/v1/images/generations` if the
model changes):

  * `POST https://api.openai.com/v1/images/generations`, `Authorization: Bearer <key>`.
  * `model` defaults to `gpt-image-2` (a `--model` flag exists for whatever comes next).
  * `size` is `WIDTHxHEIGHT`: both multiples of 16, aspect ratio between 1:3 and 3:1, neither
    edge above 3840, and total pixels between 655,360 and 8,294,400. This tool's own target,
    2064x3040 (aspect 0.679, 6,274,560 px), sits inside every one of those limits but above the
    2560x1440 area the API calls "experimental" — permitted, just flagged, so `experimental_note`
    prints an informational line rather than failing anything.
  * `quality` is one of low/medium/high/xhigh/max/auto (default here: `high`, per this tool's
    own default — the API's own default is `auto`).
  * The response has **no download URL** for these options: the image comes back as base64 in
    `data[0].b64_json` and has to be decoded locally.

Traps this script exists to not re-learn:

  * **Never upscale.** If the model returns an image at the wrong pixel size — it can happen —
    resizing it up to fit is exactly the softness-inducing defect this whole tool exists to
    avoid (scene-brief.md: "the current scenes are 1086 x 1600 and get upscaled 1.9x — the wall
    is visibly soft"). `ensure_size_matches` refuses instead of silently fixing it up.
  * **PNG only, always, for the keyed output.** JPEG silently discards the alpha channel — this
    repo's own documented trap, first hit by `render-store-screenshots.py` — so the ImageMagick
    call forces `PNG32:` on the destination even if the raw generated image came back as JPEG or
    WebP.
  * **Hard edges, not a feathered halo.** `-transparent` (with `-fuzz` for tolerance) makes a
    binary keep-or-key-out decision per pixel; there is no antialiasing pass afterwards to
    reintroduce a soft edge. This is what keeps `measure-scene-cutout.py`'s hard-edge check
    happy for free, rather than as something this script has to work at.
  * **The API key is never on the command line and never printed.** It is read from
    `$OPENAI_API_KEY` or, failing that, `~/.config/openai/api-key` (whitespace-stripped). Every
    error message that can fire before a key is found names both places to look, never a value.
  * **`--dry-run` must be free.** It prints the JSON payload and the ImageMagick argv without
    ever resolving an API key, opening a socket, or starting `magick` — so iterating on a prompt
    costs nothing until `--dry-run` is dropped. `--skip-generate` is the companion for the next
    step of that same iteration loop: re-run only the keying pass on an already-generated raw
    image, so a prompt/keying tweak doesn't have to pay for a fresh generation.

Exit codes (mirrors `render-store-screenshots.py`'s convention): 0 clean · 1 the generated (or
supplied) raw image does not match the requested `--size` — never upscaled, refused instead · 2
bad invocation (bad `--size`, no prompt given, missing API key, `--skip-generate` path does not
exist) · 3 the OpenAI API or ImageMagick failed or could not be reached/found.
"""

from __future__ import annotations

import argparse
import base64
import binascii
import json
import os
import struct
import subprocess
import sys
import urllib.error
import urllib.request
from pathlib import Path

API_ENDPOINT = "https://api.openai.com/v1/images/generations"
DEFAULT_MODEL = "gpt-image-2"
DEFAULT_QUALITY = "high"
DEFAULT_SIZE = "2064x3040"
DEFAULT_FUZZ = "12%"
DEFAULT_OUTPUT_FORMAT = "png"
CHROMA_KEY = "#FF00FF"

QUALITIES = ("low", "medium", "high", "xhigh", "max", "auto")
OUTPUT_FORMATS = ("png", "jpeg", "webp")
RAW_EXTENSIONS = {"png": ".png", "jpeg": ".jpg", "webp": ".webp"}

# size_problems: the API's own hard constraints (see module docstring).
SIZE_MULTIPLE = 16
MAX_EDGE = 3840
MIN_PIXELS = 655_360
MAX_PIXELS = 8_294_400
MIN_ASPECT = 1.0 / 3.0
MAX_ASPECT = 3.0
ASPECT_TOLERANCE = 1e-9

# experimental_note: "above 2560x1440 is flagged experimental but permitted" — an area threshold,
# not a per-edge one, since the API states it as a resolution class rather than a single edge.
EXPERIMENTAL_PIXEL_THRESHOLD = 2560 * 1440

API_KEY_ENV = "OPENAI_API_KEY"
DEFAULT_API_KEY_FILE = Path("~/.config/openai/api-key")

PNG_SIGNATURE = b"\x89PNG\r\n\x1a\n"


class InvocationError(Exception):
    """Bad CLI usage: unreadable --prompt-file, invalid --size, no prompt given, no API key
    found in either place, or a --skip-generate path that does not exist (exit code 2)."""


class ApiError(RuntimeError):
    """The OpenAI Images API could not be reached, returned an HTTP error, or returned a
    response this tool cannot parse (missing b64_json, bad base64, non-JSON body) — exit 3."""


class ExternalToolError(RuntimeError):
    """ImageMagick failed or could not be found (exit code 3)."""


class SizeMismatchError(RuntimeError):
    """The raw image (generated or supplied via --skip-generate) does not match the requested
    --size. Never upscaled to fit — see the module docstring's "Never upscale" trap. Exit 1."""


# --------------------------------------------------------------------------------------
# --size parsing and the API's hard constraints on it.
# --------------------------------------------------------------------------------------

def parse_size(text: str) -> tuple[int, int]:
    parts = (text or "").strip().split("x")
    if len(parts) != 2 or not all(p.isdigit() for p in parts):
        raise InvocationError(f"--size must be WIDTHxHEIGHT (digits only), got {text!r}")
    return int(parts[0]), int(parts[1])


def size_problems(width: int, height: int) -> list[str]:
    """Every reason `size` could be rejected by the API, reported together (not just the
    first) so a bad --size is fixed in one pass instead of one failed request at a time."""
    problems = []
    if width % SIZE_MULTIPLE or height % SIZE_MULTIPLE:
        problems.append(
            f"{width}x{height}: both dimensions must be multiples of {SIZE_MULTIPLE}")
    if max(width, height) > MAX_EDGE:
        problems.append(f"{width}x{height}: no edge may exceed {MAX_EDGE}")
    pixels = width * height
    if not (MIN_PIXELS <= pixels <= MAX_PIXELS):
        problems.append(
            f"{width}x{height}: total pixel count {pixels} is outside "
            f"[{MIN_PIXELS}, {MAX_PIXELS}]")
    aspect = width / height
    if not (MIN_ASPECT - ASPECT_TOLERANCE <= aspect <= MAX_ASPECT + ASPECT_TOLERANCE):
        problems.append(
            f"{width}x{height}: aspect ratio {aspect:.4f} is outside 1:3..3:1")
    return problems


def experimental_note(width: int, height: int) -> str | None:
    pixels = width * height
    if pixels > EXPERIMENTAL_PIXEL_THRESHOLD:
        return (
            f"note: {width}x{height} ({pixels:,} px) is above 2560x1440 — the API flags sizes "
            "this large as experimental, though still permitted")
    return None


# --------------------------------------------------------------------------------------
# Request payload / argv construction — pure, never touches urllib or subprocess.
# --------------------------------------------------------------------------------------

def build_payload(*, prompt: str, model: str, size: str, quality: str,
                   output_format: str) -> dict:
    return {
        "model": model,
        "prompt": prompt,
        "size": size,
        "quality": quality,
        "output_format": output_format,
    }


def build_request(*, api_key: str, payload: dict, endpoint: str = API_ENDPOINT
                   ) -> tuple[str, dict, bytes]:
    """The (url, headers, body) an HTTP POST needs. Deliberately never constructs a
    `urllib.request.Request` itself, so a test can assert on these three plain values without
    touching urllib at all — the actual `Request` is built once, in `post_json`."""
    body = json.dumps(payload).encode("utf-8")
    headers = {"Authorization": f"Bearer {api_key}", "Content-Type": "application/json"}
    return endpoint, headers, body


def build_key_argv(src: Path, dst: Path, *, fuzz: str) -> list[str]:
    """The chroma-key step: flood every pixel within `fuzz` of the flat magenta screen to full
    transparency. `-transparent` makes a binary in-or-out decision per pixel — there is no
    intermediate alpha value it can produce — so the result has hard edges with no feathering
    for free; adding a `-blur` or `-antialias` pass afterwards would reintroduce exactly the
    defect `measure-scene-cutout.py`'s hard-edge check exists to catch, so none is ever added
    here. `PNG32:` on the destination forces an alpha channel to be written regardless of the
    raw image's own format (JPEG/WebP raws are legal input; PNG is mandatory output — JPEG
    silently discards alpha, this repo's own documented trap)."""
    return ["magick", str(src), "-fuzz", fuzz, "-transparent", CHROMA_KEY, f"PNG32:{dst}"]


# --------------------------------------------------------------------------------------
# The HTTP seam. post_json is the ONLY place urllib touches the network, so a test can
# monkeypatch `urllib.request.urlopen` directly here — the same shape as the sibling scripts
# monkeypatching `subprocess.run` for their one external-tool seam.
# --------------------------------------------------------------------------------------

def post_json(url: str, headers: dict, body: bytes, *, timeout: int = 180) -> bytes:
    request = urllib.request.Request(url, data=body, headers=headers, method="POST")
    try:
        with urllib.request.urlopen(request, timeout=timeout) as response:
            return response.read()
    except urllib.error.HTTPError as exc:
        detail = ""
        try:
            detail = exc.read().decode("utf-8", "replace")[:500]
        except OSError:  # pragma: no cover — fp already exhausted/closed
            pass
        raise ApiError(f"OpenAI API returned HTTP {exc.code}: {detail or exc.reason}") from exc
    except urllib.error.URLError as exc:
        raise ApiError(f"could not reach the OpenAI API: {exc.reason}") from exc


def extract_b64_image(response_bytes: bytes) -> bytes:
    try:
        response = json.loads(response_bytes)
    except json.JSONDecodeError as exc:
        raise ApiError(f"OpenAI API returned non-JSON response: {exc}") from exc
    try:
        b64 = response["data"][0]["b64_json"]
    except (KeyError, IndexError, TypeError) as exc:
        raise ApiError(
            "OpenAI API response had no data[0].b64_json — there is no download URL for these "
            "request options, so this is the only place the image can come from") from exc
    try:
        return base64.b64decode(b64, validate=True)
    except (binascii.Error, ValueError) as exc:
        raise ApiError(f"OpenAI API returned unparsable base64 image data: {exc}") from exc


def generate_raw_image(*, prompt: str, model: str, size: str, quality: str,
                        output_format: str, api_key: str, endpoint: str = API_ENDPOINT) -> bytes:
    payload = build_payload(prompt=prompt, model=model, size=size, quality=quality,
                             output_format=output_format)
    url, headers, body = build_request(api_key=api_key, payload=payload, endpoint=endpoint)
    return extract_b64_image(post_json(url, headers, body))


# --------------------------------------------------------------------------------------
# API key resolution (never printed, never logged — see module docstring).
# --------------------------------------------------------------------------------------

def resolve_api_key(*, env: dict | None = None, key_file: Path | None = None) -> str:
    env = os.environ if env is None else env
    key_file = DEFAULT_API_KEY_FILE.expanduser() if key_file is None else Path(key_file)

    value = (env.get(API_KEY_ENV) or "").strip()
    if value:
        return value

    if key_file.is_file():
        text = key_file.read_text(encoding="utf-8").strip()
        if text:
            return text

    raise InvocationError(
        f"no OpenAI API key found: set ${API_KEY_ENV} or put one in {key_file} "
        "(whitespace is stripped)")


# --------------------------------------------------------------------------------------
# ImageMagick invocation (the keying step) and reading a raw image's own pixel size back.
# --------------------------------------------------------------------------------------

def key_scene(src: Path, dst: Path, *, fuzz: str) -> None:
    try:
        subprocess.run(build_key_argv(src, dst, fuzz=fuzz), check=True, capture_output=True)
    except (subprocess.CalledProcessError, FileNotFoundError) as exc:
        raise ExternalToolError(f"ImageMagick failed keying {src}: {exc}") from exc


def identify_size(path: Path) -> tuple[int, int]:
    """The raw generated image's own pixel size, straight from ImageMagick — the raw image may
    be PNG, JPEG or WebP (whichever --output-format asked for), so this cannot assume the local
    PNG-header reader `read_png_dimensions` applies to it the way it does to the keyed --out
    file, which this tool always writes as PNG itself."""
    try:
        result = subprocess.run(
            ["magick", "identify", "-format", "%w %h", f"{path}[0]"],
            check=True, capture_output=True, text=True,
        )
    except (subprocess.CalledProcessError, FileNotFoundError) as exc:
        raise ExternalToolError(f"ImageMagick could not identify {path}: {exc}") from exc
    width_str, height_str = result.stdout.split()
    return int(width_str), int(height_str)


def read_png_dimensions(data: bytes) -> tuple[int, int]:
    """Width/height read straight from the PNG's own IHDR bytes — never from a tool's opinion
    (same principle as render-store-screenshots.py's `parse_png`). Used only on the keyed
    --out file, which this tool always writes via `PNG32:`, so it is always a real PNG here."""
    if data[:8] != PNG_SIGNATURE:
        raise ValueError("not a PNG file (bad signature)")
    width, height = struct.unpack(">II", data[16:24])
    return width, height


def ensure_size_matches(actual: tuple[int, int], expected: tuple[int, int]) -> None:
    if actual != expected:
        aw, ah = actual
        ew, eh = expected
        raise SizeMismatchError(
            f"generated image came back at {aw}x{ah}, requested {ew}x{eh} — refusing to "
            "upscale; re-run with a different --size, or retry generation")


def default_raw_path(out_path: Path, output_format: str) -> Path:
    """Where the unkeyed image lives when --raw-out is not given: a sibling of --out, deleted
    again once keying succeeds. Deterministic (not a tempfile) so --dry-run's printed argv shows
    the exact path a real run would use."""
    ext = RAW_EXTENSIONS[output_format]
    return out_path.with_name(out_path.stem + ".raw" + ext)


# --------------------------------------------------------------------------------------
# CLI
# --------------------------------------------------------------------------------------

def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    prompt_group = parser.add_mutually_exclusive_group()
    prompt_group.add_argument("--prompt", help="the scene prompt, inline")
    prompt_group.add_argument("--prompt-file", help="read the scene prompt from this file")
    parser.add_argument("--out", required=True, help="where the finished, keyed scene PNG lands")
    parser.add_argument("--model", default=DEFAULT_MODEL)
    parser.add_argument("--quality", default=DEFAULT_QUALITY, choices=QUALITIES)
    parser.add_argument("--size", default=DEFAULT_SIZE, help="WIDTHxHEIGHT, e.g. 2064x3040")
    parser.add_argument("--output-format", default=DEFAULT_OUTPUT_FORMAT, choices=OUTPUT_FORMATS,
                         help="format requested from the API for the RAW generated image; the "
                              "keyed --out file is always PNG regardless of this flag")
    parser.add_argument("--fuzz", default=DEFAULT_FUZZ,
                         help="ImageMagick -fuzz tolerance for the chroma key (default 12%%)")
    parser.add_argument("--raw-out", help="keep the unkeyed generated image at this path")
    parser.add_argument("--skip-generate", metavar="PATH",
                         help="skip the API call; key this already-generated raw image instead")
    parser.add_argument("--dry-run", action="store_true",
                         help="print the request payload and the ImageMagick argv; call nothing")
    return parser


def _read_prompt(args) -> str:
    if args.prompt_file:
        try:
            return Path(args.prompt_file).expanduser().read_text(encoding="utf-8").strip()
        except OSError as exc:
            raise InvocationError(f"cannot read --prompt-file {args.prompt_file!r}: {exc}") from exc
    return (args.prompt or "").strip()


def main(argv: list[str] | None = None) -> int:
    args = build_parser().parse_args(argv)
    out_path = Path(args.out).expanduser().resolve()

    try:
        width, height = parse_size(args.size)
    except InvocationError as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 2
    problems = size_problems(width, height)
    if problems:
        for p in problems:
            print(f"error: {p}", file=sys.stderr)
        return 2
    note = experimental_note(width, height)
    if note:
        print(note, file=sys.stderr)

    if not args.skip_generate and not args.prompt and not args.prompt_file:
        print("error: one of --prompt or --prompt-file is required unless --skip-generate is "
              "given", file=sys.stderr)
        return 2

    prompt = None
    if not args.skip_generate:
        try:
            prompt = _read_prompt(args)
        except InvocationError as exc:
            print(f"error: {exc}", file=sys.stderr)
            return 2
        if not prompt:
            print("error: prompt is empty", file=sys.stderr)
            return 2

    if args.skip_generate:
        skip_path = Path(args.skip_generate).expanduser().resolve()
        if not skip_path.is_file():
            print(f"error: --skip-generate path does not exist: {skip_path}", file=sys.stderr)
            return 2

    if args.dry_run:
        if args.skip_generate:
            print(f"skip-generate: reusing raw image at {skip_path}, no API call")
            key_src = skip_path
        else:
            payload = build_payload(prompt=prompt, model=args.model, size=args.size,
                                     quality=args.quality, output_format=args.output_format)
            print(f"request: POST {API_ENDPOINT}")
            print("headers: Authorization: Bearer <not resolved in --dry-run>, "
                  "Content-Type: application/json")
            print("payload:")
            print(json.dumps(payload, indent=2))
            key_src = (Path(args.raw_out).expanduser().resolve() if args.raw_out
                       else default_raw_path(out_path, args.output_format))
        print("imagemagick argv:")
        print("  " + " ".join(build_key_argv(key_src, out_path, fuzz=args.fuzz)))
        print("dry-run: no network request or ImageMagick invocation made")
        return 0

    cleanup_raw = False
    if args.skip_generate:
        raw_path = skip_path
    else:
        try:
            api_key = resolve_api_key()
        except InvocationError as exc:
            print(f"error: {exc}", file=sys.stderr)
            return 2
        try:
            image_bytes = generate_raw_image(
                prompt=prompt, model=args.model, size=args.size, quality=args.quality,
                output_format=args.output_format, api_key=api_key)
        except ApiError as exc:
            print(f"error: {exc}", file=sys.stderr)
            return 3

        if args.raw_out:
            raw_path = Path(args.raw_out).expanduser().resolve()
        else:
            raw_path = default_raw_path(out_path, args.output_format)
            cleanup_raw = True
        raw_path.parent.mkdir(parents=True, exist_ok=True)
        raw_path.write_bytes(image_bytes)

        try:
            actual_size = identify_size(raw_path)
        except ExternalToolError as exc:
            print(f"error: {exc}", file=sys.stderr)
            if cleanup_raw:
                raw_path.unlink(missing_ok=True)
            return 3
        try:
            ensure_size_matches(actual_size, (width, height))
        except SizeMismatchError as exc:
            print(f"error: {exc}", file=sys.stderr)
            if cleanup_raw:
                raw_path.unlink(missing_ok=True)
            return 1

    out_path.parent.mkdir(parents=True, exist_ok=True)
    try:
        key_scene(raw_path, out_path, fuzz=args.fuzz)
    except ExternalToolError as exc:
        print(f"error: {exc}", file=sys.stderr)
        return 3
    finally:
        if cleanup_raw:
            raw_path.unlink(missing_ok=True)

    try:
        final_size = read_png_dimensions(out_path.read_bytes())
    except (OSError, ValueError) as exc:
        print(f"error: cannot read finished scene {out_path}: {exc}", file=sys.stderr)
        return 3

    print(f"scene written: {out_path} ({final_size[0]}x{final_size[1]})")
    return 0


if __name__ == "__main__":
    sys.exit(main())
