#!/usr/bin/env python3
"""pace_report.py <rundir | pace.txt>... [--phases] [--tsv] [--crash]

Reads BO3_PACE_LOG files (core/main.c: one line per flip the title
emits, with host time and the title's own pacing state) and prints, for the
60 fps crash camera switch (graphics.crash_60fps, BO-111, docs/crash60.md):

  phases    (--phases) the run as stretches of one pacing state: the half
            rate byte in force, the stepper's mode, the game's state, the
            stage's mode object and the crash camera byte, with the flips,
            the seconds and the flip interval of each.
  episodes  every stretch with a crash camera byte set: flips, wall time,
            simulation steps (the global step counter), world timer ticks
            and the slow-motion divisors seen, the steps per flip, and the
            flip interval (median, p95, p99, max, share over 20 ms).

  --crash   a Crash-mode event, from the impact to Crash Results, by the
            title's own phases: the camera while the world runs, the stills
            at impacts, the tour that adds up the score (the world timer
            stopped), the hand-over (the game's state 4: a load), Crash
            Results. Wall time, world ticks, steps and flips of each, and
            the sums from the impact.

The game's speed is steps per second of wall time (60 as shipped, in both
rates); a crash camera's length in steps is the title's own measure of it,
whatever the frame rate.
"""
import os
import sys


def load(path):
    if os.path.isdir(path):
        path = os.path.join(path, "pace.txt")
    rows = []
    with open(path, errors="replace") as f:
        for line in f:
            p = line.split()
            if len(p) < 24 or p[0] != "P":
                continue
            try:
                m, m2 = p[9].split("/")
                rows.append(dict(
                    flip=int(p[1]), t=float(p[3]), req=int(p[5]),
                    cur=int(p[7]), mode=int(m), mode2=int(m2),
                    steps=int(p[11]), gs=int(p[13]), wt=int(p[15]),
                    slow=int(p[17]), run=int(p[19]), crash=p[21],
                    st=int(p[23]), obj=p[25] if len(p) > 25 else ""))
            except ValueError:
                continue
    return rows


def pct(v, q):
    if not v:
        return 0.0
    v = sorted(v)
    return v[min(len(v) - 1, int(round(q * (len(v) - 1))))]


def intervals(rows):
    return [b["t"] - a["t"] for a, b in zip(rows, rows[1:])]


def stretch(rows, key):
    """Maximal runs of rows with one key: (key, first index, last index)."""
    out, s = [], 0
    for i in range(1, len(rows) + 1):
        if i == len(rows) or key(rows[i]) != key(rows[s]):
            out.append((key(rows[s]), s, i - 1))
            s = i
    return out


def summary(rows, a, b):
    """Rows a..b inclusive, measured to the row after (the stretch's end)."""
    e = min(b + 1, len(rows) - 1)
    part = rows[a:e + 1]
    iv = intervals(part)
    secs = (rows[e]["t"] - rows[a]["t"]) / 1000.0
    steps = (rows[e]["gs"] - rows[a]["gs"]) & 0xFFFFFFFF
    ticks = (rows[e]["wt"] - rows[a]["wt"]) & 0xFFFFFFFF
    hist = {}
    for r in rows[a:b + 1]:
        hist[r["steps"]] = hist.get(r["steps"], 0) + 1
    return dict(
        flips=e - a, secs=secs, steps=steps, ticks=ticks,
        sps=steps / secs if secs > 0 else 0.0,
        fps=(e - a) / secs if secs > 0 else 0.0,
        p50=pct(iv, 0.5), p95=pct(iv, 0.95), p99=pct(iv, 0.99),
        mx=max(iv) if iv else 0.0,
        over20=sum(1 for x in iv if x > 20.0) / len(iv) if iv else 0.0,
        over37=sum(1 for x in iv if x > 37.0) / len(iv) if iv else 0.0,
        slow=sorted({r["slow"] for r in rows[a:b + 1]}),
        hist=" ".join(f"{k}:{v}" for k, v in sorted(hist.items())))


