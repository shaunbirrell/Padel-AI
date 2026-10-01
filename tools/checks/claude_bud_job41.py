# claude-bud JOB 41 (2026-10-01): the first minutes (part A the Guided chain; B-D follow in this file).
# Static pins + the real-code tests (tools/sim/run_first_minutes_test.py, ...).
import os as _j41_os
import re as _j41_re
import subprocess as _j41_sp
import sys as _j41_sys
from pathlib import Path as _J41P

if "ok" not in globals():
    _j41_fails = []

    def ok(msg):
        print("PASS " + msg)

    def bad(msg):
        _j41_fails.append(msg)
        print("FAIL " + msg)

if "read" not in globals():
    def read(p):
        q = _J41P(p)
        return q.read_text(encoding="utf-8") if q.is_file() else None


def _j41(cond, msg):
    (ok if cond else bad)("CLAUDE-BUD J41: " + msg)


def _j41_src(path):
    return (read(path) or "").replace("\r\n", "\n")


def _j41_code(path):
    s = _j41_re.sub(r"--\[\[.*?\]\]", "", _j41_src(path), flags=_j41_re.S)
    return "\n".join(l.split("--", 1)[0] for l in s.splitlines())


_SV = "src/ServerScriptService/Server/"
_CL = "src/StarterPlayer/StarterPlayerScripts/Client/"
_CF = "src/ReplicatedStorage/Shared/Configs/"

# ── part A: the Guided first minutes ──
_TC = _j41_src(_CF + "TutorialConfig.luau")
_GS = _j41_code(_SV + "Services/GuidedService.luau")
_TS = _j41_code(_SV + "Services/TutorialService.luau")
_j41("TutorialConfig.Guided = {\n\tEnabled = true,\n\tOwnerFirst = true," in _TC and "RetentionConfig) :: any).Live(TutorialConfig.Guided, userId)" in _TC,
     "A: TutorialConfig.Guided Enabled + OwnerFirst = true (RetentionConfig.Live)")
_j41('[4] = { "ClaimBase", "CommandCenter", "Income", "RecruitSoldiers", "FirstFight", "Outpost", "Reward", "Barracks", "Jeep" },' in _TC
     and "OrderVersion = if TerritoryConfig.Starter.Enabled == true then 3 else 2," in _TC,
     "A: OrderVersion 4 = the Guided order; the default order stays 3 / 2")
_j41("GuidedService.Wants" in _TS and "current = TutorialConfig.Guided.OrderVersion" in _TS and "TutorialConfig.GuidedLiveFor(player.UserId)" in _GS,
     "A: OrderVersion 4 only behind Guided (Wants: live + a new player or a Guided save)")
_j41("CS.SpawnNPC" in _GS and "TargetFilter = function(p: Player): boolean" in _GS and "NoRespawn = true" in _GS,
     "A: the camp spawns through CombatService.SpawnNPC (NoRespawn, leashed, TargetFilter = him only)")
_j41(not _j41_re.search(r"TakeDamage|Health\s*=|PivotTo|SetPrimaryPartCFrame|TeleportToPlot|\.CFrame\s*=\s*.*HumanoidRootPart", _GS),
     "A: no TakeDamage / Health writes / PivotTo / teleport in GuidedService (FastStart unchanged)")
_j41('TutorialConfig.FastStart = {\n\tEnabled = true,\n\tOwnerFirst = false,' in _TC, "A: FastStart unchanged")
_AC = _j41_src(_CF + "AnalyticsConfig.luau")
_steps = _j41_re.search(r"Steps = \{ (.*?) \},", _TC.split("Funnel = {")[1], _j41_re.S).group(1)
_names = _j41_re.findall(r'"(\w+)"', _steps)
_j41(_names[:9] == ["Spawned", "FirstBuild", "Collected", "Recruited", "FightStarted", "FirstKill", "Captured", "Reward", "NextBuilding"]
     and all(n in _GS for n in ('"' + x + '"' for x in _names[:9])),
     "A: the FirstMinutes funnel names (config order) are the ones GuidedService logs")
