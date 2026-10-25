#!/usr/bin/env bash
# crash60_scene.sh <rundir> <scene> [KEY=VALUE...]
#
# The scenes the 60 fps crash camera switch is checked on (graphics.crash_60fps,
# BO-111, docs/crash60.md), with the title's pacing state logged per flip
# (BO3_PACE_LOG, core/main.c) into <rundir>/pace.txt. Run it once as
# shipped and once with RECOMP_GFX_CRASH_60FPS=1 after the scene name;
# tools/headless/pace_report.py <rundir>... compares the two.
#
# Scenes (Single Event, the first car), as fx_scene.sh:
#   crash       Crash, 1. Trailer Trash: the accelerator held from the
#               countdown, the impact, the crash camera (Impact Time), Crash
#               Results. The same input every run: the crash camera's length
#               and the score are the title's own measure of the game's
#               speed. Runs RESULTS_SECS seconds (default 60) past the
#               impact: the camera, Crash Results. IMPACT_TIME=<s>: the
#               boost button held from about <s> seconds into the camera
#               for six seconds (the title's slow motion with aftertouch).
#   race        Race, USA, the first track: DRIVE_SECS seconds (default 90)
#               of full throttle into whatever comes, steering into the
#               walls, with boost. Crash cameras as they come.
#   roadrage    Road Rage, default options, the same drive (takedowns and
#               their cameras as they come).
#   frontend    the menus only: main menu, Single Event, the garage.
#
# With CAPTURE=1 the frames of each crash camera are dumped as they come
# (CAM_FRAMES consecutive flips, default 48, from CAM_SKIP flips after its
# start, default 30) into <rundir>/cam/: motion from frame to frame, and the
# picture, with the switch and without.
#
# SWITCH_AT=<n>: in the crash scene, set graphics.crash_60fps on <n> flips
# into the crash camera and off again 3 x <n> flips later (BO3_FX_AT): the
# change in one run. Not together with RECOMP_GFX_CRASH_60FPS (it locks the
# setting).
#
# Never run with the player's HOME: give HOME and RECOMP_SETTINGS scratch
# paths (docs/crash60.md has the command).
set -u
source "$(dirname "$0")/scene_lib.sh"
rd=$1; scene=$2; shift 2
REPO="${REPO:-$(cd "$(dirname "$0")/../.." && pwd)}"
abs="$(cd "$REPO" && mkdir -p "$rd" && cd "$rd" && pwd)"
rm -rf "$abs/cam"; rm -f "$abs/pace.txt" "$abs/fx.txt"
: > "$abs/fx.txt"
scene_start "$rd" BO3_PACE_LOG="${GAME_PATH_PREFIX:-}$abs/pace.txt" \
    BO3_FX_AT="${GAME_PATH_PREFIX:-}$abs/fx.txt" "$@"

# pace <field>: the newest pace line's value after the word <field>.
pace() {
    tail -n 1 "$D/pace.txt" 2>/dev/null | awk -v k="$1" '
        { for (i = 1; i < NF; i++) if ($i == k) { print $(i + 1); exit } }'
}

# cam_watch: until the game ends, dump CAM_FRAMES flips of every crash
# camera (the pace log's crash byte going up). In the background.
cam_watch() {
    local n=0 was=00 c f
    mkdir -p "$D/cam"
    while kill -0 "$(cat "$D/pid")" 2>/dev/null; do
        c=$(pace crash); f=$(pace P)
        if [ -n "$c" ] && [ "$c" != 00 ] && [ "$was" = 00 ]; then
            n=$(( n + 1 ))
            local a=$(( f + ${CAM_SKIP:-30} )) b=$(( f + ${CAM_SKIP:-30} + ${CAM_FRAMES:-48} - 1 ))
            echo "$a-$b" >> "$D/dumpat.txt"
            printf '%s\t%s\t%s\t%s\n' "$n" "$f" "$a" "$b" >> "$D/cam/cams.tsv"
        fi
        [ -n "$c" ] && was=$c
        sleep 0.1
    done
}

drive() {
    local k t0
    # The intro camera and the countdown run by themselves; hold the
    # accelerator through them (the start is the GO).
    for (( k = 0; k * 21 < ${DRIVE_SECS:-90} + 30; k++ )); do
        cat >> "$D/pad.txt" <<'EOF'
rt+a:7000
rt+a+lleft:2200
rt+a:5000
rt+a+lright:2600
rt+a:3000
rt+a+lleft:1200
EOF
    done
    t0=$(date +%s)
    while [ $(( $(date +%s) - t0 )) -lt $(( ${DRIVE_SECS:-90} + 25 )) ]; do alive; sleep 1; done
}

