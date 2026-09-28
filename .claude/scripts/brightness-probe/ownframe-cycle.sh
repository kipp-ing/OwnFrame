#!/bin/zsh
# ownframe-cycle.sh <target-udid> <log> "<schedule>" [app args…] — spec 410 device check of OwnFrame
# itself (not the probe): a DEBUG OwnFrame runs the hermetic stub slideshow on the REAL screen with
# `--brightness-trace` (every write + a 0.5 s read on stdout, via --console) while FramePhone's probe
# switches light/dark on the target's sensor (schedule as in probe.sh, e.g. "dark:60 light:25").
# App args: `--brightness-fixed 0.8` = Fixed at 0.8 in memory (nothing persisted); none = Automatic.
# Needs a Debug OwnFrame installed on the target. The last level written outlives the app until the
# next lock (spec 410 finding 6) — end with a run at the target's normal level, or lock/unlock it.
#   summary:  grep READ <log> | awk '{print $4}' | sort | uniq -c | sort -rn;  grep -c WRITE <log>
target=$1 log=$2 schedule=$3; shift 3
PHONE=${PHONE_UDID:-00008110-000568303444801E}   # FramePhone
: > $log.marks
xcrun devicectl device process launch --device $target --terminate-existing --console ing.kipp.Immich-Slideshow \
  --uitest --uitest-slideshow --brightness-trace "$@" > $log 2>&1 &
pid=$!
sleep 4
for step in ${=schedule}; do
  xcrun devicectl device process launch --device $PHONE --terminate-existing ing.kipp.BrightnessProbe --mode ${step%%:*} >/dev/null 2>&1
  echo "$(date +%H:%M:%S) phone=${step%%:*}" >> $log.marks; sleep ${step##*:}
done
kill $pid 2>/dev/null; pkill -f "devicectl device process launch --device $target"