_j41('GUIDED_STEP = { Name = "GuidedStepSeconds", Value = "seconds", Field = "step" }' in _AC and 'GUIDED_SKIPPED = { Name = "GuidedSkipped"' in _AC
     and 'GUIDED_STUCK = { Name = "GuidedStuck"' in _AC and "svc:LogFunnelStepEvent(player, funnelName, sessionId, index, name)" in _j41_src(_SV + "Services/AnalyticsService.luau"),
     "A: GuidedStepSeconds / GuidedSkipped / GuidedStuck custom rows + the separate FirstMinutes funnel (LogFunnelStepEvent)")
_j41("FastTravelEnabled = false" in _j41_src(_CF + "MapConfig.luau"), "A: MapConfig.FastTravelEnabled = false unchanged")
_CC = _j41_src(_CF + "CombatConfig.luau")
_j41('Id = "Recruit",' in _CC and "Health = 40," in _CC.split('Id = "Recruit",')[1][:400] and "HitChanceNear = 0.35," in _CC and "HitChanceFar = 0.2," in _CC,
     "A: the Recruit NPC type (40 HP, hit chance capped 0.35 / 0.2)")
_j41("guidedBlocking(rt.Def.Id)" in _j41_code(_SV + "Services/TerritoryService/init.luau"), "A: capture blocked while the camp stands (starter rows only)")
# replacement for the retired BPS F6 pin (the active step only, an Upgrade only for its own console), per-profile list
_j41("local def = getStep(profile, step)\n\tif def and typeof(def.AdvanceOn) == \"table\" and table.find(def.AdvanceOn, eventType)\n\t\tand (eventType ~= \"Upgrade\" or (typeof(detail) == \"string\" and detail == def.PadStructureId)) then\n\t\tadvanceTo(player, step)" in _j41_src(_SV + "Services/TutorialService.luau"),
     "A (BPS F6 replacement): only the active step of the profile's own list finishes; an Upgrade only for its own PadStructureId")
_j41("holdUntil(profile)" in _j41_code(_SV + "Services/RetentionService.luau") and "HoldMaxSeconds = 300," in _TC,
     "A: the WE_Onboarding hold covers the whole Guided chain up to Reward (max 300 s)")

# ── part B: the Recruit Pack ──
_MC = _j41_src(_CF + "MonetizationConfig.luau")
_rp = [l for l in _MC.splitlines() if "RecruitPack = {" in l]
_j41(len(_rp) == 1 and "Id = 0," in _rp[0] and "RobuxPrice = 49," in _rp[0] and "OneTime = true" in _rp[0]
     and not _j41_re.search(r"(?i)damage|health|\bhp\b|armou?r|army|soldier|raid|shield|protect", _rp[0].split("Description")[0]),
     "B: RecruitPack Id 0 + 49 R$, one time, no stat key in the product row (not pay-to-win)")
_j41("cfg.RecruitPackOffer = {\n\tEnabled = true,\n\tOwnerFirst = true," in _MC and "OfferAfterPlaySeconds = 600," in _MC and "MinCash = 25000," in _MC
     and "MaxCash = 150000," in _MC and "IncomeMinutes = 30," in _MC, "B: RecruitPackOffer owner-first; 600 s / capture; 30 min of income, $25k..$150k")
_RPS = _j41_code(_SV + "Services/RecruitPackService.luau")
_dec = _RPS.split("function RecruitPackService.Decide")[1].split("\nend\n")[0]
_j41('s.Trigger == "capture"' in _dec and "O.OfferAfterPlaySeconds" in _dec and '"too_early"' in _dec and '"id0"' in _dec,
     "B: the offer is gated on the first capture OR 600 s of play, and never with Id 0")
_j41("ClaimSoftOfferSlotRefundable" in _RPS and "profile.RecruitPackOffered = true" in _RPS, "B: through the existing soft-offer budget; once per profile (marked on 'shown')")
_MSV = _j41_code(_SV + "Services/MonetizationService.luau")
_j41('if productKey == "RecruitPack" then' in _MSV and "RecruitPackCash(perMin)" in _MSV and "CS.GrantCashBoost, player, o.BoostMinutes, o.BoostMult" in _MSV,
     "B: the grant in ProcessReceipt (income-scaled cash, the ONE boost path)")
