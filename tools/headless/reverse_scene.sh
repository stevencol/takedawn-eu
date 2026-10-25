#!/usr/bin/env bash
# reverse_scene.sh <rundir> [KEY=VALUE...]
#
# BO-96: the car reverses on the left trigger. Single Event > Race as
# to_race.sh, then, with the title's own speed logged every frame
# (BO3_DRIVE_LOG, core/main.c):
#
#   rt             accelerate
#   lt             held from speed: brakes to a stop and, still held, reverses
#   rt             forward again
#   rt+lt          both held: the title brakes to a stop and stays there. It
#                  does not reverse while the accelerator is held, which is
#                  why a pad script holding rt under a player's own pad looked
#                  like a dead reverse gear (the toolkit now ends the script
#                  on a pad at the controller's first button; tests/pad_script)
#   lt             from rest, after a release: reverses
#   rt, lt=128     the trigger half pulled: stops and reverses
#
# PASS/FAIL per case in <rundir>/scene.txt and reverse.txt; exit 1 on a
# failure. The speed is a magnitude: "reverses" is the speed rising above
# 3 m/s again after the stop while only the left trigger is held. A case the
# traffic cut short (a crash ends the pad phase's speed) reads as a failure:
# run it again.
set -u
source "$(dirname "$0")/scene_lib.sh"
rd="$1"; shift
scene_start "$rd" BO3_DRIVE_LOG="$(cd "$(dirname "$0")/../.." && mkdir -p "$rd" && cd "$rd" && pwd)/drive.txt" "$@"
to_main_menu
to_single_event
press a:400 90              # Race: Select Options
press right:200 25
press down:200 20
press right:200 25
press a:400 90              # Select Car
wait_log 'CAR1[.]bgv' "car select (CAR1.bgv)"
press a:400 0
wait_log 'streamed[.]dat' "track streamed in"
wait_log "$(track_re crash1)" "race begins (tracks crash1.rws)"
a=$(anchor "$(track_re crash1)")
wait_flip $(( a + 300 ))    # the GO
# The lines are taken at once and pressed one after another, 200 ms apart.
for p in rt:4000 lt:9000 rt:3000 rt+lt:8000 lt:6000 rt:3000 lt=128:8000; do
    press "$p" 0
done
wait_flips $(( 60 * 44 ))
python3 - "$D/drive.txt" > "$D/reverse.txt" <<'PY'
import re, sys
ph = []                                 # [lt, rt, [speeds]]
for l in open(sys.argv[1]):
    m = re.match(r'D \d+ v (-?[\d.]+) .* lt (\d+) rt (\d+)', l)
    if not m:
        continue
    v, k = float(m[1]), (int(m[2]), int(m[3]))
    if not ph or ph[-1][0] != k:
        ph.append([k, []])
    ph[-1][1].append(v)
ph = [p for p in ph if len(p[1]) > 30 and p[0] != (0, 0)]
want = [((0, 255), None), ((255, 0), 'reverse'), ((0, 255), None),
        ((255, 255), 'hold'), ((255, 0), 'reverse'), ((0, 255), None),
        ((128, 0), 'reverse')]
bad = 0
if [p[0] for p in ph] != [w[0] for w in want]:
    print('FAIL: pad phases the title read:', [p[0] for p in ph])
    sys.exit(1)
for (k, vs), (_, what) in zip(ph, want):
    stop = next((i for i, v in enumerate(vs) if v < 0.5), None)
    after = max(vs[stop:]) if stop is not None else -1
    line = 'lt %3d rt %3d: %d frames, start %.1f, %s, then up to %.1f m/s' % (
        k[0], k[1], len(vs), vs[0],
        'stopped at frame %d' % stop if stop is not None else 'never stopped', after)
    if what == 'reverse':
        ok = stop is not None and after > 3.0
        print(('PASS' if ok else 'FAIL') + ' reverses: ' + line)
        bad += not ok
    elif what == 'hold':
        print('INFO accelerator and brake together (the title holds the car): ' + line)
    else:
        print('     ' + line)
sys.exit(1 if bad else 0)
PY
rc=$?
while IFS= read -r l; do note "$l"; done < "$D/reverse.txt"
scene_end "reverse scene"
exit $rc
