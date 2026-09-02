"""test_render_store_screenshots.py — unit tests for render-store-screenshots.py (AP-3, 9010).

Written FIRST per this repo's TDD policy: at the point this file was created,
`.claude/scripts/render-store-screenshots.py` did not exist, so every test below failed with
an import error. The implementation was then written until this file went green. See
`docs/traceability.md`-style discipline: a red run was captured before the first line of the
renderer existed, and is quoted in the AP-3 hand-off report rather than repeated here.

Run with:

    cd /Users/jan/dev/repos/Immich-Slideshow
    python3 -m unittest discover -s .claude/scripts/tests -v

(equivalently `python3 -m unittest .claude.scripts.tests.test_render_store_screenshots -v` from
the repo root, since Python 3's unittest discovery works on this tree without an `__init__.py`.)

Scope: PURE logic only. Chrome and ImageMagick are never invoked by these tests (FR-9010-25/26
gate the external tools behind a real render, which is an integration concern, not a unit one).
Covered here: manifest parsing and filter resolution, path resolution (including `captureRoot`
`~`-expansion and the `--capture-root` / `--scene SLOT=PATH` overrides), the `fit` ->
`preserveAspectRatio` mapping, id-based SVG substitution (scene/screenshot/headline, including
the "id absent -> no crash" case and the two/three-line tspan-cloning rule), `--check` defect
detection (one test per defect class from the spec's SC-9010-03 list), CLI exit codes, the PNG
fact reader, and the hand-written sRGB chunk injector.

Import mechanics: the module under test has a hyphenated filename, so it cannot be imported by
name (`import render-store-screenshots` is a syntax error). It is loaded once, by absolute path,
via `importlib.util.spec_from_file_location`. The real module guards all side effects behind
`if __name__ == "__main__": sys.exit(main())`, so `exec_module` here is inert — it defines
functions and module-level constants only, it does not touch the filesystem or invoke Chrome.

All fixtures this file writes go under `tmp/test-render-store-screenshots/` (FR-9010-28) and are
removed in `tearDown`/`tearDownClass`. Nothing is ever written to `Design/`.
"""

from __future__ import annotations

import contextlib
import io
import json
import shutil
import struct
import unittest
import zlib
from pathlib import Path

import importlib.util
import sys

TEST_FILE = Path(__file__).resolve()
ROOT = TEST_FILE.parents[3]
MODULE_PATH = TEST_FILE.parents[1] / "render-store-screenshots.py"
SCRATCH = ROOT / "tmp" / "test-render-store-screenshots"


def _load_module():
    spec = importlib.util.spec_from_file_location("render_store_screenshots", MODULE_PATH)
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


rss = _load_module()


# --------------------------------------------------------------------------------------
# Shared fixtures: a tiny but structurally faithful stand-in for templates/ipad/slot-03.svg,
# and a hand-rolled minimal PNG encoder so PNG-fact / sRGB-injection tests need no real files.
# --------------------------------------------------------------------------------------

SVG_NS = "http://www.w3.org/2000/svg"

FIXTURE_WITH_SCREENSHOT = f"""<svg xmlns="{SVG_NS}" width="100" height="140" viewBox="0 0 100 140">
  <image id="scene" x="0" y="0" width="100" height="140" preserveAspectRatio="xMidYMid slice" href=""/>
  <text id="headline" x="10" y="20" xml:space="preserve"><tspan x="10" dy="0">Headline line one</tspan><tspan x="10" dy="1.16em">Headline line two</tspan></text>
  <image id="screenshot" x="12" y="40" width="70" height="90" preserveAspectRatio="xMidYMid slice" href=""/>
</svg>"""

FIXTURE_NO_SCREENSHOT = f"""<svg xmlns="{SVG_NS}" width="100" height="140" viewBox="0 0 100 140">
  <image id="scene" x="0" y="0" width="100" height="140" preserveAspectRatio="xMidYMid slice" href=""/>
  <text id="headline" x="10" y="20" xml:space="preserve"><tspan x="10" dy="0">Headline line one</tspan><tspan x="10" dy="1.16em">Headline line two</tspan></text>
</svg>"""


def _png_chunk(tag: bytes, payload: bytes) -> bytes:
    return (
        struct.pack(">I", len(payload)) + tag + payload
        + struct.pack(">I", zlib.crc32(tag + payload) & 0xFFFFFFFF)
    )


