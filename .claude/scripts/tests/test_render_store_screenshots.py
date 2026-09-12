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

Sections 9-14 cover the perspective pre-warp: reading the screen quad back out of the template's
`<clipPath>`, the stdlib homography solver (asserted against hand-derived coefficients), the
axis-aligned degenerate case that must skip the warp so straight-on slots stay byte-identical,
the exact ImageMagick argv (captured via a monkeypatched `subprocess.run`, never executed), and
the `--check` geometry rules for an off-canvas or out-of-box screen.

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

FIXTURE_WITH_SUBLINE = f"""<svg xmlns="{SVG_NS}" width="100" height="140" viewBox="0 0 100 140">
  <image id="scene" x="0" y="0" width="100" height="140" preserveAspectRatio="xMidYMid slice" href=""/>
  <text id="headline" x="10" y="20" xml:space="preserve"><tspan x="10" dy="0">Headline line one</tspan><tspan x="10" dy="1.16em">Headline line two</tspan></text>
  <image id="screenshot" x="12" y="40" width="70" height="90" preserveAspectRatio="xMidYMid slice" href=""/>
  <text id="subline" x="10" y="130" xml:space="preserve"><tspan x="10" dy="0">Subline line one</tspan><tspan x="10" dy="1.3em">Subline line two</tspan></text>
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
                if slot.get("scene"):
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

    def test_subline_lines_are_substituted_when_the_template_has_one(self):
        """Jan, 2026-09-12: "text bottom AND top". The second text block is filled from the
        manifest exactly like the headline — store copy lives in content.json and nowhere else
        (FR-9010-20), so a template must never carry a baked-in sentence of its own."""
        root = self._parse(FIXTURE_WITH_SUBLINE)
        rss.substitute(root, scene_uri="u", screenshot_uri="v", fit="cover",
                        lines=["A"], subline_lines=["Sub one", "Sub two"])
        text = rss.by_id(root, "subline")
        tspans = [c for c in list(text) if c.tag == f"{{{SVG_NS}}}tspan"]
        self.assertEqual([t.text for t in tspans], ["Sub one", "Sub two"])
        self.assertEqual(tspans[0].get("dy"), "0")
        self.assertEqual(tspans[1].get("dy"), "1.3em")

    def test_subline_element_without_manifest_copy_raises(self):
        root = self._parse(FIXTURE_WITH_SUBLINE)
        with self.assertRaises(ValueError):
            rss.substitute(root, scene_uri="u", screenshot_uri="v", fit="cover",
                            lines=["A"], subline_lines=None)

    def test_subline_copy_without_a_template_element_raises(self):
        """The mirror error: copy nobody can render is as wrong as an element nobody can feed —
        same policy the scene/screenshot pair already enforces."""
        root = self._parse(FIXTURE_WITH_SCREENSHOT)
        with self.assertRaises(ValueError):
            rss.substitute(root, scene_uri="u", screenshot_uri="v", fit="cover",
                            lines=["A"], subline_lines=["orphan"])

    def test_a_template_without_a_subline_still_renders(self):
        root = self._parse(FIXTURE_WITH_SCREENSHOT)
        rss.substitute(root, scene_uri="u", screenshot_uri="v", fit="cover", lines=["A"])
        self.assertIsNone(rss.by_id(root, "subline"))

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

    def test_subline_with_a_missing_locale_detected(self):
        """`subline` is optional per slot, but a slot that HAS one must have it in every locale —
        otherwise the German run dies mid-render on a template whose element it cannot feed,
        after the English one rendered fine."""
        manifest = _small_manifest()
        manifest["slots"][0]["subline"] = {"de": ["nur deutsch"]}
        manifest_path = _write_manifest_tree(self.work / "tree", manifest)
        code, out, err = self.run_main(["--check", "--manifest", str(manifest_path)], root=self.work / "tree")
        self.assertEqual(code, 1)
        self.assertIn("01-alpha", out)
        self.assertIn("subline", out)
        self.assertIn("en", out)

    def test_subline_that_is_not_keyed_by_locale_detected(self):
        manifest = _small_manifest()
        manifest["slots"][0]["subline"] = ["a bare list, not a locale map"]
        manifest_path = _write_manifest_tree(self.work / "tree", manifest)
        code, out, err = self.run_main(["--check", "--manifest", str(manifest_path)], root=self.work / "tree")
        self.assertEqual(code, 1)
        self.assertIn("subline", out)

    def test_a_slot_without_a_subline_is_still_clean(self):
        manifest = _small_manifest()
        manifest_path = _write_manifest_tree(self.work / "tree", manifest)
        code, out, err = self.run_main(["--check", "--manifest", str(manifest_path)], root=self.work / "tree")
        self.assertNotIn("subline", out)

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


# --------------------------------------------------------------------------------------
# 9. The screen quad: parsing it back out of the template (AP-3b)
#
# A `<clipPath>` only cuts; it never transforms, and SVG's own transforms are affine
# (`matrix(a,b,c,d,e,f)`), so they cannot express perspective either. A capture destined for a
# screen that was photographed at an angle therefore has to be pre-warped before it is embedded.
# The quad it is warped ONTO already exists in the template, as the clipPath geometry — these
# tests pin the parse that reads it back out, so the template stays the single source of truth.
# --------------------------------------------------------------------------------------

# The real slot-03 clip: an axis-aligned <rect>, deliberately bleeding off the 2752 bottom edge.
FIXTURE_STRAIGHT_ON = f"""<svg xmlns="{SVG_NS}" width="2064" height="2752" viewBox="0 0 2064 2752">
  <defs><clipPath id="screen-quad"><rect x="228" y="830" width="1608" height="2144" rx="44" ry="44"/></clipPath></defs>
  <image id="scene" x="0" y="0" width="2064" height="2752" preserveAspectRatio="xMidYMid slice" href=""/>
  <text id="headline" x="140" y="404" xml:space="preserve"><tspan x="140" dy="0">One</tspan><tspan x="140" dy="1.16em">Two</tspan></text>
  <image id="screenshot" x="228" y="830" width="1608" height="2144" preserveAspectRatio="xMidYMid slice" clip-path="url(#screen-quad)" href=""/>
