#!/bin/zsh
# device-accept.sh — seam-free device acceptance (specs/220-onboarding-welcome/tasks.md Phase 7).
#
#   device-accept.sh <udid> build              build-for-testing for that device
#   device-accept.sh <udid> [test…]            run DeviceAcceptanceUITests (or Class/test), a FRESH install per test
#   device-accept.sh <udid> resilience         offline cold launch (#80) + 2 min offline recovery (cable!)
#   device-accept.sh <udid> arrival            a photo uploaded to the test album appears within one
#                                              refresh (~65 min; immich-test-album.sh once before)
#   device-accept.sh <udid> availability       PR #49: HA stays online with Settings open, bg tears down
#   device-accept.sh <udid> identity           T024: HA identity survives delete + reinstall
#                                              (needs mosquitto_sub; the frame joins the live broker)
#   device-accept.sh <udid> upgrade            SC-1100-06/FR-1100-03a: clear the sandbox purchase history
#                                              (ASC API), reinstall + rig → HA gets sensors only; buy the
#                                              Supporter Unlock → controls come back, nothing re-entered
#   device-accept.sh <udid> ha-parity          900 HA parity + #48: an ENTITLED frame on the broker gets its
#                                              largest Photos album as a 2nd source; the select lists it, its
#                                              metadata has a date and no place, no image without the
#                                              opt-in; rapid source switches end online on the last choice
#
# Every test needs camera/Local Network permission undetermined and no source configured, so
# the app is uninstalled before each one, one runner launch per test. The runner uses a copy
# of the .xctestrun with attachments kept (the screenshots are the evidence). iOS 26+ devices
# only: on iOS 17, Xcode 27's testmanagerd crash (issue #84) leaves just the first test of a
# session trustworthy — except single-test modes (arrival), which fit that limit.
#
# LOGCHECK=1 (default test loop): record the device log (idevicesyslog) during each test and fail
# if the protected link's password or either link's share key shows up in a line logged by an
# OwnFrame process (app or extension — Safari and the test runner see them legitimately).
#
# EXPECT_LANG=de|en: the device's system language, which the permission alerts must use (the
# scheme runs the app in English, so the runner can't tell). Protected-link test: link + password
# from TEST_RUNNER_PROTECTED_LINK / TEST_RUNNER_PROTECTED_PASSWORD, else from the login Keychain
# item `ownframe-protected-link` (account = the link); skips when neither is there. Identity: MQTT password from the env or the login Keychain item
# `ownframe-mqtt`, exactly like framepad.sh. UNINSTALLS the app — local settings are lost;
# purchases come back via StoreKit.
set -u
dev=${1:?usage: device-accept.sh <udid> build|identity|[test…]}; shift
BUNDLE_ID="ing.kipp.Immich-Slideshow"
DD="${ACCEPT_DD:-$HOME/Library/Developer/Xcode/DerivedData/AcceptRig-$dev}"
OUT="${ACCEPT_OUT:-$HOME/Library/Developer/Xcode/DerivedData/accept-out/$dev}"
CLASS="OwnFrameUITests/DeviceAcceptanceUITests"
TESTS=(testCameraAllowedScannerStaysUsableAndCancelReturns testCameraDeniedShowsCalmFallback
       testFreshInstallDemoLinkReachesRunningSlideshow testFreshInstallProtectedLinkRejectsWrongPasswordThenStarts)
cd "$(dirname "$0")/../.."
mkdir -p "$OUT"

if [ "${1:-}" = build ]; then
  xcodebuild build-for-testing -project OwnFrame.xcodeproj -scheme OwnFrame -destination "id=$dev" \
    -configuration Debug -derivedDataPath "$DD" -allowProvisioningUpdates > "$OUT/build.log" 2>&1 \
    && echo "ok — built into $DD" || { grep -E "error:" "$OUT/build.log" | head; exit 1; }
  exit 0
fi

