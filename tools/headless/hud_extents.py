#!/usr/bin/env python3
"""hud_extents.py: read what the HUD extent monitor wrote (BO3_HUD_MON,
core/main.c; docs/widescreen-hud.md).

  table <hudmon.txt>                 every kind of box an edge of the visible
                                     picture cut, with how long and how much
  diff <ref hudmon> <test hudmon>    ref: 4:3 as shipped; test: 16:9 with
                                     display.hud_fix. Kinds cut only in test
                                     (the fix's defects), kinds cut in both
                                     but not alike (deeper, shallower, much
                                     longer), and the rest (the title's own
                                     use of the overscan)
  trace <hudmon.txt> <callback>      the path of the traced objects of one
                                     render callback (BO3_HUD_MON_TRACE), one
                                     line a run of flips with the same box
  same <a> <b> [flips]               the T lines of the HUD and EA Trax scenes
                                     must be equal for the first <flips>
                                     flips (default 100, the time before the
                                     drive's first input) from the flip each
                                     run first drew a HUD object: 4:3 with
                                     the fix on against 4:3 as shipped, both
                                     traced with BO3_HUD_MON_TRACE=all
  present <out dir> <43|169> <frame.bmp>... [--vis x0 x1]
                                     the picture a window shows of a frame
                                     dump: cut with the presenter's source
                                     rectangle (the overscan crop, 21..619 x
                                     16..464) and scaled to the display's
                                     shape. Judge a cut-off on these.

A kind is (scene, render callback, side, object height): the same element in
both pictures, whatever it says. Scenes: 0 and 1 the HUDs, 2 the front end
(menus, loading, results), 3 EA Trax. "cut" is the share of the box beyond
the edge; "run" the longest unbroken stretch of flips one object stayed cut.
A slide that crosses the edge for a fifth of a second is a short run; a text
that sits half off the picture is a long one.
"""
import sys
from collections import defaultdict

NAMES = {
    0x0004B4D0: "boost message",
    0x000F7C20: "text",
    0x001C1A60: "image",
}


def parse(path):
    """-> (headers, V rows, T rows); a row is a dict."""
    heads, vs, ts = [], [], []
    with open(path, errors="replace") as f:
        for line in f:
            p = line.split()
            if not p:
                continue
            if p[0] == "H" and len(p) >= 9:
                heads.append(dict(flip=int(p[1]), vx0=float(p[3]), vx1=float(p[4]),
                                  aspect=float(p[6]), fix=int(p[8])))
            elif p[0] in ("V", "T") and len(p) >= 24:
                r = dict(flip=int(p[1]), scene=int(p[2][1:]), layer=int(p[3][1:]),
                         cb=int(p[5], 16), fr=int(p[7], 16), obj=int(p[9], 16),
                         x0=float(p[11]), x1=float(p[12]), y0=float(p[14]), y1=float(p[15]),
                         w=float(p[17]), h=float(p[19]), a=float(p[21]), side=p[23])
                (vs if p[0] == "V" else ts).append(r)
    return heads, vs, ts


def vis_at(heads, flip):
    v = (21.0, 619.0)
    for h in heads:
        if h["flip"] <= flip:
            v = (h["vx0"], h["vx1"])
    return v


def kinds(path):
    heads, vs, _ = parse(path)
    out = {}
    runs = {}   # (key, obj) -> [last flip, current run]
    for r in vs:
        key = (r["scene"], r["cb"], r["side"], round(r["h"]))
        k = out.setdefault(key, dict(flips=set(), run=0, cut=0.0, first=r["flip"], last=r["flip"],
                                     w=set(), x=[1e9, -1e9], y=[1e9, -1e9]))
        vx0, vx1 = vis_at(heads, r["flip"])
        wd = max(r["x1"] - r["x0"], 1e-6)
        cut = 0.0
        if "L" in r["side"]:
            cut += (vx0 - r["x0"]) / wd
        if "R" in r["side"]:
            cut += (r["x1"] - vx1) / wd
        k["cut"] = max(k["cut"], cut)
        k["flips"].add(r["flip"])
        k["last"] = r["flip"]
        k["w"].add(round(r["w"]))
        k["x"] = [min(k["x"][0], r["x0"]), max(k["x"][1], r["x1"])]
        k["y"] = [min(k["y"][0], r["y0"]), max(k["y"][1], r["y1"])]
        st = runs.setdefault((key, r["obj"]), [r["flip"] - 1, 0])
        st[1] = st[1] + 1 if r["flip"] <= st[0] + 1 else 1
        st[0] = r["flip"]
        k["run"] = max(k["run"], st[1])
    return heads, out


