#!/usr/bin/env python3
"""The Android adaptive icon from assets/icon: three vector drawables.

    tools/android/make-icon.py        # writes adapters/android/res/drawable/ic_launcher_*.xml

assets/icon/takedawn-android-fg.svg and -bg.svg are the two layers (original
artwork, see assets/icon/README.md). Android takes vector drawables, not SVG,
and the build has no SVG renderer, so this script writes the same shapes in
that form: it reads the path data and the colours out of the two SVG files
(they are plain paths and gradients) and fails when a file no longer has the
shapes it expects. The monochrome layer (Android 13's themed icons) is the T
with its two speed bars cut out. The results are committed; run this again
when the artwork changes.
"""
import os, re, sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
SRC = os.path.join(ROOT, "assets", "icon")
OUT = os.path.join(ROOT, "adapters", "android", "res", "drawable")
HEAD = '<?xml version="1.0" encoding="utf-8"?>\n<!-- Made by tools/android/make-icon.py from assets/icon/%s; do not edit. -->\n'
VEC = ('<vector xmlns:android="http://schemas.android.com/apk/res/android"\n'
       '    xmlns:aapt="http://schemas.android.com/aapt"\n'
       '    android:width="108dp" android:height="108dp"\n'
       '    android:viewportWidth="1024" android:viewportHeight="1024">\n')


def need(cond, what):
    if not cond:
        sys.exit("make-icon.py: " + what)


def argb(rgb, alpha):
    return "#%02X%s" % (round(float(alpha) * 255), rgb.lstrip("#").upper())


def stops(svg, gid):
    m = re.search(r'<(?:linear|radial)Gradient id="%s"[^>]*>(.*?)</' % gid, svg)
    need(m, "no gradient " + gid)
    out = []
    for s in re.findall(r"<stop ([^>]*)/>", m.group(1)):
        a = dict(re.findall(r'([\w-]+)="([^"]*)"', s))
        out.append((a["offset"], argb(a["stop-color"], a.get("stop-opacity", "1"))))
    return out


def gradient(kind, geom, st):
    items = "".join('                <item android:offset="%s" android:color="%s"/>\n' % s for s in st)
    return ('            <aapt:attr name="android:fillColor">\n'
            '              <gradient android:type="%s" %s>\n%s              </gradient>\n'
            '            </aapt:attr>\n' % (kind, geom, items))


def foreground():
    svg = open(os.path.join(SRC, "takedawn-android-fg.svg")).read()
    g = re.search(r'<g transform="translate\(512 512\) scale\(([\d.]+)\) translate\(-512 -512\)">', svg)
    need(g, "the foreground's group transform changed")
    scale = g.group(1)
    paths = re.findall(r"<path ([^>]*)/>", svg)
    need(len(paths) == 9, "the foreground has %d paths, not 9" % len(paths))
    P = [dict(re.findall(r'([\w-]+)="([^"]*)"', p)) for p in paths]
    t = P[0]["d"]
    ys = [float(y) for y in re.findall(r",([\d.]+)", t)]
    y0, y1 = min(ys), max(ys)
    body = ""
    for p in P[:3]:                     # the glow: three strokes round the T
        need(p["d"] == t and p["fill"] == "none", "the glow strokes changed")
        body += ('        <path android:pathData="%s" android:strokeColor="%s" android:strokeAlpha="%s"\n'
                 '            android:strokeWidth="%s" android:strokeLineJoin="round"/>\n'
                 % (t, p["stroke"], p["stroke-opacity"], p["stroke-width"]))
    sh = re.match(r"translate\((\d+) (\d+)\)", P[3].get("transform", ""))
    need(sh and P[3]["d"] == t, "the shadow changed")
    body += ('        <group android:translateX="%s" android:translateY="%s">\n'
             '            <path android:pathData="%s" android:fillColor="%s"/>\n        </group>\n'
             % (sh.group(1), sh.group(2), t, P[3]["fill"]))
    geom = 'android:startX="0" android:startY="%s" android:endX="0" android:endY="%s"' % (y0, y1)
    for gid, p in (("ccr", P[4]), ("chl", P[5])):
        need(p["d"] == t and p["fill"] == "url(#%s)" % gid, "the T's fills changed")
        st = stops(svg, gid)
        if st[-1][0] != "1":
            st.append(("1", st[-1][1]))
        body += '        <path android:pathData="%s">\n%s        </path>\n' % (t, gradient("linear", geom, st))
    for p in P[6:8]:                    # the two speed bars
        body += '        <path android:pathData="%s" android:fillColor="%s"/>\n' % (p["d"], p["fill"])
    body += ('        <path android:pathData="%s" android:fillColor="%s" android:fillAlpha="%s"/>\n'
             % (P[8]["d"], P[8]["fill"], P[8]["fill-opacity"]))
    grp = ('    <group android:pivotX="512" android:pivotY="512" android:scaleX="%s" android:scaleY="%s">\n'
           % (scale, scale))
    fg = HEAD % "takedawn-android-fg.svg" + VEC + grp + body + "    </group>\n</vector>\n"
    mono = (HEAD % "takedawn-android-fg.svg" + VEC + grp
            + '        <path android:fillType="evenOdd" android:fillColor="#FFFFFFFF"\n'
              '            android:pathData="%s %s %s"/>\n' % (t, P[6]["d"], P[7]["d"])
            + "    </group>\n</vector>\n")
    return fg, mono


def background():
    svg = open(os.path.join(SRC, "takedawn-android-bg.svg")).read()
    need(svg.count('<rect width="1024" height="1024"') == 2, "the background's rectangles changed")
    grid = re.search(r'<g stroke="(#\w+)" stroke-opacity="([\d.]+)" stroke-width="(\d+)">(.*?)</g>', svg)
    need(grid, "the background's grid changed")
    lines = " ".join(re.findall(r'<path d="([^"]*)"/>', grid.group(4)))
    rad = re.search(r'<radialGradient id="cgl"[^>]*cx="(\d+)" cy="(\d+)" r="(\d+)"', svg)
    need(rad, "the background's glow changed")
    box = "M0,0 H1024 V1024 H0 Z"
    return (HEAD % "takedawn-android-bg.svg" + VEC
            + '    <path android:pathData="%s">\n%s    </path>\n'
              % (box, gradient("linear", 'android:startX="0" android:startY="0" android:endX="0" android:endY="1024"',
                               stops(svg, "cbg")))
            + '    <path android:pathData="%s" android:strokeColor="%s" android:strokeAlpha="%s" android:strokeWidth="%s"/>\n'
              % (lines, grid.group(1), grid.group(2), grid.group(3))
            + '    <path android:pathData="%s">\n%s    </path>\n'
              % (box, gradient("radial", 'android:centerX="%s" android:centerY="%s" android:gradientRadius="%s"'
                               % rad.groups(), stops(svg, "cgl")))
            + "</vector>\n")


def main():
    os.makedirs(OUT, exist_ok=True)
    fg, mono = foreground()
    for name, text in (("ic_launcher_foreground.xml", fg), ("ic_launcher_monochrome.xml", mono),
                       ("ic_launcher_background.xml", background())):
        with open(os.path.join(OUT, name), "w") as f:
            f.write(text)
        print("wrote adapters/android/res/drawable/" + name)


if __name__ == "__main__":
    main()