products="$DD/Build/Products"
src=$(ls "$products"/*.xctestrun 2>/dev/null | grep -v keep | head -1)
[ -n "$src" ] || { echo "no build — run: $0 $dev build" >&2; exit 1; }
xctestrun="$products/keep.xctestrun"
python3 - "$src" "$xctestrun" <<'PY'
import plistlib, sys
p = plistlib.load(open(sys.argv[1], "rb"))
for c in p.get("TestConfigurations", []):
    for t in c["TestTargets"]:
        t["SystemAttachmentLifetime"] = t["UserAttachmentLifetime"] = "keepAlways"
plistlib.dump(p, open(sys.argv[2], "wb"))
PY
app="$products/Debug-iphoneos/OwnFrame.app"

uninstall() { xcrun devicectl device uninstall app --device "$dev" "$BUNDLE_ID" >/dev/null 2>&1 || true; }

# run <label> <only-testing> [env…]: one runner launch, result bundle per label.
run() {
  local label=$1 only=$2; shift 2
  local r="$OUT/$label.xcresult" log="$OUT/$label.log"
  rm -rf "$r"
  env "$@" xcodebuild test-without-building -xctestrun "$xctestrun" -destination "id=$dev" \
    -only-testing:"$only" -resultBundlePath "$r" > "$log" 2>&1
  local rc=$?
  local p=$(grep -cE "^Test Case .* passed" "$log") f=$(grep -cE "^Test Case .* failed" "$log") \
        s=$(grep -cE "^Test Case .* skipped" "$log")
  echo "$label rc=$rc passed=$p failed=$f skipped=$s"
  grep -E "error: -\[" "$log" | sed -E 's|.*/OwnFrame|    OwnFrame|' | cut -c1-300
  return $rc
}

