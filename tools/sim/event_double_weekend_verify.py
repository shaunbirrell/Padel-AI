#!/usr/bin/env python3
"""DOUBLE WEEKEND (EventConfig DoubleWeekend1) verification: runs the REAL EventConfig.luau + Modules/DoubleEvent.luau
under the luau CLI with a fake server clock (before / during / after the window, one long-running module instance, no
re-init), composes them with the real EconomyService exempt lists the way cashMultFor / XPService.AddXP do, and models
MonetizationService.PassivePerMin (the income-scaled payouts) as written. Prints PASS/FAIL per check; exit 1 on FAIL."""
import os, re, subprocess, sys, tempfile, datetime

ROOT = os.environ.get("WE_ROOT") or os.path.abspath(os.path.join(os.path.dirname(__file__), "..", ".."))
LUAU = os.environ.get("LUAU", os.path.expanduser("~/.local/bin/luau"))
P = lambda *a: os.path.join(ROOT, *a)
src = lambda p: open(P(p), encoding="utf-8").read()

EC = src("src/ReplicatedStorage/Shared/Configs/EventConfig.luau")
DE = src("src/ServerScriptService/Server/Modules/DoubleEvent.luau")
ECO = src("src/ServerScriptService/Server/Services/EconomyService.luau")
MC = src("src/ReplicatedStorage/Shared/Configs/MonetizationConfig.luau")
MS = src("src/ServerScriptService/Server/Services/MonetizationService.luau")
BR = src("src/ServerScriptService/Server/Services/BankRaidService.luau")
POIL = src("src/ServerScriptService/Server/Services/PlotOilPumpService.luau")
POILC = src("src/ReplicatedStorage/Shared/Configs/PlotOilPumpConfig.luau")

def keyset(text, name):
    m = re.search(name + r"[^{]*\{(.*?)\n\s*\}", text, re.S)
    assert m, name
    return sorted(set(re.findall(r"^\s*([A-Za-z_][A-Za-z0-9_]*)\s*=\s*true", m.group(1), re.M)))

never = keyset(ECO, r"local NEVER_MULTIPLIED")
cashExempt = keyset(MC, r"CashMultExemptReasons = ")
xpExempt = keyset(MC, r"XPMultExemptReasons = ")
extra = keyset(EC, r"ExtraCashReasons = ") if "ExtraCashReasons" in EC else []
lua_set = lambda xs: "{" + ",".join(f"[{x!r}]=true".replace("'", '"') for x in xs) + "}"

# --- 1. static facts --------------------------------------------------------------------------------------------
results = []
def check(name, ok, detail=""):
    results.append((name, ok)); print(("PASS " if ok else "FAIL ") + name + (f"  [{detail}]" if detail else ""))

start = int(re.search(r"StartUnix = (\d+)", EC).group(1)); end = int(re.search(r"EndUnix = (\d+)", EC).group(1))
u = lambda t: datetime.datetime.fromtimestamp(t, datetime.timezone.utc)
try:
    from zoneinfo import ZoneInfo; d = lambda t: u(t).astimezone(ZoneInfo("Europe/Dublin"))
    check("StartUnix = Fri 2 Oct 2026 21:00 Dublin", d(start).strftime("%a %Y-%m-%d %H:%M %Z") == "Fri 2026-10-02 21:00 IST", d(start).isoformat())
    check("EndUnix = Sun 4 Oct 2026 21:00 Dublin", d(end).strftime("%a %Y-%m-%d %H:%M %Z") == "Sun 2026-10-04 21:00 IST", d(end).isoformat())
except Exception:
    check("StartUnix = 2026-10-02 20:00 UTC", u(start).isoformat() == "2026-10-02T20:00:00+00:00")
    check("EndUnix = 2026-10-04 20:00 UTC", u(end).isoformat() == "2026-10-04T20:00:00+00:00")
