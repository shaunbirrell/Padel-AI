"""claude-bud JOB 33: rebirth pacing over several lives (the owner: "the first rebirth ~30-45 min of normal play, later ones
longer"). Builds on tools/progression_sim.py (the real BaseConfig costs, EconomyConfig / BalanceConfig income, XP
curve, build XP, IncomeXP) and adds what changes from one life to the next, read from the real configs:
  * the cash multiplier 1 + 0.10 x rebirths (EconomyConfig.PrestigeCashMultiplierPerLevel) on the income you SPEND;
  * IncomeXP is paid on the pre-multiplier income, as BaseService does;
  * the starting cash steps (RebirthConfig.Perks.StartingCashSteps; the flat 10,000 with perks off);
  * the rebirth zones' income once reached, assumed built to level 1 at the life's start (RebirthZonesConfig);
  * the level needed (PrestigeConfig.MinLevelFor: MinLevelToPrestige + MinLevelPerPrestige x p, at most MinLevelMax).
Every life rebuilds the base from nothing (the free rebirth path).
Usage: python tools/sim/rebirth_pacing_sim.py [--lives N] [--play-xp N] [--pacing on|off] [--perks on|off] [--json]
A model, not the game: no combat, raids, businesses, soldiers' income, oil, or other multipliers."""
import argparse
import json
import math
import re
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE.parent))
import progression_sim as ps  # noqa: E402

CFG = ps.CFG


def read(n):
    return (CFG / n).read_text(encoding="utf-8")


def cfg():
    rc = read("RebirthConfig.luau")
    steps = [(int(a), float(c)) for a, c in re.findall(r"\{ AtPrestige = (\d+), Cash = ([\d_]+) \}", rc.replace("_", ""))]
    pc = read("PrestigeConfig.luau")
    ec = read("EconomyConfig.luau")
    zc = read("RebirthZonesConfig.luau")
    zones = {}
    for zid, body in re.findall(r"\n\t\t(\w+) = \{ Name = \"[^\"]+\",(.*?)\},\n", zc):
        inc = re.search(r"IncomePerTick = \{ ([\d, ]+) \}", body)
        zones[zid] = float(inc.group(1).split(",")[0]) if inc else 0.0
    tiers = {zid: int(t) for zid, t in re.findall(r"(\w+) = \{ Id = \"\w+\", Tier = (\d+)", rc)}
    for zid, t in re.findall(r"(\w+) = \{\n\t\t\tId = \"\w+\",\n\t\t\tTier = (\d+)", rc):
        tiers[zid] = int(t)
    return {
        "Steps": sorted(steps),
        "MinBase": int(ps.num(pc, "MinLevelToPrestige", 40)),
        "MinPer": ps.num(pc, "MinLevelPerPrestige", 0) or 0,
        "MinMax": int(ps.num(pc, "MinLevelMax", 40) or 40),
        "Mult": ps.num(ec, "PrestigeCashMultiplierPerLevel", 0.10),
        "StartFlat": ps.num(ec, "StartingCash", 10000),
        "ZoneIncome": zones,
        "ZoneTier": tiers,
    }


def start_cash(c, p, perks):
    if not perks or p <= 0:
        return c["StartFlat"]
    best = c["StartFlat"]
    for at, cash in c["Steps"]:
        if p >= at:
            best = cash
    return best


def min_level(c, p, pacing):
    if not pacing:
        return c["MinBase"]
    return min(c["MinMax"], int(c["MinBase"] + c["MinPer"] * p))


def life(c, p, play_xp, pacing, perks, max_minutes=600):
    st = ps.structures()
    rate, base_tick, tick_s = ps.rates()
    bal = ps.balance()
    payback = bal.get("Payback")

    def level_income(sid, level):
        if payback:
            return sum(st[sid]["Costs"][i] / (payback[min(i, len(payback) - 1)] * 60 / tick_s) for i in range(level))
        return rate.get(sid, 0) * level

    mult = 1 + c["Mult"] * p
    zone_flat = sum(inc for zid, inc in c["ZoneIncome"].items() if c["ZoneTier"].get(zid, 99) <= p)
    need = min_level(c, p, pacing)
    cash = start_cash(c, p, perks)
    lv = {k: 0 for k in st}
    level, xp, t = 1, 0.0, 0.0
    while t < max_minutes * 60:
        while True:
            cands = [(d["Costs"][lv[s]], s) for s, d in st.items() if lv[s] < d["Max"] and not any(lv.get(r, 0) < n for r, n in d["Req"])]
            if not cands:
                break
            price, sid = min(cands)
            if price > cash:
                break
            cash -= price
            lv[sid] += 1
            xp += ps.build_xp(price)
        income = base_tick + zone_flat + sum(level_income(s, l) for s, l in lv.items())
        cash += income * mult
        xp += play_xp * tick_s / 60 + income / 1000 * bal.get("IncomeXPPer1000", 0)
        while xp >= ps.xp_to_next(level) and level < 100:
            xp -= ps.xp_to_next(level)
            level += 1
        if level >= need:
            return round(t / 60, 1), need
        t += tick_s
    return None, need


def run(lives=8, play_xp=30.0, pacing=True, perks=True):
    c = cfg()
    rows = []
    for p in range(lives):
        mins, need = life(c, p, play_xp, pacing, perks)
        rows.append({"Life": p + 1, "RebirthsBefore": p, "LevelNeeded": need, "Minutes": mins, "StartCash": int(start_cash(c, p, perks))})
    return rows


if __name__ == "__main__":
    ap = argparse.ArgumentParser()
    ap.add_argument("--lives", type=int, default=8)
    ap.add_argument("--play-xp", type=float, default=30.0)
    ap.add_argument("--pacing", choices=("on", "off"), default="on")
    ap.add_argument("--perks", choices=("on", "off"), default="on")
    ap.add_argument("--json", action="store_true")
    a = ap.parse_args()
    rows = run(a.lives, a.play_xp, a.pacing == "on", a.perks == "on")
    if a.json:
        print(json.dumps(rows))
    else:
        print("| Life | Rebirths before | Level needed | Start cash | Minutes to rebirth |")
        print("|---|---|---|---|---|")
        for r in rows:
            print("| %d | %d | %d | $%s | %s |" % (r["Life"], r["RebirthsBefore"], r["LevelNeeded"], f"{r['StartCash']:,}", r["Minutes"]))
