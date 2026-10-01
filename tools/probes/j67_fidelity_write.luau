local IS, AS = game:GetService("InsertService"), game:GetService("AssetService")
local root = IS:LoadAsset(116015230898207)
local mp = root:FindFirstChildWhichIsA("MeshPart", true)
local ok1, e1 = pcall(function() mp.RenderFidelity = Enum.RenderFidelity.Performance end)
print("P2 setRF", ok1, tostring(e1))
local ok2, e2 = pcall(function() mp.CollisionFidelity = Enum.CollisionFidelity.Box end)
print("P2 setCF", ok2, tostring(e2), mp.CollisionFidelity.Name)
local ok3, em = pcall(function() return AS:CreateEditableMeshAsync(Content.fromUri(mp.MeshId)) end)
print("P2 EM", ok3, tostring(em))
print("P2 hesco size", mp.Size, "pivot", root:GetPivot(), "mp cf", mp.CFrame)
local sa = mp:FindFirstChildWhichIsA("SurfaceAppearance")
print("P2 hesco SA", sa and sa.ColorMap or "-")
local sb = IS:LoadAsset(71112106874796)
for i, d in ipairs(sb:GetDescendants()) do
	if d:IsA("BasePart") then
		print(string.format("P2 SB %d %s %s parent=%s size=%.1f,%.1f,%.1f pos=%.1f,%.1f,%.1f mesh=%s", i, d.ClassName, d.Name, d.Parent.Name, d.Size.X, d.Size.Y, d.Size.Z, d.Position.X, d.Position.Y, d.Position.Z, d:IsA("MeshPart") and d.MeshId:match("%d+$") or "-"))
	end
end
print("P2 DONE")