def _make_png(width: int, height: int, *, color_type: int = 2, with_srgb: bool = False) -> bytes:
    """Hand-built minimal valid PNG, no Pillow / no third-party imaging (FR-9010-25)."""
    sig = b"\x89PNG\r\n\x1a\n"
    ihdr = struct.pack(">IIBBBBB", width, height, 8, color_type, 0, 0, 0)
    channels = {0: 1, 2: 3, 3: 1, 4: 2, 6: 4}[color_type]
    row = bytes([0]) + bytes([128]) * (width * channels)  # filter-type byte + flat fill
    idat = zlib.compress(row * height)
    chunks = [_png_chunk(b"IHDR", ihdr)]
    if with_srgb:
        chunks.append(_png_chunk(b"sRGB", bytes([0])))
    chunks.append(_png_chunk(b"IDAT", idat))
    chunks.append(_png_chunk(b"IEND", b""))
    return sig + b"".join(chunks)


def _iter_chunks(data: bytes):
    """Test-only chunk walker that keeps (tag, payload, crc) — the module's own parse_png only
    keeps tags, which is enough for the renderer but not enough to prove a CRC is correct."""
    i = 8
    out = []
    while i < len(data):
        length = struct.unpack(">I", data[i:i + 4])[0]
        tag = data[i + 4:i + 8]
        payload = data[i + 8:i + 8 + length]
        crc = struct.unpack(">I", data[i + 8 + length:i + 12 + length])[0]
        out.append((tag, payload, crc))
        i += 12 + length
        if tag == b"IEND":
            break
    return out


def _small_manifest(**overrides) -> dict:
    manifest = {
        "locales": ["de", "en"],
        "devices": {
            "ipad": {"label": "iPad", "width": 100, "height": 140},
            "iphone": {"label": "iPhone", "width": 60, "height": 130},
        },
        "captureRoot": str(SCRATCH / "captures"),
        "slots": [
            {
                "id": "01-alpha",
                "type": "ui",
                "template": "slot-01.svg",
                "scene": "01-alpha.jpg",
                "capture": "01-alpha.png",
                "fit": "cover",
                "headline": {"de": ["Eins"], "en": ["One"]},
            },
            {
                "id": "02-beta",
                "type": "ui",
                "template": "slot-02.svg",
                "scene": "02-beta.jpg",
                "capture": "02-beta.png",
                "fit": "contain",
                "headline": {"de": ["Zwei"], "en": ["Two"]},
            },
        ],
    }
    manifest.update(overrides)
    return manifest


def _write_manifest_tree(root: Path, manifest: dict, *, with_assets: bool = True) -> Path:
    """Materialise a manifest plus (optionally) every template/scene/capture file it references,
    so path-resolution and --check tests can run against a real, self-contained tmp/ tree.

    `root` plays the role of the module's `ROOT` constant: templates/scenes are nested under
    `<root>/Design/AppStore/...`, exactly as `resolve_slot_paths` fixes it (that nesting is
    NOT configurable per the README's path contract — only `captureRoot` and `--scene` are).
    The manifest file itself is written directly under `root`, since `--manifest` is a plain
    explicit path unrelated to that fixed nesting.
    """
    design = root / "Design" / "AppStore"
    design.mkdir(parents=True, exist_ok=True)
    (design / "templates").mkdir(exist_ok=True)
    (design / "scenes").mkdir(exist_ok=True)
    captures = Path(manifest["captureRoot"])
    for device in manifest["devices"]:
        (design / "templates" / device).mkdir(parents=True, exist_ok=True)
        (design / "scenes" / device).mkdir(parents=True, exist_ok=True)
        for locale in manifest["locales"]:
            (captures / device / locale).mkdir(parents=True, exist_ok=True)
    if with_assets:
        for slot in manifest["slots"]:
            for device in manifest["devices"]:
                svg = FIXTURE_WITH_SCREENSHOT if slot.get("capture") else FIXTURE_NO_SCREENSHOT
                (design / "templates" / device / slot["template"]).write_text(svg, encoding="utf-8")
                (design / "scenes" / device / slot["scene"]).write_bytes(_make_png(4, 4))
                if slot.get("capture"):
                    for locale in manifest["locales"]:
                        (captures / device / locale / slot["capture"]).write_bytes(_make_png(4, 4))
    manifest_path = root / "content.json"
    manifest_path.write_text(json.dumps(manifest), encoding="utf-8")
    return manifest_path


