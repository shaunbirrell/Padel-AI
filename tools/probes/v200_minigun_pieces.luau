local IS, AS = game:GetService("InsertService"), game:GetService("AssetService")
local ID = 109072907337393
local ok, root = pcall(function() return IS:LoadAsset(ID) end)
if not ok then print("P2 LOADFAIL "..tostring(root)) return end
for _, d in ipairs(root:GetDescendants()) do
	if d:IsA("LuaSourceContainer") then
		local src = "" pcall(function() src = d.Source end)
		print(string.format("P2 SCRIPT %s class=%s path=%s srclen=%d", d.Name, d.ClassName, d:GetFullName(), #src))
	end
	if d:IsA("ValueBase") or d:IsA("Configuration") then print("P2 VALUE "..d:GetFullName().." "..d.ClassName) end
	if not d:IsA("BasePart") and not d:IsA("LuaSourceContainer") and not d:IsA("Model") and not d:IsA("Folder") then print("P2 OTHER "..d.ClassName.." "..d:GetFullName()) end
end
local meshTris = {}
local total = 0
for i = 1, 10 do
	local name = string.format("minigun_l%02d", i)
	local m = root:FindFirstChild(name, true)
	if not m then print("P2 MISSING "..name) continue end
	local parts, tris, triOk, triFail = 0, 0, 0, 0
	local names = {}
	for _, d in ipairs(m:GetDescendants()) do
		if d:IsA("BasePart") then
			parts += 1
			table.insert(names, d.Name)
			if d:IsA("MeshPart") then
				local t = meshTris[d.MeshId]
				if t == nil then
					local ok2, em = pcall(function() return AS:CreateEditableMeshAsync(Content.fromUri(d.MeshId)) end)
					if ok2 and em then
						local ok3, faces = pcall(function() return #em:GetFaces() end)
						t = if ok3 then faces else -1
						pcall(function() em:Destroy() end)
					else
						t = -1
						print("P2 EMFAIL "..d.Name.." "..tostring(em))
					end
					meshTris[d.MeshId] = t
				end
				if t >= 0 then tris += t triOk += 1 else triFail += 1 end
			end
		end
	end
	local sz = m:GetExtentsSize()
	print(string.format("P2 PIECE %s class=%s parts=%d tris=%d triOk=%d triFail=%d ext=%.2f,%.2f,%.2f names=%s", name, m.ClassName, parts, tris, triOk, triFail, sz.X, sz.Y, sz.Z, table.concat(names, "|")))
	total += tris
end
print("P2 TOTALTRIS "..total)
root:Destroy()
print("P2 DONE")