check("DoubleEvent reads os.time() (server clock), no cached on/off state", "os.time()" in DE and "ActiveFor((player :: Player).UserId, os.time()" in DE)
check("cashMultFor applies DE only inside the non-exempt branch", re.search(r"if not isExempt then.*?DE\.CashMult\(player, reason\).*?\n\tend\n\treturn mult", ECO, re.S) is not None)
check("CollectPendingCash adds no multiplier (pending was multiplied at accrue)",
      "applyCashMult" not in re.search(r"function EconomyService.CollectPendingCash.*?\nend\n", ECO, re.S).group(0))
check("TransferPendingCash adds no multiplier", "applyCashMult" not in re.search(r"function EconomyService.TransferPendingCash.*?\nend\n", ECO, re.S).group(0))
ppm = re.search(r"function MonetizationService.PassivePerMin.*?\nend\n", MS, re.S).group(0)
check("PassivePerMin(excludeTimed) divides the DOUBLE WEEKEND factor out (Robux time packs / income-scaled rewards)",
      "DoubleEvent" in ppm, "BUG: only CashBoost + EngagementService are divided out")

SRC_FIXED = "DoubleEvent" in ppm
# Code Bot v196: DOUBLE WEEKEND on 2x-pass-exempt fixed payouts (EventConfig.ExtraCashReasons)
WANT_EXTRA = ["bank_raid", "clan_war_participate", "clan_war_win", "ops", "plot_oil", "supply_drop"]
NOT_DOUBLED = ["code", "battlepass", "onboarding", "invite_welcome", "invite_reward", "friends_bonus", "comeback", "spinner",
               "manual_dropper", "devproduct", "admin", "purchase_refund", "collector", "offline", "bank_raid_kit"]
check("EventConfig.ExtraCashReasons = oil, jobs, supply drops, bank raid, clan war (exactly)", extra == WANT_EXTRA, ",".join(extra))
check("ExtraCashReasons are all still 2x-pass exempt (MonetizationConfig.CashMultExemptReasons)", all(r in cashExempt for r in WANT_EXTRA))
check("ExtraCashReasons never lists a NEVER_MULTIPLIED reason", not (set(extra) & set(never)))
check("ExtraCashReasons lists none of codes / battle pass / onboarding / invite / friends / comeback / spinner / dropper / Robux / admin / refunds",
      not (set(extra) & set(NOT_DOUBLED)))
cmf = re.search(r"local function cashMultFor.*?\nend\n", ECO, re.S).group(0)
check("cashMultFor exempt branch: DE.ExtraCashMult only, guarded by NEVER_MULTIPLIED",
      re.search(r"elseif NEVER_MULTIPLIED\[reasonKey\] ~= true then.*?DE\.ExtraCashMult\(player, reason\)", cmf, re.S) is not None
      and cmf.count("DE.CashMult(") == 1 and cmf.count("DE.ExtraCashMult(") == 1)
check("DoubleEvent.ExtraCashMult reads ExtraCashReasons, skips CashExemptReasons / KillReasons",
      re.search(r"function DoubleEvent.ExtraCashMult.*?ExtraCashReasons.*?CashExemptReasons.*?KillReasons.*?\nend", DE, re.S) is not None)
check("oil pumps grant via AccruePendingCash with plot_oil (doubled once, at accrue)",
      'Reason = "plot_oil"' in POILC and "AccruePendingCash" in POIL)
check("CollectPendingCash pays as never-multiplied 'collector' (oil not doubled again at collect)",
      "collector" in never and "applyCashMult" not in re.search(r"function EconomyService.CollectPendingCash.*?\nend\n", ECO, re.S).group(0))
check("bank raid: no kit -> 'bank_raid' (doubled), heist kit -> 'bank_raid_kit' (income-scaled, not doubled)",
      re.search(r'if okK and \(tonumber\(kit\) or 0\) > 0 then "bank_raid_kit" else "bank_raid"', BR) is not None
      and "AddCash(player, cash, raidReason)" in BR and "bank_raid_kit" in never and "bank_raid_kit" not in extra)

