#!/usr/bin/env bash
# menu_entry_scene.sh <rundir> [KEY=VALUE...]
#
# interface.menu_entry (BO-133, core/menuentry.c): Driver Details >
# Settings lists TAKEDAWN SETTINGS as its fifth line, and A on it opens the
# overlay while the title stays on its page.
#
#   1. Driver Details > Settings, down to the fifth line: shot
#      settings_entry (CAPTURE=1).
#   2. A: the log has "[MENU] TAKEDAWN SETTINGS: opening the overlay" and
#      the overlay's "open:" line; the title loads no other page (no
#      "[FILE]" line in the 120 flips after the press).
#   3. The overlay closed (through RECOMP_OVERLAY=file=, the scripted pad
#      does not reach it): the title runs on, on its page (shot
#      settings_after, the cursor still on the fifth line).
#   With MENU_ENTRY=0 (RECOMP_MENU_ENTRY=0) only step 1, and the shot shows
#   the title's four lines.
#
# Needs a window (WINDOW=1): without one there is no overlay and the menu is
# the title's (checked as such when WINDOW is not 1).
#
# A scratch HOME and no settings file (RECOMP_SETTINGS=none): the player's
# settings are not read or written; the saves are copied as in every scene.
set -u
source "$(dirname "$0")/scene_lib.sh"
HOME_DIR="${HOME_DIR:-$(mktemp -d)}"
rd="$(cd "$(dirname "$0")/../.." && mkdir -p "$1" && cd "$1" && pwd)"
rm -f "$rd/overlay_toggle"
scene_start "$@" HOME="$HOME_DIR" RECOMP_SETTINGS=none RECOMP_MENU_ENTRY="${MENU_ENTRY:-1}" \
    RECOMP_OVERLAY="file=$rd/overlay_toggle"
fail=0
bad() { note "FAIL: $*"; fail=1; }

to_main_menu
press down:200 20; press down:200 20; press down:200 20; press down:200 20
press a:400 90              # Driver Details
press down:200 20; press down:200 20; press down:200 20; press down:200 20
press a:400 120             # Settings
press down:200 20; press down:200 20; press down:200 20; press down:200 30
SHOT_WINDOW=0 shot settings_entry "$(flip)" 20 0
listed=$(grep -ac '\[MENU\] Settings: TAKEDAWN SETTINGS listed' "$D/log.txt" || true)
if [ "${MENU_ENTRY:-1}" = 0 ] || [ "${WINDOW:-0}" != 1 ]; then
    [ "$listed" = 0 ] || die "listed without a window or with the switch off"
    scene_end "menu entry off: shot taken"
    exit 0
fi

[ "$listed" -ge 1 ] || bad "TAKEDAWN SETTINGS was not listed"
files=$(count '\[FILE\]')
# A: the overlay opens and pauses the title, so no flips come until it
# closes: these waits are on the log, in wall time.
PADN=$(( PADN + 1 )); echo "a:400" >> "$D/pad.txt"
t=$(date +%s)
until grep -aq 'open: the title is paused' "$D/log.txt"; do
    alive; [ $(( $(date +%s) - t )) -gt 30 ] && break; sleep 0.25
done
grep -aq '\[MENU\] TAKEDAWN SETTINGS: opening the overlay' "$D/log.txt" \
    || bad "no '[MENU] TAKEDAWN SETTINGS' line after A"
grep -aq 'open: the title is paused' "$D/log.txt" || bad "the overlay did not open"
sleep 2
# Close it through its trigger file (RECOMP_OVERLAY=file=..., the scripted
# pad does not reach the overlay); the title runs on, still on its page.
: > "$D/overlay_toggle"
f=$(flip); t=$(date +%s)
until [ "$(flip)" -gt $(( f + 60 )) ]; do
    alive; [ $(( $(date +%s) - t )) -gt 30 ] && { bad "the title did not run on after the overlay closed"; break; }
    sleep 0.25
done
SHOT_WINDOW=0 shot settings_after "$(flip)" 30 0
[ "$(count '\[FILE\]')" = "$files" ] || bad "the title opened a file after A (it left its page?)"
[ "${fail}" = 0 ] && note "menu entry: opened the overlay, the title stayed on its page"
scene_end "menu entry scene done (fail=$fail)"
exit $fail
