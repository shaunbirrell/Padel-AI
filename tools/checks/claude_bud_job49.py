# claude-bud JOB 49 (2026-10-01): reasons to come back. A: the streak's grace / income-scaled Day 7 / real countdown;
# B: offline earnings + Welcome back (CapBoost hook disabled); C: 3 core daily missions + Raid + reroll (Robux hook
# disabled); D: one return sequence + analytics.
import os as _j49_os
import re as _j49_re
import subprocess as _j49_sp
import sys as _j49_sys
from pathlib import Path as _J49P

if "ok" not in globals():
    def ok(msg):
        print("PASS " + msg)

    def bad(msg):
        print("FAIL " + msg)

if "read" not in globals():
    def read(p):
        q = _J49P(p)
        return q.read_text(encoding="utf-8") if q.is_file() else None


def _j49(cond, msg):
    (ok if cond else bad)("CLAUDE-BUD J49: " + msg)


def _j49_src(path):
    return (read(path) or "").replace("\r\n", "\n")


def _j49_block(src, name):
    m = _j49_re.search(r"\b" + name + r" = \{(.*?)\n\t\},", src, _j49_re.S)
    return m.group(1) if m else ""


def _j49_fn(src, head):
    return src.split(head)[1].split("\nend\n")[0] if head in src else ""


_CF = "src/ReplicatedStorage/Shared/Configs/"
_SV = "src/ServerScriptService/Server/"

# ── A ──
_DR = _j49_src(_CF + "DailyRewardConfig.luau")
for _b in ("Grace", "Day7Scale", "Calendar"):
    _blk = _j49_block(_DR, _b)
    _j49("Enabled = true," in _blk and "OwnerFirst = false," in _blk, "A: DailyRewardConfig.%s is live for everyone (Enabled + OwnerFirst = false, codebot_v177 flip)" % _b)
_j49("MissedDaysAllowed = 1," in _j49_block(_DR, "Grace") and "PerCycle = 1," in _j49_block(_DR, "Grace"), "A: grace = 1 missed day per 7-day cycle")
_MS = _j49_src(_SV + "Services/MissionService.luau")
_claim = _j49_fn(_MS, "function MissionService.ClaimDailyLogin")
_j49("MissionService.GraceCovers(player, daily, os.time())" in _claim and "MissionService.Day7Cash(player, profile)" in _claim
     and "local today = yyyymmdd(os.time())" in _claim,
     "A: ClaimDailyLogin keys the day on the SERVER's UTC clock and applies grace / the scaled Day 7 there (nothing from the client)")
_d7 = _j49_fn(_MS, "function MissionService.Day7Cash")
_j49("MS.PassivePerMin, player, profile, true" in _d7 and "math.max(floorCash" in _d7,
     "A: Day 7 = max(the table floor, IncomeMinutes x the time-pack income formula, timed boosts excluded)")

# ── B ──
_EC = _j49_src(_CF + "EconomyConfig.luau")
_cb = _j49_block(_EC, "CapBoost")
# Code Bot v180 (Shaun approved 2026-10-01): the hook is live for everyone (was Enabled = false, OwnerFirst = true)
_j49("Enabled = true," in _cb and "OwnerFirst = false," in _cb and 'ProductKey = "OfflineCap2x"' in _cb and "CapMult = 2" in _cb,
     "B: the OfflineCap2x sidegrade is live for everyone (Code Bot v180), cap time x2 only")
_j49("Enabled = true," in _j49_block(_EC, "Card") and "OwnerFirst = false," in _j49_block(_EC, "Card"), "B: the Welcome back / COLLECT card is live for everyone (codebot_v177 flip)")
_MC = _j49_src(_CF + "MonetizationConfig.luau")
# Code Bot v180: both created + priced by Shaun (OfflineCap2x is a Game Pass); still no stat keys (sidegrades only)
_m = _j49_re.search(r"\n\t\tMissionReroll = \{([^\n]*)\}", _MC)
_row = _m.group(1) if _m else ""
_j49(_row.strip().startswith("Id = 3715836569,") and "RobuxPrice = 19," in _row and "HideFromShop = true" in _row
     and not _j49_re.search(r"Damage|Health|HP|Armou?r|Soldier|ArmyCap|Speed|Raid", _row),
     "B/C: DevProducts.MissionReroll = 3715836569, 19 R$, sold from Missions only, no stat keys (Code Bot v180)")
_m = _j49_re.search(r"\n\t\tOfflineCap2x = \{(.*?)\n\t\t\},", _MC, _j49_re.S)
_row = _m.group(1) if _m else ""
_j49("Id = 2002664894," in _row and "RobuxPrice = 149," in _row
     and not _j49_re.search(r"Damage|Health|HP|Armou?r|Soldier|ArmyCap|Speed|Raid|CashMult|XPMult", _row)
     and not _j49_re.search(r"\n\t\tOfflineCap2x = \{ Id", _MC),
     "B/C: GamePasses.OfflineCap2x = 2002664894, 149 R$, no stat keys; no Developer Product stub (Code Bot v180)")