# --- 2. run the real Luau modules under a fake clock ---------------------------------------------------------------
harness = r'''
local NOW = 0
local fakeOs = setmetatable({ time = function() return NOW end }, { __index = os })
local attrs = {}
local RS = { GetAttribute = function(_, k) return attrs[k] end, SetAttribute = function(_, k, v) attrs[k] = v end }
local token = {}
function token:WaitForChild() return token end
function RS:WaitForChild() return token end
local fakeGame = { GetService = function() return RS end }
local function loadEC() %EC%
end
local EventConfig = loadEC()
local function loadDE(os, game, require, script) %DE%
end
local DoubleEvent = loadDE(fakeOs, fakeGame, function() return EventConfig end, {})
local NEVER, CASHEX, XPEX = %NEVER%, %CASHEX%, %XPEX%
local function player(uid) return setmetatable({ UserId = uid }, { __type = "Instance" }) end
-- typeof(player) must be "Instance": DoubleEvent checks it. Wrap typeof in the module env instead:
'''
# DoubleEvent uses typeof(player) ~= "Instance"; inject a typeof shim as an extra local
DE_shim = "local typeof = function(v) if type(v)=='table' and rawget(v,'UserId') then return 'Instance' end return _G_typeof(v) end\n" + DE
harness = "local _G_typeof = typeof\n" + harness
harness = harness.replace("%EC%", EC).replace("%DE%", DE_shim).replace("%NEVER%", lua_set(never)).replace("%CASHEX%", lua_set(cashExempt)).replace("%XPEX%", lua_set(xpExempt))
harness += r'''
local fails = 0
local function ok(name, cond, extra) print((cond and "PASS " or "FAIL ") .. name .. (extra and ("  [" .. extra .. "]") or "")) if not cond then fails += 1 end end
-- the cashMultFor stack, pass = MonetizationService.GetCashMultiplier (2 with the 2x Cash pass)
local function cash(p, reason, pass)
  if NEVER[reason] then return 1 end
  if CASHEX[reason] then return if DoubleEvent.ExtraCashMult then DoubleEvent.ExtraCashMult(p, reason) else 1 end
  return pass * DoubleEvent.CashMult(p, reason)
end
local function xp(p, reason, pass)
  if XPEX[reason] then return 1 end
  return pass * DoubleEvent.XPMult(p, reason)
end
local S, E = EventConfig.StartUnix, EventConfig.EndUnix
local SRC_FIXED, WANT_EXTRA, NOT_DOUBLED = %SRC_FIXED%, %WANT_EXTRA%, %NOT_DOUBLED%
local OWNER, PLAYER = player(EventConfig.OwnerUserId), player(12345)
local times = { {"T-1d", S-86400, false}, {"T-1s", S-1, false}, {"start", S, true}, {"mid", S+86400, true}, {"end-1s", E-1, true}, {"end", E, false}, {"end+1d", E+86400, false} }
-- default: preview attribute never written (DoubleEvent.Init is never called) -> PreviewOn = OwnerFirst = true
for _, t in ipairs(times) do
  NOW = t[2]
  local want = if t[3] then 2 else 1
  ok("player cash passive @" .. t[1], cash(PLAYER, "passive", 1) == want)
  ok("player cash passive w/ 2x pass @" .. t[1], cash(PLAYER, "passive", 2) == 2 * want)
  ok("player xp mission w/ 2x XP pass @" .. t[1], xp(PLAYER, "mission", 2) == 2 * want)
  ok("player kill cash pvp_kill @" .. t[1], cash(PLAYER, "pvp_kill", 1) == want)
  ok("player kill xp npc_kill w/ pass @" .. t[1], xp(PLAYER, "npc_kill", 2) == 2 * want)
  ok("player kill COUNT @" .. t[1], DoubleEvent.KillCount(PLAYER) == want)
  for _, r in ipairs({ "devproduct", "purchase_refund", "admin", "collector", "atm_raid", "code", "dismiss_soldiers", "offline" }) do
    ok("exempt " .. r .. " stays 1x @" .. t[1], cash(PLAYER, r, 2) == 1)
  end
  ok("xp admin stays 1x @" .. t[1], xp(PLAYER, "admin", 2) == 1)
  -- owner preview only before the start
  local ownerWant = if NOW < E then 2 else 1
  ok("owner cash (preview default on) @" .. t[1], cash(OWNER, "passive", 1) == ownerWant)
end
-- preview OFF must never switch the live window off
RS:SetAttribute(EventConfig.PreviewAttr, false)
for _, t in ipairs(times) do NOW = t[2]
  ok("preview OFF: player @" .. t[1], DoubleEvent.CashMult(PLAYER, "passive") == (if t[3] then 2 else 1))
  ok("preview OFF: owner @" .. t[1], DoubleEvent.CashMult(OWNER, "passive") == (if t[3] then 2 else 1))
end
RS:SetAttribute(EventConfig.PreviewAttr, true)
NOW = S - 10; ok("preview ON: non-owner still 1x before start", DoubleEvent.CashMult(PLAYER, "passive") == 1)
NOW = E + 10; ok("preview ON: owner 1x after end", DoubleEvent.CashMult(OWNER, "passive") == 1)
-- long-running server: the SAME module instance, clock walks across both edges second by second
local flips, last = 0, nil
for t = S - 5, S + 5 do NOW = t local v = DoubleEvent.CashMult(PLAYER, "passive") if last and v ~= last then flips += 1 end last = v end
for t = E - 5, E + 5 do NOW = t local v = DoubleEvent.CashMult(PLAYER, "passive") if last and v ~= last then flips += 1 end last = v end
ok("long-running server: turns on at S and off at E with no restart (2 flips)", flips == 2, tostring(flips))
-- accrue-then-collect: income accrued in the window, collected after it, is doubled exactly once
NOW = E - 60; local pending = 100 * cash(PLAYER, "passive", 2)  -- AccruePendingCash
NOW = E + 3600; local wallet = pending * cash(PLAYER, "collector", 2) -- CollectPendingCash = exempt
ok("accrue in window (pass) + collect after: 4x once, not 8x", wallet == 400, tostring(wallet))
NOW = S - 60; pending = 100 * cash(PLAYER, "passive", 2); NOW = S + 60; wallet = pending * cash(PLAYER, "collector", 2)
ok("accrued before start, collected in window: not doubled (2x pass only)", wallet == 200, tostring(wallet))
-- offline factor: only the overlap is doubled
ok("offline span fully before: x1", DoubleEvent.OfflineFactor(S - 7200, 3600) == 1)
ok("offline span half inside: x1.5", math.abs(DoubleEvent.OfflineFactor(S - 1800, 3600) - 1.5) < 1e-9)
ok("offline span fully inside: x2", DoubleEvent.OfflineFactor(S + 10, 3600) == 2)
ok("offline span after end: x1", DoubleEvent.OfflineFactor(E, 3600) == 1)
-- MaxCash clamp: 2x * 2x of a huge grant still clamps at 1e15 without float trouble
local MaxCash = 1e15
NOW = S + 1; local c = math.clamp(9.99e14 + math.floor(1e12 * cash(PLAYER, "passive", 2)), 0, MaxCash)
ok("clamp at MaxCash 1e15 with 4x grant", c == MaxCash and c == math.floor(c))
-- PassivePerMin as written (MonetizationService): excludeTimed divides CashBoost + EngagementService only
local function passivePerMin(p, perTick, tick, pass, excludeTimed, fixed)
  local m = cash(p, "passive", pass)              -- EconomyService.GetCashMult(player, "passive")
  if excludeTimed and fixed then m = m / DoubleEvent.CashMult(p, "passive") end
  return perTick * m / tick * 60
end
for _, fixed in ipairs({ SRC_FIXED, true }) do
  local tag = if fixed == SRC_FIXED and _ == 1 then " (source as written)" else " (WITH proposed fix)"
  NOW = S - 3600; local before = math.max(200000, 240 * passivePerMin(PLAYER, 10000, 5, 1, true, fixed))
  NOW = S + 3600; local during = math.max(200000, 240 * passivePerMin(PLAYER, 10000, 5, 1, true, fixed))
  ok("Robux 4h time pack is NOT doubled in the window" .. tag, during == before, string.format("%d -> %d", before, during))
  local coreBefore, coreDuring
  NOW = S - 3600; coreBefore = math.max(5000, math.floor(passivePerMin(PLAYER, 10000, 5, 1, true, fixed) * 10)) * cash(PLAYER, "mission", 1)
  NOW = S + 3600; coreDuring = math.max(5000, math.floor(passivePerMin(PLAYER, 10000, 5, 1, true, fixed) * 10)) * cash(PLAYER, "mission", 1)
  ok("income-scaled core mission pays 2x (not 4x) in the window" .. tag, coreDuring == 2 * coreBefore, string.format("%d -> %d", coreBefore, coreDuring))
end
-- Code Bot v196: ExtraCashReasons doubled in the window (once), pass never applies to them; the rest never doubled
for _, r in ipairs(WANT_EXTRA) do
  NOW = S - 60; ok("extra " .. r .. " x1 before the window (2x pass owner too)", cash(PLAYER, r, 1) == 1 and cash(PLAYER, r, 2) == 1)
  NOW = S + 3600; ok("extra " .. r .. " x2 in the window, x2 (not x4) with the 2x pass", cash(PLAYER, r, 1) == 2 and cash(PLAYER, r, 2) == 2)
  NOW = E; ok("extra " .. r .. " x1 after the window", cash(PLAYER, r, 2) == 1)
end
NOW = S + 3600
for _, r in ipairs(NOT_DOUBLED) do
  ok("NOT doubled in the window: " .. r, cash(PLAYER, r, 1) == 1 and cash(PLAYER, r, 2) == 1)
end
local pending = math.floor(100 * cash(PLAYER, "plot_oil", 2)); local wallet = math.floor(pending * cash(PLAYER, "collector", 2))
ok("oil: $100 accrued in the window -> $200 pending -> $200 collected (once, not $400)", pending == 200 and wallet == 200, pending .. " -> " .. wallet)
NOW = E + 10; local p2 = math.floor(100 * cash(PLAYER, "plot_oil", 2))
ok("oil: accrued after the window, collected later -> $100", math.floor(p2 * cash(PLAYER, "collector", 2)) == 100)
NOW = S + 3600; ok("supply drop $10k claimed in the window -> $20k", math.floor(10000 * cash(PLAYER, "supply_drop", 2)) == 20000)
ok("kill rewards stay KillMult (2x pass owner: 4x, as before)", cash(PLAYER, "pvp_kill", 2) == 4)
ok("code reward $50k in the window stays $50k", math.floor(50000 * cash(PLAYER, "code", 2)) == 50000)
ok("battle pass $25k in the window stays $25k", math.floor(25000 * cash(PLAYER, "battlepass", 2)) == 25000)
print("LUAU_FAILS=" .. fails)
'''
harness = harness.replace("%SRC_FIXED%", "true" if SRC_FIXED else "false").replace("%WANT_EXTRA%", "{" + ",".join('"%s"' % r for r in WANT_EXTRA) + "}").replace("%NOT_DOUBLED%", "{" + ",".join('"%s"' % r for r in NOT_DOUBLED) + "}")
with tempfile.NamedTemporaryFile("w", suffix=".luau", delete=False) as f:
    f.write(harness); path = f.name
out = subprocess.run([LUAU, path], capture_output=True, text=True)
print(out.stdout, end=""); print(out.stderr, end="", file=sys.stderr)
m = re.search(r"LUAU_FAILS=(\d+)", out.stdout)
check("luau harness ran", out.returncode == 0 and m is not None)
nfail = sum(1 for _, ok in results if not ok) + (int(m.group(1)) if m else 1)
print(f"\nTOTAL FAIL={nfail}")
sys.exit(1 if nfail else 0)
