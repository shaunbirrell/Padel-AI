"""claude-bud JOB 45: the Recruit Pack's gold trim, on the REAL RecruitTrimService (stand-ins: run_kit_detail_test.PRELUDE;
BaseService / Players / Workspace are recording stubs).

1. ROOT CAUSE (static, before the fix = d38c766, the v170 tip both JOB 45 and codebot_v171 started from; codebot_v171 pinned it: the moving branch now has the v171 trim): nothing builds base geometry for WE_Ent_RecruitPack.
   The only consumers are BaseSignService (a text prefix + stroke) and BaseMarkerService (a marker flag; the marker
   hides inside 60 studs of your own base).
2. PURCHASE: the entitlement attribute flips -> the gold arch is built on the owner's plot at once (no rejoin), with the
   RECRUIT banner, gold metal parts, no collisions, in Workspace.WE_RecruitTrim (never WE_Building*).
3. REJOIN / new server: a fresh service builds it from the attribute (MonetizationService sets it on join from the
   saved Entitlements).
4. A NON-OWNER (no entitlement) or an owner who left: no trim / removed.
5. REBIRTH / plot rebuild: the trim lives outside the base kits and is kept; if its folder is gone the sweep rebuilds it.
6. OFF: RecruitTrim.Enabled = false -> nothing built.
7. Code Bot v172: placed from the REAL gate (GatePost parts in WE_PerimeterWalls) at walls Lv 1-5 and on a turned plot:
   no overlap with the wall + the v171 gold wall / post bands, the posts' roofs, the gatehouse, the guards or the lane;
   on the pad, above the wall, wholly inside the wall's inner face, no z-fighting faces, rebuilt when the walls change.
(The cash grant and the 30-min 2x boost, once per receipt: tools/sim/run_recruit_pack_test.py.)
Run: LUAU=path/to/luau(.exe) python tools/sim/run_recruit_trim_test.py   (exit 1 on any failure; VERBOSE=1 prints all)"""
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
    "Configs/MonetizationConfig": SH / "Configs/MonetizationConfig.luau",
    "Configs/RecruitTrimConfig": SH / "Configs/RecruitTrimConfig.luau",
    "Configs/RetentionConfig": SH / "Configs/RetentionConfig.luau",
    "Configs/AdminConfig": SH / "Configs/AdminConfig.luau",
    "Configs/BaseConfig": SH / "Configs/BaseConfig.luau",
    "Configs/BaseLayoutConfig": SH / "Configs/BaseLayoutConfig.luau",
    "Configs/BusinessConfig": SH / "Configs/BusinessConfig.luau",
    "Configs/ShopOverhaulConfig": SH / "Configs/ShopOverhaulConfig.luau",
    "Util/PlotFrame": SH / "Util/PlotFrame.luau",
    "Services/RecruitTrimService": SV / "Services/RecruitTrimService.luau",
}

