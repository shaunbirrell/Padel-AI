#!/usr/bin/env python3
"""Code Bot JOB 67 batch 1: build a headless Open Cloud Luau Execution probe that runs the REAL
Job67DressService + Job67DressConfig source (inlined: a task cannot create ModuleScripts) against a fake
wall ring for levels 1..5 and the plot-1 prop clusters for tiers 1..5, and prints piece counts / boxes.
Usage: python3 tools/probes/j67_b1_harness.py > /tmp/j67_b1.luau  (then run it with an Open Cloud runner)."""
import re, sys
from pathlib import Path
R = Path(__file__).resolve().parents[2]
cfg = (R / "src/ReplicatedStorage/Shared/Configs/Job67DressConfig.luau").read_text().replace("--!strict", "")
svc = (R / "src/ServerScriptService/Server/Services/Job67DressService.luau").read_text().replace("--!strict", "")
svc = svc.replace("local Cfg = require(Shared.Configs.Job67DressConfig)", "local Cfg = (function()\n" + cfg + "\nend)()")
svc = re.sub(r"\nreturn Job67DressService\s*$", "\n", svc)
harness = r'''
local OWNER = 470626172
local function count(inst, cls) local n = 0 for _, d in ipairs(inst:GetDescendants()) do if d:IsA(cls) then n += 1 end end return n end
for lv = 1, 5 do
	local plotFolder = Instance.new("Folder") plotFolder.Name = "FakePlot" plotFolder.Parent = workspace
	local folder = Instance.new("Folder") folder.Name = "WE_PerimeterWalls" folder.Parent = plotFolder
	local cx, cz, padTop = 0, 0, 1
	local halfX, halfZ = 158.5, 158.5
	local th, h = 2.8 + lv * 0.7, 7.5 + lv * 2.8
	local y = padTop + h / 2
	folder:SetAttribute("WE_GateAxis", "Z") folder:SetAttribute("WE_GateSign", 1)
	local function wall(name, size, pos)
		local w = Instance.new("Part") w.Name = name w.Size = size w.Position = pos w.Anchored = true w.Parent = folder
		w:SetAttribute("WE_Perimeter", true)
		local c = Instance.new("Part") c.Name = name .. "_Cap" c.Size = Vector3.new(size.X, 0.5, size.Z) c.Position = pos + Vector3.new(0, h/2, 0) c.Anchored = true c.Parent = folder c:SetAttribute("WE_Perimeter", true)
	end
	wall("WallClosed", Vector3.new(halfX*2, h, th), Vector3.new(cx, y, cz - halfZ))
	wall("WallE", Vector3.new(th, h, halfZ*2), Vector3.new(cx + halfX, y, cz))
	wall("WallW", Vector3.new(th, h, halfZ*2), Vector3.new(cx - halfX, y, cz))
	local segLen, mid = halfX - 5, (halfX + 5) / 2
	wall("WallGate_L", Vector3.new(segLen, h, th), Vector3.new(cx - mid, y, cz + halfZ))
	wall("WallGate_R", Vector3.new(segLen, h, th), Vector3.new(cx + mid, y, cz + halfZ))
	local t0 = os.clock()
	local ok, st = pcall(Job67DressService.DressWalls, 1, plotFolder, folder, lv, padTop, Vector3.new(cx, padTop, cz), OWNER)
	local out = plotFolder:FindFirstChild("WE_J67WallDress")
	if not ok then print("J67B1 WALL L"..lv.." ERROR "..tostring(st)) else
		local hid = 0 for _, w in ipairs(folder:GetChildren()) do if w.Transparency == 1 then hid += 1 end end
		local mn, mx = Vector3.one * 1e9, Vector3.one * -1e9
		for _, d in ipairs(out:GetDescendants()) do if d:IsA("BasePart") then mn = mn:Min(d.Position - d.Size / 2) mx = mx:Max(d.Position + d.Size / 2) end end
		local sz = mx - mn
		print(string.format("J67B1 WALL L%d name=%s hesco=%d hescoTris=%d lines=%d props=%d parts=%d hidden=%d box=%.0f,%.0f,%.0f lights=%d scripts=%d collide=%d query=%d shadow=%d t=%.2fs",
			lv, tostring(out:GetAttribute("WE_WallTierName")), st.Hesco, out:GetAttribute("WE_J67HescoTris"), st.Lines, st.Props, count(out, "BasePart"), hid, sz.X, sz.Y, sz.Z,
			count(out, "Light"), count(out, "LuaSourceContainer"),
			(function() local n=0 for _,d in ipairs(out:GetDescendants()) do if d:IsA("BasePart") and d.CanCollide then n+=1 end end return n end)(),
			(function() local n=0 for _,d in ipairs(out:GetDescendants()) do if d:IsA("BasePart") and d.CanQuery then n+=1 end end return n end)(),
			(function() local n=0 for _,d in ipairs(out:GetDescendants()) do if d:IsA("BasePart") and d.CastShadow then n+=1 end end return n end)(),
			os.clock() - t0))
		if lv == 5 then
			for i, d in ipairs(out:GetChildren()) do
				if i <= 6 then local c2, s2 = (d:IsA("Model") and d:GetBoundingBox()) or d.CFrame, (d:IsA("Model") and select(2, d:GetBoundingBox())) or d.Size
					print(string.format("J67B1 WALLPIECE %s at=%.1f,%.1f,%.1f size=%.1f,%.1f,%.1f", d.Name, c2.X, c2.Y, c2.Z, s2.X, s2.Y, s2.Z)) end
			end
		end
	end
	plotFolder:Destroy()
end
for _, key in ipairs((function() local k = {} for n in pairs(Cfg.Pieces) do table.insert(k, n) end table.sort(k) return k end)()) do
	local t = Job67DressService.Template(key)
	if t then local _, s = t:GetBoundingBox() print(string.format("J67B1 PIECE %s parts=%d box=%.1f,%.1f,%.1f", key, t:GetAttribute("WE_J67Parts"), s.X, s.Y, s.Z))
	else print("J67B1 PIECE " .. key .. " MISSING") end
end
for lvsum, tier in pairs({ [1] = 1, [10] = 2, [22] = 3, [38] = 4, [75] = 5 }) do
	local ok, n = pcall(Job67DressService.SyncProps, 1, OWNER, lvsum)
	local f = workspace:FindFirstChild("WE_J67Props") and workspace.WE_J67Props:FindFirstChild("Plot1")
	print(string.format("J67B1 PROPS sum=%d tier=%d ok=%s pieces=%s parts=%d", lvsum, Cfg.PropTier(lvsum), tostring(ok), tostring(n), f and count(f, "BasePart") or -1))
	Job67DressService.ClearProps(1)
end
for id, a in pairs(Job67DressService._audit) do print("J67B1 AUDIT " .. id .. " " .. a) end
print("J67B1 LIVE owner=" .. tostring(Job67DressService.Live(Cfg.Walls, OWNER)) .. " other=" .. tostring(Job67DressService.Live(Cfg.Walls, 1)))
print("J67B1 DONE")
'''
sys.stdout.write(svc + "\n" + harness)