class ScratchTestCase(unittest.TestCase):
    """Gives every test its own tmp/ subdirectory, torn down afterwards."""

    def setUp(self):
        self.work = SCRATCH / self.__class__.__name__ / self._testMethodName
        if self.work.exists():
            shutil.rmtree(self.work)
        self.work.mkdir(parents=True)

    def tearDown(self):
        shutil.rmtree(self.work, ignore_errors=True)

    def run_main(self, argv: list[str], *, root: Path | None = None) -> tuple[int, str, str]:
        out, err = io.StringIO(), io.StringIO()
        kwargs = {} if root is None else {"root": root}
        with contextlib.redirect_stdout(out), contextlib.redirect_stderr(err):
            code = rss.main(argv, **kwargs)
        return code, out.getvalue(), err.getvalue()


# --------------------------------------------------------------------------------------
# 1. Manifest parsing / filter resolution
# --------------------------------------------------------------------------------------

class TestManifestParsing(unittest.TestCase):
    def test_no_filters_returns_everything_in_manifest_order(self):
        manifest = _small_manifest()
        devices, locales, slots = rss.resolve_filters(manifest, [], [], [])
        self.assertEqual(devices, ["ipad", "iphone"])
        self.assertEqual(locales, ["de", "en"])
        self.assertEqual([s["id"] for s in slots], ["01-alpha", "02-beta"])

    def test_slot_filter_preserves_manifest_array_order_not_flag_order(self):
        manifest = _small_manifest()
        # Filters given in reverse order; the result must still follow the manifest's own
        # array order, since that order IS App Store display order and must survive filtering.
        _, _, slots = rss.resolve_filters(manifest, [], [], ["02-beta", "01-alpha"])
        self.assertEqual([s["id"] for s in slots], ["01-alpha", "02-beta"])

    def test_device_and_locale_filters_narrow_the_result(self):
        manifest = _small_manifest()
        devices, locales, _ = rss.resolve_filters(manifest, ["iphone"], ["de"], [])
        self.assertEqual(devices, ["iphone"])
        self.assertEqual(locales, ["de"])

    def test_unknown_device_raises_invocation_error(self):
        manifest = _small_manifest()
        with self.assertRaises(rss.InvocationError):
            rss.resolve_filters(manifest, ["macos"], [], [])

    def test_unknown_locale_raises_invocation_error(self):
        manifest = _small_manifest()
        with self.assertRaises(rss.InvocationError):
            rss.resolve_filters(manifest, [], ["fr"], [])

    def test_unknown_slot_raises_invocation_error(self):
        manifest = _small_manifest()
        with self.assertRaises(rss.InvocationError):
            rss.resolve_filters(manifest, [], [], ["99-nope"])


# --------------------------------------------------------------------------------------
# 2. Path resolution
# --------------------------------------------------------------------------------------

class TestPathResolution(ScratchTestCase):
    def test_template_scene_capture_paths(self):
        manifest = _small_manifest()
        slot = manifest["slots"][0]
        paths = rss.resolve_slot_paths(
            root=ROOT, capture_root=Path(manifest["captureRoot"]),
            device="ipad", locale="en", slot=slot, scene_overrides={},
        )
        self.assertEqual(paths.template, ROOT / "Design/AppStore/templates/ipad/slot-01.svg")
        self.assertEqual(paths.scene, ROOT / "Design/AppStore/scenes/ipad/01-alpha.jpg")
        self.assertEqual(paths.capture, Path(manifest["captureRoot"]) / "ipad/en/01-alpha.png")

    def test_capture_root_tilde_expansion(self):
        expanded = rss.expand_capture_root("~/Library/x")
        self.assertEqual(expanded, Path.home() / "Library" / "x")
        self.assertTrue(expanded.is_absolute())

    def test_capture_root_cli_override_via_list(self):
        manifest = _small_manifest()
        manifest_path = _write_manifest_tree(self.work / "authoring", manifest)
        override_root = self.work / "override-captures"
        for locale in manifest["locales"]:
            d = override_root / "ipad" / locale
            d.mkdir(parents=True)
            (d / "01-alpha.png").write_bytes(_make_png(4, 4))

        code, out, err = self.run_main([
            "--list", "--manifest", str(manifest_path),
            "--device", "ipad", "--slot", "01-alpha",
            "--capture-root", str(override_root),
        ])
        self.assertEqual(code, 0, err)
        self.assertIn(str(override_root / "ipad" / "en" / "01-alpha.png"), out)

    def test_scene_override_replaces_design_scene_path(self):
        manifest = _small_manifest()
        manifest_path = _write_manifest_tree(self.work / "authoring", manifest)
        override_scene = self.work / "placeholder.jpg"
        override_scene.write_bytes(_make_png(4, 4))

        code, out, err = self.run_main([
            "--list", "--manifest", str(manifest_path),
            "--device", "ipad", "--slot", "01-alpha",
            "--scene", f"01-alpha={override_scene}",
        ])
        self.assertEqual(code, 0, err)
        self.assertIn(str(override_scene), out)
        self.assertNotIn("scenes/ipad/01-alpha.jpg", out)

    def test_scene_override_missing_path_is_invocation_error(self):
        manifest = _small_manifest()
        manifest_path = _write_manifest_tree(self.work / "authoring", manifest)
        missing = self.work / "does-not-exist.jpg"

        code, out, err = self.run_main([
            "--check", "--manifest", str(manifest_path),
            "--scene", f"01-alpha={missing}",
        ])
        self.assertEqual(code, 2)
        self.assertIn(str(missing), err)


