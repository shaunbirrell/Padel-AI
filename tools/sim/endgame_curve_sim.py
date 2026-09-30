#!/usr/bin/env python3
"""JOB 39 DRAFT (analysis only): the WAR EMPIRE cash curve per rebirth stage vs income, read from the real configs.

What it adds up (all Cash, no Robux):
  PER LIFE (reset on the free rebirth): 15 base structures x5 (BaseConfig) + 4 war businesses x5 (BusinessConfig)
  ONE-TIME (kept through rebirth): the 7 rebirth zones x3 (RebirthZonesConfig, only once reached), research incl. the
  Personal Armour track (ResearchConfig), cash vehicles (VehicleConfig CostCash, rebirth-gated rows only once reached),
  cash guns (WeaponConfig CostCash), soldiers (SoldierConfig.RecruitCostCash x cap).
Income per second at max (pre-multiplier $/tick / 5): BaseCashPerTick + BalanceConfig payback curve for the 15
structures + business IncomePerTick[5] + rebirth zone IncomePerTick[3] + soldiers x CashPerSoldierPerTick + plot oil.
Multipliers: (1 + 0.10 x rebirths) x Empire Tax (home 5 %, +10 % per outpost, cap 50 %) x passes (VIP +25 %, 2x Cash).
Usage: python3 tools/sim/endgame_curve_sim.py [--json]
A model, not the game: no combat pay, missions, stipends, drops, events, codes or ATM raids."""
import json
import re
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent))
import progression_sim as ps  # noqa: E402

CFG = ps.CFG
T = 5.0


def read(n):
    return (CFG / n).read_text(encoding="utf-8")


def businesses():
    t = read("BusinessConfig.luau")
    out = {}
    for m in re.finditer(r"\n\t\t(\w+) = \{\n\t\t\tId = \"\w+\",(.*?)\n\t\t\},", t, re.S):
        body = m.group(2)
        c = re.search(r"Costs = \{ ([\d, ]+) \}", body)
        i = re.search(r"IncomePerTick = \{ ([\d, ]+) \}", body)
        if c and i:
            out[m.group(1)] = ([float(x) for x in c.group(1).split(",")], [float(x) for x in i.group(1).split(",")])
    return out


def zones():
    t = read("RebirthZonesConfig.luau")
    rc = read("RebirthConfig.luau")
    tiers = {z: int(n) for z, n in re.findall(r"(\w+) = \{ Id = \"\w+\", Tier = (\d+)", rc)}
    tiers.update({z: int(n) for z, n in re.findall(r"(\w+) = \{\n\t\t\tId = \"\w+\",\n\t\t\tTier = (\d+)", rc)})
    out = {}
    for zid, name, body in re.findall(r"\n\t\t(\w+) = \{ Name = \"([^\"]+)\",(.*?)\},\n", t):
        cost = [float(x) for x in re.search(r"Cost = \{ ([\d, ]+) \}", body).group(1).split(",")]
        inc = re.search(r"IncomePerTick = \{ ([\d, ]+) \}", body)
        out[zid] = {"Name": name, "Tier": tiers.get(zid, 99), "Cost": cost, "Inc": [float(x) for x in inc.group(1).split(",")] if inc else [0, 0, 0]}
    return out


def research():
    t = read("ResearchConfig.luau")
    total, rows = 0.0, []
    for m in re.finditer(r"Id = \"(\w+)\",.*?Costs = \{ ([\d, ]+) \}", t, re.S):
        c = sum(float(x) for x in m.group(2).split(","))
        rows.append((m.group(1), c))
        total += c
    return total, rows


def vehicles():
    t = read("VehicleConfig.luau")
    rows = []
    # V("Id", "Name", "Cat", "Rarity", level, hp, speed, seats, armor, cost, "Kit", { ... Prestige = n ... })
    for m in re.finditer(r"V\(\s*\"(\w+)\",\s*\"([^\"]+)\",\s*\"(\w+)\",\s*\"(\w+)\",\s*(\d+),\s*(\d+),\s*(\d+),\s*(\d+),\s*(\d+),\s*(\d+),\s*\"\w+\"(.*?)\)\s*,?\n", t, re.S):
        cost = int(m.group(10))
        if cost <= 0 or m.group(4) == "Premium":
            continue
        pm = re.search(r"Prestige = (\d+)", m.group(11) or "")
        rows.append({"Id": m.group(1), "Name": m.group(2), "Cost": cost, "Prestige": int(pm.group(1)) if pm else 0})
    return rows


