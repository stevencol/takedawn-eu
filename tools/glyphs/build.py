#!/usr/bin/env python3
"""Renders assets/glyphs/<family>/*.svg at 1:1 and writes them as C arrays for
core/glyphs.c (and, with --png, as PNG files to look at).

    build.py <assets/glyphs> <out.c> <out.h> [--png <dir>]
    build.py --check        prints the renderer found; status 1 if there is none

The renderer is the one assets/icon uses (tools/install/gui/render_icon.py):
the `resvg` program, `rsvg-convert`, or the resvg_py module of the Python that
runs this. The PNG it writes is read here with zlib, so nothing else is needed.

Each picture becomes `const uint32_t bo3_glyph_<family>_<name>[w * h]`,
A8R8G8B8 words, rows top to bottom: the layout the runtime's texture decode
has (nv2a_texrep.h). Pixels with no coverage take the colour of their nearest
covered neighbours, so that a bilinear sample at an edge does not darken it.
Nothing rendered is kept in the repository.
"""
import os
import shutil
import struct
import subprocess
import sys
import tempfile
import zlib


def renderer():
    if shutil.which("resvg"):
        return "resvg"
    if shutil.which("rsvg-convert"):
        return "rsvg-convert"
    try:
        import resvg_py  # noqa: F401
        return "resvg_py"
    except ImportError:
        return None


def render_png(how, svg, w, h):
    if how == "resvg_py":
        import resvg_py
        return bytes(resvg_py.svg_to_bytes(svg_path=svg, width=w, height=h))
    with tempfile.TemporaryDirectory() as tmp:
        out = os.path.join(tmp, "g.png")
        if how == "resvg":
            subprocess.run(["resvg", "-w", str(w), "-h", str(h), svg, out], check=True)
        else:
            subprocess.run(["rsvg-convert", "-w", str(w), "-h", str(h), svg, "-o", out], check=True)
        with open(out, "rb") as f:
            return f.read()


def png_rgba(data):
    """An 8-bit, non-interlaced PNG (grey, grey+alpha, RGB or RGBA) as (w, h, [(r, g, b, a)...])."""
    if data[:8] != b"\x89PNG\r\n\x1a\n":
        raise ValueError("not a PNG")
    pos, idat, w = 8, b"", 0
    while pos < len(data):
        n, kind = struct.unpack(">I4s", data[pos:pos + 8])
        body = data[pos + 8:pos + 8 + n]
        pos += 12 + n
        if kind == b"IHDR":
            w, h, depth, ctype, _, _, interlace = struct.unpack(">IIBBBBB", body)
            if depth != 8 or interlace or ctype not in (0, 2, 4, 6):
                raise ValueError("PNG kind not read here (depth %d, type %d)" % (depth, ctype))
        elif kind == b"IDAT":
            idat += body
    ch = {0: 1, 2: 3, 4: 2, 6: 4}[ctype]
    raw = zlib.decompress(idat)
    stride = w * ch
    prev = bytearray(stride)
    px = []
    for y in range(h):
        f = raw[y * (stride + 1)]
        row = bytearray(raw[y * (stride + 1) + 1:(y + 1) * (stride + 1)])
        for i in range(stride):
            a = row[i - ch] if i >= ch else 0
            b = prev[i]
            c = prev[i - ch] if i >= ch else 0
            if f == 1:
                row[i] = (row[i] + a) & 255
            elif f == 2:
                row[i] = (row[i] + b) & 255
            elif f == 3:
                row[i] = (row[i] + ((a + b) >> 1)) & 255
            elif f == 4:
                p = a + b - c
                pa, pb, pc = abs(p - a), abs(p - b), abs(p - c)
                row[i] = (row[i] + (a if pa <= pb and pa <= pc else b if pb <= pc else c)) & 255
        for x in range(w):
            v = row[x * ch:(x + 1) * ch]
            if ch == 4:
                px.append((v[0], v[1], v[2], v[3]))
            elif ch == 3:
                px.append((v[0], v[1], v[2], 255))
            elif ch == 2:
                px.append((v[0], v[0], v[0], v[1]))
            else:
                px.append((v[0], v[0], v[0], 255))
        prev = row
    return w, h, px