class TestOutputPathResolution(unittest.TestCase):
    """A relative `--out`/`--work` used to reach `Path.as_uri()` unresolved and crash with
    `ValueError: relative path can't be expressed as a file URI` (found by an independent
    verification pass against a real render, not by these unit tests — Chrome is not invoked
    here). `resolve_output_dirs` is the pure, directly-testable seam the fix hangs off."""

    def test_relative_paths_are_resolved_to_absolute_against_cwd(self):
        out, work = rss.resolve_output_dirs("tmp/rel-out", "tmp/rel-work")
        self.assertTrue(out.is_absolute(), out)
        self.assertTrue(work.is_absolute(), work)
        self.assertEqual(out, Path.cwd() / "tmp" / "rel-out")
        self.assertEqual(work, Path.cwd() / "tmp" / "rel-work")

    def test_absolute_paths_pass_through_unchanged(self):
        # Compared against Path(...).resolve() rather than the literal string: on macOS /tmp
        # is itself a symlink to /private/tmp, so correct resolution legitimately rewrites it
        # — that is resolve()'s job, not a bug. What must hold is idempotence: resolving an
        # already-resolved absolute path is a no-op beyond symlink normalisation.
        out, work = rss.resolve_output_dirs("/tmp/abs-out", "/tmp/abs-work")
        self.assertEqual(out, Path("/tmp/abs-out").resolve())
        self.assertEqual(work, Path("/tmp/abs-work").resolve())
        self.assertTrue(out.is_absolute())
        self.assertTrue(work.is_absolute())

    def test_tilde_is_expanded_before_resolving(self):
        out, _work = rss.resolve_output_dirs("~/scratch-out", "/tmp/abs-work")
        self.assertEqual(out, Path.home() / "scratch-out")


# --------------------------------------------------------------------------------------
# 3. `fit` -> `preserveAspectRatio`
# --------------------------------------------------------------------------------------

class TestFitMapping(unittest.TestCase):
    def test_cover(self):
        self.assertEqual(rss.preserve_aspect_ratio("cover"), "xMidYMid slice")

    def test_contain(self):
        self.assertEqual(rss.preserve_aspect_ratio("contain"), "xMidYMid meet")

    def test_fill(self):
        self.assertEqual(rss.preserve_aspect_ratio("fill"), "none")

    def test_unknown_fit_rejected(self):
        with self.assertRaises(ValueError):
            rss.preserve_aspect_ratio("stretch")


# --------------------------------------------------------------------------------------
# 4. Id substitution on a fixture SVG
# --------------------------------------------------------------------------------------

