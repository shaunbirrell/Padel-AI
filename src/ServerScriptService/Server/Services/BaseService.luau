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
local StructureVisualConfig = require(Shared.Configs.StructureVisualConfig)
local EconomyConfig = require(Shared.Configs.EconomyConfig)
local DevConfig = require(Shared.Configs.DevConfig)
local Types = require(Shared.Types)

local RemoteGuard = require(script.Parent.Parent.Modules.RemoteGuard)

local BaseService = {}

local DataService: any = nil
local EconomyService: any = nil
local AnalyticsService: any = nil
local RateLimitService: any = nil
local RemoteSetup: any = nil
local TerritoryService: any = nil
local MissionService: any = nil
local TutorialService: any = nil
local NotificationService: any = nil

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
	if not RemoteGuard.IsIdString(structureId, 48) then
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

local function applyKitVisuals(plinth: BasePart, structureId: string, level: number)
	if not plinth or not plinth.Parent then
		return
	end
	local palette = StructureVisualConfig.Palettes[structureId]
	-- Missing palette / kit children is safe — plinth still scales
	local baseSize = plinth:GetAttribute("BaseSize")
	if typeof(baseSize) ~= "Vector3" then
		baseSize = Vector3.new(8, 1.2, 8)
		plinth:SetAttribute("BaseSize", baseSize)
	end
	local bs = baseSize :: Vector3
	local lv = math.clamp(level, 0, 5)
	local t = lv / 5
	local ghost = StructureVisualConfig.GhostTransparency
	local solid = StructureVisualConfig.SolidTransparency
	local transparency = if lv == 0 then ghost else solid

	-- Plinth grows slightly; kit body/roof scale with level
	plinth.Size = Vector3.new(bs.X, bs.Y * (1 + t * 0.35), bs.Z)
	if palette then
		plinth.Color = palette.Plinth
	else
		plinth.Color = Color3.fromRGB(40 + math.floor(t * 40), 60 + math.floor(t * 80), 50)
	end
	plinth.Transparency = transparency
	plinth.Material = Enum.Material.Concrete

	local bodyScale = 1 + lv * 0.55
	local accentScale = 1 + lv * 0.25

	for _, child in ipairs(plinth:GetChildren()) do
		if child:IsA("BasePart") then
			local role = child:GetAttribute("WE_KitRole")
			if role == "Body" then
				local bx = child:GetAttribute("WE_BaseSize")
				if typeof(bx) ~= "Vector3" then
					bx = child.Size
					child:SetAttribute("WE_BaseSize", bx)
				end
				local b = bx :: Vector3
				child.Size = Vector3.new(b.X * (0.9 + t * 0.15), b.Y * bodyScale, b.Z * (0.9 + t * 0.15))
				if palette then
					child.Color = palette.Body
				end
				child.Transparency = transparency
				child.Material = Enum.Material.Metal
			elseif role == "Accent" then
				local bx = child:GetAttribute("WE_BaseSize")
				if typeof(bx) ~= "Vector3" then
					bx = child.Size
					child:SetAttribute("WE_BaseSize", bx)
				end
				local b = bx :: Vector3
				child.Size = Vector3.new(b.X * accentScale, b.Y, b.Z * accentScale)
				if palette then
					child.Color = palette.Accent
				end
				-- Visual kits v2: less washout on ghost accents
				child.Transparency = if lv == 0 then 0.35 else 0.02
				child.Material = Enum.Material.Neon
			elseif role == "Roof" or role == "Antenna" then
				local bx = child:GetAttribute("WE_BaseSize")
				if typeof(bx) ~= "Vector3" then
					bx = child.Size
					child:SetAttribute("WE_BaseSize", bx)
				end
				local b = bx :: Vector3
				local yBoost = if role == "Antenna" then 1 + lv * 0.8 else 1 + lv * 0.4
				child.Size = Vector3.new(b.X, b.Y * yBoost, b.Z)
				-- Keep relative top position via attribute offset
				local off = child:GetAttribute("WE_LocalOffset")
				if typeof(off) == "Vector3" then
					local yExtra = if role == "Antenna" then lv * 0.9 else lv * 0.35
					child.CFrame = plinth.CFrame * CFrame.new((off :: Vector3) + Vector3.new(0, yExtra, 0))
				end
				if palette then
					child.Color = if role == "Antenna" then palette.Accent else palette.Roof
				end
				child.Transparency = transparency
				child.Material = if role == "Antenna" then Enum.Material.Neon else Enum.Material.Metal
			elseif role == "Detail" or role == "Pier" or role == "Door" or role == "Window" then
				child.Transparency = if lv == 0 then 0.4 else math.max(0, 0.2 - t * 0.2)
				if palette then
					child.Color = if role == "Window" then Color3.fromRGB(80, 120, 150) else palette.Accent
				end
				if role == "Window" then
					child.Material = Enum.Material.Glass
				elseif role == "Door" or role == "Pier" then
					child.Material = Enum.Material.Metal
				end
			end
		end
	end
