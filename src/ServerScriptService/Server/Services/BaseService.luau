--!strict
--[[
	Base plot assignment, upgrades, passive income, visual hooks.
]]

local Players = game:GetService("Players")
local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared.Constants)
local BaseConfig = require(Shared.Configs.BaseConfig)
local EconomyConfig = require(Shared.Configs.EconomyConfig)
local DevConfig = require(Shared.Configs.DevConfig)
local Types = require(Shared.Types)

local BaseService = {}

local DataService: any = nil
local EconomyService: any = nil
local AnalyticsService: any = nil
local RateLimitService: any = nil
local RemoteSetup: any = nil
local TerritoryService: any = nil
local MissionService: any = nil
local TutorialService: any = nil

-- plotId -> userId
local plotOwners: { [number]: number } = {}
-- Bindable for Studio visuals
local upgradeChangedBindable: BindableEvent? = nil

local function getUpgradeChangedEvent(): BindableEvent
	if upgradeChangedBindable and upgradeChangedBindable.Parent then
		return upgradeChangedBindable
	end
	local folder = ReplicatedStorage:FindFirstChild("WarEmpireEvents")
	if not folder then
		folder = Instance.new("Folder")
		folder.Name = "WarEmpireEvents"
		folder.Parent = ReplicatedStorage
	end
	local ev = folder:FindFirstChild("BaseUpgradeChanged")
	if not ev then
		ev = Instance.new("BindableEvent")
		ev.Name = "BaseUpgradeChanged"
		ev.Parent = folder
	end
	upgradeChangedBindable = ev :: BindableEvent
	return upgradeChangedBindable
end

function BaseService.GetUpgradeChangedEvent(): BindableEvent
	return getUpgradeChangedEvent()
end

local function findFreePlot(): number?
	for plotId = 1, BaseConfig.MaxPlots do
		if plotOwners[plotId] == nil then
			return plotId
		end
	end
	return nil
end

function BaseService.AssignPlot(player: Player): number?
	local profile = DataService.GetProfile(player)
	if not profile then
		return nil
	end

	-- Reclaim previous if still free
	if profile.BasePlotId and plotOwners[profile.BasePlotId] == nil then
		plotOwners[profile.BasePlotId] = player.UserId
		return profile.BasePlotId
	end

	local plotId = findFreePlot()
	if not plotId then
		warn("[BaseService] No free plots for", player.Name)
		return nil
	end

	plotOwners[plotId] = player.UserId
	profile.BasePlotId = plotId
	DataService.MarkDirty(player)
	return plotId
end

function BaseService.ReleasePlot(player: Player)
	local userId = player.UserId
	for plotId, owner in pairs(plotOwners) do
		if owner == userId then
			plotOwners[plotId] = nil
		end
	end
end

function BaseService.GetOwnerUserId(plotId: number): number?
	return plotOwners[plotId]
end

function BaseService.ComputePassiveIncomePerTick(profile: Types.PlayerProfile, player: Player?): number
	local total = EconomyConfig.PassiveIncome.BaseCashPerTick
	local rates = EconomyConfig.PassiveIncome.PerLevelRates
	for structureId, level in pairs(profile.BaseUpgrades) do
		local rate = rates[structureId]
		if rate and level > 0 then
			total += rate * level
		end
	end
	local mult = 1 + (profile.Prestige * (EconomyConfig.PrestigeCashMultiplierPerLevel or 0))
	-- Territory ownership bonuses (Phase 5)
	if player and TerritoryService and TerritoryService.GetPassiveCashBonus then
		local bonusMult, flat = TerritoryService.GetPassiveCashBonus(player)
		mult += bonusMult
		total += flat
	end
	return math.floor(total * mult)
end

function BaseService.PushState(player: Player)
	local profile = DataService.GetProfile(player)
	if not profile then
		return
	end
	local remote = RemoteSetup.Get(Constants.RemoteNames.BaseStateUpdate) :: RemoteEvent
	local payload: Types.BaseStatePayload = {
		PlotId = profile.BasePlotId,
		Upgrades = profile.BaseUpgrades,
		PassiveIncomePerTick = BaseService.ComputePassiveIncomePerTick(profile, player),
	}
	remote:FireClient(player, payload)
end

