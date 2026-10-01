#!/usr/bin/env python3
"""Code Bot v169: AdminConfig.OwnerRebirthGrant: the owner's (470626172) rebirth count -> 10 ONE TIME on his next
profile load, through PrestigeService.AdminSetRebirth (/setrebirth path: cash / items kept, refreshed, saved).
Proves: applied once from the real OnProfileLoaded hook; the Key marker stops a re-apply (after a further rebirth and
after lowering); already >= 10 changes nothing; a non-owner / an owner not in UserIds / no config are untouched;
the owner stays board-excluded. LUAU=... python3 tools/sim/run_codebot_v169_test.py"""
import os
import sys
from pathlib import Path

HERE = Path(__file__).resolve().parent
sys.path.insert(0, str(HERE))
os.environ.setdefault("LUAU", "luau")
import run_codebot_v168_test as V  # noqa: E402  (runs the v168 sections first)

if V.FAILS:
    print("CODEBOT V169 TESTS: v168 sections failed: " + ", ".join(V.FAILS))
    sys.exit(1)
V.FAILS.clear()
B_EXTRA = V.B_EXTRA.replace("defer = function() end", "defer = function(fn, ...) if type(fn) == 'function' then fn(...) end end")
TEST = r'''
local fails = 0
local function check(ok, msg) print((ok and "ok    " or "FAIL  ") .. msg); if not ok then fails += 1 end end
local AC = require(node("Configs/AdminConfig"))
local PS = require(node("Services/PrestigeService"))
local G = AC.OwnerRebirthGrant
check(G ~= nil and G.UserId == 470626172 and G.Rebirths == 10 and G.Key == "rebirth10-2026-10-01", "AdminConfig.OwnerRebirthGrant = 470626172 / 10 / rebirth10-2026-10-01")
local profiles = {}
local function prof(r) return { Cash = 123456789, Gold = 777, Level = 64, XP = 4321, Prestige = r, BaseUpgrades = { CommandCenter = 5 },
  Vehicles = { Jeep = true }, Weapons = { M4 = true }, RebirthUnlocks = {}, Endgame = { EmpireLevel = 9 } } end
local log = { dirty = 0, saved = 0, eco = 0, fired = 0 }
local loaded = {}
local remotes = {}
local function remote(name)
  if remotes[name] == nil then
    local r = { OnServerEvent = { fns = {} }, IsA = function(_, c) return c == "RemoteEvent" end }
    r.OnServerEvent.Connect = function(self, fn) table.insert(self.fns, fn) end
    r.FireClient = function() log.fired += 1 end
    remotes[name] = r
  end
  return remotes[name]
end
local deps = {
  DataService = { GetProfile = function(p) return profiles[p.UserId] end, MarkDirty = function() log.dirty += 1 end,
    OnProfileLoaded = function(fn) table.insert(loaded, fn) end, SaveProfile = function() log.saved += 1; return true end },
  EconomyService = { Push = function() log.eco += 1 end, AddGold = function() error("no gold") end, AddCash = function() error("no cash") end, SyncOutpostIncomeStacks = function() end },
  XPService = { Push = function() end, SetLevel = function() end, AddXP = function() end },
  BaseService = { PushState = function() end },
  VehicleService = { GrantVehicle = function() end },
  NotificationService = { Notify = function() end, NotifyThrottled = function() end },
  RateLimitService = { Allow = function() return true end },
  AnalyticsService = { Log = function() end },
  RemoteSetup = { Get = function(n) return remote(n) end },
  MonetizationService = {},
}
PS.Init(deps)
RUN_SPAWN = true
local function join(p) for _, fn in ipairs(loaded) do fn(p, profiles[p.UserId]) end end
-- 1. his next join at R2
profiles[SHAUN.UserId] = prof(2)
local sp = profiles[SHAUN.UserId]
join(SHAUN)
check(sp.Prestige == 10, "next join: R2 -> R10 (" .. tostring(sp.Prestige) .. ")")
check(sp.Cash == 123456789 and sp.Gold == 777 and sp.Level == 64 and sp.XP == 4321 and sp.BaseUpgrades.CommandCenter == 5 and sp.Vehicles.Jeep and sp.Weapons.M4 and sp.Endgame.EmpireLevel == 9,
  "cash, gold, level, XP, upgrades, items kept")
local nFlags = 0
for _, u in ipairs(require(node("Configs/PrestigeConfig")).RebirthUnlocks) do if u.Gate == nil and u.AtPrestige <= 10 and sp.RebirthUnlocks[u.Flag] then nFlags += 1 end end
check(nFlags > 0 and log.saved == 1 and log.eco >= 1 and log.fired >= 1, "the /setrebirth path: unlocks (" .. nFlags .. "), pushes, saved once")
check(type(sp.AdminGrants) == "table" and type(sp.AdminGrants[G.Key]) == "table" and sp.AdminGrants[G.Key].Applied == true and sp.AdminGrants[G.Key].From == 2,
  "profile.AdminGrants[Key] marker stored (From 2)")
-- 2. rejoin: nothing
log.saved = 0
join(SHAUN)
check(sp.Prestige == 10 and log.saved == 0, "rejoin: not re-applied")
-- 3. he rebirths further (R11) / lowers (R3): never pulled back to 10
sp.Prestige = 11; join(SHAUN)
check(sp.Prestige == 11, "after a real rebirth to R11: stays R11")
sp.Prestige = 3; join(SHAUN)
check(sp.Prestige == 3, "after /setrebirth 3: stays R3 (one time only)")
-- 4. a fresh profile already at R12: nothing changed, Key stored
profiles[SHAUN.UserId] = prof(12); local s12 = profiles[SHAUN.UserId]
log.saved = 0
join(SHAUN)
check(s12.Prestige == 12 and log.saved == 0 and s12.AdminGrants[G.Key].Applied == false, "already R12 (>= 10): nothing changes (marker only)")
profiles[SHAUN.UserId] = prof(10); join(SHAUN)
check(profiles[SHAUN.UserId].Prestige == 10 and log.saved == 0, "exactly R10: nothing changes")
-- 5. somebody else
profiles[RANDO.UserId] = prof(2); join(RANDO)
check(profiles[RANDO.UserId].Prestige == 2 and profiles[RANDO.UserId].AdminGrants == nil, "a non-owner: untouched")
-- 6. owner removed from UserIds / config off
local keep = AC.UserIds
AC.UserIds = {}
profiles[SHAUN.UserId] = prof(2); join(SHAUN)
check(profiles[SHAUN.UserId].Prestige == 2, "not in AdminConfig.UserIds: untouched")
AC.UserIds = keep
local g = AC.OwnerRebirthGrant
AC.OwnerRebirthGrant = nil
profiles[SHAUN.UserId] = prof(2); join(SHAUN)
check(profiles[SHAUN.UserId].Prestige == 2, "OwnerRebirthGrant = nil: off")
AC.OwnerRebirthGrant = g
-- 7. boards: the owner is excluded
check(AC.IsPlaytestOwner(470626172) and table.find(AC.UserIds, 470626172) ~= nil, "the owner stays board-excluded (IsPlaytestOwner + UserIds -> EngagementService.isBoardExcluded)")
print(string.format("V169 OWNER GRANT TEST: %d failed", fails))
if fails > 0 then error("failed") end
'''
V.run("owner grant", V.PRELUDE, B_EXTRA, V.B_MODS, TEST, "V169 OWNER GRANT TEST")
eng = (V.SV / "Services/EngagementService.luau").read_text(encoding="utf-8")
ps = (V.SV / "Services/PrestigeService.luau").read_text(encoding="utf-8")
V.check_static("EngagementService.isBoardExcluded covers IsPlaytestOwner + UserIds", "AC.IsPlaytestOwner(uid)" in eng and "local function isBoardExcluded" in eng)
V.check_static("the grant goes through AdminSetRebirth (no second rebirth path)", "local ok = PrestigeService.AdminSetRebirth(player, want)" in ps)
print("CODEBOT V169 TESTS: %d failed%s" % (len(V.FAILS), (" (" + ", ".join(V.FAILS) + ")") if V.FAILS else ""))
sys.exit(1 if V.FAILS else 0)
