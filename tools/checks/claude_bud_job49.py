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
_j49("Enabled = false," in _cb and "OwnerFirst = true," in _cb and 'ProductKey = "OfflineCap2x"' in _cb and "CapMult = 2" in _cb,
     "B: the OfflineCap2x sidegrade hook is DISABLED (Enabled = false, OwnerFirst = true), cap time x2 only")
_j49("Enabled = true," in _j49_block(_EC, "Card") and "OwnerFirst = false," in _j49_block(_EC, "Card"), "B: the Welcome back / COLLECT card is live for everyone (codebot_v177 flip)")
_MC = _j49_src(_CF + "MonetizationConfig.luau")
for _k in ("OfflineCap2x", "MissionReroll"):
    _m = _j49_re.search(r"\n\t\t" + _k + r" = \{([^\n]*)\}", _MC)
    _row = _m.group(1) if _m else ""
    _j49(_row.strip().startswith("Id = 0,") and "RobuxPrice" not in _row and "HideFromShop = true" in _row
         and not _j49_re.search(r"Damage|Health|HP|Armou?r|Soldier|ArmyCap|Speed|Raid", _row),
         "B/C: DevProducts.%s = Id 0, NO price, hidden, no stat keys (never prompted until Shaun approves a price)" % _k)
_RS = _j49_src(_SV + "Services/RetentionService.luau")
_cs = _j49_fn(_RS, "local function capSecondsFor")
_j49("profile.Entitlements[b.ProductKey] == true" in _cs and "Share" not in _cs,
     "B: the cap boost only lengthens the cap time (never Share), and only with the entitlement")
_j49("os.time()" in _j49_fn(_RS, "local function onLoadOffline") and "profile.PrevSeenUnix = nil" in _RS,
     "B: offline time is the server's os.time() vs the saved LastSeen, paid once per load")

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
