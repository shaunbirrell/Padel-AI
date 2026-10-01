local IS = game:GetService("InsertService")
local IDS = {70726960831586, 71112106874796, 87282634781307, 116015230898207, 119390702773907, 16365964601} -- Code Bot JOB 67: the paid packs + the hero Desert house (scripts / classes / tree)
local SUS = {"require","getfenv","setfenv","loadstring","HttpService","MarketplaceService","TeleportService","InsertService","\\x","string.char","Players"}
print("ENV ver="..game.PlaceVersion)
for _, id in ipairs(IDS) do
	local ok, root = pcall(function() return IS:LoadAsset(id) end)
	if not ok then print("P1 "..id.." LOADFAIL "..tostring(root)) continue end
	local cc = {}
	for _, d in ipairs(root:GetDescendants()) do
		cc[d.ClassName] = (cc[d.ClassName] or 0) + 1
		if d:IsA("LuaSourceContainer") then
			local src = "" pcall(function() src = d.Source end)
			local hits = {}
			for _, k in ipairs(SUS) do if string.find(src, k, 1, true) then table.insert(hits, k) end end
			print(string.format("P1 %d SCRIPT %s class=%s path=%s srclen=%d sus=%s", id, d.Name, d.ClassName, d:GetFullName(), #src, table.concat(hits, ",")))
		end
	end
	local cs = {}
	for k, v in pairs(cc) do table.insert(cs, k.."="..v) end
	table.sort(cs)
	print("P1 "..id.." CLASSES "..table.concat(cs, " "))
	local function walk(inst, depth, path)
		for _, ch in ipairs(inst:GetChildren()) do
			local np, ext = 0, nil
			for _, d in ipairs(ch:GetDescendants()) do if d:IsA("BasePart") then np += 1 end end
			if ch:IsA("BasePart") then np += 1 end
			local s = ""
			if ch:IsA("Model") then local e = ch:GetExtentsSize() s = string.format("ext=%.1f,%.1f,%.1f sc=%.3f", e.X, e.Y, e.Z, ch:GetScale()) end
			if ch:IsA("BasePart") then s = string.format("size=%.1f,%.1f,%.1f", ch.Size.X, ch.Size.Y, ch.Size.Z) end
			if ch:IsA("MeshPart") then s ..= " mesh="..tostring(ch.MeshId):match("%d+$").." rf="..tostring(ch.RenderFidelity.Name).." cf="..tostring(ch.CollisionFidelity.Name) end
			if ch:IsA("BasePart") or ch:IsA("Model") or ch:IsA("Folder") then
				print(string.format("P1 %d %s%s c=%s parts=%d %s", id, string.rep("  ", depth), path..ch.Name, ch.ClassName, np, s))
				if depth < 2 and not ch:IsA("BasePart") then walk(ch, depth + 1, "") end
			end
		end
	end
	walk(root, 0, "")
	root:Destroy()
end
print("P1 DONE")
