--!strict
--[[
	Base plot assignment, upgrades, passive income, visual hooks.
]]

local Players = game:GetService("Players")
local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared.Constants)
local BaseConfig = require(Shared.Configs.BaseConfig)
local StructureVisualConfig = require(Shared.Configs.StructureVisualConfig)
local EconomyConfig = require(Shared.Configs.EconomyConfig)
local DevConfig = require(Shared.Configs.DevConfig)
local Types = require(Shared.Types)

local RemoteGuard = require(script.Parent.Parent.Modules.RemoteGuard)
local StructureKitBuilder = require(script.Parent.Parent.Modules.StructureKitBuilder)

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
local MonetizationService: any = nil

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
			pcall(function()
				StructureKitBuilder.ClearPlotExtras(plotId)
			end)
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


function BaseService.GetPlotSpawnCFrame(plotId: number): CFrame?
	local wantPlot = tonumber(plotId)
	for _, inst in ipairs(CollectionService:GetTagged(Constants.Tags.BasePlot)) do
		if inst:IsA("BasePart") and wantPlot ~= nil and tonumber(inst:GetAttribute("PlotId") :: any) == wantPlot then
			local folder = inst.Parent
			if folder then
				local spawn = folder:FindFirstChild("PlayerSpawn")
				if spawn and spawn:IsA("BasePart") then
					return spawn.CFrame + Vector3.new(0, 3, 0)
				end
			end
			return inst.CFrame + Vector3.new(0, 5, 55)
		end
	end
	local pos = BaseConfig.PlotPositions[plotId]
	if typeof(pos) == "Vector3" then
		return CFrame.new(pos + Vector3.new(0, 5, 55))
	end
	return nil
end

function BaseService.TeleportToPlot(player: Player)
	local profile = DataService.GetProfile(player)
	if not profile then
		return
	end
	-- Studio solo: never leave BasePlotId nil
	if profile.BasePlotId == nil then
		BaseService.AssignPlot(player)
		profile = DataService.GetProfile(player) or profile
		if profile.BasePlotId == nil then
			profile.BasePlotId = 1
		end
	end
	local cf = BaseService.GetPlotSpawnCFrame(profile.BasePlotId)
	if not cf then
		return
	end
	local function apply(character: Model)
		if character and character.Parent then
			character:PivotTo(cf)
			local hrp = character:FindFirstChild("HumanoidRootPart")
			if hrp and hrp:IsA("BasePart") then
				hrp.AssemblyLinearVelocity = Vector3.zero
				hrp.AssemblyAngularVelocity = Vector3.zero
			end
		end
	end
	local function applyWithRetries(character: Model)
		apply(character)
		-- Retry: CharacterAdded / physics settle can undo first PivotTo
		task.delay(0.35, function()
			if player.Character == character and character.Parent then
				apply(character)
			end
		end)
		task.delay(1.0, function()
			if player.Character == character and character.Parent then
				apply(character)
			end
		end)
	end
	if player.Character then
		applyWithRetries(player.Character)
	else
		local conn: RBXScriptConnection?
		conn = player.CharacterAdded:Connect(function(character)
			if conn then
				conn:Disconnect()
			end
			task.defer(function()
				applyWithRetries(character)
			end)
		end)
		task.delay(30, function()
			if conn then
				conn:Disconnect()
			end
		end)
	end
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

	-- v35: mid-game VIP soft offer on first structure L3+
	if targetLevel >= 3 and MonetizationService and MonetizationService.TrySoftOfferVIP then
		pcall(function()
			MonetizationService.TrySoftOfferVIP(player, "structure_l3")
		end)
	end

	getUpgradeChangedEvent():Fire(player.UserId, profile.BasePlotId, structureId, targetLevel)

	return {
		Ok = true,
		Error = nil,
		NewLevel = targetLevel,
		Cash = profile.Cash,
		Gold = profile.Gold,
	}
end

