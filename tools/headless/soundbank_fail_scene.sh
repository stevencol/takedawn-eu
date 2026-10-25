#!/usr/bin/env bash
# soundbank_fail_scene.sh <rundir> [KEY=VALUE...]   (BO-218, GitHub #17)
#
# A sound bank that does not load, at race start. The title's bank cache
# loads sound\identN.awd (the EA GAMES TRAX pop-up's sounds) when a race
# starts; when the load ends in an error it counts the waves of a list that
# is no list, and the walk never ends: the picture freezes at the GO (the
# hang reports of GitHub #17: sub_001F65A0 <- sub_001C9840 <- sub_001C9660
# <- sub_001C9C80 <- sub_001543B0). Here the load is made to fail on
# purpose: a copy of the game folder made of links, its ten Ident*.awd
# empty files, then tools/headless/custom_music_scene.sh in it (the custom
# soundtrack chosen, a race). Without the guard (core/soundbank.c) the
# scene fails ("flip ... not reached"); with it the race goes on, the log
# says "[SOUND] a sound bank did not load", and this exits 0.
#
#   tools/headless/soundbank_fail_scene.sh runs/bankfail
#
# Nothing of the real game folder is changed. Same variables as
# custom_music_scene.sh (MENU_SECS, RACE_SECS, SPEAKERS, ...).
set -u
REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
RD="$(cd "$REPO" && mkdir -p "$1" && cd "$1" && pwd)"
shift
SRC="$REPO/Burnout 3 Takedown"
GD="$RD/gamedir"
F="$GD/Burnout 3 Takedown"
[ -f "$SRC/default.xbe" ] || { echo "no game data at $SRC"; exit 2; }

rm -rf "$GD"; mkdir -p "$F/sound"
for e in "$SRC"/*; do
    b=$(basename "$e")
    [ "$b" = sound ] || ln -s "$e" "$F/$b"
done
n=0
for e in "$SRC"/sound/*; do
    b=$(basename "$e")
    case "$(printf '%s' "$b" | tr '[:upper:]' '[:lower:]')" in
        ident[0-9].awd) : > "$F/sound/$b"; n=$((n + 1)) ;;
        *) ln -s "$e" "$F/sound/$b" ;;
    esac
done
[ "$n" -gt 0 ] || { echo "no Ident*.awd in $SRC/sound"; exit 2; }

STOP_AT_END=1 GAME_DIR="$GD" BIN="${BIN:-$REPO/bin/burnout3}" SCENE_TIMEOUT="${SCENE_TIMEOUT:-90}" \
    MENU_SECS="${MENU_SECS:-5}" RACE_SECS="${RACE_SECS:-20}" \
    "$REPO/tools/headless/custom_music_scene.sh" "$RD" "$@"
st=$?
said=$(grep -ac '\[SOUND\] a sound bank did not load' "$RD/log.txt" 2>/dev/null || true)
echo "soundbank_fail: custom_music_scene exit $st; guard lines in the log: ${said:-0}"
[ "$st" = 0 ] && [ "${said:-0}" -ge 1 ]
