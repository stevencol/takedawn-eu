#!/usr/bin/env python3
"""android_power.py <sample.txt> [<log> [<flips.txt>]] - summarise android_sample.sh.

    tools/perf/android_power.py runs/a34-base/sample.txt runs/a34-base/log.txt runs/a34-base/flips.txt

What a phone without root shows, as one summary per run (means over the
samples; the first second is the baseline):

  busy GHz   per cpufreq policy, the cores' busy share times the policy's
             mean clock (time_in_state): the CPU work in cycles, the
             nearest an unrooted shell gets to its power
  clocks     each policy's mean clock, MHz
  game CPU   the game process, in cores (1.00 = one core all the time)
  temps      the hottest CPU, GPU and skin zones and the battery, mean and
             last, degrees C
  battery    watts drawn, where the kernel lets the shell read it (unplugged)
  threads    the game's busiest threads, cores each
  fps        from the log's "[GPU] flip N T ms" lines (RECOMP_FLIP_MARK, on in
             every scene) between the two flips of flips.txt: the rate, the
             flip interval's p50/p95/p99 and the share over 20 ms

--json prints the same as one JSON object (android_race_power.sh keeps it
beside the run for a later comparison).
"""
import json
import re
import sys


def parse(path):
    hz = 100
    policies = {}
    samples = []
    th = {"th0": {}, "th1": {}}
    cur = None
    for line in open(path, errors="replace"):
        p = line.split()
        if not p:
            continue
        k = p[0]
        if k == "hz":
            hz = int(p[1])
        elif k == "policy":
            policies[p[1]] = [int(c) for c in p[2:]]
        elif k == "t":
            cur = {"t": int(p[1]) / 1000.0, "c": {}, "f": {}, "z": {}, "p": None, "b": None}
            samples.append(cur)
        elif k == "c" and cur is not None:
            cur["c"][int(p[1][3:])] = [int(x) for x in p[2:9]]
        elif k == "f" and cur is not None:
            cur["f"][p[1]] = {int(a): int(b) for a, b in (x.split(":") for x in p[2:] if ":" in x)}
        elif k == "z" and cur is not None and len(p) >= 3:
            try:
                v = int(p[-1])
            except ValueError:
                continue
            cur["z"].setdefault(" ".join(p[1:-1]), v)
        elif k == "p" and cur is not None and len(p) > 1:
            cur["p"] = int(p[1])
        elif k == "b" and cur is not None and len(p) > 2:
            cur["b"] = (int(p[1]), int(p[2]))
        elif k in th and len(p) >= 3:
            try:
                th[k][p[1]] = th[k].get(p[1], 0) + int(p[2])
            except ValueError:
                pass
    return hz, policies, samples, th


def deg(v):
    return v / 1000.0 if abs(v) > 200 else float(v)


def group(name):
    n = name.lower()
    if "gpu" in n:
        return "gpu"
    if "skin" in n or "quiet" in n:
        return "skin"
    if "bat" in n:
        return "battery"
    if "cpu" in n or n in ("ap", "soc") or n.startswith("cpuss"):
        return "cpu"
    return None


