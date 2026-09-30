"""claude-bud JOB 31: two real-code tests in the Luau CLI (the stand-ins from run_kit_detail_test.PRELUDE):

1. SITES: the real Modules/WorldSites placement rules (PlaceOk / Candidates) with the real WorldSitesConfig, BaseConfig,
   PlotFrame, MapAreas and WorldKits footprints:
   * every site has a candidate centre within SearchStuds that keeps off every base plot and named area, on dry land
     (the part test needs the live world);
   * every cluster row stays <= 64 studs across (WorldKits H10), measured from each kit's real footprint;
   * the planned plain parts of all sites fit MaxParts.
2. ACTIVITIES: the real Services/SiteActivityService with stub CombatService / Economy / XP / remotes / sites:
   * ClearCamp spawns its group, and all deaths pay the reward ONCE;
   * a restart during the cooldown is refused;
   * the Sniper counts only kills made on the deck (an off-deck kill stands a new target up);
   * the Cache pays only when the owner triggers the prompt from close by;
   * Convoy fails when the player leaves the zone;
   * NPCs are despawned at the end.
Run: LUAU=path/to/luau(.exe) python tools/sim/run_sites_test.py   (exit 1 on any failure)"""
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
    "Configs/WorldConfig": SH / "Configs/WorldConfig.luau",
    "Configs/WorldDetailConfig": SH / "Configs/WorldDetailConfig.luau",
    "Configs/WorldSitesConfig": SH / "Configs/WorldSitesConfig.luau",
    "Configs/SiteActivityConfig": SH / "Configs/SiteActivityConfig.luau",
    "Configs/TerritoryConfig": SH / "Configs/TerritoryConfig.luau",
    "Configs/OutpostDefenderConfig": SH / "Configs/OutpostDefenderConfig.luau",
    "Configs/BaseConfig": SH / "Configs/BaseConfig.luau",
    "Configs/BaseLayoutConfig": SH / "Configs/BaseLayoutConfig.luau",
    "Configs/RetentionConfig": SH / "Configs/RetentionConfig.luau",
    "Util/PlotFrame": SH / "Util/PlotFrame.luau",
    "Util/MapAreas": SH / "Util/MapAreas.luau",
    "Modules/WorldKits": SV / "Modules/WorldKits.luau",
    "Modules/WorldSites": SV / "Modules/WorldSites.luau",
    "Services/SiteActivityService": SV / "Services/SiteActivityService.luau",
}

EXTRA = r'''
-- more stand-ins for the services
Random = { new = function() local seed = 7; return {
  NextNumber = function(_, a, b) seed = (seed * 1103515245 + 12345) % 2147483648; local t = seed / 2147483648; return (a or 0) + t * ((b or 1) - (a or 0)) end,
  NextInteger = function(_, a, b) seed = (seed * 1103515245 + 12345) % 2147483648; return a + seed % (b - a + 1) end } end }
OverlapParams = { new = function() return {} end }
RaycastParams = { new = function() return {} end }
CFrame.lookAt = function(a, b) return CFrame.new(a.X, a.Y, a.Z) end
task = { spawn = function() end, wait = function() end, delay = function() end, defer = function() end }
local signals = {}
local function signal() local s = { fns = {} }; s.Connect = function(self, fn) table.insert(self.fns, fn); return { Disconnect = function() end } end; s.Fire = function(self, ...) for _, f in ipairs(self.fns) do f(...) end end; return s end
local prompts = {}
local rawNew = Instance.new
Instance.new = function(cls)
  local o = rawNew(cls)
  if cls == "ProximityPrompt" then o.Triggered = signal(); table.insert(prompts, o) end
  return o
end
-- players
local P = { UserId = 470626172, Name = "Owner", Parent = true, Character = nil }
local hrp = Instance.new("Part"); hrp.Position = Vector3.new(0, 5, 0)
local hum = Instance.new("Humanoid"); hum.Health = 100
local char = { FindFirstChildOfClass = function(_, c) if c == "Humanoid" then return hum end end, FindFirstChild = function(_, n) if n == "HumanoidRootPart" then return hrp end end }
P.Character = char
hrp.IsA = function(_, c) return c == "BasePart" end
local Players = { PlayerRemoving = signal(), GetPlayers = function() return { P } end, GetPlayerByUserId = function(_, id) if id == P.UserId then return P end return nil end }
local Workspace = { Raycast = function() return nil end, GetPartBoundsInRadius = function() return {} end, FindFirstChild = function() return nil end, FindFirstChildOfClass = function() return nil end }
local RunService = { IsStudio = function() return true end }
local prevGame = game
game = { GetService = function(_, n)
  if n == "Players" then return Players elseif n == "Workspace" then return Workspace elseif n == "RunService" then return RunService end
  return prevGame:GetService(n) end }
'''