_RS = _j49_src(_SV + "Services/RetentionService.luau")
_cs = _j49_fn(_RS, "local function capSecondsFor")
_j49("ownsCapBoost(player, profile, b.ProductKey or CAP_BOOST_PASS, fresh)" in _cs and "Share" not in _cs
     and "profile.Entitlements[key] == true" in _j49_fn(_RS, "local function ownsCapBoost"),
     "B: the cap boost only lengthens the cap time (never Share), and only with the pass (Code Bot v180) / entitlement")
_j49("os.time()" in _j49_fn(_RS, "local function onLoadOffline") and "profile.PrevSeenUnix = nil" in _RS,
     "B: offline time is the server's os.time() vs the saved LastSeen, paid once per load")

# ── C ──
_MCF = _j49_src(_CF + "MissionConfig.luau")
_core = _MCF.split("\tCore = {")[1].split("\n\t},\n\n")[0] if "\tCore = {" in _MCF else ""
# Code Bot v182 (Shaun approved 2026-10-01): launched for everyone (was OwnerFirst = true, -- NEW-OWNER-FIRST)
_j49("Enabled = true," in _core and "OwnerFirst = false, -- Code Bot v182" in _core and "Count = 3," in _core and "ResetHourUtc = 0," in _core,
     "C: MissionConfig.Core is live for everyone (Code Bot v182), 3 a day, reset at 00:00 UTC by default")
_j49("Robux = { Enabled = true, OwnerFirst = false, ProductKey = \"MissionReroll\" }" in _core and "FreePerDay = 1," in _core,
     "C: 1 free reroll a day; then the 19 R$ Robux reroll (Code Bot v180: live)")
_j49("Raid = true," in _MCF.split("LiveObjectives = {")[1].split("}")[0], "C: Raid is a live ObjectiveType")
_AP = _j49_src(_SV + "Modules/ArmyPlan.luau")
_MCS = _j49_src(_SV + "Services/MoneyCollectorService.luau")
_j49('TrackProgress(player, "Raid", 1)' in _AP and 'TrackProgress(thief, "Raid", 1)' in _MCS,
     "C: Raid progress comes from the SAME two raid-win hooks (ArmyPlan SEND loot, MoneyCollectorService ATM raid)")
_rr = _j49_fn(_MS, "function MissionService.Reroll(")
_j49("RemoteGuard.IsIdString(missionId, 48)" in _rr and "AddCash" not in _rr and "NoRerolls" in _rr,
     "C: the reroll takes only a mission id, checks everything on the server, and never pays")
_SC = _j49_src(_CF + "SecurityConfig.luau")
_j49('RequestMissionReroll = { "string:48" }' in _SC, "C: RequestMissionReroll's schema = one short string (no client time / amount)")
_MON = _j49_src(_SV + "Services/MonetizationService.luau")
_j49("GrantsMissionReroll == true" in _MON and "GrantRerollToken(player)" in _MON, "C: the Robux reroll grant exists in ProcessReceipt (one token per receipt)")

# ── D ──
_RCF = _j49_src(_CF + "RetentionConfig.luau")
_rsq = _j49_block(_RCF, "ReturnSequence")
# Code Bot v182 (Shaun approved 2026-10-01): launched for everyone (was OwnerFirst = true, -- NEW-OWNER-FIRST)
_j49("Enabled = true," in _rsq and "OwnerFirst = false, -- Code Bot v182" in _rsq, "D: RetentionConfig.ReturnSequence is live for everyone (Code Bot v182)")
_RCC = _j49_src("src/StarterPlayer/StarterPlayerScripts/Client/Controllers/RetentionController.luau")
_j49("enqueueCard(1," in _RCC and "enqueueCard(2," in _RCC and "enqueueCard(3," in _RCC and 'player:GetAttribute("WE_Onboarding") == true' in _RCC,
     "D: one card queue (Welcome back, streak, missions toast), never during the onboarding hold")
_ENG = _j49_src(_SV + "Services/EngagementService.luau")
_j49('player:SetAttribute("WE_ComebackCash", E.ComebackCash)' in _ENG, "D: the Comeback cash folds into the Welcome back card while the sequence is live")
for _row in ("STREAK_CLAIMED", "STREAK_RESET", "OFFLINE_COLLECTED", "MISSION_DONE", "MISSIONS_ALL_DONE", "MISSION_REROLL", "RETURN_DAY"):
    _j49(_row + " = { Name = " in _j49_src(_CF + "AnalyticsConfig.luau"), "D: analytics row " + _row)

#@@C@@

_luau = _j49_os.environ.get("LUAU")
if _luau is None and _j49_os.environ.get("LUAU_COMPILE"):
    _c = _j49_os.environ["LUAU_COMPILE"].replace("luau-compile", "luau")
    _luau = _c if _j49_os.path.isfile(_c) else None
if _luau:
    _r = _j49_sp.run([_j49_sys.executable, "tools/sim/run_daily_return_test.py"], capture_output=True, text=True, env=dict(_j49_os.environ, LUAU=_luau))
    _j49(_r.returncode == 0 and "DAILY RETURN TEST: 0 failed" in _r.stdout, "run_daily_return_test.py (real MissionService / RetentionService on a fake UTC clock)")
else:
    print("SKIP CLAUDE-BUD J49: Luau CLI tests (set LUAU)")
