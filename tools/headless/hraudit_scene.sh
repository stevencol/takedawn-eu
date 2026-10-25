#!/usr/bin/env bash
# hraudit_scene.sh <rundir> [KEY=VALUE...]: the BO-275 High refresh audit
# (core/hraudit.c). Single Event > Race (Silver Lake), autopilot, High
# refresh on at RECOMP_FLIP_PACING=host:<HZ> (default 120), then one audit
# cycle per item of CYCLES (default below), each "<tag>:<blend|noblend>:<diff
# samples>:<watch samples>[:<action>]", action one of race (as it comes),
# look (look back held), pause (the pause menu), impact (Crash mode: after
# the impact). MODE=crash: Crash mode, junction 1, accelerator held, instead
# of the race. HR=0: High refresh off (the counters' 60 Hz reference);
# CYCLES=none: no audit cycle; TAIL_S=<s>: race on so long after them.
# Reports in <rundir>:
# <tag>.diff.txt, <tag>.watch.txt; symbols with hraudit_sym.py.
set -u
REPO="${REPO:-$(cd "$(dirname "$0")/../.." && pwd)}"
source "$REPO/tools/headless/scene_lib.sh"
HZ=${HZ:-120}
HR_K=$(( HZ * 100 / 60 ))
# Menus count flips; at HZ the front end still runs at 60, the race at HZ.
eval "orig_$(declare -f wait_flip)"
wait_flip() {
    local cur; cur=$(flip)
    if [ "$1" -gt "$cur" ]; then orig_wait_flip $(( cur + ($1 - cur) * HR_K / 100 )); fi
}
R="$(cd "$REPO" && mkdir -p "$1" && cd "$1" && pwd)"
: > "$R/ctl.txt"; rm -f "$R"/*.done
STOP_AT_END=1
scene_start "$@" RECOMP_DEBUG="${AUDIT_DEBUG:-autopilot=1,pad_script_keep=1}" RECOMP_GFX_HIGH_REFRESH=${HR:-1} \
    RECOMP_FLIP_PACING=host:$HZ BO3_HIREFRESH_STATS=1 BO3_HRAUDIT_CTL="$R/ctl.txt" BO3_HRAUDIT_OUT="$R"
to_main_menu
to_single_event
if [ "${MODE:-race}" = crash ]; then
    # Crash mode, 1. Trailer Trash (as to_crash.sh); the accelerator held from the countdown
    press down:200 20; press down:200 20; press down:200 20
    press a:400 90
    press down:200 20
    press a:400 90
    wait_log 'CAR1[.]bgv' "car select"
    press a:400 0
    wait_log 'C3_V1.streamed[.]dat' "junction streamed in"
    wait_log "$(track_re crash2)" "captions"
    wait_flip $(( $(anchor "$(track_re crash2)") + 300 ))
    press a:400 60
    press rt:600000 0
    note "driving to the junction from flip $(flip)"
else
    press a:400 90
    press right:200 25
    press down:200 20
    press right:200 25
    press a:400 90
    wait_log 'CAR1[.]bgv' "car select"
    press a:400 0
    wait_log "$(track_re crash1)" "race begins"
    grep -aq 'tracks.US.C1_V2.streamed' "$D/log.txt" || note "not Silver Lake: $(grep -ao 'tracks.US.C[0-9]_V[0-9].streamed' "$D/log.txt" | head -1)"
    wait_count '\[AUTOPILOT\] engaged' 1
    sleep ${LEAD:-8}
    note "racing from flip $(flip)"
fi
[ "${CYCLES:-}" = none ] && CYCLES=" "
for c in ${CYCLES:-race_nb:noblend:40:30 race_bl:blend:30:20 look_nb:noblend:16:10:look pause_nb:noblend:16:10:pause}; do
    IFS=: read -r tag mode nd nw act <<< "$c"
    case "${act:-race}" in
        look)  press x:${LOOK_MS:-20000} 0 ;;
        pause) press start:200 0; sleep 3 ;;
        impact) wait_log 'C3_v1.crash1[.]rws' "impact"; sleep ${IMPACT_LEAD:-1} ;;
    esac
    echo "go $tag $mode $nd $nw" >> "$R/ctl.txt"
    note "cycle $tag ($mode $nd/$nw ${act:-race}) at flip $(flip)"
    t=$(date +%s)
    until [ -f "$R/$tag.done" ]; do
        alive
        [ $(( $(date +%s) - t )) -gt ${CYCLE_S:-400} ] && { note "cycle $tag timed out"; break; }
        sleep 1
    done
    note "cycle $tag done at flip $(flip)"
    case "${act:-race}" in pause) press start:200 0; sleep 3 ;; esac
done
# TAIL_S: race on for so many seconds more (the counters, a forced flash)
t=$(date +%s); while [ $(( $(date +%s) - t )) -lt ${TAIL_S:-0} ]; do alive; sleep 1; done
scene_stop
