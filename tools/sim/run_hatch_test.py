"""v133 (Code Bot): the plaza-building roof hatch, CHARACTER-SIZED (Luau CLI, the real WorldKits + PRELUDE stand-ins).

Shaun's phone bug: "the ladder to the roof ends under a solid ceiling". The JOB 32 test only checked that no roof part
covered the 2 x 2 TrussPart footprint; a climber hangs on a FACE of the truss (about 4 wide with arms, 1.2 deep, 5 tall),
so this test sweeps a character box up every face of the ladder, for every plaza building (4 orientations):
  * CLIMB: at every feet height from the upper floor to the truss top, the climber box touches no colliding part
    (the truss itself excluded) on at least one face;
  * TOP: standing on the truss top (5 tall) is clear, and one step off it on some side is a free character box
    standing ON a roof part (support under it) - he walks off the ladder onto the roof;
  * NO TRAP: no face lets you start climbing from the floor and then hits something part-way up (the v132 bug:
    every face did); at least 2 faces climb all the way;
  * the hatch hole in the roof is at least 4.4 x 4.4 (a real opening, not the truss footprint);
  * a railing stands on the hatch's open (non-exit) edge; the hatch frame exists.
Run: LUAU=path/to/luau python tools/sim/run_hatch_test.py [--expect-fail]  (exit 1 on failure)"""
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
    "Configs/PlazaBuildingsConfig": SH / "Configs/PlazaBuildingsConfig.luau",
    "Configs/CombatConfig": SH / "Configs/CombatConfig.luau",
    "Modules/WorldKits": SV / "Modules/WorldKits.luau",
    "Modules/Enterables": SV / "Modules/Enterables.luau",
    "Util/LosRule": SH / "Util/LosRule.luau",
}

