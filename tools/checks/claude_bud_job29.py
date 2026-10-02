# claude-bud JOB 29 (2026-09-30): retention. FastStart (first minute), offline earnings, streak visibility + day-7 boost,
# experience-notification opt-in + the sender state. Static pins + the offline payout test (the real ComputeOffline).
import os as _j29_os
import re as _j29_re
import subprocess as _j29_sp
import sys as _j29_sys
from pathlib import Path as _J29P

if "ok" not in globals():
    _j29_fails = []

    def ok(msg):
        print("PASS " + msg)

    def bad(msg):
        _j29_fails.append(msg)
        print("FAIL " + msg)

if "read" not in globals():
    def read(p):
        q = _J29P(p)
        return q.read_text(encoding="utf-8") if q.is_file() else None


def _j29(cond, msg):
    (ok if cond else bad)("CLAUDE-BUD J29: " + msg)


def _j29_src(path):
    return (read(path) or "").replace("\r\n", "\n")


def _j29_code(path):
    return "\n".join(l.split("--", 1)[0] for l in _j29_src(path).splitlines())


_TC = _j29_src("src/ReplicatedStorage/Shared/Configs/TutorialConfig.luau")
_EC = _j29_src("src/ReplicatedStorage/Shared/Configs/EconomyConfig.luau")
_DC = _j29_src("src/ReplicatedStorage/Shared/Configs/DailyRewardConfig.luau")
_RC = _j29_src("src/ReplicatedStorage/Shared/Configs/RetentionConfig.luau")
_RS = _j29_code("src/ServerScriptService/Server/Services/RetentionService.luau")
_RSX = _j29_src("src/ServerScriptService/Server/Services/RetentionService.luau")
_BS = _j29_code("src/ServerScriptService/Server/Services/BaseService.luau")
_DS = _j29_code("src/ServerScriptService/Server/Services/DataService.luau")
_MS = _j29_code("src/ServerScriptService/Server/Services/MissionService.luau")
_TS = _j29_code("src/ServerScriptService/Server/Services/TutorialService.luau")
_AS = _j29_code("src/ServerScriptService/Server/Services/AnalyticsService.luau")
_SO = _j29_code("src/ServerScriptService/Server/Services/SquadOrdersService.luau")
_NC = _j29_code("src/StarterPlayer/StarterPlayerScripts/Client/Controllers/NationController.luau")
_MC = _j29_code("src/StarterPlayer/StarterPlayerScripts/Client/Controllers/MissionController.luau")

# ── kill switches + owner-first (RetentionConfig.Live: Enabled, OwnerFirst) ──────────────────────────────────────────
_OWN = "OwnerFirst = false, -- codebot_v136 launch"  # v136 (Code Bot Roblox): was "OwnerFirst = true, -- only UserId 470626172"; launched for everyone, superseded in tools/checks/codebot_v136.py
_j29("TutorialConfig.FastStart = {\n\tEnabled = true,\n\t" + _OWN in _TC, "kill switch TutorialConfig.FastStart.Enabled, owner-first")
# Code Bot (Shaun 2026-10-01, offline cap): retired, superseded in tools/checks/codebot_v201.py (OfflineConfig MaxSeconds 7200 / Rate 0.10): #_j29(... "\t\tShare = 0.25,\n\t\tCapSeconds = 8 * 3600," in _EC, "... 25 % of income, capped at 8 h")
_OFC = _j29_code("src/ReplicatedStorage/Shared/Configs/OfflineConfig.luau")
_j29("\tOfflineEarnings = {\n\t\tEnabled = true,\n\t\t" + _OWN in _EC and "MaxSeconds = 7200," in _OFC and "Rate = 0.10," in _OFC,
     "kill switch EconomyConfig.OfflineEarnings.Enabled; OfflineConfig: 10 % of income, capped at 2 h")
_j29("DoubleWithRobux" not in _EC and "ProductId" not in _EC[_EC.find("OfflineEarnings = {"):], "no Robux option on offline earnings (no new Robux items)")
_j29("\tShowTomorrow = true,\n\tStreakCard = {\n\t\tEnabled = true,\n\t\t" + _OWN in _DC and "Day7Boost = { Enabled = true," in _DC,
     "kill switch DailyRewardConfig.ShowTomorrow; streak card + day-7 boost owner-first (no Robux)")
