"""test_generate_scene.py — unit tests for generate-scene.py.

Written FIRST per this repo's TDD policy: at the point this file was created,
`.claude/scripts/generate-scene.py` did not exist at all, so every test below failed with an
import error (`FileNotFoundError` out of `spec_from_file_location`/`exec_module`). The
implementation was then written until this file went green.

Run with:

    cd /Users/jan/dev/repos/Immich-Slideshow
    python3 -m unittest discover -s .claude/scripts/tests -v

Scope: PURE logic only, same policy as the sibling test files (test_render_store_screenshots.py,
test_measure_scene_cutout.py). Two external systems are involved and neither is ever really
touched here:

  * The network. `post_json` is the only place `urllib.request.urlopen` is called, so every test
    that needs to go "through" a generation monkeypatches `gs.urllib.request.urlopen` (or, for the
    tests one layer up, `gs.post_json` itself) with a fake and asserts on what was sent — the same
    shape as the sibling files' `subprocess.run` monkeypatching, just for the HTTP seam instead of
    the ImageMagick one.
  * ImageMagick. `key_scene`/`identify_size` shell out via `subprocess.run`; tests monkeypatch
    `gs.subprocess.run` and never let a real `magick` process start.

Several tests additionally install a "poison pill" — a monkeypatched `urlopen`/`subprocess.run`
that raises `AssertionError` if actually called — specifically on the `--dry-run` and
`--skip-generate` CLI paths, because "no network call happens" and "no API call is spent" are the
entire point of those two flags and deserve a test that would fail loudly if either path
regressed into calling out.

Import mechanics: hyphenated filename, loaded by absolute path via
`importlib.util.spec_from_file_location`, exactly as the sibling test files do.
"""

from __future__ import annotations

import base64
import contextlib
import importlib.util
import io
import json
import shutil
import struct
import sys
import unittest
import urllib.error
import zlib
from pathlib import Path

TEST_FILE = Path(__file__).resolve()
ROOT = TEST_FILE.parents[3]
MODULE_PATH = TEST_FILE.parents[1] / "generate-scene.py"
SCRATCH = ROOT / "tmp" / "test-generate-scene"


def _load_module():
    spec = importlib.util.spec_from_file_location("generate_scene", MODULE_PATH)
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


gs = _load_module()


# --------------------------------------------------------------------------------------
# Shared fixtures
# --------------------------------------------------------------------------------------

def _png_chunk(tag: bytes, payload: bytes) -> bytes:
    return (
        struct.pack(">I", len(payload)) + tag + payload
        + struct.pack(">I", zlib.crc32(tag + payload) & 0xFFFFFFFF)
    )


def _make_png(width: int, height: int) -> bytes:
    """Hand-built minimal valid PNG, no Pillow / no third-party imaging (FR-9010-25)."""
    sig = b"\x89PNG\r\n\x1a\n"
    ihdr = struct.pack(">IIBBBBB", width, height, 8, 2, 0, 0, 0)
    row = bytes([0]) + bytes([128]) * (width * 3)
    idat = zlib.compress(row * height)
    chunks = [_png_chunk(b"IHDR", ihdr), _png_chunk(b"IDAT", idat), _png_chunk(b"IEND", b"")]
    return sig + b"".join(chunks)


class _FakeResponse:
    """Stand-in for the object `urllib.request.urlopen` hands back, used as a context manager."""

    def __init__(self, data: bytes):
        self._data = data

    def read(self):
        return self._data

    def __enter__(self):
        return self

    def __exit__(self, *exc_info):
        return False


class ScratchTestCase(unittest.TestCase):
    """Gives every test its own tmp/ subdirectory, torn down afterwards (matches the sibling
    renderer test files' fixture policy: nothing is ever written to Design/ or the real home
    directory)."""

    def setUp(self):
        self.work = SCRATCH / self.__class__.__name__ / self._testMethodName
        if self.work.exists():
            shutil.rmtree(self.work)
        self.work.mkdir(parents=True)

    def tearDown(self):
        shutil.rmtree(self.work, ignore_errors=True)

    def run_main(self, argv: list[str]) -> tuple[int, str, str]:
        out, err = io.StringIO(), io.StringIO()
        with contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
            code = gs.main(argv)
        return code, out.getvalue(), err.getvalue()


