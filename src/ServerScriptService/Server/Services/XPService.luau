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
local _MissionService: any = nil
local MonetizationService: any = nil
local BattlePassService: any = nil
local SeasonService: any = nil
local NotificationService: any = nil
local PrestigeService: any = nil

local function pushXP(player: Player, profile: Types.PlayerProfile, unlockMessage: string?, leveledUp: boolean?)
	local remote = RemoteSetup.Get(Constants.RemoteNames.XPUpdate) :: RemoteEvent
	local hudGoal = LevelConfig.GetHudGoal(profile.Level)
	remote:FireClient(player, {
		Level = profile.Level,
		XP = profile.XP,
		XPToNext = LevelConfig.GetXPRequiredForLevel(profile.Level),
		HudGoal = hudGoal,
		UnlockMessage = unlockMessage,
		LevelUp = leveledUp == true,
	} :: Types.XPUpdatePayload)
end

function XPService.Init(deps: { [string]: any })
	DataService = deps.DataService
	EconomyService = deps.EconomyService
	AnalyticsService = deps.AnalyticsService
	RemoteSetup = deps.RemoteSetup
	TerritoryService = deps.TerritoryService
	_MissionService = deps.MissionService
	MonetizationService = deps.MonetizationService
	BattlePassService = deps.BattlePassService
	SeasonService = deps.SeasonService
	NotificationService = deps.NotificationService
	PrestigeService = deps.PrestigeService
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
	if SeasonService and SeasonService.GetXPMult and reason ~= "admin" and reason ~= "battlepass" and reason ~= "daily" then
		amount = math.max(1, math.floor(amount * SeasonService.GetXPMult()))
	end
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

	local MonetizationConfig = require(Shared.Configs.MonetizationConfig)
	local reasonKey = reason or ""
	local xpExempt = MonetizationConfig.XPMultExemptReasons
	if MonetizationService and MonetizationService.GetXPMultiplier and not (xpExempt and xpExempt[reasonKey]) then
		amount = math.max(1, math.floor(amount * MonetizationService.GetXPMultiplier(player)))
	end

	profile.XP += amount
	while profile.Level < LevelConfig.MaxLevel do
		local need = LevelConfig.GetXPRequiredForLevel(profile.Level)
		if profile.XP < need then
			break
		end
		profile.XP -= need
		profile.Level += 1
		local reward = LevelConfig.GetLevelUpReward(profile.Level)
		if reward.Cash > 0 then
			EconomyService.AddCash(player, reward.Cash, "level_up")
		end
		if reward.Gold > 0 then
			EconomyService.AddGold(player, reward.Gold, "level_up")
		end
		local unlockMsg = LevelConfig.GetUnlockMessage(profile.Level)
		-- v37: high-contrast level-up celebration toast (client also plays SFX on LevelUp flag)
		if NotificationService and NotificationService.Notify then
			local celeb = string.format("★ LEVEL %d!", profile.Level)
			if unlockMsg then
				celeb = celeb .. " — " .. unlockMsg
			end
			NotificationService.Notify(player, celeb, "Success", 5)
		end
		if AnalyticsService then
			AnalyticsService.Log("LEVEL_UP", player.UserId, { level = profile.Level, reason = reason })
		end
		-- v35: mid-game VIP soft offer (level≥10)
		if MonetizationService and MonetizationService.TrySoftOfferVIP then
			pcall(function()
				MonetizationService.TrySoftOfferVIP(player, "level")
			end)
		end
		-- v38: soft rebirth CTA when near MinLevelToPrestige
		if PrestigeService and PrestigeService.MaybeNearPrestigeToast then
			pcall(function()
				PrestigeService.MaybeNearPrestigeToast(player)
			end)
		end
		-- Push per level-up so HUD goal / unlock toast refresh immediately
		pushXP(player, profile, unlockMsg, true)
	end

	DataService.MarkDirty(player)
	pushXP(player, profile, nil)
	if BattlePassService and BattlePassService.AddXP and reason ~= "battlepass" then
		-- Mirror a portion of gameplay XP into the battle pass track
		BattlePassService.AddXP(player, amount, reason)
	end
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
