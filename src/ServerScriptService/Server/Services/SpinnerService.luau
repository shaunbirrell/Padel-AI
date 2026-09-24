--!strict
--[[
	Free Supply Spinner — claim Cash/Gold every CooldownSeconds (HUD / Settings).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared.Constants)
local SpinnerConfig = require(Shared.Configs.SpinnerConfig)
local AnalyticsConfig = require(Shared.Configs.AnalyticsConfig)

local RemoteGuard = require(script.Parent.Parent.Modules.RemoteGuard)

local SpinnerService = {}

local DataService: any = nil
local EconomyService: any = nil
local NotificationService: any = nil
local RateLimitService: any = nil
local RemoteSetup: any = nil
local AnalyticsService: any = nil

local function pickReward(): any
	local rewards = SpinnerConfig.Rewards
	local total = 0
	for _, r in ipairs(rewards) do
		total += math.max(0, tonumber(r.Weight) or 0)
	end
	if total <= 0 then
		return rewards[1]
	end
	local roll = math.random() * total
	local acc = 0
	for _, r in ipairs(rewards) do
		acc += math.max(0, tonumber(r.Weight) or 0)
		if roll <= acc then
			return r
		end
	end
	return rewards[#rewards]
end

local function remainingSeconds(profile: any): number
	local last = tonumber(profile.LastSpinnerClaimUnix) or 0
	local cd = SpinnerConfig.CooldownSeconds or (4 * 3600)
	local readyAt = last + cd
	return math.max(0, readyAt - os.time())
end

local function pushState(player: Player)
	local profile = DataService.GetProfile(player)
	if not profile then
		return
	end
	local rem = remainingSeconds(profile)
	local remote = RemoteSetup.Get(Constants.RemoteNames.SpinnerStateUpdate) :: RemoteEvent
	remote:FireClient(player, {
		Ready = rem <= 0,
		CooldownRemaining = rem,
		CooldownSeconds = SpinnerConfig.CooldownSeconds,
		DisplayName = SpinnerConfig.DisplayName or "Supply Spinner",
	})
end

function SpinnerService.Claim(player: Player): (boolean, string?)
	if not SpinnerConfig.Enabled then
		return false, "Disabled"
	end
	local profile = DataService.GetProfile(player)
	if not profile then
		return false, "NoProfile"
	end
	local rem = remainingSeconds(profile)
	if rem > 0 then
		return false, "Cooldown"
	end

	local reward = pickReward()
	local cash = tonumber(reward.Cash) or 0
	local gold = tonumber(reward.Gold) or 0
	profile.LastSpinnerClaimUnix = os.time()
	DataService.MarkDirty(player)

	if cash > 0 then
		EconomyService.AddCash(player, cash, "spinner")
	end
	if gold > 0 then
		EconomyService.AddGold(player, gold, "spinner")
	end

	if NotificationService then
		local name = reward.DisplayName or "Supply"
		NotificationService.Notify(
			player,
			string.format("%s: +$%d · +%d Gold", name, cash, gold),
			"Reward"
		)
	end
	if AnalyticsService then
		AnalyticsService.Log(AnalyticsConfig.Events.SPINNER_CLAIM, player.UserId, {
			rewardId = reward.Id,
			cash = cash,
			gold = gold,
		})
	end
	pushState(player)
	return true, nil
end

function SpinnerService.Push(player: Player)
	pushState(player)
end

function SpinnerService.Init(deps: { [string]: any })
	DataService = deps.DataService
	EconomyService = deps.EconomyService
	NotificationService = deps.NotificationService
	RateLimitService = deps.RateLimitService
	RemoteSetup = deps.RemoteSetup
	AnalyticsService = deps.AnalyticsService

	local remote = RemoteSetup.Get(Constants.RemoteNames.RequestClaimSpinner) :: RemoteEvent
	remote.OnServerEvent:Connect(function(player: Player)
		-- v69: extra taps are dropped silently (the allowed tap already answered) — never a strike
		if not RateLimitService.Allow(player, "spinner_claim", 1, 2) then
			return
		end
		if not RemoteGuard.RequireProfile(DataService, player) then
			return
		end
		local ok, err = SpinnerService.Claim(player)
		if not ok and NotificationService then
			if err == "Cooldown" then
				local profile = DataService.GetProfile(player)
				local rem = if profile then remainingSeconds(profile) else 0
				local mins = math.ceil(rem / 60)
				NotificationService.Notify(player, string.format("Spinner ready in %dm", mins), "Warn")
			else
				NotificationService.Notify(player, "Spinner unavailable", "Warn")
			end
		end
	end)

	DataService.OnProfileLoaded(function(player: Player, profile: any)
		if typeof(profile.LastSpinnerClaimUnix) ~= "number" then
			profile.LastSpinnerClaimUnix = 0
			DataService.MarkDirty(player)
		end
		pushState(player)
	end)
end

return SpinnerService
