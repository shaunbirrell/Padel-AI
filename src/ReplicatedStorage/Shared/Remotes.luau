--!strict
--[[
	Client/server helper to fetch remotes created by RemoteSetup.
	Does not create remotes on the client.

	v60/v61: HUD/BUY must NEVER block on unbounded WaitForChild.
	Use BindEvent / TryGet* / FireServer for display + BUY paths; GetEvent still waits (non-HUD).
	Folder is WE_Remotes (server-created) — Rojo no longer ships empty Remotes.
	v61: FireServer polls ≤3s then returns false — never toast "Buying…" without a live remote.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Constants = require(script.Parent.Constants)

local Remotes = {}

local function getFolderImmediate(): Folder?
	local folder = ReplicatedStorage:FindFirstChild(Constants.RemotesFolderName)
	if folder and folder:IsA("Folder") then
		return folder :: Folder
	end
	return nil
end

local function getFolder(): Folder
	local folder = getFolderImmediate()
	if folder then
		return folder
	end
	folder = ReplicatedStorage:WaitForChild(Constants.RemotesFolderName, 120) :: Folder?
	assert(folder and folder:IsA("Folder"), "WE_Remotes missing — server EarlyRemotes/RemoteSetup must run first")
	return folder :: Folder
end

local function waitForRemote(name: string, className: string): Instance
	local folder = getFolder()
	local existing = folder:FindFirstChild(name)
	if existing and existing:IsA(className) then
		return existing
	end
	local waited = 0
	while waited < 180 do
		local remote = folder:WaitForChild(name, 5)
		if remote and remote:IsA(className) then
			return remote
		end
		waited += 5
		warn(string.format("[Remotes] Waiting for %s %s… (%ds)", className, name, waited))
	end
	local remote = folder:WaitForChild(name, 30)
	if not (remote and remote:IsA(className)) then
		error(className .. " missing after wait: " .. name .. " (server Bootstrap may have aborted — check Output)", 0)
	end
	return remote
end

function Remotes.GetEvent(name: string): RemoteEvent
	return waitForRemote(name, "RemoteEvent") :: RemoteEvent
end

function Remotes.GetFunction(name: string): RemoteFunction
	return waitForRemote(name, "RemoteFunction") :: RemoteFunction
end

--[[ Non-blocking: nil if remote not ready yet. ]]
function Remotes.TryGetEvent(name: string): RemoteEvent?
	local folder = getFolderImmediate()
	if not folder then
		return nil
	end
	local remote = folder:FindFirstChild(name)
	if remote and remote:IsA("RemoteEvent") then
		return remote :: RemoteEvent
	end
	return nil
end

function Remotes.TryGetFunction(name: string): RemoteFunction?
	local folder = getFolderImmediate()
	if not folder then
		return nil
	end
	local remote = folder:FindFirstChild(name)
	if remote and remote:IsA("RemoteFunction") then
		return remote :: RemoteFunction
	end
	return nil
end

--[[
	Client→server fire without unbounded WaitForChild.
	Polls up to timeoutSec (default 3) for WE_Remotes + event.
	Returns true only if FireServer actually ran on a live RemoteEvent.
]]
function Remotes.FireServer(name: string, ...: any): boolean
	local remote = Remotes.TryGetEvent(name)
	if remote then
		remote:FireServer(...)
		return true
	end
	local timeoutSec = 3
	local deadline = os.clock() + timeoutSec
	while os.clock() < deadline do
		task.wait(0.05)
		remote = Remotes.TryGetEvent(name)
		if remote then
			remote:FireServer(...)
			return true
		end
	end
	warn("[Remotes] FireServer: remote not ready after", timeoutSec, "s:", name)
	return false
end

--[[
	Connect OnClientEvent without ever yielding the caller.
	If remote appears later, connects in a background spawn.
]]
function Remotes.BindEvent(name: string, handler: (...any) -> ()): ()
	local remote = Remotes.TryGetEvent(name)
	if remote then
		remote.OnClientEvent:Connect(handler)
		return
	end
	task.spawn(function()
		local folder = getFolderImmediate()
		if not folder then
			local waited = ReplicatedStorage:WaitForChild(Constants.RemotesFolderName, 120)
			if not (waited and waited:IsA("Folder")) then
				warn("[Remotes] BindEvent: WE_Remotes never appeared for", name)
				return
			end
			folder = waited :: Folder
		end
		local ev = folder:FindFirstChild(name)
		if not ev then
			ev = folder:WaitForChild(name, 120)
		end
		if ev and ev:IsA("RemoteEvent") then
			(ev :: RemoteEvent).OnClientEvent:Connect(handler)
		else
			warn("[Remotes] BindEvent: remote never appeared:", name)
		end
	end)
end

return Remotes