class TestIdSubstitution(unittest.TestCase):
    def _parse(self, xml_text: str):
        import xml.etree.ElementTree as ET
        return ET.fromstring(xml_text)

    def test_scene_href_set_to_data_uri(self):
        import xml.etree.ElementTree as ET
        root = self._parse(FIXTURE_WITH_SCREENSHOT)
        rss.substitute(root, scene_uri="data:image/jpeg;base64,AAAA",
                        screenshot_uri="data:image/png;base64,BBBB", fit="cover", lines=["X"])
        scene = rss.by_id(root, "scene")
        self.assertEqual(scene.get("href"), "data:image/jpeg;base64,AAAA")

    def test_screenshot_href_and_par_set(self):
        root = self._parse(FIXTURE_WITH_SCREENSHOT)
        rss.substitute(root, scene_uri="data:image/jpeg;base64,AAAA",
                        screenshot_uri="data:image/png;base64,BBBB", fit="contain", lines=["X"])
        shot = rss.by_id(root, "screenshot")
        self.assertEqual(shot.get("href"), "data:image/png;base64,BBBB")
        self.assertEqual(shot.get("preserveAspectRatio"), "xMidYMid meet")

    def test_screenshot_absent_does_not_crash(self):
        root = self._parse(FIXTURE_NO_SCREENSHOT)
        # Must not raise, whether or not a screenshot uri is available.
        rss.substitute(root, scene_uri="data:image/jpeg;base64,AAAA",
                        screenshot_uri=None, fit="cover", lines=["X"])
        self.assertIsNone(rss.by_id(root, "screenshot"))

    def test_screenshot_element_present_but_no_capture_data_raises(self):
        root = self._parse(FIXTURE_WITH_SCREENSHOT)
        with self.assertRaises(ValueError):
            rss.substitute(root, scene_uri="data:image/jpeg;base64,AAAA",
                            screenshot_uri=None, fit="cover", lines=["X"])

    def test_one_line_headline_uses_only_first_tspan(self):
        import xml.etree.ElementTree as ET
        root = self._parse(FIXTURE_WITH_SCREENSHOT)
        rss.substitute(root, scene_uri="u", screenshot_uri="v", fit="cover", lines=["Only line"])
        text = rss.by_id(root, "headline")
        tspans = [c for c in list(text) if c.tag == f"{{{SVG_NS}}}tspan"]
        self.assertEqual(len(tspans), 1)
        self.assertEqual(tspans[0].text, "Only line")
        self.assertEqual(tspans[0].get("dy"), "0")
        self.assertEqual(tspans[0].get("x"), "10")

    def test_two_line_headline_second_tspan_carries_template_dy(self):
        root = self._parse(FIXTURE_WITH_SCREENSHOT)
        rss.substitute(root, scene_uri="u", screenshot_uri="v", fit="cover", lines=["A", "B"])
        text = rss.by_id(root, "headline")
        tspans = [c for c in list(text) if c.tag == f"{{{SVG_NS}}}tspan"]
        self.assertEqual([t.text for t in tspans], ["A", "B"])
        self.assertEqual(tspans[0].get("dy"), "0")
        self.assertEqual(tspans[1].get("dy"), "1.16em")

    def test_three_line_headline_third_tspan_clones_second_attrs(self):
        root = self._parse(FIXTURE_WITH_SCREENSHOT)
        rss.substitute(root, scene_uri="u", screenshot_uri="v", fit="cover", lines=["A", "B", "C"])
        text = rss.by_id(root, "headline")
        tspans = [c for c in list(text) if c.tag == f"{{{SVG_NS}}}tspan"]
        self.assertEqual([t.text for t in tspans], ["A", "B", "C"])
        self.assertEqual(tspans[0].attrib, {"x": "10", "dy": "0"})
        self.assertEqual(tspans[1].attrib, {"x": "10", "dy": "1.16em"})
        self.assertEqual(tspans[2].attrib, tspans[1].attrib)

    def test_scene_preserve_aspect_ratio_unchanged_regardless_of_fit(self):
        for fit in ("cover", "contain", "fill"):
            root = self._parse(FIXTURE_WITH_SCREENSHOT)
            rss.substitute(root, scene_uri="u", screenshot_uri="v", fit=fit, lines=["X"])
            scene = rss.by_id(root, "scene")
            self.assertEqual(scene.get("preserveAspectRatio"), "xMidYMid slice", fit)

    def test_no_namespace_prefix_leak_in_serialized_output(self):
        import xml.etree.ElementTree as ET
        root = self._parse(FIXTURE_WITH_SCREENSHOT)
        rss.substitute(root, scene_uri="u", screenshot_uri="v", fit="cover", lines=["A", "B"])
        text = ET.tostring(root, encoding="unicode")
        self.assertNotIn("ns0:", text)


