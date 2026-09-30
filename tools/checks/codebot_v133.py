# Code Bot Roblox v133 (2026-09-30): Shaun's phone bugs.
#  1a. An enemy army on FOLLOW / HOLD never shot him: a player was a target only in SquadOrdersService.pickSquadTarget,
#      which the think loop ran only for ATTACK (OrdersConfig.DefaultOrder = "Follow"; FOLLOW / HOLD scanned WE_NPC only).
#      Fix: pickDefendTarget / defendAimOnly (ArmyConfig.ArmyCombat.DefendOnFollow) under UnitMayHitPlayer.
#  1b. His shots did nothing to that army: CombatService's shot filter excluded the WHOLE Workspace.WarEmpireSquads
#      folder (live probe on v132: the ray passed the soldier and hit the wall behind), and resolveTarget had no kind for
#      a squad unit. Fix: the filter passes only his own / clan allies' soldiers, resolveTarget "Unit", ApplyHit "Unit"
#      under ArmyHostility (CombatService deals the damage; the squad remembers the shooter: NoteArmyAggressor).
#  2.  The roof ladder ended under the roof slab (a climber hangs on a FACE of the truss): a real hatch opening, the
#      ladder inside it, a shaft panel on its roofed face (tools/sim/run_hatch_test.py, character-sized).
#  3.  Speed: Speed Boost x2 (32), Speed Pass x1.5 (24), MAX_WALK_SPEED_MULT 2; soldiers keep catch-up headroom (46).
#  4.  Town-centre facades: PlazaBuildingsConfig.Styles + the WorldKits PlazaHouse facade (142 parts each).
import os as _os133
import subprocess as _sp133
import sys as _sys133
from pathlib import Path as _P133


def _cb133(cond, label):
    if "ok" in globals() and "bad" in globals():
        (ok if cond else bad)(label)
    else:
        print(("PASS " if cond else "FAIL ") + label)
        if not cond:
            raise SystemExit(1)


def _rd133(p):
    q = _P133(p)
    return q.read_text(encoding="utf-8") if q.is_file() else ""


def _code133(p):
    return "\n".join(l.split("--", 1)[0] for l in _rd133(p).splitlines())


def _fn133(src, head, n=6000):
    i = src.find(head)
    return src[i:i + n] if i >= 0 else ""


_S133 = "src/ServerScriptService/Server/"
for _f in (_S133 + "Services/DataService.luau", _S133 + "Services/BaseService.luau", _S133 + "EarlyRemotes.server.luau"):
    pass  # v134 (Code Bot Roblox): retired, superseded in tools/checks/codebot_v134.py: #_cb133('SetAttribute("WE_Build", 133)' in _rd133(_f), "CODEBOT v133: WE_Build=133 " + _f.rsplit("/", 1)[-1])
# v134 (Code Bot Roblox): retired, superseded in tools/checks/codebot_v134.py: #_cb133("WE_Build=133" in _rd133(_S133 + "Services/DataService.luau"), "CODEBOT v133: DataService profile-loaded log says WE_Build=133")

# ── 1b: player shots on enemy soldiers ──
_CS = _rd133(_S133 + "Services/CombatService/init.luau")
_CSc = _code133(_S133 + "Services/CombatService/init.luau")
_sf = _fn133(_CSc, "local function shotFilterFor(character: Model, veh: Model?, shooterUid: number?): { Instance }", 2200)
_cb133(_sf != "" and "fr = uo == uid or (shooter ~= nil and (op == nil or isClanAlly(shooter, op)))" in _sf and "acfg.PlayersHitUnits ~= true then\n\t\t\ttable.insert(f, squads)" in _sf,
       "CODEBOT v133: the shot filter passes only the shooter's own / clan allies' soldiers (whole folder only with PlayersHitUnits off)")
_cb133('if typeof(unitOwner) == "number" and node:GetAttribute("SquadUnitId") ~= nil then' in _CSc and 'return "Unit", unitOwner, node' in _CSc,
       "CODEBOT v133: resolveTarget gives a squad unit the kind \"Unit\" (it was \"None\": no WE_NPC tag, no NPCId)")
