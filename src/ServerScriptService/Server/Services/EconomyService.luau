--!strict
--[[
	Server-only currency mutations. Client never sets Cash/Gold/PendingCash.

	Cash multiplier stack order (AddCash / AccruePendingCash, non-exempt reasons):
	  1. Base amount (caller)
	  2. Prestige: × (1 + Prestige * EconomyConfig.PrestigeCashMultiplierPerLevel)
	  3. Monetization VIP/DoubleCash: × MonetizationService.GetCashMultiplier
	  4. Season: × SeasonService.GetCashMult()
	  5. Empire Tax (F3): × (1 + EmpireTaxPct / 100). EmpireTaxPct = OutpostIncomeStacks x MultPerStack (10 %) plus
	     StarterPct (5 %) while the player holds their OWN Home Outpost, capped at MaxStacks x MultPerStack (50 %).
	     Stacks recount from owned territories (contested / stealable); a Home Outpost is never a stack.
	Passive income accrues to PendingCash (Money Collector); CollectPendingCash grants Cash.
	ATM raid transfers PendingCash thief←victim without re-applying multipliers.

	B1 (owner's 11 features, lane E): prestige is applied ONCE, here (step 2). BaseService's passive per-tick amount
	and SoldierService's training per-tick amount are pre-multiplier, so prestige 1 pays exactly +10 %.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared.Constants)
local EconomyConfig = require(Shared.Configs.EconomyConfig)
local TycoonGuideConfig = require(Shared.Configs.TycoonGuideConfig)
local TerritoryConfig = require(Shared.Configs.TerritoryConfig)
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

-- v69: refunds / purchases / pre-multiplied transfers are paid 1:1 even if the config list drifts
-- (a multiplied dismiss refund > recruit cost is an infinite-cash loop at high prestige).
local NEVER_MULTIPLIED: { [string]: boolean } = {
	dismiss_soldiers = true,
	purchase_refund = true,
	devproduct = true,
	admin = true,
	collector = true,
	atm_raid = true,
}

--[[ F3 Empire Tax (EconomyConfig.OutpostIncomeBuff). A Home Outpost row (TerritoryConfig.Starter, F10) is never a
	stack: its id carries Starter.IdPrefix (so does a leftover id saved while the Starter was on, if it is off now).
	Only the player's OWN Home Outpost (def.PlotId == profile.BasePlotId; the row exists only while Starter.Enabled)
	adds StarterPct. Pure reads of the profile: no workspace, no yield. ]]
local function isStarterId(id: any): boolean
	if typeof(id) ~= "string" then
		return false
	end
	if TerritoryConfig.IsStarterDef(TerritoryConfig.Territories[id]) then
		return true
	end
	local prefix = TerritoryConfig.Starter and TerritoryConfig.Starter.IdPrefix
	return typeof(prefix) == "string" and prefix ~= "" and string.sub(id, 1, #prefix) == prefix
end

local function ownsOwnStarter(profile: any): boolean
	local st = TerritoryConfig.Starter
	local plotId = tonumber(profile.BasePlotId)
	local owned = profile.Territories
	if not st or plotId == nil or plotId ~= plotId or typeof(owned) ~= "table" then
		return false
	end
	local plot = math.floor(plotId)
	local id = tostring(st.IdPrefix) .. tostring(plot)
	if owned[id] ~= true then
		return false
	end
	local def = TerritoryConfig.Territories[id]
	return def ~= nil and TerritoryConfig.IsStarterDef(def) and def.PlotId == plot
end

-- whole % per captured outpost (10), MaxStacks (5) and the cap (50); float-safe (0.1 x 100 -> 10)
local function empireTaxSteps(): (number, number, number)
	local buff = EconomyConfig.OutpostIncomeBuff
	local perStack = math.floor(((buff and buff.MultPerStack) or 0.10) * 100 + 0.5)
	local maxStacks = math.max(0, math.floor((buff and buff.MaxStacks) or 5))
	return perStack, maxStacks, maxStacks * perStack
end

local function storedStacks(profile: any, maxStacks: number): number
	local n = tonumber(profile.OutpostIncomeStacks) or 0
	if n ~= n then
		return 0
	end
	return math.clamp(math.floor(n), 0, maxStacks)
end

-- Whole-number Empire Tax % for a profile: min(cap, stacks x 10 + (own Home Outpost held and StarterPct or 0))
local function empireTaxPct(profile: any): number
	local buff = EconomyConfig.OutpostIncomeBuff
	if not buff or typeof(profile) ~= "table" then
		return 0
	end
	local perStack, maxStacks, cap = empireTaxSteps()
	local pct = storedStacks(profile, maxStacks) * perStack
	if ownsOwnStarter(profile) then
		pct += math.max(0, math.floor(tonumber(buff.StarterPct) or 0))
	end
	return math.clamp(pct, 0, cap)
end

local EMPIRE_TAX_ATTR = "WE_EmpireTaxPct" -- = EconomyConfig.OutpostIncomeBuff.Attribute (fallback only)

-- WE_EmpireTaxPct (display only: the HUD chip). Written only when the value changes; nil and 0 both mean "none".
local function publishEmpireTax(player: Player, pct: number)
	local buff = EconomyConfig.OutpostIncomeBuff
	local attr = if buff and typeof(buff.Attribute) == "string" then buff.Attribute else EMPIRE_TAX_ATTR
	pcall(function()
		local cur = player:GetAttribute(attr)
		if cur ~= pct and not (cur == nil and pct == 0) then
			player:SetAttribute(attr, pct)
		end
	end)
end

local function cashMultFor(player: Player, profile: any, reason: string?): number
	local MonetizationConfig = require(Shared.Configs.MonetizationConfig)
	local reasonKey = reason or ""
	local exempt = MonetizationConfig.CashMultExemptReasons
	local isExempt = NEVER_MULTIPLIED[reasonKey] == true or (exempt ~= nil and exempt[reasonKey] == true)
	local mult = 1
	if not isExempt then
		-- v69: prestige is part of the non-exempt stack (was applied to exempt reasons too)
		local prestige = math.max(0, tonumber(profile.Prestige) or 0)
		mult = 1 + prestige * (EconomyConfig.PrestigeCashMultiplierPerLevel or 0)
		-- F3 Empire Tax: captured outposts (+10 % each) and the own Home Outpost (+5 %), capped at +50 %
		local taxPct = empireTaxPct(profile)
		if taxPct > 0 then
			mult *= (1 + taxPct / 100)
		end
		if MonetizationService and MonetizationService.GetCashMultiplier then
			mult *= MonetizationService.GetCashMultiplier(player)
		end
		if SeasonService and SeasonService.GetCashMult then
			mult *= SeasonService.GetCashMult()
		end
	end
	return mult
end

local function applyCashMult(player: Player, profile: any, amount: number, reason: string?): number
	return math.floor(amount * cashMultFor(player, profile, reason))
end

-- v72: the multiplier AddCash / AccruePendingCash would apply for `reason` right now (1 for exempt reasons).
-- Display only (BaseService.IncomeMult -> WE_IncomeMult); never used to grant.
function EconomyService.GetCashMult(player: Player, reason: string?): number
	local DS = getDataService()
	local profile = if DS then DS.GetProfile(player) else nil
	if not profile then
		return 1
	end
	return cashMultFor(player, profile, reason)
end

--[[ v72 WE_IncomePerSec (tycoon guide: cash pill "+$24/s", the pick's "ready in"): the last amount granted per steady
	reason (TycoonGuideConfig.SteadyIncomeReasons: passive / training / plot_oil), multipliers included, summed and
	divided by the passive TickSeconds, rounded to 0.1. A reason that missed SteadyIncomeExpireTicks ticks drops out
	(oil pumps after a rebirth). Written only when the value changes. Nothing here grants or changes money. ]]
type SteadyEntry = { Amount: number, At: number }
local steadyIncome: { [number]: { [string]: SteadyEntry } } = {}

-- F4 WE_TickTraining: the last training grant ($ per training tick, multipliers in) for the client's Training Yard
-- label (ProducerLabels). Gated on EconomyConfig.ProducerLabels.Enabled only (not the guide flag); written only when
-- the value changes. Oil pumps need no attribute: plot_oil is exempt, the label reads PlotOilPumpConfig.CashPerTick.
local TICK_TRAINING_ATTR = "WE_TickTraining"

local function noteTrainingTick(player: Player, reason: string?, granted: number)
	local labels = EconomyConfig.ProducerLabels
	if reason ~= "training" or not (labels and labels.Enabled == true) then
		return
	end
	pcall(function()
		if player:GetAttribute(TICK_TRAINING_ATTR) ~= granted then
			player:SetAttribute(TICK_TRAINING_ATTR, granted)
		end
	end)
end

local function noteSteadyIncome(player: Player, reason: string?, granted: number)
	noteTrainingTick(player, reason, granted) -- F4 (own flag; runs even while the guide is off)
	if not TycoonGuideConfig.Enabled or reason == nil or TycoonGuideConfig.SteadyIncomeReasons[reason] ~= true then
		return
	end
	local now = os.clock()
	local book = steadyIncome[player.UserId]
	if book == nil then
		book = {}
		steadyIncome[player.UserId] = book
	end
	local b = book :: { [string]: SteadyEntry }
	b[reason] = { Amount = granted, At = now }
	local tickSec = EconomyConfig.PassiveIncome.TickSeconds
	-- half a tick of slack: the pay loops wait TickSeconds plus their own work between grants
	local window = (TycoonGuideConfig.SteadyIncomeExpireTicks + 0.5) * tickSec
	local sum = 0
	for r, e in pairs(b) do
		if now - e.At > window then
			b[r] = nil
		else
			sum += e.Amount
		end
	end
	local perSec = if tickSec > 0 then math.floor(sum / tickSec * 10 + 0.5) / 10 else 0
	pcall(function()
		if player:GetAttribute("WE_IncomePerSec") ~= perSec then
			player:SetAttribute("WE_IncomePerSec", perSec)
		end
	end)
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
	if TycoonGuideConfig.Enabled then
		game:GetService("Players").PlayerRemoving:Connect(function(player: Player)
			steadyIncome[player.UserId] = nil
		end)
	end
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
	noteSteadyIncome(player, reason, granted) -- v72 WE_IncomePerSec (display only; no-op while the guide is off)
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
	noteSteadyIncome(player, reason, granted) -- v72 WE_IncomePerSec (display only; no-op while the guide is off)
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
	v67: the loaded profile is the only source of truth. v62 lifted profile.Cash to max(profile, WE_Cash,
	leaderstats) because the profile was a placeholder while DataService failed to load; with real loads
	that turned any stale display value (EarlyRemotes' seeded StartingCash, cash before a rebirth reset)
	into free money. Now the displays are re-synced to the profile instead.
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
	profile.Cash = have
	local attr = tonumber(player:GetAttribute("WE_Cash"))
	if attr == nil or math.floor(attr) ~= have then
		pushEconomy(player, profile)
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
	local DS = getDataService()
	local profile = if DS then DS.GetProfile(player) else nil
	if not profile then
		return 1
	end
	return 1 + empireTaxPct(profile) / 100
end

--[[ F3: the player's Empire Tax as a whole percent (0..50): captured outposts x 10 + 5 for the own Home Outpost,
	capped. The same number cashMultFor pays with and WE_EmpireTaxPct shows. 0 without a profile. Never yields. ]]
function EconomyService.EmpireTaxPct(player: Player): number
	local DS = getDataService()
	local profile = if DS then DS.GetProfile(player) else nil
	if not profile then
		return 0
	end
	return empireTaxPct(profile)
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
	publishEmpireTax(player, empireTaxPct(profile))
	local pct = empireTaxSteps()
	return true, stacks, pct
end

--[[
	Recount OutpostIncomeStacks from profile.Territories (owned zone ids). F3: Home Outposts (Starter rows) are never
	a stack; the own one adds StarterPct to the total instead. Publishes WE_EmpireTaxPct (only when it changes).
	Returns (oldStacks, newStacks, percentPerStack, totalEmpireTaxPct). The 4th value is new in F3 (callers that read
	three values are unchanged); toasts that name the total use it or EconomyService.EmpireTaxPct.
	PersistClaims (EconomyConfig.OutpostIncomeBuff, lane W): the % is always derived from the profile, which is what
	persists; re-planting saved claims on join / releasing them on leave is TerritoryService's, which calls this after.
]]
function EconomyService.SyncOutpostIncomeStacks(player: Player): (number, number, number, number)
	local DS = getDataService()
	local profile = if DS then DS.GetProfile(player) else nil
	if not profile then
		return 0, 0, 0, 0
	end
	local perStack, maxStacks = empireTaxSteps()
	local owned = 0
	if typeof(profile.Territories) == "table" then
		for id in pairs(profile.Territories) do
			if not isStarterId(id) then
				owned += 1
			end
		end
	end
	local newStacks = math.clamp(owned, 0, maxStacks)
	local oldStacks = math.floor(tonumber((profile :: any).OutpostIncomeStacks) or 0)
	if oldStacks ~= oldStacks then
		oldStacks = 0
	end
	if oldStacks ~= newStacks then
		(profile :: any).OutpostIncomeStacks = newStacks
		DS.MarkDirty(player)
	end
	local total = empireTaxPct(profile)
	publishEmpireTax(player, total)
	return oldStacks, newStacks, perStack, total
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
