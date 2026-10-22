#!/usr/bin/env python3
"""The disc manifest: path, size and SHA-256 of every file of the supported
disc, which the game's own installer (burnout3 --install, the toolkit's
src/install) checks the player's disc against.

    python3 tools/release/make_manifest.py "<disc image>"          write it
    python3 tools/release/make_manifest.py --check "<image or folder>"

Made from a disc image, never from a folder the game has run in: the title
writes CACHE/LocalCache*.bin beside its data, which are not on the disc.
The image's default.xbe must be the supported build (tools/install/supported.json).
The file holds names, sizes and hashes only, none of the disc's contents, and
is committed; the build compiles it in (cmake/release_info.cmake).

The id on the "# id" line is the first 16 hex digits of the SHA-256 of the
entry lines (each with its newline). It names the manifest in the installed
data's .complete marker and in --version.
"""

import argparse
import hashlib
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "install"))

import disc      # noqa: E402
import xdvdfs    # noqa: E402

DEFAULT_OUT = os.path.join(HERE, "..", "..", "config", "disc", "%s.manifest")


def image_entries(path):
    """[(path, size, sha256)] of an image, sorted by path, and the build."""
    out = []
    with xdvdfs.Image(path) as img:
        xbe = img.find("default.xbe")
        if xbe is None:
            raise SystemExit("no default.xbe in the image")
        build = disc.check_xbe(img.read(xbe))
        for e in img.walk():
            h = hashlib.sha256()
            left = e.size
            img._f.seek(img.base + e.sector * xdvdfs.SECTOR)
            while left:
                data = img._f.read(min(left, 4 << 20))
                if not data:
                    raise SystemExit("the image ends inside " + e.path)
                h.update(data)
                left -= len(data)
            out.append((e.path, e.size, h.hexdigest()))
    return sorted(out), build


def folder_entries(path):
    root = disc.find_folder_root(path)
    out = []
    for dp, _, fn in os.walk(root):
        for n in fn:
            p = os.path.join(dp, n)
            h = hashlib.sha256()
            with open(p, "rb") as f:
                for data in iter(lambda: f.read(4 << 20), b""):
                    h.update(data)
            out.append((os.path.relpath(p, root).replace(os.sep, "/"), os.path.getsize(p),
                        h.hexdigest()))
    return sorted(out)


def body(entries):
    return "".join("%s %d %s\n" % (sha, size, path) for path, size, sha in entries)


def manifest_id(entries):
    return hashlib.sha256(body(entries).encode("utf-8")).hexdigest()[:16]


def read_manifest(path):
    entries = []
    with open(path, encoding="utf-8") as f:
        for line in f:
            if line.startswith("#") or not line.strip():
                continue
            sha, size, name = line.rstrip("\n").split(" ", 2)
            entries.append((name, int(size), sha))
    return entries


def main():
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("source", help="the disc image (--check: an image or an extracted folder)")
    ap.add_argument("-o", "--out", help="the manifest (default config/disc/<build id>.manifest)")
    ap.add_argument("--check", action="store_true",
                    help="compare the source with the manifest instead of writing it")
    a = ap.parse_args()

    if os.path.isdir(a.source):
        if not a.check:
            raise SystemExit("a manifest is made from a disc image; a folder can only be --check'ed")
        entries = folder_entries(a.source)
        with open(os.path.join(disc.find_folder_root(a.source), "default.xbe"), "rb") as f:
            build = disc.check_xbe(f.read())
    else:
        entries, build = image_entries(a.source)
    out = a.out or DEFAULT_OUT % build["id"]

    if a.check:
        want = {p: (s, h) for p, s, h in read_manifest(out)}
        got = {p: (s, h) for p, s, h in entries}
        missing = sorted(set(want) - set(got))
        extra = sorted(set(got) - set(want))
        differ = sorted(p for p in want if p in got and want[p] != got[p])
        for what, names in (("missing", missing), ("not on the disc", extra), ("different", differ)):
            for n in names:
                print("%s: %s" % (what, n))
        print("%d files in the manifest, %d in the source: %d missing, %d not on the disc, "
              "%d different" % (len(want), len(got), len(missing), len(extra), len(differ)))
        return 1 if missing or differ else 0

    text = ("# Takedawn disc manifest 1: sha256, size, path of every file of the disc.\n"
            "# Made by tools/release/make_manifest.py from a disc image; do not edit.\n"
            "# build %s\n# title_id %s\n# files %d\n# bytes %d\n# id %s\n"
            % (build["id"], build["xbe"]["title_id"], len(entries),
               sum(s for _, s, _ in entries), manifest_id(entries))) + body(entries)
    os.makedirs(os.path.dirname(os.path.abspath(out)), exist_ok=True)
    with open(out, "w", encoding="utf-8", newline="\n") as f:
        f.write(text)
    print("%s: %d files, %d bytes, id %s" % (os.path.normpath(out), len(entries),
                                             sum(s for _, s, _ in entries), manifest_id(entries)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