def _poison(monkeypatch_target: str, module, name: str):
    """Replace `module.<name>` with a callable that fails the test if it is ever invoked, and
    return a restore function. Used to prove a code path truly never touches the network or
    ImageMagick."""
    original = getattr(module, name)

    def _boom(*args, **kwargs):
        raise AssertionError(f"{monkeypatch_target} must not be called on this path")

    setattr(module, name, _boom)

    def _restore():
        setattr(module, name, original)

    return _restore


# --------------------------------------------------------------------------------------
# 1. --size parsing and the API's own hard constraints (FR-9010-25 facts, verified 2026-09-12)
# --------------------------------------------------------------------------------------

class TestParseSize(unittest.TestCase):
    def test_parses_width_and_height(self):
        self.assertEqual(gs.parse_size("2064x3040"), (2064, 3040))

    def test_rejects_missing_x(self):
        with self.assertRaises(gs.InvocationError):
            gs.parse_size("2064-3040")

    def test_rejects_non_numeric(self):
        with self.assertRaises(gs.InvocationError):
            gs.parse_size("wideXtall")

    def test_rejects_trailing_garbage(self):
        with self.assertRaises(gs.InvocationError):
            gs.parse_size("2064x3040x1")


class TestSizeProblems(unittest.TestCase):
    def test_target_geometry_is_clean(self):
        self.assertEqual(gs.size_problems(2064, 3040), [])

    def test_non_multiple_of_16_is_flagged(self):
        problems = gs.size_problems(2065, 3040)
        self.assertTrue(any("multiple" in p for p in problems))

    def test_odd_height_is_flagged(self):
        problems = gs.size_problems(2064, 3041)
        self.assertTrue(any("multiple" in p for p in problems))

    def test_edge_over_3840_is_flagged(self):
        problems = gs.size_problems(3856, 1024)
        self.assertTrue(any("3840" in p for p in problems))

    def test_too_few_pixels_is_flagged(self):
        problems = gs.size_problems(256, 256)  # 65,536 px, well under the 655,360 floor
        self.assertTrue(any("pixel count" in p for p in problems))

    def test_too_many_pixels_is_flagged(self):
        problems = gs.size_problems(3840, 3840)  # over the 8,294,400 ceiling
        self.assertTrue(any("pixel count" in p for p in problems))

    def test_aspect_ratio_beyond_3to1_is_flagged(self):
        problems = gs.size_problems(3840, 1024)  # ratio 3.75, outside 1:3..3:1
        self.assertTrue(any("aspect" in p for p in problems))

    def test_aspect_ratio_exactly_3to1_is_clean(self):
        # 3072x1024: multiples of 16, 3,145,728 px (in range), ratio exactly 3.0.
        self.assertEqual(gs.size_problems(3072, 1024), [])

    def test_multiple_problems_all_reported(self):
        problems = gs.size_problems(3841, 3841)
        self.assertGreaterEqual(len(problems), 2)


class TestExperimentalNote(unittest.TestCase):
    def test_below_threshold_is_none(self):
        self.assertIsNone(gs.experimental_note(1024, 1024))

    def test_above_2560x1440_area_is_flagged_informational(self):
        note = gs.experimental_note(2064, 3040)
        self.assertIsNotNone(note)
        self.assertIn("experimental", note)


# --------------------------------------------------------------------------------------
# 2. Request payload / argv construction — pure, never touches urllib or subprocess.
# --------------------------------------------------------------------------------------

class TestBuildPayload(unittest.TestCase):
    def test_payload_has_exactly_the_documented_fields(self):
        payload = gs.build_payload(
            prompt="a room", model="gpt-image-2", size="2064x3040",
            quality="high", output_format="png",
        )
        self.assertEqual(payload, {
            "model": "gpt-image-2",
            "prompt": "a room",
            "size": "2064x3040",
            "quality": "high",
            "output_format": "png",
        })


