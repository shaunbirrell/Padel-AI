"""claude-bud JOB 58: real aircraft / boat bodies in the hangar and at the dock, on the REAL HangarDockConfig +
HangarDockDisplayService (stand-ins: run_kit_detail_test.PRELUDE; VisualAssetService.CloneDisplayBody is a recording stub
that returns a body or nil).

1. FRAMES: the hangar body faces the Part jet's nose and sits on the hangar floor; the dock body faces the Part boat's
   bow, keel in the water; the body's own Yaw turns it like a driven body.
2. PLACED: two jet slots + the boat get bodies (FighterJet, ReconPlane, the first allowed boat); ONLY then the Part
   pieces under them are hidden (Transparency 1, no collide / query, WE_DisplayHidden); a piece far away stays.
3. FALLBACK: no body (not allowed / not loaded) -> nothing hidden, the Part build stays exactly.
4. Owner-first: another owner gets nothing.
Run: LUAU=path/to/luau(.exe) python tools/sim/run_hangar_dock_test.py   (exit 1 on any failure; VERBOSE=1 prints all)"""
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
    "Configs/HangarDockConfig": SH / "Configs/HangarDockConfig.luau",
    "Configs/RetentionConfig": SH / "Configs/RetentionConfig.luau",
    "Configs/AdminConfig": SH / "Configs/AdminConfig.luau",
    "Configs/EconomyConfig": SH / "Configs/EconomyConfig.luau",
    "Services/HangarDockDisplayService": SV / "Services/HangarDockDisplayService.luau",
}