EXTRA = r'''
task = { spawn = function() end, delay = function() end, defer = function() end, wait = function() end }
RaycastParams = { new = function() return {} end }
Enum.RaycastFilterType = { Exclude = "Exclude" }
local function signal() local s = { fns = {} }; s.Connect = function(self, fn) table.insert(self.fns, fn); return { Disconnect = function() end } end; s.Fire = function(self, ...) for _, f in ipairs(self.fns) do f(...) end end; return s end
WS = Instance.new("Folder")
WS.FindFirstChild = function(s, n) for _, c in ipairs(s:GetChildren()) do if c.Name == n then return c end end return nil end
WS.Raycast = function() return nil end
local function mkPlayer(uid, name)
  local attrs, sigs = {}, {}
  local p = { UserId = uid, Name = name, Parent = true }
  p.GetAttribute = function(_, k) return attrs[k] end
  p.SetAttribute = function(_, k, v) attrs[k] = v; if sigs[k] then sigs[k]:Fire() end end
  p.GetAttributeChangedSignal = function(_, k) sigs[k] = sigs[k] or signal(); return sigs[k] end
  return p
end
OWNER = mkPlayer(470626172, "shaunie6")
OTHER = mkPlayer(1234, "rookie99")
local inServer = { OWNER, OTHER }
local Players = { PlayerAdded = signal(), PlayerRemoving = signal(), GetPlayers = function() return inServer end,
  GetPlayerByUserId = function(_, uid) for _, p in ipairs(inServer) do if p.UserId == uid then return p end end return nil end }
function Players_list() return inServer end
function leave(p) for i, q in ipairs(inServer) do if q == p then table.remove(inServer, i) end end end
local RunService = { IsStudio = function() return false end }
local prevGame = game
game = { GetService = function(_, n)
  if n == "Players" then return Players elseif n == "RunService" then return RunService elseif n == "Workspace" then return WS end
  return prevGame:GetService(n) end }
OWNERS = { [2] = OWNER.UserId, [5] = OTHER.UserId }
DEPS = { BaseService = { GetOwnerUserId = function(id) return OWNERS[id] end,
  GetOwnedPlotId = function(p) for id, u in pairs(OWNERS) do if u == p.UserId then return id end end return nil end } }

function mk(cls, name, parent, props)
  local o = Instance.new(cls)
  o.Name = name
  o.FindFirstChild = function(s, n) for _, c in ipairs(s:GetChildren()) do if c.Name == n then return c end end return nil end
  for k, v in pairs(props or {}) do o[k] = v end
  o.Parent = parent
  return o
end
-- Code Bot v172: a stand-in of the REAL gate for plot 2 (StructureKitBuilder.SyncPerimeterWalls numbers, gate on +Z)
-- returns the boxes the arch must stay clear of (min / max corners) and the wall top
function perimeter(lv, swap)
  -- swap: the gate on the +X face (a plot turned 90 degrees): plot (x, z) -> world (z, x)
  local function P(x, y, z) if swap then return CFrame.new(z, y, x) end return CFrame.new(x, y, z) end
  local function Sz(x, y, z) if swap then return Vector3.new(z, y, x) end return Vector3.new(x, y, z) end
  local old = WS:FindFirstChild("WarEmpireSetup")
  if old then old:Destroy() end
  local setup = mk("Folder", "WarEmpireSetup", WS)
  local bases = mk("Folder", "Bases", setup)
  local plot = mk("Folder", "Plot2", bases)
  mk("Part", "PlotPad", plot, { Size = Vector3.new(320, 1, 320), CFrame = CFrame.new(0, 0, 0) })
  local peri = mk("Folder", "WE_PerimeterWalls", plot)
  local top, halfZ = 0.5, 158.5
  local th, h = 2.8 + lv * 0.7, 7.5 + lv * 2.8
  local postW, postH = 2.2 + lv * 0.15, h + 1.5
  local segLen, mid = 158.5 - 5, (158.5 + 5) * 0.5
  local keep = {}
  local function box(name, cx, cy, cz, sx, sy, sz) if swap then cx, cz, sx, sz = cz, cx, sz, sx end table.insert(keep, { name, vec3(cx - sx / 2, cy - sy / 2, cz - sz / 2), vec3(cx + sx / 2, cy + sy / 2, cz + sz / 2) }) end
  for _, sx in ipairs({ -1, 1 }) do
    local w = mk("Part", "WallGate_" .. (sx < 0 and "L" or "R"), peri, { Size = Sz(segLen, h, th), CFrame = P(sx * mid, top + h / 2, halfZ) })
    w:SetAttribute("WE_WallLevel", lv)
    box("wall + v171 gold band", sx * mid, top + h / 2, halfZ, segLen + 0.5, h + 0.9, th + 0.5)
    local px = 5 + postW / 2
    mk("Part", "GatePost", peri, { Size = Sz(postW, postH, postW), CFrame = P(sx * px, top + postH / 2, halfZ) })
    box("gate post + roof eave / v171 post band", sx * px, top + postH / 2 + 1.5, halfZ, postW + 1.4, postH + 3, postW + 1.4)
    box("Tier 3 gatehouse pier", sx * 6.6, top + 10, halfZ, 3.4, 40, 4.6)
    box("gate guard post / patrol", sx * 4.5, top + 3, halfZ - 10, 5, 6, 2.5)
  end
  box("GateArch + chevron", 0, top + h + 1.5, halfZ, 10 + postW * 2, 3, th + 1.6)
  box("gatehouse lintel / crests", 0, top + math.max(h, 12) + 3, halfZ, 16, 8, 5.2)
  box("the 10-stud gate lane", 0, top + h / 2, halfZ - 8, 10, h, 16 + th)
  return keep, top + h
end
function vec3(x, y, z) return Vector3.new(x, y, z) end
function aabb(p)
  local cf, sz = p.CFrame, p.Size
  local r = rawget(cf, "r")
  local ex = {}
  for i = 1, 3 do ex[i] = math.abs(r[i][1]) * sz.X / 2 + math.abs(r[i][2]) * sz.Y / 2 + math.abs(r[i][3]) * sz.Z / 2 end
  local c = cf.Position
  return vec3(c.X - ex[1], c.Y - ex[2], c.Z - ex[3]), vec3(c.X + ex[1], c.Y + ex[2], c.Z + ex[3]), r[1][1] == 1 and r[2][2] == 1 and r[3][3] == 1
end
function overlaps(a0, a1, b0, b1) return a0.X < b1.X and b0.X < a1.X and a0.Y < b1.Y and b0.Y < a1.Y and a0.Z < b1.Z and b0.Z < a1.Z end
-- same-facing coplanar faces with a shared area (z-fighting), axis-aligned parts only
function zfight(parts)
  local hits = {}
  local K = { "X", "Y", "Z" }
  for i = 1, #parts do for j = i + 1, #parts do
    local a0, a1, axA = aabb(parts[i]); local b0, b1, axB = aabb(parts[j])
    if axA and axB then
      for ai = 1, 3 do
        local o1, o2 = K[(ai % 3) + 1], K[((ai + 1) % 3) + 1]
        local share = math.min(a1[o1], b1[o1]) - math.max(a0[o1], b0[o1]) > 1e-3 and math.min(a1[o2], b1[o2]) - math.max(a0[o2], b0[o2]) > 1e-3
        local k = K[ai]
        if share and (math.abs(a1[k] - b1[k]) < 1e-3 or math.abs(a0[k] - b0[k]) < 1e-3) then
          table.insert(hits, parts[i].Name .. "/" .. parts[j].Name .. " " .. k)
        end
      end
    end
  end end
  return hits
end
function fresh()
  CACHE["Services/RecruitTrimService"] = nil
  for _, c in ipairs(WS:GetChildren()) do c:Destroy() end
  local S = require(node("Services/RecruitTrimService"))
  S.Init(DEPS)
  return S
end
function trimOf(plot)
  local r = WS:FindFirstChild("WE_RecruitTrim")
  if r == nil then return nil end
  for _, c in ipairs(r:GetChildren()) do if c.Name == "Plot" .. plot then return c end end
  return nil
end
'''

