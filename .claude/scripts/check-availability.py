#!/usr/bin/env python3
"""PR #49 checker (hitl §4): lines up the RIGMARK lines of
DeviceRigConfigUITests.testSettingsOverSlideshowThenBackground with a broker recording
(`mosquitto_sub -F '%U %t %p'`) of the frame's availability and frame_status topics.

    check-availability.py <xcodebuild test log> <mqtt recording>

Expected (FR-700-23, FR-710-24): with Settings open the frame stays `online` and
frame_status reads `inactive`; after Done it reads `running` again; in the background the
frame goes `offline`; back in the foreground it is `online` and `running`.
"""
import re, sys

log, rec = sys.argv[1], sys.argv[2]
marks = {m.group(1): float(m.group(2))
         for m in re.finditer(r"RIGMARK (\S+) ([0-9.]+)", open(log, errors="replace").read())}
events = []
for line in open(rec, errors="replace"):
    parts = line.split(" ", 2)
    if len(parts) == 3:
        ts, topic, payload = parts
        kind = "availability" if topic.endswith("/availability") else "status"
        events.append((float(ts), kind, payload.strip()))

need = ["settings-open", "settings-close", "background", "foreground", "end"]
missing = [m for m in need if m not in marks]
if missing:
    sys.exit(f"FAIL: test log lacks markers {missing} — did the test run to the end?")
if not events:
    sys.exit("FAIL: no broker messages recorded — the frame never talked to the broker")

def last_before(kind, t):
    vals = [p for ts, k, p in events if k == kind and ts <= t]
    return vals[-1] if vals else None

def seen(kind, payload, start, end):
    return any(k == kind and p == payload and start <= ts <= end for ts, k, p in events)

SLACK = 15  # seconds for a publish to land after a UI step
checks = [
    ("online before Settings", last_before("availability", marks["settings-open"]) == "online"),
    ("running before Settings", last_before("status", marks["settings-open"]) == "running"),
    ("inactive while Settings is open",
     seen("status", "inactive", marks["settings-open"], marks["settings-close"])),
    ("never offline while Settings is open (PR #49)",
     not seen("availability", "offline", marks["settings-open"], marks["settings-close"] + SLACK)),
    ("running again after Done",
     seen("status", "running", marks["settings-close"], marks["background"])),
    ("offline in the background (teardown)",
     seen("availability", "offline", marks["background"], marks["foreground"] + SLACK)),
    ("online again in the foreground",
     seen("availability", "online", marks["foreground"], marks["end"] + SLACK)),
    ("running again in the foreground",
     last_before("status", marks["end"] + SLACK) == "running"),
]
for name, ok in checks:
    print(f"  {'ok  ' if ok else 'FAIL'} {name}")
t0 = marks["settings-open"] - 5
for ts, k, p in events:
    if ts >= t0:
        print(f"    {ts - marks['settings-open']:+7.1f}s {k:12} {p}")
sys.exit(0 if all(ok for _, ok in checks) else 1)