local function findUpgradeSlots(plotId: number, structureId: string): { BasePart }
	local found: { BasePart } = {}
	local seen: { [BasePart]: boolean } = {}
	local wantPlot = tonumber(plotId)
	for _, inst in ipairs(CollectionService:GetTagged(Constants.Tags.UpgradeSlot)) do
		if inst:IsA("BasePart") then
			local p = tonumber(inst:GetAttribute("PlotId") :: any)
			local s = inst:GetAttribute("StructureId")
			if wantPlot ~= nil and p == wantPlot and s == structureId then
				seen[inst] = true
				table.insert(found, inst)
			end
		end
	end
	-- Fallback: attribute scan under Bases (tags can lag / stale place files)
	if #found == 0 then
		local setup = Workspace:FindFirstChild("WarEmpireSetup")
		local bases = setup and setup:FindFirstChild("Bases")
		local plotFolder = bases and bases:FindFirstChild("Plot" .. tostring(plotId))
		if plotFolder then
			for _, desc in ipairs(plotFolder:GetDescendants()) do
				if desc:IsA("BasePart") and not seen[desc] then
					local dp = tonumber(desc:GetAttribute("PlotId") :: any)
					if desc:GetAttribute("StructureId") == structureId and wantPlot ~= nil and dp == wantPlot then
						CollectionService:AddTag(desc, Constants.Tags.UpgradeSlot)
						table.insert(found, desc)
					end
				end
			end
		end
	end
	return found
end

local showroomSpinConn: RBXScriptConnection? = nil

local function ensureShowroomSpin()
	if showroomSpinConn then
		return
	end
	local RunService = game:GetService("RunService")
	showroomSpinConn = RunService.Heartbeat:Connect(function(dt)
		for _, inst in ipairs(CollectionService:GetTagged("WE_UpgradeSlot")) do
			if inst:IsA("BasePart") then
				for _, child in ipairs(inst:GetChildren()) do
					if child:IsA("BasePart") and child:GetAttribute("WE_ShowroomSpin") == true and child.Transparency < 0.5 then
						child.CFrame = child.CFrame * CFrame.Angles(0, math.rad(22) * dt, 0)
					end
				end
			end
		end
	end)
end

local function syncUpgradePops(plinth: BasePart, structureId: string, lv: number)
	-- Clear prior pop folder
	local old = plinth:FindFirstChild("WE_UpgradePops")
	if old then
		old:Destroy()
	end
	if lv < 2 then
		return
	end
	local folder = Instance.new("Folder")
	folder.Name = "WE_UpgradePops"
	folder.Parent = plinth

	local function popPart(name: string, size: Vector3, offset: Vector3, color: Color3, material: Enum.Material, shape: Enum.PartType?): BasePart
		local p = Instance.new("Part")
		p.Name = name
		p.Size = size
		p.Anchored = true
		p.CanCollide = false
		p.CanTouch = false
		p.CanQuery = false
		p.Color = color
		p.Material = material
		if shape then
			p.Shape = shape
		end
		p.CFrame = plinth.CFrame * CFrame.new(offset)
		p.Parent = folder
		p:SetAttribute("WE_KitRole", name)
		return p
	end

	-- L2+: light + trim accent
	if lv >= 2 then
		popPart("UpgradeLight", Vector3.new(0.5, 0.5, 0.5), Vector3.new(2.6, 4.2, 2.2), Constants.Colors.GoldBright, Enum.Material.Neon, Enum.PartType.Ball)
		popPart("UpgradeTrim", Vector3.new(6.8, 0.14, 0.35), Vector3.new(0, 3.6, -2.7), Constants.Colors.GoldBright, Enum.Material.Neon, nil)
	end
	-- L4+: sandbag ring around plinth
	if lv >= 4 then
		local sand = Color3.fromRGB(130, 115, 80)
		for i = 0, 7 do
			local ang = (i / 8) * math.pi * 2
			local r = 5.2
			local ox = math.cos(ang) * r
			local oz = math.sin(ang) * r
			popPart("SandbagRing", Vector3.new(1.6, 0.9, 0.9), Vector3.new(ox, 0.7, oz), sand, Enum.Material.Sand, nil)
		end
	end
	-- L5: flag + floodlight
	if lv >= 5 then
		local pole = popPart("UpgradeFlag", Vector3.new(0.25, 7.5, 0.25), Vector3.new(-3.2, 4.2, 3.2), Color3.fromRGB(60, 60, 65), Enum.Material.Metal, nil)
		local cloth = popPart("UpgradeFlag", Vector3.new(2.4, 1.4, 0.12), Vector3.new(-2.0, 7.2, 3.2), Constants.Colors.GoldBright, Enum.Material.Fabric, nil)
		local flood = popPart("UpgradeFloodlight", Vector3.new(1.2, 0.4, 0.8), Vector3.new(3.0, 5.5, -2.5), Color3.fromRGB(220, 220, 200), Enum.Material.Metal, nil)
		local glow = Instance.new("PointLight")
		glow.Name = "FloodGlow"
		glow.Brightness = 2.2
		glow.Range = 28
		glow.Color = Color3.fromRGB(255, 245, 210)
		glow.Parent = flood
		pcall(function()
			local vas = require(script.Parent.VisualAssetService)
			if vas.TryAttachPropVisual then
				vas.TryAttachPropVisual(cloth, "Flag")
				vas.TryAttachPropVisual(flood, "Floodlight")
			end
		end)
	end
