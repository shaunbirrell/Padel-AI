--!strict
--[[
	Army recruitment — server-authoritative soldier counts.
	Spends Cash via EconomyService; never trusts client counts.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared.Constants)
local SoldierConfig = require(Shared.Configs.SoldierConfig)

local SoldierService = {}

local DataService: any = nil
local EconomyService: any = nil
local NotificationService: any = nil
local RateLimitService: any = nil
local RemoteSetup: any = nil
local AnalyticsService: any = nil

local function barracksLevel(profile: any): number
	local upgrades = profile.BaseUpgrades
	if typeof(upgrades) ~= "table" then
		return 0
	end
	return tonumber(upgrades.Barracks) or 0
end

local function maxSoldiers(profile: any): number
	local base = SoldierConfig.MaxSoldiersBase or 50
	local per = SoldierConfig.SoldiersPerBarracksLevel or 5
	return base + barracksLevel(profile) * per
end

local function pushState(player: Player)
	local profile = DataService.GetProfile(player)
	if not profile then
		return
	end
	local count = tonumber(profile.Soldiers) or 0
	local remote = RemoteSetup.Get(Constants.RemoteNames.SoldierStateUpdate) :: RemoteEvent
	remote:FireClient(player, {
		Soldiers = count,
		MaxSoldiers = maxSoldiers(profile),
		BarracksLevel = barracksLevel(profile),
		RecruitCostCash = SoldierConfig.RecruitCostCash or 500,
		RecruitBatchSize = SoldierConfig.RecruitBatchSize or 1,
		DismissRefundMult = SoldierConfig.DismissRefundMult or 0.25,
	})
end

function SoldierService.GetCount(player: Player): number
	local profile = DataService.GetProfile(player)
	if not profile then
		return 0
	end
	return tonumber(profile.Soldiers) or 0
end

function SoldierService.Recruit(player: Player, amount: any): (boolean, string?)
	if typeof(amount) ~= "number" or amount ~= amount then
		return false, "InvalidAmount"
	end
	amount = math.floor(amount)
	if amount < 1 or amount > 50 then
		return false, "InvalidAmount"
	end
	local profile = DataService.GetProfile(player)
	if not profile then
		return false, "NoProfile"
	end
	local current = tonumber(profile.Soldiers) or 0
	local cap = maxSoldiers(profile)
	if current + amount > cap then
		return false, "AtCap"
	end
	local costEach = SoldierConfig.RecruitCostCash or 500
	local total = costEach * amount
	local ok, err = EconomyService.SpendCash(player, total, "recruit_soldiers")
	if not ok then
		return false, err or "CannotAfford"
	end
	profile.Soldiers = current + amount
	DataService.MarkDirty(player)
	pushState(player)
	if NotificationService then
		NotificationService.Notify(player, string.format("Recruited %d soldiers (-$%d)", amount, total), "Success")
	end
	if AnalyticsService and AnalyticsService.Log then
		AnalyticsService.Log("SOLDIER_RECRUIT", player.UserId, { amount = amount, cost = total })
	end
	return true, nil
end

function SoldierService.Dismiss(player: Player, amount: any): (boolean, string?)
	if typeof(amount) ~= "number" or amount ~= amount then
		return false, "InvalidAmount"
	end
	amount = math.floor(amount)
	if amount < 1 or amount > 50 then
		return false, "InvalidAmount"
	end
	local profile = DataService.GetProfile(player)
	if not profile then
		return false, "NoProfile"
	end
	local current = tonumber(profile.Soldiers) or 0
	if amount > current then
		return false, "NotEnoughSoldiers"
	end
	profile.Soldiers = current - amount
	local refund = math.floor((SoldierConfig.RecruitCostCash or 500) * amount * (SoldierConfig.DismissRefundMult or 0.25))
	if refund > 0 then
		EconomyService.AddCash(player, refund, "dismiss_soldiers")
	end
	DataService.MarkDirty(player)
	pushState(player)
	if NotificationService then
		NotificationService.Notify(player, string.format("Dismissed %d soldiers (+$%d)", amount, refund), "Info")
	end
	return true, nil
end

function SoldierService.Push(player: Player)
	pushState(player)
end

function SoldierService.Init(deps: { [string]: any })
	DataService = deps.DataService
	EconomyService = deps.EconomyService
	NotificationService = deps.NotificationService
	RateLimitService = deps.RateLimitService
	RemoteSetup = deps.RemoteSetup
	AnalyticsService = deps.AnalyticsService

	local recruitRemote = RemoteSetup.Get(Constants.RemoteNames.RequestRecruitSoldiers) :: RemoteEvent
	recruitRemote.OnServerEvent:Connect(function(player: Player, amount: any)
		if not RateLimitService.Allow(player, "soldier_recruit", 2, 4) then
			return
		end
		local ok, err = SoldierService.Recruit(player, amount)
		if not ok and NotificationService then
			NotificationService.Notify(player, "Recruit failed: " .. tostring(err), "Warn")
		end
	end)

	local dismissRemote = RemoteSetup.Get(Constants.RemoteNames.RequestDismissSoldiers) :: RemoteEvent
	dismissRemote.OnServerEvent:Connect(function(player: Player, amount: any)
		if not RateLimitService.Allow(player, "soldier_dismiss", 2, 4) then
			return
		end
		local ok, err = SoldierService.Dismiss(player, amount)
		if not ok and NotificationService then
			NotificationService.Notify(player, "Dismiss failed: " .. tostring(err), "Warn")
		end
	end)

	DataService.OnProfileLoaded(function(player: Player, profile: any)
		if typeof(profile.Soldiers) ~= "number" then
			profile.Soldiers = SoldierConfig.StartingSoldiers or 5
			DataService.MarkDirty(player)
		end
		pushState(player)
	end)
end

return SoldierService
