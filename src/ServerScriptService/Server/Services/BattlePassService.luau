--!strict
--[[
	Minimal battle pass track — XP from gameplay, claim Free/Premium rewards.
	Premium flag only set via Monetization ProcessReceipt / admin — never client.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared.Constants)
local BattlePassConfig = require(Shared.Configs.BattlePassConfig)
local SeasonConfig = require(Shared.Configs.SeasonConfig)

local BattlePassService = {}

local DataService: any = nil
local EconomyService: any = nil
local NotificationService: any = nil
local RateLimitService: any = nil
local RemoteSetup: any = nil
local AnalyticsService: any = nil

local function ensureSeason(profile: any)
	local seasonId = SeasonConfig.CurrentSeasonId or BattlePassConfig.SeasonId
	if typeof(profile.BattlePass) ~= "table" then
		profile.BattlePass = {
			SeasonId = seasonId,
			XP = 0,
			Level = 0,
			Premium = false,
			ClaimedFree = {},
			ClaimedPremium = {},
		}
		return
	end
	if profile.BattlePass.SeasonId ~= seasonId then
		profile.BattlePass = {
			SeasonId = seasonId,
			XP = 0,
			Level = 0,
			Premium = profile.BattlePass.Premium == true, -- keep premium entitlement across seasons (policy: soft)
			ClaimedFree = {},
			ClaimedPremium = {},
		}
	end
	if typeof(profile.BattlePass.ClaimedFree) ~= "table" then
		profile.BattlePass.ClaimedFree = {}
	end
	if typeof(profile.BattlePass.ClaimedPremium) ~= "table" then
		profile.BattlePass.ClaimedPremium = {}
	end
end

local function pushState(player: Player)
	local profile = DataService.GetProfile(player)
	if not profile then
		return
	end
	ensureSeason(profile)
	local bp = profile.BattlePass
	local remote = RemoteSetup.Get(Constants.RemoteNames.BattlePassStateUpdate) :: RemoteEvent
	remote:FireClient(player, {
		SeasonId = bp.SeasonId,
		XP = bp.XP,
		Level = bp.Level,
		XPPerLevel = BattlePassConfig.XPPerLevel,
		MaxLevel = BattlePassConfig.MaxLevel,
		Premium = bp.Premium == true,
		ClaimedFree = bp.ClaimedFree,
		ClaimedPremium = bp.ClaimedPremium,
		FreeTrack = BattlePassConfig.FreeTrack,
		PremiumTrack = BattlePassConfig.PremiumTrack,
	})
end

function BattlePassService.AddXP(player: Player, amount: number, reason: string?)
	if typeof(amount) ~= "number" or amount ~= amount or amount <= 0 then
		return
	end
	amount = math.floor(amount)
	local profile = DataService.GetProfile(player)
	if not profile then
		return
	end
	ensureSeason(profile)
	local bp = profile.BattlePass
	if bp.Level >= BattlePassConfig.MaxLevel then
		return
	end
	bp.XP += amount
	while bp.Level < BattlePassConfig.MaxLevel do
		local need = BattlePassConfig.XPPerLevel
		if bp.XP < need then
			break
		end
		bp.XP -= need
		bp.Level += 1
		if NotificationService then
			NotificationService.Notify(player, "Battle Pass level " .. tostring(bp.Level) .. "!", "Reward", 4)
		end
	end
	DataService.MarkDirty(player)
	pushState(player)
end

local function grantReward(player: Player, reward: any)
	if typeof(reward) ~= "table" then
		return
	end
	if typeof(reward.Cash) == "number" and reward.Cash > 0 then
		EconomyService.AddCash(player, reward.Cash, "battlepass")
	end
	if typeof(reward.Gold) == "number" and reward.Gold > 0 then
		EconomyService.AddGold(player, reward.Gold, "battlepass")
	end
end

function BattlePassService.Claim(player: Player, level: number, track: string): (boolean, string?)
	if typeof(level) ~= "number" or level ~= level then
		return false, "InvalidLevel"
	end
	level = math.floor(level)
	if track ~= "free" and track ~= "premium" then
		return false, "InvalidTrack"
	end
	local profile = DataService.GetProfile(player)
	if not profile then
		return false, "NoProfile"
	end
	ensureSeason(profile)
	local bp = profile.BattlePass
	if level < 1 or level > bp.Level then
		return false, "LevelNotReached"
	end
	local key = tostring(level)
	if track == "free" then
		local reward = BattlePassConfig.FreeTrack[level]
		if not reward then
			return false, "NoReward"
		end
		if bp.ClaimedFree[key] then
			return false, "AlreadyClaimed"
		end
		bp.ClaimedFree[key] = true
		grantReward(player, reward)
	else
		if not bp.Premium then
			return false, "PremiumRequired"
		end
		local reward = BattlePassConfig.PremiumTrack[level]
		if not reward then
			return false, "NoReward"
		end
		if bp.ClaimedPremium[key] then
			return false, "AlreadyClaimed"
		end
		bp.ClaimedPremium[key] = true
		grantReward(player, reward)
	end
	DataService.MarkDirty(player)
	pushState(player)
	if NotificationService then
		NotificationService.Notify(player, "Battle Pass reward claimed (L" .. key .. " " .. track .. ")", "Reward")
	end
	if AnalyticsService and AnalyticsService.Log then
		AnalyticsService.Log("BATTLEPASS_CLAIM", player.UserId, { level = level, track = track })
	end
	return true, nil
end

function BattlePassService.SetPremium(player: Player, premium: boolean)
	local profile = DataService.GetProfile(player)
	if not profile then
		return
	end
	ensureSeason(profile)
	profile.BattlePass.Premium = premium == true
	DataService.MarkDirty(player)
	pushState(player)
end

function BattlePassService.Push(player: Player)
	pushState(player)
end

function BattlePassService.Init(deps: { [string]: any })
	DataService = deps.DataService
	EconomyService = deps.EconomyService
	NotificationService = deps.NotificationService
	RateLimitService = deps.RateLimitService
	RemoteSetup = deps.RemoteSetup
	AnalyticsService = deps.AnalyticsService

	local claimRemote = RemoteSetup.Get(Constants.RemoteNames.RequestClaimBattlePassReward) :: RemoteEvent
	claimRemote.OnServerEvent:Connect(function(player: Player, level: any, track: any)
		if not RateLimitService.Allow(player, "bp_claim", 4, 6) then
			return
		end
		local ok, err = BattlePassService.Claim(player, level, track)
		if not ok and NotificationService then
			NotificationService.Notify(player, "Cannot claim: " .. tostring(err), "Warn")
		end
	end)

	DataService.OnProfileLoaded(function(player: Player, profile: any)
		ensureSeason(profile)
		DataService.MarkDirty(player)
		pushState(player)
	end)
end

return BattlePassService