end

local function applyKitVisuals(plinth: BasePart, structureId: string, level: number)
	if not plinth or not plinth.Parent then
		return
	end
	-- Ensure Part-kit silhouette exists (spawn if bare plinth / stripped children)
	local okEnsure, ensureCountOrErr = pcall(StructureKitBuilder.EnsureKit, plinth, structureId)
	if not okEnsure then
		warn("[BaseService] EnsureKit failed", structureId, ensureCountOrErr)
	end

	local palette = StructureVisualConfig.Palettes[structureId]
	if palette == nil and (tonumber(level) or 0) >= 1 then
		warn("[BaseService] applyKitVisuals: profile level>=1 but no kit palette for", structureId)
	end
	local baseSize = plinth:GetAttribute("BaseSize")
	if typeof(baseSize) ~= "Vector3" then
		baseSize = Vector3.new(8, 1.2, 8)
		plinth:SetAttribute("BaseSize", baseSize)
	end
	local bs = baseSize :: Vector3
	-- v43: coerce DataStore/remote level; never let non-number leave kits at Transparency=1
	local lv = math.clamp(tonumber(level) or 0, 0, 5)
	local t = lv / 5
	-- L0 = nearly invisible placeholder; L1+ solid "built" structure (spawn-on-buy feel)
	local ghost = math.max(StructureVisualConfig.GhostTransparency, 0.72)
	local solid = StructureVisualConfig.SolidTransparency
	local transparency = if lv == 0 then ghost else solid

	plinth.Size = Vector3.new(bs.X, bs.Y * (1 + t * 0.35), bs.Z)
	if palette then
		plinth.Color = palette.Plinth
	else
		plinth.Color = Color3.fromRGB(40 + math.floor(t * 40), 60 + math.floor(t * 80), 50)
	end
	-- Plinth stays walkable; keep slightly visible at L0 so pads remain findable
	plinth.Transparency = if lv == 0 then math.min(ghost, 0.45) else solid
	plinth.Material = Enum.Material.Concrete

	-- v39: mild level scale (was 0.55/lv → L5 Body 3.75× buried underground)
	local bodyScale = 1 + lv * 0.12
	local accentScale = 1 + lv * 0.08

	local function placeKitPart(child: BasePart, newSize: Vector3, yExtra: number?)
		local bx = child:GetAttribute("WE_BaseSize")
		if typeof(bx) ~= "Vector3" then
			bx = child.Size
			child:SetAttribute("WE_BaseSize", bx)
		end
		local off = child:GetAttribute("WE_LocalOffset")
		if typeof(off) == "Vector3" then
			local o = off :: Vector3
			local b = bx :: Vector3
			-- Keep bottom at original base bottom so scale grows upward, not into the pad
			local bottom = o.Y - b.Y * 0.5
			local newOffY = bottom + newSize.Y * 0.5 + (yExtra or 0)
			child.Size = newSize
			child.CFrame = plinth.CFrame * CFrame.new(o.X, newOffY, o.Z)
		else
			child.Size = newSize
		end
	end

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
				local newSize = Vector3.new(b.X * (0.95 + t * 0.08), b.Y * bodyScale, b.Z * (0.95 + t * 0.08))
				placeKitPart(child, newSize, nil)
				if palette then
					child.Color = palette.Body
				end
				child.Transparency = transparency
				child.Material = Enum.Material.Metal
				child.CastShadow = lv > 0
			elseif role == "Accent" then
				local bx = child:GetAttribute("WE_BaseSize")
				if typeof(bx) ~= "Vector3" then
					bx = child.Size
					child:SetAttribute("WE_BaseSize", bx)
				end
				local b = bx :: Vector3
				placeKitPart(child, Vector3.new(b.X * accentScale, b.Y, b.Z * accentScale), nil)
				if palette then
					child.Color = palette.Accent
				end
				child.Transparency = if lv == 0 then 0.85 else 0.02
				child.Material = Enum.Material.Neon
			elseif role == "Roof" or role == "Antenna" then
				local bx = child:GetAttribute("WE_BaseSize")
				if typeof(bx) ~= "Vector3" then
					bx = child.Size
					child:SetAttribute("WE_BaseSize", bx)
				end
				local b = bx :: Vector3
				local yBoost = if role == "Antenna" then 1 + lv * 0.25 else 1 + lv * 0.1
				local yExtra = if role == "Antenna" then lv * 0.35 else lv * 0.12
				placeKitPart(child, Vector3.new(b.X, b.Y * yBoost, b.Z), yExtra)
				if palette then
					child.Color = if role == "Antenna" then palette.Accent else palette.Roof
				end
				child.Transparency = transparency
				child.Material = Enum.Material.Metal -- Design: reject neon antenna accents
			elseif role == "Crate" then
				-- Warehouse interior crates — were stuck Transparency=1 (unhandled role)
				local bx = child:GetAttribute("WE_BaseSize")
				if typeof(bx) ~= "Vector3" then
					bx = child.Size
					child:SetAttribute("WE_BaseSize", bx)
				end
				placeKitPart(child, bx :: Vector3, nil)
				child.Transparency = if lv == 0 then 1 else 0.05
				child.Material = Enum.Material.Wood
				child.CastShadow = lv > 0
			elseif role == "DressHost" then
				-- Tier 2 interior/prop hosts: gunmetal, no neon wash
				child.Transparency = if lv == 0 then 0.95 else 0.72
				child.Color = Color3.fromRGB(55, 60, 58)
				child.Material = Enum.Material.Metal
				if child:GetAttribute("WE_GunmetalDesk") or string.find(child.Name, "CommandDesk", 1, true) then
					child.Transparency = if lv == 0 then 0.9 else 0.05
					child.Color = Color3.fromRGB(55, 60, 58)
				end
			elseif role == "ParkedHeli" or role == "ParkedBoat" then
				-- v37: static parked presence — solid at L1+ (mesh may soften later)
				child.Transparency = if lv == 0 then 1 else 0.08
				child.Material = Enum.Material.Metal
				child.CastShadow = lv > 0
			elseif role == "Detail" or role == "Pier" or role == "Door" or role == "Window" then
				local bx = child:GetAttribute("WE_BaseSize")
				if typeof(bx) ~= "Vector3" then
					bx = child.Size
					child:SetAttribute("WE_BaseSize", bx)
				end
				placeKitPart(child, bx :: Vector3, nil)
				child.Transparency = if lv == 0 then 0.9 else math.max(0, 0.08 - t * 0.08)
				if palette then
					child.Color = if role == "Window" then Color3.fromRGB(80, 120, 150) else palette.Accent
				end
				if role == "Window" then
					child.Material = Enum.Material.Glass
				elseif role == "Door" or role == "Pier" then
					child.Material = Enum.Material.Metal
				end
				child.CastShadow = lv > 0
			elseif role == "Podium" or role == "PodiumRing" or role == "ShowroomMesh" then
				-- VehicleDepot showroom — visible once depot built
				child.Transparency = if lv == 0 then 1 else 0.05
				if role == "PodiumRing" then
					child.Color = Constants.Colors.GoldBright
					child.Material = Enum.Material.Neon
				elseif role == "Podium" then
					child.Color = Constants.Colors.PlateDark
				end
			elseif role == "UpgradeLight" or role == "UpgradeTrim" then
				child.Transparency = if lv >= 2 then 0.05 else 1
			elseif role == "SandbagRing" then
				child.Transparency = if lv >= 4 then 0.05 else 1
			elseif role == "UpgradeFlag" or role == "UpgradeFloodlight" then
				child.Transparency = if lv >= 5 then 0.05 else 1
			end
		end
	end

	-- Upgrade pop extras (idempotent Part kits; never required for gameplay)
	syncUpgradePops(plinth, structureId, lv)

	-- v43: assert Body exists + solid at L1+ BEFORE any mesh dress (visibility first)
	if lv >= 1 then
		local bodyPart: BasePart? = nil
		for _, child in ipairs(plinth:GetChildren()) do
			if child:IsA("BasePart") and child:GetAttribute("WE_KitRole") == "Body" then
				bodyPart = child
				if child.Transparency > 0.2 then
					child.Transparency = StructureVisualConfig.SolidTransparency
				end
				break
			end
		end
		if not bodyPart then
			warn("[BaseService] applyKitVisuals L1+ missing Body — re-EnsureKit", structureId)
			pcall(StructureKitBuilder.EnsureKit, plinth, structureId)
			for _, child in ipairs(plinth:GetChildren()) do
				if child:IsA("BasePart") and child:GetAttribute("WE_KitRole") ~= nil then
					local role = child:GetAttribute("WE_KitRole")
					if role == "Body" or role == "Roof" or role == "Accent" or role == "Antenna" then
						child.Transparency = StructureVisualConfig.SolidTransparency
					elseif role == "Detail" or role == "Door" or role == "Window" or role == "Pier" then
						child.Transparency = 0.05
					end
				end
			end
		end
	end

	-- Design P0: PreferMesh L1+ OPTIONAL dress on top — deferred so InsertService yield
	-- never blocks / races Part-kit solidify. Mesh failure must never skip EnsureKit path.
	local preferMesh = StructureVisualConfig.PreferMeshWhenAssetIdSet ~= false
	local meshMin = tonumber((StructureVisualConfig :: any).PreferMeshMinLevel) or 1
	if preferMesh and lv >= meshMin then
		local plinthRef = plinth
		local sid = structureId
		local levelRef = lv
		task.defer(function()
			if not plinthRef or not plinthRef.Parent then
				return
			end
			pcall(function()
				local vas = require(script.Parent.VisualAssetService)
				vas.TryAttachBuildingVisual(plinthRef, sid, levelRef)
				if sid == "VehicleDepot" and vas.TryAttachShowroomVisual then
					vas.TryAttachShowroomVisual(plinthRef)
				end
				if vas.TryDressStructureInterior then
					vas.TryDressStructureInterior(plinthRef, sid)
				end
				if vas.TryAttachParkedPresence then
					vas.TryAttachParkedPresence(plinthRef, sid, levelRef)
				end
			end)
			-- Re-assert Part kits visible after optional mesh (hideKitBody is no-op; belt+suspenders)
			if levelRef >= 1 and plinthRef.Parent then
				for _, child in ipairs(plinthRef:GetChildren()) do
					if child:IsA("BasePart") then
						local role = child:GetAttribute("WE_KitRole")
						if role == "Body" or role == "Roof" then
							if child.Transparency > 0.35 then
								child.Transparency = StructureVisualConfig.SolidTransparency
							end
						end
					end
				end
			end
		end)
	end

	-- L0 ghost → max: roof smoke plume at L5 (typed neon chimney)
	if lv >= 5 then
		local smokeHost = plinth:FindFirstChild("Roof")
		if smokeHost and smokeHost:IsA("BasePart") and not smokeHost:FindFirstChild("WE_MaxSmoke") then
			local emitter = Instance.new("ParticleEmitter")
			emitter.Name = "WE_MaxSmoke"
			emitter.Rate = 8
			emitter.Lifetime = NumberRange.new(1.2, 2.0)
			emitter.Speed = NumberRange.new(1.5, 3.0)
			emitter.SpreadAngle = Vector2.new(12, 12)
			emitter.Size = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 0.4),
				NumberSequenceKeypoint.new(1, 1.6),
			})
			emitter.Transparency = NumberSequence.new({
				NumberSequenceKeypoint.new(0, 0.4),
				NumberSequenceKeypoint.new(1, 1),
			})
			emitter.Color = ColorSequence.new(Color3.fromRGB(90, 95, 100))
			emitter.Parent = smokeHost
		end
	else
		local roof = plinth:FindFirstChild("Roof")
		if roof then
			local sm = roof:FindFirstChild("WE_MaxSmoke")
			if sm then
				sm:Destroy()
			end
		end
	end
