# claude-bud JOB 39 (2026-09-30): ENDGAME PROGRESSION phase 1, owner-first (EndgameConfig.Live + Parts): the rebirth
# price scale, EMPIRE LEVEL (+2 % cash / level, kept through rebirth) and the Command Office in the plaza.
# Static pins + the real-code test (tools/sim/run_endgame_test.py).
import os as _j39_os
import re as _j39_re
import subprocess as _j39_sp
import sys as _j39_sys
from pathlib import Path as _J39P

if "ok" not in globals():
    _j39_fails = []

    def ok(msg):
        print("PASS " + msg)

    def bad(msg):
        _j39_fails.append(msg)
        print("FAIL " + msg)

if "read" not in globals():
    def read(p):
        q = _J39P(p)
        return q.read_text(encoding="utf-8") if q.is_file() else None


def _j39(cond, msg):
    (ok if cond else bad)("CLAUDE-BUD J39: " + msg)


def _j39_src(path):
    return (read(path) or "").replace("\r\n", "\n")


def _j39_code(path):
    s = _j39_re.sub(r"--\[\[.*?\]\]", "", _j39_src(path), flags=_j39_re.S)
    return "\n".join(l.split("--", 1)[0] for l in s.splitlines())


_SV = "src/ServerScriptService/Server/"
_CL = "src/StarterPlayer/StarterPlayerScripts/Client/"
_CF = "src/ReplicatedStorage/Shared/Configs/"
_EGC = _j39_src(_CF + "EndgameConfig.luau")
_ES = _j39_code(_SV + "Services/EndgameService.luau")
_ECT = _j39_code(_CL + "Controllers/EndgameController.luau")
_ECO = _j39_code(_SV + "Services/EconomyService.luau")
_BS = _j39_code(_SV + "Services/BaseService.luau")

# flags: one owner-first kill switch + a switch per system; phase 1 turns on Rebirth + EmpireLevel only
_j39("\tLive = {\n\t\tEnabled = true,\n\t\tOwnerFirst = true, -- only UserId 470626172" in _EGC and "RetentionConfig.Live(EndgameConfig.Live, userId)" in _EGC,
     "one owner-first kill switch (EndgameConfig.Live)")
_j39("\t\tRebirth = true," in _EGC and "\t\tEmpireLevel = true," in _EGC and "\t\tBaseTier = true," in _EGC and "\t\tDefence = true," in _EGC,
     "phases 1-2 parts on (Rebirth, EmpireLevel, BaseTier, Defence)")
_j39('= "owner"' not in _EGC and '= "owner"' not in _j39_src(_CF + "PlazaServicesConfig.luau"), "no \"owner\" strings in the new configs (codebot_v101)")
# OFF = old: every read is behind LiveFor
_j39("if not EndgameConfig.LiveFor(player.UserId, \"EmpireLevel\") then\n\t\treturn 1\n\tend" in _ES
     and "if typeof(profile) ~= \"table\" or not EndgameConfig.LiveFor(userId, \"Rebirth\") then\n\t\treturn 1\n\tend" in _ES,
     "OFF = old: no Empire factor and the raw price unless the part is live (nothing reads profile.Endgame)")
_j39("local eg = EconomyService._Endgame\n\t\tif eg and eg.EmpireMultFor then\n\t\t\tmult *= eg.EmpireMultFor(player, profile)" in _ECO
     and _ECO.index("mult *= eg.EmpireMultFor(player, profile)") > _ECO.index("if not isExempt then"),
     "the Empire factor is one more factor of the non-exempt cash stack (cashMultFor)")
_j39("\tlocal cost = def.Costs[targetLevel]\n\tif not cost then\n\t\treturn { Ok = false, Error = \"NoCost\" }\n\tend\n\t\n\tlocal eg = BaseService._Endgame\n\tif eg and eg.ScaledCost then\n\t\tcost = eg.ScaledCost(player, profile, structureId, cost)\n\tend" in _BS,
     "the one structure buy path charges the scaled price (BaseService.PurchaseUpgrade)")
_j39("Endgame" not in _j39_src(_CF + "BalanceConfig.luau"), "structure income reads the raw Costs (income unchanged)")
# the one purchase path; the client sends only kind / id
_j39("function EndgameService.Purchase(player: Player, kind: string, id: string?, auto: boolean?): (boolean, string)" in _ES
     and _ES.count("eco.SpendCash(") == 1 and 'local ok, err = eco.SpendCash(player, price, "endgame_" .. key)' in _ES
     and "local price = EndgameConfig.EmpireCost(L + 1)" in _ES and "Price = nx.Cost," in _ES,
     "ONE purchase path, ONE SpendCash (\"endgame_\" .. key); every price comes from config (EndgameService._Plan)")
