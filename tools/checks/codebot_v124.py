# Code Bot Roblox v124 (2026-09-30): phone bug "in ATTACK my army shot the bank guards but never Stevie, the player
# killing me right next to it". Root cause: the squad target pick (FormationController.PickTarget, sticky nearest-first
# over NPCs + players + guards alike) kept the NPC target unless the player was AttackRetargetStuds (15) nearer the army
# centre than it; the per-unit fallback shot is NPC-only. Fix: priority tiers (enemy player > guard / NPC; the player who
# hurt the owner first), ONE shared PvP rule (pvpBlock: guns, blasts, army), /armydebug [ArmyTarget] per-candidate log.
from pathlib import Path as _P124
import sys as _sys124


def _cb124(cond, label):
    if "ok" in globals() and "bad" in globals():
        (ok if cond else bad)(label)
    else:
        print(("PASS " if cond else "FAIL ") + label)
        if not cond:
            raise SystemExit(1)


def _rd124(p):
    q = _P124(p)
    return q.read_text(encoding="utf-8") if q.is_file() else ""


def _code124(text):
    return "\n".join(l.split("--", 1)[0] for l in text.splitlines())


def _fn124(src, head):
    i = src.find(head)
    if i < 0:
        return ""
    j = src.find("\nend\n", i)
    return src[i:j + 5] if j > 0 else src[i:]


_S124 = "src/ServerScriptService/Server/"
for _f in (_S124 + "Services/DataService.luau", _S124 + "Services/BaseService.luau", _S124 + "EarlyRemotes.server.luau"):
    pass  # v125 (Code Bot Roblox): retired, superseded in tools/checks/codebot_v125.py: #_cb124('SetAttribute("WE_Build", 124)' in _rd124(_f), "CODEBOT v124: WE_Build=124 " + _f.rsplit("/", 1)[-1])
# v125 (Code Bot Roblox): retired, superseded in tools/checks/codebot_v125.py: #_cb124("WE_Build=124" in _rd124(_S124 + "Services/DataService.luau"), "CODEBOT v124: DataService profile-loaded log says WE_Build=124")

# 1. ONE shared PvP hostility rule: guns (hurtPlayer), blasts and the army all use pvpBlock
_cs = _code124(_rd124(_S124 + "Services/CombatService/init.luau"))
_pb = _fn124(_cs, "local function pvpBlock(")
_cb124(all(k in _pb for k in ("GameConfig.PvPEnabled", '"self"', "NS.allowsAttack(attacker)", "InvulnerableUntil", "NS.Active[victim.UserId]", '"protected"', '"dead"')),
       "CODEBOT v124: pvpBlock = PvP on, not self, attacker not novice-shielded, victim not spawn/novice shielded, alive")
_cb124("Admin" not in _pb and "IsPlaytestOwner" not in _pb, "CODEBOT v124: no admin / owner / playtest bypass or immunity in the PvP rule")
_hp = _fn124(_cs, "local function hurtPlayer(")
_cb124("elseif pvpBlock(attacker, victim) ~= nil then" in _hp and "GameConfig.FriendlyFire" in _hp, "CODEBOT v124: guns / melee / vehicle hits (hurtPlayer) use pvpBlock")
_cb124("attacker == victim or pvpBlock(attacker, victim) ~= nil" in _fn124(_cs, "function CombatService.ApplyBlastDamage("), "CODEBOT v124: blasts use pvpBlock")
_may = _fn124(_cs, "function CombatService.UnitMayHitPlayer(")
_cb124("isClanAlly(owner, victim)" in _may and "pvpBlock(owner, victim)" in _may and "GameConfig" not in _may and "InvulnerableUntil" not in _may,
       "CODEBOT v124: the army = pvpBlock + never a clan ally (no second copy of the rule)")
_cb124("CombatService.UnitMayHitPlayer(owner, victim)" in _fn124(_cs, "function CombatService.ApplyUnitPlayerHit("), "CODEBOT v124: every army hit on a player re-checks the rule")
_cb124("byVictim[attacker.UserId] = clock()" in _hp and "function CombatService.RecentlyHurtBy(" in _cs, "CODEBOT v124: aggressor record (who hurt whom) for the army's priority")

# 2. the tiered squad target
_fc = _code124(_rd124("src/ReplicatedStorage/Shared/Util/FormationController.luau"))
_pt = _fn124(_fc, "function FormationController.PickTargetTiered(")
_cb124("FormationController.PickTarget(" in _pt, "CODEBOT v124: inside a tier the sticky PickTarget rule is unchanged")
_so = _code124(_rd124(_S124 + "Services/SquadOrdersService.luau"))
_pst = _fn124(_so, "local function pickSquadTarget(")
_cb124("FormationController.PickTargetTiered(" in _pst and 'consider(hum, r, "Player", pl, pri)' in _pst and "CombatService.RecentlyHurtBy(player, pl, aggroSecs)" in _pst,
       "CODEBOT v124: pickSquadTarget ranks enemy players (aggressors first) over guards / NPCs")
_cb124("pl ~= player" in _pst and "CombatService.UnitMayHitPlayer, player, pl" in _pst, "CODEBOT v124: never the owner; every player candidate passes UnitMayHitPlayer (no clan ally)")
_cb124("[ArmyTarget]" in _rd124(_S124 + "Services/SquadOrdersService.luau") and "acm.DebugFor(player)" in _pst and "TargetLogSeconds" in _pst,
       "CODEBOT v124: /armydebug [ArmyTarget] per-candidate verdict log (owner debug only, rate-limited)")
_ac = _rd124("src/ReplicatedStorage/Shared/Configs/ArmyConfig.luau")
_cb124("PreferPlayers = true," in _ac and "AggressorSeconds = 10," in _ac and "TargetLogSeconds = 2," in _ac, "CODEBOT v124: ArmyCombat.PreferPlayers / AggressorSeconds / TargetLogSeconds")
_cb124("PlayerMaxDps = 50" in _ac and "PlayerMaxDps" in _fn124(_so, "local function unitShootAt("), "CODEBOT v124: the per-victim PlayerMaxDps cap kept")
_cb124("AttackSteer = true," in _ac and "Steer = true" in _ac, "CODEBOT v124: Follow3.Steer / AttackSteer unchanged")

# 3. the real PickTarget(Tiered) under luau: the phone geometry (v123 keeps the guard once Stevie is >= 21 studs from the centre)
try:
    _sys124.path.insert(0, str(_P124("tools/sim").resolve()))
    import army_target_tiers as _att
    _r = _att.run()
    if _r is None:
        ok("CODEBOT v124: luau CLI missing, target-tier sim skipped") if "ok" in globals() else print("SKIP luau")
    else:
        _rows, _regs, _err = _r
        _cb124(len(_rows) == 8 and all(r[2] == "Stevie" for r in _rows), "CODEBOT v124: sim: the enemy player beside / near the army is the target at every distance " + str(_rows))
        _cb124(any(r[1] == "Guard" for r in _rows), "CODEBOT v124: sim reproduces the v123 bug (sticky guard hides the player at >= 25 studs)")
        _cb124(len(_regs) == 7 and all(_regs.values()), "CODEBOT v124: sim regressions (NPC stickiness, far player, keep band, aggressor) " + str(_regs) + _err[:200])
except Exception as _e:  # noqa: BLE001
    _cb124(False, "CODEBOT v124: target-tier sim error " + repr(_e))