end

function BaseService.UpdateVisuals(player: Player, structureId: string, level: number)
	ensureShowroomSpin()
	local profile = DataService.GetProfile(player)
	if not profile or not profile.BasePlotId then
		warn("[BaseService] UpdateVisuals skipped — no plot", player.Name, structureId)
		return
	end
	local plotId = profile.BasePlotId
	local slots = findUpgradeSlots(plotId, structureId)
	local lvNum = tonumber(level) or 0
	if #slots == 0 and lvNum >= 1 then
		warn("[BaseService] UpdateVisuals: NO SLOTS for lv>=1 — scanning ALL BaseParts under Plot", structureId, "plot", plotId)
		local setup = Workspace:FindFirstChild("WarEmpireSetup")
		local bases = setup and setup:FindFirstChild("Bases")
		local plotFolder = bases and bases:FindFirstChild("Plot" .. tostring(plotId))
		local want = tonumber(plotId)
		if plotFolder and want ~= nil then
			for _, desc in ipairs(plotFolder:GetDescendants()) do
				if desc:IsA("BasePart") and desc:GetAttribute("StructureId") == structureId then
					local dp = tonumber(desc:GetAttribute("PlotId") :: any)
					if dp == nil or dp == want then
						CollectionService:AddTag(desc, Constants.Tags.UpgradeSlot)
						table.insert(slots, desc)
					end
				end
			end
		end
		if #slots == 0 then
			warn("[BaseService] UpdateVisuals: STILL no slot after PlotN StructureId scan", structureId, "plot", plotId)
		end
	elseif #slots == 0 then
		warn("[BaseService] UpdateVisuals: no slot for", structureId, "plot", plotId)
	end
	for _, inst in ipairs(slots) do
		-- E) sync pad owned level from profile (clear stale MAX attrs)
		inst:SetAttribute("WE_OwnedLevel", lvNum)
		local okApply, errApply = pcall(applyKitVisuals, inst, structureId, level)
		if not okApply then
			warn("[BaseService] applyKitVisuals failed", structureId, errApply)
		end
	end

	-- Plot-scale fortifications (DefensiveWalls / Watchtowers / BaseCeiling) — walls on BUY only path
	if structureId == "DefensiveWalls" then
		local wallsLv = tonumber(level) or 0
		print("[BaseService] DefensiveWalls → SyncPerimeterWalls plot=", plotId, "level=", wallsLv)
		local okW, errW = pcall(StructureKitBuilder.SyncPerimeterWalls, plotId, wallsLv)
		if not okW then
			warn("[BaseService] SyncPerimeterWalls failed", errW)
		end
		-- Anti-heli Base Ceiling unlocks at DefensiveWalls ≥ L3
		local okC, errC = pcall(StructureKitBuilder.SyncBaseCeiling, plotId, level)
		if not okC then
			warn("[BaseService] SyncBaseCeiling failed", errC)
		end
	elseif structureId == "Watchtowers" then
		local okT, errT = pcall(StructureKitBuilder.SyncCornerTowers, plotId, level)
		if not okT then
			warn("[BaseService] SyncCornerTowers failed", errT)
		end
	end