# --------------------------------------------------------------------------------------
# 5. `--check` defect detection
# --------------------------------------------------------------------------------------

class TestCheckDetection(ScratchTestCase):
    def test_clean_manifest_has_no_problems(self):
        manifest = _small_manifest()
        manifest_path = _write_manifest_tree(self.work / "tree", manifest)
        code, out, err = self.run_main(["--check", "--manifest", str(manifest_path)], root=self.work / "tree")
        self.assertEqual(code, 0, out + err)

    def test_missing_template_detected_and_named(self):
        manifest = _small_manifest()
        manifest_path = _write_manifest_tree(self.work / "tree", manifest)
        (self.work / "tree" / "Design" / "AppStore" / "templates" / "ipad" / "slot-01.svg").unlink()
        code, out, err = self.run_main(["--check", "--manifest", str(manifest_path)], root=self.work / "tree")
        self.assertEqual(code, 1)
        self.assertIn("missing template", out)
        self.assertIn("slot-01.svg", out)

    def test_missing_scene_detected_and_named(self):
        manifest = _small_manifest()
        manifest_path = _write_manifest_tree(self.work / "tree", manifest)
        (self.work / "tree" / "Design" / "AppStore" / "scenes" / "ipad" / "01-alpha.jpg").unlink()
        code, out, err = self.run_main(["--check", "--manifest", str(manifest_path)], root=self.work / "tree")
        self.assertEqual(code, 1)
        self.assertIn("missing scene", out)
        self.assertIn("01-alpha.jpg", out)

    def test_missing_capture_detected_and_named(self):
        manifest = _small_manifest()
        manifest_path = _write_manifest_tree(self.work / "tree", manifest)
        (Path(manifest["captureRoot"]) / "ipad" / "en" / "01-alpha.png").unlink()
        code, out, err = self.run_main(["--check", "--manifest", str(manifest_path)], root=self.work / "tree")
        self.assertEqual(code, 1)
        self.assertIn("missing capture", out)
        self.assertIn("01-alpha.png", out)

    def test_unknown_fit_value_detected(self):
        manifest = _small_manifest()
        manifest["slots"][0]["fit"] = "zoom"
        manifest_path = _write_manifest_tree(self.work / "tree", manifest)
        code, out, err = self.run_main(["--check", "--manifest", str(manifest_path)], root=self.work / "tree")
        self.assertEqual(code, 1)
        self.assertIn("01-alpha", out)
        self.assertIn("fit", out)
        self.assertIn("zoom", out)

    def test_missing_locale_in_headline_detected(self):
        manifest = _small_manifest()
        del manifest["slots"][0]["headline"]["en"]
        manifest_path = _write_manifest_tree(self.work / "tree", manifest)
        code, out, err = self.run_main(["--check", "--manifest", str(manifest_path)], root=self.work / "tree")
        self.assertEqual(code, 1)
        self.assertIn("01-alpha", out)
        self.assertIn("en", out)
        self.assertIn("headline", out)

    def test_empty_headline_line_list_detected(self):
        manifest = _small_manifest()
        manifest["slots"][0]["headline"]["en"] = []
        manifest_path = _write_manifest_tree(self.work / "tree", manifest)
        code, out, err = self.run_main(["--check", "--manifest", str(manifest_path)], root=self.work / "tree")
        self.assertEqual(code, 1)
        self.assertIn("01-alpha", out)

    def test_malformed_perspective_wrong_point_count_detected(self):
        manifest = _small_manifest()
        manifest["slots"][0]["perspective"] = [[0, 0], [1, 1]]
        manifest_path = _write_manifest_tree(self.work / "tree", manifest)
        code, out, err = self.run_main(["--check", "--manifest", str(manifest_path)], root=self.work / "tree")
        self.assertEqual(code, 1)
        self.assertIn("perspective", out)
        self.assertIn("01-alpha", out)

    def test_malformed_perspective_non_numeric_detected(self):
        manifest = _small_manifest()
        manifest["slots"][0]["perspective"] = [[0, 0], [1, 1], [2, "two"], [3, 3]]
        manifest_path = _write_manifest_tree(self.work / "tree", manifest)
        code, out, err = self.run_main(["--check", "--manifest", str(manifest_path)], root=self.work / "tree")
        self.assertEqual(code, 1)
        self.assertIn("perspective", out)

    def test_duplicate_slot_id_detected(self):
        manifest = _small_manifest()
        manifest["slots"][1]["id"] = "01-alpha"
        manifest_path = _write_manifest_tree(self.work / "tree", manifest)
        code, out, err = self.run_main(["--check", "--manifest", str(manifest_path)], root=self.work / "tree")
        self.assertEqual(code, 1)
        self.assertIn("duplicate", out)
        self.assertIn("01-alpha", out)

    def test_null_or_empty_slot_id_detected(self):
        """Presence is not enough: `id: null` used to pass --check, then render to `None.png`."""
        for bad in (None, ""):
            with self.subTest(id=bad):
                manifest = _small_manifest()
                manifest["slots"][0]["id"] = bad
                manifest_path = _write_manifest_tree(self.work / "tree", manifest)
                code, out, err = self.run_main(["--check", "--manifest", str(manifest_path)],
                                               root=self.work / "tree")
                self.assertEqual(code, 1)
                self.assertIn("id", out)

    def test_non_string_asset_reference_detected_without_crashing(self):
        """A non-string template/scene/capture used to raise TypeError out of path building,
        producing no `check:` output at all — the opposite of "reports every problem"."""
        for key in ("template", "scene", "capture"):
            with self.subTest(key=key):
                # Lay the tree down from a VALID manifest first — the helper builds asset
                # paths out of these very values — then corrupt only the JSON on disk.
                manifest_path = _write_manifest_tree(self.work / "tree", _small_manifest())
                broken = _small_manifest()
                broken["slots"][0][key] = 7
                manifest_path.write_text(json.dumps(broken), encoding="utf-8")
                code, out, err = self.run_main(["--check", "--manifest", str(manifest_path)],
                                               root=self.work / "tree")
                self.assertEqual(code, 1)
                self.assertIn(key, out)
                self.assertIn("check:", out)

    def test_non_string_headline_line_detected(self):
        """The worst false green: --check passed, then the render died serialising an int."""
        manifest = _small_manifest()
        manifest["slots"][0]["headline"]["en"] = [123]
        manifest_path = _write_manifest_tree(self.work / "tree", manifest)
        code, out, err = self.run_main(["--check", "--manifest", str(manifest_path)],
                                       root=self.work / "tree")
        self.assertEqual(code, 1)
        self.assertIn("headline", out)
        self.assertIn("01-alpha", out)

    def test_check_reports_every_problem_not_just_the_first(self):
        manifest = _small_manifest()
        manifest["slots"][0]["fit"] = "zoom"
        del manifest["slots"][1]["headline"]["de"]
        manifest_path = _write_manifest_tree(self.work / "tree", manifest)
        (self.work / "tree" / "Design" / "AppStore" / "templates" / "ipad" / "slot-01.svg").unlink()
        code, out, err = self.run_main(["--check", "--manifest", str(manifest_path)], root=self.work / "tree")
        self.assertEqual(code, 1)
        self.assertIn("fit", out)
        self.assertIn("headline", out)
        self.assertIn("missing template", out)

    def test_check_renders_nothing(self):
        manifest = _small_manifest()
        manifest["slots"][0]["fit"] = "zoom"
        manifest_path = _write_manifest_tree(self.work / "tree", manifest)
        out_dir = self.work / "out"
        self.run_main(["--check", "--manifest", str(manifest_path), "--out", str(out_dir)], root=self.work / "tree")
        self.assertFalse(out_dir.exists())


