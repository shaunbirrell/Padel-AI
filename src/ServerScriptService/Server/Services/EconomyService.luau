--!strict
--[[
	Server-only currency mutations. Client never sets Cash/Gold.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared.Constants)
local EconomyConfig = require(Shared.Configs.EconomyConfig)
local Types = require(Shared.Types)

local EconomyService = {}

local DataService: any = nil
local RemoteSetup: any = nil

local function pushEconomy(player: Player, profile: Types.PlayerProfile)
	local remote = RemoteSetup.Get(Constants.RemoteNames.EconomyUpdate) :: RemoteEvent
	remote:FireClient(player, {
		Cash = profile.Cash,
		Gold = profile.Gold,
	} :: Types.EconomyUpdatePayload)
end

function EconomyService.Init(deps: { [string]: any })
	DataService = deps.DataService
	RemoteSetup = deps.RemoteSetup
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
	local granted = math.floor(amount * mult)
	profile.Cash = math.clamp(profile.Cash + granted, EconomyConfig.MinCash, EconomyConfig.MaxCash)
	profile.Stats.TotalCashEarned += granted
	DataService.MarkDirty(player)
	pushEconomy(player, profile)
	return true
end

function EconomyService.SpendCash(player: Player, amount: number, reason: string?): (boolean, string?)
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

function EconomyService.AddGold(player: Player, amount: number, reason: string?): boolean
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

function EconomyService.SpendGold(player: Player, amount: number, reason: string?): (boolean, string?)
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