def summary(path, log=None, flips=None):
    hz, policies, s, th = parse(path)
    if len(s) < 3:
        raise SystemExit("%s: fewer than 3 samples" % path)
    a, b = s[0], s[-1]
    secs = b["t"] - a["t"]
    out = {"seconds": round(secs, 1), "policies": {}}
    total_ghz = 0.0
    for pol, cpus in sorted(policies.items()):
        fa, fb = a["f"].get(pol, {}), b["f"].get(pol, {})
        dt = {f: fb.get(f, 0) - fa.get(f, 0) for f in fb}
        tot = sum(v for v in dt.values() if v > 0)
        mhz = sum(f * v for f, v in dt.items() if v > 0) / tot / 1000.0 if tot else 0.0
        busy = 0.0
        for c in cpus:
            ca, cb = a["c"].get(c), b["c"].get(c)
            if not ca or not cb:
                continue
            d = [y - x for x, y in zip(ca, cb)]
            all_ = sum(d)
            idle = d[3] + d[4]
            busy += (all_ - idle) / all_ if all_ else 0.0
        ghz = busy * mhz / 1000.0
        total_ghz += ghz
        out["policies"][pol] = {"cpus": len(cpus), "busy_cores": round(busy, 2),
                                "mhz": round(mhz), "busy_ghz": round(ghz, 2)}
    out["busy_ghz"] = round(total_ghz, 2)
    if a["p"] is not None and b["p"] is not None:
        out["game_cores"] = round((b["p"] - a["p"]) / hz / secs, 2)
    temps = {}
    for smp in s:
        g = {}
        for name, v in smp["z"].items():
            k = group(name)
            if k:
                g[k] = max(g.get(k, -1e9), deg(v))
        for k, v in g.items():
            temps.setdefault(k, []).append(v)
    out["temps"] = {k: {"mean": round(sum(v) / len(v), 1), "max": round(max(v), 1),
                        "last": round(v[-1], 1)} for k, v in sorted(temps.items())}
    bw = [abs(x["b"][0]) * x["b"][1] for x in s if x["b"]]
    if bw:
        # current_now is uA or mA by vendor, voltage_now uV or mV: scaled to W
        # by magnitude.
        w = sum(bw) / len(bw)
        while w > 100:
            w /= 1000.0
        out["battery_w"] = round(w, 2)
    if th["th0"] and th["th1"]:
        d = {n: (th["th1"].get(n, 0) - th["th0"].get(n, 0)) / hz / secs for n in th["th1"]}
        out["threads"] = {n: round(v, 2) for n, v in sorted(d.items(), key=lambda x: -x[1])[:10] if v >= 0.02}
    if log:
        lo, hi = 0, 1 << 62
        if flips:
            lo, hi = (int(x) for x in open(flips).read().split()[:2])
        t = []
        for l in open(log, errors="replace"):
            m = re.search(r"\[GPU\] flip (\d+) ([\d.]+) ms", l)
            if m and lo <= int(m.group(1)) <= hi:
                t.append(float(m.group(2)))
        iv = sorted(y - x for x, y in zip(t, t[1:]) if y > x)
        if iv:
            out["fps"] = round(len(iv) / ((t[-1] - t[0]) / 1000.0), 1)
            out["frame_p50_ms"] = round(iv[len(iv) // 2], 2)
            out["frame_p95_ms"] = round(iv[int(len(iv) * 0.95)], 2)
            out["frame_p99_ms"] = round(iv[int(len(iv) * 0.99)], 2)
            out["slow_pct"] = round(100.0 * sum(1 for v in iv if v > 20.0) / len(iv), 1)
    return out


def show(o):
    print("%.0f s  busy %.2f GHz  game %.2f cores" % (o["seconds"], o["busy_ghz"], o.get("game_cores", float("nan"))))
    for pol, v in o["policies"].items():
        print("  %-8s %d cpus  %.2f busy  %5d MHz  %.2f GHz" % (pol, v["cpus"], v["busy_cores"], v["mhz"], v["busy_ghz"]))
    for k, v in o["temps"].items():
        print("  %-8s mean %.1f  max %.1f  last %.1f C" % (k, v["mean"], v["max"], v["last"]))
    if "battery_w" in o:
        print("  battery  %.2f W" % o["battery_w"])
    if "fps" in o:
        print("  fps      %.1f  frame p50 %.2f  p95 %.2f  p99 %.2f ms  over 20 ms %.1f%%"
              % (o["fps"], o["frame_p50_ms"], o["frame_p95_ms"], o["frame_p99_ms"], o["slow_pct"]))
    for n, v in o.get("threads", {}).items():
        print("    %-16s %.2f" % (n, v))


if __name__ == "__main__":
    args = [x for x in sys.argv[1:] if x != "--json"]
    if not args:
        raise SystemExit(__doc__)
    o = summary(args[0], args[1] if len(args) > 1 else None, args[2] if len(args) > 2 else None)
    if "--json" in sys.argv:
        print(json.dumps(o))
    else:
        show(o)
