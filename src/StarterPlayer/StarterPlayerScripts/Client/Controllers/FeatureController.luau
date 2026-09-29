--!strict
--[[
	claude-bud JOB 4/5 (2026-09-29): client side of the server's FeaturePush cues (Constants.RemoteNames.FeaturePush,
	server -> this client only; the server fires it only to players a feature is live for, so nothing here gates).
	Display only: every reward is decided on the server.
	  "Airdrop"  { Show = true, X, Y, Z, Cash } -> the one objective marker ("AIRDROP") to the landing spot
	             { Show = false }               -> clears it if it is still the airdrop
	  "Bounty"   { Show = true, X, Y, Z }       -> the objective marker ("BOUNTY") on the Central Plaza
	             { Show = false }               -> clears it if it is still the bounty
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ObjectiveMarker = require(script.Parent.Parent.Modules.ObjectiveMarker)
local Shared = ReplicatedStorage:WaitForChild("Shared", 60) -- ships with the place (Rojo); bounded wait anyway
local Remotes = require(Shared.Remotes)
local Constants = require(Shared.Constants)

local FeatureController = {}

-- claude-bud JOB 4.4: the local "Army Upgrades" prompt at the own Barracks (opens the Research Soldiers track)
local upgradeAnchor: Attachment? = nil
local function armyUpgrades(data: any)
	if typeof(data) ~= "table" then
		return
	end
	local x, y, z = tonumber(data.X), tonumber(data.Y), tonumber(data.Z)
	if not (x and y and z) then
		return
	end
	if upgradeAnchor then
		upgradeAnchor:Destroy()
	end
	local a = Instance.new("Attachment")
	a.Name = "WE_ArmyUpgradesPrompt"
	a.WorldPosition = Vector3.new(x, y, z)
	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Army Upgrades"
	prompt.ObjectText = "Barracks"
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 14
	prompt.RequiresLineOfSight = false
	prompt.Parent = a
	local track = if typeof(data.Track) == "string" then data.Track else "Soldiers"
	prompt.Triggered:Connect(function()
		local rc = script.Parent:FindFirstChild("ResearchController")
		if rc and rc:IsA("ModuleScript") then
			local ok, mod = pcall(require, rc)
			if ok and type(mod) == "table" and type((mod :: any).Open) == "function" then
				(mod :: any).Open(track)
			end
		end
	end)
	a.Parent = workspace.Terrain
	upgradeAnchor = a
end

local LABELS = { Airdrop = "AIRDROP", Bounty = "BOUNTY" }

local function marker(kind: string, data: any)
	local label = LABELS[kind]
	if label == nil or typeof(data) ~= "table" then
		return
	end
	if data.Show == true then
		local x, y, z = tonumber(data.X), tonumber(data.Y), tonumber(data.Z)
		if x and y and z then
			ObjectiveMarker.ShowWith({ Short = label, X = x, Y = y, Z = z }, { TimeoutSeconds = 300 })
		end
	else
		local cur = ObjectiveMarker.Current()
		if cur and cur.Short == label then
			ObjectiveMarker.Clear()
		end
	end
end

-- claude-bud JOB 5b: VIP perks on this client (display / own movement only; the server decides every payout)
local function vipPerks()
	local Players = game:GetService("Players")
	local TextChatService = game:GetService("TextChatService")
	local MonetizationConfig = require(Shared.Configs.MonetizationConfig)
	local tag = tostring(((MonetizationConfig :: any).VIPPerks or {}).ChatTag or "[VIP]")
	-- the [VIP] chat tag of any sender the server marked (WE_VIPTag), seen by everyone
	pcall(function()
		TextChatService.OnIncomingMessage = function(message: TextChatMessage)
			local props = Instance.new("TextChatMessageProperties")
			local src = message.TextSource
			local sender = if src then Players:GetPlayerByUserId(src.UserId) else nil
			if sender and sender:GetAttribute("WE_VIPTag") == true then
				props.PrefixText = "<font color='#D4AF37'>" .. tag .. "</font> " .. message.PrefixText
			end
			return props
		end
	end)
	-- the lounge door: open (non-colliding) on a VIP's own client only; 3 s poll (streaming-safe, no tree scans)
	task.spawn(function()
		local lp = Players.LocalPlayer
		while lp.Parent do
			local lounge = workspace:FindFirstChild("WE_VIPLounge")
			local door = lounge and lounge:FindFirstChild("VIPDoor")
			if door and door:IsA("BasePart") then
				local vip = lp:GetAttribute("WE_VIPTag") == true
				door.CanCollide = not vip
				door.LocalTransparencyModifier = if vip then 0.5 else 0
			end
			task.wait(3)
		end
	end)
end
function FeatureController.Init()
	vipPerks()
	Remotes.BindEvent(Constants.RemoteNames.FeaturePush, function(kind: any, data: any)
		if typeof(kind) ~= "string" then
			return
		end
		if LABELS[kind] then
			marker(kind, data)
		elseif kind == "ArmyUpgrades" then
			armyUpgrades(data)
		end
	end)
end

return FeatureController
