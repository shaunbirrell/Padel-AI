--!strict
--[[
	Army recruitment — server-authoritative soldier counts.
	Spends Cash via EconomyService; never trusts client counts.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared.Constants)
local SoldierConfig = require(Shared.Configs.SoldierConfig)
local AnalyticsConfig = require(Shared.Configs.AnalyticsConfig)
local MonetizationConfig = require(Shared.Configs.MonetizationConfig)
local WorldLabel = require(Shared.Util.WorldLabel)

local TRAIN_POP_RADIUS = 28 -- studs: the "+$N" training pop shows only to the owner standing this close (spec §5)

local RemoteGuard = require(script.Parent.Parent.Modules.RemoteGuard)

local SoldierService = {}

local armyChangedListeners: { (Player) -> () } = {}

local DataService: any = nil
local EconomyService: any = nil
local NotificationService: any = nil
local RateLimitService: any = nil
local RemoteSetup: any = nil
local AnalyticsService: any = nil
local MissionService: any = nil
local TutorialService: any = nil

local MAX_BATCH = 50
-- Recruit/Dismiss tap limiter (per remote): 4/s sustained, 8 burst — above human tap speed for a
-- short burst; extra taps are dropped with a throttled toast (no AntiExploit strike).
local TAP_RATE = 4
local TAP_BURST = 8

local function slowDownToast(player: Player, what: string)
	if not NotificationService then
		return
	end
	local msg = "Slow down — too many " .. what .. " taps, try again in a moment"
	if NotificationService.NotifyThrottled then
		NotificationService.NotifyThrottled(player, msg, "Info", 1.5, 2, "soldier_tap_" .. what)
	end
end

local function trainingIncomePerTick(profile: any): number
	local cfg = SoldierConfig.TrainingIncome
	if not cfg then
		return 0
	end
	local count = tonumber(profile.Soldiers) or 0
	local minN = cfg.MinSoldiersForIncome or 1
	if count < minN then
		return 0
	end
	local per = cfg.CashPerSoldierPerTick or 0
	local prestigeMult = 1 + ((tonumber(profile.Prestige) or 0) * 0.05)
	return math.floor(count * per * prestigeMult)
end


local function barracksLevel(profile: any): number
	local upgrades = profile.BaseUpgrades
	if typeof(upgrades) ~= "table" then
		return 0
	end
	return tonumber(upgrades.Barracks) or 0
end

--[[ v71 money (M1, owner decision D3): Army Expansion. The live ExtraSoldierSlot product (same Id) now adds
	MonetizationConfig.DevProducts.ExtraSoldierSlot.ArmyCapBonus (10) army capacity instead of +1. It reads the
	entitlement exactly as MonetizationService records it (ProcessReceipt → GrantEntitlement("ExtraSoldierSlot")
	→ profile.Entitlements.ExtraSoldierSlot = true; admin grants use the same key), so it is retroactive: players
	who bought the old +1 slot get +10 on their next state push. A one-time boolean — owning it never stacks. ]]
local ARMY_EXPANSION_DEFAULT_BONUS = 10

local function armyCapBonus(profile: any): number
	if typeof(profile.Entitlements) ~= "table" or profile.Entitlements.ExtraSoldierSlot ~= true then
		return 0
	end
	local def: any = MonetizationConfig.DevProducts.ExtraSoldierSlot
	local bonus = if typeof(def) == "table" then tonumber(def.ArmyCapBonus) else nil
	return math.max(0, math.floor(bonus or ARMY_EXPANSION_DEFAULT_BONUS))
end

local function maxSoldiers(profile: any): number
	local base = SoldierConfig.MaxSoldiersBase or 50
	local per = SoldierConfig.SoldiersPerBarracksLevel or 5
	-- + Army Expansion (ExtraSoldierSlot DevProduct entitlement): ArmyCapBonus capacity
	return base + barracksLevel(profile) * per + armyCapBonus(profile)
end

local function pushState(player: Player)
	local profile = DataService.GetProfile(player)
	if not profile then
		return
	end
	local count = tonumber(profile.Soldiers) or 0
	local cap = maxSoldiers(profile)
	local cost = SoldierConfig.RecruitCostCash or 500
	local room = math.max(0, cap - count)
	local remote = RemoteSetup.Get(Constants.RemoteNames.SoldierStateUpdate) :: RemoteEvent
	local training = trainingIncomePerTick(profile)
	local tickSec = (SoldierConfig.TrainingIncome and SoldierConfig.TrainingIncome.TickSeconds) or 5
	remote:FireClient(player, {
		Soldiers = count,
		MaxSoldiers = cap,
		BarracksLevel = barracksLevel(profile),
		RecruitCostCash = cost,
		RecruitBatchSize = SoldierConfig.RecruitBatchSize or 1,
		DismissRefundMult = SoldierConfig.DismissRefundMult or 0.25,
		SlotsFree = room,
		FillCost = cost * room,
		TrainingIncomePerTick = training,
		TrainingTickSeconds = tickSec,
		TrainingIncomePerSec = if tickSec > 0 then training / tickSec else 0,
		-- v71 money (M1): > 0 when Army Expansion is owned (already inside MaxSoldiers); the Army panel shows OWNED
		ArmyCapBonus = armyCapBonus(profile),
	})
	for _, cb in ipairs(armyChangedListeners) do
		task.defer(cb, player)
	end
end

function SoldierService.GetCount(player: Player): number
	local profile = DataService.GetProfile(player)
	if not profile then
		return 0
	end
	return tonumber(profile.Soldiers) or 0
end

local function sanitizeAmount(amount: any): (number?, string?)
	local n = RemoteGuard.ClampPositiveInt(amount, MAX_BATCH)
	if not n then
		return nil, "InvalidAmount"
	end
	return n, nil
end

function SoldierService.Recruit(player: Player, amount: any): (boolean, string?)
	local n, serr = sanitizeAmount(amount)
	if not n then
		return false, serr
	end
	local profile = DataService.GetProfile(player)
	if not profile then
		return false, "NoProfile"
	end
	local current = tonumber(profile.Soldiers) or 0
	local cap = maxSoldiers(profile)
	if current >= cap then
		return false, "AtCap"
	end
	if current + n > cap then
		n = cap - current -- clamp to remaining slots
	end
	local costEach = SoldierConfig.RecruitCostCash or 500
	local total = costEach * n
	local ok, err = EconomyService.SpendCash(player, total, "recruit_soldiers")
	if not ok then
		return false, err or "CannotAfford"
	end
	profile.Soldiers = current + n
	DataService.MarkDirty(player)
	if MissionService and MissionService.TrackProgress then
		MissionService.TrackProgress(player, "RecruitSoldiers", n)
	end
	if TutorialService and TutorialService.Notify then
		TutorialService.Notify(player, "RecruitSoldiers", n)
	end
	pushState(player)
	if NotificationService then
		NotificationService.Notify(
			player,
			string.format("Recruited %d · Army %d/%d (−$%d)", n, profile.Soldiers, cap, total),
			"Success"
		)
	end
	local eventName = if AnalyticsConfig.Events.SOLDIER_RECRUIT then AnalyticsConfig.Events.SOLDIER_RECRUIT else "SOLDIER_RECRUIT"
	if AnalyticsService and AnalyticsService.Log then
		AnalyticsService.Log(eventName, player.UserId, { amount = n, cost = total, total = profile.Soldiers })
	end
	return true, nil
end

function SoldierService.Dismiss(player: Player, amount: any): (boolean, string?)
	local n, serr = sanitizeAmount(amount)
	if not n then
		return false, serr
	end
	local profile = DataService.GetProfile(player)
	if not profile then
		return false, "NoProfile"
	end
	local current = tonumber(profile.Soldiers) or 0
	if n > current then
		return false, "NotEnoughSoldiers"
	end
	profile.Soldiers = current - n
	local refund = math.floor((SoldierConfig.RecruitCostCash or 500) * n * (SoldierConfig.DismissRefundMult or 0.25))
	if refund > 0 then
		EconomyService.AddCash(player, refund, "dismiss_soldiers")
	end
	DataService.MarkDirty(player)
	pushState(player)
	if NotificationService then
		NotificationService.Notify(
			player,
			string.format("Dismissed %d · Army %d (−refund $%d)", n, profile.Soldiers, refund),
			"Info"
		)
	end
	local eventName = if AnalyticsConfig.Events.SOLDIER_DISMISS then AnalyticsConfig.Events.SOLDIER_DISMISS else "SOLDIER_DISMISS"
	if AnalyticsService and AnalyticsService.Log then
		AnalyticsService.Log(eventName, player.UserId, { amount = n, refund = refund })
	end
	return true, nil
end

function SoldierService.Push(player: Player)
	pushState(player)
end

function SoldierService.OnArmyChanged(cb: (Player) -> ())
	table.insert(armyChangedListeners, cb)
end


local function refreshTrainingYardFeedback(player: Player, profile: any, tickAmount: number)
	local plotId = profile.BasePlotId
	if typeof(plotId) ~= "number" then
		return
	end
	local setup = game:GetService("Workspace"):FindFirstChild("WarEmpireSetup")
	if not setup then
		return
	end
	local bases = setup:FindFirstChild("Bases")
	if not bases then
		return
	end
	local plotFolder = bases:FindFirstChild("Plot" .. tostring(plotId))
	if not plotFolder then
		return
	end
	local yard = plotFolder:FindFirstChild("TrainingYard")
	if not yard then
		return
	end
	local anchor = yard:FindFirstChild("YardPad")
		or yard:FindFirstChild("YardEarnAnchor")
		or yard:FindFirstChild("YardAnchor")
	if not anchor or not anchor:IsA("BasePart") then
		return
	end
	-- v71 (spec §5): no "+$/tick" earn board over the yard (the old one also looked for a label named "Amount"
	-- that MapSetup's board never had, so it never updated). One owner-only "+$N" pop per tick, and only while
	-- the owner stands near the yard — nobody else sees it and nothing is made for an empty yard.
	local char = player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	if not (hrp and hrp:IsA("BasePart")) or (hrp.Position - anchor.Position).Magnitude > TRAIN_POP_RADIUS then
		return
	end
	local pop = WorldLabel.Create(anchor, string.format("+$%d", tickAmount), {
		Name = "WE_TrainCashPop",
		Color = Color3.fromRGB(100, 255, 140),
		TextSize = 18,
		Studs = Vector2.new(3, 1.2),
		Offset = Vector3.new(0, 3.5, 0),
		MaxDistance = TRAIN_POP_RADIUS,
		OwnerUserId = player.UserId,
	})
	local popLab = pop:FindFirstChild("Title")
	task.spawn(function()
		for i = 1, 6 do
			pop.StudsOffsetWorldSpace = Vector3.new(0, 3.5 + i * 0.4, 0)
			if popLab and popLab:IsA("TextLabel") then
				popLab.TextTransparency = i / 7
			end
			task.wait(0.1)
		end
		pop:Destroy()
	end)
end

function SoldierService.Init(deps: { [string]: any })
	DataService = deps.DataService
	EconomyService = deps.EconomyService
	NotificationService = deps.NotificationService
	RateLimitService = deps.RateLimitService
	RemoteSetup = deps.RemoteSetup
	AnalyticsService = deps.AnalyticsService
	MissionService = deps.MissionService
	TutorialService = deps.TutorialService

	local recruitRemote = RemoteSetup.Get(Constants.RemoteNames.RequestRecruitSoldiers) :: RemoteEvent
	recruitRemote.OnServerEvent:Connect(function(player: Player, amount: any)
		-- v69: fast taps are normal play — drop extras with a throttled toast, never an AntiExploit strike
		if not RateLimitService.Allow(player, "soldier_recruit", TAP_RATE, TAP_BURST) then
			slowDownToast(player, "recruit")
			return
		end
		if not RemoteGuard.RequireProfile(DataService, player) then
			return
		end
		local ok, err = SoldierService.Recruit(player, amount)
		if not ok and NotificationService then
			local msg = "Recruit failed: " .. tostring(err)
			if err == "AtCap" then
				msg = "Army at capacity — upgrade Barracks"
			elseif err == "InsufficientCash" or err == "CannotAfford" then
				msg = "Not enough cash to recruit"
			end
			NotificationService.Notify(player, msg, "Warn")
		end
	end)

	local dismissRemote = RemoteSetup.Get(Constants.RemoteNames.RequestDismissSoldiers) :: RemoteEvent
	dismissRemote.OnServerEvent:Connect(function(player: Player, amount: any)
		if not RateLimitService.Allow(player, "soldier_dismiss", TAP_RATE, TAP_BURST) then
			slowDownToast(player, "dismiss")
			return
		end
		if not RemoteGuard.RequireProfile(DataService, player) then
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
		-- Re-push after client controllers connect (missed SoldierStateUpdate race)
		task.delay(1.5, function()
			if player.Parent then
				pushState(player)
			end
		end)
		player.CharacterAdded:Connect(function()
			task.defer(function()
				if player.Parent then
					pushState(player)
				end
			end)
		end)
	end)

	-- Training Yard worker income (MT-inspired)
	task.spawn(function()
		local Players = game:GetService("Players")
		while true do
			local tickSec = (SoldierConfig.TrainingIncome and SoldierConfig.TrainingIncome.TickSeconds) or 5
			task.wait(tickSec)
			for _, player in ipairs(Players:GetPlayers()) do
				local profile = DataService.GetProfile(player)
				if profile then
					local amount = trainingIncomePerTick(profile)
					if amount > 0 then
						-- AFK training → PendingCash (Money Collector / AutoCollect). Not AddCash bypass.
						if EconomyService.AccruePendingCash then
							EconomyService.AccruePendingCash(player, amount, "training")
						else
							EconomyService.AddCash(player, amount, "training")
						end
						refreshTrainingYardFeedback(player, profile, amount)
					end
				end
			end
		end
	end)
end

return SoldierService
