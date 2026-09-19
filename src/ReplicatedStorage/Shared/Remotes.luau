--!strict
--[[
	Client/server helper to fetch remotes created by RemoteSetup.
	Does not create remotes on the client.
	Waits patiently — Rojo ships an empty Remotes folder; server may still
	be running MapSetup before RemoteSetup.Init. Never hard-assert after 10s.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Constants = require(script.Parent.Constants)

local Remotes = {}

local function getFolder(): Folder
	local folder = ReplicatedStorage:FindFirstChild(Constants.RemotesFolderName)
	if folder and folder:IsA("Folder") then
		return folder :: Folder
	end
	folder = ReplicatedStorage:WaitForChild(Constants.RemotesFolderName, 120)
	assert(folder and folder:IsA("Folder"), "Remotes folder missing — server Bootstrap must run first")
	return folder :: Folder
end

local function waitForRemote(name: string, className: string): Instance
	local folder = getFolder()
	local existing = folder:FindFirstChild(name)
	if existing and existing:IsA(className) then
		return existing
	end
	-- Poll with warns — map/service load can exceed 10s on cold Studio Play
	local waited = 0
	while waited < 180 do
		local remote = folder:WaitForChild(name, 5)
		if remote and remote:IsA(className) then
			return remote
		end
		waited += 5
		warn(string.format("[Remotes] Waiting for %s %s… (%ds)", className, name, waited))
	end
	local remote = folder:WaitForChild(name)
	assert(remote and remote:IsA(className), className .. " missing: " .. name)
	return remote
end

function Remotes.GetEvent(name: string): RemoteEvent
	return waitForRemote(name, "RemoteEvent") :: RemoteEvent
end

function Remotes.GetFunction(name: string): RemoteFunction
	return waitForRemote(name, "RemoteFunction") :: RemoteFunction
end

return Remotes
