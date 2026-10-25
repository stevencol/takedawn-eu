#!/usr/bin/env bash
# hud_scene.sh <rundir> <scene> [KEY=VALUE...]
#
# One scripted drive for the HUD extent monitor (BO3_HUD_MON, core/main.c;
# docs/widescreen-hud.md). hud_extents.sh runs these in 4:3 and in 16:9 with
# display.hud_fix and compares what the monitor wrote.
#
# Scenes (Single Event, the first car):
#   race        Race, USA, the first track: accelerate, weave across the road,
#               brake into slides, use the boost. For the boost messages (AIR,
#               ONCOMING, DRIFT, NEAR MISS, TAILGATING), the sliding messages
#               of the race (the gap to the car ahead, laps) and, sooner or
#               later, a crash's letterbox and caption.
#   roadrage    Road Rage, default options, the same drive.
#   burninglap  Burning Lap (Time Attack), default options, the same drive.
#   crash       Crash, 1. Trailer Trash, to the Crash Results (to_crash.sh's
#               route).
#
# DRIVE_SECS (default 100): how long the drive lasts. With CAPTURE=1 a frame
# every FRAME_EVERY flips (default 180; the list takes 64) besides the monitor's own.
# <rundir>/anchor.txt: the flip the stage began at (tracks crash1.rws for the
# driven modes), the zero of the flips before any input of ours.
set -u
source "$(dirname "$0")/scene_lib.sh"
rd=$1; scene=$2; shift 2
scene_start "$rd" "$@"
to_main_menu
to_single_event

# drive <anchor>: from the GO on. One line of pad.txt is one held state; the
# runtime takes them in order.
drive() {
    local a=$1 secs=${DRIVE_SECS:-100} k=0 f
    if [ "${CAPTURE:-0}" = 1 ]; then
        for (( f = a + 240; f <= a + 300 + secs * 60; f += ${FRAME_EVERY:-180} )); do
            echo "$f" >> "$D/dumpat.txt"
        done
    fi
    wait_flip $(( a + 290 ))
    # About 21 s a round: straight, a weave into the oncoming lane and back,
    # a slide each way (brake with the steering held, the accelerator down),
    # a burst of boost.
    while [ $(( k * 21 )) -lt "$secs" ]; do
        k=$(( k + 1 ))
        cat >> "$D/pad.txt" <<'EOF'
rt:4000
rt+lleft:350
rt:2500
rt+lright:350
rt:2500
rt+lt+lleft:500
rt+lleft:400
rt:2000
rt+a:1500
rt+lt+lright:500
rt+lright:400
rt:2500
EOF
    done
    while [ "$(flip)" -lt $(( a + 300 + secs * 60 )) ]; do alive; sleep 1; done
}

case "$scene" in
race)
    press a:400 90              # Race: Select Options
    press right:200 25          # Region: Random > USA
    press down:200 20
    press right:200 25          # Track: Random > the first
    press a:400 90              # Select Car
    ;;
burninglap|roadrage)
    press down:200 20           # Time Attack
    [ "$scene" = roadrage ] && press down:200 20
    press a:400 90              # the mode: its options
    press a:400 90              # the defaults: Select Car
    ;;
crash)
    press down:200 20; press down:200 20; press down:200 20
    press a:400 90              # Junction Selection
    press down:200 20           # 1. Trailer Trash
    press a:400 90              # Select Car
    ;;
*)  die "unknown scene $scene" ;;
esac
wait_log 'CAR1[.]bgv' "car select (CAR1.bgv)"
press a:400 0                   # the first car: loading

if [ "$scene" = crash ]; then
    wait_log 'TrC_ENG[.]xmv' "Crash Training video (TrC_ENG.xmv)"
    wait_log 'C3_V1.streamed[.]dat' "junction streamed in"
    wait_log "$(track_re crash2)" "captions (crash2.rws)"
    b=$(anchor "$(track_re crash2)")
    echo "$b" > "$D/anchor.txt"
    wait_flip $(( b + 300 ))
    press a:400 60              # the countdown
    press rt:600000 0           # held from the countdown
    wait_log 'C3_v1.crash1[.]rws' "impact (C3_v1 crash1.rws)"
    c=$(anchor 'C3_v1.crash1[.]rws')
    if [ "${CAPTURE:-0}" = 1 ]; then
        for off in 60 300 600 900; do echo $(( c + $(cam_flips $off) )) >> "$D/dumpat.txt"; done
    fi
    wait_flip $(( c + $(cam_flips 1000) ))
else
    wait_log 'streamed[.]dat' "track streamed in"
    wait_log "$(track_re crash1)" "stage begins (tracks crash1.rws)"
    a=$(anchor "$(track_re crash1)")
    echo "$a" > "$D/anchor.txt"
    drive "$a"
fi
mkdir -p "$D/frames"
mv "$D"/fb_flip_*.bmp "$D/frames/" 2>/dev/null
scene_end "hud scene $scene"