# --------------------------------------------------------------------------------------
# 6. Exit codes
# --------------------------------------------------------------------------------------

class TestExitCodes(ScratchTestCase):
    def test_check_clean_is_zero(self):
        manifest = _small_manifest()
        manifest_path = _write_manifest_tree(self.work / "tree", manifest)
        code, _, _ = self.run_main(["--check", "--manifest", str(manifest_path)], root=self.work / "tree")
        self.assertEqual(code, 0)

    def test_check_broken_is_one(self):
        manifest = _small_manifest()
        manifest["slots"][0]["fit"] = "zoom"
        manifest_path = _write_manifest_tree(self.work / "tree", manifest)
        code, _, _ = self.run_main(["--check", "--manifest", str(manifest_path)], root=self.work / "tree")
        self.assertEqual(code, 1)

    def test_unknown_device_is_two(self):
        manifest = _small_manifest()
        manifest_path = _write_manifest_tree(self.work / "tree", manifest)
        code, _, err = self.run_main(["--check", "--manifest", str(manifest_path), "--device", "macos"])
        self.assertEqual(code, 2)
        self.assertIn("macos", err)

    def test_malformed_json_manifest_is_two(self):
        bad = self.work / "broken.json"
        bad.write_text("{not valid json", encoding="utf-8")
        code, _, err = self.run_main(["--check", "--manifest", str(bad)])
        self.assertEqual(code, 2)
        self.assertIn(str(bad), err)

    def test_unreadable_manifest_path_is_two(self):
        code, _, err = self.run_main(["--check", "--manifest", str(self.work / "nope.json")])
        self.assertEqual(code, 2)


