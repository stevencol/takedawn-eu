#!/usr/bin/env python3
"""Map guest addresses of the North American default.xbe to another release.

The PAL build is the same program as the NTSC-U one, compiled again with a
few hundred bytes of code added here and there, so every function and every
global sits a little further on, by an amount that changes along the image.
This aligns the two executables instruction by instruction and learns the
map from them:

  - code:  each matched instruction start, US -> other;
  - data:  each address an instruction holds (a global, a constant, a call
           or jump target, a vtable...), paired with the address the same
           operand holds in the other build. The BSS, which has no bytes to
           compare, is only known this way.

Addresses nobody references directly (a field inside a struct, an
instruction inside a run the alignment skipped) are placed by the nearest
known neighbour; the result says how sure each one is.

  addrmap.py build US.xbe OTHER.xbe -o map.json
  addrmap.py lookup map.json 0x59BF7 0x45B9BC ...

Nothing here reads game data beyond the two executables the user gives it,
and map.json, made from them, is not committed.
"""

import argparse
import bisect
import collections
import json
import re
import struct
import sys

import capstone

IMG_LO, IMG_HI = 0x00010000, 0x00800000
CODE_SECTIONS = {".text", "XMV", "DSOUND", "WMADEC", "XONLINE", "XNET",
                 "D3D", "XGRPH", "XPP"}
HEX = re.compile(r"0x[0-9a-fA-F]+|\b\d+\b")
BRANCH = re.compile(r"^(j[a-z]+|call|loop[a-z]*|jecxz)$")

# Resync search when the two instruction streams diverge: up to MAXD
# instructions skipped in total, and K matching instructions to accept.
MAXD = 600
K = 10


class Xbe:
    def __init__(self, path):
        self.path = path
        self.d = open(path, "rb").read()
        d = self.d
        if d[:4] != b"XBEH":
            sys.exit(f"{path}: not an XBE")
        base = struct.unpack_from("<I", d, 0x104)[0]
        n = struct.unpack_from("<I", d, 0x11C)[0]
        sh = struct.unpack_from("<I", d, 0x120)[0] - base
        self.sections = []
        for i in range(n):
            _fl, va, vs, ra, rs, na = struct.unpack_from("<IIIIII", d, sh + i * 0x38)
            name = d[na - base:d.index(b"\0", na - base)].decode()
            self.sections.append((name, va, vs, ra, rs))
        cert = struct.unpack_from("<I", d, 0x118)[0] - base
        self.title_id = struct.unpack_from("<I", d, cert + 8)[0]
        self.region = struct.unpack_from("<I", d, cert + 0xA0)[0]
        self.version = struct.unpack_from("<I", d, cert + 0xAC)[0]
        self.entry = struct.unpack_from("<I", d, 0x128)[0]

    def section(self, va):
        for s in self.sections:
            if s[1] <= va < s[1] + s[2]:
                return s
        return None

    def byte_at(self, va, n):
        s = self.section(va)
        if not s or va + n > s[1] + s[4]:
            return None
        o = s[3] + va - s[1]
        return self.d[o:o + n]


def disasm(x):
    """Linear sweep of the code sections: (va, token, [image addresses])."""
    md = capstone.Cs(capstone.CS_ARCH_X86, capstone.CS_MODE_32)
    out = []
    for name, va, _vs, ra, rs in x.sections:
        if name not in CODE_SECTIONS:
            continue
        code = x.d[ra:ra + rs]
        off = 0
        while off < len(code):
            got = False
            for ins in md.disasm_lite(code[off:], va + off):
                a, size, mn, ops = ins
                addrs = []

                def norm(m):
                    v = int(m.group(0), 0)
                    if IMG_LO <= v < IMG_HI:
                        addrs.append(v)
                        return "A"
                    return m.group(0)
                tok = mn + " " + HEX.sub(norm, ops)
                out.append((a, hash(tok), addrs, size))
                off += size
                got = True
            if off < len(code):
                # undecodable byte (data in the code section): one token, step on
                out.append((va + off, hash("db"), [], 1))
                off += 1
            elif not got:
                break
    return out


def words(x):
    """The initialized data sections as 4-byte words: (va, token, [image addresses])."""
    out = []
    for name, va, _vs, ra, rs in x.sections:
        if name in CODE_SECTIONS or name.startswith("$$"):
            continue
        for o in range(0, rs - 3, 4):
            v = struct.unpack_from("<I", x.d, ra + o)[0]
            if IMG_LO <= v < IMG_HI:
                out.append((va + o, hash("A"), [v], 4))
            else:
                out.append((va + o, hash(v), [], 4))
    return out


def align(us, ot):
    """Pairs (i, j) of matching instruction indexes, greedy with resync."""
    hu = [t[1] for t in us]
    ho = [t[1] for t in ot]
    pairs = []
    i = j = 0
    nu, no = len(hu), len(ho)
    gaps = []
    while i < nu and j < no:
        if hu[i] == ho[j]:
            pairs.append((i, j))
            i += 1
            j += 1
            continue
        found = None
        for d in range(1, MAXD + 1):
            for a in range(d + 1):
                b = d - a
                if i + a + K <= nu and j + b + K <= no and \
                        hu[i + a:i + a + K] == ho[j + b:j + b + K]:
                    found = (a, b)
                    break
            if found:
                break
        if not found:
            gaps.append((us[i][0], ot[j][0], "lost"))
            break
        gaps.append((us[i][0], ot[j][0], found))
        i += found[0]
        j += found[1]
    return pairs, gaps