_j39('Remotes.FireServer, Constants.RemoteNames.RequestEndgameBuy, "Empire", "Next")' in _ECT and "NextCost" not in _ECT.split("RequestEndgameBuy")[1][:40],
     "the client sends only the kind and id (never a price)")
_j39("if not EndgameService.AtStation(player, \"Command\") then" in _ES and "if not EndgameService.AtStation(player, \"Engineers\") then" in _ES
     and _ES.count("if not EndgameService.AtHQ(player) then") == 2 and _ES.count("if EndgameService.RecentlyHurt(player) then") >= 3,
     "buying needs the station / HQ console reach and no damage in the last HurtLockSeconds")
# phase 2: every effect is the old number while the part is not live for the base owner
_GD = _j39_code(_SV + "Services/GateDefenseService.luau")
_j39("maxHp = math.floor(maxHp * eg.GateHpMult(ownerUserId) + 0.5)" in _GD and "os.clock() + GateDefenseService.RebuildSeconds(def.OwnerUserId)" in _GD
     and "tu.MaxHealth = math.floor(tu.MaxHealth * eg.TurretHpMult(ownerUserId) + 0.5)" in _GD
     and "for slot, sx in ipairs(GateDefenseService.GunSlots(gx, ownerUserId)) do" in _GD and "(stats.TurretDamage or 22) * gunMult" in _GD,
     "GateDefenseService reads the Base Tier / Defence effects (gate HP, rebuild, turret HP / damage, nests)")
_j39("local function tierOf(userId: number): number\n\tif not EndgameConfig.LiveFor(userId, \"BaseTier\") then\n\t\treturn 0" in _ES
     and "local function defOf(userId: number, track: string): number\n\tif not EndgameConfig.LiveFor(userId, \"Defence\") then\n\t\treturn 0" in _ES,
     "OFF = old: the tier / defence levels read as 0 unless the part is live for the owner")
_j39("R.StealFraction * MoneyCollectorService.VaultMult(victim, false)" in _j39_code(_SV + "Services/MoneyCollectorService.luau"),
     "Vault Plating lowers the ATM raid (and the army raid) through MoneyCollectorService.VaultMult")
_BTB = _j39_code(_SV + "Modules/BaseTierBuilder.luau")
_j39("sl.Shadows = false" in _BTB and "Neon" not in _BTB and "PreferMesh" not in _BTB and "MeshPart" not in _BTB, "Base Tier builds: Parts only, no Neon, the one floodlight casts no shadows")
_SEC = _j39_src(_CF + "SecurityConfig.luau")
_j39('RequestEndgameBuy = { "string:16", "string:32?" },' in _SEC and "RequestEndgameState = {}," in _SEC
     and 'require(script.Parent.Parent.Modules.RemoteGate).Check(player, "RequestEndgameBuy", kind, id)' in _ES
     and 'require(script.Parent.Parent.Modules.RemoteGate).Check(player, "RequestEndgameState")' in _ES,
     "RemoteGate schemas + checks for both remotes")
# no fast travel / teleport / health writes; no Robux path
_NEW = _ES + _ECT + _EGC
_j39("PivotTo" not in _NEW and "FastTravel" not in _NEW and "TeleportService" not in _NEW, "no PivotTo / fast travel / teleport in the new code")
_j39(_j39_re.search(r"\.Health\s*=[^=]", _NEW) is None and "TakeDamage" not in _NEW, "no Humanoid.Health writes in the new code")
_j39("Endgame" not in _j39_src(_SV + "Services/MonetizationService.luau") and "Endgame" not in _j39_src(_CF + "MonetizationConfig.luau"),
     "no Robux path to Empire Level (MonetizationService / Config untouched)")
_j39("Endgame" not in _j39_code(_SV + "Services/LeaderboardService.luau") if read(_SV + "Services/LeaderboardService.luau") else True,
     "Empire Level is on no leaderboard")