if [ "${1:-}" = identity ] || [ "${1:-}" = availability ] || [ "${1:-}" = upgrade ] || [ "${1:-}" = ha-parity ]; then
  [ -n "${MQTT_PASSWORD:-}" ] || MQTT_PASSWORD="$(security find-generic-password -a "${MQTT_USER:-mqtt-car}" -s ownframe-mqtt -w 2>/dev/null || true)"
  [ -n "$MQTT_PASSWORD" ] || { echo "no MQTT password (env or Keychain ownframe-mqtt)" >&2; exit 1; }
  sub=(mosquitto_sub -h "${MQTT_HOST:-home.kippings.de}" -p "${MQTT_PORT:-8883}" -u "${MQTT_USER:-mqtt-car}"
       -P "$MQTT_PASSWORD" --cafile /etc/ssl/cert.pem)
  # The device id that is LIVE right now: launch the app and collect ids from fresh messages
  # only (-R drops stale retained ones). A snapshot of retained topics alone would pass even if
  # the reinstalled app never reached the broker — a false green.
  live_id() {
    local tmp; tmp=$(mktemp)
    "${sub[@]}" -t 'ownframe/+/#' -v -R -W 45 > "$tmp" 2>/dev/null &
    local pid=$!
    sleep 2
    xcrun devicectl device process launch --device "$dev" "$BUNDLE_ID" >/dev/null 2>&1
    wait $pid
    awk '{split($1,a,"/"); print a[2]}' "$tmp" | sort -u; rm -f "$tmp"
  }
  rig() {
    run "identity-$1" OwnFrameUITests/DeviceRigConfigUITests/testConfigureFrameWithSharedLinkAndBroker \
      TEST_RUNNER_DEVICE_RIG=1 TEST_RUNNER_MQTT_PASSWORD="$MQTT_PASSWORD"
  }
  # controls: how many of the frame's retained HA discovery configs carry a command_topic.
  controls() {
    "${sub[@]}" -t "homeassistant/+/$1/+/config" -v -W 6 2>/dev/null | grep -c command_topic
  }
  if [ "$1" = upgrade ]; then
    # The sandbox account signed in on the device (Settings → Developer) must be unpurchased
    # for the buy to be real: clear its history through the ASC API (tester id in the Keychain
    # item `ownframe-sandbox-tester`), then a fresh install so no cached unlock survives
    # (an omission deliberately never relocks). Password: Keychain `ownframe-sandbox`.
    tester="${SANDBOX_TESTER_ID:-$(security find-generic-password -s ownframe-sandbox-tester -w 2>/dev/null)}"
    spw="$(security find-generic-password -s ownframe-sandbox -w 2>/dev/null || true)"
    [ -n "$tester" ] && [ -n "$spw" ] || { echo "no sandbox tester id / password in the Keychain" >&2; exit 1; }
    bash "$(dirname "$0")/asc-api.sh" POST /v2/sandboxTestersClearPurchaseHistoryRequest \
      "{\"data\":{\"type\":\"sandboxTestersClearPurchaseHistoryRequest\",\"relationships\":{\"sandboxTesters\":{\"data\":[{\"type\":\"sandboxTesters\",\"id\":\"$tester\"}]}}}}" \
      | grep -q '"id"' || { echo "clearing the sandbox purchase history failed" >&2; exit 1; }
    echo "sandbox purchase history cleared; waiting ${CLEAR_WAIT:-180} s for it to reach StoreKit"
    sleep "${CLEAR_WAIT:-180}"
    uninstall
    rig first || exit 1
    id=$(live_id)
    [ "$(echo "$id" | grep -c .)" = 1 ] || { echo "expected exactly one live device id, got:"; echo "$id"; exit 1; }
    c0=$(controls "$id"); echo "unentitled: $c0 controllable discovery configs (want 0)"
    run upgrade-buy OwnFrameUITests/DevicePurchaseUITests/testSandboxPurchaseUnlocksWithoutSecondTap \
      TEST_RUNNER_DEVICE_PURCHASE=1 TEST_RUNNER_SANDBOX_PASSWORD="$spw" \
      TEST_RUNNER_PURCHASE_LABELS="${PURCHASE_LABELS:-}" || exit 1
    after=$(live_id)  # a plain relaunch, nothing re-entered
    c1=$(controls "$id"); echo "entitled:   $c1 controllable discovery configs (want > 0), live id ${after:-<none>}"
    if [ "$c0" = 0 ] && [ "$c1" -gt 0 ] && [ "$after" = "$id" ]; then
      echo "UPGRADE OK — sensors only while unentitled; buying brought the controls back, same frame, nothing re-entered"
    else echo "UPGRADE FAILED"; exit 1; fi
    exit 0
  fi
  if [ "$1" = ha-parity ]; then
    pub() { mosquitto_pub -h "${MQTT_HOST:-home.kippings.de}" -p "${MQTT_PORT:-8883}" -u "${MQTT_USER:-mqtt-car}" \
              -P "$MQTT_PASSWORD" --cafile /etc/ssl/cert.pem -t "$1" -m "$2"; }
    # PHOTOS_SOURCE=<title> reuses a Photos album an earlier run already added.
    # SECOND=link: no Photos album on the device — add the test album's Immich link instead;
    # the Photos-only parity checks are skipped, the race step still runs.
    photos="${PHOTOS_SOURCE:-}"; kind=photos
    if [ "${SECOND:-}" = link ] && [ -z "$photos" ]; then
      kind=link
      second="$(security find-generic-password -s ownframe-test-album 2>/dev/null | sed -n 's/^ *"acct"<blob>="\(.*\)"$/\1/p')"
      run ha-parity-add OwnFrameUITests/DeviceHAParityUITests/testAddSecondImmichLinkSource \
        TEST_RUNNER_DEVICE_HA_PARITY=1 TEST_RUNNER_SECOND_LINK="$second" || exit 1
      photos="Race B"
    elif [ -z "$photos" ]; then
      run ha-parity-add OwnFrameUITests/DeviceHAParityUITests/testAddFirstPhotosAlbumAsSecondSource \
        TEST_RUNNER_DEVICE_HA_PARITY=1 TEST_RUNNER_PHOTOS_ALBUM="${PHOTOS_ALBUM:-}" || exit 1
      photos=$(sed -n 's/^photos-source: //p' "$OUT/ha-parity-add.log" | head -1 | tr -d '\r' | sed 's/[[:space:]]*$//')
    fi
    id=$(live_id)
    [ "$(echo "$id" | grep -c .)" = 1 ] || { echo "expected exactly one live device id, got:"; echo "$id"; exit 1; }
    t="ownframe/$id"
    opts=$("${sub[@]}" -t "homeassistant/select/$id/album/config" -C 1 -W 6 2>/dev/null)
    first=$(echo "$opts" | python3 -c 'import json,sys; print(json.load(sys.stdin)["options"][0])')
    echo "$opts" | PHOTOS="$photos" python3 -c 'import json,os,sys; o=json.load(sys.stdin)["options"]; print("album select:", o); sys.exit(os.environ["PHOTOS"] not in o)' \
      || { echo "HA PARITY FAILED — the select does not list the Photos album '$photos'"; exit 1; }
    # Switch to the Photos album and record everything the frame publishes for a while.
    rec="$OUT/ha-parity.mqtt"
    "${sub[@]}" -t "$t/#" -v -R -W 40 -F '%t %p' > "$rec" 2>/dev/null &
    recpid=$!; sleep 2
    pub "$t/album/set" "$photos"
    wait $recpid
    [ "$kind" = link ] && echo "(link source: Photos parity checks skipped)"
    [ "$kind" = link ] || python3 - "$rec" "$photos" <<'PY' || exit 1
