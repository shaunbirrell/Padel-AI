#!/usr/bin/env python3
"""Code Bot JOB 67 batch 3: an Open Cloud Luau Execution probe that builds the REAL Wreck / HeliWreck kit clusters (WorldKits
from the live place + the POILayouts rows) under a fake WarEmpireSetup.WorldDressing, then runs the REAL (inlined)
Job67DressService.SyncWorld for the Wrecks block (owner gate opened for the probe) and prints each building's fit, hidden kit parts,
colliders / lights / scripts, and ClearWorld's restore.
Usage: python3 tools/probes/j67_b3_harness.py > /tmp/j67_b3.luau"""
import re
from pathlib import Path
R = Path(__file__).resolve().parents[2]
cfg = (R / "src/ReplicatedStorage/Shared/Configs/Job67DressConfig.luau").read_text().replace("--!strict", "")
import os, sys
if len(sys.argv) > 1 and "Wrecks = {" not in cfg:  # optional block file, spliced in before the Buildings block
    cfg = cfg.replace("\tBuildings = {", Path(sys.argv[1]).read_text().strip("\n") + "\n\tBuildings = {", 1)
svc = (R / "src/ServerScriptService/Server/Services/Job67DressService.luau").read_text().replace("--!strict", "")
svc = svc.replace("local Cfg = require(Shared.Configs.Job67DressConfig)", "local Cfg = (function()\n" + cfg + "\nend)()")
svc = svc.replace("script.Parent.Parent:FindFirstChild(\"Modules\")", "game:GetService(\"ServerScriptService\").Server:FindFirstChild(\"Modules\")")
svc = re.sub(r"\nreturn Job67DressService\s*$", "\n", svc)
harness = r'''
C.OwnerFirst = false
C.Buildings.Enabled = false
C.Wrecks.OwnerFirst = false
local SSS = game:GetService("ServerScriptService")
local WorldKits = require(SSS.Server.Modules.WorldKits)
local WorldConfig = require(game:GetService("ReplicatedStorage").Shared.Configs.WorldConfig)
local setup = Instance.new("Folder") setup.Name = "WarEmpireSetup" setup.Parent = workspace
local wd = Instance.new("Folder") wd.Name = "WorldDressing" wd.Parent = setup
local base = workspace:FindFirstChild("Baseplate")
local kitParts = {}
for _, row in ipairs(C.Wrecks.Rows) do
	local c, k = clusterRow(row.Poi, row.Cluster, row.Kit, row.KitIndex)
	if c == nil then print("J67B3 NOROW "..row.Poi.."/"..row.Cluster) continue end
	if (wd:FindFirstChild("POI_"..row.Poi) and wd["POI_"..row.Poi]:FindFirstChild(c.Id)) then continue end
	local f = wd:FindFirstChild("POI_"..row.Poi) or Instance.new("Folder")
	f.Name = "POI_"..row.Poi f.Parent = wd
	local m = WorldKits.NewCluster(c.Id, { Source = "poi", Kind = c.Role, Anchor = "poi:"..row.Poi, AnchorX = c.X, AnchorZ = c.Z, Tier = c.Tier })
	local frame = CFrame.new(c.X, 0.5, c.Z) * CFrame.Angles(0, math.rad(c.Yaw or 0), 0)
	for _, kk in ipairs(c.Kits) do
		local kcf = frame * CFrame.new(kk.X, 0, kk.Z) * CFrame.Angles(0, math.rad(kk.Yaw or 0), 0)
		local ok, e = pcall(WorldKits.Add, m, kk.Kit, kcf, { Variant = kk.Variant, Width = kk.Width, Depth = kk.Depth, Storeys = kk.Storeys, Roof = kk.Roof, Lantern = kk.Lantern })
		if not ok then print("J67B3 KITERR "..tostring(e)) end
	end
	local okF, eF = pcall(WorldKits.Finish, m, f)
	if not okF then m.Parent = f end
	local n, l = 0, 0
	for _, d in ipairs(m:GetDescendants()) do if d:IsA("BasePart") then n += 1 end if d:IsA("Light") then l += 1 end end
	kitParts[row.Poi.."/"..row.Cluster] = n
	print(string.format("J67B3 KIT %s/%s parts=%d lights=%d w=%s d=%s storeys=%s variant=%s", row.Poi, row.Cluster, n, l, tostring(k.Width), tostring(k.Depth), tostring(k.Storeys), tostring(k.Variant)))
end
local t0 = os.clock()
local ok, n = pcall(Job67DressService.SyncWorld)
print("J67B3 SYNC ok="..tostring(ok).." placed="..tostring(n).." t="..string.format("%.2f", os.clock() - t0))
local out = workspace:FindFirstChild("WE_J67Wrecks")
local totalParts = 0
for _, m in ipairs(out and out:GetChildren() or {}) do
	local cf, s = m:GetBoundingBox()
	local p, col, q, sh, li, sc, un = 0, 0, 0, 0, 0, 0, 0
	for _, d in ipairs(m:GetDescendants()) do
		if d:IsA("BasePart") then p += 1 if d.CanCollide then col += 1 end if d.CanQuery then q += 1 end if d.CastShadow then sh += 1 end if not d.Anchored then un += 1 end end
		if d:IsA("Light") or d:IsA("ParticleEmitter") then li += 1 end
		if d:IsA("LuaSourceContainer") then sc += 1 end
	end
	totalParts += p
	local cl = wd["POI_"..m:GetAttribute("WE_J67Poi")][m:GetAttribute("WE_J67Cluster")]
	local vis, colK = 0, 0
	for _, d in ipairs(cl:GetDescendants()) do if d:IsA("BasePart") then if d.Transparency < 1 then vis += 1 end if d.CanCollide then colK += 1 end end end
	local _, ks = cl:GetBoundingBox()
	print(string.format("J67B3 BUILD %s scale=%.2f at=%.0f,%.1f,%.0f size=%.1f,%.1f,%.1f kitBox=%.1f,%.1f,%.1f parts=%d collide=%d query=%d shadow=%d unanch=%d fx=%d scripts=%d kitVisible=%d kitColliders=%d",
		m.Name.."@"..m:GetAttribute("WE_J67Poi").."/"..m:GetAttribute("WE_J67Cluster"), m:GetAttribute("WE_J67Scale"), cf.X, cf.Y - s.Y / 2, cf.Z, s.X, s.Y, s.Z, ks.X, ks.Y, ks.Z, p, col, q, sh, un, li, sc, vis, colK))
end
print("J67B3 TOTAL parts="..totalParts)
-- every layout anchor of the POI must stay outside each building's box (+1 stud), on the real collidable parts
for _, m in ipairs(out and out:GetChildren() or {}) do
	local poi = m:GetAttribute("WE_J67Poi")
	local layoutName
	for _, p in ipairs(WorldConfig.POIs) do if p.Id == poi then layoutName = p.Layout end end
	local group = require(SSS.Server.Modules.POILayouts[layoutName])
	local inside = {}
	local colParts = {}
	for _, d in ipairs(m:GetDescendants()) do if d:IsA("BasePart") and d.CanCollide then table.insert(colParts, d) end end
	for _, a in ipairs(group[poi].Anchors or {}) do
		local pt = Vector3.new(a.X, 0.5 + (a.Y or 0) + 2.5, a.Z)
		local best = math.huge
		for _, d in ipairs(colParts) do
			local lp = d.CFrame:PointToObjectSpace(pt)
			local q = Vector3.new(math.max(math.abs(lp.X) - d.Size.X / 2, 0), math.max(math.abs(lp.Y) - d.Size.Y / 2, 0), math.max(math.abs(lp.Z) - d.Size.Z / 2, 0))
			best = math.min(best, q.Magnitude)
		end
		if best < (WorldConfig.Activity and WorldConfig.Activity.MinClear or 3) then table.insert(inside, string.format("%s(%.1f)", a.Id, best)) end
	end
	print("J67B3 ANCHORS "..m.Name.."@"..poi.."/"..m:GetAttribute("WE_J67Cluster").." tooClose="..#inside.." "..table.concat(inside, " "))
end
Job67DressService.ClearWorld()
local vis = 0
for _, d in ipairs(wd:GetDescendants()) do if d:IsA("BasePart") and d.Transparency >= 1 and d:GetAttribute("WE_J67T") ~= nil then vis += 1 end end
print("J67B3 CLEAR folder="..tostring(workspace:FindFirstChild("WE_J67Wrecks") ~= nil).." stillHidden="..vis)
for k, v in pairs(Job67DressService._audit) do print("J67B3 AUDIT "..k.." "..v) end
setup:Destroy()
print("J67B3 DONE")
'''
print(svc + "\n" + harness)