TEST = r'''
local fails = 0
local function check(ok, msg) print((ok and "ok    " or "FAIL  ") .. msg); if not ok then fails += 1 end end
local WK = require(node("Modules/WorldKits"))
-- R15: the colliding parts are the root / torso / head (about 2 wide, 1 deep, 5 tall); the arms reach round the rungs
local CLIMB_W, CLIMB_D, TALL = 2.4, 1.2, 5.0
local function boxOf(frame, p)
  local rel = frame:ToObjectSpace(p.CFrame); local s = p.Size
  local r, u, l = rel.RightVector * s.X * 0.5, rel.UpVector * s.Y * 0.5, rel.LookVector * s.Z * 0.5
  local hx = math.abs(r.X) + math.abs(u.X) + math.abs(l.X)
  local hy = math.abs(r.Y) + math.abs(u.Y) + math.abs(l.Y)
  local hz = math.abs(r.Z) + math.abs(u.Z) + math.abs(l.Z)
  local c = rel.Position
  return { N = p.Name, X0 = c.X - hx, X1 = c.X + hx, Y0 = c.Y - hy, Y1 = c.Y + hy, Z0 = c.Z - hz, Z1 = c.Z + hz, Collide = p.CanCollide, Truss = p.ClassName == "TrussPart" }
end
local function overl(b, x0, x1, y0, y1, z0, z1)
  return b.X0 < x1 - 0.02 and b.X1 > x0 + 0.02 and b.Y0 < y1 - 0.02 and b.Y1 > y0 + 0.02 and b.Z0 < z1 - 0.02 and b.Z1 > z0 + 0.02
end
local ROT = { 0, 90, 180, 270 }
local NAMES = { "NE_E1", "SW_S1", "NE_N1", "NW_W1" }
for i, deg in ipairs(ROT) do
  local frame = CFrame.new(100 * i, 0.5, -40 * i) * CFrame.Angles(0, math.rad(deg), 0)
  local cluster = Instance.new("Model"); cluster.Name = NAMES[i]
  WK.Add(cluster, "TownHouse", frame, { Variant = "walkup", Enterable = true })
  local boxes, truss, roofs = {}, nil, {}
  for _, p in ipairs(cluster:GetDescendants()) do
    if not rawget(p, "__destroyed") and (p.ClassName == "Part" or p.ClassName == "TrussPart") then
      local b = boxOf(frame, p)
      if b.Truss then truss = b elseif b.Collide then table.insert(boxes, b) end
      if b.N == "PlazaRoof" then table.insert(roofs, b) end
    end
  end
  local tag = NAMES[i] .. " (" .. deg .. " deg)"
  check(truss ~= nil, tag .. ": the ladder TrussPart exists")
  if truss then
    local roofTop = -math.huge
    for _, r in ipairs(roofs) do roofTop = math.max(roofTop, r.Y1) end
    local floorTop = 11.4
    check(truss.Y0 <= floorTop + 0.05 and truss.Y1 >= roofTop + 0.5, string.format("%s: ladder y %.1f..%.1f runs from the upper floor through the roof (top %.1f)", tag, truss.Y0, truss.Y1, roofTop))
    local cx, cz = (truss.X0 + truss.X1) * 0.5, (truss.Z0 + truss.Z1) * 0.5
    local faces = {
      { "+X", truss.X1, truss.X1 + CLIMB_D, cz - CLIMB_W / 2, cz + CLIMB_W / 2, -1, 0 },
      { "-X", truss.X0 - CLIMB_D, truss.X0, cz - CLIMB_W / 2, cz + CLIMB_W / 2, 1, 0 },
      { "+Z", cx - CLIMB_W / 2, cx + CLIMB_W / 2, truss.Z1, truss.Z1 + CLIMB_D, 0, -1 },
      { "-Z", cx - CLIMB_W / 2, cx + CLIMB_W / 2, truss.Z0 - CLIMB_D, truss.Z0, 0, 1 },
    }
    local report = {}
    local ups, traps = 0, 0
    -- ways off the ladder's top: a character box one step beyond it, free, standing on a roof part
    local exits = {}
    for _, e in ipairs({ { "+X", 1, 0 }, { "-X", -1, 0 }, { "+Z", 0, 1 }, { "-Z", 0, -1 } }) do
      local ex0, ex1 = truss.X0 + e[2] * 2.2, truss.X1 + e[2] * 2.2
      local ez0, ez1 = truss.Z0 + e[3] * 2.2, truss.Z1 + e[3] * 2.2
      local free, support = true, false
      for _, b in ipairs(boxes) do
        if overl(b, ex0, ex1, roofTop + 0.05, roofTop + TALL, ez0, ez1) then free = false end
        if b.Y1 >= roofTop - 0.05 and b.Y1 <= roofTop + 0.7 and overl(b, ex0 + 0.4, ex1 - 0.4, roofTop - 0.5, roofTop + 0.01, ez0 + 0.4, ez1 - 0.4) then support = true end
      end
      if free and support then table.insert(exits, e[1]) end
    end
    for _, f in ipairs(faces) do
      local blockedAt, by = nil, nil
      local y = floorTop
      while y <= truss.Y1 - 0.5 do
        for _, b in ipairs(boxes) do
          if overl(b, f[2], f[3], y, y + TALL, f[4], f[5]) then blockedAt, by = y, b.N; break end
        end
        if blockedAt then break end
        y += 0.25
      end
      local climbOk = blockedAt == nil
      -- the top: stand on the truss top, then one step off it (any side) onto a roof part (support under it)
      local topOk = false
      if climbOk then
        local stand = true
        for _, b in ipairs(boxes) do if overl(b, truss.X0, truss.X1, truss.Y1, truss.Y1 + TALL, truss.Z0, truss.Z1) then stand = false end end
        topOk = stand and #exits > 0
      end
      -- a TRAP face: you can grab it from the floor but hit something part-way up (the v132 bug)
      local trap = (not climbOk) and blockedAt > floorTop + 0.3
      if trap then traps += 1 end
      table.insert(report, string.format("%s:%s", f[1], if climbOk then (if topOk then "UP" else "top-blocked") else string.format("%s@y%.1f by %s", if trap then "TRAP" else "boxed", blockedAt, by)))
      if climbOk and topOk then ups += 1 end
    end
    local anyUp = ups > 0
    check(traps == 0, tag .. ": no ladder face lets you start climbing and then hits the ceiling (" .. traps .. " traps)")
    check(ups >= 2, tag .. ": >= 2 faces climb all the way up (" .. ups .. "); exits off the top: " .. table.concat(exits, ","))
    check(anyUp, tag .. ": a character climbs the ladder through the hatch onto the roof [" .. table.concat(report, " ") .. "]")
    -- the hole: the free square around the truss at the roof slab height
    local hx0, hx1, hz0, hz1 = truss.X0, truss.X1, truss.Z0, truss.Z1
    local function freeAt(x0, x1, z0, z1)
      for _, r in ipairs(roofs) do if overl(r, x0, x1, roofTop - 0.7, roofTop, z0, z1) then return false end end
      for _, b in ipairs(boxes) do if b.Y0 < roofTop and b.Y1 > roofTop - 0.7 and overl(b, x0, x1, roofTop - 0.7, roofTop, z0, z1) then return false end end
      return true
    end
    for _ = 1, 40 do
      local grew = false
      if freeAt(hx0 - 0.1, hx0, hz0, hz1) then hx0 -= 0.1; grew = true end
      if freeAt(hx1, hx1 + 0.1, hz0, hz1) then hx1 += 0.1; grew = true end
      if freeAt(hx0, hx1, hz0 - 0.1, hz0) then hz0 -= 0.1; grew = true end
      if freeAt(hx0, hx1, hz1, hz1 + 0.1) then hz1 += 0.1; grew = true end
      if not grew then break end
    end
    check(hx1 - hx0 >= 4.4 and hz1 - hz0 >= 4.4, string.format("%s: the hatch opening is %.1f x %.1f (>= 4.4 x 4.4)", tag, hx1 - hx0, hz1 - hz0))
    local rail, frameN = 0, 0
    for _, p in ipairs(cluster:GetDescendants()) do
      if p.Name == "PlazaHatchRail" then rail += 1 end
      if p.Name == "PlazaHatchFrame" then frameN += 1 end
    end
    check(rail >= 2 and frameN >= 2, string.format("%s: hatch railing (%d) and frame (%d) parts", tag, rail, frameN))
  end
end
print(string.format("HATCH TEST: %d failed", fails))
if fails > 0 then error("failed") end
'''

chunks = [PRELUDE]
for key, path in MODS.items():
    chunks.append("SOURCES[%r] = function(script)\n%s\nend" % (key, path.read_text(encoding="utf-8")))
chunks.append(TEST)
with tempfile.NamedTemporaryFile("w", suffix=".luau", delete=False, encoding="utf-8") as f:
    f.write("\n".join(chunks))
    path = f.name
luau = os.environ.get("LUAU", "luau")
r = subprocess.run([luau, path], capture_output=True, text=True)
out = r.stdout.strip()
print(out if os.environ.get("VERBOSE", "1") else out)
if r.returncode != 0:
    print(r.stderr.strip()[-2000:])
    sys.exit(0 if "--expect-fail" in sys.argv else 1)
sys.exit(1 if "--expect-fail" in sys.argv else 0)
