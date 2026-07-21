#!/usr/bin/env bash
#
# framepad.sh — drive the physical frame iPad ("Framepad") from the CLI.
#
# Every flag here is load-bearing; see docs/device-testing.md for why. In short:
#   -allowProvisioningUpdates   the .xctrunner needs its own profile, automatic signing is off
#   -derivedDataPath outside /private/tmp   CoreDevice cannot bookmark the scratchpad
#   --terminate-existing        else a launch re-activates and IGNORES new arguments
#   OS_ACTIVITY_DT_MODE=enable  routes os.Logger to stderr so --console can capture it
#
# Never pipe xcodebuild into tail/head: the exit code becomes the filter's, and a failed
# build reports success. Everything here redirects to a log and checks $?.
#
# Prerequisites that CANNOT be set from the CLI (one-time, on the device):
#   Settings > Developer > Enable UI Automation      (else no test bundle runs at all)
#   Settings > Display & Brightness > Auto-Lock > Never  (else runs park at preflight)
#
set -euo pipefail

DEVICE_ID="${FRAMEPAD_DEVICE_ID:-E7B3970E-8FD1-546B-8A1F-EC9A85167731}"
BUNDLE_ID="ing.kipp.Immich-Slideshow"
PROJECT="Immich Slideshow.xcodeproj"
SCHEME="Immich Slideshow"
DD="${FRAMEPAD_DD:-$HOME/Library/Developer/Xcode/DerivedData/FramepadRig}"
OUT="${FRAMEPAD_OUT:-$HOME/Library/Developer/Xcode/DerivedData/framepad-out}"
UITESTS="Immich SlideshowUITests/DeviceRigConfigUITests"

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$REPO_ROOT"
mkdir -p "$OUT"

die() { echo "error: $*" >&2; exit 1; }

# xcodebuild, with the exit code preserved and the log kept for inspection.
xcb() {
  local log="$1"; shift
  if ! xcodebuild -project "$PROJECT" -scheme "$SCHEME" \
      -destination "id=$DEVICE_ID" -configuration Debug \
      -derivedDataPath "$DD" -allowProvisioningUpdates "$@" > "$log" 2>&1; then
    echo "--- xcodebuild failed; errors from $log:" >&2
    grep -E 'error:|Testing failed|encountered an error' "$log" | head -20 >&2 || true
    return 1
  fi
}

require_device() {
  xcrun devicectl list devices 2>/dev/null | grep -q "$DEVICE_ID.*connected" \
    || die "Framepad not connected (is it awake and unlocked? a reboot leaves it locked)"
}

# Pull screenshots + UI-hierarchy dumps out of a result bundle. This is the ONLY way to
# see this device's screen — there is no devicectl screenshot.
export_shots() {
  local bundle="$1" dest="$2"
  rm -rf "$dest"; mkdir -p "$dest"
  xcrun xcresulttool export attachments --path "$bundle" --output-path "$dest" >/dev/null 2>&1 || true
  [ -f "$dest/manifest.json" ] && python3 - "$dest" <<'PY'
import json, sys, os
d = sys.argv[1]
for t in json.load(open(os.path.join(d, "manifest.json"))):
    for a in t.get("attachments", []):
        n = a.get("suggestedHumanReadableName", "")
        if n.endswith(".png") or "hierarchy" in n:
            print(f"  {n[:48]:<50} {a.get('exportedFileName')}")
PY
  echo "screenshots: $dest"
}

cmd_build() {
  require_device
  echo "building for testing…"
  xcb "$OUT/build.log" build-for-testing
  echo "ok — products in $DD/Build/Products/Debug-iphoneos"
}

cmd_install() {
  require_device
  xcb "$OUT/build.log" build
  xcrun devicectl device install app --device "$DEVICE_ID" \
    "$DD/Build/Products/Debug-iphoneos/Immich Slideshow.app" | tail -3
}

# Launch with app logs streaming to stdout. Args after `logs` go to the app, e.g.
#   framepad.sh logs --uitest-entitlements=all
cmd_logs() {
  require_device
  echo "launching with console capture (ctrl-c to stop)…"
  xcrun devicectl device process launch --device "$DEVICE_ID" \
    --console --terminate-existing \
    --environment-variables '{"OS_ACTIVITY_DT_MODE":"enable"}' \
    "$BUNDLE_ID" "$@"
}

# Launch detached (app keeps running after this returns).
cmd_launch() {
  require_device
  xcrun devicectl device process launch --device "$DEVICE_ID" \
    --terminate-existing "$BUNDLE_ID" "$@" | tail -2
}

