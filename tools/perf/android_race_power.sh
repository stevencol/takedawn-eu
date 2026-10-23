#!/usr/bin/env bash
# android_race_power.sh <rundir> [KEY=VALUE...]
#
# One measured race on an Android device over adb: tools/headless/race_drive.sh
# (the title's AI drives Silver Lake Southbound) through
# tools/android/scene-launch.sh, and from WARM seconds after the AI takes
# the car, SECS seconds of android_sample.sh on the device. Then the game is
# stopped and <rundir>/power.json and power.txt hold the summary
# (android_power.py): busy GHz, clocks, temperatures, battery watts where
# readable, the busiest threads, the frame rate; meminfo.txt the game's
# memory at the end of the samples (dumpsys meminfo).
#
#   ADB="adb -s <serial>" tools/perf/android_race_power.sh runs/poco-base
#   tools/perf/android_race_power.sh runs/poco-lead0 RECOMP_PRESENT_SPIN_LEAD=0
#
# KEY=VALUE pairs go to the game (the scene's RECOMP_* variables). The run
# uses its own save root and settings file on the device (scene-launch.sh),
# never the player's: the saves come from SAVES_FROM_DEVICE (a folder with
# UDATA, default /sdcard/takedawn-pal-backup/saves), the settings from
# SETTINGS_FROM (a settings.toml on the host; default none: the build's
# defaults). COOL=s waits until the hottest CPU zone is under COOL degrees
# before the start (default 50), so runs start alike.
set -u
REPO="$(cd "$(dirname "$0")/../.." && pwd)"
export REPO
ADB="${ADB:-adb}"
export ADB
P=io.github.xenophobentx.takedawn
F=/sdcard/Android/data/$P/files
R="$1"; shift
mkdir -p "$R"
R="$(cd "$R" && pwd)"
SECS="${SECS:-120}"
WARM="${WARM:-15}"
# Git Bash on Windows: the device's paths stay as they are; the host's are
# still converted for adb.exe.
export MSYS2_ARG_CONV_EXCL="/sdcard;/data;/storage;/system;/proc"

# The same start for every run: the phone cool enough.
cool="${COOL:-50}"
$ADB shell am force-stop $P
for i in $(seq 1 120); do
    t=$($ADB shell 'for z in /sys/class/thermal/thermal_zone*; do case "$(cat $z/type)" in *cpu*|*CPU*) cat $z/temp;; esac; done 2>/dev/null' \
        | awk 'BEGIN{m=0} {v=$1; if (v>1000) v/=1000; if (v>m) m=v} END{printf "%d", m}')
    [ "${t:-0}" -lt "$cool" ] && break
    [ $(( i % 6 )) = 1 ] && echo "android_race_power: CPU at $t C, waiting for $cool C" >&2
    sleep 10
done

settings="$F/scene-settings.toml"
if [ -n "${SETTINGS_FROM:-}" ]; then
    $ADB push "$SETTINGS_FROM" "$settings" > /dev/null
else
    $ADB shell "rm -f $settings"
fi
$ADB push "$REPO/tools/perf/android_sample.sh" /data/local/tmp/android_sample.sh > /dev/null
# The sampler off the cores the game pins (little_cores.sh says why).
. "$REPO/tools/android/little_cores.sh"
LITTLE=$(little_mask)

# The sampler: once the AI has the car (the scene's own log line), WARM
# seconds, then SECS of samples; then the game is stopped, which ends the
# scene.
(
    until grep -aq '\[AUTOPILOT\] engaged' "$R/log.txt" 2>/dev/null; do sleep 1; done
    sleep "$WARM"
    lastflip() { grep -a -o '\[GPU\] flip [0-9]*' "$R/log.txt" | tail -n 1 | awk '{print $3}'; }
    f0=$(lastflip)
    $ADB shell taskset $LITTLE sh /data/local/tmp/android_sample.sh "$SECS" $P > "$R/sample.txt"
    echo "$f0 $(lastflip)" > "$R/flips.txt"
    $ADB shell dumpsys meminfo $P > "$R/meminfo.txt" 2>/dev/null
    cp "$R/log.txt" "$R/log-at-end.txt"
    $ADB shell am force-stop $P
) &
spid=$!

# A save root of the run's own: on some phones (a Samsung) the shell may
# not delete what the app wrote, so a reused root keeps the last run's files.
ANDROID_SAVE_DIR="${ANDROID_SAVE_DIR:-$F/scene-saves-$(date +%Y%m%d-%H%M%S)}" \
ANDROID_SAVES_FROM_DEVICE="${SAVES_FROM_DEVICE:-/sdcard/takedawn-pal-backup/saves}" \
LAUNCH="$REPO/tools/android/scene-launch.sh" GAME_DIR="$R" SAVES=none \
SCENE_TIMEOUT="${SCENE_TIMEOUT:-600}" RACE_LIMIT=$(( SECS + WARM + 600 )) \
    bash "$REPO/tools/headless/race_drive.sh" "$R" "$@" > "$R/scene.out" 2>&1
wait "$spid" 2>/dev/null
$ADB shell "am force-stop $P; rm -f $F/scene-env.txt"

[ -s "$R/sample.txt" ] || { echo "android_race_power: no samples (see $R/scene.out)" >&2; tail -5 "$R/scene.out" >&2; exit 1; }
py="${TAKEDAWN_PYTHON:-python3}"
"$py" "$REPO/tools/perf/android_power.py" "$R/sample.txt" "$R/log-at-end.txt" "$R/flips.txt" --json > "$R/power.json"
"$py" "$REPO/tools/perf/android_power.py" "$R/sample.txt" "$R/log-at-end.txt" "$R/flips.txt" | tee "$R/power.txt"