import json, sys
lines = [l.rstrip("\n").split(" ", 1) for l in open(sys.argv[1]) if " " in l]
album = [p for t, p in lines if t.endswith("/album/state")]
photos = [json.loads(p) for t, p in lines if t.endswith("/current_photo/state") and p.startswith("{")]
images = [t for t, p in lines if "image" in t.split("/")[2:] and p]
ok = True
print("album/state:", album[-1:] or "none")
if not album or album[-1] != sys.argv[2]: ok = False; print("FAIL: the frame did not switch to the Photos album")
if not photos: ok = False; print("FAIL: no current_photo metadata after the switch")
for ph in photos[-1:]:
    print("current_photo:", ph)
    if not ph.get("taken_at"): ok = False; print("FAIL: no capture date")
    if any(ph.get(k) for k in ("city", "state", "country")): ok = False; print("FAIL: a place left the device")
    if any(k in ph for k in ("latitude", "longitude", "lat", "lon")): print("note: coordinates published")
if images: ok = False; print("FAIL: image published without the opt-in:", images[:3])
print("HA PARITY OK" if ok else "HA PARITY FAILED")
sys.exit(0 if ok else 1)
PY
    # #48: rapid source switches with brightness changes in between must end online, on the
    # last source and the last brightness — never offline while the frame plays.
    for i in 1 2 3 4 5 6; do
      pub "$t/album/set" "$([ $((i % 2)) = 1 ] && echo "$first" || echo "$photos")"
      pub "$t/brightness/set" "$((i % 2 ? 60 : 200))"
      sleep 1
    done
    sleep 30
    final=$("${sub[@]}" -t "$t/availability" -t "$t/album/state" -t "$t/brightness/state" -t "$t/frame_status/state" \
              -v -W 5 2>/dev/null)
    echo "$final" | sed 's/^/  /'
    pub "$t/album/set" "$first"
    if echo "$final" | grep -q "availability online" && echo "$final" | grep -q "album/state $photos" \
       && echo "$final" | grep -qE "brightness/state (19[5-9]|20[0-5])$" && echo "$final" | grep -q "frame_status/state running"; then
      echo "RACE OK — six switches later: online, last source, last brightness, running"
    else echo "RACE FAILED (brightness 255 after a switch = issue #91)"; exit 1; fi
    exit 0
  fi
  if [ "$1" = availability ]; then
    # PR #49 (hitl §4): record the frame's topics with wall-clock stamps while the rig test
    # walks slideshow → Settings → Done → background → foreground, then line both up.
    # SKIP_RIG=1 reuses a frame the rig already configured (the rig takes ~20 min: every
    # keystroke waits out the slideshow's never-idle animations).
    [ -n "${SKIP_RIG:-}" ] || { uninstall; rig first || exit 1; }
    id=$(live_id)
    sleep 10 # let that launch settle, else the runner can time out enabling automation mode
    [ "$(echo "$id" | grep -c .)" = 1 ] || { echo "expected exactly one live device id, got:"; echo "$id"; exit 1; }
    rec="$OUT/availability.mqtt"
    "${sub[@]}" -t "ownframe/$id/availability" -t "ownframe/$id/frame_status/state" -F '%U %t %p' > "$rec" 2>/dev/null &
    recpid=$!
    run availability OwnFrameUITests/DeviceRigConfigUITests/testSettingsOverSlideshowThenBackground \
      TEST_RUNNER_DEVICE_RIG=1; rc=$?
    kill $recpid 2>/dev/null
    "${sub[@]}" -t "homeassistant/+/$id/+/config" -v -W 6 2>/dev/null \
      | awk '{print ($0 ~ /command_topic/) ? "control" : "sensor"}' | sort | uniq -c | sed 's/^/  discovery: /'
    python3 "$(dirname "$0")/check-availability.py" "$OUT/availability.log" "$rec" || rc=1
    exit $rc
  fi
  rig first || exit 1
  before=$(live_id)
  [ "$(echo "$before" | grep -c .)" = 1 ] || { echo "expected exactly one live device id, got:"; echo "$before"; exit 1; }
  echo "live device id before reinstall: $before"
  uninstall
  xcrun devicectl device install app --device "$dev" "$app" >/dev/null || exit 1
  rig again || exit 1
  after=$(live_id)
  echo "live device id after reinstall:  ${after:-<none>}"
  if [ "$after" = "$before" ]; then echo "IDENTITY OK — the reinstalled frame publishes under the same device id"
  else echo "IDENTITY FAILED — a different (or no) live device id after delete + reinstall"; exit 1; fi
  exit 0