class TestBuildRequest(unittest.TestCase):
    def test_endpoint_headers_and_body(self):
        payload = {"model": "gpt-image-2", "prompt": "x"}
        url, headers, body = gs.build_request(api_key="sk-test-123", payload=payload)
        self.assertEqual(url, "https://api.openai.com/v1/images/generations")
        self.assertEqual(headers["Authorization"], "Bearer sk-test-123")
        self.assertEqual(headers["Content-Type"], "application/json")
        self.assertEqual(json.loads(body), payload)

    def test_body_is_bytes_not_str(self):
        _, _, body = gs.build_request(api_key="k", payload={"a": 1})
        self.assertIsInstance(body, bytes)


class TestBuildKeyArgv(unittest.TestCase):
    def test_argv_shape(self):
        cmd = gs.build_key_argv(Path("/tmp/raw.png"), Path("/tmp/out.png"), fuzz="12%")
        self.assertEqual(cmd[0], "magick")
        self.assertIn(str(Path("/tmp/raw.png")), cmd)
        self.assertIn("-fuzz", cmd)
        self.assertEqual(cmd[cmd.index("-fuzz") + 1], "12%")
        self.assertIn("-transparent", cmd)
        self.assertEqual(cmd[cmd.index("-transparent") + 1], "#FF00FF")
        self.assertEqual(cmd[-1], "PNG32:/tmp/out.png")

    def test_no_blur_or_antialias_flags_which_would_feather_the_edge(self):
        # measure-scene-cutout.py's hard-edge check is the whole point of this tool; a -blur or
        # -antialias flag here would reintroduce the exact defect it exists to catch.
        cmd = gs.build_key_argv(Path("/a.png"), Path("/b.png"), fuzz="10%")
        self.assertNotIn("-blur", cmd)
        self.assertNotIn("-antialias", cmd)

    def test_custom_fuzz_is_passed_through_unchanged(self):
        cmd = gs.build_key_argv(Path("/a.png"), Path("/b.png"), fuzz="20%")
        self.assertEqual(cmd[cmd.index("-fuzz") + 1], "20%")


# --------------------------------------------------------------------------------------
# 3. The HTTP seam: post_json (monkeypatched urlopen), extract_b64_image, generate_raw_image.
# --------------------------------------------------------------------------------------

class TestPostJson(unittest.TestCase):
    def setUp(self):
        self._real_urlopen = gs.urllib.request.urlopen

    def tearDown(self):
        gs.urllib.request.urlopen = self._real_urlopen

    def test_success_returns_response_bytes(self):
        gs.urllib.request.urlopen = lambda req, timeout=None: _FakeResponse(b'{"ok": true}')
        result = gs.post_json("https://x", {"A": "b"}, b"{}")
        self.assertEqual(result, b'{"ok": true}')

    def test_request_carries_method_headers_and_body(self):
        seen = {}

        def fake_urlopen(request, timeout=None):
            seen["url"] = request.full_url
            seen["method"] = request.get_method()
            seen["auth"] = request.get_header("Authorization")
            seen["body"] = request.data
            return _FakeResponse(b"{}")

        gs.urllib.request.urlopen = fake_urlopen
        gs.post_json("https://x/y", {"Authorization": "Bearer k"}, b'{"a": 1}')
        self.assertEqual(seen["url"], "https://x/y")
        self.assertEqual(seen["method"], "POST")
        self.assertEqual(seen["auth"], "Bearer k")
        self.assertEqual(seen["body"], b'{"a": 1}')

    def test_http_error_becomes_api_error_never_a_raw_urllib_exception(self):
        def fake_urlopen(request, timeout=None):
            raise urllib.error.HTTPError(
                "https://x", 400, "Bad Request", None, io.BytesIO(b'{"error": "bad prompt"}'))

        gs.urllib.request.urlopen = fake_urlopen
        with self.assertRaises(gs.ApiError) as ctx:
            gs.post_json("https://x", {}, b"{}")
        self.assertIn("400", str(ctx.exception))

    def test_url_error_becomes_api_error(self):
        gs.urllib.request.urlopen = lambda request, timeout=None: (_ for _ in ()).throw(
            urllib.error.URLError("no route to host"))
        with self.assertRaises(gs.ApiError):
            gs.post_json("https://x", {}, b"{}")


