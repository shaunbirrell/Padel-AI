"""Code Bot v221 (Shaun 2026-10-02): the Plaza Airstrike ALSO takes the Central Plaza for the buyer.
Real-code test in the Luau CLI: the REAL TerritoryService (awardCapture through InstantCapture), the REAL
PlazaAirstrike module, the REAL MonetizationConfig / TerritoryConfig / EconomyConfig / RetentionConfig / AdminConfig.
Around them recording fakes (DataService, NotificationService, EconomyService, CombatService, PlazaBounty,
OutpostDefenders, RemoteSetup, Players). Stand-ins from run_kit_detail_test.PRELUDE.

1. PURCHASE -> CAPTURE: a rival holds the Plaza; the buyer's receipt has banked 1 charge; FireFromPurchase (the
   OnGranted path) spends it, warns, lands the strike (others in the zone hurt, never killed, the buyer untouched),
   then the buyer owns the Plaza through awardCapture: the rival loses it (his "lost" toast), Stats.PlazaCaptures and
   TerritoriesCaptured +1, PlazaBounty.OnCaptured(buyer), the defenders see it Held, a full push, everyone gets
   "AIRSTRIKE! <name> took the Plaza", the normal protection period starts (re-capture rules unchanged).
2. ALREADY HOLDS: a second purchase still strikes; ownership / counters unchanged; "You still hold the Plaza".
3. TAKE IT BACK: the rival buys one -> he holds it again (nothing is locked to the buyer).
4. NO CLIENT TRUST: no saved charge -> FireFromPurchase does nothing; the AIRSTRIKE remote far from the Plaza refuses.
5. SWITCH OFF: PlazaAirstrikeTakeover.Enabled = false -> the charge stays banked, nobody captures.
Run: LUAU=path/to/luau(.exe) python tools/sim/run_plaza_airstrike_takeover_test.py   (exit 1 on any failure; VERBOSE=1)"""
import os
import subprocess
import sys
import tempfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from run_kit_detail_test import PRELUDE  # noqa: E402

ROOT = Path(__file__).resolve().parents[2]
SH = ROOT / "src/ReplicatedStorage/Shared"
SV = ROOT / "src/ServerScriptService/Server"
MODS = {
    "Constants": SH / "Constants.luau",
    "Configs/TerritoryConfig": SH / "Configs/TerritoryConfig.luau",
    "Configs/BaseConfig": SH / "Configs/BaseConfig.luau",
    "Util/PlotFrame": SH / "Util/PlotFrame.luau",
    "Configs/EconomyConfig": SH / "Configs/EconomyConfig.luau",
    "Configs/MonetizationConfig": SH / "Configs/MonetizationConfig.luau",
    "Configs/RetentionConfig": SH / "Configs/RetentionConfig.luau",
    "Configs/AdminConfig": SH / "Configs/AdminConfig.luau",
    "Services/TerritoryService": SV / "Services/TerritoryService/init.luau",
    "Modules/PlazaAirstrike": SV / "Modules/PlazaAirstrike.luau",
}

