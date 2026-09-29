# claude-bud JOB 24 big pass (2026-09-29): army PvP damage (§2), live server warnings (§4), new codes (§9), analytics (§10),
# crown explainer (§11), building tips (§5), outpost / area enemies (§6-7), town streaming (§8).
# Static pins (+ the PvP time-to-kill model, tools/sim/army_pvp_model.py).
import re as _jb_re
import subprocess as _jb_sp
import sys as _jb_sys
from pathlib import Path as _JbP

if "ok" not in globals():
    _jb_fails = []

    def ok(msg):
        print("PASS " + msg)

    def bad(msg):
        _jb_fails.append(msg)
        print("FAIL " + msg)

if "read" not in globals():
    def read(p):
        q = _JbP(p)
        return q.read_text(encoding="utf-8") if q.is_file() else None


def _jb(cond, msg):
    (ok if cond else bad)("CLAUDE-BUD J24b: " + msg)


def _jb_code(path):
    return "\n".join(l.split("--", 1)[0] for l in (read(path) or "").splitlines())


def _jb_fn(src, head):
    i = src.find(head)
    if i < 0:
        return ""
    j = src.find("\nend\n", i)
    return src[i:j + 5] if j > 0 else src[i:]


_SOS = _jb_code("src/ServerScriptService/Server/Services/SquadOrdersService.luau")
_CS = _jb_code("src/ServerScriptService/Server/Services/CombatService/init.luau")
_GD = _jb_code("src/ServerScriptService/Server/Services/GateDefenseService.luau")
_ARMY = read("src/ReplicatedStorage/Shared/Configs/ArmyConfig.luau") or ""

# §2 army vs players / guards / gates
_jb("\tArmyCombat = {\n\t\tEnabled = true," in _ARMY and "PlayerMaxDps = " in _ARMY, "ArmyConfig.ArmyCombat on (kill switch Enabled), player DPS capped")
_may = _jb_fn(_CS, "function CombatService.UnitMayHitPlayer(")
_jb(all(k in _may for k in ("GameConfig.PvPEnabled", "isClanAlly(owner, victim)", "NS.allowsAttack(owner)", "InvulnerableUntil", '"protected"')),
    "UnitMayHitPlayer keeps PvP, clan, novice and spawn-shield rules")
_uph = _jb_fn(_CS, "function CombatService.ApplyUnitPlayerHit(")
_jb("CombatService.UnitMayHitPlayer(owner, victim)" in _uph and 'hurtPlayer(owner, victim, damage, "Squad", { UnitShot = true })' in _uph,
    "an army hit on a player goes through hurtPlayer (creator tag = the owner: cash, XP, MOST KILLS)")
_jb("Players:GetPlayerFromCharacter(model) ~= nil then" in _jb_fn(_CS, "function CombatService.ApplyUnitHit("), "ApplyUnitHit (NPC path) unchanged: never a player")
_jb("function GateDefenseService.ApplyUnitDamage(" in _GD and "local function applyDamageFrom(" in _GD and "function GateDefenseService.ApplyDamage(" in _GD
    and "((fromPos or root.Position) - hitPart.Position).Magnitude > maxDist" in _GD, "guards / gates: the unit's shot is range-checked from the unit")
_jb("function GateDefenseService.HostileGuards(" in _GD and "GateDefenseService.IsAlly(def.OwnerUserId, player)" in _GD, "hostile guards only from other, non-allied bases")
_pst = _jb_fn(_SOS, "local function pickSquadTarget(")
_jb('consider(hum, r, "Player", pl)' in _pst and 'consider(g.Hum, g.Root, "Guard")' in _pst and "noteProtected(player, pl, why)" in _pst,
    "the attack target may be an enemy player / guard; protected players shown as Protected")
_usa = _jb_fn(_SOS, "local function unitShootAt(")
_jb("unitHitChance(" in _usa and "CombatService.ApplyUnitPlayerHit" in _usa and "gd.ApplyUnitDamage" in _usa and "PlayerMaxDps" in _usa and "hitLog(" in _usa,
    "unit shots at players / guards / gates: hit roll, server damage, DPS cap, hit log")
_aao = _jb_fn(_SOS, "local function attackAimOnly(")
_jb("unitHasLos(player, unit, tgt.Root)" in _aao and "gateBlocking(player, unit, tgt.Root)" in _aao, "line of sight kept; a player behind a gate: the army shoots the gate")
_jb("CreditSteeredAttackKills" in _aao, "steered ATTACK kills credited to the owner")

