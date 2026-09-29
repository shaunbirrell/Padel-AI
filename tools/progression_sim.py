#!/usr/bin/env python3
"""claude-bud JOB 10 (2026-09-29): progression simulator for the first life (start -> first rebirth).

Reads the real configs (BaseConfig structure costs / requirements, EconomyConfig passive income, XPBalanceConfig build
XP, LevelConfig curve, PrestigeConfig first-rebirth level, BalanceConfig when present) and simulates a player who:
  * collects passive income every tick (ATM / auto collect),
  * always buys the cheapest affordable base upgrade whose requirements are met (the game's PickCheapest),
  * earns build XP per purchase, plus "play XP" per minute (kills / missions / captures; PlayXPPerMinute),
  * and, with BalanceConfig.IncomeXP on, XP per $ of passive income collected.
It prints the minute the base is complete, the level over time and the minute the first-rebirth level is reached.
Usage: python tools/progression_sim.py [--play-xp N] [--minutes M] [--json]
It is a model, not the game: no combat, raids, businesses, oil, soldiers' training income or multipliers.
"""
import argparse
import json
import math
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
CFG = ROOT / "src/ReplicatedStorage/Shared/Configs"


def read(name):
    return (CFG / name).read_text(encoding="utf-8")


def num(text, key, default=None):
    m = re.search(r"\b" + key + r"\s*=\s*(-?[\d.]+)", text)
    return float(m.group(1)) if m else default


def structures():
    t = read("BaseConfig.luau")
    out = {}
    for m in re.finditer(r"\n\t\t(\w+) = \{\n\t\t\tId = \"\w+\",(.*?)\n\t\t\},", t, re.S):
        sid, body = m.group(1), m.group(2)
        cm = re.search(r"Costs = costs\(([^)]*)\)", body)
        if not cm:
            continue
        costs = [float(x) for x in cm.group(1).split(",")]
        req = [(r, int(lv)) for r, lv in re.findall(r'StructureId = "(\w+)", Level = (\d+)', body)]
        out[sid] = {"Costs": costs, "Max": int(num(body, "MaxLevel", len(costs))), "Req": req}
    return out


def rates():
    t = read("EconomyConfig.luau")
    blk = t[t.index("PerLevelRates = {"):t.index("}", t.index("PerLevelRates = {"))]
    return {k: float(v) for k, v in re.findall(r"(\w+) = ([\d.]+)", blk)}, num(t, "BaseCashPerTick", 25), num(t, "TickSeconds", 5)


def build_xp(price):
    t = read("XPBalanceConfig.luau")
    a, p, cap = num(t, "A", 0.8), num(t, "P", 0.5), num(t, "Cap", 1000)
    return min(cap, math.floor(a * price ** p))


def xp_to_next(level):
    t = read("LevelConfig.luau")
    en = "CurveV2 = { Enabled = true" in t
    scale, knee, ramp = num(t, "Scale", 0.65), num(t, "Knee", 21), num(t, "RampEnd", 30)
    mult = 1.0
    if en and level < ramp:
        mult = scale if level <= knee else scale + (1 - scale) * (level - knee) / (ramp - knee)
    return math.floor(100 * level ** 1.45 * mult)


def balance():
    """BalanceConfig numbers (empty dict when the file is missing)."""
    p = CFG / "BalanceConfig.luau"
    if not p.exists():
        return {}
    t = p.read_text(encoding="utf-8")
    pb = re.search(r"PaybackMinutes = \{([^}]*)\}", t)
    ix = re.search(r"IncomeXP = \{(.*?)\n\t\}", t, re.S)
    first = re.search(r"FirstRebirthMinutes = \{ Min = ([\d.]+), Max = ([\d.]+) \}", t)
    return {
        "Payback": [float(x) for x in pb.group(1).split(",")] if pb else None,
        "IncomeXPPer1000": (num(ix.group(1), "Per1000", 0) if ix and "Enabled = true" in ix.group(1) else 0),
        "FirstRebirthMinutes": (float(first.group(1)), float(first.group(2))) if first else None,
        "PremiumVehicleMaxEdge": num(t, "PremiumVehicleMaxEdge", None),
    }


def simulate(play_xp_per_min=30.0, minutes=180, curve="balance"):
    st = structures()
    rate, base_tick, tick_s = rates()
    bal = balance() if curve == "balance" else {}
    payback = bal.get("Payback")

    def level_income(sid, level):
        if payback:
            return sum(st[sid]["Costs"][i] / (payback[min(i, len(payback) - 1)] * 60 / tick_s) for i in range(level))
        return rate.get(sid, 0) * level

    first_rebirth = int(num(read("PrestigeConfig.luau"), "MinLevelToPrestige", 40))
    cash = num(read("EconomyConfig.luau"), "StartingCash", 10000)
    lv = {k: 0 for k in st}
    level, xp = 1, 0.0
    t = 0.0
    log, done_at, rebirth_at, dead = [], None, None, []
    while t < minutes * 60:
        # buy greedily
        while True:
            cands = []
            for sid, d in st.items():
                if lv[sid] >= d["Max"]:
                    continue
                if any(lv.get(r, 0) < need for r, need in d["Req"]):
                    continue
                cands.append((d["Costs"][lv[sid]], sid))
            if not cands:
                if done_at is None:
                    done_at = t
                break
            price, sid = min(cands)
            if price > cash:
                break
            gain = level_income(sid, lv[sid] + 1) - level_income(sid, lv[sid])
            pay_s = price / max(gain / tick_s, 1e-9)
            if gain <= 0:
                dead.append((sid, lv[sid] + 1, price))
            cash -= price
            lv[sid] += 1
            xp += build_xp(price)
            log.append((round(t / 60, 1), sid, lv[sid], int(price), round(pay_s / 60, 1)))
        income = base_tick + sum(level_income(s, l) for s, l in lv.items())
        cash += income
        xp += play_xp_per_min * tick_s / 60 + income / 1000 * bal.get("IncomeXPPer1000", 0)
        while xp >= xp_to_next(level):
            xp -= xp_to_next(level)
            level += 1
        if rebirth_at is None and level >= first_rebirth:
            rebirth_at = t
        t += tick_s
    return {"FirstRebirthLevel": first_rebirth, "BaseDoneMin": None if done_at is None else round(done_at / 60, 1),
            "RebirthMin": None if rebirth_at is None else round(rebirth_at / 60, 1), "LevelAtEnd": level,
            "Purchases": len(log), "DeadPurchases": dead, "Log": log,
            "IncomePerMinAtEnd": round((base_tick + sum(level_income(s, l) for s, l in lv.items())) * 60 / tick_s),
            "WorstPaybackMin": max((row[4] for row in log), default=0), "Curve": curve}


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--play-xp", type=float, default=30.0)
    ap.add_argument("--minutes", type=int, default=180)
    ap.add_argument("--json", action="store_true")
    ap.add_argument("--curve", choices=("balance", "old"), default="balance")
    a = ap.parse_args()
    r = simulate(a.play_xp, a.minutes, a.curve)
    if a.json:
        print(json.dumps({k: v for k, v in r.items() if k != "Log"}))
    else:
        for row in r["Log"]:
            print("t=%6.1f min  %-22s L%d  $%-8d payback %.1f min" % row)
        print({k: v for k, v in r.items() if k != "Log"})
