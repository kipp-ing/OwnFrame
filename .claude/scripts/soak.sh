#!/bin/zsh
# soak.sh — the hitl.md §7 soaks on a real, already configured frame (DeviceSoakUITests).
#
#   soak.sh <udid> offline-entitled [hours=24]   SC-1100-04: entitled + offline; clock on, airplane
#                                                on, a relaunch checkpoint every hours/4, one reboot
#                                                in the middle; airplane off again however it ends
#   soak.sh <udid> free-tier [hours=4]           SC-1100-02: an UNPURCHASED frame plays for hours
#                                                with no purchase UI (one test: fits iOS 17 / #84)
#
# Build first with `device-accept.sh <udid> build` (same DerivedData). The device must be on a
# CABLE (airplane mode cuts Wi-Fi) and, for the reboot, have no passcode — else the post-reboot
# checkpoint fails at the lock screen and says so. Results: accept-out/<udid>/soak-*.
set -u
dev=${1:?usage: soak.sh <udid> offline-entitled|free-tier [hours]}; mode=${2:?mode}
DD="${ACCEPT_DD:-$HOME/Library/Developer/Xcode/DerivedData/AcceptRig-$dev}"
OUT="${ACCEPT_OUT:-$HOME/Library/Developer/Xcode/DerivedData/accept-out/$dev}"
xctestrun=$(ls "$DD"/Build/Products/*.xctestrun 2>/dev/null | grep -v keep | head -1)
[ -n "$xctestrun" ] || { echo "no build — run: device-accept.sh $dev build" >&2; exit 1; }
mkdir -p "$OUT"

step() { # step <label> <test> [env…]
  local label=$1 t=$2; shift 2
  local r="$OUT/soak-$label.xcresult" log="$OUT/soak-$label.log"; rm -rf "$r"
  env TEST_RUNNER_SOAK=1 "$@" xcodebuild test-without-building -xctestrun "$xctestrun" \
    -destination "id=$dev" -only-testing:"OwnFrameUITests/DeviceSoakUITests/$t" \
    -resultBundlePath "$r" > "$log" 2>&1
  local rc=$?
  echo "$(date '+%F %T') $label rc=$rc $(grep -E 'error: -\[' "$log" | sed -E 's/.*error: -\[[^]]*\] : //' | head -1)"
  return $rc
}

case $mode in
  offline-entitled)
    hours=${3:-24}; gap=$(( hours * 3600 / 4 ))
    step prepare testSoakPrepareClockOn || exit 1
    trap 'step airplane-off testSoakAirplane TEST_RUNNER_AIRPLANE=off' EXIT
    step airplane-on testSoakAirplane TEST_RUNNER_AIRPLANE=on || exit 1
    fail=0
    step checkpoint-0 testSoakCheckpoint TEST_RUNNER_EXPECT_CLOCK=1 || fail=1
    for i in 1 2 3 4; do
      sleep $gap
      if [ $i = 2 ]; then
        xcrun devicectl device reboot --device "$dev" >/dev/null 2>&1
        sleep 180 # boot + CoreDevice reconnect
        echo "$(date '+%F %T') rebooted"
      fi
      step checkpoint-$i testSoakCheckpoint TEST_RUNNER_EXPECT_CLOCK=1 || fail=1
    done
    [ $fail = 0 ] && echo "SOAK PASSED (offline-entitled, ${hours} h)" || echo "SOAK FAILED — see $OUT/soak-*"
    exit $fail ;;
  free-tier)
    hours=${3:-4}
    step free-tier testFreeTierPlaybackShowsNoPurchaseUI TEST_RUNNER_HOURS="$hours" \
      && echo "SOAK PASSED (free-tier, ${hours} h)" || { echo "SOAK FAILED — see $OUT/soak-free-tier.*"; exit 1; } ;;
  *) echo "unknown mode $mode" >&2; exit 2 ;;
esac
