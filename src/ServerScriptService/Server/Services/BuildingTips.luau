--!strict
--[[
	claude-bud JOB 24 §5: "NEW BUILDING" cards, server side (Shared/Configs/BuildingTutorialConfig). Server-confirmed:
	only BaseService's BaseUpgradeChanged (a completed purchase) at level 1 triggers a card, once per building per player
	(profile.SeenTutorials[id] = true; kept through rebirth). profile.Settings.TipsOff (Settings -> TIPS) mutes them;
	RequestTipsReplay re-sends the cards of every building he owns now (Settings -> "Show my tips"). The client only
	shows what it is sent (BuildingTip remote: { Id }).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared.Constants)
local BuildingTutorialConfig = require(Shared.Configs.BuildingTutorialConfig)

local BuildingTips = {}

local DataService: any = nil
local RemoteSetup: any = nil
local RateLimitService: any = nil

local function send(player: Player, id: string)
	local ok, remote = pcall(RemoteSetup.Get, Constants.RemoteNames.BuildingTip)
	if ok and remote then
		(remote :: any):FireClient(player, { Id = id })
	end
end

local function tipsOff(profile: any): boolean
	return typeof(profile.Settings) == "table" and profile.Settings.TipsOff == true
end

function BuildingTips.OnUpgrade(userId: number, structureId: string, newLevel: number)
	if BuildingTutorialConfig.Enabled ~= true or newLevel ~= 1 or BuildingTutorialConfig.Tips[structureId] == nil then
		return
	end
	local player = Players:GetPlayerByUserId(userId)
	local profile = player and DataService and DataService.GetProfile(player)
	if player == nil or profile == nil then
		return
	end
	if typeof(profile.SeenTutorials) ~= "table" then
		profile.SeenTutorials = {}
	end
	if profile.SeenTutorials[structureId] then
		return
	end
	profile.SeenTutorials[structureId] = true
	DataService.MarkDirty(player)
	if not tipsOff(profile) then
		send(player, structureId)
	end
end

local function pushSetting(player: Player, profile: any)
	player:SetAttribute("WE_TipsOff", if tipsOff(profile) then true else nil)
end

function BuildingTips.Init(deps: { [string]: any })
	DataService = deps.DataService
	RemoteSetup = deps.RemoteSetup
	RateLimitService = deps.RateLimitService
	local bs = deps.BaseService
	if bs and bs.GetUpgradeChangedEvent then
		local ev = bs.GetUpgradeChangedEvent()
		if ev then
			ev.Event:Connect(function(userId: number, _plotId: number, structureId: string, newLevel: number)
				pcall(BuildingTips.OnUpgrade, userId, structureId, newLevel)
			end)
		end
	end
	local setRemote = RemoteSetup.Get(Constants.RemoteNames.RequestTipSetting) :: RemoteEvent
	setRemote.OnServerEvent:Connect(function(player: Player, off: any)
		if not require(script.Parent.Parent.Modules.RemoteGate).Check(player, "RequestTipSetting", off) then -- claude-bud JOB 15 gate
			return
		end
		if typeof(off) ~= "boolean" or (RateLimitService and not RateLimitService.Allow(player, "tip_setting", 1, 3)) then
			return
		end
		local profile = DataService.GetProfile(player)
		if profile == nil then
			return
		end
		if typeof(profile.Settings) ~= "table" then
			profile.Settings = {}
		end
		profile.Settings.TipsOff = off
		DataService.MarkDirty(player)
		pushSetting(player, profile)
	end)
	local replay = RemoteSetup.Get(Constants.RemoteNames.RequestTipsReplay) :: RemoteEvent
	replay.OnServerEvent:Connect(function(player: Player)
		if not require(script.Parent.Parent.Modules.RemoteGate).Check(player, "RequestTipsReplay") then -- claude-bud JOB 15 gate
			return
		end
		if RateLimitService and not RateLimitService.Allow(player, "tips_replay", 1 / 10, 1) then
			return
		end
		local profile = DataService.GetProfile(player)
		if profile == nil or typeof(profile.BaseUpgrades) ~= "table" then
			return
		end
		local ids = {}
		for id, _ in pairs(BuildingTutorialConfig.Tips) do
			if (tonumber(profile.BaseUpgrades[id]) or 0) >= 1 then -- (one level read per tip; the table is never handed on)
				table.insert(ids, id)
			end
		end
		table.sort(ids)
		for _, id in ipairs(ids) do
			send(player, id)
		end
	end)
	-- the setting on join (the client's Settings row reads WE_TipsOff)
	local function onJoin(p: Player)
		task.spawn(function()
			for _ = 1, 30 do
				local profile = DataService.GetProfile(p)
				if profile then
					pushSetting(p, profile)
					return
				end
				task.wait(1)
			end
		end)
	end
	Players.PlayerAdded:Connect(onJoin)
	for _, p in ipairs(Players:GetPlayers()) do
		onJoin(p)
	end
end

return BuildingTips
