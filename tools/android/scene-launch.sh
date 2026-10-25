#!/usr/bin/env bash
# The reference scenes of tools/headless on an Android device, over adb: this
# is the LAUNCH of scene_lib.sh. The scene script runs on the PC that has adb;
# the game runs on the device, in its window.
#
#   ADB="adb -s <serial>" LAUNCH="$PWD/tools/android/scene-launch.sh" \
#   GAME_DIR=/tmp/bo3-scene SAVES=none \
#     tools/headless/to_first_race.sh /tmp/bo3-scene/r1 \
#       RECOMP_TRACE=pacing=all,frametime=/sdcard/Android/data/com.stevencol.takedawn/files/ft.csv
#
# What it does: writes the run's RECOMP_* variables to the app's scene-env.txt (the
# host's paths left out), starts the app, follows the app's takedawn.log into
# the run's log.txt (which is what the scene waits on), and passes every line
# the scene appends to pad.txt on to the device's pad file. It lives as long
# as the app does; the scene's "game pid" is this script. The app reads
# scene-env.txt at that start only and deletes it; the player's own env.txt is
# never touched.
#
# The saves: a scene never touches the player's own. The scene's SAVES copy
# (scene_lib.sh) works on the host and does not reach the device, and the
# host's RECOMP_SAVE_DIR is a host path, so this script gives the app a save
# root and a settings file of its own on the device:
#
#   ANDROID_SAVE_DIR=<device path>   the scene's save root (default <files>/scene-saves)
#   ANDROID_SETTINGS=<device path>   its settings file (default <files>/scene-settings.toml)
#   ANDROID_SAVES_FROM=<host dir>    pushed to the save root before every start
#                                    (a folder with UDATA/ and TDATA/, as saves/ on the host)
#   ANDROID_SAVES_FROM_DEVICE=<dir>  the same, copied on the device (a backup, a seed)
#                                    (without either the root is kept as it is; empty: the first-boot screens)
#   ANDROID_SHADER_CACHE=<device path>  the shader cache of this run, emptied before the start
#                                    (a cold start on demand; default: the app's own)
#   ANDROID_ALLOW_REAL_SAVES=1       the old behaviour, on purpose: the scene runs on the player's
#                                    own saves and settings (<files>/takedawn, <files>/burnout3)
#
# The script refuses to start when the save root is the player's own (or
# inside or around it), and after the start it reads the app's "[SAVE] dir:"
# line and stops the app if that is not the scene's root. The app's log is
# removed before the start so that line is this start's own.
set -u
ADB="${ADB:-adb}"
P=com.stevencol.takedawn
F=/sdcard/Android/data/$P/files
D="$(dirname "$RECOMP_STDIO_LOG")"

SAVE_ARGS=()
SAVE_DIR=""
if [ "${ANDROID_ALLOW_REAL_SAVES:-0}" = 1 ]; then
  echo "scene-launch: ANDROID_ALLOW_REAL_SAVES=1: this scene runs on the player's own saves and settings" >&2