TEST = r'''
local fails = 0
local function check(ok, msg) print((ok and "ok    " or "FAIL  ") .. msg); if not ok then fails += 1 end end
local MC = { RecruitTrim = require(node("Configs/RecruitTrimConfig")) }
local S = fresh()
-- before purchase: nothing
S.SyncAll()
check(trimOf(2) == nil and trimOf(5) == nil, "no entitlement: no trim anywhere")
-- 2. purchase: the attribute flips (MonetizationService.GrantEntitlement) -> built at once by the change signal
OWNER:SetAttribute("WE_Ent_RecruitPack", true)
local t = trimOf(2)
check(t ~= nil, "purchase: the gold arch is built on HIS plot at once (the attribute signal, no rejoin)")
local nParts, gold, banner, collide, text, building = 0, 0, false, false, nil, false
for _, d in ipairs(t and t:GetDescendants() or {}) do
  if d.ClassName == "Part" then
    nParts += 1
    if d.Name == "Shaft" or d.Name == "Beam" or d.Name == "Cap" or d.Name == "Finial" then gold += 1 end
    if d.Name == "Banner" then banner = true end
    if d.CanCollide ~= false then collide = true end
    if string.find(d.Name, "WE_Building") then building = true end
  elseif d.ClassName == "TextLabel" then text = d.Text end
end
check(nParts >= 20 and gold >= 7 and banner and text == "★ RECRUIT ★", string.format("a detailed arch: %d parts, %d gold metal pieces, the banner reads %s", nParts, gold, tostring(text)))
check(not collide and not building and t.Parent ~= nil and t.Parent.Name == "WE_RecruitTrim", "non-colliding decor in Workspace.WE_RecruitTrim (never a WE_Building* part)")
check(trimOf(5) == nil, "a non-owner (no entitlement) has no trim")
-- 3. rejoin / a new server: built from the attribute by a fresh service's sweep
S = fresh()
check(trimOf(2) == nil, "(a new server starts empty)")
S.SyncAll()
check(trimOf(2) ~= nil, "rejoin / new server: the sweep rebuilds it from WE_Ent_RecruitPack")
-- 5. rebirth / plot rebuild: kept; a lost folder is rebuilt
local before = trimOf(2)
S.SyncAll()
check(trimOf(2) == before, "rebirth / base rebuild: the trim is kept (it lives outside the base kits)")
before:Destroy()
S.SyncAll()
check(trimOf(2) ~= nil and trimOf(2) ~= before, "if its folder is wiped, the next sweep rebuilds it")
-- 4. the owner leaves: removed
leave(OWNER)
S.SyncAll()
check(trimOf(2) == nil, "the owner left: the trim is removed")

-- 7. Code Bot v172: placed from the REAL gate at every walls level: clear of the wall / v171 bands / posts / gate
--    furniture / guards / the lane, above the wall, no z-fighting, and moved when the walls are upgraded
leave(OWNER); table.insert(Players_list(), OWNER)
S = fresh()
local prevKey = nil
for lv = 1, 5 do
  local keep, wallTop = perimeter(lv)
  S.SyncAll()
  local tr = trimOf(2)
  check(tr ~= nil and tr:GetAttribute("WE_PlaceKey") ~= prevKey and string.sub(tr:GetAttribute("WE_PlaceKey") or "", 1, 2) == "G|",
    string.format("walls Lv %d: the arch is (re)built from the real gate posts", lv))
  prevKey = tr and tr:GetAttribute("WE_PlaceKey")
  local parts, clash, maxY, minY, nearZ = {}, {}, -1e9, 1e9, -1e9
  for _, d in ipairs(tr and tr:GetDescendants() or {}) do
    if d.ClassName == "Part" then
      table.insert(parts, d)
      local a0, a1 = aabb(d)
      maxY = math.max(maxY, a1.Y); minY = math.min(minY, a0.Y); nearZ = math.max(nearZ, a1.Z)
      for _, k in ipairs(keep) do
        if overlaps(a0, a1, k[2], k[3]) then table.insert(clash, d.Name .. " x " .. k[1]) end
      end
      if d.CanCollide ~= false or d.CanQuery ~= false or d.CanTouch ~= false then table.insert(clash, d.Name .. " collides") end
    end
  end
  check(#clash == 0, string.format("walls Lv %d: no part overlaps the wall, the v171 gold bands, the posts, the gate furniture, the guards or the lane%s", lv, if #clash > 0 then " (" .. table.concat(clash, ", ") .. ")" else ""))
  check(maxY >= wallTop + 3 and minY >= 0.5 - 0.11 and minY < 0.5, string.format("walls Lv %d: on the pad (bottom %.2f), rising above the %.1f-stud wall (top %.1f)", lv, minY, wallTop, maxY))
  check(nearZ < 158.5 - (2.8 + lv * 0.7) / 2, string.format("walls Lv %d: wholly inside the wall's inner face (nearest %.2f)", lv, nearZ))
  local zf = zfight(parts)
  check(#zf == 0, string.format("walls Lv %d: no coplanar same-facing faces in the arch (z-fighting)%s", lv, if #zf > 0 then ": " .. table.concat(zf, ", ") else ""))
end
-- a plot turned 90 degrees (the gate on the +X face): the arch turns with it and stays clear
for _, lv in ipairs({ 1, 5 }) do
  local keep = perimeter(lv, true)
  S.SyncAll()
  local tr = trimOf(2)
  local clash, nearX, banner = {}, -1e9, nil
  for _, d in ipairs(tr and tr:GetDescendants() or {}) do
    if d.ClassName == "Part" then
      local a0, a1 = aabb(d)
      nearX = math.max(nearX, a1.X)
      for _, k in ipairs(keep) do if overlaps(a0, a1, k[2], k[3]) then table.insert(clash, d.Name .. " x " .. k[1]) end end
      if d.Name == "Banner" then banner = { a0, a1 } end
    end
  end
  check(tr ~= nil and #clash == 0 and nearX < 158.5 - (2.8 + lv * 0.7) / 2 and banner ~= nil and (banner[2].Z - banner[1].Z) > 11,
    string.format("gate on +X, walls Lv %d: the arch turns with the gate (banner across Z), inside the wall, no overlaps%s", lv, if #clash > 0 then " (" .. table.concat(clash, ", ") .. ")" else ""))
end
-- 6. OFF
MC.RecruitTrim.Enabled = false
S = fresh()
S.SyncAll()
check(trimOf(2) == nil, "RecruitTrim.Enabled = false: nothing built")
print(string.format("RECRUIT TRIM LUA: %d failed", fails))
if fails > 0 then error("failed") end
'''


