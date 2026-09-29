"""claude-bud JOB 24 §8: before / after model of the phone LOW-quality culling (Client/Modules/QualityGovernor) during a
fast drive. The governor runs on the client only, so this re-plays its rule (v116 vs JOB 24) on a straight drive past a
row of clusters 25 studs off the road, every 30 studs, half of them Tier 2, a third of them buildings ("block").
Reports, per speed, how close to the car a cluster first appears ahead ("pop-in distance": lower = worse) and how many
buildings are ever missing within 150 studs of the car. Numbers from QualityConfig. Run: python tools/sim/quality_cull_model.py"""
import math
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]


def cfg():
    t = (ROOT / "src/ReplicatedStorage/Shared/Configs/QualityConfig.luau").read_text(encoding="utf-8")

    def n(k, d):
        m = re.search(r"\b" + k + r" = (-?[\d.]+)", t)
        return float(m.group(1)) if m else d
    return {"t2": n("HideTier2BeyondStuds", 180), "any": n("HideAnyBeyondStuds", 420), "hz": n("CheckHz", 1),
            "look": n("LookAheadSeconds", 0), "fast": n("FastStuds", 1e9), "fastHz": n("FastHz", 1), "slack": n("ShowSlackStuds", 0),
            "never": set(re.findall(r'"(\w+)"', t[t.find("NeverHideKinds"):t.find("}", t.find("NeverHideKinds"))]))}


def drive(c, speed, new):
    clusters = []
    for i in range(80):
        kind = "block" if i % 3 == 0 else "rubble"
        clusters.append({"x": 400 + i * 30, "z": 25 if i % 2 else -25, "tier": 2 if i % 2 else 1, "kind": kind, "hidden": True, "seen": False})
    dt, t, x = 1 / 60, 0.0, 0.0
    next_check = 0.0
    pop, missing = [], 0
    last = None
    while x < 400 + 80 * 30:
        x += speed * dt
        t += dt
        if t >= next_check:
            vel = speed if last is not None else 0.0
            last = x
            ahead = x + (vel * c["look"] if new else 0)
            for cl in clusters:
                if new and cl["kind"] in c["never"]:
                    cl["hidden"] = False
                    continue
                d = min(math.hypot(cl["x"] - x, cl["z"]), math.hypot(cl["x"] - ahead, cl["z"]) if new else 1e9)
                extra = 0 if cl["hidden"] or not new else c["slack"]
                cl["hidden"] = (cl["tier"] >= 2 and d > c["t2"] + extra) or d > c["any"] + extra
            hz = c["fastHz"] if new and speed > c["fast"] else c["hz"]
            next_check = t + 1 / hz
        for cl in clusters:
            d = math.hypot(cl["x"] - x, cl["z"])
            if not cl["hidden"] and not cl["seen"] and cl["x"] > x:
                cl["seen"] = True
                pop.append(d)
            if cl["kind"] == "block" and cl["hidden"] and d <= 150:
                missing += 1
    return min(pop) if pop else float("nan"), missing * dt


if __name__ == "__main__":
    c = cfg()
    print("| Speed (studs/s) | Closest pop-in ahead, v116 | Closest pop-in ahead, JOB 24 | Building-seconds missing within 150 studs, v116 | JOB 24 |")
    print("|---|---|---|---|---|")
    for v in (16, 60, 100, 140):
        a = drive(c, v, False)
        b = drive(c, v, True)
        print(f"| {v} | {a[0]:.0f} studs | {b[0]:.0f} studs | {a[1]:.1f} | {b[1]:.1f} |")