# --------------------------------------------------------------------------------------
# 7. PNG fact reader
# --------------------------------------------------------------------------------------

class TestPngFacts(unittest.TestCase):
    def test_dimensions_and_color_type(self):
        data = _make_png(37, 21, color_type=2)
        facts = rss.parse_png(data)
        self.assertEqual(facts["width"], 37)
        self.assertEqual(facts["height"], 21)
        self.assertEqual(facts["color_type"], 2)
        self.assertEqual(facts["bit_depth"], 8)

    def test_srgb_chunk_absent_by_default(self):
        data = _make_png(4, 4, with_srgb=False)
        facts = rss.parse_png(data)
        self.assertNotIn("sRGB", facts["chunks"])

    def test_srgb_chunk_detected_when_present(self):
        data = _make_png(4, 4, with_srgb=True)
        facts = rss.parse_png(data)
        self.assertIn("sRGB", facts["chunks"])

    def test_idat_not_listed_as_a_chunk(self):
        data = _make_png(4, 4)
        facts = rss.parse_png(data)
        self.assertNotIn("IDAT", facts["chunks"])
        self.assertIn("IHDR", facts["chunks"])
        self.assertIn("IEND", facts["chunks"])

    def test_png_facts_from_file_includes_sha256(self):
        path = SCRATCH / "TestPngFacts" / "one.png"
        path.parent.mkdir(parents=True, exist_ok=True)
        data = _make_png(4, 4)
        path.write_bytes(data)
        try:
            facts = rss.png_facts(path)
            self.assertEqual(facts["width"], 4)
            self.assertIn("sha256", facts)
            self.assertEqual(len(facts["sha256"]), 64)
        finally:
            shutil.rmtree(SCRATCH / "TestPngFacts", ignore_errors=True)


# --------------------------------------------------------------------------------------
# 8. sRGB chunk injector
# --------------------------------------------------------------------------------------

class TestSrgbInjection(unittest.TestCase):
    def test_inserts_immediately_after_ihdr(self):
        data = _make_png(4, 4, with_srgb=False)
        patched = rss.add_srgb_chunk(data)
        chunks = _iter_chunks(patched)
        tags = [tag for tag, _payload, _crc in chunks]
        self.assertEqual(tags[0], b"IHDR")
        self.assertEqual(tags[1], b"sRGB")

    def test_crc_is_correct(self):
        data = _make_png(4, 4, with_srgb=False)
        patched = rss.add_srgb_chunk(data)
        for tag, payload, crc in _iter_chunks(patched):
            if tag == b"sRGB":
                self.assertEqual(crc, zlib.crc32(tag + payload) & 0xFFFFFFFF)
                break
        else:
            self.fail("no sRGB chunk found after injection")

    def test_result_parses_back_with_srgb_in_chunks(self):
        data = _make_png(4, 4, with_srgb=False)
        patched = rss.add_srgb_chunk(data)
        facts = rss.parse_png(patched)
        self.assertIn("sRGB", facts["chunks"])
        # Injection must not corrupt the pixel geometry facts.
        self.assertEqual(facts["width"], 4)
        self.assertEqual(facts["height"], 4)

    def test_payload_is_rendering_intent_zero_by_default(self):
        data = _make_png(4, 4, with_srgb=False)
        patched = rss.add_srgb_chunk(data)
        for tag, payload, _crc in _iter_chunks(patched):
            if tag == b"sRGB":
                self.assertEqual(payload, bytes([0]))
                break
        else:
            self.fail("no sRGB chunk found after injection")


def tearDownModule():
    shutil.rmtree(SCRATCH, ignore_errors=True)


if __name__ == "__main__":
    unittest.main()