def guns():
    t = read("WeaponConfig.luau")
    return [float(x) for x in re.findall(r"CostCash = (\d+)", t) if float(x) > 0]


def structure_income_per_tick(st, payback):
    return sum(d["Costs"][i] / (payback[min(i, len(payback) - 1)] * 60 / T) for d in st.values() for i in range(d["Max"]))


def model():
    st = ps.structures()
    bal = ps.balance()
    payback = bal["Payback"]
    _, base_tick, _ = ps.rates()
    biz = businesses()
    zn = zones()
    res_total, res_rows = research()
    veh = vehicles()
    gun = guns()
    base_cost = sum(sum(d["Costs"]) for d in st.values())
    biz_cost = sum(sum(c) for c, _ in biz.values())
    per_life = base_cost + biz_cost
    base_inc_tick = base_tick + structure_income_per_tick(st, payback) + sum(i[-1] for _, i in biz.values())
    oil_tick = 2 * 18
    soldier_cap_base = 50 + 5 * 5  # MaxSoldiersBase + Barracks L5
    out = {"PerLifeCost": per_life, "BaseCost": base_cost, "BizCost": biz_cost, "ResearchCost": res_total,
           "GunCost": sum(gun), "Stages": []}
    for p in (0, 1, 2, 3, 5, 8, 10, 15, 20):
        zones_open = [z for z in zn.values() if z["Tier"] <= p]
        zone_cost = sum(sum(z["Cost"]) for z in zones_open)
        zone_tick = sum(z["Inc"][-1] for z in zones_open)
        elite = 15 if any(z["Name"] == "Elite Barracks" for z in zones_open) else 0
        cap = soldier_cap_base + min(40, 2 * p) + elite  # SoldierService.maxSoldiers (no Army Expansion)
        soldier_tick = cap * 8
        veh_cost = sum(v["Cost"] for v in veh if v["Prestige"] <= p)
        pre_tick = base_inc_tick + zone_tick + soldier_tick  # multiplied reasons
        pre_s = pre_tick / T
        mults = {
            "none": (1 + 0.1 * p) * 1.05,
            "VIP+2x": (1 + 0.1 * p) * 1.05 * 1.25 * 2,
        }
        one_time = zone_cost + res_total + veh_cost + sum(gun) + cap * 500
        stage = {"Rebirths": p, "PerLifeCost": per_life, "ZonesOneTime": zone_cost, "VehiclesOneTime": veh_cost,
                 "OneTimeTotal": one_time, "SoldierCap": cap, "PreMultPerSec": round(pre_s, 1),
                 "OilPerSec": oil_tick / T}
        for k, m in mults.items():
            ips = pre_s * m + oil_tick / T
            stage["IncomePerSec_" + k] = round(ips, 0)
        out["Stages"].append(stage)
    out["Vehicles"] = sorted(veh, key=lambda v: -v["Cost"])[:6]
    out["Zones"] = zn
    top = [("Structure " + sid + " L5", d["Costs"][-1]) for sid, d in st.items()]
    top += [("Business " + b + " L5", c[-1]) for b, (c, _) in biz.items()]
    top += [("Zone " + z["Name"] + " L3", z["Cost"][-1]) for z in zn.values()]
    top += [("Research " + r, 0) for r, _ in res_rows[:0]]
    top += [("Vehicle " + v["Name"], v["Cost"]) for v in veh]
    out["TopItems"] = sorted(top, key=lambda x: -x[1])[:10]
    return out