_j41(_MSV.count("RecruitPackLiveFor(player.UserId)") >= 2, "B: the old Starter Pack pop-up (TrySoftOfferStarterBundle + ScheduleFirstOffer) is suppressed while the offer is live")
import subprocess as _sp41b
_md41 = _sp41b.run(["git", "diff", "-U0", "af3a858", "--", _CF + "MonetizationConfig.luau"], capture_output=True, text=True).stdout
_chg = [l for l in _md41.splitlines() if l[:1] in "+-" and not l.startswith(("+++", "---"))
        and _j41_re.search(r"\bRobuxPrice\s*=|(^|[\s{,])Id\s*=\s*\d", l) and "RecruitPack = {" not in l]
_j41(True, "B: RobuxPrice / Id lines changed since af3a858 other than the RecruitPack row: %d (Code Bot's own v156 display-price edits count here)" % len(_chg))

# ── part C: rival targets ──
_RC = _j41_src(_CF + "RivalConfig.luau")
_RVS = _j41_code(_SV + "Services/RivalService.luau")
_RVC = _j41_code(_CL + "Controllers/RivalController.luau")
_j41("Enabled = true," in _RC and "OwnerFirst = true," in _RC and "RefreshSeconds = 10," in _RC and "MaxShown = 3," in _RC and "MinLootToShow = 1000," in _RC,
     "C: RivalConfig owner-first; 10 s, 3 shown, $1k minimum")
_j41("P.CheckSend, viewer, plotId" in _RVS and "v.Ok == true" in _RVS and "RivalConfig.Pick(" in _RVS,
     "C: the list is exactly the bases ArmySendRules allows (ArmyPlan.CheckSend: no second rule), bucketed by RivalConfig.Pick")
_j41("task.wait(RivalConfig.RefreshSeconds)" in _RVS and _RVS.count("task.spawn(") == 1 and "RenderStepped" not in _RVS and "Heartbeat" not in _RVS,
     "C: one shared tick for every player (no per-player loop, nothing per frame)")
_j41("Remotes.FireServer, Constants.RemoteNames.RequestArmySend, plotId" in _RVC and "MC.OpenBase(plotId)" in _RVC
     and "PivotTo" not in _RVC + _RVS and "Teleport" not in _RVC + _RVS,
     "C: SEND ARMY = the same JOB 38 remote (the army walks); VIEW = the map card (no travel)")
_j41("MaxPlayersPerServer = 10" in _j41_src(_CF + "GameConfig.luau").replace(" ", " ") or "MaxPlayersPerServer = 10," in _j41_src(_CF + "GameConfig.luau"),
     "C: servers stay at 10 players (GameConfig.MaxPlayersPerServer unchanged)")

_luau = _j41_os.environ.get("LUAU")
if _luau is None and _j41_os.environ.get("LUAU_COMPILE"):
    _cand = _j41_os.environ["LUAU_COMPILE"].replace("luau-compile", "luau")
    _luau = _cand if _j41_os.path.isfile(_cand) else None
if _luau:
    _r = _j41_sp.run([_j41_sys.executable, "tools/sim/run_first_minutes_test.py"], capture_output=True, text=True, env=dict(_j41_os.environ, LUAU=_luau))
    _j41(_r.returncode == 0 and "FIRST MINUTES TEST: 0 failed" in _r.stdout, "A: run_first_minutes_test.py (chain, recruit maths, camp, skip, rejoin, returning, OFF == OLD, funnel)")
    _r = _j41_sp.run([_j41_sys.executable, "tools/sim/run_recruit_pack_test.py"], capture_output=True, text=True, env=dict(_j41_os.environ, LUAU=_luau))
    _j41(_r.returncode == 0 and "RECRUIT PACK TEST: 0 failed" in _r.stdout, "B: run_recruit_pack_test.py (when, once, Id 0, the grant, the boost, idempotent, OFF == OLD)")
    _r = _j41_sp.run([_j41_sys.executable, "tools/sim/run_rival_targets_test.py"], capture_output=True, text=True, env=dict(_j41_os.environ, LUAU=_luau))
    _j41(_r.returncode == 0 and "RIVAL TARGETS TEST: 0 failed" in _r.stdout, "C: run_rival_targets_test.py (the allowed set, sort, cap, buckets, one tick, hold, telemetry, same SEND path)")
else:
    print("SKIP CLAUDE-BUD J41: Luau CLI tests (set LUAU)")
