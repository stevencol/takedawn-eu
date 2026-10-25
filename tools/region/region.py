#!/usr/bin/env python3
"""Other releases of the title: their addresses for the ones the project uses.

Everything in config/ and core names the title by its addresses in the
North American default.xbe. config/region/<build>.json holds, for another
release, the address of each of those in that release's default.xbe; it is
made once by a maintainer who has both executables, and from then on a build
needs only the user's own default.xbe.

  region.py export --map build/region/map.json --xbe PAL/default.xbe \\
                   --build pal-retail [--name "..."]
      Collect every US address the project uses, look each up in the map
      (tools/region/addrmap.py build), and write config/region/<build>.json.
      Fails, writing nothing, if an address is not known for certain; an
      address placed by hand goes in that file's "overrides" and is kept.

  region.py apply --xbe default.xbe --out build/xr/region
      For regen.sh: say which release default.xbe is, write
      core/recomp/gen/region_map.h, and for a release other than NTSC-U
      the translated config/*.json and the recomp_manual.c the recompiler
      scans, into --out. Prints the build id; the files regen.sh should use
      are listed in --out/files.txt.
"""

import argparse
import glob
import hashlib
import json
import os
import re
import struct
import sys

ROOT = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

US_SHA256 = "9f497acd82adb8edfb72cc31aeeb35010b45d32b13a3f1fc6540717ff24d13f9"
GA_RE = re.compile(r"\bGA\((0x[0-9A-Fa-f]+)[uU]?\)")
SUB_RE = re.compile(r"\bsub_([0-9A-Fa-f]{8})(_gen)?\b")
SOURCES = ["core/*.c", "core/*.h", "core/recomp/*.c"]
MANUAL = "core/recomp/recomp_manual.c"
HEADER = "core/recomp/gen/region_map.h"


def code_only(src):
    """src with comments and string contents blanked (line structure kept)."""
    out, i, n = [], 0, len(src)
    while i < n:
        if src.startswith("/*", i):
            j = src.find("*/", i + 2)
            j = n if j < 0 else j + 2
            out.append(re.sub(r"[^\n]", " ", src[i:j]))
            i = j
        elif src.startswith("//", i):
            j = src.find("\n", i)
            j = n if j < 0 else j
            out.append(" " * (j - i))
            i = j
        elif src[i] == '"':
            j = i + 1
            while j < n and src[j] not in '"\n':
                j += 2 if src[j] == "\\" else 1
            out.append('"' + " " * (j - i - 1) + '"')
            i = j + 1
        else:
            out.append(src[i])
            i += 1
    return "".join(out)


def sources():
    for pat in SOURCES:
        for f in sorted(glob.glob(os.path.join(ROOT, pat))):
            yield f, code_only(open(f, encoding="utf-8").read())


def load_json(rel):
    return json.load(open(os.path.join(ROOT, rel), encoding="utf-8"))


def used_addresses():
    """{US address: (kind, where)}. kind: code (an instruction), data."""
    used = {}

    def add(va, kind, where):
        if va not in used or kind == "code":
            used[va] = (kind, where)

    for p in load_json("config/patches.json")["patches"]:
        add(int(p["va"], 16), "code", "patches.json")
        for v in (p.get("if") or {}).get("in", []):
            add(int(v, 16), "data", "patches.json if")
    for s in load_json("config/seed_functions.json"):
        add(int(s["start"], 16), "code", "seed_functions.json")
    for s in load_json("config/spin_waits.json")["sites"]:
        add(int(s["va"], 16), "code", "spin_waits.json")
    for f, src in sources():
        rel = os.path.relpath(f, ROOT).replace(os.sep, "/")
        for m in GA_RE.finditer(src):
            add(int(m.group(1), 16), "data", rel)
        for m in SUB_RE.finditer(src):
            add(int(m.group(1), 16), "code", rel)
    return used