# Run rig tests. Requires the broker password in the environment — never hard-coded.
run_rig() {
  local test_id="$1" label="$2"
  [ -n "${MQTT_PASSWORD:-}" ] || die "set MQTT_PASSWORD (broker password; never committed)"
  require_device
  local bundle="$OUT/$label.xcresult"
  rm -rf "$bundle"
  echo "running $label on device (slow — 2017 hardware)…"
  TEST_RUNNER_DEVICE_RIG=1 TEST_RUNNER_MQTT_PASSWORD="$MQTT_PASSWORD" \
    xcb "$OUT/$label.log" -only-testing:"$test_id" \
      -resultBundlePath "$bundle" test-without-building \
    && echo "PASS" || echo "FAIL — see $OUT/$label.log"
  grep -E 'Test Case.*(passed|failed)' "$OUT/$label.log" | tail -5 || true
  export_shots "$bundle" "$OUT/$label-shots"
}

cmd_rig()   { run_rig "$UITESTS/testConfigureFrameWithSharedLinkAndBroker" rig; }
cmd_gates() { run_rig "$UITESTS/testHoldForegroundSoCoordinatorAnnounces" gates; }
cmd_diag()  { run_rig "$UITESTS/testDiagnoseBrokerConnectionState" diag; }

# Assert what the broker actually holds for a device id. Takes the id from the app's
# `start: connecting (device=…)` log line — it is NOT stable across broker reconfiguration.
cmd_ha_check() {
  local dev="${1:-}"
  [ -n "$dev" ] || die "usage: framepad.sh ha-check <device-uuid>   (from the HAControl log line)"
  local sub=(mosquitto_sub -h "${MQTT_HOST:-home.kippings.de}" -p "${MQTT_PORT:-8883}"
             -u "${MQTT_USER:-car}" -P "${MQTT_PASSWORD:?set MQTT_PASSWORD}"
             --cafile /etc/ssl/cert.pem)

  echo "=== availability"
  { "${sub[@]}" -t "immichslideshow/$dev/availability" -v -W 5 2>&1 || true; } | grep -v '^Timed' || true

  # `mosquitto_sub -W` exits non-zero on its timeout, which is the NORMAL end of a
  # retained-state dump. With `set -e -o pipefail` that would abort the function midway
  # (it silently swallowed the count line once) — hence `|| true` on every subscribe.
  local raw
  raw=$("${sub[@]}" -t "homeassistant/+/$dev/+/config" -v -W 8 2>&1 || true)

  echo "=== live discovery configs (non-empty retained payloads)"
  echo "$raw" | awk -v d="$dev" '{n=length($0)-length($1)-1; if(n>0 && $1 ~ /config$/){
        gsub("homeassistant/","",$1); gsub("/"d"/","  ",$1); gsub("/config","",$1); print "  " $1}}' \
    | sort

  local count
  count=$(echo "$raw" | awk '{n=length($0)-length($1)-1; if(n>0 && $1 ~ /config$/) c++} END {print c+0}')
  echo "=== live config count: $count"
  echo "    expect 4 telemetry-only (gated) or 20 full (--uitest-entitlements=all)"
}

usage() {
  cat <<'EOF'
framepad.sh <command>

  build              build-for-testing on the device
  install            build + install the app
  launch [args...]   launch detached (app keeps running)
  logs [args...]     launch with os.Logger output streamed to stdout
  rig                configure the frame (shared link + broker)   [needs MQTT_PASSWORD]
  gates              T056: hold foreground so the coordinator announces
  diag               capture the broker/settings UI state as screenshots
  ha-check <dev-id>  assert broker state for a device id          [needs MQTT_PASSWORD]

Device prerequisites (cannot be set from the CLI):
  Settings > Developer > Enable UI Automation
  Settings > Display & Brightness > Auto-Lock > Never

See docs/device-testing.md.
EOF
}

case "${1:-}" in
  build)    shift; cmd_build "$@" ;;
  install)  shift; cmd_install "$@" ;;
  launch)   shift; cmd_launch "$@" ;;
  logs)     shift; cmd_logs "$@" ;;
  rig)      shift; cmd_rig "$@" ;;
  gates)    shift; cmd_gates "$@" ;;
  diag)     shift; cmd_diag "$@" ;;
  ha-check) shift; cmd_ha_check "$@" ;;
  *)        usage; exit 1 ;;
esac