class TestExtractB64Image(unittest.TestCase):
    def test_decodes_valid_response(self):
        raw = b"not really a png but bytes are bytes"
        response = json.dumps({"data": [{"b64_json": base64.b64encode(raw).decode("ascii")}]})
        self.assertEqual(gs.extract_b64_image(response.encode("utf-8")), raw)

    def test_malformed_json_is_api_error(self):
        with self.assertRaises(gs.ApiError):
            gs.extract_b64_image(b"not json at all")

    def test_missing_data_key_is_api_error(self):
        with self.assertRaises(gs.ApiError):
            gs.extract_b64_image(json.dumps({"nope": []}).encode("utf-8"))

    def test_empty_data_array_is_api_error(self):
        with self.assertRaises(gs.ApiError):
            gs.extract_b64_image(json.dumps({"data": []}).encode("utf-8"))

    def test_bad_base64_is_api_error(self):
        with self.assertRaises(gs.ApiError):
            gs.extract_b64_image(json.dumps({"data": [{"b64_json": "!!!not-base64!!!"}]}).encode())


class TestGenerateRawImage(unittest.TestCase):
    def setUp(self):
        self._real_post_json = gs.post_json

    def tearDown(self):
        gs.post_json = self._real_post_json

    def test_wires_payload_through_to_post_json_and_decodes_the_result(self):
        raw = b"scene-bytes"
        seen = {}

        def fake_post_json(url, headers, body, timeout=180):
            seen["url"] = url
            seen["headers"] = headers
            seen["payload"] = json.loads(body)
            return json.dumps({"data": [{"b64_json": base64.b64encode(raw).decode("ascii")}]}).encode()

        gs.post_json = fake_post_json
        result = gs.generate_raw_image(
            prompt="a room", model="gpt-image-2", size="2064x3040", quality="high",
            output_format="png", api_key="sk-test",
        )
        self.assertEqual(result, raw)
        self.assertEqual(seen["payload"]["prompt"], "a room")
        self.assertEqual(seen["headers"]["Authorization"], "Bearer sk-test")


# --------------------------------------------------------------------------------------
# 4. API key resolution — env first, then the key file; never prints/logs the value.
# --------------------------------------------------------------------------------------

class TestResolveApiKey(ScratchTestCase):
    def test_env_var_wins(self):
        key = gs.resolve_api_key(env={"OPENAI_API_KEY": "sk-env"}, key_file=self.work / "nope")
        self.assertEqual(key, "sk-env")

    def test_env_var_is_stripped(self):
        key = gs.resolve_api_key(env={"OPENAI_API_KEY": "  sk-env  \n"}, key_file=self.work / "nope")
        self.assertEqual(key, "sk-env")

    def test_falls_back_to_key_file_when_env_absent(self):
        key_file = self.work / "api-key"
        key_file.write_text("sk-file\n", encoding="utf-8")
        key = gs.resolve_api_key(env={}, key_file=key_file)
        self.assertEqual(key, "sk-file")

    def test_falls_back_to_key_file_when_env_blank(self):
        key_file = self.work / "api-key"
        key_file.write_text("sk-file", encoding="utf-8")
        key = gs.resolve_api_key(env={"OPENAI_API_KEY": ""}, key_file=key_file)
        self.assertEqual(key, "sk-file")

    def test_neither_present_names_both_options_and_never_a_key_value(self):
        with self.assertRaises(gs.InvocationError) as ctx:
            gs.resolve_api_key(env={}, key_file=self.work / "does-not-exist")
        message = str(ctx.exception)
        self.assertIn("OPENAI_API_KEY", message)
        self.assertIn("does-not-exist", message)

    def test_empty_key_file_also_falls_through_to_the_error(self):
        key_file = self.work / "api-key"
        key_file.write_text("   \n", encoding="utf-8")
        with self.assertRaises(gs.InvocationError):
            gs.resolve_api_key(env={}, key_file=key_file)


