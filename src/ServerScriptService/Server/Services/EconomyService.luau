--!strict
--[[
	Server-only currency mutations. Client never sets Cash/Gold.

	Cash multiplier stack order (AddCash, non-exempt reasons):
	  1. Base amount (caller)
	  2. Prestige: × (1 + Prestige * EconomyConfig.PrestigeCashMultiplierPerLevel)  -- +10%/rebirth
	  3. Monetization VIP/DoubleCash: × MonetizationService.GetCashMultiplier
	     (VIP additive +0.25 into a base of 1, then DoubleCash ×2)
	  4. Season: × SeasonService.GetCashMult()
	Exempt reasons (MonetizationConfig.CashMultExemptReasons) skip steps 3–4 only;
	prestige mult still applies unless reason is listed — currently prestige gold path
	uses AddGold; cash exempts (devproduct/admin/code/spinner/…) skip VIP/season only.
	Passive / worker training / capture stipend / combat kill rewards all use AddCash
	so prestige + VIP/2x + season stack consistently.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared.Constants)
local EconomyConfig = require(Shared.Configs.EconomyConfig)
local Types = require(Shared.Types)

local EconomyService = {}

local SeasonService: any = nil

local DataService: any = nil
local RemoteSetup: any = nil
local MissionService: any = nil
local MonetizationService: any = nil
local TutorialService: any = nil

local function pushEconomy(player: Player, profile: Types.PlayerProfile)
	local remote = RemoteSetup.Get(Constants.RemoteNames.EconomyUpdate) :: RemoteEvent
	remote:FireClient(player, {
		Cash = profile.Cash,
		Gold = profile.Gold,
	} :: Types.EconomyUpdatePayload)
end

function EconomyService.Init(deps: { [string]: any })
	SeasonService = deps.SeasonService
	DataService = deps.DataService
	RemoteSetup = deps.RemoteSetup
	MissionService = deps.MissionService
	MonetizationService = deps.MonetizationService
	TutorialService = deps.TutorialService
end

function EconomyService.Push(player: Player)
	local profile = DataService.GetProfile(player)
	if profile then
		pushEconomy(player, profile)
	end
end

function EconomyService.AddCash(player: Player, amount: number, reason: string?): boolean
	if typeof(amount) ~= "number" or amount ~= amount or amount <= 0 then
		return false
	end
	amount = math.floor(amount)
	local profile = DataService.GetProfile(player)
	if not profile then
		return false
	end

	local mult = 1 + (profile.Prestige * (EconomyConfig.PrestigeCashMultiplierPerLevel or 0))
	local MonetizationConfig = require(Shared.Configs.MonetizationConfig)
	local reasonKey = reason or ""
	local exempt = MonetizationConfig.CashMultExemptReasons
	if MonetizationService and MonetizationService.GetCashMultiplier and not (exempt and exempt[reasonKey]) then
		mult *= MonetizationService.GetCashMultiplier(player)
	end
	if SeasonService and SeasonService.GetCashMult and not (exempt and exempt[reasonKey]) then
		mult *= SeasonService.GetCashMult()
	end
	local granted = math.floor(amount * mult)
	profile.Cash = math.clamp(profile.Cash + granted, EconomyConfig.MinCash, EconomyConfig.MaxCash)
	profile.Stats.TotalCashEarned += granted
	DataService.MarkDirty(player)
	pushEconomy(player, profile)
	-- Feed daily EarnCash missions (skip recursive mission reward noise is fine)
	if MissionService and MissionService.TrackProgress and reason ~= "mission" and reason ~= "achievement" then
		MissionService.TrackProgress(player, "EarnCash", granted)
	end
	if reason == "passive" and TutorialService and TutorialService.Notify then
		TutorialService.Notify(player, "PassiveIncome")
	end
	return true
end

function EconomyService.SpendCash(player: Player, amount: number, _reason: string?): (boolean, string?)
	if typeof(amount) ~= "number" or amount ~= amount or amount < 0 then
		return false, "InvalidAmount"
	end
	amount = math.floor(amount)
	local profile = DataService.GetProfile(player)
	if not profile then
		return false, "NoProfile"
	end
	if profile.Cash < amount then
		return false, "InsufficientCash"
	end
	profile.Cash -= amount
	DataService.MarkDirty(player)
	pushEconomy(player, profile)
	return true, nil
end

function EconomyService.AddGold(player: Player, amount: number, _reason: string?): boolean
	if typeof(amount) ~= "number" or amount ~= amount or amount <= 0 then
		return false
	end
	amount = math.floor(amount)
	local profile = DataService.GetProfile(player)
	if not profile then
		return false
	end
	profile.Gold = math.clamp(profile.Gold + amount, EconomyConfig.MinGold, EconomyConfig.MaxGold)
	profile.Stats.TotalGoldEarned += amount
	DataService.MarkDirty(player)
	pushEconomy(player, profile)
	return true
end

function EconomyService.SpendGold(player: Player, amount: number, _reason: string?): (boolean, string?)
	if typeof(amount) ~= "number" or amount ~= amount or amount < 0 then
		return false, "InvalidAmount"
	end
	amount = math.floor(amount)
	local profile = DataService.GetProfile(player)
	if not profile then
		return false, "NoProfile"
	end
	if profile.Gold < amount then
		return false, "InsufficientGold"
	end
	profile.Gold -= amount
	DataService.MarkDirty(player)
	pushEconomy(player, profile)
	return true, nil
end

function EconomyService.GetCash(player: Player): number
	local profile = DataService.GetProfile(player)
	return if profile then profile.Cash else 0
end

function EconomyService.GetGold(player: Player): number
	local profile = DataService.GetProfile(player)
	return if profile then profile.Gold else 0
end

return EconomyService