TEST = r'''
local fails = 0
local function check(ok, msg) print((ok and "ok    " or "FAIL  ") .. msg); if not ok then fails += 1 end end
task = { spawn = function() end, delay = function() end, defer = function() end, wait = function() end }
local mt = getmetatable(Vector3.new(0, 0, 0))
local oldIdx = mt.__index
mt.__index = function(t, k)
  if k == "Cross" then return function(a, b) return Vector3.new(a.Y * b.Z - a.Z * b.Y, a.Z * b.X - a.X * b.Z, a.X * b.Y - a.Y * b.X) end end
  return oldIdx(t, k)
end
CFrame.lookAt = function(p, target)
  local f = (target - p).Unit
  local r = f:Cross(Vector3.new(0, 1, 0)).Unit
  local u = r:Cross(f)
  return CFrame.new(p.X, p.Y, p.Z, r.X, u.X, -f.X, r.Y, u.Y, -f.Y, r.Z, u.Z, -f.Z)
end
local function findIn(s, n) for _, c in ipairs(s:GetChildren()) do if c.Name == n then return c end end return nil end
local WS = Instance.new("Workspace")
WS.FindFirstChild = findIn
local prevG = game
game = { GetService = function(_, n)
  if n == "Workspace" then return WS end
  if n == "Players" then return { GetPlayers = function() return {} end, PlayerRemoving = { Connect = function() end }, GetPlayerByUserId = function() return nil end } end
  if n == "RunService" then return { IsStudio = function() return false end } end
  return prevG:GetService(n) end }
local rn = Instance.new
Instance.new = function(cls)
  local o = rn(cls)
  o.FindFirstChild = findIn
  o.GetPropertyChangedSignal = function() return { Connect = function() end } end
  return o
end

local HC = require(node("Configs/HangarDockConfig"))
-- codebot_v220 (Shaun 2026-10-02 07:51: everything public): HC.OwnerFirst = false live; the owner-first paths
-- below are still proved with OwnerFirst = true, and a non-owner is live once it is restored (end of test)
local __V220_LAUNCHED = HC.OwnerFirst
check(__V220_LAUNCHED == false, "codebot_v220: HC.OwnerFirst = false (public for everyone)")
HC.OwnerFirst = true
local HD = require(node("Services/HangarDockDisplayService"))
local OWNER, OTHER = 470626172, 9

-- the plot: Workspace.WarEmpireSetup.Bases.Plot4 with two Part jets and the Part boat
local setup = Instance.new("Folder"); setup.Name = "WarEmpireSetup"; setup.Parent = WS
local bases = Instance.new("Folder"); bases.Name = "Bases"; bases.Parent = setup
local plot = Instance.new("Folder"); plot.Name = "Plot4"; plot.Parent = bases
local function piece(name, cf, size) local p = Instance.new("Part"); p.Name = name; p.CFrame = cf; p.Size = size; p.Transparency = 0; p.CanCollide = true; p.Parent = plot; return p end
local function partJet(x, z)
  local f = CFrame.new(x, 2.8, z) -- the jet frame (+Z = nose), floor y 0.4
  piece("JetFuselage", f * CFrame.Angles(0, math.rad(90), 0), Vector3.new(15, 2.2, 2.2))
  piece("JetWing", f * CFrame.new(0, -0.3, -0.5), Vector3.new(12, 0.3, 4.4))
  piece("JetFin", f * CFrame.new(0, 2.4, -6), Vector3.new(0.3, 3.2, 2.6))
end
partJet(-11.5, 0); partJet(7.5, -1.5)
local farWing = piece("JetWing", CFrame.new(60, 2.5, 0), Vector3.new(12, 0.3, 4.4))
local hull = piece("BoatHull", CFrame.new(200, 1.65, 29), Vector3.new(13, 1.5, 6))
piece("BoatDeck", CFrame.new(201, 2.6, 29), Vector3.new(16, 0.4, 5))
piece("BoatWheelhouse", CFrame.new(203, 5, 29), Vector3.new(5, 6, 4))

-- 1. frames
local jetCf = CFrame.new(0, 2.8, 0) * CFrame.Angles(0, math.rad(90), 0)
local fH = HD.FrameFor("Hangar", jetCf, Vector3.new(15, 2.2, 2.2), 0)
check(math.abs(fH.LookVector:Dot(Vector3.new(0, 0, 1)) - 1) < 1e-6 and math.abs(fH.Y - 0.4) < 1e-6, string.format("hangar: the body faces the Part jet's nose (+Z) on the floor (y %.2f)", fH.Y))
local fH180 = HD.FrameFor("Hangar", jetCf, Vector3.new(15, 2.2, 2.2), 180)
check(math.abs(fH180.LookVector:Dot(Vector3.new(0, 0, -1)) - 1) < 1e-6, "a body Yaw of 180 turns it round, like a driven body")
local fD = HD.FrameFor("Dock", hull.CFrame, hull.Size, 0)
check(math.abs(fD.LookVector:Dot(Vector3.new(1, 0, 0)) - 1) < 1e-6 and fD.Y < hull.CFrame.Y - hull.Size.Y / 2, string.format("dock: the body faces the bow (+X), keel in the water (y %.2f)", fD.Y))

-- 2. placed (the stub returns a body for every allowed id)
local ASKED = {}
local allowed = { FighterJet = true, ReconPlane = true, LandingCraft = true }
local VAS = { CloneDisplayBody = function(vid, owner, fit)
  table.insert(ASKED, vid)
  if not allowed[vid] then return nil, 0 end
  local m = rn("Model")
  m.Name = "WE_Display_" .. vid
  m.FindFirstChild = findIn
  m.PivotTo = function(s, cf) s.__pv = cf end
  m.GetPivot = function(s) return s.__pv end
  m.GetBoundingBox = function(s) return s.__pv, Vector3.new(fit, 4, fit * 0.7) end
  return m, if vid == "FighterJet" then 180 else 0
end }
HD.Init({ VisualAssetService = VAS })
local n = HD.Sync(4, OWNER)
local disp = findIn(WS:FindFirstChild("WE_HangarDock"), "Plot4")
local names = {}
for _, c in ipairs(disp and disp:GetChildren() or {}) do table.insert(names, c.Name) end
table.sort(names)
check(n == 3 and table.concat(names, ",") == "WE_Display_FighterJet,WE_Display_LandingCraft,WE_Display_ReconPlane", "two jet slots + the boat: " .. table.concat(names, ", "))
local hidden, shown = 0, 0
for _, p in ipairs(plot:GetChildren()) do
  if p ~= farWing then
    if p.Transparency == 1 and p.CanCollide == false and p.CanQuery == false and p:GetAttribute("WE_DisplayHidden") then hidden += 1 else shown += 1 end
  end
end
check(hidden == 9 and shown == 0, string.format("the Part jets / boat under the bodies are hidden (%d hidden, %d left showing)", hidden, shown))
check(farWing.Transparency == 0 and farWing:GetAttribute("WE_DisplayHidden") == nil, "a Part piece far from any body stays")
local boatBody = findIn(disp, "WE_Display_LandingCraft")
local bb, bs = boatBody:GetBoundingBox()
check(math.abs((bb.Y - bs.Y / 2) - fD.Y) < 1e-6, "the boat's lowest point sits on the waterline frame")

check(HD.Sync(4, OWNER) == 3 and #findIn(WS:FindFirstChild("WE_HangarDock"), "Plot4"):GetChildren() == 3, "a resync (an Airfield / Dock upgrade) puts all three back (hidden Part pieces still mark the slots)")
-- 3. fallback: nothing allowed
for _, p in ipairs(plot:GetChildren()) do p.Transparency = 0; p.CanCollide = true; p.__attr.WE_DisplayHidden = nil end
allowed = {}
local n0 = HD.Sync(4, OWNER)
local still = 0
for _, p in ipairs(plot:GetChildren()) do if p.Transparency == 0 and p:GetAttribute("WE_DisplayHidden") == nil then still += 1 end end
check(n0 == 0 and still == #plot:GetChildren(), "no body allowed / loaded: nothing hidden, the Part hangar jets and boat stay exactly")

-- 4. owner-first
allowed = { FighterJet = true, ReconPlane = true, LandingCraft = true }
check(HD.Sync(4, OTHER) == 0, "another owner while OwnerFirst: no showpieces (OFF = today)")

print(string.format("HANGAR DOCK LUA: %d failed", fails))
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
    if r.returncode != 0 or "HANGAR DOCK LUA: 0 failed" not in r.stdout:
        fails = 1
        out.append(r.stderr.strip()[-2500:])
    out.append("HANGAR DOCK TEST: %d failed" % fails)
    print("\n".join(out) if os.environ.get("VERBOSE") else "\n".join(l for l in out if l.startswith(("FAIL", "HANGAR DOCK TEST"))))
    sys.exit(1 if fails else 0)


if __name__ == "__main__":
    main()
