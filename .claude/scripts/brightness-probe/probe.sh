#!/bin/zsh
# probe.sh — brightness probe rig (spec 410 device findings). A throwaway app, ing.kipp.BrightnessProbe,
# logs UIScreen.brightness every 0.5 s on the TARGET device; FramePhone lies face-down on the target's
# ambient light sensor as a switchable light source (white screen at full brightness vs black).
#
#   probe.sh build                                 build the probe (DerivedData, not the repo)
#   probe.sh install <udid>…                       install it on each device (FramePhone + target)
#   probe.sh cycle <target-udid> "<schedule>" <log> [probe args…]
#        schedule = phone steps "light:25 dark:40 light:30" (seconds each); the target probe runs for
#        the whole schedule. Probe args: --mode watch (default) [--set 0.8 --at 10] [--reassert 1]
#   probe.sh show <log>                            marks + every 4th sample, 4 per line
#
# Traps (2026-09-28): the probe's own --mode light|dark WRITES brightness (1.0 / 0.0) — never launch
# those on the target, only on the light-source phone; a relaunch with --terminate-existing is how an
# old instance is killed. Every write outlives the app until the next lock and shifts the
# auto-brightness curve (spec 410 findings 6–8), so note the target's state before and after.
set -u
here=${0:A:h}; DD="$HOME/Library/Developer/Xcode/DerivedData/BrightnessProbe"
APP="$DD/Build/Products/Debug-iphoneos/Probe.app"; B=ing.kipp.BrightnessProbe
PHONE=${PHONE_UDID:-00008110-000568303444801E}   # FramePhone
case ${1:-} in
build)
  xcodebuild -project "$here/Probe.xcodeproj" -scheme Probe -configuration Debug \
    -destination generic/platform=iOS -derivedDataPath "$DD" -allowProvisioningUpdates build 2>&1 \
    | grep -E "error|BUILD" ;;
install)
  shift; for d in "$@"; do xcrun devicectl device install app --device "$d" "$APP" >/dev/null 2>&1 \
    && echo "installed on $d" || echo "install FAILED on $d"; done ;;
cycle)
  target=$2 schedule=$3 log=$4; shift 4
  : > "$log.marks"
  xcrun devicectl device process launch --device "$target" --terminate-existing --console $B "$@" > "$log" 2>&1 &
  pid=$!
  for step in ${=schedule}; do
    xcrun devicectl device process launch --device $PHONE --terminate-existing $B --mode ${step%%:*} >/dev/null 2>&1
    echo "$(date +%T) phone=${step%%:*}" >> "$log.marks"; sleep ${step##*:}
  done
  kill $pid 2>/dev/null ;;
show)
  cat "$2.marks"; grep PROBE "$2" | awk '/WRITE/ || NR%4==1' | cut -c1-40 | paste - - - - ;;
*) sed -n 2,19p "$0"; exit 1 ;;
esac
