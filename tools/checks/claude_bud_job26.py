# claude-bud JOB 26 (2026-09-29): stronger army + buyable player armour. Static pins + the time-to-kill model.
import re as _j26_re
import sys as _j26_sys
from pathlib import Path as _J26P

if "ok" not in globals():
    _j26_fails = []

    def ok(msg):
        print("PASS " + msg)

    def bad(msg):
        _j26_fails.append(msg)
        print("FAIL " + msg)

if "read" not in globals():
    def read(p):
        q = _J26P(p)
        return q.read_text(encoding="utf-8") if q.is_file() else None


def _j26(cond, msg):
    (ok if cond else bad)("CLAUDE-BUD J26: " + msg)


def _j26_code(path):
    return "\n".join(l.split("--", 1)[0] for l in (read(path) or "").splitlines())


_A = read("src/ReplicatedStorage/Shared/Configs/ArmyConfig.luau") or ""
_AR = read("src/ReplicatedStorage/Shared/Configs/ArmourConfig.luau") or ""
_S = _j26_code("src/ServerScriptService/Server/Services/SquadOrdersService.luau")
_AS = _j26_code("src/ServerScriptService/Server/Services/ArmourService.luau")
_RC = read("src/ReplicatedStorage/Shared/Configs/ResearchConfig.luau") or ""
_j26("\tStrongerArmy = {\n\t\tEnabled = true," in _A.replace("\r\n", "\n") and "Damage = " in _A and "FireRate = " in _A, "ArmyConfig.StrongerArmy on (kill switch), numbers in config")
_j26("armyDamageBase() * researchMult(player, \"SoldierDamage\")" in _S and "armyFireRate(unit)" in _S and "armyHealthBase() * researchMult(" in _S
     and "OrdersConfig.AttackDamage or 8) * researchMult" not in _S, "every soldier stat reads StrongerArmy (x research)")
_j26('"SoldierFireRate"' in _RC and "CombatDrills = {" in _RC, "Training = the Combat Drills research (fire rate); Firepower / Toughness = the existing research")
_j26("NoAttackerFb = not fb" in _j26_code("src/ServerScriptService/Server/Services/CombatService/init.luau"), "the owner sees his army's NPC hits (throttled hit markers)")
_j26("\tEnabled = true," in _AR and len(_j26_re.findall(r"Reduction = ", _AR)) >= 4 and "MaxReduction = 0.5" in _AR and "CommanderArmourRobux = false" in _AR,
     "ArmourConfig on, 4-5 tiers, capped at 50 %, no Robux item")
_j26("hum.MaxHealth = mx" in _AS and "baseHp() / (1 - ArmourService.ReductionFor(tier))" in _AS, "armour = bonus max health (works against every damage source)")
_j26("tier ~= tierOf(player) + 1" in _AS and "NeedCommandCenter" in _AS and "inOwnPlot(player, profile)" in _AS and "rs.PurchaseViaService(player, \"PersonalArmour\")" in _AS,
     "server-checked purchase: next tier, Command Center level, inside his base, Cash")
_j26('RemoteGate).Check(player, "RequestBuyArmour"' in (read("src/ServerScriptService/Server/Services/ArmourService.luau") or ""), "armour remotes gated")
_j26("CanQuery = false" in _AS and "Massless = true" in _AS and "HideArmourLook" in _AS, "armour look: inert welded parts, hideable")
_cc = _j26_code("src/StarterPlayer/StarterPlayerScripts/Client/Controllers/CombatController.luau")
_j26('ab.Name = "ArmourPanel"' in _cc and "WE_ArmourBaseHP" in _cc and "GetPropertyChangedSignal(\"AbsolutePosition\"):Connect(syncArmour)" in _cc, "HUD: blue armour bar above the health bar")
_ac = _j26_code("src/StarterPlayer/StarterPlayerScripts/Client/Controllers/ArmyController.luau")
_j26('"ARMY UPGRADES"' in _ac and '"MY ARMOUR"' in _ac, "Army menu: upgrades + armour")
try:
    _j26_sys.path.insert(0, str(_J26P("tools/sim").resolve()))
    import army_pvp_model as _m26
    _rows, _after, _before = _m26.job26_tables()
    _p = [r for r in _rows if r[0] == "player, no armour" and r[1] == 5][0]
    _pa = [r for r in _rows if r[0].startswith("player, top armour") and r[1] == 5][0]
    _j26(_p[3] < _p[2] and 1.2 <= _p[3] <= 4, f"a full army beats an unarmoured player faster ({_p[2]:.1f} -> {_p[3]:.1f} s)")
    _j26(_pa[3] >= _p[3] * 2, f"top armour at least doubles the time to kill ({_pa[3]:.1f} s)")
    _g = [r for r in _rows if "gate guard" in r[0]]
    _j26(all(r[3] < r[2] for r in _g), "guards / defenders fall faster than before")
except Exception as _e:  # noqa: BLE001
    bad("CLAUDE-BUD J26: model error " + repr(_e))

# replacements for the retired squadfair / army A0 pins (same guarantees, JOB 26 numbers)
_CS26 = read("src/ServerScriptService/Server/Services/CombatService/init.luau") or ""
_SO26 = read("src/ServerScriptService/Server/Services/SquadOrdersService.luau") or ""
_j26('local ok, dealt = pcall(apply, player, th, armyDamageBase() * researchMult(player, "SoldierDamage"), credit)' in _SO26,
     "squadfair (J26): a unit hit goes through CombatService.ApplyUnitHit (pcall; research damage kept)")
_j26("\tunit.LosCheckAt = now + 1 / math.max(armyFireRate(unit), 0.1)\n\tunit.LosBlocked = true" in _SO26.replace("\r\n", "\n"),
     "squadfair v2 (J26): a check that found nothing in sight waits one shot cooldown")
_j26("\tif not unitMayHit(owner, rec) then\n\t\treturn 0, false -- squadfair" in _CS26.replace("\r\n", "\n")
     and 'return hurtNPC(owner, npcId, damage, "Squad", { UnitShot = true, NoAttackerFb = not fb, NoCredit = credit ~= true })' in _CS26,
     "squadfair v3 (J26): no provoke by proxy; hurtNPC with credit rules; hit markers throttled")
_j26('if cfg.Enabled ~= true or not ArmyConfig.IsLive("Escort", owner) then' in _CS26
     and "pcall(CombatFx.ArmyBullet, owner.UserId, origin, landed, kind, gap, cfg.PerRecipientHz, cfg.PerRecipientBurst)" in _CS26,
     "army A0 (J26): UnitShotFx live owners only, through CombatFx.ArmyBullet with the per-recipient caps")
_RS26 = read("src/ServerScriptService/Server/Services/ResearchService.luau") or ""
_j26('if (def :: any).ServiceOnly == true and not serviceCall then' in _RS26 and 'rs.PurchaseViaService(player, "PersonalArmour")' in (read("src/ServerScriptService/Server/Services/ArmourService.luau") or ""),
     "armour is paid through the one research Cash path (ServiceOnly: the research remote cannot buy it)")
_armour_costs = [int(x) for x in _j26_re.findall(r"Cost = (\d+)", _AR)]
_rc_block = _RC[_RC.find("PersonalArmour = {"):]
_rc_costs = [int(x) for x in _j26_re.findall(r"\d+", _j26_re.search(r"Costs = \{([^}]*)\}", _rc_block).group(1))] if "PersonalArmour = {" in _RC else []
_j26(_armour_costs and _armour_costs == _rc_costs, f"armour prices identical in ArmourConfig and the PersonalArmour research ({_armour_costs} / {_rc_costs})")
