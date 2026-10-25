#!/usr/bin/env bash
# fx_scene.sh <rundir> <scene> [KEY=VALUE...]
#
# The two effect switches (graphics.bloom, graphics.motion_blur; BO-101,
# docs/effects.md) checked in one headless run. At chosen moments one switch
# goes off for six frames and on again (BO3_FX_AT, core/main.c) and the
# frames around both changes are dumped: the same scene with the effect,
# without it, and with it again. RECOMP_TRACE=metal_frame is on: the log has
# the render passes of every flip.
#
# Scenes (Single Event, the first car), as hud_scene.sh:
#   race        Race, USA, the first track. Changes in the garage, in the
#               intro camera, on the grid after the GO (a picture that
#               stands still: the exact comparison), at speed, in the pause
#               menu, then every FX_EVERY flips (default 120) of a drive
#               with boost held for DRIVE_SECS seconds (default 60).
#   roadrage    Road Rage, default options, the same.
#   crash       Crash, 1. Trailer Trash: the run-up, the impact, the crash
#               camera (Impact Time) and Crash Results, every 40 flips.
#
# Output: <rundir>/frames/fb_flip_N.bmp and <rundir>/ab.tsv, one line a
# change: the switch, the flip it went off at, where in the scene.
# tools/headless/fx_report.py <rundir> compares the frames.
set -u
source "$(dirname "$0")/scene_lib.sh"
rd=$1; scene=$2; shift 2
export CAPTURE=1
REPO="${REPO:-$(cd "$(dirname "$0")/../.." && pwd)}"
abs="$(cd "$REPO" && mkdir -p "$rd" && cd "$rd" && pwd)"
scene_start "$rd" BO3_FX_AT="${GAME_PATH_PREFIX:-}$abs/fx.txt" \
    RECOMP_TRACE="${RECOMP_TRACE:-metal_frame}" "$@"
: > "$D/fx.txt"; : > "$D/ab.tsv"
to_main_menu
to_single_event

# ab <flip> <bloom|blur> [tag]: the switch off at <flip> and on again six
# flips later; the frames around both changes are dumped. A change reaches the
# picture one or two frames on (the title builds a frame ahead of the one
# shown), so fx_report.py compares <flip> (on), <flip> + 3 (off) and
# <flip> + 9 (on again). Both files are read ahead of the game. The dump list
# holds 64 ranges: the ones behind the game are dropped first.
ab() {
    local f=$1 what=$2 now; now=$(flip)
    [ "$f" -le $(( now + 3 )) ] && die "ab $what at $f asked for at flip $now"
    awk -F- -v n="$now" '$2 >= n' "$D/dumpat.txt" > "$D/dumpat.new" 2>/dev/null
    mv "$D/dumpat.new" "$D/dumpat.txt"
    echo "$f $what 0" >> "$D/fx.txt"
    echo "$(( f + 6 )) $what 1" >> "$D/fx.txt"
    echo "$(( f - 2 ))-$(( f + 10 ))" >> "$D/dumpat.txt"
    printf '%s\t%s\t%s\n' "$what" "$f" "${3:-}" >> "$D/ab.tsv"
}

# ab_both <flip> <tag>: blur, then bloom 20 flips on; returns when both are done.
ab_both() {
    ab "$1" blur "$2"
    ab $(( $1 + 20 )) bloom "$2"
    wait_flip $(( $1 + 34 ))
}

# ab_every <from> <to> <tag>: blur and bloom in turn every FX_EVERY flips.
ab_every() {
    local f k=0 what
    for (( f = $1; f <= $2; f += ${FX_EVERY:-120} )); do
        what=blur; [ $(( k % 2 )) = 1 ] && what=bloom
        k=$(( k + 1 ))
        ab "$f" "$what" "$3"
    done
}