fi

if [ -z "${TEST_RUNNER_PROTECTED_LINK:-}" ]; then
  TEST_RUNNER_PROTECTED_LINK="$(security find-generic-password -s ownframe-protected-link 2>/dev/null \
    | sed -n 's/^ *"acct"<blob>="\(.*\)"$/\1/p')"
  TEST_RUNNER_PROTECTED_PASSWORD="$(security find-generic-password -s ownframe-protected-link -w 2>/dev/null || true)"
fi
export TEST_RUNNER_PROTECTED_LINK TEST_RUNNER_PROTECTED_PASSWORD

# arrival: the test album + upload key from the Keychain (immich-test-album.sh made both).
if [ "${1:-}" = arrival ]; then
  TEST_RUNNER_ARRIVAL_LINK="$(security find-generic-password -s ownframe-test-album 2>/dev/null \
    | sed -n 's/^ *"acct"<blob>="\(.*\)"$/\1/p')"
  TEST_RUNNER_ARRIVAL_ALBUM="$(security find-generic-password -s ownframe-test-album -w 2>/dev/null || true)"
  TEST_RUNNER_IMMICH_UPLOAD_KEY="$(security find-generic-password -a immich-upload -s ownframe-immich-upload -w 2>/dev/null || true)"
  [ -n "$TEST_RUNNER_ARRIVAL_LINK" ] && [ -n "$TEST_RUNNER_IMMICH_UPLOAD_KEY" ] \
    || { echo "no test album or upload key — run immich-test-album.sh first" >&2; exit 1; }
  export TEST_RUNNER_ARRIVAL_LINK TEST_RUNNER_ARRIVAL_ALBUM TEST_RUNNER_IMMICH_UPLOAD_KEY
fi

# resilience: airplane mode through Control Center — the device must be on a CABLE.
if [ "${1:-}" = resilience ]; then TESTS=(testOfflineColdLaunchResumesTheSlideshow testTwoMinutesOfflineThenRecovers)
elif [ "${1:-}" = arrival ]; then TESTS=(testNewServerPhotoAppearsWithinOneRefresh)
elif [ $# -gt 0 ]; then TESTS=("$@"); fi
fail=0
# Secrets that must never reach the device log: the password and the share keys (the path
# segment after /s/) of both test links.
secrets=("${TEST_RUNNER_PROTECTED_PASSWORD:-}" "${TEST_RUNNER_PROTECTED_LINK##*/s/}" Iceland2021)
for t in "${TESTS[@]}"; do
  uninstall
  only="$CLASS/$t"; [[ $t == */* ]] && only="OwnFrameUITests/$t"   # Class/test runs another class
  label="${t//\//-}"
  if [ -n "${LOGCHECK:-}" ]; then idevicesyslog -u "$dev" --no-colors > "$OUT/$label.syslog" 2>/dev/null & logpid=$!; fi
  run "$label" "$only" TEST_RUNNER_DEVICE_ACCEPT=1 TEST_RUNNER_EXPECT_LANG="${EXPECT_LANG:-}" || fail=1
  if [ -n "${LOGCHECK:-}" ]; then
    kill $logpid 2>/dev/null; wait $logpid 2>/dev/null
    for sec in "${secrets[@]}"; do
      [ ${#sec} -ge 6 ] || continue
      n=$(grep -E ' OwnFrame[A-Za-z]*(\([^)]*\))?\[' "$OUT/$label.syslog" | grep -v 'UITests-Runner' | grep -F -c -- "$sec")
      [ "$n" = 0 ] || { echo "  LOG LEAK: a test secret appears $n× in $label.syslog"; fail=1; }
    done
    echo "  log check: $(grep -cE ' OwnFrame[A-Za-z]*(\([^)]*\))?\[' "$OUT/$label.syslog" | tr -d ' ') OwnFrame log lines searched"
  fi
done
exit $fail