_j29(_OWN in _RC and "NotBeforeSeconds = 60," in _RC and "DeclineCooldownDays = 7," in _RC and "MaxPerDay = 1," in _RC
     and "Moments = { TutorialComplete = true }" in _RC, "notification opt-in: after the tutorial only, never first 60 s, 7 days after a decline")
_j29("if block.OwnerFirst ~= true then" in _RC and "IsPlaytestOwner(userId)" in _RC, "OwnerFirst = the owner (+ Studio) only")
_m = _j29_re.search(r'WelcomeText = "([^"]*)"', _TC[_TC.find("TutorialConfig.FastStart = {"):])
_j29(_m is not None and len(_m.group(1)) <= 42 and not _j29_re.search(r"\b(click|key|keyboard|mouse)\b", _m.group(1), _j29_re.I),
     "FastStart welcome hint <= 42 characters, device-neutral")

# ── FastStart ─────────────────────────────────────────────────────────────────────────────────────────────────────
_j29("RS :: any).FastStartCFrame, player, profile, plotId)" in _BS, "the join teleport asks RetentionService for the FastStart spot (nil = the old plot spawn)")
_j29('ConsoleLocator.Find(plotId, "CommandCenter")' in _RS and "not isNewPlayer(profile)" in _RS and "TutorialConfig.FastStartLiveFor(player.UserId)" in _RS,
     "FastStart only for a new player (Command Center not bought, tutorial not done) at HIS plot's console")
_j29('profile.StarterPayoutDone == true or profile.TutorialComplete == true' in _RS and 'EconomyService.AddCash(player, amount, "onboarding")' in _RS,
     "the starter payout is server-side, once per profile, only during the tutorial")
_j29("retentionStep(player, step, complete == true)" in _TS and "setHold(player, false)" in _RS and "HoldMaxSeconds" in _RS,
     "the onboarding hold (WE_Onboarding) ends after the Command Center step or HoldMaxSeconds")
_j29('player:GetAttribute("WE_Onboarding") == true' in _NC, "the nation picker waits for the onboarding hold")
# claude-bud JOB 49 A: retired the literal 90 s (Calendar waits up to FirstCardSeconds; OFF keeps 90). Replacement:
_j29("RS.WaitOnboarding(player, holdMax)" in _MS and "local holdMax = 90" in _MS, "the daily-streak card waits for the onboarding hold (90 s, or Calendar's FirstCardSeconds)")
# ── offline earnings ──────────────────────────────────────────────────────────────────────────────────────────────
_j29("(profile :: any).LastSeenUnix = os.time()" in _DS and "(profile :: any).PrevSeenUnix = (profile :: any).LastSeenUnix" in _DS,
     "LastSeenUnix (os.time) stamped on every save; the load keeps the previous one for the payout")
_PS = _j29_src("src/ServerScriptService/Server/Modules/ProfileSchema.luau")
_j29("profile.LastSeenUnix = nonNegInt(profile.LastSeenUnix)" in _PS, "LastSeenUnix is an additive, migrated profile field")
# Code Bot (Shaun 2026-10-01, offline cap): retired, superseded in tools/checks/codebot_v201.py (OfflineConfig MaxSeconds 7200 / Rate 0.10): #_j29(... "local counted = math.min(away, math.max(0, tonumber(o.CapSeconds) or 0))" in _RS ...)
_j29("if prevSeen <= 0 or perSec <= 0" in _RS and "return OfflineConfig.Earnings(away, perSec, cap, mult)" in _RS and "return math.min(away, cap)" in _OFC,
     "first join pays nothing; the cap is enforced (OfflineConfig.Earnings)")
_j29('BaseService.ComputePassiveIncomePerTick, profile, player)' in _RS and 'EconomyService.GetCashMult, player, "passive")' in _RS,
     "same formula as the live passive tick (per-tick income x the passive cash multiplier)")
_j29('EconomyService.AccruePendingCash(player, cash, "offline")' in _RS and 'push(player, "WelcomeBack"' in _RS and "profile.PrevSeenUnix = nil" in _RS,
     "paid once into PendingCash, then the Welcome back card")
_MON = _j29_src("src/ReplicatedStorage/Shared/Configs/MonetizationConfig.luau")
_j29("\t\toffline = true," in _MON and "\t\tonboarding = true," in _MON, "offline / onboarding pay are never multiplied twice")
# ── streak + boost ────────────────────────────────────────────────────────────────────────────────────────────────
_j29('(ev :: RemoteEvent):FireClient(player, "Streak", strip)' in _MS and "MissionService.ClaimDailyLogin(player, card)" in _MS,
     "one streak card (7-day strip + tomorrow) instead of two toasts")
