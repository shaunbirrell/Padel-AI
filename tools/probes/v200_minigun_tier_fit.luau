local IS = game:GetService("InsertService")
local ID = 109072907337393
local raw = IS:LoadAsset(ID)
for _, d in ipairs(raw:GetDescendants()) do if d:IsA("BaseScript") or d:IsA("ModuleScript") then d:Destroy() end end
local TIERS = { { "minigun_l01", 5.5 }, { "minigun_l03", 5.8 }, { "minigun_l05", 6.1 }, { "minigun_l08", 6.5 }, { "minigun_l10", 7.0 } }
for t, row in ipairs(TIERS) do
	local piece = raw:FindFirstChild(row[1], true)
	local model = piece:Clone()
	local n, hum, scripts = 0, 0, 0
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then n += 1 elseif d:IsA("Humanoid") then hum += 1 elseif d:IsA("LuaSourceContainer") then scripts += 1 end
	end
	-- prepareAimTemplate(yaw 180, aimHitbox)
	local parts = {}
	for _, d in ipairs(model:GetDescendants()) do if d:IsA("BasePart") then table.insert(parts, d) end end
	local lo, hi = parts[1].Position, parts[1].Position
	for _, p in ipairs(parts) do lo, hi = lo:Min(p.Position), hi:Max(p.Position) end
	local c = (lo + hi) * 0.5
	local turn = CFrame.new(c) * CFrame.Angles(0, math.rad(180), 0) * CFrame.new(-c)
	for _, p in ipairs(parts) do p.CFrame = turn * p.CFrame end
	lo, hi = parts[1].Position, parts[1].Position
	for _, p in ipairs(parts) do
		local cf, sz = p.CFrame, p.Size * 0.5
		for _, k in ipairs({ Vector3.new(1,1,1), Vector3.new(-1,1,1), Vector3.new(1,-1,1), Vector3.new(1,1,-1), Vector3.new(-1,-1,1), Vector3.new(-1,1,-1), Vector3.new(1,-1,-1), Vector3.new(-1,-1,-1) }) do
			local w = cf:PointToWorldSpace(sz * k); lo, hi = lo:Min(w), hi:Max(w)
		end
	end
	local box = Instance.new("Part"); box.Name = "WE_AimHitbox"; box.Size = (hi - lo); box.CFrame = CFrame.new((lo + hi) * 0.5)
	box.Transparency = 1; box.Anchored = true; box.Parent = model; model.PrimaryPart = box
	-- scale
	local size = model:GetExtentsSize()
	local f = row[2] / math.max(size.X, size.Y, size.Z)
	local s0 = model:GetScale()
	model:ScaleTo(s0 * f)
	print(string.format("P3 S0 %s %.4f", row[1], s0))
	model:PivotTo(CFrame.new(0, 50, 0))
	local barrel, pitch
	for _, d in ipairs(model:GetDescendants()) do
		if d.Name:find("BarrelRotation") then barrel = d end
		if d.Name:find("GunPitch") then pitch = d end
	end
	local rel = box.CFrame:PointToObjectSpace(barrel.Position)
	local relP = box.CFrame:PointToObjectSpace(pitch.Position)
	local e = model:GetExtentsSize()
	local tip = box.CFrame:PointToObjectSpace(barrel.Position + barrel.CFrame.LookVector * 0) -- centre
	print(string.format("P3 T%d %s parts=%d(+hitbox) hum=%d scripts=%d scale=%.3f final=%.2f,%.2f,%.2f barrelZ=%.2f pitchZ=%.2f barrelFront=%s look=%.2f,%.2f,%.2f",
		t, row[1], n, hum, scripts, f, e.X, e.Y, e.Z, rel.Z, relP.Z, tostring(rel.Z < relP.Z), box.CFrame.LookVector.X, box.CFrame.LookVector.Y, box.CFrame.LookVector.Z))
	model:Destroy()
end
raw:Destroy()
print("P3 DONE")