def name(cb):
    return NAMES.get(cb, "")


def fmt(key, k):
    scene, cb, side, h = key
    ws = sorted(k["w"])
    wtxt = str(ws[0]) if len(ws) == 1 else "%d..%d" % (ws[0], ws[-1])
    return ("s%d cb %08X %-2s h %3d w %-9s flips %5d run %5d cut %3.0f%%  x %7.1f..%7.1f"
            " y %5.1f..%5.1f  flips %d..%d %s"
            % (scene, cb, side, h, wtxt, len(k["flips"]), k["run"], 100 * k["cut"],
               k["x"][0], k["x"][1], k["y"][0], k["y"][1], k["first"], k["last"], name(cb)))


def head_line(tag, heads):
    if not heads:
        return "%s: no header (the monitor wrote nothing)" % tag
    h = heads[-1]
    return "%s: aspect %.4f fix %d visible columns %.2f..%.2f" % (
        tag, h["aspect"], h["fix"], h["vx0"], h["vx1"])


def cmd_table(path):
    heads, ks = kinds(path)
    print(head_line(path, heads))
    for key in sorted(ks):
        print("  " + fmt(key, ks[key]))
    print("%d kinds" % len(ks))


def cmd_diff(ref, test):
    hr, kr = kinds(ref)
    ht, kt = kinds(test)
    print(head_line("ref ", hr))
    print(head_line("test", ht))
    only = sorted(k for k in kt if k not in kr)
    both = sorted(k for k in kt if k in kr)
    gone = sorted(k for k in kr if k not in kt)
    worse = [k for k in both
             if abs(kt[k]["cut"] - kr[k]["cut"]) > 0.10
             or kt[k]["run"] > 2 * kr[k]["run"] + 12 or kr[k]["run"] > 2 * kt[k]["run"] + 12]
    print("\nONLY IN TEST (%d): the fix's, each needs an explanation" % len(only))
    for k in only:
        print("  " + fmt(k, kt[k]))
    print("\nIN BOTH, BUT NOT ALIKE (%d): cut 10 points deeper or shallower, or twice as long" % len(worse))
    for k in worse:
        print("  test " + fmt(k, kt[k]))
        print("  ref  " + fmt(k, kr[k]))
    print("\nIN BOTH, ALIKE (%d): the title's own" % (len(both) - len(worse)))
    for k in both:
        if k not in worse:
            print("  test " + fmt(k, kt[k]))
            print("  ref  " + fmt(k, kr[k]))
    print("\nONLY IN REF (%d)" % len(gone))
    for k in gone:
        print("  " + fmt(k, kr[k]))
    return 1 if only else 0


def cmd_trace(path, cb_text, lo=None, hi=None):
    cb = int(cb_text, 16)
    heads, _, ts = parse(path)
    print(head_line(path, heads))
    last = {}
    for r in ts:
        if r["cb"] != cb:
            continue
        if lo is not None and r["flip"] < lo or hi is not None and r["flip"] > hi:
            continue
        sig = (round(r["x0"], 1), round(r["x1"], 1), round(r["y0"], 1), round(r["y1"], 1), r["side"])
        o = last.get(r["obj"])
        if o and o["sig"] == sig and r["flip"] == o["end"] + 1:
            o["end"] = r["flip"]
            continue
        if o:
            emit(o)
        last[r["obj"]] = dict(sig=sig, start=r["flip"], end=r["flip"], r=r)
    for o in sorted(last.values(), key=lambda o: o["start"]):
        emit(o)