_ah = _fn133(_CSc, 'elseif kind == "Unit" then', 3000)
_cb133("CombatService.ArmyHostility(attacker, owner)" in _ah and "NS.allowsAttack(attacker)" in _ah and "uh:TakeDamage(dmg)" in _ah
       and "CombatService.NoteArmyAggressor(owner, attacker)" in _ah and "hitFeedback(attacker, {" in _ah,
       "CODEBOT v133: ApplyHit \"Unit\": ArmyHostility + attacker shield, real Humanoid damage, the owner's army remembers the shooter, hit feedback")
_cb133("army is Protected (new-player shield)" in _ah, "CODEBOT v133: a hit on a shielded player's army toasts Protected (rate-limited)")
_ahs = _fn133(_CSc, "function CombatService.ArmyHostility(attacker: Player, owner: Player): (boolean, string)", 700)
_cb133('"pvp_off"' in _ahs and '"self"' in _ahs and "isClanAlly(attacker, owner)" in _ahs and "NS.Active[owner.UserId] ~= nil" in _ahs,
       "CODEBOT v133: ArmyHostility = PvP on, not self, never a clan ally, never a novice-shielded owner's army")
_cb133('local isHead = (kind == "Player" or kind == "NPC" or kind == "Unit") and result.Instance.Name == "Head"' in _CSc,
       "CODEBOT v133: headshots on the exact ray include soldiers")
_cb133('print(string.format("[ArmyUnitHit]' in _CSc, "CODEBOT v133: /armydebug [ArmyUnitHit] log")

_SO = _rd133(_S133 + "Services/SquadOrdersService.luau")
_SOc = _code133(_S133 + "Services/SquadOrdersService.luau")
_cb133("CombatService.SetUnitHitHandler(playerHitUnit)" in _SOc and "local function playerHitUnit(_attacker: Player, model: Model): Humanoid?" in _SOc,
       "CODEBOT v133: SquadOrdersService hands CombatService its live-unit lookup (it deals no raw damage: squadfair)")
_cb133("TakeDamage(" not in _SOc, "CODEBOT v133: still no raw TakeDamage in SquadOrdersService")

# ── 1a: FOLLOW / HOLD defend ──
_cb133("local function pickDefendTarget(player: Player, st: SquadState, proot: BasePart)" in _SOc and "CombatService.UnitMayHitPlayer" in _fn133(_SOc, "local function pickDefendTarget(", 5000)
       and "CombatService.RecentlyHurtBy" in _fn133(_SOc, "local function pickDefendTarget(", 5000),
       "CODEBOT v133: pickDefendTarget (THE shared UnitMayHitPlayer; aggressors first)")
_cb133('(st.Order == "Follow" or st.Order == "Hold") and proot' in _SOc and "pcall(pickDefendTarget :: any, player, st, proot)" in _SOc,
       "CODEBOT v133: the think loop picks a defend target for FOLLOW / HOLD (was ATTACK only: pickSquadTarget)")
_cb133("local engaged = defendAimOnly(player, st, unit, now)" in _SOc and "[ArmyDefend]" in _SO, "CODEBOT v133: thinkUnit fires on the defend target; /armydebug [ArmyDefend] log")
_AY = _rd133("src/ReplicatedStorage/Shared/Configs/ArmyConfig.luau")
_cb133("DefendOnFollow = true," in _AY and "DefendPlayerStuds = 47," in _AY and "DefendAggressorStuds = 55," in _AY and "PlayersHitUnits = true," in _AY,
       "CODEBOT v133: ArmyCombat DefendOnFollow / 47 / 55 / PlayersHitUnits (kill switches)")
_CL = _code133("src/StarterPlayer/StarterPlayerScripts/Client/Controllers/CombatController.luau")
_cb133('if m:GetAttribute("OwnerUserId") == player.UserId or typeof(m:GetAttribute("OwnerUserId")) ~= "number" then' in _CL and "Feel.FilterKids" in _CL,
       "CODEBOT v133: the client aim filter passes only his own soldiers (rebuilt when the squad folder changes)")