# --------------------------------------------------------------------------------------
# 5. ImageMagick invocation — subprocess.run monkeypatched, never actually executed.
# --------------------------------------------------------------------------------------

class TestKeyScene(ScratchTestCase):
    def test_runs_the_expected_argv_and_leaves_the_output_in_place(self):
        src = self.work / "raw.png"
        src.write_bytes(_make_png(4, 4))
        dst = self.work / "out.png"
        seen = {}
        real_run = gs.subprocess.run

        def fake_run(cmd, **kwargs):
            seen["cmd"] = cmd
            dst.write_bytes(_make_png(4, 4))
            class _R:
                returncode = 0
            return _R()

        gs.subprocess.run = fake_run
        try:
            gs.key_scene(src, dst, fuzz="12%")
        finally:
            gs.subprocess.run = real_run
        self.assertEqual(seen["cmd"][0], "magick")
        self.assertTrue(dst.exists())

    def test_called_process_error_becomes_external_tool_error(self):
        import subprocess as sp

        def fake_run(cmd, **kwargs):
            raise sp.CalledProcessError(1, cmd, stderr=b"boom")

        real_run = gs.subprocess.run
        gs.subprocess.run = fake_run
        try:
            with self.assertRaises(gs.ExternalToolError):
                gs.key_scene(self.work / "a.png", self.work / "b.png", fuzz="12%")
        finally:
            gs.subprocess.run = real_run

    def test_missing_binary_becomes_external_tool_error(self):
        def fake_run(cmd, **kwargs):
            raise FileNotFoundError("magick")

        real_run = gs.subprocess.run
        gs.subprocess.run = fake_run
        try:
            with self.assertRaises(gs.ExternalToolError):
                gs.key_scene(self.work / "a.png", self.work / "b.png", fuzz="12%")
        finally:
            gs.subprocess.run = real_run


class TestIdentifySize(ScratchTestCase):
    def test_parses_stdout(self):
        real_run = gs.subprocess.run

        class _R:
            stdout = "2064 3040\n"

        gs.subprocess.run = lambda cmd, **kwargs: _R()
        try:
            self.assertEqual(gs.identify_size(self.work / "x.png"), (2064, 3040))
        finally:
            gs.subprocess.run = real_run

    def test_missing_binary_becomes_external_tool_error(self):
        real_run = gs.subprocess.run

        def fake_run(cmd, **kwargs):
            raise FileNotFoundError("magick")

        gs.subprocess.run = fake_run
        try:
            with self.assertRaises(gs.ExternalToolError):
                gs.identify_size(self.work / "x.png")
        finally:
            gs.subprocess.run = real_run


# --------------------------------------------------------------------------------------
# 6. PNG dimension reading straight from bytes (no ImageMagick, mirrors the sibling renderer).
# --------------------------------------------------------------------------------------

class TestReadPngDimensions(unittest.TestCase):
    def test_reads_width_and_height(self):
        data = _make_png(2064, 3040)
        self.assertEqual(gs.read_png_dimensions(data), (2064, 3040))

    def test_bad_signature_raises_value_error(self):
        with self.assertRaises(ValueError):
            gs.read_png_dimensions(b"not a png")


# --------------------------------------------------------------------------------------
# 7. Size-match enforcement — never upscale; fail loudly instead.
# --------------------------------------------------------------------------------------

class TestEnsureSizeMatches(unittest.TestCase):
    def test_matching_size_is_silent(self):
        gs.ensure_size_matches((2064, 3040), (2064, 3040))  # must not raise

    def test_mismatch_raises_with_both_sizes_named(self):
        with self.assertRaises(gs.SizeMismatchError) as ctx:
            gs.ensure_size_matches((1024, 1024), (2064, 3040))
        message = str(ctx.exception)
        self.assertIn("1024x1024", message)
        self.assertIn("2064x3040", message)
        self.assertIn("upscal", message)  # "upscale"/"upscaling" — never silently resized


# --------------------------------------------------------------------------------------
# 8. default_raw_path — where the unkeyed image goes when --raw-out is not given.
# --------------------------------------------------------------------------------------