# kept through rebirth
_PS = _j39_code(_SV + "Services/PrestigeService.luau")
_j39("profile.Endgame" not in _PS, "PrestigeService never touches profile.Endgame (kept on both rebirth paths)")
_j39("local function ensureEndgameFields(profile: any)" in _j39_src(_SV + "Modules/ProfileSchema.luau") and "\tensureEndgameFields(profile)\n" in _j39_src(_SV + "Modules/ProfileSchema.luau"),
     "profile.Endgame is sanitised on load (ProfileSchema)")
# the plaza station: client-only, budgets
_PSC = _j39_src(_CF + "PlazaServicesConfig.luau")
_j39("MaxParts = 40," in _PSC and "Parts = 39," in _PSC and "SignMaxDistance = 40," in _PSC and "LightRange = 14," in _PSC,
     "the Command Office interior: 39 parts (cap 40), one light (range 14), sign MaxDistance 40")
_j39("light.Shadows = false" in _ECT and "M.Neon" not in _ECT and 'Instance.new("Humanoid")' not in _ECT, "no shadows, no Neon, no Humanoid on the station NPC")
_j39("local want = live and EndgameConfig.LiveFor(player.UserId, st.Part)" in _ECT, "the station is built only for players it is live for (nobody else sees a change)")
# never touched
_j39(all("WE_Building" not in _j39_src(p) for p in (_SV + "Services/EndgameService.luau", _CL + "Controllers/EndgameController.luau", _SV + "Modules/BaseTierBuilder.luau")), "no WE_Building* edits")
_j39("PreferMesh" not in _NEW, "PreferMesh untouched")

_luau = _j39_os.environ.get("LUAU")
if _luau is None and _j39_os.environ.get("LUAU_COMPILE"):
    _cand = _j39_os.environ["LUAU_COMPILE"].replace("luau-compile", "luau")
    _luau = _cand if _j39_os.path.isfile(_cand) else None
if _luau:
    _r = _j39_sp.run([_j39_sys.executable, "tools/sim/run_endgame_test.py"], capture_output=True, text=True, env=dict(_j39_os.environ, LUAU=_luau))
    _j39(_r.returncode == 0 and "ENDGAME TEST: 0 failed" in _r.stdout, "run_endgame_test.py (real config / service / station builder / summary)")
else:
    print("SKIP CLAUDE-BUD J39: Luau CLI test (set LUAU)")

# phase 3: Elite Training (claude-bud JOB 39): server-side stats through the one damage path, the look, the refill
_SQ39 = _j39_code(_SV + "Services/SquadOrdersService.luau")
_j39("\t\tElite = true," in _EGC and "Recruits = { Row = \"NE_E1\", Part = \"Elite\"" in _j39_src(_CF + "PlazaServicesConfig.luau"), "phase 3 part on (Elite) + the Recruitment Office in NE_E1")
_j39("local elite = if eg and eg.UnitElite then eg.UnitElite(owner, slot) else nil" in _SQ39
     and "armyDamageBase() * SquadOrdersService._UnitDmg(player, unit) * armyBoostMult(player), credit)" in _SQ39
     and "local base = armyDamageBase() * SquadOrdersService._UnitDmg(player, unit) * armyBoostMult(player)" in _SQ39
     and "return math.min(r * e, tonumber((require(Shared.Configs.ResearchConfig) :: any).MaxMult) or 3)" in _SQ39,
     "Elite HP at spawn, Elite damage at both unit hit sites (research x elite, capped at MaxMult); PlayerMaxDps untouched downstream")
_j39("if not EndgameConfig.LiveFor(owner.UserId, \"Elite\") then\n\t\treturn nil" in _ES, "OFF = old: no Elite part live = today's soldier (UnitElite nil)")
_j39("model:ScaleTo(scale)" in _ES and "humanoid.HipHeight = hip0 * scale" in _ES, "trained soldiers are scaled (Model:ScaleTo) with the hip height kept right")
_j39("pcall(EGS.GrantRefill, player)" in _j39_code(_SV + "Services/SoldierService.luau"), "the Instant Army Refill (same product / price / Id) also pays the re-train fees (APPROVED §9 b)")
_j39("c = ArmyController.ScaledCfg(c, es)" in _j39_code(_SV + "Modules/ArmyController.luau"), "formation spacing x the largest soldier scale in the block")
_j39("e.Rate = 3" in _ECT and "e.LightEmission = 0.3" in _ECT and "return lvl >= 4" in _ECT, "the Mythic aura: Rate 3, LightEmission 0.3, client-only, Graphics Quality >= 4")
