--!strict
--[[
	Battle pass track — dense Free/Premium rewards from BattlePassConfig.
	Premium flag only via Monetization ProcessReceipt (PremiumPass) / admin grantpremium — never client.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared.Constants)
local BattlePassConfig = require(Shared.Configs.BattlePassConfig)
local SeasonConfig = require(Shared.Configs.SeasonConfig)
local AnalyticsConfig = require(Shared.Configs.AnalyticsConfig)

local RemoteGuard = require(script.Parent.Parent.Modules.RemoteGuard)

local BattlePassService = {}

local DataService: any = nil
local EconomyService: any = nil
local NotificationService: any = nil
local RateLimitService: any = nil
local RemoteSetup: any = nil
local AnalyticsService: any = nil
local AntiExploitService: any = nil

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

local function countClaimable(bp: any, track: { [number]: any }, claimedMap: any, requirePremium: boolean): number
	if requirePremium and not bp.Premium then
		return 0
	end
	local n = 0
	local level = tonumber(bp.Level) or 0
	for tier, _reward in pairs(track) do
		local t = tonumber(tier)
		if t and t >= 1 and t <= level and not claimedMap[tostring(t)] then
			n += 1
		end
	end
	return n
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
		ClaimableFree = countClaimable(bp, BattlePassConfig.FreeTrack, bp.ClaimedFree, false),
		ClaimablePremium = countClaimable(bp, BattlePassConfig.PremiumTrack, bp.ClaimedPremium, true),
		PremiumProductId = BattlePassConfig.PremiumProductId,
	})
end

function BattlePassService.AddXP(player: Player, amount: number, _reason: string?)
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
	local maxLevel = BattlePassConfig.MaxLevel or 50
	local clamped = RemoteGuard.ClampPositiveInt(level, maxLevel)
	if not clamped then
		return false, "InvalidLevel"
	end
	level = clamped
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
		AnalyticsService.Log(AnalyticsConfig.Events.BATTLEPASS_CLAIM or "BATTLEPASS_CLAIM", player.UserId, { level = level, track = track })
	end
	return true, nil
end


function BattlePassService.ClaimAll(player: Player, track: string): (number, string?)
	if track ~= "free" and track ~= "premium" then
		return 0, "InvalidTrack"
	end
	local profile = DataService.GetProfile(player)
	if not profile then
		return 0, "NoProfile"
	end
	ensureSeason(profile)
	local bp = profile.BattlePass
	if track == "premium" and not bp.Premium then
		return 0, "PremiumRequired"
	end
	local trackTable = if track == "free" then BattlePassConfig.FreeTrack else BattlePassConfig.PremiumTrack
	local claimedMap = if track == "free" then bp.ClaimedFree else bp.ClaimedPremium
	local claimed = 0
	local tiers: { number } = {}
	for tier in pairs(trackTable) do
		local t = tonumber(tier)
		if t then
			table.insert(tiers, t)
		end
	end
	table.sort(tiers)
	for _, level in ipairs(tiers) do
		if level >= 1 and level <= bp.Level then
			local key = tostring(level)
			if not claimedMap[key] then
				local reward = trackTable[level]
				if reward then
					claimedMap[key] = true
					grantReward(player, reward)
					claimed += 1
					if AnalyticsService and AnalyticsService.Log then
						AnalyticsService.Log(AnalyticsConfig.Events.BATTLEPASS_CLAIM or "BATTLEPASS_CLAIM", player.UserId, { level = level, track = track, batch = true })
					end
				end
			end
		end
	end
	if claimed > 0 then
		DataService.MarkDirty(player)
		pushState(player)
	end
	return claimed, nil
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
	AntiExploitService = deps.AntiExploitService

	local claimRemote = RemoteSetup.Get(Constants.RemoteNames.RequestClaimBattlePassReward) :: RemoteEvent
	claimRemote.OnServerEvent:Connect(function(player: Player, level: any, track: any)
		if not RateLimitService.Allow(player, "bp_claim", 4, 8) then
			if AntiExploitService and AntiExploitService.Strike then
				AntiExploitService.Strike(player, "bp_claim_rate")
			end
			return
		end
		if not RemoteGuard.RequireProfile(DataService, player) then
			return
		end
		if typeof(track) ~= "string" or (track ~= "free" and track ~= "premium") then
			return
		end
		-- level 0 / "all" = claim every reachable unclaimed reward on that track
		if level == 0 or level == "all" then
			local n, err = BattlePassService.ClaimAll(player, track)
			if NotificationService then
				if n > 0 then
					NotificationService.Notify(player, string.format("Claimed %d %s battle pass rewards", n, track), "Reward")
				elseif err then
					NotificationService.Notify(player, "Cannot claim: " .. tostring(err), "Warn")
				else
					NotificationService.Notify(player, "No " .. track .. " rewards ready to claim", "Info")
				end
			end
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
