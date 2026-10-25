#!/usr/bin/env bash
# draw_scene.sh <rundir> [KEY=VALUE...]
#
# graphics.vehicle_detail (BO-112, docs/draw-distance.md) checked in one run:
# Single Event > Race on the first USA track, then
#
#   - the rolling start, the rivals pulling away: the setting goes original >
#     far > farthest > original, in motion and then under the title's pause
#     menu at a few moments (the world stands still there and is still
#     drawn, so the three levels are compared on the same instant);
#   - a drive (accelerator held, a slide each way, boost) with the same
#     change every DRAW_EVERY flips (default 150), traffic as it comes, and
#     a frame every DRAW_STUDY flips (default 20) for looking at what pops
#     in at the original setting.
#
# The changes go through BO3_FX_AT ("<flip> vdetail 0|1|2", core/main.c),
# which sets the setting as the overlay's row does. A change reaches the
# picture one or two frames on, so the frames compared are N (original), N+4
# (far), N+10 (farthest) and N+16 (original again); frames N-1..N+17 are
# dumped. tools/headless/draw_report.py <rundir> prints the draws and indices
# of each and makes the picture pairs.
#
# WINDOW=1 (scene_lib.sh) runs it in a window and also takes the window as
# presented at each level under the pause menu (<rundir>/window/p<n>_<level>
# .bmp: the render scale's picture, which the frame dumps, 640x480 from the
# guest's memory, do not show). Add RECOMP_AUDIO_MUTE=1.
#
# Run it with a scratch HOME (a start with the real one moves the player's
# save folder) and SAVES=<the reference saves>:
#
#   HOME=/tmp/x SAVES=$PWD/../burnout3/saves STOP_AT_END=1 \
#       tools/headless/draw_scene.sh runs/draw1
set -u
source "$(dirname "$0")/scene_lib.sh"
rd=$1; shift
export CAPTURE=1
REPO="${REPO:-$(cd "$(dirname "$0")/../.." && pwd)}"
abs="$(cd "$REPO" && mkdir -p "$rd" && cd "$rd" && pwd)"
scene_start "$rd" BO3_FX_AT="${GAME_PATH_PREFIX:-}$abs/fx.txt" \
    BO3_DRIVE_LOG="${GAME_PATH_PREFIX:-}$abs/drive.txt" \
    RECOMP_OVERLAY_TEST="${GAME_PATH_PREFIX:-}$abs/ovl.txt" \
    RECOMP_TRACE="${RECOMP_TRACE:-metal_frame}" "$@"
: > "$D/fx.txt"; : > "$D/ab.tsv"; : > "$D/ovl.txt"; mkdir -p "$D/window"
to_main_menu
to_single_event

# abc <flip> <where>: original until <flip>, far from it, farthest from +6,
# original again from +12.
abc() {
    local f=$1 now; now=$(flip)
    [ "$f" -le $(( now + 3 )) ] && die "abc at $f asked for at flip $now"
    echo "$f vdetail 1" >> "$D/fx.txt"
    echo "$(( f + 6 )) vdetail 2" >> "$D/fx.txt"
    echo "$(( f + 12 )) vdetail 0" >> "$D/fx.txt"
    echo "$(( f - 1 ))-$(( f + 17 ))" >> "$D/dumpat.txt"
    printf '%s\t%s\n' "$f" "$2" >> "$D/ab.tsv"
}

press a:400 90              # Race: Select Options
press right:200 25          # Region: Random > USA
press down:200 20
press right:200 25          # Track: Random > the first
press a:400 90              # Select Car
wait_log 'CAR1[.]bgv' "car select (CAR1.bgv)"
press a:400 0               # the first car: loading
wait_log 'streamed[.]dat' "track streamed in"
wait_log "$(track_re crash1)" "stage begins (tracks crash1.rws)"
a=$(anchor "$(track_re crash1)")
echo "$a" > "$D/anchor.txt"

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

# paused <where>: the title's pause menu, the three levels under it (the
# world stands still and is still drawn: the same instant at each level),
# then Continue.
paused() {
    pad "start:$(( 210 + PN ))"; PN=$(( PN + 1 ))
    wait_flip $(( P + 60 ))
    if [ "${WINDOW:-0}" = 1 ]; then
        # The window as presented (render scale and all), one picture a level.
        local k n=$(( SN++ ))
        for k in 0 1 2 0; do
            echo "$(flip) vdetail $k" >> "$D/fx.txt"
            wait_flip $(( $(flip) + 20 ))
            echo "shot ${GAME_PATH_PREFIX:-}$D/window/p${n}_$k.bmp" >> "$D/ovl.txt"
            wait_flip $(( $(flip) + 20 ))
        done
    fi
    abc $(( $(flip) + 8 )) "$1"
    wait_flip $(( $(flip) + 30 ))
    pad "a:$(( 410 + PN ))"; PN=$(( PN + 1 ))
    wait_flip $(( P + 20 ))
}
PN=0; SN=0

# The start: no input of ours on the car, the rivals leave. The levels in
# motion (the counts), and under the pause menu (the pictures).
for off in ${DRAW_GRID:-260 300}; do
    abc $(( a + off )) grid
    wait_flip $(( a + off + 19 ))
done
for off in ${DRAW_PAUSED:-330 380 440}; do
    wait_flip $(( a + off ))
    paused paused
done
pad "rt:$(( 6000 + PN ))"; PN=$(( PN + 1 ))
paused paused

# The drive.
f=$(flip); f0=$(( f + 30 )); f1=$(( f0 + ${DRIVE_SECS:-70} * 60 ))
for (( k = f0; k <= f1; k += ${DRAW_EVERY:-150} )); do abc "$k" drive; done
for (( k = f0 + 10; k <= f1; k += ${DRAW_STUDY:-20} )); do echo "$k-$k" >> "$D/dumpat.txt"; done
# The runtime takes 64 ranges at most: it is given the next ones as the run
# goes (feed, below).
sort -n "$D/dumpat.txt" > "$D/dumpat.all"
feed() {
    awk -F- -v n="$(flip)" '$2 >= n' "$D/dumpat.all" | head -n 48 > "$D/dumpat.new"
    mv "$D/dumpat.new" "$D/dumpat.txt"
}
feed
for (( k = 0; k * 21 < ${DRIVE_SECS:-70}; k++ )); do
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
scene_end "draw scene"