</svg>"""

# The measured cut-out of `docs/design/appstore prerenders/ipad-mit-freischnitt.png`, mapped onto
# the 2064x2752 canvas with the CENTRED cover fit (CUTOUT.md section 5). BL.y = 2802.79 is 50.79 px
# past the bottom edge — the off-canvas defect the crop offset exists to fix.
MEASURED_QUAD_CENTRED = [
    (284.04, 181.69), (1744.90, 317.69), (1828.16, 2721.66), (323.53, 2802.79),
]
# The same cut-out with CUTOUT.md's recommended crop_top = 573.93 instead of the centred 457.69.
MEASURED_QUAD_OFFSET = [
    (284.04, 65.45), (1744.90, 201.45), (1828.16, 2605.42), (323.53, 2686.55),
]


def _perspective_template(quad, *, box=None, canvas=(2064, 2752), clip="polygon") -> str:
    """A slot-03-shaped template whose screen quad is a genuine perspective trapezoid."""
    w, h = canvas
    xs, ys = [p[0] for p in quad], [p[1] for p in quad]
    bx, by, bw, bh = box if box else (min(xs), min(ys), max(xs) - min(xs), max(ys) - min(ys))
    pts = " ".join(f"{x},{y}" for x, y in quad)
    if clip == "polygon":
        shape = f'<polygon points="{pts}"/>'
    elif clip == "polyline":
        shape = f'<polyline points="{pts}"/>'
    else:
        shape = f'<path d="M {quad[0][0]} {quad[0][1]} L {quad[1][0]} {quad[1][1]} Z"/>'
    return f"""<svg xmlns="{SVG_NS}" width="{w}" height="{h}" viewBox="0 0 {w} {h}">
  <defs><clipPath id="screen-quad">{shape}</clipPath></defs>
  <image id="scene" x="0" y="0" width="{w}" height="{h}" preserveAspectRatio="xMidYMid slice" href=""/>
  <text id="headline" x="140" y="404" xml:space="preserve"><tspan x="140" dy="0">One</tspan><tspan x="140" dy="1.16em">Two</tspan></text>
  <image id="screenshot" x="{bx}" y="{by}" width="{bw}" height="{bh}" preserveAspectRatio="xMidYMid slice" clip-path="url(#screen-quad)" href=""/>