def main():
    out, fails = [], 0
    before = subprocess.run(["git", "grep", "-l", "WE_Ent_RecruitPack", "d38c766", "--", "src"], capture_output=True, text=True).stdout
    readers = sorted(l.split(":", 1)[1] for l in before.splitlines() if l)
    builds = [r for r in readers if "RecruitTrim" in r]
    out.append("BEFORE (d38c766 = v170): WE_Ent_RecruitPack readers = %s" % ", ".join(readers))
    ok = not builds and all(("BaseSignService" in r or "BaseMarkerService" in r or "RecruitPackService" in r) for r in readers)
    if not builds:
        out.append(("ok    " if ok else "FAIL  ") + "ROOT CAUSE: before the fix nothing builds base geometry for the entitlement (readers: the sign text / stroke, the marker flag, and RecruitPackService's owned check that stops re-offering)")
        fails += 0 if ok else 1
    else:
        out.append("note  origin already carries RecruitTrimService (the fix shipped); root cause recorded in docs/proof/recruit-trim/REPORT.md")
    chunks = [PRELUDE, EXTRA]
    for key, path in MODS.items():
        chunks.append("SOURCES[%r] = function(script)\n%s\nend" % (key, path.read_text(encoding="utf-8")))
    chunks.append(TEST)
    with tempfile.NamedTemporaryFile("w", suffix=".luau", delete=False, encoding="utf-8") as f:
        f.write("\n".join(chunks))
        path = f.name
    r = subprocess.run([os.environ.get("LUAU", "luau"), path], capture_output=True, text=True)
    out.extend(r.stdout.strip().splitlines())
    if r.returncode != 0 or "RECRUIT TRIM LUA: 0 failed" not in r.stdout:
        fails += 1
        out.append(r.stderr.strip()[-2000:])
    out.append("RECRUIT TRIM TEST: %d failed" % fails)
    print("\n".join(out) if os.environ.get("VERBOSE") else "\n".join(l for l in out if l.startswith(("FAIL", "RECRUIT TRIM TEST", "BEFORE"))))
    sys.exit(1 if fails else 0)


if __name__ == "__main__":
    main()
