#!/usr/bin/env python3
"""Upload App Store screenshots to App Store Connect, both locales.

Usage (defaults reproduce the v1.0 iPad-13" upload of 2026-07-11):

    python3 .claude/scripts/asc-upload-screenshots.py \
        --dir ~/Library/Developer/Xcode/ImmichSlideshow-dist/screenshots-v1.0 \
        --display-type APP_IPAD_PRO_3GEN_129 \
        --files 03-hero-chapel.png 05-hero-iceberg.png ...

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
import urllib.request

API = "https://api.appstoreconnect.apple.com/v1"
# appStoreVersionLocalizations of app 6784154405, version 1.0 (e425bae6-…).
LOCALES = {
    "en-US": "7caa665a-0a53-4161-a902-65931623a3f8",
    "de-DE": "df44b6b9-23a2-4f56-ad74-ce29198e1e77",
}
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
    p.add_argument("--dir", required=True, help="directory containing the PNGs")
    p.add_argument("--display-type", required=True,
                   help="ASC screenshotDisplayType, e.g. APP_IPAD_PRO_3GEN_129, APP_IPHONE_69")
    p.add_argument("--files", nargs="+", default=DEFAULT_ORDER,
                   help="file names in display order (default: the v1.0 set)")
    args = p.parse_args()
    directory = os.path.expanduser(args.dir)

    for locale, loc_id in LOCALES.items():
        set_id = ensure_set(loc_id, args.display_type)
        print(f"{locale}: set {set_id} ({args.display_type})")
        clear_set(set_id)
        for fname in args.files:
            shot_id = upload_one(set_id, os.path.join(directory, fname))
            print(f"  {fname} -> {shot_id}")
    print("done")


if __name__ == "__main__":
    main()