end


--[[ v44 P0: destroy stale kits on owned plinths and rebuild solid Part kits from profile. ]]
function BaseService.NuclearRehydrateKits(player: Player)
	local profile = DataService.GetProfile(player)
	if not profile or not profile.BasePlotId then
		return
	end
	local plotId = profile.BasePlotId
	-- v45: iterate BaseConfig.Structures keys (not only BaseUpgrades pairs) so missing keys still get L0/L1 kits
	local seen: { [string]: boolean } = {}
	local function rehydrateOne(structureId: string, rawLevel: any)
		if seen[structureId] then
			return
		end
		seen[structureId] = true
		local lv = math.clamp(tonumber(rawLevel) or 0, 0, 5)
		if lv < 1 then
			return
		end
		if StructureVisualConfig.Palettes[structureId] == nil then
			warn("[BaseService] profile has level but no StructureVisualConfig.Palettes entry:", structureId, lv)
		end
		local slots = findUpgradeSlots(plotId, structureId)
		if #slots == 0 then
			warn("[BaseService] NuclearRehydrateKits: empty slots lv>=1 — PlotN StructureId scan", structureId, plotId)
			local setup = Workspace:FindFirstChild("WarEmpireSetup")
			local bases = setup and setup:FindFirstChild("Bases")
			local plotFolder = bases and bases:FindFirstChild("Plot" .. tostring(plotId))
			local want = tonumber(plotId)
			if plotFolder and want ~= nil then
				for _, desc in ipairs(plotFolder:GetDescendants()) do
					if desc:IsA("BasePart") and desc:GetAttribute("StructureId") == structureId then
						CollectionService:AddTag(desc, Constants.Tags.UpgradeSlot)
						table.insert(slots, desc)
					end
				end
			end
		end
		for _, plinth in ipairs(slots) do
			-- Destroy existing WE_KitRole children + catalog dress
			for _, ch in ipairs(plinth:GetChildren()) do
				if ch:IsA("BasePart") and ch:GetAttribute("WE_KitRole") ~= nil then
					ch:Destroy()
				elseif ch:IsA("Model") and (ch.Name == "WE_CatalogBuilding" or ch.Name == "WE_AirfieldComposite" or string.sub(ch.Name, 1, 14) == "WE_CatalogBuild") then
					ch:Destroy()
				end
			end
			plinth:SetAttribute("WE_KitGen", nil)
			plinth:SetAttribute("WE_CatalogAssetId", nil)
			plinth:SetAttribute("WE_BuildingDressGen", nil)
			plinth:SetAttribute("WE_OwnedLevel", lv)
			pcall(StructureKitBuilder.EnsureKit, plinth, structureId)
			pcall(applyKitVisuals, plinth, structureId, lv)
		end
	end
	for structureId in pairs(BaseConfig.Structures) do
		rehydrateOne(structureId, profile.BaseUpgrades[structureId])
	end
	for structureId, rawLevel in pairs(profile.BaseUpgrades) do
		rehydrateOne(structureId, rawLevel)
	end
