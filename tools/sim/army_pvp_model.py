"""claude-bud JOB 24 §2: time-to-kill / hit-rate model of an ATTACKING army vs players, guards and gates.

The combat services need the Roblox runtime, so this is a Monte Carlo MODEL built from the live config numbers
(OrdersConfig AttackDamage / AttackFireRate / AttackRange, CombatFairnessConfig unit hit chance, ArmyConfig.ArmyCombat
PlayerDamageMult / PlayerMaxDps / GuardDamageMult / GateDamageMult, CombatConfig.PlayerMaxHealth, RaidConfig guard HP,
GateDefenseConfig gate HP) and the rules SquadOrdersService.unitShootAt applies: one shot per soldier per 1 / fire rate,
the hit roll at the distance, the per-victim DPS cap for players. Escort figures are client-side and never shoot. The
hit model has no movement penalty (a moving player is hit like a standing one while in sight). Research multipliers = 1.
Run: python tools/sim/army_pvp_model.py"""
import random
import re
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
CFG = ROOT / "src/ReplicatedStorage/Shared/Configs"


def num(text, key, default):
    m = re.search(r"\b" + key + r"\s*=\s*(-?[\d.]+)", text)
    return float(m.group(1)) if m else default


def load():
    orders = (CFG / "OrdersConfig.luau").read_text(encoding="utf-8")
    fair = (CFG / "CombatFairnessConfig.luau").read_text(encoding="utf-8")
    army = (CFG / "ArmyConfig.luau").read_text(encoding="utf-8")
    ac = army[army.find("\tArmyCombat = {"):]
    ac = ac[:ac.find("\n\t},")]
    combat = (CFG / "CombatConfig.luau").read_text(encoding="utf-8")
    raid = (CFG / "RaidConfig.luau").read_text(encoding="utf-8")
    gate = (CFG / "GateDefenseConfig.luau").read_text(encoding="utf-8")
    g = gate[gate.find("GateMaxHealthByWallsLevel"):]
    return {
        "damage": num(orders, "AttackDamage", 8), "rate": num(orders, "AttackFireRate", 1.8), "range": num(orders, "AttackRange", 55),
        "near": num(fair, "UnitNearStuds", 35), "pNear": num(fair, "UnitNearHitChance", 0.98), "pFar": num(fair, "UnitFarHitChance", 0.96),
        "pMax": num(fair, "UnitMaxHitChance", 0.95), "pMin": num(fair, "UnitMinHitChance", 0.05),
        "pMult": num(ac, "PlayerDamageMult", 1), "dpsCap": num(ac, "PlayerMaxDps", 1e9), "guardMult": num(ac, "GuardDamageMult", 1),
        "gateMult": num(ac, "GateDamageMult", 1), "playerHp": num(combat, "PlayerMaxHealth", 100),
        "guardHp": [float(x) for x in re.findall(r"GuardHealth = (\d+)", gate)],
        "gateHp": [float(x) for x in re.findall(r"\[\d\] = (\d+)", g[:g.find("}")])],
        "regen": num(gate, "GateRegenPerSecond", 0),
    }


def hit_chance(c, d):
    if d <= c["near"] or c["range"] <= c["near"]:
        p = c["pNear"]
    else:
        t = min(1, max(0, (d - c["near"]) / (c["range"] - c["near"])))
        p = c["pNear"] + (c["pFar"] - c["pNear"]) * t
    hi = min(c["pMax"], 0.99)
    return max(min(hi, c["pMin"]), min(hi, p))