def xbe_info(path):
    d = open(path, "rb").read()
    if d[:4] != b"XBEH":
        sys.exit(f"{path}: not an XBE")
    base = struct.unpack_from("<I", d, 0x104)[0]
    cert = struct.unpack_from("<I", d, 0x118)[0] - base
    return {
        "sha256": hashlib.sha256(d).hexdigest(),
        "size": len(d),
        "title_id": f"0x{struct.unpack_from('<I', d, cert + 8)[0]:08X}",
        "region": struct.unpack_from("<I", d, cert + 0xA0)[0],
        "version": struct.unpack_from("<I", d, cert + 0xAC)[0],
    }


def export(args):
    from addrmap import Map
    m = Map(args.map)
    info = xbe_info(args.xbe)
    out = args.o or os.path.join(ROOT, "config", "region", args.build + ".json")
    old = json.load(open(out)) if os.path.exists(out) else {}
    overrides = {int(k, 16): int(v, 16) for k, v in old.get("overrides", {}).items()
                 if not k.startswith("_")}

    table, review, bad = {}, {}, []
    for va, (kind, where) in sorted(used_addresses().items()):
        if va in overrides:
            table[va] = overrides[va]
            continue
        to, how, why = m.lookup(va)
        if kind == "code" and how != "exact":
            bad.append(f"{va:#010x} ({where}): an instruction, but {how}: {why}")
        elif to is None or how in ("far", "conflict"):
            bad.append(f"{va:#010x} ({where}): {how}: {why}")
        else:
            table[va] = to
            if how in ("near", "word"):
                review[f"0x{va:08X}"] = f"{where}: {why}"
    if bad:
        print("not known for certain; place them by hand in 'overrides' of", out)
        for b in bad:
            print("  " + b)
        sys.exit(1)

    doc = {
        "about": "Addresses in this release's default.xbe of the ones config/ and "
                 "core use, which name the North American default.xbe. Made by "
                 "tools/region/region.py export from the two executables "
                 "(tools/region/addrmap.py); 'overrides' are placed by hand and "
                 "kept on export. 'review' lists those placed from a neighbour "
                 "rather than seen in the code.",
        "build": args.build,
        "name": args.name or old.get("name", args.build),
        "xbe": info,
        "overrides": old.get("overrides", {}),
        "review": review,
        "addresses": {f"0x{k:08X}": f"0x{v:08X}" for k, v in sorted(table.items())},
    }
    os.makedirs(os.path.dirname(out), exist_ok=True)
    with open(out, "w", encoding="utf-8", newline="\n") as f:
        json.dump(doc, f, indent=1)
        f.write("\n")
    print(f"{len(table)} addresses ({len(review)} to review, "
          f"{len(overrides)} by hand) -> {os.path.relpath(out, ROOT)}")


def find_build(sha):
    for f in sorted(glob.glob(os.path.join(ROOT, "config", "region", "*.json"))):
        doc = json.load(open(f, encoding="utf-8"))
        if doc.get("xbe", {}).get("sha256") == sha:
            return doc
    return None


def write(path, text):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    with open(path, "w", encoding="utf-8", newline="\n") as f:
        f.write(text)


