#!/usr/bin/env bash
# scenery_scene.sh <rundir> [KEY=VALUE...]
#
# graphics.scenery_detail (BO-177, docs/draw-distance.md) checked in one run:
# Single Event > Race on a USA track (SCENERY_TRACK, below; default Silver Lake), then
#
#   - under the title's pause menu at a few moments (the world stands still
#     and is still drawn): original > far > original, the same instant;
#   - a drive (accelerator held, slides, boost) with the same change every
#     SCENERY_EVERY flips (default 150), for the draws and indices in motion.
#
# The changes go through BO3_FX_AT ("<flip> sdetail 0|1", core/main.c),
# which sets the setting as the overlay's row does; the first one lists the
# track's prop types in the log ("BO3_FX_AT: prop ..."). Frames compared:
# N (original), N+4 (far), N+10 (original again); N-1..N+11 are dumped.
# tools/headless/scenery_report.py <rundir> prints the draws, indices and
# picture differences and makes the crops.
#
#   HOME=/tmp/x STOP_AT_END=1 tools/headless/scenery_scene.sh runs/sd1
set -u
source "$(dirname "$0")/scene_lib.sh"
rd=$1; shift
export CAPTURE=1
REPO="${REPO:-$(cd "$(dirname "$0")/../.." && pwd)}"
abs="$(cd "$REPO" && mkdir -p "$rd" && cd "$rd" && pwd)"
# SCENERY_NOFX=1 changes no setting at the pauses (frames only, for another
# switch under test, e.g. SCENERY_DEBUG=zbias_ab=4).
# SCENERY_AUTO=<flips>: the title's AI drives (RECOMP_DEBUG=autopilot=1) and
# the world runs that many flips between the pauses (SCENERY_PAUSES_N pauses,
# default 14), for a spot the accelerator-held drive does not reach (BO-253).
AUTO=()
[ -n "${SCENERY_AUTO:-}" ] && AUTO=(RECOMP_DEBUG="autopilot=1${SCENERY_DEBUG:+,$SCENERY_DEBUG}")
scene_start "$rd" ${AUTO[@]+"${AUTO[@]}"} BO3_FX_AT="${GAME_PATH_PREFIX:-}$abs/fx.txt" \
    BO3_DRIVE_LOG="${GAME_PATH_PREFIX:-}$abs/drive.txt" \
    RECOMP_TRACE="${RECOMP_TRACE:-metal_frame}" "$@"
: > "$D/fx.txt"; : > "$D/ab.tsv"
to_main_menu
to_single_event
press a:400 90              # Race: Select Options
for (( k = 0; k < ${SCENERY_REGION:-1}; k++ )); do press right:200 25; done   # Region: Random > USA (> Europe with 2 and BO3_UNLOCK_ALL=1)
press down:200 20
# Track: Random > the first, then SCENERY_TRACK more to the right (the
# reference saves: 0 the first USA track, C1_V2; 4 Silver Lake, C3_V1).
for (( k = 0; k <= ${SCENERY_TRACK:-4}; k++ )); do press right:200 25; done
press a:400 90              # Select Car
wait_log 'CAR1[.]bgv' "car select (CAR1.bgv)"
press a:400 0               # the first car: loading
wait_log 'streamed[.]dat' "track streamed in"
grep -a -m1 -o 'tracks.US.C[0-9]_V[0-9]' "$D/events.txt" | tee "$D/track.txt"
[ -n "${SCENERY_PROBE:-}" ] && { scene_stop; exit 0; }
wait_log "$(track_re crash1)" "stage begins (tracks crash1.rws)"
a=$(anchor "$(track_re crash1)")
echo "$a" > "$D/anchor.txt"

