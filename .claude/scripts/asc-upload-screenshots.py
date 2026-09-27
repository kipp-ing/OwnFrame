#!/usr/bin/env python3
"""Upload App Store screenshots to App Store Connect, both locales.

Usage (the 1.2 upload, one folder per locale — <dir>/en and <dir>/de):

    python3 .claude/scripts/asc-upload-screenshots.py --version 1.2 --per-locale \
        --dir tmp/store-upload-1.2/ipad --display-type APP_IPAD_PRO_3GEN_129 \
        --files 01.png 02.png 03.png 04.png 05.png

Without --per-locale every locale gets the same files from <dir> (the v1.0 behaviour).
Only a version in PREPARE_FOR_SUBMISSION accepts screenshots.

The set for the display type is created if missing and CLEARED before upload
(idempotent, safe to re-run). File order = display order in the store listing.
Needs the JWT helper at ~/.appstoreconnect/asc_jwt.py (stdlib-only, prints a
15-minute token; the .p8 key sits next to it).
"""
import argparse
import hashlib
import json
import os
import subprocess
import time
import urllib.request

API = "https://api.appstoreconnect.apple.com/v1"
APP_ID = "6784154405"
# Store locale -> the per-locale folder name the renderer writes (content.json "locales").
LOCALE_DIRS = {"en-US": "en", "de-DE": "de"}
DEFAULT_ORDER = [
    "03-hero-chapel.png",
    "05-hero-iceberg.png",
    "07-photo-info.png",
    "04-chrome.png",
    "02-onboarding-sharedlink.png",
    "01-onboarding-choice.png",
    "06-settings.png",
]


def jwt() -> str:
    return subprocess.run(
        ["python3", os.path.expanduser("~/.appstoreconnect/asc_jwt.py")],
        capture_output=True, text=True, check=True,
    ).stdout.strip()


def call(method: str, url: str, body=None, headers=None, raw=False):
    # Pre-signed upload URLs must receive ONLY the operation's own headers —
    # an ASC Bearer token there gets the request rejected with 400.
    h = {} if raw else {"Authorization": f"Bearer {jwt()}"}
    if body is not None and not raw:
        body = json.dumps(body).encode()
        h["Content-Type"] = "application/json"
    if headers:
        h.update(headers)
    req = urllib.request.Request(url, data=body, method=method, headers=h)
    with urllib.request.urlopen(req) as r:
        data = r.read()
        return json.loads(data) if data else {}


def version_localizations(version: str) -> dict:
    """locale -> appStoreVersionLocalization id for the app's iOS version `version`."""
    versions = call("GET", f"{API}/apps/{APP_ID}/appStoreVersions"
                           f"?filter[versionString]={version}&filter[platform]=IOS")
    if not versions.get("data"):
        raise SystemExit(f"no iOS appStoreVersion {version!r} on app {APP_ID}")
    vid = versions["data"][0]["id"]
    locs = call("GET", f"{API}/appStoreVersions/{vid}/appStoreVersionLocalizations")
    return {l["attributes"]["locale"]: l["id"] for l in locs["data"]}


def wait_delivered(set_id: str, expected: int, timeout: int = 300):
    """FR-9010-40: every asset must reach COMPLETE; COMPLETE alone still needs an eyeball."""
    deadline = time.time() + timeout
    while True:
        shots = call("GET", f"{API}/appScreenshotSets/{set_id}/appScreenshots?limit=50")["data"]
        states = [s["attributes"]["assetDeliveryState"]["state"] for s in shots]
        if len(states) == expected and all(st == "COMPLETE" for st in states):
            print(f"  delivered: {expected}/{expected} COMPLETE")
            return
        if any(st == "FAILED" for st in states) or time.time() > deadline:
            raise SystemExit(f"  delivery not complete for set {set_id}: {states}")
        time.sleep(5)


def ensure_set(loc_id: str, display_type: str) -> str:
    existing = call("GET", f"{API}/appStoreVersionLocalizations/{loc_id}/appScreenshotSets")
    for s in existing.get("data", []):
        if s["attributes"]["screenshotDisplayType"] == display_type:
            return s["id"]
    created = call("POST", f"{API}/appScreenshotSets", {
        "data": {
            "type": "appScreenshotSets",
            "attributes": {"screenshotDisplayType": display_type},
            "relationships": {"appStoreVersionLocalization": {
                "data": {"type": "appStoreVersionLocalizations", "id": loc_id}}},
        }
    })
    return created["data"]["id"]


def clear_set(set_id: str):
    existing = call("GET", f"{API}/appScreenshotSets/{set_id}/appScreenshots?limit=50")
    for s in existing.get("data", []):
        call("DELETE", f"{API}/appScreenshots/{s['id']}")
        print(f"  deleted stale {s['id']}")


def upload_one(set_id: str, path: str) -> str:
    name = os.path.basename(path)
    blob = open(path, "rb").read()
    reserved = call("POST", f"{API}/appScreenshots", {
        "data": {
            "type": "appScreenshots",
            "attributes": {"fileName": name, "fileSize": len(blob)},
            "relationships": {"appScreenshotSet": {
                "data": {"type": "appScreenshotSets", "id": set_id}}},
        }
    })
    shot_id = reserved["data"]["id"]
    for op in reserved["data"]["attributes"]["uploadOperations"]:
        chunk = blob[op["offset"]: op["offset"] + op["length"]]
        hdrs = {h["name"]: h["value"] for h in op.get("requestHeaders", [])}
        call(op["method"], op["url"], body=chunk, headers=hdrs, raw=True)
    call("PATCH", f"{API}/appScreenshots/{shot_id}", {
        "data": {
            "type": "appScreenshots",
            "id": shot_id,
            "attributes": {
                "uploaded": True,
                "sourceFileChecksum": hashlib.md5(blob).hexdigest(),
            },
        }
    })
    return shot_id


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--version", required=True, help="appStoreVersion versionString, e.g. 1.2")
    p.add_argument("--dir", required=True, help="directory containing the PNGs")
    p.add_argument("--per-locale", action="store_true",
                   help="read each locale's files from <dir>/<en|de>/ instead of <dir>")
    p.add_argument("--display-type", required=True,
                   help="ASC screenshotDisplayType, e.g. APP_IPAD_PRO_3GEN_129, APP_IPHONE_69")
    p.add_argument("--files", nargs="+", default=DEFAULT_ORDER,
                   help="file names in display order (default: the v1.0 set)")
    args = p.parse_args()
    directory = os.path.expanduser(args.dir)

    for locale, loc_id in version_localizations(args.version).items():
        src = os.path.join(directory, LOCALE_DIRS[locale]) if args.per_locale else directory
        set_id = ensure_set(loc_id, args.display_type)
        print(f"{locale}: set {set_id} ({args.display_type}) from {src}")
        clear_set(set_id)
        for fname in args.files:
            shot_id = upload_one(set_id, os.path.join(src, fname))
            print(f"  {fname} -> {shot_id}")
        wait_delivered(set_id, len(args.files))
    print("done")


if __name__ == "__main__":
    main()
