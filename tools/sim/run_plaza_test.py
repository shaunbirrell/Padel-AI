"""claude-bud JOB 32 (v133 Code Bot: the facade detail, the real hatch; see tools/sim/run_hatch_test.py for the climb):
real-code tests in the Luau CLI (stand-ins from run_kit_detail_test.PRELUDE).

1. PLAZA HOUSE: the real WorldKits builds the enterable PlazaHouse for a TownHouse row flagged Enterable:
   * v133: PLAZA_PARTS parts (the facade); Add returns the TownHouse's plain count; ExtraParts / Finish keep the budgets on the plain kit;
   * the door gap (6 x 8) and every window gap hold no COLLIDING part (v133: the glass never collides and never
     answers a ray, so walkers, shots and sight pass as before);
   * the ramp is walkable (<= 45 degrees), its foot has >= 2 studs of floor in front, and no floor part covers it;
   * no roof part covers the hatch opening (v133: x -8 .. -2.4, z 2.6 .. 7.9; the climb is run_hatch_test.py);
   * the parapet stands 3-3.5 above the roof (shoot over it);
   * the building stays inside the TownHouse core it replaces, the facade reaching <= 1 stud out of the front (v133:
     WorldPOI's road / plaza-ring keep-outs measure the row's part box; its disc radius stays <= 12.8);
   * Enterables: inside / on the roof = this building; 3 studs outside = none; the army's waiting point is out in the
     street in front of the door.
2. LOS RULE: the real Shared/Util/LosRule against a scripted ray world:
   * a shot steps over a non-colliding sign and stops on the wall behind it;
   * a shot stops on a character's non-colliding limb, but a sight check does not;
   * the caller's params are never grown;
   * with Unified = false it is the plain raycast.
Run: LUAU=path/to/luau(.exe) python tools/sim/run_plaza_test.py   (exit 1 on any failure)"""
import os
import subprocess
import sys
import tempfile
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from run_kit_detail_test import PRELUDE  # noqa: E402

PLAZA_PARTS = 141  # v133: WorldKits.Part parts per PlazaHouse (+ the ladder TrussPart); PlazaBuildingsConfig.Parts - 1

ROOT = Path(__file__).resolve().parents[2]
SH = ROOT / "src/ReplicatedStorage/Shared"
SV = ROOT / "src/ServerScriptService/Server"
MODS = {
    "Configs/WorldConfig": SH / "Configs/WorldConfig.luau",
    "Configs/WorldDetailConfig": SH / "Configs/WorldDetailConfig.luau",
    "Configs/PlazaBuildingsConfig": SH / "Configs/PlazaBuildingsConfig.luau",
    "Configs/CombatConfig": SH / "Configs/CombatConfig.luau",
    "Modules/WorldKits": SV / "Modules/WorldKits.luau",
    "Modules/Enterables": SV / "Modules/Enterables.luau",
    "Util/LosRule": SH / "Util/LosRule.luau",
}

EXTRA = r'''
-- a scripted ray world for LosRule: WORLD = the parts along the ray, in order
WORLD = {}
local PARAMS = {}
PARAMS.__index = PARAMS
RaycastParams = { new = function() return setmetatable({ FilterDescendantsInstances = {}, RespectCanCollide = false, IgnoreWater = false, __added = 0 }, PARAMS) end }
function PARAMS:AddToFilter(i) local l = table.clone(self.FilterDescendantsInstances); table.insert(l, i); self.FilterDescendantsInstances = l; self.__added += 1 end
local function filtered(params, part)
  for _, f in ipairs(params.FilterDescendantsInstances) do if f == part then return true end end
  return false
end
local WS = { Raycast = function(_, o, d, params)
  for _, part in ipairs(WORLD) do
    if not filtered(params, part) and (not params.RespectCanCollide or part.CanCollide) then return { Instance = part, Position = Vector3.new(0, 0, 0) } end
  end
  return nil end }
local prevGame = game
game = { GetService = function(_, n) if n == "Workspace" then return WS end return prevGame:GetService(n) end }
'''

