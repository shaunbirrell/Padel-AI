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

local RemoteGuard = require(script.Parent.Parent.Modules.RemoteGuard)

local SoldierService = {}

local DataService: any = nil
local EconomyService: any = nil
local NotificationService: any = nil
local RateLimitService: any = nil
local RemoteSetup: any = nil
local AnalyticsService: any = nil
local AntiExploitService: any = nil
local MissionService: any = nil
local TutorialService: any = nil

local MAX_BATCH = 50

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
	})
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
	local anchor = yard:FindFirstChild("YardEarnAnchor") or yard:FindFirstChild("YardAnchor")
	if not anchor or not anchor:IsA("BasePart") then
		return
	end
	local bb = anchor:FindFirstChild("WE_TrainingEarnBillboard")
	if not bb or not bb:IsA("BillboardGui") then
		bb = Instance.new("BillboardGui")
		bb.Name = "WE_TrainingEarnBillboard"
		bb.Size = UDim2.fromOffset(180, 48)
		bb.StudsOffset = Vector3.new(0, 4, 0)
		bb.AlwaysOnTop = true
		bb.MaxDistance = 80
		bb.Parent = anchor
		local label = Instance.new("TextLabel")
		label.Name = "Amount"
		label.Size = UDim2.fromScale(1, 1)
		label.BackgroundTransparency = 1
		label.Font = Enum.Font.GothamBold
		label.TextScaled = true
		label.TextColor3 = Color3.fromRGB(90, 240, 130)
		label.TextStrokeTransparency = 0.4
		label.Parent = bb
	end
	local amountLabel = bb:FindFirstChild("Amount")
	if amountLabel and amountLabel:IsA("TextLabel") then
		local perTick = trainingIncomePerTick(profile)
		amountLabel.Text = string.format("+$%d/tick", perTick)
		amountLabel.TextTransparency = 0
		-- brief pulse so workers "feel" like they earn
		task.delay(0.35, function()
			if amountLabel.Parent then
				amountLabel.TextTransparency = 0.15
			end
		end)
	end
	-- Floating +$ popup on tick (cosmetic)
	local pop = Instance.new("BillboardGui")
	pop.Name = "WE_TrainCashPop"
	pop.Size = UDim2.fromOffset(100, 28)
	pop.StudsOffset = Vector3.new(0, 6, 0)
	pop.AlwaysOnTop = true
	pop.MaxDistance = 60
	pop.Parent = anchor
	local popLab = Instance.new("TextLabel")
	popLab.Size = UDim2.fromScale(1, 1)
	popLab.BackgroundTransparency = 1
	popLab.Font = Enum.Font.GothamBold
	popLab.TextScaled = true
	popLab.TextColor3 = Color3.fromRGB(100, 255, 140)
	popLab.TextStrokeTransparency = 0.35
	popLab.Text = string.format("+$%d", tickAmount)
	popLab.Parent = pop
	task.spawn(function()
		for i = 1, 8 do
			pop.StudsOffset = Vector3.new(0, 6 + i * 0.35, 0)
			popLab.TextTransparency = i / 10
			task.wait(0.06)
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
	AntiExploitService = deps.AntiExploitService
	MissionService = deps.MissionService
	TutorialService = deps.TutorialService

	local recruitRemote = RemoteSetup.Get(Constants.RemoteNames.RequestRecruitSoldiers) :: RemoteEvent
	recruitRemote.OnServerEvent:Connect(function(player: Player, amount: any)
		if not RateLimitService.Allow(player, "soldier_recruit", 2, 4) then
			if AntiExploitService and AntiExploitService.Strike then
				AntiExploitService.Strike(player, "soldier_recruit_rate")
			end
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
		if not RateLimitService.Allow(player, "soldier_dismiss", 2, 4) then
			if AntiExploitService and AntiExploitService.Strike then
				AntiExploitService.Strike(player, "soldier_dismiss_rate")
			end
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
