--!strict
--[[ Server-authoritative XP / Level ]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared.Constants)
local LevelConfig = require(Shared.Configs.LevelConfig)
local Types = require(Shared.Types)

local XPService = {}

local DataService: any = nil
local EconomyService: any = nil
local AnalyticsService: any = nil
local RemoteSetup: any = nil
local TerritoryService: any = nil
local MissionService: any = nil

local function xpToNext(level: number, xp: number): number
	local need = LevelConfig.GetXPRequiredForLevel(level)
	if need == math.huge then
		return 0
	end
	return math.max(0, need - xp)
end

local function pushXP(player: Player, profile: Types.PlayerProfile)
	local remote = RemoteSetup.Get(Constants.RemoteNames.XPUpdate) :: RemoteEvent
	remote:FireClient(player, {
		Level = profile.Level,
		XP = profile.XP,
		XPToNext = LevelConfig.GetXPRequiredForLevel(profile.Level),
	} :: Types.XPUpdatePayload)
end

function XPService.Init(deps: { [string]: any })
	DataService = deps.DataService
	EconomyService = deps.EconomyService
	AnalyticsService = deps.AnalyticsService
	RemoteSetup = deps.RemoteSetup
	TerritoryService = deps.TerritoryService
	MissionService = deps.MissionService
end

function XPService.Push(player: Player)
	local profile = DataService.GetProfile(player)
	if profile then
		pushXP(player, profile)
	end
end

function XPService.AddXP(player: Player, amount: number, reason: string?): boolean
	if typeof(amount) ~= "number" or amount ~= amount or amount <= 0 then
		return false
	end
	amount = math.floor(amount)
	local profile = DataService.GetProfile(player)
	if not profile then
		return false
	end

	if profile.Level >= LevelConfig.MaxLevel then
		return false
	end

	if TerritoryService and TerritoryService.GetXPMult and reason ~= "achievement" then
		amount = math.max(1, math.floor(amount * TerritoryService.GetXPMult(player)))
	end

	profile.XP += amount
	local leveled = false
	while profile.Level < LevelConfig.MaxLevel do
		local need = LevelConfig.GetXPRequiredForLevel(profile.Level)
		if profile.XP < need then
			break
		end
		profile.XP -= need
		profile.Level += 1
		leveled = true
		local reward = LevelConfig.GetLevelUpReward(profile.Level)
		if reward.Cash > 0 then
			EconomyService.AddCash(player, reward.Cash, "level_up")
		end
		if reward.Gold > 0 then
			EconomyService.AddGold(player, reward.Gold, "level_up")
		end
		if AnalyticsService then
			AnalyticsService.Log("LEVEL_UP", player.UserId, { level = profile.Level, reason = reason })
		end
	end

	DataService.MarkDirty(player)
	pushXP(player, profile)
	return true
end

function XPService.SetLevel(player: Player, level: number)
	local profile = DataService.GetProfile(player)
	if not profile then
		return
	end
	profile.Level = math.clamp(math.floor(level), 1, LevelConfig.MaxLevel)
	profile.XP = 0
	DataService.MarkDirty(player)
	pushXP(player, profile)
end

function XPService.GetXPToNext(player: Player): number
	local profile = DataService.GetProfile(player)
	if not profile then
		return 0
	end
	return LevelConfig.GetXPRequiredForLevel(profile.Level)
end

return XPService