def crash_event(rows):
    """The first crash camera of a Crash-mode run, phase by phase."""
    i0 = next((i for i, r in enumerate(rows) if r["crash"] != "00"), None)
    if i0 is None:
        print("  no crash camera")
        return
    # The camera: world running or stopped, in state 5; then state 4 (the
    # hand-over) until state 5 comes back with the byte clear: Crash Results.
    i1 = next((i for i in range(i0, len(rows)) if rows[i]["st"] != 5), len(rows) - 1)
    i2 = next((i for i in range(i1, len(rows))
               if rows[i]["st"] == 5 and rows[i]["crash"] == "00"), len(rows) - 1)
    segs = [(k, i0 + a, i0 + b) for k, a, b in
            stretch(rows[i0:i1], lambda r: r["run"])]
    tour = segs[-1] if segs and segs[-1][0] == 0 else None
    parts = []
    world = [0, 0.0, 0, 0]
    still = [0, 0.0, 0, 0]

    def span(a, b):
        return [rows[b]["wt"] - rows[a]["wt"], (rows[b]["t"] - rows[a]["t"]) / 1000.0,
                (rows[b]["gs"] - rows[a]["gs"]) & 0xFFFFFFFF, b - a]

    for seg in segs:
        k, a, b = seg
        if seg is tour:
            continue
        d = span(a, min(b + 1, len(rows) - 1))
        tgt = world if k else still
        for j in range(4):
            tgt[j] += d[j]
    t_tour = tour[1] if tour else i1
    parts.append(("camera, world running", world))
    parts.append(("stills at impacts", still))
    parts.append(("score tour (world stopped)", span(t_tour, i1) if tour else [0, 0.0, 0, 0]))
    parts.append(("hand-over (state 4)", span(i1, i2)))
    print("  phase                         seconds  world ticks   steps   flips")
    for name, d in parts:
        ticks = d[0] if name.startswith(("camera", "stills")) else 0
        print(f"  {name:28s} {d[1]:8.2f} {ticks:12d} {d[2]:7d} {d[3]:7d}")
    for name, b in (("impact to the tour's start", t_tour),
                    ("impact to the camera's end", i1),
                    ("impact to Crash Results", i2)):
        d = span(i0, b)
        print(f"  {name:28s} {d[1]:8.2f} {'':12s} {d[2]:7d} {d[3]:7d}")


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    phases, tsv = "--phases" in sys.argv, "--tsv" in sys.argv
    crash = "--crash" in sys.argv
    if not args:
        sys.exit(__doc__)
    for path in args:
        rows = load(path)
        if len(rows) < 2:
            print(f"{path}: no pace lines")
            continue
        print(f"== {path}: {len(rows)} flips, "
              f"{(rows[-1]['t'] - rows[0]['t']) / 1000.0:.1f} s")
        if phases:
            print("  flip    flips    secs   fps  steps/s  cur req mode st "
                  "crash obj       steps/flip        iv p50/p95/max ms")
            for key, a, b in stretch(rows, lambda r: (
                    r["cur"], r["req"], r["mode"], r["mode2"], r["st"],
                    r["crash"], r["obj"])):
                if b - a < 3:
                    continue
                s = summary(rows, a, b)
                print(f"  {rows[a]['flip']:6d} {s['flips']:6d} {s['secs']:7.2f} "
                      f"{s['fps']:5.1f} {s['sps']:7.1f}   {key[0]}   {key[1]}  "
                      f"{key[2]}/{key[3]} {key[4]:2d}  {key[5]}  {key[6]} "
                      f"{s['hist']:<16s} {s['p50']:5.1f}/{s['p95']:5.1f}/{s['mx']:6.1f}")
        if crash:
            crash_event(rows)
            continue
        eps = [(k, a, b) for k, a, b in
               stretch(rows, lambda r: r["crash"] != "00") if k]
        print(f"  crash camera episodes: {len(eps)}")
        if tsv:
            print("\t".join(["run", "flip", "flips", "secs", "steps", "ticks",
                             "fps", "steps_per_s", "p50", "p95", "p99", "max",
                             "over20", "cur", "slow"]))
        for _, a, b in eps:
            s = summary(rows, a, b)
            cur = sorted({r["cur"] for r in rows[a:b + 1]})
            if tsv:
                print("\t".join(str(x) for x in [
                    path, rows[a]["flip"], s["flips"], f"{s['secs']:.3f}",
                    s["steps"], s["ticks"], f"{s['fps']:.2f}",
                    f"{s['sps']:.2f}", f"{s['p50']:.2f}", f"{s['p95']:.2f}",
                    f"{s['p99']:.2f}", f"{s['mx']:.2f}", f"{s['over20']:.3f}",
                    "".join(map(str, cur)), ",".join(map(str, s["slow"]))]))
                continue
            print(f"  flip {rows[a]['flip']:6d}: {s['flips']:5d} flips "
                  f"{s['secs']:7.3f} s  {s['steps']:5d} steps "
                  f"({s['sps']:5.1f}/s)  {s['ticks']:5d} ticks  "
                  f"slow {s['slow']}  half-rate {cur}\n"
                  f"               {s['fps']:5.1f} fps, interval p50 "
                  f"{s['p50']:.2f} p95 {s['p95']:.2f} p99 {s['p99']:.2f} "
                  f"max {s['mx']:.1f} ms, over 20 ms {100 * s['over20']:.1f} %, "
                  f"over 37 ms {100 * s['over37']:.1f} %; steps/flip {s['hist']}")


if __name__ == "__main__":
    main()