class TestDefaultRawPath(unittest.TestCase):
    def test_derives_a_sibling_of_out_with_raw_suffix(self):
        out = Path("/tmp/scenes/01-drawer.png")
        self.assertEqual(gs.default_raw_path(out, "png"), Path("/tmp/scenes/01-drawer.raw.png"))

    def test_extension_follows_output_format(self):
        out = Path("/tmp/scenes/01-drawer.png")
        self.assertEqual(gs.default_raw_path(out, "jpeg").suffix, ".jpg")
        self.assertEqual(gs.default_raw_path(out, "webp").suffix, ".webp")


# --------------------------------------------------------------------------------------
# 9. CLI: --dry-run touches neither network nor ImageMagick, and prints both artefacts.
# --------------------------------------------------------------------------------------

class TestDryRunCli(ScratchTestCase):
    def test_dry_run_prints_payload_and_argv_and_touches_nothing(self):
        restore_net = _poison("urllib.request.urlopen", gs.urllib.request, "urlopen")
        restore_run = _poison("subprocess.run", gs.subprocess, "run")
        out_path = self.work / "scene.png"
        try:
            code, out, err = self.run_main([
                "--dry-run", "--prompt", "test", "--out", str(out_path),
            ])
        finally:
            restore_net()
            restore_run()
        self.assertEqual(code, 0, err)
        self.assertIn('"model": "gpt-image-2"', out)
        self.assertIn('"prompt": "test"', out)
        self.assertIn('"size": "2064x3040"', out)
        self.assertIn("magick", out)
        self.assertIn("-transparent", out)
        self.assertIn("#FF00FF", out)
        self.assertIn("dry-run", out.lower())
        self.assertFalse(out_path.exists())

    def test_dry_run_respects_custom_flags(self):
        out_path = self.work / "scene.png"
        code, out, _err = self.run_main([
            "--dry-run", "--prompt", "a cosy room", "--out", str(out_path),
            "--model", "gpt-image-2", "--quality", "medium", "--size", "1024x1024",
            "--fuzz", "8%",
        ])
        self.assertEqual(code, 0)
        self.assertIn('"quality": "medium"', out)
        self.assertIn('"size": "1024x1024"', out)
        self.assertIn("8%", out)

    def test_dry_run_with_skip_generate_shows_no_payload_and_reuses_raw_path(self):
        raw = self.work / "already-generated.png"
        raw.write_bytes(_make_png(4, 4))
        out_path = self.work / "scene.png"
        restore_net = _poison("urllib.request.urlopen", gs.urllib.request, "urlopen")
        try:
            code, out, err = self.run_main([
                "--dry-run", "--skip-generate", str(raw), "--out", str(out_path),
            ])
        finally:
            restore_net()
        self.assertEqual(code, 0, err)
        self.assertNotIn('"model"', out)
        self.assertIn(str(raw), out)
        self.assertIn("magick", out)

    def test_dry_run_without_prompt_or_skip_generate_is_invocation_error(self):
        code, _out, err = self.run_main(["--dry-run", "--out", str(self.work / "x.png")])
        self.assertEqual(code, 2)
        self.assertIn("--prompt", err)

    def test_bad_size_is_invocation_error_even_in_dry_run(self):
        code, _out, err = self.run_main([
            "--dry-run", "--prompt", "x", "--out", str(self.work / "x.png"), "--size", "999x999",
        ])
        self.assertEqual(code, 2)
        self.assertTrue(err.strip())


# --------------------------------------------------------------------------------------
# 10. CLI: --skip-generate on the real (non-dry-run) path never calls the API.
# --------------------------------------------------------------------------------------