TEST = r'''
local fails = 0
local function check(ok, msg) print((ok and "ok    " or "FAIL  ") .. msg); if not ok then fails += 1 end end
local DELAYED = {}
warn = function(...) print("WARN", ...) end
task = { spawn = function() end, delay = function(_, fn, ...) table.insert(DELAYED, fn) end, defer = function(fn, ...) fn(...) end, wait = function() end }
local function runDelayed() local q = DELAYED; DELAYED = {}; for _, fn in ipairs(q) do fn() end end
local LIST = {}
local PLAYERS = { PlayerRemoving = { Connect = function() end }, PlayerAdded = { Connect = function() end } }
function PLAYERS:GetPlayers() return table.clone(LIST) end
function PLAYERS:GetPlayerByUserId(u) for _, p in ipairs(LIST) do if p.UserId == u then return p end end return nil end
local prevG = game
game = { GetService = function(_, n)
  if n == "Players" then return PLAYERS end
  if n == "RunService" then return { IsStudio = function() return false end, Heartbeat = { Connect = function() end } } end
  return prevG:GetService(n) end }
workspace = setmetatable({}, { __index = function() return function() return nil end end })

-- the fakes around the real modules
local NOTE, PUSHES, BOUNTY = {}, 0, {}
local DEF_DEPS = nil
SOURCES["Services/TerritoryService/TerritoryRadar"] = function() return setmetatable({ FindMarker = function() return nil end, ShownTo = function() return true end }, { __index = function() return function() return nil end end }) end
SOURCES["Modules/OutpostDefenders"] = function() return { Start = function(d) DEF_DEPS = d end, Blocking = function() return false end, NoteBlocked = function() end } end
SOURCES["Modules/PlazaBounty"] = function() return { Bind = function() end, OnCaptured = function(p, id) table.insert(BOUNTY, { p = p, id = id }) end } end
local HURT = {}
SOURCES["Services/CombatService"] = function() return { IsSpawnInvulnerable = function() return false end, IsNoviceShielded = function() return false end } end

local TC = require(node("Configs/TerritoryConfig"))
local MC = require(node("Configs/MonetizationConfig"))
local PLAZA = TC.Territories.CentralPlaza
local function mkP(uid, name, pos)
  local p = Instance.new("Player")
  p.UserId = uid; p.Name = name; p.DisplayName = name; p.Parent = PLAYERS
  local hum = { Health = 100, ClassName = "Humanoid" }
  function hum:TakeDamage(n) self.Health -= n; table.insert(HURT, { p = p, n = n }) end
  local root = { Position = pos, IsA = function(_, c) return c == "BasePart" end }
  p.Character = { FindFirstChild = function(_, n) return if n == "HumanoidRootPart" then root else nil end,
    FindFirstChildOfClass = function(_, c) return if c == "Humanoid" then hum else nil end }
  table.insert(LIST, p)
  return p, hum, root
end
local far = PLAZA.Position + Vector3.new(2000, 0, 0)
local B, BH = mkP(101, "Buyer", far)                                -- the buyer: far away (bought from the Shop)
local R, RH, RR = mkP(202, "Rival", PLAZA.Position + Vector3.new(5, 0, 0)) -- on the Plaza
local O = mkP(303, "Other", far)
local PROF = {}
for _, p in ipairs(LIST) do PROF[p.UserId] = { Stats = { TerritoriesCaptured = 0 }, Territories = {}, AirstrikeCharges = 0 } end
local remoteHandlers = {}
local function mkRemote(name) return { IsA = function() return true end, FireClient = function() PUSHES += 1 end, FireAllClients = function() end,
  OnServerEvent = { Connect = function(_, fn) remoteHandlers[name] = fn end } } end
local REM = {}
local deps = {
  DataService = { GetProfile = function(p) return PROF[p.UserId] end, MarkDirty = function() end, OnProfileLoaded = function() end },
  NotificationService = { Notify = function(p, t, k) table.insert(NOTE, { p = p, t = t, k = k }) end },
  EconomyService = { SyncOutpostIncomeStacks = function(p) local n = 0; for _ in pairs(PROF[p.UserId].Territories) do n += 1 end; return 0, n, 10, n * 10 end, EmpireTaxPct = function(p) local n = 0; for _ in pairs(PROF[p.UserId].Territories) do n += 1 end; return n * 10 end },
  RateLimitService = { Allow = function() return true end },
  RemoteSetup = { Get = function(n) REM[n] = REM[n] or mkRemote(n); return REM[n] end },
}
local TS = require(node("Services/TerritoryService"))
TS.Init(deps)
local PA = require(node("Modules/PlazaAirstrike"))
PA.Start(deps)

local rt = TS.GetRuntime("CentralPlaza")
check(rt ~= nil and MC.PlazaAirstrikeTakeover.Enabled == true and MC.PlazaAirstrikeTakeover.OwnerFirst == false, "Plaza runtime exists; PlazaAirstrikeTakeover Enabled, PUBLIC (OwnerFirst = false)")
check(MC.DevProducts.PlazaAirstrike.GrantAirstrikes == 1 and MC.SkuLiveFor(B.UserId, "PlazaAirstrike"), "the product banks 1 charge and is live for a non-owner")
local OT = TC.OwnerTypes
-- the rival holds it (as after a normal capture)
rt.OwnerType = OT.Player; rt.OwnerUserId = R.UserId; PROF[R.UserId].Territories.CentralPlaza = true
local function heldFor()
  for _, t in ipairs(DEF_DEPS.Territories()) do if t.Id == "CentralPlaza" then return t.Held end end
  return nil
end
local function toastFor(p, needle) for _, n in ipairs(NOTE) do if n.p == p and string.find(n.t, needle, 1, true) then return n end end return nil end

-- 1. purchase -> capture
PROF[B.UserId].AirstrikeCharges = 1 -- ProcessReceipt (CounterGrants.GrantAirstrikes), saved
local pushes0 = PUSHES
local fired = PA.FireFromPurchase(B)
check(fired == true and PROF[B.UserId].AirstrikeCharges == 0 and B:GetAttribute("WE_AirstrikeCharges") == 0, "OnGranted: the saved charge is spent at once (anywhere on the map)")
check(toastFor(B, "AIRSTRIKE incoming") ~= nil and toastFor(R, "AIRSTRIKE incoming") ~= nil and toastFor(O, "AIRSTRIKE incoming") == nil, "warning: the buyer + everyone in the zone, not the far player")
check(rt.OwnerUserId == R.UserId, "nothing changes before the strike lands")
runDelayed()
check(#HURT == 1 and HURT[1].p == R and RH.Health == 100 - MC.PlazaAirstrikeTuning.Damage and BH.Health == 100, string.format("the strike lands: the rival in the zone takes %d (never lethal), the buyer untouched", MC.PlazaAirstrikeTuning.Damage))
check(rt.OwnerType == OT.Player and rt.OwnerUserId == B.UserId, "the buyer OWNS the Central Plaza")
check(PROF[B.UserId].Territories.CentralPlaza == true and PROF[R.UserId].Territories.CentralPlaza == nil, "profile ownership synced: buyer has it, rival lost it")
check(PROF[B.UserId].Stats.PlazaCaptures == 1 and PROF[B.UserId].Stats.TerritoriesCaptured == 1, "Plaza leaderboard (Stats.PlazaCaptures) and TerritoriesCaptured +1, like a normal capture")
check(#BOUNTY == 1 and BOUNTY[1].p == B and BOUNTY[1].id == "CentralPlaza", "PlazaBounty.OnCaptured(buyer) (the normal capture reward)")
check(heldFor() == true, "the Plaza defenders see it Held (they stand down exactly as after a normal capture)")
check(PUSHES > pushes0, "the new owner is pushed to every client (map / HUD / flag)")
local want = string.format(MC.PlazaAirstrikeTakeover.ToastAll, "Buyer")
check(want == "AIRSTRIKE! Buyer took the Plaza" and toastFor(B, want) ~= nil and toastFor(R, want) ~= nil and toastFor(O, want) ~= nil, "everyone sees: " .. want)
check(toastFor(R, "Central Plaza") ~= nil, "the rival gets the normal 'lost' toast")
check(toastFor(B, "Central Plaza") ~= nil or toastFor(B, "SECURED") ~= nil, "the buyer gets the normal capture toast")
check(rt.Progress == 0 and rt.Contested == false and math.abs(rt.ProtectedUntil - (os.time() + TC.ProtectionPeriodSeconds)) <= 1, "the normal protection period starts (re-capture rules unchanged)")

-- 2. already holds
NOTE = {}
PROF[B.UserId].AirstrikeCharges = 1
RH.Health = 100
check(PA.FireFromPurchase(B) == true, "a second purchase still strikes")
runDelayed()
check(rt.OwnerUserId == B.UserId and PROF[B.UserId].Stats.PlazaCaptures == 1 and #BOUNTY == 1, "already the holder: no second capture / bounty / leaderboard bump")
check(toastFor(B, MC.PlazaAirstrikeTakeover.ToastHeld) ~= nil and RH.Health < 100, "the strike still lands; the buyer is told: " .. MC.PlazaAirstrikeTakeover.ToastHeld)

-- 3. the rival takes it back
PROF[R.UserId].AirstrikeCharges = 1
check(PA.FireFromPurchase(R) == true, "the rival buys one too")
runDelayed()
check(rt.OwnerUserId == R.UserId and PROF[B.UserId].Territories.CentralPlaza == nil, "others can take it back (nothing locks it to the buyer)")

-- 4. no client trust
local before = rt.OwnerUserId
PROF[O.UserId].AirstrikeCharges = 0
check(PA.FireFromPurchase(O) == false and #DELAYED == 0 and rt.OwnerUserId == before, "no saved charge: nothing happens")
local h = remoteHandlers["RequestPlazaAirstrike"]
PROF[O.UserId].AirstrikeCharges = 1
if h then h(O) end
check(h ~= nil and PROF[O.UserId].AirstrikeCharges == 1 and #DELAYED == 0, "the AIRSTRIKE remote far from the Plaza refuses (server range check)")

-- 5. switch off
MC.PlazaAirstrikeTakeover.Enabled = false
PROF[O.UserId].AirstrikeCharges = 1
check(PA.FireFromPurchase(O) == false and PROF[O.UserId].AirstrikeCharges == 1 and rt.OwnerUserId == before, "Enabled = false: the charge stays banked (old behaviour), nobody captures")
MC.PlazaAirstrikeTakeover.Enabled = true

print(string.format("PLAZA AIRSTRIKE TAKEOVER LUA: %d failed", fails))
if fails > 0 then error("failed") end
'''


def main():
    chunks = [PRELUDE]
    for key, path in MODS.items():
        chunks.append("SOURCES[%r] = function(script)\n%s\nend" % (key, path.read_text(encoding="utf-8")))
    chunks.append(TEST)
    with tempfile.NamedTemporaryFile("w", suffix=".luau", delete=False, encoding="utf-8") as f:
        f.write("\n".join(chunks))
        path = f.name
    try:
        r = subprocess.run([os.environ.get("LUAU", "luau"), path], capture_output=True, text=True, timeout=120)
    finally:
        os.unlink(path)
    out = r.stdout.strip().splitlines()
    fails = 0
    if r.returncode != 0 or "PLAZA AIRSTRIKE TAKEOVER LUA: 0 failed" not in r.stdout:
        fails = 1
        out.append(r.stderr.strip()[-2500:])
    out.append("PLAZA AIRSTRIKE TAKEOVER TEST: %d failed" % fails)
    print("\n".join(out) if os.environ.get("VERBOSE") else "\n".join(l for l in out if l.startswith(("FAIL", "PLAZA AIRSTRIKE TAKEOVER TEST", "  ")) or "error" in l.lower()))
    sys.exit(1 if fails else 0)


if __name__ == "__main__":
    main()