TEST = r'''
local PLAZA_PARTS = __PLAZA_PARTS__
local fails = 0
local function check(ok, msg) print((ok and "ok    " or "FAIL  ") .. msg); if not ok then fails += 1 end end
local WK = require(node("Modules/WorldKits"))
local ENT = require(node("Modules/Enterables"))
local frame = CFrame.new(0, 0.5, 0)
-- record every part made
local rec = {}
local realPart = WK.Part
WK.Part = function(ps, parent) local p = realPart(ps, parent); table.insert(rec, p); return p end
local cluster = Instance.new("Model"); cluster.Name = "NE_E1"
local plain = WK.Footprint("TownHouse", { Variant = "walkup" })
rec = {} -- the Footprint's throw-away build is not the building
local ret = WK.Add(cluster, "TownHouse", frame, { Variant = "walkup", Enterable = true })
local live = {}
for _, p in ipairs(rec) do if not rawget(p, "__destroyed") then table.insert(live, p) end end
check(#live == PLAZA_PARTS, "PlazaHouse: " .. PLAZA_PARTS .. " Parts + the ladder TrussPart (" .. #live .. " Parts)")
local PBC0 = require(node("Configs/PlazaBuildingsConfig"))
check(PBC0.Parts == PLAZA_PARTS + 1, "PlazaBuildingsConfig.Parts = " .. (PLAZA_PARTS + 1) .. " (" .. tostring(PBC0.Parts) .. ")")
check(PBC0.MaxExtraParts >= 4 * (PLAZA_PARTS + 1 - (plain and plain.Parts or 0)), "MaxExtraParts holds all 4 plaza houses (" .. tostring(PBC0.MaxExtraParts) .. ")")
local glassN, glassBad = 0, 0
for _, p in ipairs(live) do
  if p.Name == "PlazaWindowGlass" then glassN += 1; if p.CanCollide or p.CanQuery or p.Transparency < 0.3 then glassBad += 1 end end
end
check(glassN >= 9 and glassBad == 0, "window glass: " .. glassN .. " panes, all see-through, none collide or answer a ray (" .. glassBad .. " bad)")
local small, shadowSmall = 0, 0
for _, p in ipairs(live) do
  if math.max(p.Size.X, p.Size.Y, p.Size.Z) < 8 then small += 1; if p.CastShadow then shadowSmall += 1 end end
end
check(shadowSmall == 0, "no small part casts a shadow (" .. shadowSmall .. " of " .. small .. ")")
check(plain ~= nil and ret == plain.Parts, "Add returns the TownHouse plain count " .. tostring(ret))
check(WK.ExtraParts(cluster) == PLAZA_PARTS + 1 - (plain and plain.Parts or 0), "ExtraParts = Parts - plain (" .. WK.ExtraParts(cluster) .. ")")
-- local boxes of every part
local boxes = {}
for _, p in ipairs(live) do
  local rel = frame:ToObjectSpace(p.CFrame); local s = p.Size
  local r, u, l = rel.RightVector * s.X * 0.5, rel.UpVector * s.Y * 0.5, rel.LookVector * s.Z * 0.5
  local hx = math.abs(r.X) + math.abs(u.X) + math.abs(l.X)
  local hy = math.abs(r.Y) + math.abs(u.Y) + math.abs(l.Y)
  local hz = math.abs(r.Z) + math.abs(u.Z) + math.abs(l.Z)
  local c = rel.Position
  table.insert(boxes, { N = p.Name, X0 = c.X - hx, X1 = c.X + hx, Y0 = c.Y - hy, Y1 = c.Y + hy, Z0 = c.Z - hz, Z1 = c.Z + hz, Collide = p.CanCollide, Shape = p.Shape })
end
local function hits(x0, x1, y0, y1, z0, z1, skipName)
  local n = {}
  for _, b in ipairs(boxes) do
    if b.N ~= skipName and b.Collide and b.X0 < x1 - 0.01 and b.X1 > x0 + 0.01 and b.Y0 < y1 - 0.01 and b.Y1 > y0 + 0.01 and b.Z0 < z1 - 0.01 and b.Z1 > z0 + 0.01 then table.insert(n, b.N) end
  end
  return n
end
local D, W = 17.4, 17.6
-- the door gap: x -2.9 .. 2.9, y 0.35 .. 7.9, through the front wall (z -8.7 .. -7.9)
local d = hits(-2.9, 2.9, 0.35, 7.9, -8.7, -7.9)
check(#d == 0, "door gap 5.8 x 7.5 is empty (" .. table.concat(d, ",") .. ")")
-- windows (front, storey 1 and 2; back / sides upstairs)
local wins = {
  { -7.1, -3.7, 4.1, 7.3, -8.7, -7.9, "front L1" }, { 3.7, 7.1, 4.1, 7.3, -8.7, -7.9, "front R1" },
  { -7.1, -3.7, 14.6, 17.9, -8.7, -7.9, "front L2" }, { -1.7, 1.7, 14.6, 17.9, -8.7, -7.9, "front C2" }, { 3.7, 7.1, 14.6, 17.9, -8.7, -7.9, "front R2" },
  { -1.7, 1.7, 14.6, 17.9, 7.9, 8.7, "back 2" },
}
for _, w in ipairs(wins) do
  local h = hits(w[1], w[2], w[3], w[4], w[5], w[6])
  check(#h == 0, "window " .. w[7] .. " is an open gap (" .. table.concat(h, ",") .. ")")
end
-- the stair
local stair
for _, b in ipairs(boxes) do if b.N == "PlazaStair" then stair = b end end
check(stair ~= nil, "the ramp exists")
if stair then
  local rise, run = stair.Y1 - stair.Y0, stair.Z1 - stair.Z0
  check(math.deg(math.atan2(rise, run)) <= 45, string.format("ramp slope %.1f deg <= 45", math.deg(math.atan2(rise, run))))
  check(stair.Z0 - (-D * 0.5 + 0.8) >= 2, string.format("floor in front of the ramp foot %.1f >= 2", stair.Z0 - (-D * 0.5 + 0.8)))
  check(math.abs(stair.Y1 - 11.4) < 0.05, "the ramp top meets the upper floor (y " .. string.format("%.2f", stair.Y1) .. ")")
  local cover = {}
  for _, b in ipairs(boxes) do
    if b.N == "PlazaFloor" and b.Y0 > 5 and b.X0 < stair.X1 - 0.05 and b.X1 > stair.X0 + 0.05 and b.Z0 < stair.Z1 - 0.05 and b.Z1 > stair.Z0 + 0.05 then table.insert(cover, b.N) end
  end
  check(#cover == 0, "no upper floor covers the ramp (stair hole)")
end
-- the roof hatch opening (v133: x -8 .. -2.4, z 2.6 .. 7.9)
local roofTop = -math.huge
for _, b in ipairs(boxes) do if b.N == "PlazaRoof" then roofTop = math.max(roofTop, b.Y1) end end
local hatch = {}
for _, b in ipairs(boxes) do if b.N == "PlazaRoof" and b.X0 < -2.45 and b.X1 > -7.95 and b.Z0 < 7.85 and b.Z1 > 2.65 then table.insert(hatch, b.N) end end
check(#hatch == 0, "no roof part covers the hatch")
check(math.abs(roofTop - 22.8) < 0.05, "roof top 22.8")
-- the ladder is a TrussPart made by truss() (not WorldKits.Part): its span is pinned in tools/checks/claude_bud_job32.py
-- parapet
local ptop = -math.huge
for _, b in ipairs(boxes) do if b.N == "PlazaParapet" then ptop = math.max(ptop, b.Y1) end end
check(ptop - roofTop >= 3 and ptop - roofTop <= 3.5, string.format("parapet %.1f above the roof (3-3.5: shoot over, duck behind)", ptop - roofTop))
-- inside the TownHouse core
local x0, x1, z0, z1 = math.huge, -math.huge, math.huge, -math.huge
for _, b in ipairs(boxes) do x0, x1, z0, z1 = math.min(x0, b.X0), math.max(x1, b.X1), math.min(z0, b.Z0), math.max(z1, b.Z1) end
check(x0 >= -W * 0.5 - 0.05 and x1 <= W * 0.5 + 0.05 and z0 >= -D * 0.5 - 1.05 and z1 <= D * 0.5 + 0.05, string.format("footprint x %.2f..%.2f z %.2f..%.2f inside the 17.6 x 17.4 core (+1 out of the front)", x0, x1, z0, z1))
local discR = 0.5 * math.sqrt((x1 - x0) ^ 2 + (z1 - z0) ^ 2)
check(discR <= 12.8, string.format("WorldPOI disc radius %.2f <= 12.8 (road >= 30 and the plaza capture ring keep their margin)", discR))
-- Enterables
local e = ENT.At(Vector3.new(2, 3.5, 2))
check(e ~= nil and e.Id == "NE_E1", "inside the ground floor = this building")
check(ENT.At(Vector3.new(0, 25, 0)) ~= nil, "on the roof = this building")
check(ENT.At(Vector3.new(0, 3.5, -12)) == nil, "3 studs out in the street = none")
check(e ~= nil and math.abs(e.Door.Z - (-D * 0.5 - 10)) < 0.05 and math.abs(e.Door.X) < 0.05, "the army waits 10 studs out in front of the door")
check(e ~= nil and e.Face.Z > 0.99, "the army faces the building (its block forms out in the street)")
-- the kill switch
local PBC = require(node("Configs/PlazaBuildingsConfig"))
PBC.Enabled = false
rec = {}
local c2 = Instance.new("Model")
WK.Add(c2, "TownHouse", frame, { Variant = "walkup", Enterable = true })
local n2 = 0
for _, p in ipairs(rec) do if not rawget(p, "__destroyed") then n2 += 1 end end
check(n2 == plain.Parts, "Enabled = false: the solid TownHouse (" .. n2 .. " parts)")
WK.Part = realPart

-- ── LosRule ──
local LR = require(node("Util/LosRule"))
local function part(name, collide, parent) local p = Instance.new("Part"); p.Name = name; p.CanCollide = collide; p.Parent = parent; p.IsA = function(_, c) return c == "BasePart" end; p.FindFirstChildOfClass = function() return nil end; return p end
local sign = part("Sign", false)
local wall = part("Wall", true)
local charModel = Instance.new("Model"); charModel.IsA = function(_, c) return c == "Model" end; charModel.FindFirstChildOfClass = function(_, c) if c == "Humanoid" then return {} end end
local arm = part("LeftUpperArm", false, charModel)
local params = RaycastParams.new()
WORLD = { sign, wall }
local r = LR.HitCast(Vector3.new(0, 0, 0), Vector3.new(0, 0, -10), params)
check(r ~= nil and r.Instance == wall, "a shot steps over the see-through sign and stops on the wall")
check(params.__added == 0, "the caller's params were not grown")
WORLD = { sign, arm, wall }
r = LR.HitCast(Vector3.new(0, 0, 0), Vector3.new(0, 0, -10), params)
check(r ~= nil and r.Instance == arm, "a shot stops on a character's (non-colliding) limb")
local sp = RaycastParams.new(); sp.RespectCanCollide = LR.SightRespect(false)
check(sp.RespectCanCollide == true, "sight rays always skip non-colliding parts while the rule is on")
check(WS:Raycast(Vector3.new(0, 0, 0), Vector3.new(0, 0, -10), sp).Instance == wall, "a sight check passes the limb and the sign, stops on the wall")
WORLD = { part("Window gap?", false) }
check(LR.HitCast(Vector3.new(0, 0, 0), Vector3.new(0, 0, -10), params) == nil, "nothing solid on the line: the shot is clear")
local CC = require(node("Configs/CombatConfig"))
CC.LineOfSight.Unified = false
WORLD = { sign, wall }
r = LR.HitCast(Vector3.new(0, 0, 0), Vector3.new(0, 0, -10), RaycastParams.new())
check(r ~= nil and r.Instance == sign, "Unified = false: the plain raycast (stops on the sign, as before)")
check(LR.SightRespect(false) == false, "Unified = false: each shooter's own RespectCanCollide")
print(string.format("PLAZA TEST: %d failed", fails))
if fails > 0 then error("failed") end
'''

chunks = [PRELUDE, EXTRA]
for key, path in MODS.items():
    chunks.append("SOURCES[%r] = function(script)\n%s\nend" % (key, path.read_text(encoding="utf-8")))
chunks.append(TEST.replace("__PLAZA_PARTS__", str(PLAZA_PARTS)))
with tempfile.NamedTemporaryFile("w", suffix=".luau", delete=False, encoding="utf-8") as f:
    f.write("\n".join(chunks))
    path = f.name
luau = os.environ.get("LUAU", "luau")
r = subprocess.run([luau, path], capture_output=True, text=True)
out = r.stdout.strip()
print(out if os.environ.get("VERBOSE") else ("\n".join(l for l in out.splitlines() if l.startswith("FAIL") or l.startswith("PLAZA TEST")) or out))
if r.returncode != 0:
    print(r.stderr.strip()[-2000:])
    sys.exit(1)