# ── 2 + 4: the plaza buildings ──
_WK = _rd133(_S133 + "Modules/WorldKits.luau")
_PB = _rd133("src/ReplicatedStorage/Shared/Configs/PlazaBuildingsConfig.luau")
_cb133("MaxExtraParts = 640," in _PB and "Parts = 142," in _PB and "Rows = { NE_E1 = true, SW_S1 = true, NE_N1 = true, NW_W1 = true }" in _PB and "Enabled = true," in _PB,
       "CODEBOT v133: PlazaBuildingsConfig: kill switch, the 4 rows, 142 parts each, allowance 640")
_cb133("WorldKits.DetailSpecs.PlazaHouse = 142" in _WK and 'truss(b, "PlazaLadder", 12, CFrame.new(hx1 - 1.2, H + 0.4 + 6, 5.25), PAL.SteelDark)' in _WK and '"PlazaHatchShaft"' in _WK,
       "CODEBOT v133: the ladder stands inside the hatch opening; its roofed face is boxed in")
_ph = _fn133(_WK, "Builders.PlazaHouse = function(b: B)", 20000)
_cb133("WorldKits.Sign" not in _ph and "nightLamp" not in _ph, "CODEBOT v133: the facade adds no SurfaceGui / light (WorldPOI's row caps would skip the building)")
_cb133("PreferMesh = true" not in _rd133("src/ReplicatedStorage/Shared/Configs/VisualAssetConfig.luau"), "CODEBOT v133: PreferMesh stays OFF")

# ── 3: speed ──
_mc = _rd133("src/ReplicatedStorage/Shared/Configs/MonetizationConfig.luau")
_sp = _mc[_mc.find("ImpulseSpeed = {"):][:700]
_sb = _mc[_mc.find("\t\tSpeedBoost = {"):][:900]
_cb133("Id = 1998656357," in _sp and "RobuxPrice = 99," in _sp and "WalkSpeedMult = 1.5," in _sp and 'Description = "Run 50% faster, forever"' in _sp,
       "CODEBOT v133: Speed Pass Id / 99 R$ unchanged, x1.5 (24), 'Run 50% faster, forever'")
_cb133("Id = 3713839342," in _sb and "RobuxPrice = 99," in _sb and "OneTime = true" in _sb and "WalkSpeedMult = 2.0," in _sb and 'Description = "Run 2x faster, forever"' in _sb,
       "CODEBOT v133: Speed Boost Id / 99 R$ / OneTime unchanged, x2 (32), 'Run 2x faster, forever'")
_cb133("local MAX_WALK_SPEED_MULT = 2.0" in _rd133(_S133 + "Services/MonetizationService.luau"), "CODEBOT v133: MAX_WALK_SPEED_MULT = 2 (the cap 32)")
_cb133("MaxSpeed = 46, -- v133" in _AY and "FormMaxSpeed = 24," in _AY and "FormSpeedMult = 1.25," in _AY,
       "CODEBOT v133: Follow3 soldiers MaxSpeed 46; the block runs max(24, his speed x 1.25) = 40 behind a 32 runner")

# ── the Luau CLI tests ──
_luau = _os133.environ.get("LUAU")
if _luau is None and _os133.environ.get("LUAU_COMPILE"):
    _cand = _os133.environ["LUAU_COMPILE"].replace("luau-compile", "luau")
    _luau = _cand if _os133.path.isfile(_cand) else None
if _luau:
    _r = _sp133.run([_sys133.executable, "tools/sim/run_hatch_test.py"], capture_output=True, text=True, env=dict(_os133.environ, LUAU=_luau))
    _cb133(_r.returncode == 0 and "HATCH TEST: 0 failed" in _r.stdout, "CODEBOT v133: run_hatch_test.py (a character climbs every plaza ladder onto the roof; no trap face)")
else:
    print("SKIP CODEBOT v133: Luau CLI hatch test (set LUAU)")