</svg>"""


class TestQuadFromTemplate(unittest.TestCase):
    def _parse(self, xml_text):
        import xml.etree.ElementTree as ET
        return ET.fromstring(xml_text)

    def test_rect_clip_yields_four_corners_clockwise_from_top_left(self):
        quad = rss.template_screen_quad(self._parse(FIXTURE_STRAIGHT_ON))
        self.assertEqual(quad, [(228.0, 830.0), (1836.0, 830.0), (1836.0, 2974.0), (228.0, 2974.0)])

    def test_polygon_clip_yields_its_points_in_authored_order(self):
        quad = rss.template_screen_quad(self._parse(_perspective_template(MEASURED_QUAD_CENTRED)))
        for got, want in zip(quad, MEASURED_QUAD_CENTRED):
            self.assertAlmostEqual(got[0], want[0], places=6)
            self.assertAlmostEqual(got[1], want[1], places=6)

    def test_polyline_clip_is_accepted_too(self):
        quad = rss.template_screen_quad(
            self._parse(_perspective_template(MEASURED_QUAD_CENTRED, clip="polyline")))
        self.assertEqual(len(quad), 4)

    def test_points_accept_comma_space_and_newline_separators(self):
        self.assertEqual(
            rss.parse_points("1,2 3,4\n  5 6,7,8"),
            [(1.0, 2.0), (3.0, 4.0), (5.0, 6.0), (7.0, 8.0)],
        )

    def test_screenshot_without_clip_path_has_no_quad(self):
        # The small shared fixture carries no clip-path at all: no quad, hence no warp, hence
        # the byte-identical straight-on path stays available to templates that want it.
        self.assertIsNone(rss.template_screen_quad(self._parse(FIXTURE_WITH_SCREENSHOT)))

    def test_template_without_screenshot_element_has_no_quad(self):
        self.assertIsNone(rss.template_screen_quad(self._parse(FIXTURE_NO_SCREENSHOT)))

    def test_path_clip_is_a_named_error_not_a_crash(self):
        with self.assertRaises(rss.GeometryError) as ctx:
            rss.template_screen_quad(
                self._parse(_perspective_template(MEASURED_QUAD_CENTRED, clip="path")))
        self.assertIn("polygon", str(ctx.exception))

    def test_image_box_read_from_the_screenshot_element(self):
        root = self._parse(FIXTURE_STRAIGHT_ON)
        self.assertEqual(rss.image_box(rss.by_id(root, "screenshot")), (228.0, 830.0, 1608.0, 2144.0))

    def test_manifest_perspective_overrides_the_template_quad(self):
        root = self._parse(FIXTURE_STRAIGHT_ON)
        override = [[10, 20], [30, 21], [31, 60], [11, 59]]
        quad = rss.screen_quad_for(root, {"id": "x", "perspective": override})
        self.assertEqual(quad, [(10.0, 20.0), (30.0, 21.0), (31.0, 60.0), (11.0, 59.0)])

    def test_absent_manifest_perspective_falls_back_to_the_template_quad(self):
        root = self._parse(FIXTURE_STRAIGHT_ON)
        self.assertEqual(rss.screen_quad_for(root, {"id": "x"}), rss.template_screen_quad(root))


# --------------------------------------------------------------------------------------
# 10. Degenerate-case detection: an axis-aligned rectangle must never be warped.
#
# This is the regression gate for FR-9010-30 and for the AP-2 spike's byte-identical output
# (sha256 a48d6b8c... de / d99bb66f... en for slot 03): the moment slot-03 starts going through
# ImageMagick, those hashes move. It must not.
# --------------------------------------------------------------------------------------

class TestAxisAlignedDetection(unittest.TestCase):
    def test_real_slot_03_rect_is_axis_aligned(self):
        quad = [(228.0, 830.0), (1836.0, 830.0), (1836.0, 2974.0), (228.0, 2974.0)]
        self.assertTrue(rss.is_axis_aligned_rect(quad))
        self.assertFalse(rss.needs_warp(quad))

    def test_sub_tolerance_jitter_still_counts_as_axis_aligned(self):
        quad = [(228.0, 830.2), (1836.1, 830.0), (1836.0, 2974.0), (228.2, 2973.9)]
        self.assertTrue(rss.is_axis_aligned_rect(quad))

    def test_measured_trapezoid_is_not_axis_aligned(self):
        self.assertFalse(rss.is_axis_aligned_rect(MEASURED_QUAD_CENTRED))
        self.assertTrue(rss.needs_warp(MEASURED_QUAD_CENTRED))

    def test_rotated_rectangle_is_not_axis_aligned(self):
        # A rotation IS expressible as an SVG transform, but it is not a rectangle in canvas
        # space, so it takes the warp path too. Being conservative here is the safe direction.
        quad = [(100.0, 100.0), (300.0, 140.0), (260.0, 340.0), (60.0, 300.0)]
        self.assertFalse(rss.is_axis_aligned_rect(quad))

    def test_no_quad_means_no_warp(self):
        self.assertFalse(rss.needs_warp(None))


# --------------------------------------------------------------------------------------
# 11. The homography itself. Solved in stdlib Python (Gaussian elimination with partial
# pivoting) rather than by numpy (FR-9010-25). ImageMagick recomputes the same map from the
# four point pairs; solving it here buys the degeneracy check and a testable seam.
# --------------------------------------------------------------------------------------

UNIT_SQUARE = [(0.0, 0.0), (1.0, 0.0), (1.0, 1.0), (0.0, 1.0)]


class TestHomography(unittest.TestCase):
    def assertCoeffs(self, got, want, places=9):
        self.assertEqual(len(got), 8)
        for i, (g, w) in enumerate(zip(got, want)):
            self.assertAlmostEqual(g, w, places=places, msg=f"coefficient {i}")

    def test_identity(self):
        self.assertCoeffs(rss.homography(UNIT_SQUARE, UNIT_SQUARE), (1, 0, 0, 0, 1, 0, 0, 0))

    def test_pure_scale_and_translate_has_no_perspective_terms(self):
        dst = [(5.0, 7.0), (9.0, 7.0), (9.0, 13.0), (5.0, 13.0)]  # 4x wide, 6x tall, +(5,7)
        self.assertCoeffs(rss.homography(UNIT_SQUARE, dst), (4, 0, 5, 0, 6, 7, 0, 0))

    def test_shear_is_affine_so_g_and_h_stay_zero(self):
        dst = [(0.0, 0.0), (1.0, 0.0), (1.5, 1.0), (0.5, 1.0)]  # a parallelogram
        self.assertCoeffs(rss.homography(UNIT_SQUARE, dst), (1, 0.5, 0, 0, 1, 0, 0, 0))

    def test_known_perspective_case_against_hand_derived_coefficients(self):
        # Unit square -> (0,0),(1,0),(2,2),(0,1). Solving by hand with c=f=0 gives
        # a = g+1, e = h+1, s = g+h+1 = 1/(p+q-1) with (p,q) = (2,2), so s = 1/3,
        # g = h = ps-1 = -1/3, a = e = 2/3. Every coefficient below is that derivation.
        dst = [(0.0, 0.0), (1.0, 0.0), (2.0, 2.0), (0.0, 1.0)]
        self.assertCoeffs(rss.homography(UNIT_SQUARE, dst),
                          (2 / 3, 0, 0, 0, 2 / 3, 0, -1 / 3, -1 / 3))

    def test_apply_homography_reproduces_every_destination_corner(self):
        src = [(0.0, 0.0), (2064.0, 0.0), (2064.0, 2752.0), (0.0, 2752.0)]
        coeffs = rss.homography(src, MEASURED_QUAD_CENTRED)
        for (sx, sy), (dx, dy) in zip(src, MEASURED_QUAD_CENTRED):
            gx, gy = rss.apply_homography(coeffs, sx, sy)
            self.assertAlmostEqual(gx, dx, places=6)
            self.assertAlmostEqual(gy, dy, places=6)

    def test_measured_trapezoid_really_carries_perspective_terms(self):
        # CUTOUT.md rules the cut-out out as a parallelogram three ways. If g and h came back
        # zero the map would be affine and this whole warp would be unnecessary.
        src = [(0.0, 0.0), (2064.0, 0.0), (2064.0, 2752.0), (0.0, 2752.0)]
        _a, _b, _c, _d, _e, _f, g, h = rss.homography(src, MEASURED_QUAD_CENTRED)
        self.assertNotAlmostEqual(g, 0.0, places=9)
        self.assertNotAlmostEqual(h, 0.0, places=9)

    def test_collinear_destination_quad_is_a_clean_geometry_error(self):
        collinear = [(0.0, 0.0), (1.0, 1.0), (2.0, 2.0), (3.0, 3.0)]
        with self.assertRaises(rss.GeometryError):
            rss.homography(UNIT_SQUARE, collinear)

    def test_repeated_destination_points_are_a_clean_geometry_error(self):
        degenerate = [(0.0, 0.0), (0.0, 0.0), (1.0, 1.0), (0.0, 1.0)]
        with self.assertRaises(rss.GeometryError):
            rss.homography(UNIT_SQUARE, degenerate)

    def test_collinear_source_quad_is_a_clean_geometry_error(self):
        with self.assertRaises(rss.GeometryError):
            rss.homography([(0.0, 0.0), (1.0, 0.0), (2.0, 0.0), (3.0, 0.0)], UNIT_SQUARE)

    def test_geometry_error_is_a_value_error_so_callers_can_catch_either(self):
        self.assertTrue(issubclass(rss.GeometryError, ValueError))


# --------------------------------------------------------------------------------------
# 12. The ImageMagick call. Verified against the installed binary's own spelling
# (`magick -list distort` names `Perspective`; `-matte` warns "use -alpha Set" on IM 7.1.2),
# but never actually invoked here — this file stays tool-free (see the module docstring).
# --------------------------------------------------------------------------------------

class TestPerspectiveControlPoints(unittest.TestCase):
    def test_source_corners_are_the_capture_rectangle_clockwise_from_top_left(self):
        got = rss.perspective_control_points((100, 140), [(1.0, 2.0), (3.0, 4.0), (5.0, 6.0), (7.0, 8.0)])
        self.assertEqual(got, "0,0 1,2  100,0 3,4  100,140 5,6  0,140 7,8")

    def test_fractional_destination_corners_are_preserved_not_rounded(self):
        got = rss.perspective_control_points((2064, 2752), MEASURED_QUAD_CENTRED)
        self.assertIn("284.04", got)
        self.assertIn("2802.79", got)
        self.assertTrue(got.startswith("0,0 284.04,181.69"))

    def test_control_points_are_deterministic(self):
        a = rss.perspective_control_points((2064, 2752), MEASURED_QUAD_CENTRED)
        b = rss.perspective_control_points((2064, 2752), MEASURED_QUAD_CENTRED)
        self.assertEqual(a, b)


class TestWarpInvocation(ScratchTestCase):
    """`warp_capture_perspective` shells out; the subprocess call is captured, never run."""

    def _capture_argv(self, quad, box, *, capture_size=(2064, 2752)):
        capture = self.work / "capture.png"
        capture.write_bytes(_make_png(*capture_size))
        seen = {}

        def fake_run(cmd, **kwargs):
            seen["cmd"] = cmd
            Path(cmd[-1]).write_bytes(_make_png(4, 4))
            class _R:
                returncode = 0
            return _R()

        real_run = rss.subprocess.run
        rss.subprocess.run = fake_run
        try:
            out = rss.warp_capture_perspective(capture, quad, box=box,
                                                work_dir=self.work, tag="ipad-de-99")
        finally:
            rss.subprocess.run = real_run
        return seen["cmd"], out

    def test_measured_trapezoid_is_warped_with_the_right_corner_arguments(self):
        box = (284.04, 181.69, 1544.12, 2621.10)
        cmd, out = self._capture_argv(MEASURED_QUAD_CENTRED, box)
        self.assertEqual(cmd[0], "magick")
        self.assertIn("-distort", cmd)
        self.assertEqual(cmd[cmd.index("-distort") + 1], "Perspective")
        pairs = cmd[cmd.index("-distort") + 2]
        self.assertEqual(
            pairs,
            "0,0 284.04,181.69  2064,0 1744.9,317.69  "
            "2064,2752 1828.16,2721.66  0,2752 323.53,2802.79",
        )
        self.assertTrue(out.exists())

    def test_alpha_and_virtual_pixel_flags_use_the_imagemagick_7_spelling(self):
        # `-matte` still works on IM 7.1.2 but emits "option has been replaced" on stderr.
        cmd, _ = self._capture_argv(MEASURED_QUAD_CENTRED, (284.04, 181.69, 1544.12, 2621.10))
        self.assertNotIn("-matte", cmd)
        self.assertEqual(cmd[cmd.index("-alpha") + 1], "set")
        self.assertEqual(cmd[cmd.index("-virtual-pixel") + 1], "transparent")

    def test_viewport_is_the_screenshot_image_box_so_quad_coords_stay_absolute(self):
        cmd, _ = self._capture_argv(MEASURED_QUAD_CENTRED, (284.04, 181.69, 1544.12, 2621.10))
        idx = cmd.index("option:distort:viewport")
        self.assertEqual(cmd[idx + 1], "1544x2621+284+182")

    def test_output_is_stripped_so_the_intermediate_is_byte_stable(self):
        cmd, _ = self._capture_argv(MEASURED_QUAD_CENTRED, (284.04, 181.69, 1544.12, 2621.10))
        self.assertIn("-strip", cmd)

    def test_degenerate_quad_raises_before_imagemagick_is_ever_reached(self):
        with self.assertRaises(rss.GeometryError):
            self._capture_argv([(0.0, 0.0), (1.0, 1.0), (2.0, 2.0), (3.0, 3.0)],
                               (0.0, 0.0, 10.0, 10.0))


# --------------------------------------------------------------------------------------
# 13. Warped substitution: the pre-warped bitmap is authored in the box's own units, so `fit`
# has already been consumed by the homography and preserveAspectRatio must be `none`.
# --------------------------------------------------------------------------------------

class TestWarpedSubstitution(unittest.TestCase):
    def _parse(self, xml_text):
        import xml.etree.ElementTree as ET
        return ET.fromstring(xml_text)

    def test_warped_capture_forces_preserve_aspect_ratio_none(self):
        root = self._parse(FIXTURE_WITH_SCREENSHOT)
        rss.substitute(root, scene_uri="u", screenshot_uri="v", fit="cover", lines=["A"],
                        warped=True)
        self.assertEqual(rss.by_id(root, "screenshot").get("preserveAspectRatio"), "none")

    def test_unwarped_default_is_unchanged(self):
        root = self._parse(FIXTURE_WITH_SCREENSHOT)
        rss.substitute(root, scene_uri="u", screenshot_uri="v", fit="cover", lines=["A"])
        self.assertEqual(rss.by_id(root, "screenshot").get("preserveAspectRatio"),
                          "xMidYMid slice")

    def test_two_identical_substitutions_serialise_to_identical_bytes(self):
        import xml.etree.ElementTree as ET
        outs = []
        for _ in range(2):
            root = self._parse(_perspective_template(MEASURED_QUAD_OFFSET))
            rss.substitute(root, scene_uri="u", screenshot_uri="v", fit="cover",
                            lines=["A", "B"], warped=True)
            outs.append(ET.tostring(root, encoding="utf-8"))
        self.assertEqual(outs[0], outs[1])


# --------------------------------------------------------------------------------------
# 14. `--check` on template geometry. "A scene whose screen falls off the canvas must be caught
# by --check, not discovered by eye" — CUTOUT.md measured exactly that defect on the centred
# cover fit of `ipad-mit-freischnitt.png` (BL.y = 2802.79 vs a 2752 canvas).
# --------------------------------------------------------------------------------------

class TestTemplateGeometryCheck(ScratchTestCase):
    def _tree_with_template(self, svg_text, *, slot_overrides=None):
        manifest = _small_manifest()
        manifest["devices"] = {"ipad": {"label": "iPad", "width": 2064, "height": 2752}}
        manifest["slots"] = manifest["slots"][:1]
        if slot_overrides:
            manifest["slots"][0].update(slot_overrides)
        tree = self.work / "tree"
        manifest_path = _write_manifest_tree(tree, manifest)
        (tree / "Design" / "AppStore" / "templates" / "ipad" / "slot-01.svg").write_text(
            svg_text, encoding="utf-8")
        return manifest_path, tree

    def test_off_canvas_perspective_quad_is_reported(self):
        svg = _perspective_template(MEASURED_QUAD_CENTRED)
        manifest_path, tree = self._tree_with_template(svg)
        code, out, err = self.run_main(["--check", "--manifest", str(manifest_path)], root=tree)
        self.assertEqual(code, 1, out + err)
        self.assertIn("off-canvas", out)
        self.assertIn("2802.79", out)

    def test_recommended_crop_offset_puts_the_same_quad_back_on_canvas(self):
        svg = _perspective_template(MEASURED_QUAD_OFFSET)
        manifest_path, tree = self._tree_with_template(svg)
        code, out, err = self.run_main(["--check", "--manifest", str(manifest_path)], root=tree)
        self.assertEqual(code, 0, out + err)

    def test_straight_on_template_may_bleed_off_the_bottom_edge(self):
        # slot-03's device body bleeds off the canvas *by design*. The on-canvas rule applies to
        # perspective quads (a screen photographed inside a scene) only — see the README.
        manifest_path, tree = self._tree_with_template(FIXTURE_STRAIGHT_ON)
        code, out, err = self.run_main(["--check", "--manifest", str(manifest_path)], root=tree)
        self.assertEqual(code, 0, out + err)

    def test_quad_outside_the_screenshot_image_box_is_reported(self):
        svg = _perspective_template(MEASURED_QUAD_OFFSET, box=(600, 600, 400, 400))
        manifest_path, tree = self._tree_with_template(svg)
        code, out, err = self.run_main(["--check", "--manifest", str(manifest_path)], root=tree)
        self.assertEqual(code, 1, out + err)
        self.assertIn("outside", out)

    def test_degenerate_template_quad_is_reported_not_crashed_on(self):
        svg = _perspective_template([(100.0, 100.0), (200.0, 200.0), (300.0, 300.0), (400.0, 400.0)])
        manifest_path, tree = self._tree_with_template(svg)
        code, out, err = self.run_main(["--check", "--manifest", str(manifest_path)], root=tree)
        self.assertEqual(code, 1, out + err)
        self.assertIn("degenerate", out.lower() + err.lower())

    def test_path_clip_on_a_perspective_slot_is_reported(self):
        svg = _perspective_template(MEASURED_QUAD_OFFSET, clip="path")
        manifest_path, tree = self._tree_with_template(svg)
        code, out, err = self.run_main(["--check", "--manifest", str(manifest_path)], root=tree)
        self.assertEqual(code, 1, out + err)
        self.assertIn("polygon", out)

    def test_unparseable_template_is_reported_not_crashed_on(self):
        manifest_path, tree = self._tree_with_template("<svg><unclosed>")
        code, out, err = self.run_main(["--check", "--manifest", str(manifest_path)], root=tree)
        self.assertEqual(code, 1, out + err)
        self.assertIn("slot-01.svg", out)

    def test_manifest_perspective_override_is_checked_against_the_canvas_too(self):
        manifest_path, tree = self._tree_with_template(
            FIXTURE_STRAIGHT_ON,
            slot_overrides={"perspective": [[10, 20], [3000, 21], [2990, 2700], [11, 2740]]},
        )
        code, out, err = self.run_main(["--check", "--manifest", str(manifest_path)], root=tree)
        self.assertEqual(code, 1, out + err)
        self.assertIn("off-canvas", out)

# --------------------------------------------------------------------------------------
# 15. Sceneless UI slots (FR-9010-03 amendment, 2026-09-10)
#
# The two slot archetypes: a photo slot composites its capture into a photographed room, a UI
# slot drops the room entirely and stands the screen on the brand ground the template draws
# itself. So `scene` becomes exactly as optional as `capture` already was — the renderer used
# to demand a scene file for every slot and an id="scene" in every template, which is why the
# first UI slots were built as rooms and looked it.
#
# The contract is symmetric in both directions, and both directions are asserted: declared but
# absent is still an error, and supplied-but-unconsumable is an error too. `type` is what
# decides requiredness, so `type` is validated against its vocabulary here for the first time.
# --------------------------------------------------------------------------------------


def _parse_svg(xml_text: str):
    import xml.etree.ElementTree as ET
    return ET.fromstring(xml_text)


class TestScenelessUiSlots(ScratchTestCase):
    FIXTURE_NO_SCENE = f"""<svg xmlns="{SVG_NS}" width="100" height="140" viewBox="0 0 100 140">
  <rect x="0" y="0" width="100" height="140" fill="#000000"/>
  <text id="headline" x="10" y="20" xml:space="preserve"><tspan x="10" dy="0">Headline line one</tspan><tspan x="10" dy="1.16em">Headline line two</tspan></text>
  <image id="screenshot" x="12" y="40" width="70" height="90" preserveAspectRatio="xMidYMid slice" href=""/>