def fight(c, soldiers, hp, dmg, dist, cap=None, regen=0.0, trials=400, seed=1):
    rng = random.Random(seed)
    times, hits, shots = [], 0, 0
    period = 1 / c["rate"]
    for _ in range(trials):
        t, left = 0.0, hp
        nxt = [rng.random() * period for _ in range(soldiers)]  # the thinks are not in step
        win_at, win = 0.0, 0.0
        while left > 0 and t < 600:
            i = min(range(soldiers), key=lambda k: nxt[k])
            dt = nxt[i] - t
            t = nxt[i]
            left = min(hp, left + regen * dt)
            nxt[i] += period
            shots += 1
            if rng.random() >= hit_chance(c, dist):
                continue
            d = dmg
            if cap is not None:
                if t - win_at >= 1:
                    win_at, win = t, 0.0
                d = min(d, max(0.0, cap - win))
                win += d
            if d > 0:
                hits += 1
                left -= d
        times.append(t)
    times.sort()
    return sum(times) / len(times), times[len(times) // 2], hits / max(1, shots)


def table():
    c = load()
    rows = []
    for n in (5, 8):
        pd = c["damage"] * c["pMult"]
        for label, dist in (("stationary player at 36 studs", 36), ("moving player (in sight, 40 studs)", 40)):
            m, med, hr = fight(c, n, c["playerHp"], pd, dist, cap=c["dpsCap"])
            rows.append((n, label, m, hr))
        for lvl, gh in enumerate(c["gateHp"], 1):
            m, med, hr = fight(c, n, gh, c["damage"] * c["gateMult"], 38, regen=c["regen"], trials=60)
            mp, _, _ = fight(c, n, c["playerHp"], pd, 36, cap=c["dpsCap"])
            rows.append((n, f"player behind a L{lvl} gate (breach {m:.0f} s + kill)", m + mp, hr))
        for gh in (c["guardHp"][0], c["guardHp"][-1]):
            m, med, hr = fight(c, n, gh, c["damage"] * c["guardMult"], 38)
            rows.append((n, f"gate guard {gh:.0f} HP", m, hr))
    return c, rows


if __name__ == "__main__":
    c, rows = table()
    print(f"player damage per hit {c['damage'] * c['pMult']:.1f}, cap {c['dpsCap']:.0f}/s, fire rate {c['rate']}/s per soldier")
    print("| Soldiers | Target | Mean time to kill (s) | Hit rate |")
    print("|---|---|---|---|")
    for n, label, m, hr in rows:
        print(f"| {n} | {label} | {m:.1f} | {hr:.0%} |")


# ── claude-bud JOB 26: before (v118 numbers) / after (ArmyConfig.StrongerArmy) and player armour ──────────────────
def job26_tables():
    base = load()
    army = (CFG / "ArmyConfig.luau").read_text(encoding="utf-8")
    sa = army[army.find("\tStrongerArmy = {"):]
    sa = sa[:sa.find("\n\t},")]
    armour = (CFG / "ArmourConfig.luau").read_text(encoding="utf-8")
    reds = [float(x) for x in re.findall(r"Reduction = ([\d.]+)", armour)]
    combat = (CFG / "CombatConfig.luau").read_text(encoding="utf-8")
    npc = {k: float(v) for k, v in re.findall(r"\n\t\t(\w+) = \{\n(?:[^}]*?)Health = (\d+)", combat)}
    before = dict(base)
    after = dict(base)
    after["damage"] = num(sa, "Damage", base["damage"])
    after["rate"] = num(sa, "FireRate", base["rate"])
    after["dpsCap"] = num(sa, "PlayerMaxDps", base["dpsCap"])
    rows = []
    for label, hp in [("player, no armour", base["playerHp"]), (f"player, top armour (-{int(max(reds) * 100)}%)", base["playerHp"] / (1 - max(reds)))]:
        for n in (5, 8):
            b = fight(before, n, hp, before["damage"] * before["pMult"], 36, cap=before["dpsCap"])[0]
            a = fight(after, n, hp, after["damage"] * after["pMult"], 36, cap=after["dpsCap"])[0]
            rows.append((label, n, b, a))
    for t in ("Infantry", "HeavyInfantry", "FortGuard", "OilRigGuard"):
        if t in npc:
            b = fight(before, 5, npc[t], before["damage"], 38)[0]
            a = fight(after, 5, npc[t], after["damage"], 38)[0]
            rows.append((f"outpost defender {t} ({npc[t]:.0f} HP)", 5, b, a))
    for gh in (base["guardHp"][0], base["guardHp"][-1]):
        b = fight(before, 5, gh, before["damage"], 38)[0]
        a = fight(after, 5, gh, after["damage"], 38)[0]
        rows.append((f"gate guard {gh:.0f} HP", 5, b, a))
    return rows, after, before


if __name__ == "__main__":
    rows, after, before = job26_tables()
    print()
    print(f"JOB 26: soldier damage {before['damage']:.0f} -> {after['damage']:.0f}, fire rate {before['rate']} -> {after['rate']}, player DPS cap {before['dpsCap']:.0f} -> {after['dpsCap']:.0f}")
    print("| Target | Soldiers | Time to kill before (s) | after (s) |")
    print("|---|---|---|---|")
    for label, n, b, a in rows:
        print(f"| {label} | {n} | {b:.1f} | {a:.1f} |")