end

function BaseService.UpdateVisuals(player: Player, structureId: string, level: number)
	local profile = DataService.GetProfile(player)
	if not profile or not profile.BasePlotId then
		return
	end
	local plotId = profile.BasePlotId

	for _, inst in ipairs(CollectionService:GetTagged(Constants.Tags.UpgradeSlot)) do
		if inst:IsA("BasePart") then
			local p = inst:GetAttribute("PlotId")
			local s = inst:GetAttribute("StructureId")
			if p == plotId and s == structureId then
				local okApply, errApply = pcall(applyKitVisuals, inst, structureId, level)
				if not okApply then
					warn("[BaseService] applyKitVisuals failed", structureId, errApply)
				end
			end
		end
	end
end

function BaseService.RefreshAllVisuals(player: Player)
	local profile = DataService.GetProfile(player)
	if not profile then
		return
	end
	-- Apply to every configured structure (missing kit slots safe; L0 = ghost)
	for structureId in pairs(BaseConfig.Structures) do
		local level = profile.BaseUpgrades[structureId] or 0
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
		NationColorId = profile.NationColorId,
		TrainingIncomePerTick = (function()
			local SoldierConfig = require(Shared.Configs.SoldierConfig)
			local cfg = SoldierConfig.TrainingIncome
			if not cfg then
				return 0
			end
			local count = tonumber(profile.Soldiers) or 0
			if count < (cfg.MinSoldiersForIncome or 1) then
				return 0
			end
			local prestigeMult = 1 + ((tonumber(profile.Prestige) or 0) * 0.05)
			return math.floor(count * (cfg.CashPerSoldierPerTick or 0) * prestigeMult)
		end)(),
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
	NotificationService = deps.NotificationService

	getUpgradeChangedEvent()

	local purchaseRemote = RemoteSetup.Get(Constants.RemoteNames.RequestPurchaseUpgrade) :: RemoteEvent
	purchaseRemote.OnServerEvent:Connect(function(player: Player, payload: any)
		if not RateLimitService.Allow(player, "purchase_upgrade", 6, 8) then
			if NotificationService then
				NotificationService.Notify(player, "Buying too fast — wait a moment", "Warn", 2.5)
			end
			return
		end
		local structureId = if typeof(payload) == "table" then payload.StructureId else payload
		local result = BaseService.PurchaseUpgrade(player, structureId)
		if not NotificationService then
			return
		end
		if result.Ok then
			local def = BaseConfig.Structures[structureId]
			local name = if def then def.DisplayName else tostring(structureId)
			NotificationService.Notify(
				player,
				string.format("%s → Lv %d", name, result.NewLevel or 0),
				"Success",
				3
			)
		else
			local err = result.Error or "Failed"
			local msg = if err == "InsufficientCash"
				then "Not enough cash"
				elseif err == "InsufficientGold"
				then "Not enough gold"
				elseif err == "MaxLevel"
				then "Already at MAX level"
				elseif err == "MissingRequirement"
				then "Missing prerequisite structure"
				elseif err == "UnknownStructure" or err == "InvalidStructure"
				then "Unknown structure"
				else ("Purchase failed: " .. tostring(err))
			NotificationService.Notify(player, msg, "Warn", 3.5)
		end
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