_j29("Tomorrow: $%s" in _j29_src("src/ServerScriptService/Server/Services/MissionService.luau") and "Tomorrow $%s" in _j29_src("src/StarterPlayer/StarterPlayerScripts/Client/Controllers/MissionController.luau"),
     "tomorrow's reward shown wherever the streak is (toast, Missions daily row)")
_j29("(payload :: any).Streak7 = strip" in _MS and "Streak7Row" in _MC, "the Missions panel shows the strip and the tomorrow goals")
_j29("* armyBoostMult(player)" in _SO and 'player:SetAttribute("WE_ArmyBoostUntil", untilUnix)' in _MS, "day 7 = army damage boost (server)")
# ── notifications ─────────────────────────────────────────────────────────────────────────────────────────────────
_j29("promptedThisSession[uid] or RetentionService.IsOnboarding(player)" in _RS and "(tonumber(N.DeclineCooldownDays) or 7) * 86400" in _RS
     and 'n.Result == "accepted"' in _RS and 'RetentionService.GoodMoment(player, "TutorialComplete")' in _RS,
     "opt-in after the tutorial: once a session, never during onboarding, 7 days after a decline, never after accept")
_NO = _j29_code("src/StarterPlayer/StarterPlayerScripts/Client/Modules/NotifOptIn.luau")
_j29("svc:CanPromptOptInAsync()" in _NO and "svc:PromptOptIn()" in _NO and "RequestNotifOptInResult" in _NO
     and 'NotifOptIn).Ask("settings")' in _j29_code("src/StarterPlayer/StarterPlayerScripts/Client/Controllers/SettingsController.luau"),
     "one client opt-in path (ExperienceNotificationService), also from Settings")
_j29("DataStoreService:GetDataStore(RetentionConfig.Notifications.StateStore)" in _RS and 'n.Result ~= "accepted"' in _RS,
     "the sender state is written on leave, only for players who opted in")
_ND = read("docs/NOTIFICATIONS.md") or ""
_j29("{day}" in _ND and "Creator Hub" in _ND and "We will not notify" in _ND, "docs/NOTIFICATIONS.md: Creator Hub steps, templates, what we will / won't notify")
# ── funnel (the SAME AnalyticsConfig.Roblox.Funnel, extended) ─────────────────────────────────────────────────────────
_AC = _j29_src("src/ReplicatedStorage/Shared/Configs/AnalyticsConfig.luau")
# v183 / JOB 61: one Roblox.Funnel with the eight first-session steps (legacy STEP:* names retired)
_j29(_AC.count("Funnel = {") == 1 and 'Step = "joined"' in _AC and 'Step = "base_claimed"' in _AC and 'Step = "reached_5_minutes"' in _AC,
     "one funnel, extended with the onboarding steps")
_j29('pcall(funnel, player, "STEP:" .. m.Step)' in _AS and 'onboard(player, if doneDef.Id == "ClaimBase" then "BaseClaimed" else "Tut_" .. doneDef.Id)' in _TS
     and 'AnalyticsService.Onboard, player, "CharacterSpawned")' in _RS, "every onboarding step fires the funnel at the real moment")
_j29("GiveCash" not in _RSX and "GiveXP" not in _RSX, "no GiveCash / GiveXP remotes")

# ── the offline payout test (the real function, Luau CLI) ─────────────────────────────────────────────────────────
_luau = _j29_os.environ.get("LUAU")
if _luau is None and _j29_os.environ.get("LUAU_COMPILE"):
    _cand = _j29_os.environ["LUAU_COMPILE"].replace("luau-compile", "luau")
    _luau = _cand if _j29_os.path.isfile(_cand) else None
if _luau:
    _r = _j29_sp.run([_j29_sys.executable, "tools/sim/run_offline_test.py"], capture_output=True, text=True, env=dict(_j29_os.environ, LUAU=_luau))
    _j29(_r.returncode == 0 and "OFFLINE TEST: 0 case(s) failed" in _r.stdout, "offline payout cases (first join / negative / +2 h / +20 h cap / Premium)")
else:
    print("SKIP CLAUDE-BUD J29: offline payout test (no luau CLI: set LUAU)")