end

function BaseService.RefreshAllVisuals(player: Player)
	local profile = DataService.GetProfile(player)
	if not profile then
		return
	end
	-- v43: perimeter FIRST (independent of upgrade-slot discovery)
	if profile.BasePlotId then
		local wallsLv = tonumber(profile.BaseUpgrades.DefensiveWalls) or 0
		pcall(StructureKitBuilder.SyncPerimeterWalls, profile.BasePlotId, wallsLv)
		pcall(StructureKitBuilder.SyncBaseCeiling, profile.BasePlotId, wallsLv)
		local towerLv = tonumber(profile.BaseUpgrades.Watchtowers) or 0
		pcall(StructureKitBuilder.SyncCornerTowers, profile.BasePlotId, towerLv)
	end
	-- Apply every structure from profile (L0 = faint placeholder; L1+ spawn/solid kit)
	for structureId in pairs(BaseConfig.Structures) do
		local level = tonumber(profile.BaseUpgrades[structureId]) or 0
		BaseService.UpdateVisuals(player, structureId, level)
	end
	-- DefensiveWalls / Watchtowers / BaseCeiling again after pads/kits (slot race heal)
	if profile.BasePlotId then
		local wallsLv = tonumber(profile.BaseUpgrades.DefensiveWalls) or 0
		pcall(StructureKitBuilder.SyncPerimeterWalls, profile.BasePlotId, wallsLv)
		pcall(StructureKitBuilder.SyncBaseCeiling, profile.BasePlotId, wallsLv)
		local towerLv = tonumber(profile.BaseUpgrades.Watchtowers) or 0
		pcall(StructureKitBuilder.SyncCornerTowers, profile.BasePlotId, towerLv)
	end