local function meetsRequirements(profile: Types.PlayerProfile, structureId: string): (boolean, string?)
	local def = BaseConfig.Structures[structureId]
	if not def then
		return false, "UnknownStructure"
	end
	if def.Requires then
		for _, req in ipairs(def.Requires) do
			local have = profile.BaseUpgrades[req.StructureId] or 0
			if have < req.Level then
				return false, "MissingRequirement"
			end
		end
	end
	return true, nil
end

function BaseService.PurchaseUpgrade(player: Player, structureId: string): Types.PurchaseUpgradeResult
	if typeof(structureId) ~= "string" then
		return { Ok = false, Error = "InvalidStructure" }
	end

	local profile = DataService.GetProfile(player)
	if not profile then
		return { Ok = false, Error = "NoProfile" }
	end

	local def = BaseConfig.Structures[structureId]
	if not def then
		return { Ok = false, Error = "UnknownStructure" }
	end

	local current = profile.BaseUpgrades[structureId] or 0
	if current >= def.MaxLevel then
		return { Ok = false, Error = "MaxLevel" }
	end

	local okReq, reqErr = meetsRequirements(profile, structureId)
	if not okReq then
		return { Ok = false, Error = reqErr }
	end

	local targetLevel = current + 1
	local cost = def.Costs[targetLevel]
	if not cost then
		return { Ok = false, Error = "NoCost" }
	end

	local spendOk, spendErr
	if def.Currency == "Gold" then
		spendOk, spendErr = EconomyService.SpendGold(player, cost, "upgrade_" .. structureId)
	else
		spendOk, spendErr = EconomyService.SpendCash(player, cost, "upgrade_" .. structureId)
	end
	if not spendOk then
		return { Ok = false, Error = spendErr or "SpendFailed" }
	end

	profile.BaseUpgrades[structureId] = targetLevel
	profile.Stats.UpgradesPurchased += 1
	DataService.MarkDirty(player)

	local firstUpgrade = profile.Stats.UpgradesPurchased == 1
	if AnalyticsService then
		AnalyticsService.Log("UPGRADE_PURCHASED", player.UserId, {
			structure = structureId,
			level = targetLevel,
			cost = cost,
		})
		if firstUpgrade then
			AnalyticsService.Log("FIRST_UPGRADE", player.UserId, { structure = structureId })
		end
	end

	if MissionService and MissionService.TrackProgress then
		MissionService.TrackProgress(player, "PurchaseUpgrade", 1)
	end

	BaseService.PushState(player)
	BaseService.UpdateVisuals(player, structureId, targetLevel)

	getUpgradeChangedEvent():Fire(player.UserId, profile.BasePlotId, structureId, targetLevel)

	return {
		Ok = true,
		Error = nil,
		NewLevel = targetLevel,
		Cash = profile.Cash,
		Gold = profile.Gold,
	}
end

function BaseService.UpdateVisuals(player: Player, structureId: string, level: number)
	local profile = DataService.GetProfile(player)
	if not profile or not profile.BasePlotId then
		return
	end
	local plotId = profile.BasePlotId

	-- Find upgrade slot parts tagged WE_UpgradeSlot with attributes PlotId + StructureId
	for _, inst in ipairs(CollectionService:GetTagged(Constants.Tags.UpgradeSlot)) do
		if inst:IsA("BasePart") then
			local p = inst:GetAttribute("PlotId")
			local s = inst:GetAttribute("StructureId")
			if p == plotId and s == structureId then
				local baseSize = inst:GetAttribute("BaseSize")
				if typeof(baseSize) ~= "Vector3" then
					baseSize = Vector3.new(4, 1, 4)
					inst:SetAttribute("BaseSize", baseSize)
				end
				local heightScale = 1 + level * 0.6
				inst.Size = Vector3.new((baseSize :: Vector3).X, (baseSize :: Vector3).Y * heightScale, (baseSize :: Vector3).Z)
				-- Recolor by level
				local t = math.clamp(level / 5, 0, 1)
				inst.Color = Color3.fromRGB(
					math.floor(40 + t * 40),
					math.floor(60 + t * 100),
					math.floor(50 + t * 40)
				)
				inst.Transparency = if level == 0 then 0.5 else 0
			end
		end
	end
end