to_main_menu
if [ "$scene" = frontend ]; then
    wait_flips 300
    to_single_event
    wait_flips 200
    press a:400 90              # Race: Select Options
    press right:200 25
    press down:200 20
    press right:200 25
    press a:400 90              # Select Car: the garage
    wait_log 'CAR1[.]bgv' "car select (CAR1.bgv)"
    wait_flips 400
    scene_end "crash60 scene frontend"
    exit 0
fi
to_single_event
case "$scene" in
race)
    press a:400 90              # Race: Select Options
    press right:200 25          # Region: Random > USA
    press down:200 20
    press right:200 25          # Track: Random > the first
    press a:400 90              # Select Car
    ;;
roadrage)
    press down:200 20           # Time Attack
    press down:200 20           # Road Rage
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
wait_flips 60
press a:400 0                   # the first car: loading
[ "${CAPTURE:-0}" = 1 ] && { cam_watch & }

if [ "$scene" = crash ]; then
    wait_log 'TrC_ENG[.]xmv' "Crash Training video (TrC_ENG.xmv)"
    wait_log 'C3_V1.streamed[.]dat' "junction streamed in"
    wait_log "$(track_re crash2)" "captions (crash2.rws)"
    b=$(anchor "$(track_re crash2)")
    wait_flip $(( b + 300 ))
    press a:400 60              # the countdown
    if [ -n "${IMPACT_TIME:-}" ]; then
        # The impact comes about 17.5 s after the press; the pad lines run
        # one after the other, so the accelerator's hold ends there and the
        # boost button (Impact Time: slow motion, aftertouch with the stick)
        # follows IMPACT_TIME seconds into the crash camera.
        press "rt:$(( 17500 + IMPACT_TIME * 1000 ))" 0
        echo "a+lleft:6000" >> "$D/pad.txt"
        echo "rt:600000" >> "$D/pad.txt"
    else
        press rt:600000 0       # held from the countdown
    fi
    wait_log 'C3_v1.crash1[.]rws' "impact (C3_v1 crash1.rws)"
    c=$(anchor 'C3_v1.crash1[.]rws')
    if [ -n "${SWITCH_AT:-}" ]; then
        until [ "$(pace crash)" != 00 ]; do alive; sleep 0.05; done
        f=$(pace P)
        echo "$(( f + SWITCH_AT )) crash60 1" >> "$D/fx.txt"
        echo "$(( f + 4 * SWITCH_AT )) crash60 0" >> "$D/fx.txt"
        note "switch on at flip $(( f + SWITCH_AT )), off at $(( f + 4 * SWITCH_AT ))"
    fi
    # The crash camera, then Crash Results: by the clock, the flips of the
    # two rates differ. With CAPTURE=1 a frame every SHOT_SECS seconds
    # (default 4) from the impact on, shots/t<seconds>.bmp: the camera, the
    # results as they stand, what follows.
    t0=$(date +%s); k=0
    mkdir -p "$D/shots"
    while [ $(( $(date +%s) - t0 )) -lt "${RESULTS_SECS:-60}" ]; do
        alive
        if [ "${CAPTURE:-0}" = 1 ] && [ $(( $(date +%s) - t0 )) -ge $(( k * ${SHOT_SECS:-4} )) ]; then
            f=$(( $(flip) + 8 ))
            echo "$f-$f" >> "$D/dumpat.txt"
            printf '%s\t%s\n' "$(( k * ${SHOT_SECS:-4} ))" "$f" >> "$D/shots/shots.tsv"
            k=$(( k + 1 ))
        fi
        sleep 0.2
    done
    if [ "${CAPTURE:-0}" = 1 ]; then
        sleep 1
        while IFS=$'\t' read -r sec f; do
            mv "$(printf '%s/fb_flip_%05u.bmp' "$D" "$f")" \
               "$(printf '%s/shots/t%02u.bmp' "$D" "$sec")" 2>/dev/null
        done < "$D/shots/shots.tsv"
    fi
else
    wait_log 'streamed[.]dat' "track streamed in"
    wait_log "$(track_re crash1)" "stage begins (tracks crash1.rws)"
    drive
fi
if [ "${CAPTURE:-0}" = 1 ]; then
    sleep 1
    mv "$D"/fb_flip_*.bmp "$D/cam/" 2>/dev/null
fi
scene_end "crash60 scene $scene"
