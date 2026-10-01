# claude-bud JOB 48 (2026-10-01): the first 2 minutes hook (TutorialConfig.Guided.Hook: OrderVersion 5, RAID A RIVAL BASE
# or the fallback, RewardSoldiers, the real fast-raid bonus, funnel steps 12-16, SessionMilestone / FtueTimeToFight).
import os as _j48_os
import re as _j48_re
import subprocess as _j48_sp
import sys as _j48_sys
from pathlib import Path as _J48P

if "ok" not in globals():
    def ok(msg):
        print("PASS " + msg)

    def bad(msg):
        print("FAIL " + msg)

if "read" not in globals():
    def read(p):
        q = _J48P(p)
        return q.read_text(encoding="utf-8") if q.is_file() else None


def _j48(cond, msg):
    (ok if cond else bad)("CLAUDE-BUD J48: " + msg)


def _j48_src(path):
    return (read(path) or "").replace("\r\n", "\n")


def _j48_code(path):
    s = _j48_re.sub(r"--\[\[.*?\]\]", "", _j48_src(path), flags=_j48_re.S)
    return "\n".join(l.split("--", 1)[0] for l in s.splitlines())


_CF = "src/ReplicatedStorage/Shared/Configs/"
_SV = "src/ServerScriptService/Server/"
_TC = _j48_src(_CF + "TutorialConfig.luau")
_hook = _TC.split("\tHook = {")[1].split("\n\t},\n}")[0] if "\tHook = {" in _TC else ""
_j48("Enabled = true," in _hook and "OwnerFirst = true," in _hook and "OrderVersion = 5," in _hook,
     "TutorialConfig.Guided.Hook: Enabled = true, OwnerFirst = true (owner-first), OrderVersion 5")
_j48('Steps = { "Spawned", "FirstBuild", "Collected", "Recruited", "FightStarted", "FirstKill", "Captured", "Reward",\n\t\t\t"NextBuilding", "Offered", "Bought" },' in _TC,
     "the live FirstMinutes funnel steps 1-11 are unchanged (the Hook's steps go after them)")
_j48('FunnelSteps = { "ArmyGrew", "GoalRaidShown", "RaidSent", "RaidWon", "NextGoal" },' in _hook and 'FallbackWonName = "GoalFallbackWon"' in _hook,
     "the Hook's funnel steps 12-16 + the fallback win name")
_j48('[4] = { "ClaimBase", "CommandCenter", "Income", "RecruitSoldiers", "FirstFight", "Outpost", "Reward", "Barracks", "Jeep" },' in _TC
     and '"Reward", "RaidRival",\n\t\t\t"Barracks", "Jeep", "Missions" },' in _TC,
     "SavedOrders[4] unchanged; SavedOrders[5] = v4 + RaidRival after the reward + Missions last")
_steps = {}
for _id in ("RaidRival", "Missions"):
    _blk = _TC.split("\t%s = {" % _id)[1].split("\n\t},")[0] if ("\t%s = {" % _id) in _TC else ""
    _t = _j48_re.search(r'Title = "([^"]*)"', _blk)
    _h = _j48_re.search(r'Hint = "([^"]*)"', _blk)
    _steps[_id] = (_t.group(1) if _t else "", _h.group(1) if _h else "")
_ft = _j48_re.search(r'FallbackTitle = "([^"]*)"', _hook)
_fh = _j48_re.search(r'FallbackHint = "([^"]*)"', _hook)
_copy = list(_steps.values()) + [((_ft.group(1) if _ft else ""), (_fh.group(1) if _fh else ""))]
_j48(all(0 < len(t) <= 18 and 0 < len(h) <= 42 and not _j48_re.search(r"\b(click|press [A-Z]|key)\b", t + " " + h, _j48_re.I) for t, h in _copy),
     "every new banner: Title <= 18, Hint <= 42 characters, no key names, never 'click' (%s)" % _copy)
_AC = _j48_src(_CF + "AnalyticsConfig.luau")
_j48('SESSION_MILESTONE = { Name = "SessionMilestone"' in _AC and 'FTUE_TIME_TO_FIGHT = { Name = "FtueTimeToFight"' in _AC,
     "the custom events SessionMilestone / FtueTimeToFight are rows in AnalyticsConfig.Roblox.Custom")
_GS = _j48_code(_SV + "Services/GuidedService.luau")
for _ev in ("SESSION_MILESTONE", "FTUE_TIME_TO_FIGHT"):
    _j48('"%s"' % _ev in _GS, "GuidedService logs %s through AnalyticsService.Log (the custom path + budget)" % _ev)
_new = _GS + _j48_code(_SV + "Services/SoldierService.luau")
_j48(not _j48_re.search(r"PivotTo|TeleportToPlot|SetPrimaryPartCFrame|Humanoid\.Health\s*=|\.Health\s*=", _GS),
     "the Hook code never teleports / snaps a player or a soldier and never writes Humanoid health")
_j48("RivalService" in _GS and "Candidates" in _GS and "OnRaidWon" in _j48_code(_SV + "Modules/ArmyPlan.luau")
     and "OnRaidSent" in _j48_code(_SV + "Modules/ArmyCommand.luau"),
     "the raid goal reads the JOB 38 verdicts (RivalService.Candidates) and finishes on the real SEND / loot hooks")
_SS = _j48_code(_SV + "Services/SoldierService.luau")
_gf = _SS.split("function SoldierService.GrantFree")[1].split("\nend\n")[0] if "function SoldierService.GrantFree" in _SS else ""
_j48("maxSoldiers(profile) - current" in _gf and "SpendCash" not in _gf and "Robux" not in _gf,
     "RewardSoldiers goes through SoldierService.GrantFree: clamped to the army cap, free (no cash, no Robux)")
_MC = _j48_src(_CF + "MapConfig.luau")
_j48(_j48_re.search(r"FastTravelEnabled\s*=\s*false", _MC) is not None, "no fast travel (MapConfig.FastTravelEnabled = false)")
_j48(not _j48_re.search(r"RobuxPrice|ProductId|MarketplaceService|Prompt\w*Purchase", _hook + _GS + _gf),
     "no Robux in the chain: no RobuxPrice / product Id / purchase prompt in the Hook config, GuidedService or GrantFree")

_luau = _j48_os.environ.get("LUAU")
if _luau is None and _j48_os.environ.get("LUAU_COMPILE"):
    _c = _j48_os.environ["LUAU_COMPILE"].replace("luau-compile", "luau")
    _luau = _c if _j48_os.path.isfile(_c) else None
if _luau:
    _r = _j48_sp.run([_j48_sys.executable, "tools/sim/run_first_minutes_test.py"], capture_output=True, text=True, env=dict(_j48_os.environ, LUAU=_luau))
    _j48(_r.returncode == 0 and "FIRST MINUTES TEST: 0 failed" in _r.stdout and "HOOK TIMES" in _r.stdout,
         "run_first_minutes_test.py (v4 chain with the Hook OFF + the Hook: raid goal, fallback, cap, fast raid, migration, funnel)")
else:
    print("SKIP CLAUDE-BUD J48: Luau CLI tests (set LUAU)")
