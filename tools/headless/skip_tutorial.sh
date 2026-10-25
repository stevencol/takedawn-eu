#!/usr/bin/env bash
# skip_tutorial.sh <rundir> [KEY=VALUE...]
#
# The training film of a new profile's first Race / Road Rage / Crash event
# (A or START leaving it, core/tutorial.c). Same start as to_first_race.sh
# (SAVES=empty: the first-boot screens, a profile that is not saved), then
#
#   MODE=race|roadrage|crash   which mode's first event (default race)
#   PRESS=a|start|none         what to press once the film has played
#                              PRESS_AFTER flips (default none: it plays out)
#   PRESS_AFTER=flips          (default 600)
#   CAR_HOLD=ms                how long A is held on the car (default 400)
#
# and it prints, for the film (TrD_ENG.xmv Race and Road Rage, TrC_ENG.xmv
# Crash) and the load after it, "film_flips": the flips from the film's file
# open to the track's streamed.dat. Leaves the game running, or STOP_AT_END=1.
set -u
source "$(dirname "$0")/scene_lib.sh"
SAVES=empty scene_start "$@"
MODE="${MODE:-race}"
wait_log 'Titles30[.]xmv' "intro film (Titles30.xmv)"
press_until start:300 '_FEMain[.]xmv' 60
wait_flip $(( $(anchor '_FEMain[.]xmv') + 300 ))
press start:600 150         # Select Option: New Profile
press a:400 150             # the keyboard, cursor on Done
press a:400 150             # save your profile? No
press a:400 150             # Autosave will be disabled: No
press up:200 30             # Yes
press a:400 240             # the main menu
note "main menu"
to_single_event
case "$MODE" in
race)
    film='TrD_ENG[.]xmv'
    press a:400 120         # Race: Select Options
    press right:200 30      # Region: Random > USA
    press down:200 30
    press right:200 30      # Track: Random > Silver Lake Southbound
    ;;
roadrage)
    film='TrD_ENG[.]xmv'
    press down:200 20
    press a:400 120         # Road Rage: Select Options
    press right:200 30
    press down:200 30
    press right:200 30
    ;;
crash)
    film='TrC_ENG[.]xmv'
    press down:200 20; press down:200 20; press down:200 20
    press a:400 90          # Junction Selection
    press down:200 20       # 1. Trailer Trash
    ;;
esac
press_until a:400 'CAR1[.]bgv' 150
note "car select (flip $(anchor 'CAR1[.]bgv'))"
wait_flip $(( $(anchor 'CAR1[.]bgv') + 200 ))
press a:${CAR_HOLD:-400} 0        # the first car: the training film, the load
wait_log "$film" "training film"
f0=$(anchor "$film")
case "${PRESS:-none}" in
none) ;;
*)  wait_flip $(( f0 + ${PRESS_AFTER:-600} ))
    press "${PRESS}:300" 0 ;;
esac
wait_log 'C3_V1.streamed[.]dat' "track streamed in"
f1=$(anchor 'C3_V1.streamed[.]dat')
echo "film_flips=$(( f1 - f0 )) film_open_flip=$f0 streamed_flip=$f1 mode=$MODE press=${PRESS:-none}" | tee -a "$D/scene.txt"
scene_end "after the training film"