def apply(args):
    info = xbe_info(args.xbe)
    header = os.path.join(args.gen, "region_map.h") if args.gen else os.path.join(ROOT, HEADER)
    out = args.out
    os.makedirs(out, exist_ok=True)
    files = {
        "patches": os.path.join(ROOT, "config", "patches.json"),
        "seeds": os.path.join(ROOT, "config", "seed_functions.json"),
        "spin_waits": os.path.join(ROOT, "config", "spin_waits.json"),
        "manual": os.path.join(ROOT, MANUAL),
    }
    if info["sha256"] == US_SHA256:
        build = "ntsc-u-retail"
        write(header, "/* Generated by tools/region/region.py apply: NTSC-U, the\n"
                      " * addresses the sources are written in. */\n"
                      "#define BO3_BUILD_NTSC_U_RETAIL 1\n"
                      '#define BO3_BUILD_ID "ntsc-u-retail"\n'
                      f'#define BO3_XBE_SHA256 "{US_SHA256}"\n')
    else:
        doc = find_build(info["sha256"])
        if not doc:
            sys.exit(f"{args.xbe}: not a supported default.xbe (sha256 {info['sha256']}, "
                     f"region {info['region']}, version {info['version']})")
        build = doc["build"]
        table = {int(k, 16): int(v, 16) for k, v in doc["addresses"].items()}

        def to(va, where):
            if va not in table:
                sys.exit(f"{where}: {va:#010x} is not in config/region/{build}.json; "
                         f"run tools/region/region.py export again")
            return table[va]

        def hx(v):
            return f"0x{v:08X}"

        p = load_json("config/patches.json")
        for e in p["patches"]:
            e["va"] = hx(to(int(e["va"], 16), "patches.json"))
            if e.get("if", {}).get("in"):
                e["if"]["in"] = [hx(to(int(v, 16), "patches.json")) for v in e["if"]["in"]]
        s = load_json("config/seed_functions.json")
        for e in s:
            e["start"] = hx(to(int(e["start"], 16), "seed_functions.json"))
        w = load_json("config/spin_waits.json")
        for e in w["sites"]:
            e["va"] = hx(to(int(e["va"], 16), "spin_waits.json"))
        files = {k: os.path.join(out, os.path.basename(v)) for k, v in files.items()}
        for k, obj in (("patches", p), ("seeds", s), ("spin_waits", w)):
            write(files[k], json.dumps(obj, indent=1) + "\n")

        # The recompiler reads what recomp_manual.c defines by name; give it
        # the names of this release (the compiler gets them from the header).
        # Every name in its code is in the table; one only in a comment may
        # not be, and stays as it is.
        man = open(os.path.join(ROOT, MANUAL), encoding="utf-8").read()
        write(files["manual"], SUB_RE.sub(
            lambda m: (f"sub_{table[int(m.group(1), 16)]:08X}{m.group(2) or ''}"
                       if int(m.group(1), 16) in table else m.group(0)), man))

        lits, subs = {}, set()
        for f, src in sources():
            for m in GA_RE.finditer(src):
                lit = m.group(0)[3:-1]
                lits[lit] = to(int(m.group(1), 16), f)
            for m in SUB_RE.finditer(src):
                subs.add(int(m.group(1), 16))
        lines = [f"/* Generated by tools/region/region.py apply: {doc['name']}.",
                 f" * From config/region/{build}.json; do not edit. */",
                 f"#define BO3_BUILD_{build.upper().replace('-', '_')} 1",
                 f'#define BO3_BUILD_ID "{build}"',
                 f'#define BO3_XBE_SHA256 "{info["sha256"]}"',
                 "#define GA(x) GA_##x"]
        lines += [f"#define GA_{lit} 0x{v:08X}u" for lit, v in sorted(lits.items())]
        for va in sorted(subs):
            o = to(va, "sources")
            lines.append(f"#define sub_{va:08X} sub_{o:08X}")
            lines.append(f"#define sub_{va:08X}_gen sub_{o:08X}_gen")
        write(header, "\n".join(lines) + "\n")
    write(os.path.join(out, "files.txt"),
          "".join(f"{k}={v}\n" for k, v in files.items()))
    print(build)


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    sub = ap.add_subparsers(dest="cmd", required=True)
    e = sub.add_parser("export")
    e.add_argument("--map", required=True)
    e.add_argument("--xbe", required=True, help="the other release's default.xbe")
    e.add_argument("--build", required=True, help="its id, e.g. pal-retail")
    e.add_argument("--name")
    e.add_argument("-o", help="default: config/region/<build>.json")
    a = sub.add_parser("apply")
    a.add_argument("--xbe", required=True)
    a.add_argument("--out", required=True)
    a.add_argument("--gen", help="the generated-code folder the header goes in "
                                 "(default core/recomp/gen)")
    args = ap.parse_args()
    {"export": export, "apply": apply}[args.cmd](args)


if __name__ == "__main__":
    main()
