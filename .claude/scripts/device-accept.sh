#!/bin/zsh
# device-accept.sh — seam-free device acceptance (specs/220-onboarding-welcome/tasks.md Phase 7).
#
#   device-accept.sh <udid> build              build-for-testing for that device
#   device-accept.sh <udid> [test…]            run DeviceAcceptanceUITests, a FRESH install per test
#   device-accept.sh <udid> identity           T024: HA identity survives delete + reinstall
#
# Every test needs camera/Local Network permission undetermined and no source configured, so
# the app is uninstalled before each one, one runner launch per test. The runner uses a copy
# of the .xctestrun with attachments kept (the screenshots are the evidence). iOS 26+ devices
# only: on iOS 17, Xcode 27's testmanagerd crash (issue #84) leaves just the first test of a
# session trustworthy.
#
# EXPECT_LANG=de|en: the device's system language, which the permission alerts must use (the
# scheme runs the app in English, so the runner can't tell). Protected-link test: TEST_RUNNER_PROTECTED_LINK / TEST_RUNNER_PROTECTED_PASSWORD in the env
# (skips when unset). Identity: MQTT password from the env or the login Keychain item
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

if [ "${1:-}" = identity ]; then
  [ -n "${MQTT_PASSWORD:-}" ] || MQTT_PASSWORD="$(security find-generic-password -a "${MQTT_USER:-car}" -s ownframe-mqtt -w 2>/dev/null || true)"
  [ -n "$MQTT_PASSWORD" ] || { echo "no MQTT password (env or Keychain ownframe-mqtt)" >&2; exit 1; }
  ids() {
    mosquitto_sub -h "${MQTT_HOST:-home.kippings.de}" -p "${MQTT_PORT:-8883}" -u "${MQTT_USER:-car}" \
      -P "$MQTT_PASSWORD" --cafile /etc/ssl/cert.pem -t 'ownframe/+/availability' -v -W 6 2>/dev/null \
      | awk '$2!="" {split($1,a,"/"); print a[2]}' | sort -u
  }
  rig() {
    run "identity-$1" OwnFrameUITests/DeviceRigConfigUITests/testConfigureFrameWithSharedLinkAndBroker \
      TEST_RUNNER_DEVICE_RIG=1 TEST_RUNNER_MQTT_PASSWORD="$MQTT_PASSWORD"
  }
  rig first || exit 1
  sleep 10; before=$(ids); echo "device ids on the broker before reinstall:"; echo "$before" | sed 's/^/    /'
  uninstall
  xcrun devicectl device install app --device "$dev" "$app" >/dev/null || exit 1
  rig again || exit 1
  sleep 10; after=$(ids)
  new=$(comm -13 <(echo "$before") <(echo "$after"))
  if [ -z "$new" ]; then echo "IDENTITY OK — no new device id after delete + reinstall"
  else echo "IDENTITY FAILED — new device id(s) after reinstall (a duplicate device in HA):"; echo "$new" | sed 's/^/    /'; exit 1; fi
  exit 0
fi

[ $# -gt 0 ] && TESTS=("$@")
fail=0
for t in "${TESTS[@]}"; do
  uninstall
  run "$t" "$CLASS/$t" TEST_RUNNER_DEVICE_ACCEPT=1 TEST_RUNNER_EXPECT_LANG="${EXPECT_LANG:-}" || fail=1
done
exit $fail