# the time-to-kill model (config numbers)
try:
    _jb_sys.path.insert(0, str(_JbP("tools/sim").resolve()))
    import army_pvp_model as _pvp
    _c, _rows = _pvp.table()
    _p5 = [r for r in _rows if r[0] == 5 and r[1].startswith("stationary")][0]
    _jb(1.2 <= _p5[2] <= 8, f"5 soldiers kill a standing player in 1.2-8 s (JOB 26 StrongerArmy; model {_p5[2]:.1f} s, hit rate {_p5[3]:.0%})")
    _g = [r for r in _rows if r[0] == 5 and "gate guard" in r[1]]
    _jb(all(r[2] <= 10 for r in _g), f"5 soldiers kill a gate guard within 10 s ({[round(r[2], 1) for r in _g]})")
except Exception as _e:  # noqa: BLE001
    bad("CLAUDE-BUD J24b: PvP model error " + repr(_e))

# §4a research stats: every node's Stat is registered
_RC = read("src/ReplicatedStorage/Shared/Configs/ResearchConfig.luau") or ""
_ids = set(_jb_re.findall(r'"(\w+)"', _RC[_RC.find("ResearchConfig.StatIds = {"):_RC.find("}", _RC.find("ResearchConfig.StatIds = {"))]))
_stats = set(_jb_re.findall(r'\n\t\tStat = "(\w+)"', _RC))
_jb(_stats and _stats <= _ids, f"every research node Stat is in StatIds (missing {sorted(_stats - _ids)})")
_jb({"GuardHP", "GuardCount", "TowerGuards"} <= _ids, "guard research stats registered (GuardArmor / GuardRoster / TowerGuards live)")
_jb("FlatCosts = true," in _RC and "def.FlatCosts ~= true" in (read("src/ServerScriptService/Server/Services/ResearchService.luau") or ""),
    "TowerGuards' flat price passes the sanity check")
# §4b terrain
_WT = read("src/ServerScriptService/Server/Modules/WorldTerrain.luau") or ""
_jb("pcall(function()\n\t\t\tterrain.Decoration = c.Decoration" in _WT.replace("\r\n", "\n"), "Terrain.Decoration write guarded (the build no longer aborts)")
_jb('warn("[WAR EMPIRE] WorldTerrain: dropped "' not in _WT, "terrain keep-out drops: one info line, not warnings")
# §4c assets
_VAC = read("src/ReplicatedStorage/Shared/Configs/VisualAssetConfig.luau") or ""
for _aid in ("76846072091295", "53591587", "175462478", "107381977457431", "90362241548850", "35409899", "15192621369", "18220523228"):
    _jb(_jb_re.search(r"ModelAssetId = " + _aid + r"\b", _VAC) is None, f"asset {_aid} (not authorized / over the part cap live) removed")
# §4d noise
_jb("anchor rows not stamped (%s)\", poi.Id, noHost, why), true)" in (read("src/ServerScriptService/Server/Modules/WorldPOI.luau") or ""),
    "WorldPOI: skips are info, a missing activity host stays a warning")
_jb("if not isHostCluster(c) and (row.Parts + pParts > partsCap" in (read("src/ServerScriptService/Server/Modules/WorldPOI.luau") or ""), "the ActivityHost cluster is never capped out")
_jb("AUTOSAVE_SKIP_RECENT" in (read("src/ServerScriptService/Server/Services/DataService.luau") or ""), "autosave skips a profile written in the last seconds (DataStore queue)")

# §9 codes
_CC = read("src/ServerScriptService/Server/Configs/CodesConfig.luau") or ""
for _code in ("BUDSTUDIOS", "BUDSQUAD", "WAREMPIRE", "ATTACK"):
    _jb(_jb_re.search(r"\n\t\t" + _code + r" = \{\n\t\t\tActive = true,", _CC.replace("\r\n", "\n")) is not None, f"code {_code} active")
_jb("XPService.AddXP, player, xp, \"code\"" in (read("src/ServerScriptService/Server/Services/CodesService.luau") or ""), "codes can grant XP")

# §10 analytics
_AN = _jb_code("src/ServerScriptService/Server/Services/AnalyticsService.luau")
_jb("LogOnboardingFunnelStepEvent" in _AN and "LogEconomyEvent" in _AN and "LogCustomEvent" in _AN, "Roblox AnalyticsService sink: funnel, economy, custom")
_jb("budgetOk()" in _AN and "EconomyFlushSeconds" in _AN and "ClientPerMinute" in _AN, "analytics limits: custom budget, economy flushed per minute, client events rate-limited")
_jb('analyticsEconomy(player, "Source", granted, profile.Cash, reason)' in _jb_code("src/ServerScriptService/Server/Services/EconomyService.luau"), "Cash sources / sinks reported")