def build(args):
    xu, xo = Xbe(args.us), Xbe(args.other)
    print(f"US    title {xu.title_id:08X} region {xu.region} version {xu.version}")
    print(f"other title {xo.title_id:08X} region {xo.region} version {xo.version}")
    du, do = disasm(xu), disasm(xo)
    print(f"instructions: US {len(du)}, other {len(do)}")
    pairs, gaps = align(du, do)
    print(f"matched {len(pairs)} ({100 * len(pairs) / len(du):.2f}% of US), "
          f"{len(gaps)} resyncs")

    wu, wo = words(xu), words(xo)
    wpairs, wgaps = align(wu, wo)
    print(f"data words: matched {len(wpairs)} of {len(wu)} "
          f"({100 * len(wpairs) / len(wu):.2f}%), {len(wgaps)} resyncs")

    code, data = {}, {}
    votes = collections.defaultdict(collections.Counter)
    for a, b, prs, pos in ((du, do, pairs, code), (wu, wo, wpairs, data)):
        for i, j in prs:
            ua, _, uaddr, _ = a[i]
            oa, _, oaddr, _ = b[j]
            pos[ua] = oa
            if len(uaddr) == len(oaddr):
                for u, o in zip(uaddr, oaddr):
                    votes[u][o] += 1
    # The instruction starts are references too (anything can point at them).
    refs = {}
    conflicts = {}
    for u, c in votes.items():
        (o, n), = c.most_common(1)
        refs[u] = o
        if len(c) > 1:
            conflicts[u] = dict(c)
    # Section starts and ends anchor what lies between references.
    for (n1, va1, vs1, *_), (n2, va2, vs2, *_) in zip(xu.sections, xo.sections):
        if n1 == n2:
            refs.setdefault(va1, va2)
    json.dump({
        "us": {"path": args.us, "region": xu.region, "version": xu.version,
               "entry": xu.entry, "sections": xu.sections},
        "other": {"path": args.other, "region": xo.region, "version": xo.version,
                  "entry": xo.entry, "sections": xo.sections},
        "code": {f"{k:08X}": v for k, v in sorted(code.items())},
        "data": {f"{k:08X}": v for k, v in sorted(data.items())},
        "refs": {f"{k:08X}": v for k, v in sorted(refs.items())},
        "conflicts": {f"{k:08X}": {f"{a:08X}": n for a, n in v.items()}
                      for k, v in sorted(conflicts.items())},
        "gaps": [[f"{a:08X}", f"{b:08X}", g] for a, b, g in gaps],
    }, open(args.o, "w"), indent=0)
    print(f"code {len(code)}, data {len(data)}, refs {len(refs)}, "
          f"conflicting refs {len(conflicts)}"
          f" -> {args.o}")


class Map:
    def __init__(self, path):
        m = json.load(open(path))
        self.m = m
        self.code = {int(k, 16): v for k, v in m["code"].items()}
        self.refs = {int(k, 16): v for k, v in m["refs"].items()}
        self.data = {int(k, 16): v for k, v in m["data"].items()}
        self.conflicts = {int(k, 16) for k in m["conflicts"]}
        both = dict(self.refs)
        both.update(self.data)
        both.update(self.code)
        self.keys = sorted(both)
        self.both = both
        self.us_secs = m["us"]["sections"]
        self.ot_secs = {s[0]: s for s in m["other"]["sections"]}

    def sec(self, va):
        for s in self.us_secs:
            if s[1] <= va < s[1] + s[2]:
                return s[0]
        return None

    def lookup(self, va):
        """(other address or None, how: exact|ref|near|far|outside, detail)."""
        if va in self.code:
            return self.code[va], "exact", "instruction"
        # What the code says wins over the data words: a run of pointers (a
        # vtable) all look alike to the word alignment, which can slip there.
        if va in self.refs:
            how = "ref" if va not in self.conflicts else "conflict"
            return self.refs[va], how, "referenced"
        if va in self.data:
            return self.data[va], "word", "aligned data word"
        name = self.sec(va)
        if name is None:
            return None, "outside", "not in the image"
        k = bisect.bisect_right(self.keys, va) - 1
        lo = self.keys[k] if k >= 0 else None
        hi = self.keys[k + 1] if k + 1 < len(self.keys) else None
        if lo is None or self.sec(lo) != name:
            return None, "far", "no anchor before it in its section"
        dlo = self.both[lo] - lo
        dhi = self.both[hi] - hi if hi is not None and self.sec(hi) == name else None
        how = "near" if dhi == dlo else "far"
        return va + dlo, how, (f"{va - lo:#x} after {lo:#010x}, delta {dlo:+#x}"
                               + (f", next anchor delta {dhi:+#x}" if dhi is not None else ""))


def lookup(args):
    m = Map(args.map)
    for a in args.addrs:
        va = int(a, 16)
        o, how, why = m.lookup(va)
        print(f"{va:#010x} -> {o:#010x}  {how:8} {why}" if o is not None
              else f"{va:#010x} -> ?           {how:8} {why}")


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    sub = ap.add_subparsers(dest="cmd", required=True)
    b = sub.add_parser("build")
    b.add_argument("us")
    b.add_argument("other")
    b.add_argument("-o", default="build/region/map.json")
    l = sub.add_parser("lookup")
    l.add_argument("map")
    l.add_argument("addrs", nargs="+")
    args = ap.parse_args()
    {"build": build, "lookup": lookup}[args.cmd](args)


if __name__ == "__main__":
    main()