def bleed(w, h, px, rounds=3):
    """Uncovered pixels take the mean colour of their covered neighbours (alpha stays 0)."""
    known = [p[3] > 0 for p in px]
    for _ in range(rounds):
        new, newk = list(px), list(known)
        for y in range(h):
            for x in range(w):
                i = y * w + x
                if known[i]:
                    continue
                r = g = b = n = 0
                for dy in (-1, 0, 1):
                    for dx in (-1, 0, 1):
                        xx, yy = x + dx, y + dy
                        if 0 <= xx < w and 0 <= yy < h and known[yy * w + xx]:
                            q = px[yy * w + xx]
                            r, g, b, n = r + q[0], g + q[1], b + q[2], n + 1
                if n:
                    new[i] = (r // n, g // n, b // n, 0)
                    newk[i] = True
        px, known = new, newk
    return px


def write_png(path, w, h, px):
    raw = b"".join(b"\x00" + b"".join(bytes(p) for p in px[y * w:(y + 1) * w]) for y in range(h))

    def chunk(kind, body):
        return struct.pack(">I", len(body)) + kind + body + struct.pack(">I", zlib.crc32(kind + body) & 0xFFFFFFFF)
    with open(path, "wb") as f:
        f.write(b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 6, 0, 0, 0))
                + chunk(b"IDAT", zlib.compress(raw, 9)) + chunk(b"IEND", b""))


def svg_size(path):
    head = open(path, encoding="utf-8").read(400)
    w = int(head.split('width="')[1].split('"')[0])
    h = int(head.split('height="')[1].split('"')[0])
    return w, h


def main(argv):
    how = renderer()
    if len(argv) == 2 and argv[1] == "--check":
        print(how or "none")
        return 0 if how else 1
    if len(argv) < 4:
        sys.stderr.write(__doc__)
        return 2
    if not how:
        sys.stderr.write("build.py: no SVG renderer (resvg, rsvg-convert or the resvg_py module)\n")
        return 1
    root, out_c, out_h = argv[1], argv[2], argv[3]
    png_dir = argv[5] if len(argv) > 5 and argv[4] == "--png" else None
    c = ["/* Generated by tools/glyphs/build.py from assets/glyphs. Not kept in the repository. */",
         '#include "%s"' % os.path.basename(out_h), ""]
    hd = ["/* Generated by tools/glyphs/build.py from assets/glyphs. Not kept in the repository. */",
          "#ifndef BO3_GLYPH_ART_H", "#define BO3_GLYPH_ART_H", "#include <stdint.h>", ""]
    for fam in sorted(os.listdir(root)):
        d = os.path.join(root, fam)
        if not os.path.isdir(d):
            continue
        for name in sorted(os.listdir(d)):
            if not name.endswith(".svg"):
                continue
            svg = os.path.join(d, name)
            w, h = svg_size(svg)
            pw, ph, px = png_rgba(render_png(how, svg, w, h))
            if (pw, ph) != (w, h):
                raise SystemExit("%s: rendered %dx%d, wanted %dx%d" % (svg, pw, ph, w, h))
            if png_dir:
                os.makedirs(os.path.join(png_dir, fam), exist_ok=True)
                write_png(os.path.join(png_dir, fam, name[:-4] + ".png"), w, h, px)
            px = bleed(w, h, px)
            sym = "bo3_glyph_%s_%s" % (fam, name[:-4])
            hd.append("extern const uint32_t %s[%d * %d];" % (sym, w, h))
            c.append("const uint32_t %s[%d * %d] = {" % (sym, w, h))
            for y in range(h):
                c.append("    " + ",".join("0x%02X%02X%02X%02Xu" % (p[3], p[0], p[1], p[2])
                                           for p in px[y * w:(y + 1) * w]) + ",")
            c.append("};")
            c.append("")
    hd += ["", "#endif", ""]
    for path, lines in ((out_c, c), (out_h, hd)):
        os.makedirs(os.path.dirname(os.path.abspath(path)), exist_ok=True)
        with open(path, "w", encoding="utf-8", newline="\n") as f:
            f.write("\n".join(lines))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