# §11 crown
_ES = read("src/ServerScriptService/Server/Services/EngagementService.luau") or ""
_jb('"#1 " .. string.upper(label) .. " this week"' in _ES and "Keep it to keep your crown." in _ES, "crown label + one-time note")
_jb("not isBoardExcluded(uid)" in _ES, "owner / admin stay off the boards and crowns")

# §5 building tips
_BT = read("src/ReplicatedStorage/Shared/Configs/BuildingTutorialConfig.luau") or ""
_BC = read("src/ReplicatedStorage/Shared/Configs/BaseConfig.luau") or ""
_sids = set(_jb_re.findall(r"\n\t\t(\w+) = \{\n\t\t\tId = \"\w+\"", _BC.replace("\r\n", "\n")))
_tips = set(_jb_re.findall(r"\n\t\t(\w+) = \{ Lines = ", _BT.replace("\r\n", "\n")))
_jb(_tips and _sids <= _tips, f"every building has a tip card (missing {sorted(_sids - _tips)})")
_long = [l for l in _jb_re.findall(r'"([^"]{3,})"', _BT[_BT.find("Tips = {"):]) if len(l.split()) > 12]
_jb(not _long, f"tip lines stay short (<= 12 words): {_long[:3]}")
_jb(not _jb_re.search(r"\b(press|click)\b|\b[EF] key\b", _BT[_BT.find("Tips = {"):], _jb_re.I), "tip copy names no key and never says click (phones)")
_BTS = _jb_code("src/ServerScriptService/Server/Services/BuildingTips.luau")
_jb("GetUpgradeChangedEvent" in _BTS and "newLevel ~= 1" in _BTS and "profile.SeenTutorials[structureId] = true" in _BTS, "a card only after a server-confirmed first purchase, once per building (SeenTutorials)")
_jb('RemoteGate).Check(player, "RequestTipSetting"' in (read("src/ServerScriptService/Server/Services/BuildingTips.luau") or ""), "tip remotes gated")
_BTC = _jb_code("src/StarterPlayer/StarterPlayerScripts/Client/Controllers/BuildingTipController.luau")
_jb("hum.SeatPart ~= nil" in _BTC and "table.remove(queue, 1)" in _BTC and "WE_ConsolePos_" in _BTC, "cards queued, never while driving; SHOW ME beams to the console")
_jb("TipsToggle" in (read("src/StarterPlayer/StarterPlayerScripts/Client/Controllers/SettingsController.luau") or ""), "Settings: tips toggle + replay")

# §6 / §7 defenders
_OD = _jb_code("src/ServerScriptService/Server/Modules/OutpostDefenders.luau")
_ODC = read("src/ReplicatedStorage/Shared/Configs/OutpostDefenderConfig.luau") or ""
_jb("\tEnabled = true," in _ODC and "MaxTotal = " in _ODC and "Areas = {" in _ODC, "outpost + area defenders on, capped, areas listed")
_jb("NoRespawn = true" in _OD and "OverCap = true" in _OD and "DespawnNPC" in _OD and "anyPlayerWithin(pos, C.WakeStuds)" in _OD, "defenders: CombatService NPCs, awake only near players, managed respawn")
_jb("OutpostDefenders.Blocking(rt.Def.Id)" in _jb_code("src/ServerScriptService/Server/Services/TerritoryService/init.luau"), "no capture while defenders stand")
_jb("es.NoteDefenderKill" in _OD and "function EngagementService.NoteDefenderKill(" in _jb_code("src/ServerScriptService/Server/Services/EngagementService.luau"),
    "defender kills count on MOST KILLS")
_jb("SpecialOverCap = 24," in (read("src/ReplicatedStorage/Shared/Configs/CombatConfig.luau") or ""), "NPC headroom = bank 4 + defenders 20")

# §8 phone culling
_QG = _jb_code("src/StarterPlayer/StarterPlayerScripts/Client/Modules/QualityGovernor.luau")
_QC = read("src/ReplicatedStorage/Shared/Configs/QualityConfig.luau") or ""
_jb("NeverHideKinds = {" in _QC and '"block"' in _QC and "LookAheadSeconds" in _QC, "town buildings / landmarks are never culled; look-ahead for fast travel")
_jb("if neverHide[kind] then" in _QG and "focusVel * (tonumber(Q.LookAheadSeconds) or 0)" in _QG and "ShowSlackStuds" in _QG, "governor: skip buildings, predict, hysteresis")
_jb("Streaming" not in (read("default.project.json") or ""), "StreamingEnabled untouched (still off)")
