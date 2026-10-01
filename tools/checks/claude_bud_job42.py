# claude-bud JOB 42 (2026-10-01): TIME-based cash packs (part A config + grant; B-D follow in this file).
# Static pins + the real-code tests (tools/sim/run_time_packs_test.py, ...).
import os as _j42_os
import re as _j42_re
import subprocess as _j42_sp
import sys as _j42_sys
from pathlib import Path as _J42P

if "ok" not in globals():
    _j42_fails = []

    def ok(msg):
        print("PASS " + msg)

    def bad(msg):
        _j42_fails.append(msg)
        print("FAIL " + msg)

if "read" not in globals():
    def read(p):
        q = _J42P(p)
        return q.read_text(encoding="utf-8") if q.is_file() else None


def _j42(cond, msg):
    (ok if cond else bad)("CLAUDE-BUD J42: " + msg)


def _j42_src(path):
    return (read(path) or "").replace("\r\n", "\n")


def _j42_code(path):
    s = _j42_re.sub(r"--\[\[.*?\]\]", "", _j42_src(path), flags=_j42_re.S)
    return "\n".join(l.split("--", 1)[0] for l in s.splitlines())


_SV = "src/ServerScriptService/Server/"
_CL = "src/StarterPlayer/StarterPlayerScripts/Client/"
_CF = "src/ReplicatedStorage/Shared/Configs/"

# ── part A: config + the server grant ──
_MC = _j42_src(_CF + "MonetizationConfig.luau")
_WANT = {"Cash15m": 25, "Cash30m": 49, "Cash1h": 89, "Cash2h": 159, "Cash4h": 279}
_rows = {}
for _k in _WANT:
    _m = _j42_re.search(r"\b" + _k + r" = \{ (.*?) \},", _MC)
    _rows[_k] = _m.group(1) if _m else ""
_j42(all(("Id = 0," in _rows[k] and ("RobuxPrice = %d," % p) in _rows[k] and "OneTime" not in _rows[k]) for k, p in _WANT.items()),
     "A: the five rows: Id 0, 25 / 49 / 89 / 159 / 279 R$, repeatable")
_j42(not any(_j42_re.search(r"(?i)damage|health|armou?r|army|raid|protect|shield", r) for r in _rows.values()), "A: cash only: no stat key in the new rows")
_SOC = _j42_src(_CF + "ShopOverhaulConfig.luau")
_tp = _SOC.split("TimePacks = {")[1].split("\n\t},")[0] if "TimePacks = {" in _SOC else ""
_j42("\t\tEnabled = true,\n\t\tOwnerFirst = true," in _tp and 'BestValueKey = "Cash4h",' in _tp and "ExcludeTimedBoosts = true," in _tp,
     "A: TimePacks Enabled + OwnerFirst = true; BEST VALUE on Cash4h; timed boosts left out")
_cash_keys = _j42_re.findall(r"\n\t\t(Cash\w+) = \{", _MC)
_titles = _j42_re.findall(r'Title = "([^"]+)"', _tp)
_mins = [int(x) for x in _j42_re.findall(r"Minutes = (\d+)", _tp)]
_names = [d for d in _j42_re.findall(r'DisplayName = "([^"]+)"', _MC) if "Cash" in d]
_j42(not any(m >= 1440 for m in _mins) and not any(_j42_re.search(r"1d|24h|7d|Day|Week", x) for x in _cash_keys + _names)
     and not any(_j42_re.search(r"DAY|WEEK", t) for t in _titles),
     "A: no 1-day / 7-day pack (no 1440 / 10080 minutes, no 1d / 24h / 7d / Day / Week in keys, names or titles)")
_MSV = _j42_code(_SV + "Services/MonetizationService.luau")
_rcpt = _MSV.split("local function processReceipt")[1] if "local function processReceipt" in _MSV else ""
_ti = _rcpt.find("ShopOverhaulConfig.TimePacks.Packs[productKey :: string] ~= nil")
_j42(_ti > 0 and _ti < _rcpt.find("EconomyService.AddCash(player, cashGrant") and
     "if not player.Parent or DataService.GetProfile(player) ~= profile then" in _rcpt[_ti:_ti + 600]
     and "ShopOverhaulConfig.TimePackAmount(productKey :: string, perMin)" in _rcpt,
     "A: ProcessReceipt: the time-pack income lookup sits before the first AddCash, followed by the player + profile re-check")
_j42("function MonetizationService.PassivePerMin(player: Player, profile: any, excludeTimed: boolean?)" in _MSV
     and _MSV.count("function MonetizationService.PassivePerMin") == 1, "A: ONE income function (the timed-boost exclusion is an option on it)")
_SOS = _j42_code(_SV + "Services/ShopOverhaulService.luau")
_j42("ShopOverhaulConfig.TimePacks.PerMinAttribute" in _SOS and _SOS.count("task.spawn(") <= 2 and "ShopOverhaulConfig.TimePacksLiveFor(p.UserId)" in _SOS,
     "A: WE_TimePackPerMin from the SAME publish tick, only where the time packs are live")
_old = {"CashSmall": ("3713838744", "49"), "CashMedium": ("3713838815", "149"), "CashLarge": ("3713838888", "399"), "CashMega": ("3713838952", "799")}
_j42(all(_j42_re.search(k + r" = \{ Id = " + i + r", .*RobuxPrice = " + p + r",", _MC) for k, (i, p) in _old.items()) and "RecruitPack = { Id = 0," in _MC and "RobuxPrice = 49," in _MC.split("RecruitPack = {")[1][:200],
     "A: the old four unchanged (Ids / prices), RecruitPack still Id 0 / 49")

_luau = _j42_os.environ.get("LUAU")
if _luau is None and _j42_os.environ.get("LUAU_COMPILE"):
    _cand = _j42_os.environ["LUAU_COMPILE"].replace("luau-compile", "luau")
    _luau = _cand if _j42_os.path.isfile(_cand) else None
if _luau:
    _r = _j42_sp.run([_j42_sys.executable, "tools/sim/run_time_packs_test.py"], capture_output=True, text=True, env=dict(_j42_os.environ, LUAU=_luau))
    _j42(_r.returncode == 0 and "TIME PACKS TEST: 0 failed" in _r.stdout, "A: run_time_packs_test.py (amounts, receipt order, gating)")
else:
    print("SKIP CLAUDE-BUD J42: Luau CLI tests (set LUAU)")
