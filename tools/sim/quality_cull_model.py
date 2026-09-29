"""claude-bud JOB 24 §8 / JOB 27: replay of the phone LOW-quality culling rule (Client/Modules/QualityGovernor) on a city
route. The governor is client-only (no Luau-CLI Roblox), so this re-plays its three versions of the rule, exactly as
written, on a synthetic street:
  * "v116"  one cached PIVOT point, one threshold (hide > 180 Tier 2 / > 420 any), checked at 1 Hz, every cluster;
  * "j24"   JOB 24 §8: + NeverHideKinds (POI roles), 1.5 s look-ahead, 3 Hz when fast, 40-stud hysteresis;
  * "j27"   JOB 27: bounding-box distance, buildings by SIZE never culled (+ clusters on a building), load / unload
            buffer (Tier 2 220/320, any 480/640), one manager at 0.4 s (0.2 s fast).
The street: a straight road with city clusters on both sides every 30 studs: fill buildings (kit names, 20-60 studs
wide, some 300 studs long with the pivot at one end: the owner's "spans X 400-650, pivot at X 100"), rooftop props (small
clusters on top of a building), and small decoration (crates / lamps). Driven at 16 / 28 / 60 / 100 / 140 studs/s.
Reported per rule: seconds a BUILDING (or its rooftop props) was missing while within 200 studs of the car (the owner's
bug), and the closest distance at which small decoration popped in ahead. Numbers from QualityConfig.
Run: python tools/sim/quality_cull_model.py"""
import math
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]


def cfg():
    t = (ROOT / "src/ReplicatedStorage/Shared/Configs/QualityConfig.luau").read_text(encoding="utf-8")

    def n(k, d):
        m = re.search(r"\b" + k + r" = (-?[\d.]+)", t)
        return float(m.group(1)) if m else d
    return {k: n(k, d) for k, d in [("HideTier2BeyondStuds", 180), ("HideAnyBeyondStuds", 420), ("CheckHz", 1), ("LookAheadSeconds", 1.5),
                                     ("FastStuds", 30), ("FastHz", 3), ("ShowSlackStuds", 40), ("BuildingMinStuds", 14), ("BuildingMinHeight", 10),
                                     ("Tier2ShowStuds", 220), ("Tier2HideStuds", 320), ("AnyShowStuds", 480), ("AnyHideStuds", 640),
                                     ("CullSeconds", 0.4), ("FastCullSeconds", 0.2)]}


def street():
    out = []
    for i in range(70):
        x = 300 + i * 30
        side = 1 if i % 2 else -1
        if i % 3 == 0:  # a fill building (kind = kit name); every 4th one is a long block with the pivot at its far end
            long = i % 12 == 0
            w = 300 if long else 24
            mn = (x, 0, side * 22 if side > 0 else -22 - 18)
            mx = (x + w, 22, (side * 22 + 18) if side > 0 else -22)
            pivot = (x + w, 11, (mn[2] + mx[2]) / 2) if long else ((x + x + w) / 2, 11, (mn[2] + mx[2]) / 2)
            out.append({"kind": "Warehouse", "tier": 1, "min": mn, "max": mx, "pivot": pivot, "building": True})
            out.append({"kind": "RoofAC", "tier": 2, "min": (x + 4, 22, mn[2] + 4), "max": (x + 8, 25, mn[2] + 8), "pivot": (x + 6, 23, mn[2] + 6), "building": True, "roof": True})
        else:  # small decoration (crates / lamps)
            z = side * 16
            out.append({"kind": "Crates", "tier": 2 if i % 2 else 1, "min": (x, 0, z - 2), "max": (x + 4, 3, z + 2), "pivot": (x + 2, 1.5, z), "building": False})
    return out


def box_dist(p, mn, mx):
    d = [max(mn[k] - p[k], 0, p[k] - mx[k]) for k in range(3)]
    return math.sqrt(sum(v * v for v in d))


def pt_dist(p, q):
    return math.sqrt(sum((p[k] - q[k]) ** 2 for k in range(3)))


NEVER_J24 = {"block", "tower", "landmark", "square", "town", "fort", "checkpoint", "motorpool", "mast", "ruins", "camp", "hold", "Booth"}


def drive(c, speed, rule):
    cl = [dict(e, hidden=True, seen=False) for e in street()]
    for e in cl:
        size = [e["max"][k] - e["min"][k] for k in range(3)]
        e["big"] = max(size[0], size[2]) >= c["BuildingMinStuds"] or size[1] >= c["BuildingMinHeight"]
    dt, t, x = 1 / 60, 0.0, 0.0
    nxt, vel = 0.0, 0.0
    missing, pop = 0.0, []
    while x < 300 + 70 * 30 + 400:
        x += speed * dt
        t += dt
        cam = (x, 6, 0)
        if t >= nxt:
            vel = speed
            ahead = (x + vel * c["LookAheadSeconds"], 6, 0)
            for e in cl:
                if rule == "v116":
                    d = pt_dist(cam, e["pivot"])
                    e["hidden"] = (e["tier"] >= 2 and d > c["HideTier2BeyondStuds"]) or d > c["HideAnyBeyondStuds"]
                elif rule == "j24":
                    if e["kind"] in NEVER_J24:
                        e["hidden"] = False
                        continue
                    d = min(pt_dist(cam, e["pivot"]), pt_dist(ahead, e["pivot"]))
                    extra = 0 if e["hidden"] else c["ShowSlackStuds"]
                    e["hidden"] = (e["tier"] >= 2 and d > c["HideTier2BeyondStuds"] + extra) or d > c["HideAnyBeyondStuds"] + extra
                else:  # j27
                    if e["big"] or e.get("roof"):
                        e["hidden"] = False  # buildings and what stands on them: never culled
                        continue
                    d = min(box_dist(cam, e["min"], e["max"]), box_dist(ahead, e["min"], e["max"]))
                    show_at = c["Tier2ShowStuds"] if e["tier"] >= 2 else c["AnyShowStuds"]
                    hide_at = c["Tier2HideStuds"] if e["tier"] >= 2 else c["AnyHideStuds"]
                    if e["hidden"] and d < show_at:
                        e["hidden"] = False
                    elif not e["hidden"] and d > hide_at:
                        e["hidden"] = True
            if rule == "v116":
                nxt = t + 1 / c["CheckHz"]
            elif rule == "j24":
                nxt = t + (1 / c["FastHz"] if speed > c["FastStuds"] else 1 / c["CheckHz"])
            else:
                nxt = t + (c["FastCullSeconds"] if speed > c["FastStuds"] else c["CullSeconds"])
        for e in cl:
            d = box_dist(cam, e["min"], e["max"])
            if e["building"] and e["hidden"] and d <= 200:
                missing += dt
            if not e["building"] and not e["hidden"] and not e["seen"] and e["min"][0] > x:
                e["seen"] = True
                pop.append(d)
    return missing, (min(pop) if pop else float("nan"))


def table():
    c = cfg()
    rows = []
    for v in (16, 28, 60, 100, 140):
        rows.append((v, drive(c, v, "v116"), drive(c, v, "j24"), drive(c, v, "j27")))
    return rows


if __name__ == "__main__":
    print("| Speed (studs/s) | Building-seconds missing within 200 studs: v116 / JOB 24 §8 / JOB 27 | Closest decor pop-in ahead: v116 / JOB 24 / JOB 27 |")
    print("|---|---|---|")
    for v, a, b, cc in table():
        print(f"| {v} | {a[0]:.1f} / {b[0]:.1f} / {cc[0]:.1f} | {a[1]:.0f} / {b[1]:.0f} / {cc[1]:.0f} studs |")