class TestSkipGenerateCli(ScratchTestCase):
    def test_skips_generation_and_keys_the_existing_raw_image(self):
        raw = self.work / "raw.png"
        raw.write_bytes(_make_png(2064, 3040))
        out_path = self.work / "scene.png"

        restore_net = _poison("urllib.request.urlopen", gs.urllib.request, "urlopen")

        def fake_run(cmd, **kwargs):
            out_path.write_bytes(_make_png(2064, 3040))
            class _R:
                returncode = 0
            return _R()

        real_run = gs.subprocess.run
        gs.subprocess.run = fake_run
        try:
            code, out, err = self.run_main([
                "--skip-generate", str(raw), "--out", str(out_path),
            ])
        finally:
            gs.subprocess.run = real_run
            restore_net()
        self.assertEqual(code, 0, err)
        self.assertIn(str(out_path), out)
        self.assertIn("2064x3040", out)

    def test_missing_skip_generate_path_is_invocation_error(self):
        code, _out, err = self.run_main([
            "--skip-generate", str(self.work / "does-not-exist.png"),
            "--out", str(self.work / "scene.png"),
        ])
        self.assertEqual(code, 2)
        self.assertIn("does-not-exist", err)


# --------------------------------------------------------------------------------------
# 11. CLI: the real generation path, fully monkeypatched (never touches network/ImageMagick).
# --------------------------------------------------------------------------------------

class TestGenerateCli(ScratchTestCase):
    def _patch_generate(self, image_bytes: bytes):
        real_generate = gs.generate_raw_image
        gs.generate_raw_image = lambda **kwargs: image_bytes
        return lambda: setattr(gs, "generate_raw_image", real_generate)

    def _patch_resolve_key(self):
        real_resolve = gs.resolve_api_key
        gs.resolve_api_key = lambda **kwargs: "sk-fake"
        return lambda: setattr(gs, "resolve_api_key", real_resolve)

    def test_full_success_writes_scene_and_cleans_up_default_raw_file(self):
        restore_key = self._patch_resolve_key()
        restore_gen = self._patch_generate(b"raw-bytes-stand-in")
        real_identify = gs.identify_size
        real_run = gs.subprocess.run
        out_path = self.work / "scene.png"

        gs.identify_size = lambda path: (2064, 3040)

        def fake_run(cmd, **kwargs):
            out_path.write_bytes(_make_png(2064, 3040))
            class _R:
                returncode = 0
            return _R()

        gs.subprocess.run = fake_run
        try:
            code, out, err = self.run_main(["--prompt", "a room", "--out", str(out_path)])
        finally:
            gs.subprocess.run = real_run
            gs.identify_size = real_identify
            restore_gen()
            restore_key()

        self.assertEqual(code, 0, err)
        self.assertIn(str(out_path), out)
        self.assertIn("2064x3040", out)
        default_raw = gs.default_raw_path(out_path, "png")
        self.assertFalse(default_raw.exists(), "the default raw file must be cleaned up")

    def test_raw_out_keeps_the_unkeyed_image(self):
        restore_key = self._patch_resolve_key()
        restore_gen = self._patch_generate(b"raw-bytes-stand-in")
        real_identify = gs.identify_size
        real_run = gs.subprocess.run
        out_path = self.work / "scene.png"
        raw_out = self.work / "kept-raw.png"

        gs.identify_size = lambda path: (2064, 3040)

        def fake_run(cmd, **kwargs):
            out_path.write_bytes(_make_png(2064, 3040))
            class _R:
                returncode = 0
            return _R()

        gs.subprocess.run = fake_run
        try:
            code, _out, err = self.run_main([
                "--prompt", "a room", "--out", str(out_path), "--raw-out", str(raw_out),
            ])
        finally:
            gs.subprocess.run = real_run
            gs.identify_size = real_identify
            restore_gen()
            restore_key()

        self.assertEqual(code, 0, err)
        self.assertTrue(raw_out.exists(), "an explicit --raw-out must survive the run")

    def test_size_mismatch_fails_loudly_and_never_keys_or_upscales(self):
        restore_key = self._patch_resolve_key()
        restore_gen = self._patch_generate(b"raw-bytes-stand-in")
        real_identify = gs.identify_size
        restore_run = _poison("subprocess.run", gs.subprocess, "run")
        out_path = self.work / "scene.png"

        gs.identify_size = lambda path: (1024, 1024)  # wrong — requested default is 2064x3040
        try:
            code, _out, err = self.run_main(["--prompt", "a room", "--out", str(out_path)])
        finally:
            gs.identify_size = real_identify
            restore_run()
            restore_gen()
            restore_key()

        self.assertEqual(code, 1)
        self.assertIn("1024x1024", err)
        self.assertIn("2064x3040", err)
        self.assertFalse(out_path.exists())

    def test_missing_api_key_is_invocation_error_and_never_calls_generate(self):
        def boom(**kwargs):
            raise AssertionError("resolve_api_key must be called before generate_raw_image")

        real_resolve = gs.resolve_api_key

        def fake_resolve(**kwargs):
            raise gs.InvocationError("no OpenAI API key found: set $OPENAI_API_KEY or ...")

        gs.resolve_api_key = fake_resolve
        restore_gen = self._patch_generate_poison()
        try:
            code, _out, err = self.run_main([
                "--prompt", "a room", "--out", str(self.work / "scene.png"),
            ])
        finally:
            gs.resolve_api_key = real_resolve
            restore_gen()

        self.assertEqual(code, 2)
        self.assertIn("OPENAI_API_KEY", err)

    def _patch_generate_poison(self):
        real_generate = gs.generate_raw_image

        def boom(**kwargs):
            raise AssertionError("generate_raw_image must not be called without an API key")

        gs.generate_raw_image = boom
        return lambda: setattr(gs, "generate_raw_image", real_generate)

    def test_missing_prompt_and_no_skip_generate_is_invocation_error(self):
        code, _out, err = self.run_main(["--out", str(self.work / "scene.png")])
        self.assertEqual(code, 2)
        self.assertIn("--prompt", err)

    def test_prompt_file_is_read_and_stripped(self):
        prompt_file = self.work / "prompt.txt"
        prompt_file.write_text("a lovely room\n", encoding="utf-8")
        restore_key = self._patch_resolve_key()
        seen = {}

        real_generate = gs.generate_raw_image

        def fake_generate(**kwargs):
            seen["prompt"] = kwargs["prompt"]
            return b"raw-bytes"

        gs.generate_raw_image = fake_generate
        real_identify = gs.identify_size
        gs.identify_size = lambda path: (2064, 3040)
        real_run = gs.subprocess.run
        out_path = self.work / "scene.png"

        def fake_run(cmd, **kwargs):
            out_path.write_bytes(_make_png(2064, 3040))
            class _R:
                returncode = 0
            return _R()

        gs.subprocess.run = fake_run
        try:
            code, _out, err = self.run_main([
                "--prompt-file", str(prompt_file), "--out", str(out_path),
            ])
        finally:
            gs.subprocess.run = real_run
            gs.identify_size = real_identify
            gs.generate_raw_image = real_generate
            restore_key()

        self.assertEqual(code, 0, err)
        self.assertEqual(seen["prompt"], "a lovely room")


