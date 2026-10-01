local IS = game:GetService("InsertService")
local root = IS:LoadAsset(116015230898207)
local mp = root:FindFirstChildWhichIsA("MeshPart", true)
mp.Anchored = true
mp.CFrame = CFrame.new(0, 5000, 0)
mp.Parent = workspace
task.wait(0.5)
local rp = RaycastParams.new() rp.FilterType = Enum.RaycastFilterType.Include rp.FilterDescendantsInstances = {mp}
local s = mp.Size
local function cast(o, d) local r = workspace:Raycast(o, d, rp) return r and r.Position end
-- from top down grid
for _, fx in ipairs({-0.45,-0.25,0,0.25,0.45}) do
	local row = {}
	for _, fz in ipairs({-0.45,-0.3,-0.15,0,0.15,0.3,0.45}) do
		local p = cast(Vector3.new(fx*s.X, 5000 + s.Y, fz*s.Z), Vector3.new(0, -s.Y*2, 0))
		table.insert(row, p and string.format("%.0f", p.Y - (5000 - s.Y/2)) or "-")
	end
	print("P3 topY x="..fx.." z: "..table.concat(row, " "))
end
for _, fy in ipairs({0.1, 0.5, 0.9}) do
	local row = {}
	for _, fx in ipairs({-0.45,-0.25,0,0.25,0.45}) do
		local a = cast(Vector3.new(fx*s.X, 5000 - s.Y/2 + fy*s.Y, s.Z), Vector3.new(0,0,-s.Z*2))
		local b = cast(Vector3.new(fx*s.X, 5000 - s.Y/2 + fy*s.Y, -s.Z), Vector3.new(0,0,s.Z*2))
		table.insert(row, (a and string.format("%.0f", a.Z) or "-").."/"..(b and string.format("%.0f", b.Z) or "-"))
	end
	print("P3 frontZ/backZ y="..fy.." : "..table.concat(row, " "))
end
print("P3 DONE")