else
  SAVE_DIR="${ANDROID_SAVE_DIR:-$F/scene-saves}"
  SETTINGS_FILE="${ANDROID_SETTINGS:-$F/scene-settings.toml}"
  SAVE_DIR="${SAVE_DIR%/}"
  # The player's own roots: the current and the previous package's folder
  # (refused: the same, inside, or around them), and the files folder that
  # holds them and the game's data (refused: the same, or around it).
  for real in "$F/takedawn" "$F/burnout3"; do
    case "$SAVE_DIR/" in
      "$real"/*) echo "scene-launch: refusing to run: the save root '$SAVE_DIR' is the player's own ($real) or inside it. Set ANDROID_SAVE_DIR to a folder of its own, or ANDROID_ALLOW_REAL_SAVES=1 to run on the real saves on purpose." >&2; exit 2 ;;
    esac
  done
  for real in "$F/takedawn" "$F/burnout3" "$F"; do
    case "$real/" in
      "$SAVE_DIR"/*) echo "scene-launch: refusing to run: the save root '$SAVE_DIR' is, or holds, the player's own saves or the game's data ($real)." >&2; exit 2 ;;
    esac
  done
  [ -n "$SAVE_DIR" ] || { echo "scene-launch: refusing to run: no save root." >&2; exit 2; }
  case "$SETTINGS_FILE" in
    "$F/takedawn/"*|"$F/burnout3/"*|"") echo "scene-launch: refusing to run: the settings file '$SETTINGS_FILE' is the player's own." >&2; exit 2 ;;
  esac
  SAVE_ARGS=(RECOMP_SAVE_DIR="$SAVE_DIR" RECOMP_SETTINGS="$SETTINGS_FILE")
fi

# Logs a scene reads while the game runs (controls_scene.sh's BO3_CTL_LOG and
# BO3_DRIVE_LOG) are written on the device and followed into the host's file.
MIRROR=()
for v in BO3_CTL_LOG BO3_DRIVE_LOG; do
  [ -n "${!v:-}" ] && MIRROR+=("$v")
done
{
  env | grep -E '^(RECOMP_|BO3_|TU_|MESA_)' | grep -v -E \
    '^(RECOMP_(DEBUG|PAD_LIVE|STDIO_LOG|SAVE_DIR|SETTINGS|RENDER_SHADER_CACHE|HEADLESS|FB_DUMP|FB_DUMP_AT|D3D11_DUMP|PB_BACKEND)|BO3_CTL_LOG|BO3_DRIVE_LOG)='
  for v in ${MIRROR[@]+"${MIRROR[@]}"}; do echo "$v=$F/scene-$v.txt"; done
  echo "RECOMP_PAD_LIVE=$F/scene-pad.txt"
  for kv in ${SAVE_ARGS[@]+"${SAVE_ARGS[@]}"}; do echo "$kv"; done
  # BO-208: a shader cache of the scene's own (a cold start on demand): the app's
  # usual one is in its internal files, which adb cannot empty.
  [ -n "${ANDROID_SHADER_CACHE:-}" ] && echo "RECOMP_RENDER_SHADER_CACHE=$ANDROID_SHADER_CACHE"
  # A test start: the device's own pad (a resting stick, a hand) must not
  # take the pad from the script.
  echo "RECOMP_DEBUG=${RECOMP_DEBUG:+$RECOMP_DEBUG,}pad_script_only=1"
} > "$D/device-env.txt"

[ -n "${ANDROID_SHADER_CACHE:-}" ] && $ADB shell "rm -rf '$ANDROID_SHADER_CACHE'"
$ADB shell "am force-stop $P; : > $F/scene-pad.txt; rm -f $F/ft.csv $F/scene-BO3_*.txt $F/takedawn.log"
# The scene's own save root: seeded when asked, else kept (made if missing).
if [ -n "$SAVE_DIR" ]; then
  if [ -n "${ANDROID_SAVES_FROM:-}" ]; then
    [ -d "$ANDROID_SAVES_FROM/UDATA" ] || { echo "scene-launch: ANDROID_SAVES_FROM=$ANDROID_SAVES_FROM has no UDATA" >&2; exit 2; }
    $ADB shell "rm -rf '$SAVE_DIR'; mkdir -p '$SAVE_DIR'"
    for sub in UDATA TDATA; do [ -d "$ANDROID_SAVES_FROM/$sub" ] && $ADB push "$ANDROID_SAVES_FROM/$sub" "$SAVE_DIR/" > /dev/null; done
  elif [ -n "${ANDROID_SAVES_FROM_DEVICE:-}" ]; then
    $ADB shell "rm -rf '$SAVE_DIR'; mkdir -p '$SAVE_DIR' && cp -r '$ANDROID_SAVES_FROM_DEVICE'/UDATA '$ANDROID_SAVES_FROM_DEVICE'/TDATA '$SAVE_DIR'/"
  else
    $ADB shell "mkdir -p '$SAVE_DIR'"
  fi
fi
$ADB push "$D/device-env.txt" "$F/scene-env.txt" > /dev/null
# The scene's own commands on the device: off the cores the game pins.
. "$(dirname "$0")/little_cores.sh"
ON_LITTLE="taskset $(little_mask)"
$ADB shell am start -n $P/.StartActivity > /dev/null
sleep 2
$ADB shell "$ON_LITTLE tail -n +1 -F $F/takedawn.log" > "$RECOMP_STDIO_LOG" 2>/dev/null &
logpid=$!
( tail -n +1 -F "$D/pad.txt" 2>/dev/null | while IFS= read -r line; do
      [ -n "$line" ] && $ADB shell "echo '$line' >> $F/scene-pad.txt"
  done ) &
padpid=$!
mpids=""
for v in ${MIRROR[@]+"${MIRROR[@]}"}; do
  $ADB shell "$ON_LITTLE tail -n +1 -F $F/scene-$v.txt" > "${!v}" 2>/dev/null &
  mpids="$mpids $!"
done
trap '$ADB shell "am force-stop $P; rm -f $F/scene-env.txt $F/scene-pad.txt $F/scene-BO3_*.txt"; kill $logpid $padpid $mpids 2>/dev/null; pkill -P $padpid 2>/dev/null' EXIT TERM INT
sleep 5
# The proof, from the app's own log: the save root it opened is the scene's.
if [ -n "$SAVE_DIR" ]; then
  line=""
  for i in $(seq 1 30); do
    line=$(grep -a '\[SAVE\] dir:' "$RECOMP_STDIO_LOG" 2>/dev/null | tail -n 1)
    [ -n "$line" ] && break
    sleep 1
  done
  case "$line" in
    *"[SAVE] dir: $SAVE_DIR") echo "scene-launch: save root confirmed: $line" >&2 ;;
    *) echo "scene-launch: the app's save root is not $SAVE_DIR ('${line:-no [SAVE] dir line}'): stopping the app" >&2
       $ADB shell "am force-stop $P"; exit 3 ;;
  esac
fi
while [ -n "$($ADB shell $ON_LITTLE pidof $P 2>/dev/null)" ]; do sleep 2; done