class TestQualityDefaultIsCheap(unittest.TestCase):
    """Jan's workflow, 2026-09-12: "wir iterieren mit LOW ... DANN generieren wir die in HIGH."

    Composition is what the prompt loop is actually fighting — is the whole device in frame, is
    the top quarter empty, is the screen a flat magenta — and all three are judgeable at `low`.
    Paying for fidelity while the composition is still wrong is pure waste, and at 6.27M pixels
    per image that waste is real money over a prompt loop.

    So the default is the cheap one and `high` has to be typed. A forgotten flag should cost
    cents, never the other way round.
    """

    def test_default_quality_is_low_so_a_forgotten_flag_is_cheap(self):
        self.assertEqual(gs.DEFAULT_QUALITY, "low")

    def test_parser_default_matches(self):
        args = gs.build_parser().parse_args(["--prompt", "x", "--out", "/tmp/x.png"])
        self.assertEqual(args.quality, "low")

    def test_the_expensive_tiers_are_still_reachable_explicitly(self):
        for tier in ("high", "xhigh", "max"):
            with self.subTest(tier=tier):
                args = gs.build_parser().parse_args(
                    ["--prompt", "x", "--out", "/tmp/x.png", "--quality", tier])
                self.assertEqual(args.quality, tier)


if __name__ == "__main__":
    unittest.main()