# ab <flip> <where>: original until <flip>, far from it, original again
# from +6.
ABK=0
ab() {
    local f=$1 now; now=$(flip)
    [ "$f" -le $(( now + 3 )) ] && die "ab at $f asked for at flip $now"
    if [ -n "${SCENERY_GROUPS:-}" ]; then
        # SCENERY_GROUPS="1,2,3 4,5": from pause SCENERY_GROUP_FROM on, each
        # pause hides one group of prop types (draw distance 1 m) in its
        # second arm, so one run asks which type a thing in the picture is.
        local gs=($SCENERY_GROUPS) gi=$(( ABK - ${SCENERY_GROUP_FROM:-0} )) t
        [ -n "${GSEL:-}" ] && gi=$GSEL
        if [ "$gi" -ge 0 ] && [ "$gi" -lt "${#gs[@]}" ]; then
            for t in ${gs[$gi]//,/ }; do
                echo "$f pdraw$t 1" >> "$D/fx.txt"
                echo "$(( f + 6 )) pdraw$t 0" >> "$D/fx.txt"
            done
        fi
        [ -z "${GSEL:-}" ] && ABK=$(( ABK + 1 ))
    elif [ -n "${SCENERY_FXON:-}" ]; then
        # SCENERY_FXON / SCENERY_FXOFF: BO3_FX_AT lines (";" between) for the
        # two arms instead of the scenery setting, e.g. "pdraw15 1000".
        echo "${SCENERY_FXON//;/$'\n'$f }" | sed "1s/^/$f /" >> "$D/fx.txt"
        echo "${SCENERY_FXOFF//;/$'\n'$(( f + 6 )) }" | sed "1s/^/$(( f + 6 )) /" >> "$D/fx.txt"
    elif [ -z "${SCENERY_NOFX:-}" ]; then
        echo "$f sdetail 1" >> "$D/fx.txt"
        echo "$(( f + 6 )) sdetail 0" >> "$D/fx.txt"
    fi
    echo "$(( f - 1 ))-$(( f + ${SCENERY_WIN:-11} ))" >> "$D/dumpat.txt"
    printf '%s\t%s\n' "$f" "$2" >> "$D/ab.tsv"
}

# pad <spec>: one line for the pad, then wait until it is over (800 ms of
# the game's own time past the press); P is the flip then.
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

# paused <where>: the title's pause menu, the two settings under it, then
# Continue.
paused() {
    pad "start:$(( 210 + PN ))"; PN=$(( PN + 1 ))
    wait_flip $(( P + 60 ))
    if [ -n "${SCENERY_SWEEP:-}" ] && [ "$PAUSEK" -ge "${SCENERY_GROUP_FROM:-0}" ] \
        && [ "$PAUSEK" -lt $(( ${SCENERY_GROUP_FROM:-0} + SCENERY_SWEEP )) ]; then
        # SCENERY_SWEEP=n: in n pauses from SCENERY_GROUP_FROM, every group of
        # SCENERY_GROUPS in turn (16 flips apart) under the one pause.
        local g ng; ng=$(echo $SCENERY_GROUPS | wc -w)
        for (( g = 0; g < ng; g++ )); do
            GSEL=$g ab $(( $(flip) + 8 )) "$1-g$g"
            wait_flip $(( $(flip) + 16 ))
        done
    else
        ab $(( $(flip) + 8 )) "$1"
        wait_flip $(( $(flip) + 26 ))
    fi
    PAUSEK=$(( PAUSEK + 1 ))
    pad "a:$(( 410 + PN ))"; PN=$(( PN + 1 ))
    wait_flip $(( P + 20 ))
}
PN=0
PAUSEK=0

# The start, then pauses along the first stretch of the drive (the pine
# woods of Silver Lake), the accelerator held between them.
wait_flip $(( a + 330 ))
paused grid
if [ -n "${SCENERY_AUTO:-}" ]; then
    for (( k = 0; k < ${SCENERY_PAUSES_N:-14}; k++ )); do
        wait_flip $(( $(flip) + SCENERY_AUTO ))
        paused auto
    done
else
for k in ${SCENERY_PAUSES:-4 4 4 4 4 4}; do
    pad "rt:$(( k * 1000 + PN ))"; PN=$(( PN + 1 ))
    paused paused
done
fi

# The drive.
f=$(flip); f0=$(( f + 30 )); f1=$(( f0 + ${DRIVE_SECS:-60} * 60 ))
for (( k = f0; k <= f1; k += ${SCENERY_EVERY:-150} )); do ab "$k" drive; done
sort -n "$D/dumpat.txt" > "$D/dumpat.all"
feed() {
    awk -F- -v n="$(flip)" '$2 >= n' "$D/dumpat.all" | head -n 48 > "$D/dumpat.new"
    mv "$D/dumpat.new" "$D/dumpat.txt"
}
feed
for (( k = 0; k * 21 < ${DRIVE_SECS:-60}; k++ )); do
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
while [ "$(flip)" -lt $(( f1 + 30 )) ]; do alive; feed; sleep 1; done
mkdir -p "$D/frames"
mv "$D"/fb_flip_*.bmp "$D/frames/" 2>/dev/null
scene_end "scenery scene"
