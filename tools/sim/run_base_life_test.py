"""claude-bud JOB 57: base life, on the REAL BaseLifeConfig + BaseLifeService + WorldKits (+ StorePropsConfig, CombatConfig,
BaseLayoutConfig, PlotFrame) in the Luau CLI (stand-ins: run_kit_detail_test.PRELUDE; the ground ray hits y = 0).

1. PROPS: one owned plot gets the BaseLife rows: >= 30 parts (a lived-in base), <= StorePropsConfig.Budget.
   MaxBasePartsPerPlot (600, the JOB 40 C allowance); no row in StorePropsConfig.BaseKeepOut, on a road, on a structure
   site or on a kiosk / console spot (conservative footprints from BaseLayoutConfig).
2. ROUTES: every patrol leg stays clear of the structures, the props and the keep-out boxes.
3. SOLDIERS: PerBase (3) per owned plot; 10 owned plots never exceed ServerMax = CombatConfig.MaxActiveNPCs (18); every
   part CanQuery off, no rifle, a Humanoid, not a CombatService NPC.
4. BRAIN: IDLE -> PATROL when the idle time is up (MoveTo the next route point), PATROL -> IDLE on arrival or after
   LegTimeout (blocked), and round the loop.
5. Owner-first: another owner gets nothing; Clear gives the soldiers back.
Run: LUAU=path/to/luau(.exe) python tools/sim/run_base_life_test.py   (exit 1 on any failure; VERBOSE=1 prints all)"""
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
    "Configs/BaseLifeConfig": SH / "Configs/BaseLifeConfig.luau",
    "Configs/StorePropsConfig": SH / "Configs/StorePropsConfig.luau",
    "Configs/CombatConfig": SH / "Configs/CombatConfig.luau",
    "Configs/RetentionConfig": SH / "Configs/RetentionConfig.luau",
    "Configs/AdminConfig": SH / "Configs/AdminConfig.luau",
    "Configs/EconomyConfig": SH / "Configs/EconomyConfig.luau",
    "Configs/BaseConfig": SH / "Configs/BaseConfig.luau",
    "Configs/BaseLayoutConfig": SH / "Configs/BaseLayoutConfig.luau",
    "Configs/BusinessConfig": SH / "Configs/BusinessConfig.luau",
    "Configs/WorldConfig": SH / "Configs/WorldConfig.luau",
    "Configs/WorldDetailConfig": SH / "Configs/WorldDetailConfig.luau",
    "Util/PlotFrame": SH / "Util/PlotFrame.luau",
    "Modules/WorldKits": SV / "Modules/WorldKits.luau",
    "Services/BaseLifeService": SV / "Services/BaseLifeService.luau",
}