def emit(o):
    r = o["r"]
    print("  %6d..%-6d s%d obj %08X fr %08X x %7.1f..%7.1f y %5.1f..%5.1f w %.0f h %.0f a %.2f %s"
          % (o["start"], o["end"], r["scene"], r["obj"], r["fr"], r["x0"], r["x1"],
             r["y0"], r["y1"], r["w"], r["h"], r["a"], r["side"]))


def cmd_same(a, b, flips):
    def rows(path):
        _, _, ts = parse(path)
        hud = [r["flip"] for r in ts if r["scene"] == 0]
        if not hud:
            return None, {}
        first = min(hud)
        out = defaultdict(list)
        for r in ts:
            d = r["flip"] - first
            if 0 <= d < flips and r["scene"] != 2:
                out[d].append((r["scene"], r["layer"], r["cb"], r["x0"], r["x1"], r["y0"], r["y1"],
                               r["w"], r["h"], r["a"], r["side"]))
        return first, out
    fa, ra = rows(a)
    fb, rb = rows(b)
    if fa is None or fb is None:
        print("no HUD rows: trace with BO3_HUD_MON_TRACE=all")
        return 1

    def differing(shift):
        return [d for d in range(3, flips - 3)
                if sorted(ra.get(d, [])) != sorted(rb.get(d + shift, []))]
    # A run can miss the first frame of the HUD's entrance: the same frames,
    # a flip or two apart. The shift with the fewest differences.
    shift = min(range(-3, 4), key=lambda k: (len(differing(k)), abs(k)))
    bad = differing(shift)
    for d in bad[:5]:
        sa, sb = set(ra.get(d, [])), set(rb.get(d + shift, []))
        print("flip +%d differs: %d rows against %d" % (d, len(ra.get(d, [])), len(rb.get(d + shift, []))))
        for row in sorted(sa - sb)[:4]:
            print("   a only: s%d L%02d cb %08X x %.2f..%.2f y %.2f..%.2f w %.2f h %.2f a %.2f" % row[:10])
        for row in sorted(sb - sa)[:4]:
            print("   b only: s%d L%02d cb %08X x %.2f..%.2f y %.2f..%.2f w %.2f h %.2f a %.2f" % row[:10])
    n = sum(len(ra.get(d, [])) for d in range(3, flips - 3))
    print("HUD first drawn at flip %d / %d, b taken %+d flips; %d flips compared, %d rows in a, %d flips differ"
          % (fa, fb, shift, flips - 6, n, len(bad)))
    return 1 if bad or not n else 0


def cmd_present(out, shape, files, vis=(21, 619)):
    import os
    from PIL import Image
    os.makedirs(out, exist_ok=True)
    w = 1280 if shape == "169" else 960
    for f in files:
        im = Image.open(f).convert("RGB").crop((vis[0], 16, vis[1], 464)).resize((w, 720), Image.BILINEAR)
        im.save(os.path.join(out, os.path.splitext(os.path.basename(f))[0] + ".png"))


def main(argv):
    if len(argv) >= 3 and argv[1] == "table":
        return cmd_table(argv[2])
    if len(argv) >= 4 and argv[1] == "diff":
        return cmd_diff(argv[2], argv[3])
    if len(argv) >= 4 and argv[1] == "trace":
        lo = int(argv[4]) if len(argv) > 4 else None
        hi = int(argv[5]) if len(argv) > 5 else None
        return cmd_trace(argv[2], argv[3], lo, hi)
    if len(argv) >= 4 and argv[1] == "same":
        return cmd_same(argv[2], argv[3], int(argv[4]) if len(argv) > 4 else 100)
    if len(argv) >= 5 and argv[1] == "present":
        files = argv[4:]
        vis = (21, 619)
        if "--vis" in files:
            i = files.index("--vis")
            vis = (int(files[i + 1]), int(files[i + 2]))
            files = files[:i] + files[i + 3:]
        return cmd_present(argv[2], argv[3], files, vis)
    sys.stderr.write(__doc__)
    return 2


if __name__ == "__main__":
    sys.exit(main(sys.argv) or 0)
