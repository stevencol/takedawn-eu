"""Disc input for the installer: an Xbox disc image (XDVDFS / XISO / redump) or a
folder already extracted from one -> the game data where the port expects it.

The port reads "Burnout 3 Takedown/" (the disc's contents) from its working
directory (core/main.c, BO3_GAME_DIR), so that is what ends up in
<root>/Game/. Only one build is supported; see supported.json.
"""

import json
import os
import shutil

try:                                    # run as a script (python tools/install/install.py)
    import xbe as xbe_mod
    import xdvdfs
except ImportError:                     # imported as a package
    from . import xbe as xbe_mod
    from . import xdvdfs

HERE = os.path.dirname(os.path.abspath(__file__))


class DiscError(Exception):
    """code: a short machine-readable word for the GUI; str(): the message."""

    def __init__(self, code, message):
        Exception.__init__(self, message)
        self.code = code


def load_supported(path=None):
    with open(path or os.path.join(HERE, "supported.json")) as f:
        return json.load(f)["builds"]


def check_xbe(data, builds=None):
    """The supported build `data` (the bytes of default.xbe) is, or DiscError."""
    builds = builds or load_supported()
    digest = xbe_mod.sha256(data)
    for b in builds:
        if b["xbe"]["sha256"] == digest:
            return b
    try:
        d = xbe_mod.Xbe(data).describe()
        what = "%s (title id %s, %s, %d bytes)" % (d["title"], d["title_id"], d["region"], d["size"])
    except xbe_mod.XbeError as e:
        raise DiscError("not-an-xbe", "default.xbe is not an Xbox executable: %s" % e)
    want = ", ".join(b["name"] for b in builds)
    raise DiscError("unsupported-xbe",
                    "this disc's default.xbe is %s, sha256 %s. This port supports only: %s "
                    "(sha256 %s). Other regions and patched executables have different code "
                    "addresses and cannot be recompiled with this configuration."
                    % (what, digest[:16] + "...", want, builds[0]["xbe"]["sha256"][:16] + "..."))


def find_folder_root(path):
    """The directory under `path` that holds default.xbe: `path` itself or a
    single level down (an extracted folder is often wrapped in one more)."""
    def has_xbe(d):
        try:
            return any(n.lower() == "default.xbe" for n in os.listdir(d))
        except OSError:
            return False
    if has_xbe(path):
        return path
    try:
        subs = sorted(n for n in os.listdir(path) if os.path.isdir(os.path.join(path, n)))
    except OSError:
        subs = []
    for n in subs:
        if has_xbe(os.path.join(path, n)):
            return os.path.join(path, n)
    raise DiscError("no-xbe", "no default.xbe in %s (or one folder below it): this is not an "
                              "extracted Xbox disc" % path)


def _listfile(d, name):
    for n in os.listdir(d):
        if n.lower() == name.lower():
            return os.path.join(d, n)
    return None


def probe(source, builds=None):
    """Identify `source` without writing anything. -> dict(kind, build, files,
    bytes, label) or DiscError. Reads default.xbe (4 MB) and the directory tables."""
    builds = builds or load_supported()
    if os.path.isdir(source):
        root = find_folder_root(source)
        with open(_listfile(root, "default.xbe"), "rb") as f:
            build = check_xbe(f.read(), builds)
        files = nbytes = 0
        for dp, _, fn in os.walk(root):
            for n in fn:
                files += 1
                nbytes += os.path.getsize(os.path.join(dp, n))
        return {"kind": "folder", "root": root, "build": build, "files": files, "bytes": nbytes}
    if not os.path.isfile(source):
        raise DiscError("no-source", "%s does not exist" % source)
    try:
        with xdvdfs.Image(source) as img:
            e = img.find("default.xbe")
            if e is None:
                hint = (" (it has a default.xex: an Xbox 360 disc, not an original Xbox one)"
                        if img.find("default.xex") else "")
                raise DiscError("no-xbe", "the image has no default.xbe in its root" + hint)
            build = check_xbe(img.read(e), builds)
            files = list(img.walk())
            return {"kind": "image", "base": img.base, "build": build, "files": len(files),
                    "bytes": sum(f.size for f in files)}
    except xdvdfs.XdvdfsError as e:
        raise DiscError("bad-image", str(e))


def _safe_join(base, rel):
    dest = os.path.normpath(os.path.join(base, *rel.split("/")))
    if dest != base and not dest.startswith(base + os.sep):
        raise DiscError("unsafe-path", "refusing to write outside the game folder: " + rel)
    return dest


def install(source, game_dir, builds=None, progress=None):
    """Put the disc's files in game_dir (".../Burnout 3 Takedown"). Restartable:
    a file already there with the right size is kept (files are written through
    ".part" and renamed, so a size match means it finished). Returns the probe
    dict. progress(fraction, text) is called as bytes are written."""
    info = probe(source, builds)
    game_dir = os.path.abspath(game_dir)
    total = max(info["bytes"], 1)
    done = [0]

    def tick(n, text=""):
        done[0] += n
        if progress:
            progress(min(done[0] / total, 1.0), text)

    os.makedirs(game_dir, exist_ok=True)
    if info["kind"] == "folder":
        src_root = os.path.abspath(info["root"])
        if os.path.realpath(src_root) == os.path.realpath(game_dir):
            return info                                   # already in place
        for dp, dn, fn in os.walk(src_root):
            rel = os.path.relpath(dp, src_root)
            os.makedirs(os.path.join(game_dir, rel) if rel != "." else game_dir, exist_ok=True)
            for n in sorted(fn):
                s = os.path.join(dp, n)
                d = os.path.join(game_dir, rel, n) if rel != "." else os.path.join(game_dir, n)
                size = os.path.getsize(s)
                if os.path.isfile(d) and os.path.getsize(d) == size:
                    tick(size)
                    continue
                shutil.copyfile(s, d + ".part")
                os.replace(d + ".part", d)
                tick(size, n)
    else:
        with xdvdfs.Image(source) as img:
            for e in img.walk():
                d = _safe_join(game_dir, e.path)
                os.makedirs(os.path.dirname(d), exist_ok=True)
                if os.path.isfile(d) and os.path.getsize(d) == e.size:
                    tick(e.size)
                    continue
                img.copy_to(e, d, progress=lambda n, t=e.path: tick(n, t))
            # empty directories the disc has (the port may create them itself,
            # but a faithful tree costs nothing)
            for e in _dirs(img, ""):
                os.makedirs(_safe_join(game_dir, e), exist_ok=True)
    return info


def _dirs(img, prefix):
    for e in img.listdir(prefix):
        if e.is_dir:
            yield e.path
            yield from _dirs(img, e.path)


def verify_installed(game_dir, builds=None):
    """The supported build whose default.xbe sits in game_dir, or DiscError."""
    p = os.path.join(game_dir, "default.xbe")
    if not os.path.isfile(p):
        raise DiscError("no-xbe", "%s is missing" % p)
    with open(p, "rb") as f:
        return check_xbe(f.read(), builds)