function BaseService.RefreshAllVisuals(player: Player)
	local profile = DataService.GetProfile(player)
	if not profile then
		return
	end
	for structureId, level in pairs(profile.BaseUpgrades) do
		BaseService.UpdateVisuals(player, structureId, level)
	end
end

local function buildPlayerState(player: Player): Types.PlayerStatePayload?
	local profile = DataService.GetProfile(player)
	if not profile then
		return nil
	end
	local LevelConfig = require(Shared.Configs.LevelConfig)
	return {
		Cash = profile.Cash,
		Gold = profile.Gold,
		Level = profile.Level,
		XP = profile.XP,
		XPToNext = LevelConfig.GetXPRequiredForLevel(profile.Level),
		Prestige = profile.Prestige,
		Soldiers = profile.Soldiers,
		Base = {
			PlotId = profile.BasePlotId,
			Upgrades = profile.BaseUpgrades,
			PassiveIncomePerTick = BaseService.ComputePassiveIncomePerTick(profile, player),
		},
		TutorialStep = profile.TutorialStep,
		TutorialComplete = profile.TutorialComplete,
		Vehicles = profile.Vehicles,
		Weapons = profile.Weapons,
		EquippedWeapon = profile.EquippedWeapon,
		DailyLogin = profile.DailyLogin,
		TerritoriesOwned = profile.Territories,
	}
end

function BaseService.GetPlayerState(player: Player): Types.PlayerStatePayload?
	return buildPlayerState(player)
end

function BaseService.Init(deps: { [string]: any })
	DataService = deps.DataService
	EconomyService = deps.EconomyService
	AnalyticsService = deps.AnalyticsService
	RateLimitService = deps.RateLimitService
	RemoteSetup = deps.RemoteSetup
	TerritoryService = deps.TerritoryService
	MissionService = deps.MissionService
	TutorialService = deps.TutorialService

	getUpgradeChangedEvent()

	local purchaseRemote = RemoteSetup.Get(Constants.RemoteNames.RequestPurchaseUpgrade) :: RemoteEvent
	purchaseRemote.OnServerEvent:Connect(function(player: Player, payload: any)
		if not RateLimitService.Allow(player, "purchase_upgrade", 4, 6) then
			return
		end
		local structureId = if typeof(payload) == "table" then payload.StructureId else payload
		BaseService.PurchaseUpgrade(player, structureId)
	end)

	local getStateFn = RemoteSetup.Get(Constants.RemoteNames.GetPlayerState) :: RemoteFunction
	getStateFn.OnServerInvoke = function(player: Player)
		if not RateLimitService.Allow(player, "get_state", 2, 4) then
			return nil
		end
		return buildPlayerState(player)
	end

	DataService.OnProfileLoaded(function(player: Player, _profile: Types.PlayerProfile)
		BaseService.AssignPlot(player)
		if TutorialService and TutorialService.Notify then
			TutorialService.Notify(player, "PlotAssigned")
		end
		BaseService.PushState(player)
		EconomyService.Push(player)
		if deps.XPService then
			deps.XPService.Push(player)
		end
		local stateRemote = RemoteSetup.Get(Constants.RemoteNames.PlayerStateUpdate) :: RemoteEvent
		local state = buildPlayerState(player)
		if state then
			stateRemote:FireClient(player, state)
		end
		task.defer(function()
			BaseService.RefreshAllVisuals(player)
		end)
		if AnalyticsService then
			AnalyticsService.Log("PLAYER_JOIN", player.UserId, { plot = _profile.BasePlotId })
		end
	end)

	Players.PlayerRemoving:Connect(function(player)
		if AnalyticsService then
			AnalyticsService.Log("PLAYER_LEAVE", player.UserId, {})
		end
		BaseService.ReleasePlot(player)
	end)

	-- Passive income loop
	task.spawn(function()
		local tickSeconds = EconomyConfig.PassiveIncome.TickSeconds
		if RunService:IsStudio() and DevConfig.FastPassiveIncome then
			tickSeconds = 1
		end
		while true do
			task.wait(tickSeconds)
			for _, player in ipairs(Players:GetPlayers()) do
				local profile = DataService.GetProfile(player)
				if profile then
					local amount = BaseService.ComputePassiveIncomePerTick(profile, player)
					if amount > 0 then
						EconomyService.AddCash(player, amount, "passive")
					end
				end
			end
		end
	end)
end

return BaseService
