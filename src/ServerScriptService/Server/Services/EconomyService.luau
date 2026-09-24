--!strict
--[[
	Server-only currency mutations. Client never sets Cash/Gold/PendingCash.

	Cash multiplier stack order (AddCash / AccruePendingCash, non-exempt reasons):
	  1. Base amount (caller)
	  2. Prestige: × (1 + Prestige * EconomyConfig.PrestigeCashMultiplierPerLevel)
	  3. Monetization VIP/DoubleCash: × MonetizationService.GetCashMultiplier
	  4. Season: × SeasonService.GetCashMult()
	  5. OutpostIncomeStacks: × (1 + stacks * OutpostIncomeBuff.MultPerStack)
	     (stacks recount from owned territories — contested / stealable)
	Passive income accrues to PendingCash (Money Collector); CollectPendingCash grants Cash.
	ATM raid transfers PendingCash thief←victim without re-applying multipliers.
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
local MoneyCollectorService: any = nil

-- v65: never index nil DataService (SpendCash must not throw GetProfile on nil)
local function getDataService(): any
	if DataService ~= nil then
		return DataService
	end
	local ok, mod = pcall(require, script.Parent.DataService)
	if ok and mod ~= nil then
		DataService = mod
		warn("[Economy] getDataService: recovered via require(script.Parent.DataService)")
		return DataService
	end
	warn("[Economy] getDataService: DataService still nil after require fallback")
	return nil
end

local function ensureLeaderstats(player: Player, cash: number, gold: number)
	-- Classic tycoon belt+suspenders: IntValues replicate to client even if remotes miss
	local folder = player:FindFirstChild("leaderstats")
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "leaderstats"
		folder.Parent = player
	end
	local cashVal = folder:FindFirstChild("Cash")
	if not cashVal then
		cashVal = Instance.new("IntValue")
		cashVal.Name = "Cash"
		cashVal.Parent = folder
	end
	if cashVal:IsA("IntValue") or cashVal:IsA("NumberValue") then
		(cashVal :: any).Value = cash
	end
	local goldVal = folder:FindFirstChild("Gold")
	if not goldVal then
		goldVal = Instance.new("IntValue")
		goldVal.Name = "Gold"
		goldVal.Parent = folder
	end
	if goldVal:IsA("IntValue") or goldVal:IsA("NumberValue") then
		(goldVal :: any).Value = gold
	end
end

local function pushEconomy(player: Player, profile: Types.PlayerProfile)
	local cash = math.floor(tonumber(profile.Cash) or 0)
	local gold = math.floor(tonumber(profile.Gold) or 0)
	local pending = math.floor(tonumber((profile :: any).PendingCash) or 0)
	-- Keep profile numeric (SpendCash / client Attribute fallback)
	profile.Cash = cash
	profile.Gold = gold
	;(profile :: any).PendingCash = pending
	-- Replicated attributes: clients that miss FireClient still read spendable Cash
	pcall(function()
		player:SetAttribute("WE_Cash", cash)
		player:SetAttribute("WE_Gold", gold)
		player:SetAttribute("WE_PendingCash", pending)
	end)
	pcall(ensureLeaderstats, player, cash, gold)
	-- v60: never yield Push on missing remotes — leaderstats/attrs already replicate
	pcall(function()
		if not RemoteSetup then
			return
		end
		local folder = game:GetService("ReplicatedStorage"):FindFirstChild(Constants.RemotesFolderName)
		local remote = folder and folder:FindFirstChild(Constants.RemoteNames.EconomyUpdate)
		if remote and remote:IsA("RemoteEvent") then
			(remote :: RemoteEvent):FireClient(player, {
				Cash = cash,
				Gold = gold,
				PendingCash = pending,
			} :: Types.EconomyUpdatePayload)
		end
	end)
end

local function applyCashMult(player: Player, profile: any, amount: number, reason: string?): number
	local mult = 1 + (profile.Prestige * (EconomyConfig.PrestigeCashMultiplierPerLevel or 0))
	local MonetizationConfig = require(Shared.Configs.MonetizationConfig)
	local reasonKey = reason or ""
	local exempt = MonetizationConfig.CashMultExemptReasons
	local isExempt = exempt and exempt[reasonKey]
	if not isExempt then
		-- Permanent outpost capture stacks (passive / structure / training AccruePendingCash)
		local buff = EconomyConfig.OutpostIncomeBuff
		if buff then
			local stacks = math.clamp(math.floor(tonumber(profile.OutpostIncomeStacks) or 0), 0, buff.MaxStacks or 5)
			if stacks > 0 then
				mult *= (1 + stacks * (buff.MultPerStack or 0.10))
			end
		end
		if MonetizationService and MonetizationService.GetCashMultiplier then
			mult *= MonetizationService.GetCashMultiplier(player)
		end
		if SeasonService and SeasonService.GetCashMult then
			mult *= SeasonService.GetCashMult()
		end
	end
	return math.floor(amount * mult)
end

function EconomyService.Init(deps: { [string]: any })
	assert(deps.DataService, "EconomyService.Init missing deps.DataService")
	SeasonService = deps.SeasonService
	DataService = deps.DataService
	RemoteSetup = deps.RemoteSetup
	MissionService = deps.MissionService
	MonetizationService = deps.MonetizationService
	TutorialService = deps.TutorialService
	MoneyCollectorService = deps.MoneyCollectorService
end

function EconomyService.Push(player: Player)
	local DS = getDataService()
	if not DS then
		return
	end
	local profile = DS.GetProfile(player)
	if profile then
		pushEconomy(player, profile)
	end
end

function EconomyService.AddCash(player: Player, amount: number, reason: string?): boolean
	if typeof(amount) ~= "number" or amount ~= amount or amount <= 0 then
		return false
	end
	amount = math.floor(amount)
	local profile = getDataService().GetProfile(player)
	if not profile then
		return false
	end

	local granted = applyCashMult(player, profile, amount, reason)
	profile.Cash = math.clamp(profile.Cash + granted, EconomyConfig.MinCash, EconomyConfig.MaxCash)
	profile.Stats.TotalCashEarned += granted
	getDataService().MarkDirty(player)
	pushEconomy(player, profile)
	if MissionService and MissionService.TrackProgress and reason ~= "mission" and reason ~= "achievement" then
		MissionService.TrackProgress(player, "EarnCash", granted)
	end
	if reason == "collector" and TutorialService and TutorialService.Notify then
		TutorialService.Notify(player, "PassiveIncome")
	end
	return true
end

--[[ Accrue passive / stipend into PendingCash (not spendable until Money Collector). ]]
function EconomyService.AccruePendingCash(player: Player, amount: number, reason: string?): boolean
	if typeof(amount) ~= "number" or amount ~= amount or amount <= 0 then
		return false
	end
	amount = math.floor(amount)
	local profile = getDataService().GetProfile(player)
	if not profile then
		return false
	end
	local granted = applyCashMult(player, profile, amount, reason)
	local pending = tonumber((profile :: any).PendingCash) or 0
	(profile :: any).PendingCash = math.clamp(pending + granted, 0, EconomyConfig.MaxCash)
	getDataService().MarkDirty(player)
	pushEconomy(player, profile)
	if MoneyCollectorService and MoneyCollectorService.RefreshForPlayer then
		MoneyCollectorService.RefreshForPlayer(player)
	end
	return true
end

function EconomyService.CollectPendingCash(player: Player): number
	local profile = getDataService().GetProfile(player)
	if not profile then
		return 0
	end
	local pending = math.floor(tonumber((profile :: any).PendingCash) or 0)
	if pending <= 0 then
		return 0
	end
	(profile :: any).PendingCash = 0
	-- Pending already had mult applied at accrue; grant with exempt reason
	profile.Cash = math.clamp(profile.Cash + pending, EconomyConfig.MinCash, EconomyConfig.MaxCash)
	profile.Stats.TotalCashEarned += pending
	getDataService().MarkDirty(player)
	pushEconomy(player, profile)
	if MissionService and MissionService.TrackProgress then
		MissionService.TrackProgress(player, "EarnCash", pending)
	end
	return pending
end

function EconomyService.GetPendingCash(player: Player): number
	local profile = getDataService().GetProfile(player)
	if not profile then
		return 0
	end
	return math.floor(tonumber((profile :: any).PendingCash) or 0)
end


--[[
	v62: EarlyRemotes seeds leaderstats/WE_Cash BEFORE DataService profile exists.
	HUD can show $50M while profile.Cash is still StartingCash → SpendCash InsufficientCash
	with no visible deduct. Lift profile.Cash to max(profile, server WE_Cash, leaderstats).
	Attrs/leaderstats are server-authored only — safe, not client-trust.
]]
function EconomyService.ReconcileSpendableCash(player: Player): number
	local DS = getDataService()
	if not DS then
		return 0
	end
	local profile = DS.GetProfile(player)
	if not profile then
		return 0
	end
	local have = math.floor(tonumber(profile.Cash) or 0)
	local attr = tonumber(player:GetAttribute("WE_Cash"))
	if typeof(attr) == "number" then
		have = math.max(have, math.floor(attr))
	end
	local folder = player:FindFirstChild("leaderstats")
	if folder then
		local cashV = folder:FindFirstChild("Cash")
		if cashV and (cashV:IsA("IntValue") or cashV:IsA("NumberValue")) then
			have = math.max(have, math.floor((cashV :: any).Value))
		end
	end
	local before = math.floor(tonumber(profile.Cash) or 0)
	if have > before then
		profile.Cash = have
		getDataService().MarkDirty(player)
		print(string.format("[Economy] Reconcile %s profile.Cash %d → %d (attr/leaderstats)", player.Name, before, have))
		pushEconomy(player, profile)
	else
		profile.Cash = have
	end
	return have
end

function EconomyService.SpendCash(player: Player, amount: number, _reason: string?): (boolean, string?)
	-- v64: NEVER throw — bad state returns false,"SpendFailed"
	-- v65: getDataService fallback so nil module never surfaces as GetProfile index error
	local ok, a, b = pcall(function(): (boolean, string?)
		local DS = getDataService()
		if not DS then
			return false, "NoDataService"
		end
		if typeof(amount) ~= "number" or amount ~= amount or amount < 0 then
			return false, "InvalidAmount"
		end
		amount = math.floor(amount)
		local profile = DS.GetProfile(player)
		if not profile then
			return false, "NoProfile"
		end
		-- v62/v64: sync profile to EarlyRemotes/leaderstats before afford check
		local have = 0
		if EconomyService.ReconcileSpendableCash then
			local rok, rhave = pcall(function()
				return EconomyService.ReconcileSpendableCash(player)
			end)
			if rok and typeof(rhave) == "number" then
				have = rhave
			end
		end
		profile = getDataService().GetProfile(player) or profile
		have = math.floor(tonumber(profile.Cash) or have)
		profile.Cash = have
		if have < amount then
			print(string.format("[Economy] SpendCash FAIL %s have=%d need=%d", player.Name, have, amount))
			return false, "InsufficientCash"
		end
		profile.Cash = have - amount
		pcall(function()
			getDataService().MarkDirty(player)
		end)
		pcall(function()
			pushEconomy(player, profile)
		end)
		return true, nil
	end)
	if not ok then
		warn("[Economy] SpendCash threw:", a)
		return false, "SpendFailed"
	end
	return (a :: any) :: boolean, b :: string?
end

function EconomyService.AddGold(player: Player, amount: number, _reason: string?): boolean
	if typeof(amount) ~= "number" or amount ~= amount or amount <= 0 then
		return false
	end
	amount = math.floor(amount)
	local profile = getDataService().GetProfile(player)
	if not profile then
		return false
	end
	profile.Gold = math.clamp(profile.Gold + amount, EconomyConfig.MinGold, EconomyConfig.MaxGold)
	profile.Stats.TotalGoldEarned += amount
	getDataService().MarkDirty(player)
	pushEconomy(player, profile)
	return true
end

function EconomyService.SpendGold(player: Player, amount: number, _reason: string?): (boolean, string?)
	if typeof(amount) ~= "number" or amount ~= amount or amount < 0 then
		return false, "InvalidAmount"
	end
	amount = math.floor(amount)
	local profile = getDataService().GetProfile(player)
	if not profile then
		return false, "NoProfile"
	end
	if profile.Gold < amount then
		return false, "InsufficientGold"
	end
	profile.Gold -= amount
	getDataService().MarkDirty(player)
	pushEconomy(player, profile)
	return true, nil
end

function EconomyService.GetCash(player: Player): number
	local profile = getDataService().GetProfile(player)
	return if profile then math.floor(tonumber(profile.Cash) or 0) else 0
end

function EconomyService.GetGold(player: Player): number
	local profile = getDataService().GetProfile(player)
	return if profile then profile.Gold else 0
end

function EconomyService.GetOutpostIncomeMultiplier(player: Player): number
	local profile = getDataService().GetProfile(player)
	if not profile then
		return 1
	end
	local buff = EconomyConfig.OutpostIncomeBuff
	if not buff then
		return 1
	end
	local stacks = math.clamp(math.floor(tonumber((profile :: any).OutpostIncomeStacks) or 0), 0, buff.MaxStacks or 5)
	return 1 + stacks * (buff.MultPerStack or 0.10)
end

--[[ Grant one outpost income stack (capped). Prefer SyncOutpostIncomeStacks for contested ownership. ]]
function EconomyService.GrantOutpostIncomeStack(player: Player): (boolean, number, number)
	local profile = getDataService().GetProfile(player)
	if not profile then
		return false, 0, 0
	end
	local buff = EconomyConfig.OutpostIncomeBuff
	if not buff then
		return false, 0, 0
	end
	local maxStacks = buff.MaxStacks or 5
	local stacks = math.floor(tonumber((profile :: any).OutpostIncomeStacks) or 0)
	if stacks >= maxStacks then
		return false, stacks, 0
	end
	stacks += 1
	(profile :: any).OutpostIncomeStacks = stacks
	getDataService().MarkDirty(player)
	local pct = math.floor((buff.MultPerStack or 0.10) * 100)
	return true, stacks, pct
end

--[[
	Recount OutpostIncomeStacks from profile.Territories (owned zone ids).
	Returns (oldStacks, newStacks, percentPerStack).
]]
function EconomyService.SyncOutpostIncomeStacks(player: Player): (number, number, number)
	local profile = getDataService().GetProfile(player)
	if not profile then
		return 0, 0, 0
	end
	local buff = EconomyConfig.OutpostIncomeBuff
	local maxStacks = if buff then (buff.MaxStacks or 5) else 5
	local pct = math.floor(((buff and buff.MultPerStack) or 0.10) * 100)
	local owned = 0
	if typeof(profile.Territories) == "table" then
		for _ in pairs(profile.Territories) do
			owned += 1
		end
	end
	local newStacks = math.clamp(owned, 0, maxStacks)
	local oldStacks = math.floor(tonumber((profile :: any).OutpostIncomeStacks) or 0)
	if oldStacks ~= newStacks then
		(profile :: any).OutpostIncomeStacks = newStacks
		getDataService().MarkDirty(player)
	end
	return oldStacks, newStacks, pct
end

--[[
	Move PendingCash from victim → thief without cash multipliers (already accrued).
	Returns amount transferred (0 if none).
]]
function EconomyService.TransferPendingCash(fromPlayer: Player, toPlayer: Player, amount: number): number
	if typeof(amount) ~= "number" or amount ~= amount or amount <= 0 then
		return 0
	end
	amount = math.floor(amount)
	local fromProfile = getDataService().GetProfile(fromPlayer)
	local toProfile = getDataService().GetProfile(toPlayer)
	if not fromProfile or not toProfile then
		return 0
	end
	local fromPending = math.floor(tonumber((fromProfile :: any).PendingCash) or 0)
	if fromPending <= 0 then
		return 0
	end
	local take = math.min(amount, fromPending)
	if take <= 0 then
		return 0
	end
	(fromProfile :: any).PendingCash = fromPending - take
	local toPending = math.floor(tonumber((toProfile :: any).PendingCash) or 0)
	;(toProfile :: any).PendingCash = math.clamp(toPending + take, 0, EconomyConfig.MaxCash)
	getDataService().MarkDirty(fromPlayer)
	getDataService().MarkDirty(toPlayer)
	pushEconomy(fromPlayer, fromProfile)
	pushEconomy(toPlayer, toProfile)
	if MoneyCollectorService and MoneyCollectorService.RefreshForPlayer then
		MoneyCollectorService.RefreshForPlayer(fromPlayer)
		MoneyCollectorService.RefreshForPlayer(toPlayer)
	end
	return take
end

return EconomyService