TEST = r'''
local fails = 0
local function check(ok, msg) print((ok and "ok    " or "FAIL  ") .. msg); if not ok then fails += 1 end end
-- ── 1. sites ──
local WS = require(node("Modules/WorldSites"))
local WSC = require(node("Configs/WorldSitesConfig"))
local WK = require(node("Modules/WorldKits"))
local planned = 0
for _, site in ipairs(WSC.Sites) do
  local kind = WSC.Kinds[site.Kind]
  check(kind ~= nil, site.Id .. " kind " .. site.Kind .. " exists")
  local found = nil
  for _, c in ipairs(WS.Candidates(site.X, site.Z, WSC.SearchStuds)) do
    if WS.PlaceOk(c[1], c[2], kind.R) then found = c; break end
  end
  check(found ~= nil, site.Id .. " has a clear candidate" .. (found and string.format(" at (%d, %d)", found[1], found[2]) or ""))
  for i, cl in ipairs(kind.Clusters) do
    local x0, x1, z0, z1 = math.huge, -math.huge, math.huge, -math.huge
    for _, k in ipairs(cl.Kits) do
      local fp = WK.Footprint(k.Kit, { Variant = k.Variant, Count = k.Count, Length = k.Length, Scale = k.Scale })
      check(fp ~= nil, site.Id .. " kit " .. k.Kit .. " builds")
      if fp then
        planned += fp.Parts
        local yaw = math.rad(k.Yaw or 0)
        for _, px in ipairs({ fp.X0, fp.X1 }) do for _, pz in ipairs({ fp.Z0, fp.Z1 }) do
          local wx = k.X + px * math.cos(yaw) + pz * math.sin(yaw)
          local wz = k.Z - px * math.sin(yaw) + pz * math.cos(yaw)
          x0, x1, z0, z1 = math.min(x0, wx), math.max(x1, wx), math.min(z0, wz), math.max(z1, wz)
        end end
      end
    end
    local span = math.max(x1 - x0, z1 - z0)
    check(span <= 64, string.format("%s cluster %d span %.1f <= 64", site.Id, i, span))
  end
end
check(planned <= WSC.MaxParts, string.format("planned plain parts %d <= MaxParts %d", planned, WSC.MaxParts))

-- ── 2. activities ──
local SAC = require(node("Configs/SiteActivityConfig"))
local sites = {
  CampViper = { Id = "CampViper", Name = "Camp Viper", Kind = "camp", X = 100, Z = 0, R = 46, Y = 0.5 },
  Kestrel = { Id = "Kestrel", Name = "Kestrel", Kind = "depot", X = 300, Z = 0, R = 46, Y = 0.5 },
  Hawk = { Id = "Hawk", Name = "Hawk", Kind = "checkpoint", X = 0, Z = 300, R = 40, Y = 0.5 },
  DryWell = { Id = "DryWell", Name = "Dry Well", Kind = "village", X = -300, Z = 0, R = 50, Y = 0.5 },
  PumpSeven = { Id = "PumpSeven", Name = "P7", Kind = "oil", X = -300, Z = 0, R = 46, Y = 0.5 },
  Anvil = { Id = "Anvil", Name = "Anvil", Kind = "tankyard", X = -300, Z = 0, R = 46, Y = 0.5 },
  Overwatch = { Id = "Overwatch", Name = "Ridge", Kind = "overwatch", X = 0, Z = -300, R = 44, Y = 0.5, Tower = CFrame.new(0, 14.5, -300) },
}
CACHE["Modules/WorldSites"] = { Get = function(id) return sites[id] end, List = function() local l = {} for _, s in pairs(sites) do table.insert(l, s) end return l end }
local npcs, alive, nextId, deathFn = {}, 0, 0, nil
local CS = {
  SpawnNPC = function(t, cf, o) nextId += 1; local rec = { Id = "N" .. nextId, TypeId = t, Alive = true, GroupId = o.GroupId, Model = Instance.new("Model"), Static = o.Static }; npcs[rec.Id] = rec; alive += 1; return rec end,
  DespawnNPC = function(id) local r = npcs[id]; if r and r.Alive then r.Alive = false; alive -= 1 end; return true end,
  OnNPCDeath = function(fn) deathFn = fn; return function() end end,
}
local function kill(id, killer) local r = npcs[id]; r.Alive = false; alive -= 1; deathFn({ Id = id, TypeId = r.TypeId, GroupId = r.GroupId, Killer = killer, ByUnit = false, Position = Vector3.new(0, 0, 0) }) end
local cash, xp, handler, pushed = 0, 0, nil, nil
local remote = { OnServerEvent = { Connect = function(_, fn) handler = fn end }, IsA = function() return true end, FireClient = function(_, _p, kind, data) if kind == "Activities" then pushed = data end end }
local deps = {
  CombatService = CS,
  EconomyService = { AddCash = function(_, n) cash += n; return true end, AddGold = function() return true end },
  XPService = { AddXP = function(_, n) xp += n end },
  NotificationService = { Notify = function() end },
  RateLimitService = { Allow = function() return true end },
  AnalyticsService = { Log = function() end },
  RemoteSetup = { Get = function() return remote end },
}
CACHE["Modules/RemoteGate"] = { Check = function() return true end }
local SAS = require(node("Services/SiteActivityService"))
SAS.Init(deps)
check(handler ~= nil and deathFn ~= nil, "remote handler + NPC death hook connected")
local function groupIds() local l = {} for id, r in pairs(npcs) do if r.Alive and r.GroupId == "Act." .. P.UserId then table.insert(l, id) end end return l end
-- ClearCamp
handler(P, "start", "ClearViper")
local g = groupIds()
check(#g == 4, "ClearCamp spawned its 4 soldiers (" .. #g .. ")")
for _, id in ipairs(g) do kill(id, P) end
SAS._Tick(1)
check(cash == 6000 and xp == 150, "ClearCamp paid once: $" .. cash .. " + " .. xp .. " XP")
SAS._Tick(1)
check(cash == 6000, "no second payout")
handler(P, "start", "ClearViper")
check(#groupIds() == 0, "restart refused during the cooldown")
-- Sniper: off-deck kill does not count and stands a new target up; on-deck kills finish it
hrp.Position = Vector3.new(50, 5, -300)
handler(P, "start", "RidgeSniper")
g = groupIds()
check(#g == 5, "Sniper posted 5 targets (" .. #g .. ")")
kill(g[1], P)
check(#groupIds() == 5, "off-deck kill: a new target stood up (still 5)")
hrp.Position = Vector3.new(1, 15, -301)
for _, id in ipairs(groupIds()) do kill(id, P) end
SAS._Tick(1)
check(cash == 6000 + 7500, "Sniper paid after 5 deck kills ($" .. cash .. ")")
check(#groupIds() == 0, "sniper group despawned at the end")
-- Cache: only the owner, only close
hrp.Position = Vector3.new(0, 5, 0)
handler(P, "start", "FindCache")
local run = SAS.Running(P)
check(run == "FindCache", "cache activity running")
local pr = prompts[#prompts]
local crate = pr and pr.Parent
local other = { UserId = 1, Parent = true }
pr.Triggered:Fire(other)
check(SAS.Running(P) == "FindCache", "another player's trigger is ignored")
hrp.Position = crate.Position + Vector3.new(40, 0, 0)
pr.Triggered:Fire(P)
check(SAS.Running(P) == "FindCache", "the owner's trigger from 40 studs is ignored")
hrp.Position = crate.Position + Vector3.new(3, 0, 0)
local before = cash
pr.Triggered:Fire(P)
check(SAS.Running(P) == nil and cash == before + 4000, "the owner opening it close by pays $4000 once")
check(rawget(crate, "__destroyed") == true, "the cache crate is removed")
-- Convoy: leaving the zone fails it
hrp.Position = Vector3.new(0, 5, 300)
handler(P, "start", "HawkConvoy")
check(SAS.Running(P) == "HawkConvoy" and #groupIds() == 3, "convoy wave 1 spawned")
hrp.Position = Vector3.new(0, 5, 700)
for _ = 1, 10 do SAS._Tick(1) end
check(SAS.Running(P) == nil and #groupIds() == 0, "convoy failed after leaving the zone; NPCs removed")
check(cash == 6000 + 7500 + 4000, "no payout for a failed convoy (still $17,500)")
-- text rules
for _, d in ipairs(SAC.Activities) do
  check(#d.Title <= 24 and #d.Desc <= 42 and not string.find(string.lower(d.Desc), "click") and #d.Short <= 12, d.Id .. " copy fits (title <= 24, desc <= 42, no 'click')")
end
print(string.format("SITES TEST: %d failed", fails))
if fails > 0 then error("failed") end
'''

chunks = [PRELUDE, EXTRA]
for key, path in MODS.items():
    chunks.append("SOURCES[%r] = function(script)\n%s\nend" % (key, path.read_text(encoding="utf-8")))
chunks.append(TEST)
with tempfile.NamedTemporaryFile("w", suffix=".luau", delete=False, encoding="utf-8") as f:
    f.write("\n".join(chunks))
    path = f.name
luau = os.environ.get("LUAU", "luau")
r = subprocess.run([luau, path], capture_output=True, text=True)
out = r.stdout.strip()
print(out if os.environ.get("VERBOSE") else ("\n".join(l for l in out.splitlines() if l.startswith("FAIL") or l.startswith("SITES TEST")) or out))
if r.returncode != 0:
    print(r.stderr.strip()[-2000:])
    sys.exit(1)