end

--[[ v45: after map heal/rebuild, re-apply kits/walls for every online player (race fix). ]]
function BaseService.RefreshAllOnlinePlayers()
	for _, plr in ipairs(Players:GetPlayers()) do
		pcall(function()
			pcall(BaseService.NuclearRehydrateKits, plr)
			BaseService.RefreshAllVisuals(plr)
		end)
	end
	print("[BaseService] RefreshAllOnlinePlayers done for", #Players:GetPlayers(), "players")
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
		PendingCash = tonumber((profile :: any).PendingCash) or 0,
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
	MonetizationService = deps.MonetizationService

	getUpgradeChangedEvent()

	local purchaseRemote = RemoteSetup.Get(Constants.RemoteNames.RequestPurchaseUpgrade) :: RemoteEvent
	purchaseRemote.OnServerEvent:Connect(function(player: Player, payload: any)
		if not RemoteGuard.RequireProfile(DataService, player) then
			print(string.format("[BaseService] Remote BUY no-profile %s", player.Name))
			return
		end
		if not RateLimitService.Allow(player, "purchase_upgrade", 6, 8) then
			print(string.format("[BaseService] Remote BUY rate-limit %s", player.Name))
			if NotificationService then
				NotificationService.Notify(player, "Buying too fast — wait a moment", "Warn", 2.5)
			end
			return
		end
		local structureId = if typeof(payload) == "table" then payload.StructureId else payload
		if not RemoteGuard.IsIdString(structureId, 48) then
			print(string.format("[BaseService] Remote BUY bad-id %s → %s", player.Name, tostring(structureId)))
			return
		end
		print(string.format("[BaseService] Remote BUY attempt %s → %s", player.Name, tostring(structureId)))
		local result = BaseService.PurchaseUpgrade(player, structureId)
		print(string.format("[BaseService] Remote BUY result %s → Ok=%s Err=%s", player.Name, tostring(result.Ok), tostring(result.Error)))
		if not NotificationService then
			warn("[BaseService] NotificationService nil — purchase toast skipped")
			return
		end
		if result.Ok then
			local def = BaseConfig.Structures[structureId]
			local name = if def then def.DisplayName else tostring(structureId)
			NotificationService.Notify(
				player,
				string.format("Purchase SUCCESSFUL! %s → Lv %d", name, result.NewLevel or 0),
				"Success",
				3.5
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
			-- Debounce can't-afford / fail spam from menu + pad
			local key = "basebuy|" .. err .. "|" .. tostring(structureId)
			if NotificationService.NotifyThrottled then
				NotificationService.NotifyThrottled(player, msg, "Warn", 3.5, 0.9, key)
			else
				NotificationService.Notify(player, msg, "Warn", 3.5)
			end
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
		-- ALWAYS teleport onto THEIR plot after character exists (retry inside TeleportToPlot)
		task.defer(function()
			BaseService.TeleportToPlot(player)
		end)
		task.delay(1.5, function()
			if player.Parent then
				BaseService.TeleportToPlot(player)
			end
		end)
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
		-- v45 P0: nuclear kit rebuild then RefreshAllVisuals at 0 / 0.5 / 2 / 5s (map-heal race)
		task.defer(function()
			pcall(BaseService.NuclearRehydrateKits, player)
			BaseService.RefreshAllVisuals(player)
		end)
		for _, delaySec in ipairs({ 0.5, 2.0, 5.0 }) do
			task.delay(delaySec, function()
				if player.Parent then
					pcall(BaseService.NuclearRehydrateKits, player)
					BaseService.RefreshAllVisuals(player)
				end
			end)
		end
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
						-- Accrue to Money Collector pending (not auto Cash)
						if EconomyService.AccruePendingCash then
							EconomyService.AccruePendingCash(player, amount, "passive")
						else
							EconomyService.AddCash(player, amount, "passive")
						end
					end
				end
			end
		end
	end)
end

return BaseService
