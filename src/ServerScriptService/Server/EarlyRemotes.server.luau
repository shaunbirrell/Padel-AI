--!strict
--[[
	v59 belt: create Remotes/EconomyUpdate ASAP so client never WaitForChild 180s
	while Bootstrap is still requiring modules. Idempotent with RemoteSetup.Init.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local folder = ReplicatedStorage:FindFirstChild("Remotes")
if not folder then
	folder = Instance.new("Folder")
	folder.Name = "Remotes"
	folder.Parent = ReplicatedStorage
end

if not folder:FindFirstChild("EconomyUpdate") then
	local ev = Instance.new("RemoteEvent")
	ev.Name = "EconomyUpdate"
	ev.Parent = folder
end

if not folder:FindFirstChild("PlayerStateUpdate") then
	local ev = Instance.new("RemoteEvent")
	ev.Name = "PlayerStateUpdate"
	ev.Parent = folder
end

print("[WAR EMPIRE] EarlyRemotes belt: EconomyUpdate present")