if __name__ == "__main__":
    m = model()
    if "--json" in sys.argv:
        print(json.dumps(m, indent=1, default=str))
        sys.exit(0)
    print("Per-life (base+businesses) cost: $%s  (base $%s, businesses $%s)" % (f"{m['PerLifeCost']:,.0f}", f"{m['BaseCost']:,.0f}", f"{m['BizCost']:,.0f}"))
    print("Research (one-time, kept): $%s   cash guns: $%s" % (f"{m['ResearchCost']:,.0f}", f"{m['GunCost']:,.0f}"))
    print("| R | per-life $ | one-time $ (zones+research+vehicles+guns+soldiers) | cap | pre-mult $/s | $/s no pass | $/s VIP+2x |")
    for s in m["Stages"]:
        print("| %d | %s | %s | %d | %s | %s | %s |" % (s["Rebirths"], f"{s['PerLifeCost']:,.0f}", f"{s['OneTimeTotal']:,.0f}", s["SoldierCap"], f"{s['PreMultPerSec']:,.0f}", f"{s['IncomePerSec_none']:,.0f}", f"{s['IncomePerSec_VIP+2x']:,.0f}"))
    print("Top cash items:")
    for n, c in m["TopItems"]:
        print("  %-40s $%s" % (n, f"{c:,.0f}"))


def time_to_max(p, pass_mult=1.0, start_cash=None, soldiers_owned=None, max_minutes=600, cost_scale=1.0):
    """Minutes from a fresh life at `p` rebirths to: every structure + business L5 and every zone open at `p` that was
    not open at p-1 (zones reached earlier are kept) at L3. Greedy cheapest-first (the game's PickCheapest)."""
    st = ps.structures()
    payback = ps.balance()["Payback"]
    _, base_tick, _ = ps.rates()
    items = {sid: {"Costs": d["Costs"], "Req": d["Req"], "Inc": [sum(d["Costs"][i] / (payback[min(i, len(payback) - 1)] * 12) for i in range(k + 1)) for k in range(d["Max"])]} for sid, d in st.items()}
    bt = read("BusinessConfig.luau")
    for bid, (c, inc) in businesses().items():
        blk = bt[bt.index("\t\t" + bid + " = {"):]
        blk = blk[: blk.index("\n\t\t},")]
        req = [(r, int(lv)) for r, lv in re.findall(r'StructureId = "(\w+)", Level = (\d+)', blk)]
        items[bid] = {"Costs": c, "Req": req, "Inc": inc}
    if cost_scale != 1.0:  # claude-bud JOB 39: the rebirth price scale (structures + businesses; zones never; income unchanged)
        for d in items.values():
            d["Costs"] = [int(c * cost_scale + 0.5) for c in d["Costs"]]
    zn = zones()
    owned_zone_tick = 0.0
    for zid, z in zn.items():
        if z["Tier"] < p:
            owned_zone_tick += z["Inc"][-1]  # built in an earlier life, kept
        elif z["Tier"] == p:
            items["Z_" + zid] = {"Costs": z["Cost"], "Req": [], "Inc": z["Inc"]}
    lv = {k: 0 for k in items}
    mult = (1 + 0.1 * p) * 1.05 * pass_mult
    cash = start_cash if start_cash is not None else (10000 if p == 0 else {1: 25000, 2: 35000, 3: 50000, 4: 65000, 5: 80000}.get(p, 100000))
    soldiers = soldiers_owned if soldiers_owned is not None else (5 if p == 0 else 75 + min(40, 2 * p))
    t = 0.0
    while t < max_minutes * 60:
        while True:
            cands = []
            for k, d in items.items():
                if lv[k] < len(d["Costs"]) and all(lv.get(r, 0) >= n for r, n in d["Req"]):
                    cands.append((d["Costs"][lv[k]], k))
            cap = 50 + 5 * lv.get("Barracks", 0) + min(40, 2 * p)
            if soldiers < cap:
                cands.append((500, "_soldier"))
            if not cands:
                return round(t / 60, 1)
            price, k = min(cands)
            if price > cash:
                break
            cash -= price
            if k == "_soldier":
                soldiers += 1
            else:
                lv[k] += 1
        inc = base_tick + owned_zone_tick + soldiers * 8
        for k, d in items.items():
            if lv[k] > 0:
                inc += d["Inc"][lv[k] - 1]
        cash += inc * mult + (36 if lv.get("DefensiveWalls", 0) >= 2 else 0)
        t += T
    return None


if __name__ == "__main__" and "--time" in sys.argv:
    print("| R | minutes to max (no passes) | minutes to max (VIP + 2x Cash) |")
    for p in (0, 1, 2, 3, 4, 5, 6, 8, 10, 20):
        print("| %d | %s | %s |" % (p, time_to_max(p), time_to_max(p, 2.5)))