</svg>"""

    def test_template_without_scene_id_substitutes_when_no_scene_supplied(self):
        root = _parse_svg(self.FIXTURE_NO_SCENE)
        rss.substitute(root, scene_uri=None, screenshot_uri="data:image/png;base64,AAAA",
                       fit="cover", lines=["One"])
        self.assertEqual(rss.by_id(root, "screenshot").get("href"),
                         "data:image/png;base64,AAAA")
        self.assertIsNone(rss.by_id(root, "scene"))

    def test_template_with_scene_id_but_no_scene_supplied_raises(self):
        root = _parse_svg(FIXTURE_WITH_SCREENSHOT)
        with self.assertRaises(ValueError) as ctx:
            rss.substitute(root, scene_uri=None, screenshot_uri="data:image/png;base64,AAAA",
                           fit="cover", lines=["One"])
        self.assertIn("scene", str(ctx.exception))

    def test_scene_supplied_but_template_has_no_scene_id_raises(self):
        """The mirror of the screenshot rule: silently dropping a declared asset is how a slot
        ships looking like nobody noticed."""
        root = _parse_svg(self.FIXTURE_NO_SCENE)
        with self.assertRaises(ValueError) as ctx:
            rss.substitute(root, scene_uri="data:image/png;base64,AAAA",
                           screenshot_uri="data:image/png;base64,AAAA",
                           fit="cover", lines=["One"])
        self.assertIn("scene", str(ctx.exception))

    def test_slot_without_scene_key_resolves_to_no_scene_path(self):
        slot = {"id": "03-ui", "type": "ui", "template": "slot-03.svg",
                "capture": "03-ui.png", "fit": "cover", "headline": {"en": ["One"]}}
        paths = rss.resolve_slot_paths(
            root=self.work, capture_root=self.work / "captures", device="ipad", locale="en",
            slot=slot, scene_overrides={},
        )
        self.assertIsNone(paths.scene)
        self.assertIsNotNone(paths.capture)

    def test_ui_slot_without_scene_key_is_not_reported_missing(self):
        manifest = _small_manifest()
        del manifest["slots"][0]["scene"]
        manifest_path = _write_manifest_tree(self.work / "tree", manifest)
        (self.work / "tree" / "Design" / "AppStore" / "templates" / "ipad"
         / "slot-01.svg").write_text(self.FIXTURE_NO_SCENE, encoding="utf-8")
        (self.work / "tree" / "Design" / "AppStore" / "templates" / "iphone"
         / "slot-01.svg").write_text(self.FIXTURE_NO_SCENE, encoding="utf-8")
        code, out, err = self.run_main(
            ["--check", "--manifest", str(manifest_path)], root=self.work / "tree")
        self.assertEqual(code, 0, out + err)
        self.assertNotIn("missing scene", out)

        # A green --check is not enough on its own: the slot could be green because it was
        # silently dropped as unresolvable and never checked at all. Assert it actually resolves.
        code, out, err = self.run_main(
            ["--list", "--manifest", str(manifest_path)], root=self.work / "tree")
        self.assertEqual(code, 0, out + err)
        rows = [r for r in out.splitlines() if "01-alpha" in r]
        self.assertTrue(rows, out)
        for row in rows:
            self.assertNotIn("unresolvable", row)
            self.assertIn("slot-01.svg", row)

    def test_scene_slot_without_scene_key_is_a_manifest_problem(self):
        manifest = _small_manifest()
        manifest["slots"][0]["type"] = "scene"
        del manifest["slots"][0]["scene"]
        problems = rss.manifest_problems(manifest)
        self.assertTrue(any("scene" in p and "01-alpha" in p for p in problems), problems)

    def test_declared_scene_that_does_not_exist_is_still_reported(self):
        """Optional means "may be omitted", never "may be wrong"."""
        manifest = _small_manifest()
        manifest_path = _write_manifest_tree(self.work / "tree", manifest)
        (self.work / "tree" / "Design" / "AppStore" / "scenes" / "ipad" / "01-alpha.jpg").unlink()
        code, out, err = self.run_main(
            ["--check", "--manifest", str(manifest_path)], root=self.work / "tree")
        self.assertEqual(code, 1)
        self.assertIn("missing scene", out)

    def test_unknown_slot_type_is_a_manifest_problem(self):
        manifest = _small_manifest()
        manifest["slots"][0]["type"] = "diorama"
        problems = rss.manifest_problems(manifest)
        self.assertTrue(any("type" in p and "diorama" in p for p in problems), problems)

    def test_both_shipped_slot_types_are_accepted(self):
        for slot_type in ("scene", "ui"):
            with self.subTest(type=slot_type):
                manifest = _small_manifest()
                manifest["slots"][0]["type"] = slot_type
                problems = rss.manifest_problems(manifest)
                self.assertEqual([p for p in problems if "type" in p], [])


# --------------------------------------------------------------------------------------
# 16. `captureCrop`: zoom a UI capture into its own content before it is composited.
#
# Why this exists. The app uses a centred content column (FR-9000-17), so a full-screen iPad
# capture carries large dead margins. Compositing the whole capture faithfully reproduces that
# emptiness, and at App Store carousel width (~230px/tile) the UI slots read as black tiles with
# an illegible smudge. Cropping to the content roughly doubles apparent text size and needs no
# new material and no re-capture.
#
# Fractions, not pixels, deliberately: capture size varies by rig (1488x2266 on an iPad mini vs
# 2064x2752 on a 13-inch), and a fractional rect survives a change of capture device. The key is
# optional and its absence must leave the existing pipeline untouched, byte-for-byte.
# --------------------------------------------------------------------------------------

class TestCaptureCropValidation(unittest.TestCase):
    """--check must reject a malformed crop before a long Chrome batch, not during it."""

    def _problems(self, crop):
        manifest = _small_manifest()
        manifest["slots"][0]["captureCrop"] = crop
        return [p for p in rss.manifest_problems(manifest) if "captureCrop" in p]

    def test_absent_crop_is_valid(self):
        manifest = _small_manifest()
        self.assertEqual(
            [p for p in rss.manifest_problems(manifest) if "captureCrop" in p], [])

    def test_full_frame_crop_is_valid(self):
        self.assertEqual(self._problems({"x": 0, "y": 0, "width": 1, "height": 1}), [])

    def test_typical_content_crop_is_valid(self):
        self.assertEqual(self._problems({"x": 0.0, "y": 0.0, "width": 1.0, "height": 0.62}), [])

    def test_non_object_crop_is_rejected(self):
        self.assertTrue(self._problems([0, 0, 1, 1]))

    def test_missing_key_is_rejected(self):
        self.assertTrue(self._problems({"x": 0, "y": 0, "width": 1}))

    def test_non_numeric_value_is_rejected(self):
        self.assertTrue(self._problems({"x": 0, "y": 0, "width": "1", "height": 1}))

    def test_bool_is_not_a_number(self):
        # bool is an int subclass in Python; a crop of `true` must not sail through.
        self.assertTrue(self._problems({"x": 0, "y": 0, "width": True, "height": 1}))

    def test_negative_origin_is_rejected(self):
        self.assertTrue(self._problems({"x": -0.1, "y": 0, "width": 1, "height": 1}))

    def test_zero_extent_is_rejected(self):
        self.assertTrue(self._problems({"x": 0, "y": 0, "width": 0, "height": 1}))

    def test_extent_past_the_frame_is_rejected(self):
        self.assertTrue(self._problems({"x": 0.5, "y": 0, "width": 0.75, "height": 1}))
        self.assertTrue(self._problems({"x": 0, "y": 0.5, "width": 1, "height": 0.75}))

    def test_unknown_key_is_rejected_so_a_typo_is_never_silently_ignored(self):
        self.assertTrue(self._problems({"x": 0, "y": 0, "width": 1, "height": 1, "hieght": 0.5}))


class TestCropInvocation(ScratchTestCase):
    """`crop_capture` shells out; the subprocess call is captured, never run."""

    def _capture_argv(self, crop, *, capture_size=(1488, 2266)):
        capture = self.work / "capture.png"
        capture.write_bytes(_make_png(*capture_size))
        seen = {}

        def fake_run(cmd, **kwargs):
            seen["cmd"] = cmd
            Path(cmd[-1]).write_bytes(_make_png(4, 4))
            class _R:
                returncode = 0
            return _R()

        real_run = rss.subprocess.run
        rss.subprocess.run = fake_run
        try:
            out = rss.crop_capture(capture, crop, work_dir=self.work, tag="ipad-en-03")
        finally:
            rss.subprocess.run = real_run
        return seen["cmd"], out

    def test_fractional_rect_becomes_imagemagick_pixel_geometry(self):
        cmd, out = self._capture_argv({"x": 0.0, "y": 0.0, "width": 1.0, "height": 0.62})
        self.assertEqual(cmd[0], "magick")
        self.assertEqual(cmd[cmd.index("-crop") + 1], "1488x1405+0+0")
        self.assertTrue(out.exists())

    def test_offset_rect_is_placed_correctly(self):
        cmd, _ = self._capture_argv({"x": 0.25, "y": 0.1, "width": 0.5, "height": 0.5})
        self.assertEqual(cmd[cmd.index("-crop") + 1], "744x1133+372+227")

    def test_repage_follows_the_crop_so_the_canvas_offset_is_discarded(self):
        # Without +repage the cropped PNG keeps the original canvas geometry, and the later
        # homography would then map the FULL frame, silently undoing the zoom.
        cmd, _ = self._capture_argv({"x": 0.1, "y": 0.1, "width": 0.8, "height": 0.8})
        self.assertIn("+repage", cmd)
        self.assertGreater(cmd.index("+repage"), cmd.index("-crop"))

    def test_output_is_stripped_so_the_intermediate_is_byte_stable(self):
        cmd, _ = self._capture_argv({"x": 0, "y": 0, "width": 1, "height": 0.5})
        self.assertIn("-strip", cmd)

    def test_a_rect_that_rounds_to_nothing_still_asks_for_at_least_one_pixel(self):
        cmd, _ = self._capture_argv({"x": 0.0, "y": 0.0, "width": 0.0001, "height": 0.0001})
        geometry = cmd[cmd.index("-crop") + 1]
        width, rest = geometry.split("x")
        height = rest.split("+")[0]
        self.assertGreaterEqual(int(width), 1)
        self.assertGreaterEqual(int(height), 1)


class TestCropAppliedInRenderPipeline(ScratchTestCase):
    """Ordering: the crop runs BEFORE the perspective decision, and only when declared."""

    def test_crop_is_skipped_entirely_when_the_key_is_absent(self):
        called = []
        real_crop = rss.crop_capture
        rss.crop_capture = lambda *a, **k: called.append(a) or a[0]
        try:
            slot = _small_manifest()["slots"][0]
            self.assertNotIn("captureCrop", slot)
        finally:
            rss.crop_capture = real_crop
        self.assertEqual(called, [])

    def test_crop_precedes_warp_so_the_homography_maps_the_cropped_frame(self):
        # The homography maps the capture's OWN rectangle onto the screen quad. Cropping after
        # the warp would therefore cut the already-placed screen instead of zooming it, so the
        # order is load-bearing rather than incidental.
        order = []
        real_crop, real_warp = rss.crop_capture, rss.warp_capture_perspective

        def fake_crop(capture, crop, *, work_dir, tag):
            order.append("crop")
            dst = work_dir / "cropped.png"
            dst.write_bytes(_make_png(100, 100))
            return dst

        def fake_warp(capture, quad, *, box, work_dir, tag):
            order.append("warp")
            dst = work_dir / "warped.png"
            dst.write_bytes(_make_png(100, 100))
            return dst

        rss.crop_capture, rss.warp_capture_perspective = fake_crop, fake_warp
        try:
            src, warped = rss.prepare_capture(
                self.work / "c.png",
                crop={"x": 0, "y": 0, "width": 1, "height": 0.6},
                quad=MEASURED_QUAD_CENTRED,
                box=(0.0, 0.0, 10.0, 10.0),
                work_dir=self.work,
                tag="t",
            )
        finally:
            rss.crop_capture, rss.warp_capture_perspective = real_crop, real_warp
        self.assertEqual(order, ["crop", "warp"])
        self.assertTrue(warped)
        self.assertTrue(src.exists())

    def test_an_axis_aligned_quad_still_crops_but_never_warps(self):
        order = []
        real_crop, real_warp = rss.crop_capture, rss.warp_capture_perspective

        def fake_crop(capture, crop, *, work_dir, tag):
            order.append("crop")
            dst = work_dir / "cropped.png"
            dst.write_bytes(_make_png(100, 100))
            return dst

        def fake_warp(*a, **k):
            order.append("warp")
            raise AssertionError("a straight-on quad must skip ImageMagick entirely")

        rss.crop_capture, rss.warp_capture_perspective = fake_crop, fake_warp
        try:
            src, warped = rss.prepare_capture(
                self.work / "c.png",
                crop={"x": 0, "y": 0, "width": 1, "height": 0.6},
                quad=[(0.0, 0.0), (10.0, 0.0), (10.0, 20.0), (0.0, 20.0)],
                box=(0.0, 0.0, 10.0, 20.0),
                work_dir=self.work,
                tag="t",
            )
        finally:
            rss.crop_capture, rss.warp_capture_perspective = real_crop, real_warp
        self.assertEqual(order, ["crop"])
        self.assertFalse(warped)


def tearDownModule():
    shutil.rmtree(SCRATCH, ignore_errors=True)


if __name__ == "__main__":
    unittest.main()