TEST = r'''
local fails = 0
local function check(ok, msg) print((ok and "ok    " or "FAIL  ") .. msg); if not ok then fails += 1 end end
task = { spawn = function() end, delay = function() end, defer = function() end, wait = function() end }
RaycastParams = { new = function() return {} end }
Random = { new = function() return { NextNumber = function(_, a, b) return (a + b) / 2 end } end }
local function findIn(s, n) for _, c in ipairs(s:GetChildren()) do if c.Name == n then return c end end return nil end
local WS = Instance.new("Workspace")
WS.Raycast = function(_, from) return { Position = Vector3.new(from.X, 0, from.Z) } end
WS.FindFirstChild = findIn
local prevG = game
game = { GetService = function(_, n)
  if n == "Workspace" then return WS end
  if n == "Players" then return { GetPlayers = function() return {} end, PlayerRemoving = { Connect = function() end } } end
  if n == "RunService" then return { IsStudio = function() return false end } end
  return prevG:GetService(n) end }
local rn = Instance.new
Instance.new = function(cls)
  local o = rn(cls)
  o.FindFirstChild = findIn
  if cls == "Model" then o.DescendantAdded = { Connect = function() end }; o.Destroy = function(s) s.Parent = nil end end
  if cls == "Humanoid" then o.Health = 100; o.MoveTo = function(s, p) s.__to = p end end
  return o
end

local BL = require(node("Configs/BaseLifeConfig"))
local SP = require(node("Configs/StorePropsConfig"))
local CC = require(node("Configs/CombatConfig"))
local LC = require(node("Configs/BaseLayoutConfig"))
local WK = require(node("Modules/WorldKits"))
local SVC = require(node("Services/BaseLifeService"))
local OWNER, OTHER = 470626172, 9
local CAP = SP.Budget.MaxBasePartsPerPlot

-- conservative no-build boxes (plot-local): roads, structure sites, kiosks / consoles, keep-out
local boxes = {}
for _, r in ipairs(LC.Roads) do table.insert(boxes, { X = r.X, Z = r.Z, HX = r.SizeX / 2 + 1, HZ = r.SizeZ / 2 + 1, N = "road " .. r.Name }) end
for id, st in pairs(LC.Structures) do
  local h = if st.WalkIn then 22 else 14
  table.insert(boxes, { X = st.Site.X, Z = st.Site.Z, HX = h, HZ = h, N = "structure " .. id })
  local k = st.Kiosk or st.Console
  if st.Kiosk then table.insert(boxes, { X = st.Kiosk.X, Z = st.Kiosk.Z, HX = 5, HZ = 5, N = "kiosk " .. id }) end
end
for _, k in ipairs(SP.BaseKeepOut) do table.insert(boxes, { X = k.X, Z = k.Z, HX = k.HX, HZ = k.HZ, N = "keep-out" }) end
local function hits(x, z, hx, hz, skipRoads)
  for _, b in ipairs(boxes) do
    if not (skipRoads and string.sub(b.N, 1, 4) == "road") and math.abs(x - b.X) < b.HX + hx and math.abs(z - b.Z) < b.HZ + hz then return b.N end
  end
  return nil
end

-- 1. props on clear ground
local bad = {}
for _, row in ipairs(BL.Props) do
  local s = WK.Specs[row.Kit]
  local r = if s then math.max(s.Size.X, s.Size.Z) / 2 else 4
  local h = hits(row.X, row.Z, r, r, false)
  if s == nil or h then table.insert(bad, row.Kit .. "@" .. row.X .. "," .. row.Z .. " -> " .. tostring(h or "no kit")) end
end
check(#bad == 0, "every prop row on clear ground (no road / structure / kiosk / keep-out): " .. (if #bad == 0 then #BL.Props .. " rows" else table.concat(bad, "; ")))
local parts, n = SVC.Sync(1, OWNER)
check(parts >= 30 and parts <= CAP, string.format("plot 1 props: %d parts (>= 30, <= the per-plot allowance %d)", parts, CAP))

-- 2. routes clear of structures, props and keep-out (roads are walkable)
local blocked = {}
local propBoxes = {}
for _, row in ipairs(BL.Props) do local s = WK.Specs[row.Kit]; table.insert(propBoxes, { X = row.X, Z = row.Z, R = math.max(s.Size.X, s.Size.Z) / 2 }) end
for ri, route in ipairs(BL.Soldiers.Routes) do
  for i = 1, #route do
    local a, b = route[i], route[i % #route + 1]
    for t = 0, 1, 0.05 do
      local x, z = a.X + (b.X - a.X) * t, a.Z + (b.Z - a.Z) * t
      local h = hits(x, z, 1.5, 1.5, true)
      for _, p in ipairs(propBoxes) do if math.abs(x - p.X) < p.R + 1.5 and math.abs(z - p.Z) < p.R + 1.5 then h = "a prop" end end
      if h then table.insert(blocked, string.format("route %d leg %d (%.0f,%.0f) -> %s", ri, i, x, z, h)); break end
    end
  end
end
check(#blocked == 0, "every patrol leg is clear (structures, props, keep-out): " .. (if #blocked == 0 then #BL.Soldiers.Routes .. " routes" else table.concat(blocked, "; ")))

-- 3. soldiers
check(n == BL.Soldiers.PerBase, string.format("plot 1: %d ambient soldiers (PerBase %d)", n, BL.Soldiers.PerBase))
local f1 = findIn(WS:FindFirstChild("WE_BaseLife"), "Plot1")
local soldierBad, soldiers = 0, 0
for _, m in ipairs(f1:GetChildren()) do
  if m.Name == "BaseLifeSoldier" then
    soldiers += 1
    local hum = false
    for _, d in ipairs(m:GetDescendants()) do
      if d.ClassName == "Part" and d.CanQuery ~= false then soldierBad += 1 end
      if string.find(tostring(d.Name), "Rifle") then soldierBad += 1 end
      if d.ClassName == "Humanoid" then hum = true end
    end
    if not hum or m:GetAttribute("WE_Ambient") ~= true then soldierBad += 1 end
  end
end
check(soldiers == n and soldierBad == 0, "every soldier: CanQuery off (shots pass through), no rifle, a Humanoid, WE_Ambient (not a CombatService NPC)")
for plotId = 2, 10 do SVC.Sync(plotId, OWNER) end
check(SVC.Count() <= CC.MaxActiveNPCs and SVC.ServerMax() == CC.MaxActiveNPCs, string.format("10 owned plots: %d soldiers in the server (<= CombatConfig.MaxActiveNPCs %d)", SVC.Count(), CC.MaxActiveNPCs))

-- 4. the brain
check(BL.Next("IDLE", { Now = 5, IdleUntil = 6, LegStarted = 0, Dist = 10 }) == "IDLE" and BL.Next("IDLE", { Now = 6, IdleUntil = 6, LegStarted = 0, Dist = 10 }) == "PATROL", "IDLE -> PATROL when the idle time is up")
check(BL.Next("PATROL", { Now = 3, IdleUntil = 0, LegStarted = 0, Dist = 1 }) == "IDLE" and BL.Next("PATROL", { Now = 3, IdleUntil = 0, LegStarted = 0, Dist = 10 }) == "PATROL"
  and BL.Next("PATROL", { Now = BL.Soldiers.LegTimeout, IdleUntil = 0, LegStarted = 0, Dist = 10 }) == "IDLE", "PATROL -> IDLE on arrival or after the leg timeout (blocked)")
local T = 1000
SVC._clock = function() return T end
SVC.Sync(1, OWNER)
local s1
for _, m in ipairs(findIn(WS:FindFirstChild("WE_BaseLife"), "Plot1"):GetChildren()) do if m.Name == "BaseLifeSoldier" then s1 = m; break end end
local hum
for _, d in ipairs(s1 and s1:GetChildren() or {}) do if d.ClassName == "Humanoid" then hum = d end end -- (the stand-in has no default Name)
T += 10; SVC.Step()
local to1 = hum and hum.__to
check(to1 ~= nil, "after the idle time: walking to the next route point")
local rootP = s1:FindFirstChild("HumanoidRootPart")
rootP.CFrame = CFrame.new(to1.X, 3, to1.Z)
T += 1; SVC.Step()
local idleTo = hum.__to
check(idleTo ~= nil and (idleTo - rootP.Position).Magnitude < 1e-6, "arrived: IDLE (stands still)")
T += 10; SVC.Step()
check(hum.__to ~= nil and (hum.__to - to1).Magnitude > 1, "idle over: on to the following point (round the loop)")

-- 5. owner-first + clear
local before = SVC.Count()
local p2, n2 = SVC.Sync(11, OTHER)
check(p2 == 0 and n2 == 0, "another owner while OwnerFirst: no props, no soldiers (OFF = today)")
SVC.Clear(1)
check(SVC.Count() < before and findIn(WS:FindFirstChild("WE_BaseLife"), "Plot1") == nil, "the owner leaves: his props and soldiers go")

print(string.format("BASE LIFE LUA: %d failed", fails))
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
    r = subprocess.run([os.environ.get("LUAU", "luau"), path], capture_output=True, text=True)
    out = r.stdout.strip().splitlines()
    fails = 0
    if r.returncode != 0 or "BASE LIFE LUA: 0 failed" not in r.stdout:
        fails = 1
        out.append(r.stderr.strip()[-2500:])
    out.append("BASE LIFE TEST: %d failed" % fails)
    print("\n".join(out) if os.environ.get("VERBOSE") else "\n".join(l for l in out if l.startswith(("FAIL", "BASE LIFE TEST"))))
    sys.exit(1 if fails else 0)


if __name__ == "__main__":
    main()
