--!strict
--[[
	Client/server helper to fetch remotes created by RemoteSetup.
	Does not create remotes on the client.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Constants = require(script.Parent.Constants)

local Remotes = {}

local function getFolder(): Folder
	local folder = ReplicatedStorage:FindFirstChild(Constants.RemotesFolderName)
	assert(folder and folder:IsA("Folder"), "Remotes folder missing — server Bootstrap must run first")
	return folder :: Folder
end

function Remotes.GetEvent(name: string): RemoteEvent
	local folder = getFolder()
	local remote = folder:WaitForChild(name, 10)
	assert(remote and remote:IsA("RemoteEvent"), "RemoteEvent missing: " .. name)
	return remote :: RemoteEvent
end

function Remotes.GetFunction(name: string): RemoteFunction
	local folder = getFolder()
	local remote = folder:WaitForChild(name, 10)
	assert(remote and remote:IsA("RemoteFunction"), "RemoteFunction missing: " .. name)
	return remote :: RemoteFunction
end

return Remotes