# pad <line>: one held state of the pad, appended; returns when it is being
# held, with the flip in $P. The runtime logs a line when it reads it, with
# the time it will press it (the state before it runs out first), on the
# clock of the "[GPU] flip N T ms" lines less about half a second; the lines
# here are all different, so each is found by its own text.
pad() {
    local re="PAD: live \"${1//+/[+]}\"" t now
    echo "$1" >> "$D/pad.txt"
    wait_log "$re" "pad $1"
    t=$(grep -a -m1 -E "$re" "$D/events.txt" | sed -E 's/.* at t=([0-9]+) ms.*/\1/')
    while :; do
        now=$(tail -c 4096 "$D/events.txt" | grep -a '\[GPU\] flip' | tail -n 1 | awk '{print $4}')
        [ "${now:-0}" -ge $(( t + 800 )) ] && break
        alive; sleep 0.1
    done
    P=$(flip)
}

# drive <anchor>: from the GO on.
drive() {
    local a=$1 k f
    wait_flip $(( a + 200 ))
    ab_both $(( $(flip) + 8 )) intro        # the intro camera
    # After the GO, no input yet: the car stands on the grid and the rivals
    # are gone, so a switch is nearly the only thing that changes in the
    # picture (the exact comparison for the bloom; the blur has no strength
    # at a standstill).
    wait_flip $(( a + 1200 ))
    ab_both $(( $(flip) + 8 )) grid
    ab_both $(( $(flip) + 9 )) grid         # again, at other phases of the
    ab_both $(( $(flip) + 10 )) grid        # track's animated lights
    # Up to speed (the blur comes with speed, boost or not), then the pause
    # menu: the title itself draws neither effect under it.
    pad rt:9010
    pad rt+lleft:310
    pad rt+a:5010
    ab_both $(( P + 30 )) speed
    pad start:210                           # pause, at speed
    wait_flip $(( P + 90 ))
    ab_both $(( $(flip) + 8 )) paused
    pad a:410                               # Continue
    wait_flip $(( P + 30 ))
    # The rest of the drive, a change every FX_EVERY flips: boosts, traffic,
    # crashes and their cameras as they come.
    f=$(flip)
    ab_every $(( f + 30 )) $(( f + ${DRIVE_SECS:-60} * 60 )) drive
    for (( k = 0; k * 21 < ${DRIVE_SECS:-60}; k++ )); do
        # A slide each way and the oncoming lane fill the boost bar (brake
        # with the steering held, the accelerator down); then boost.
        cat >> "$D/pad.txt" <<'EOF'
rt:3000
rt+lt+lleft:500
rt+lleft:400
rt:2000
rt+lt+lright:500
rt+lright:400
rt+a:6000
rt+lleft:300
rt+a:5000
rt+lright:300
EOF
    done
    while [ "$(flip)" -lt $(( f + 60 + ${DRIVE_SECS:-60} * 60 )) ]; do alive; sleep 1; done
}

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
ab_both $(( $(flip) + 40 )) garage
press a:400 0                   # the first car: loading

if [ "$scene" = crash ]; then
    wait_log 'TrC_ENG[.]xmv' "Crash Training video (TrC_ENG.xmv)"
    wait_log 'C3_V1.streamed[.]dat' "junction streamed in"
    wait_log "$(track_re crash2)" "captions (crash2.rws)"
    b=$(anchor "$(track_re crash2)")
    wait_flip $(( b + 300 ))
    press a:400 60              # the countdown
    press rt:600000 0           # held from the countdown
    f=$(flip)
    FX_EVERY=60 ab_every $(( f + 150 )) $(( f + 390 )) runup
    wait_log 'C3_v1.crash1[.]rws' "impact (C3_v1 crash1.rws)"
    c=$(anchor 'C3_v1.crash1[.]rws')
    f=$(flip)
    FX_EVERY=40 ab_every $(( f + 10 )) $(( c + $(cam_flips 1000) )) crashcam
    wait_flip $(( c + $(cam_flips 1000) + 20 ))
else
    wait_log 'streamed[.]dat' "track streamed in"
    wait_log "$(track_re crash1)" "stage begins (tracks crash1.rws)"
    a=$(anchor "$(track_re crash1)")
    echo "$a" > "$D/anchor.txt"
    drive "$a"
fi
mkdir -p "$D/frames"
mv "$D"/fb_flip_*.bmp "$D/frames/" 2>/dev/null
scene_end "fx scene $scene"
