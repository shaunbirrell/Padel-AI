--!strict
--[[
	Near-plot oil pumpjacks outside DefensiveWalls (toward warzone / map origin).
	Income → PendingCash. Part kit + optional IndustrialPack dress.
	Does NOT touch OilRig Alpha/Bravo far POIs.

	v71 (HUD v70 spec §5): no neon IncomePad and no "+$/tick" card over each pump.
	F4 (owner's 11 features, lane W): no server "+$18" pop either. The owner's one "+$18 / every 5s" label is the
	client ProducerLabels module (EconomyConfig.ProducerLabels), so the server makes no BillboardGui per tick.
	F9 Golden Pumpjacks (MonetizationConfig.DevProducts.GoldenPumpjack, PlotOilPumpConfig.Golden): an owner's pumps
	are gold Metal with Reflectance (never a glowing material, no light); the catalog mesh clone is recoloured too
	(re-applied after the deferred prop attach). While the Id is live and the plot owner does not own it, ONE 7x7 gold
	pad (WE_PremiumPad, PremiumPadService prompts it) stands between the pumps, PadOffsetStuds toward the plot, with
	one stud-scaled "Golden Pump" label (MaxDistance LabelMaxDistance, never AlwaysOnTop, tagged
	WorldLabelConfig.BaseLabelTag for the client LabelGovernor). The re-sync on grant (MonetizationService) removes it.
]]

local Players = game:GetService("Players")
local CollectionService = game:GetService("CollectionService")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared.Constants)
local BaseConfig = require(Shared.Configs.BaseConfig)
local PlotOilPumpConfig = require(Shared.Configs.PlotOilPumpConfig)
local MonetizationConfig = require(Shared.Configs.MonetizationConfig)
local WorldLabel = require(Shared.Util.WorldLabel)
local PlotFrame = require(Shared.Util.PlotFrame)

local GOLDEN_KEY = "GoldenPumpjack" -- MonetizationConfig.DevProducts key and entitlement
local GOLD_PAD_TAG = (Constants.Tags and Constants.Tags.PremiumPad) or "WE_PremiumPad"
-- F9: the pump kit parts that take the gold Metal dress (the Pad keeps its Asphalt, gold coloured)
local GOLDEN_KIT_PARTS: { [string]: boolean } = { Derrick = true, WalkingBeam = true, HorseHead = true }
-- F9 (lane W assumption): the walk-over gold pad never sits in the main gate lane. Where the spec spot (lateral 0,
-- PadOffsetStuds toward the plot) is closer than this to the main gate centre (plot-local (0, PlotSize/2): plots 3
-- and 4, whose pumps flank the gate), the pad moves beside the outer pump instead, on the pump line, so an owner
-- walking out of the gate is never shown a Robux sheet. Candidate for PlotOilPumpConfig.Golden (lane Z, config-first).
local GOLD_PAD_GATE_CLEAR = 24
local GOLD_PAD_BESIDE_PUMP = 8.5 -- studs from a pump centre to the pad centre (pump pad half 4 + gap 1 + pad half 3.5)

local PlotOilPumpService = {}

local BaseService: any = nil
local DataService: any = nil
local EconomyService: any = nil
local VisualAssetService: any = nil
local MonetizationService: any = nil

local pumpsByPlot: { [number]: Folder } = {}
local accum = 0

local TAG = (Constants.Tags and Constants.Tags.PlotOilPump) or "WE_PlotOilPump"

local function findPlotFolder(plotId: number): Folder?
	local setup = Workspace:FindFirstChild("WarEmpireSetup")
	local bases = setup and setup:FindFirstChild("Bases")
	if not bases then
		return nil
	end
	local f = bases:FindFirstChild("Plot" .. tostring(plotId))
	if f and f:IsA("Folder") then
		return f
	end
	return nil
end

local function clearPlot(plotId: number)
	local f = pumpsByPlot[plotId]
	if f and f.Parent then
		f:Destroy()
	end
	pumpsByPlot[plotId] = nil
end

local function wallsLevelFor(player: Player): number
	if not DataService then
		return 0
	end
	local profile = DataService.GetProfile(player)
	if not profile or not profile.BaseUpgrades then
		return 0
	end
	return tonumber(profile.BaseUpgrades.DefensiveWalls) or 0
end

--[[ F9: gold dress (PlotOilPumpConfig.Golden). Kit parts Derrick / WalkingBeam / HorseHead: gold Metal + Reflectance;
	the Pad stays Asphalt with a gold colour; the catalog mesh clone (under the Derrick, VisualAssetService): every
	BasePart gold Metal, its MeshPart textures cleared, SurfaceAppearance / Texture / Decal removed. Idempotent;
	one pass over this pump model only (a few parts, on build / grant, never per frame). ]]
local function applyGoldenDress(model: Model)
	local g = PlotOilPumpConfig.Golden
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			if d.Parent == model and d.Name == "Pad" then
				d.Color = g.Color
			elseif d.Parent ~= model or GOLDEN_KIT_PARTS[d.Name] then
				d.Color = g.Color
				d.Material = g.Material
				d.Reflectance = g.Reflectance
				if d:IsA("MeshPart") then
					pcall(function()
						d.TextureID = ""
					end)
				end
			end
		elseif d:IsA("SurfaceAppearance") or d:IsA("Texture") or d:IsA("Decal") then
			d:Destroy()
		end
	end
	model:SetAttribute("WE_GoldenPump", true)
end

local function buildPumpKit(at: CFrame, parent: Instance, index: number): Model
	local model = Instance.new("Model")
	model.Name = "PlotOilPump_" .. tostring(index)

	local pad = Instance.new("Part")
	pad.Name = "Pad"
	pad.Size = Vector3.new(8, 0.6, 8)
	pad.CFrame = at
	pad.Anchored = true
	pad.CanCollide = true
	pad.Color = Color3.fromRGB(42, 44, 40)
	pad.Material = Enum.Material.Asphalt
	pad.Parent = model

	local tower = Instance.new("Part")
	tower.Name = "Derrick"
	tower.Size = Vector3.new(1.1, 14, 1.1)
	tower.CFrame = at * CFrame.new(0, 7.3, 0)
	tower.Anchored = true
	tower.CanCollide = false
	tower.Color = Color3.fromRGB(70, 72, 68)
	tower.Material = Enum.Material.Metal
	tower.Parent = model

	local beam = Instance.new("Part")
	beam.Name = "WalkingBeam"
	beam.Size = Vector3.new(10, 0.55, 0.55)
	beam.CFrame = at * CFrame.new(0, 14.2, 0)
	beam.Anchored = true
	beam.CanCollide = false
	beam.Color = Color3.fromRGB(90, 70, 50)
	beam.Material = Enum.Material.Metal
	beam:SetAttribute("WE_OilBeam", true)
	beam.Parent = model

	local head = Instance.new("Part")
	head.Name = "HorseHead"
	head.Size = Vector3.new(2.2, 1.4, 1.2)
	head.CFrame = at * CFrame.new(4.2, 13.6, 0)
	head.Anchored = true
	head.CanCollide = false
	head.Color = Color3.fromRGB(80, 60, 40)
	head.Material = Enum.Material.Metal
	head.Parent = model

	-- v71: no neon IncomePad and no "+$/tick" billboard (spec §5); the owner sees a "+$18" pop when nearby

	model.PrimaryPart = pad
	model.Parent = parent

	if VisualAssetService and VisualAssetService.TryAttachPropVisual then
		task.defer(function()
			pcall(function()
				VisualAssetService.TryAttachPropVisual(tower, PlotOilPumpConfig.VisualPropKey or "IndustrialPack")
			end)
			-- F9: the catalog clone arrives after SyncPlot dressed the kit: gold it too
			if model.Parent and model:GetAttribute("WE_GoldenPump") == true then
				applyGoldenDress(model)
			end
		end)
	end

	-- v35: pumpjack spectacle — walking beam + horse head bob together
	task.spawn(function()
		local t0 = os.clock()
		while model.Parent do
			local t = os.clock() - t0
			local ang = math.sin(t * 1.1) * 14 -- degrees
			if beam.Parent then
				beam.CFrame = at * CFrame.new(0, 14.2, 0) * CFrame.Angles(0, 0, math.rad(ang))
			end
			if head.Parent then
				-- Tip of beam (~4.2 studs along X) follows tilt
				local tip = CFrame.new(4.2, 0, 0)
				head.CFrame = at * CFrame.new(0, 14.2, 0) * CFrame.Angles(0, 0, math.rad(ang)) * tip * CFrame.new(0, -0.6, 0)
			end
			task.wait(0.08)
		end
	end)


	return model
end

function PlotOilPumpService.SyncPlot(plotId: number)
	if not PlotOilPumpConfig.Enabled then
		clearPlot(plotId)
		return
	end
	local ownerUserId = if BaseService and BaseService.GetOwnerUserId then BaseService.GetOwnerUserId(plotId) else nil
	if not ownerUserId then
		clearPlot(plotId)
		return
	end
	local owner = Players:GetPlayerByUserId(ownerUserId)
	local walls = if owner then wallsLevelFor(owner) else 0
	if walls < (PlotOilPumpConfig.MinWallsLevel or 2) then
		clearPlot(plotId)
		return
	end

	local plotFolder = findPlotFolder(plotId)
	if not plotFolder then
		return
	end

	clearPlot(plotId)
	local folder = Instance.new("Folder")
	folder.Name = PlotOilPumpConfig.FolderName or "WE_PlotOilPumps"
	folder:SetAttribute("PlotId", plotId)
	folder:SetAttribute("OwnerUserId", ownerUserId)
	folder.Parent = plotFolder
	pumpsByPlot[plotId] = folder

	local plotPos = BaseConfig.PlotPositions[plotId]
	if typeof(plotPos) ~= "Vector3" then
		return
	end
	local toward = Vector3.new(-plotPos.X, 0, -plotPos.Z)
	if toward.Magnitude < 0.05 then
		toward = Vector3.new(0, 0, -1)
	else
		toward = toward.Unit
	end
	local right = Vector3.new(-toward.Z, 0, toward.X)
	local half = (BaseConfig.PlotSize.X or 200) * 0.5
	-- `toward` is diagonal for the corner plots: step far enough along it to clear the square plot edge
	-- by WallClearanceStuds (measured square to the wall), not just half the plot size.
	local axis = math.max(math.abs(toward.X), math.abs(toward.Z), 0.5)
	local out = (half + (PlotOilPumpConfig.WallClearanceStuds or 18)) / axis
	local spread = PlotOilPumpConfig.LateralSpreadStuds or 22
	local count = math.clamp(PlotOilPumpConfig.PumpsPerPlot or 2, 1, 2)
	local hasGold = owner ~= nil
		and MonetizationService ~= nil
		and MonetizationService.PlayerOwnsEntitlement ~= nil
		and MonetizationService.PlayerOwnsEntitlement(owner, GOLDEN_KEY) == true

	for i = 1, count do
		local lat = if count == 1 then 0 elseif i == 1 then -spread * 0.5 else spread * 0.5
		local pos = (plotPos :: Vector3) + toward * out + right * lat + Vector3.new(0, 0.5, 0)
		local look = CFrame.lookAt(pos, pos + toward)
		local pump = buildPumpKit(look, folder, i)
		pump:SetAttribute("PlotId", plotId)
		pump:SetAttribute("OwnerUserId", ownerUserId)
		if hasGold then
			applyGoldenDress(pump)
		end
		pcall(function()
			CollectionService:AddTag(pump, TAG)
		end)
	end

	-- F9: the Golden Pump pad, only while the Id is live and the owner does not own it (nothing prompts at Id 0)
	local goldDef = (MonetizationConfig.DevProducts :: any)[GOLDEN_KEY]
	local goldLive = typeof(goldDef) == "table" and typeof(goldDef.Id) == "number" and goldDef.Id ~= 0
	if goldLive and not hasGold then
		local g = PlotOilPumpConfig.Golden
		local padPos = (plotPos :: Vector3) + toward * (out - (g.PadOffsetStuds or 10)) + Vector3.new(0, 0.3, 0)
		local gate = PlotFrame.LocalToWorld(plotId, 0, half)
		if Vector3.new(padPos.X - gate.X, 0, padPos.Z - gate.Z).Magnitude < GOLD_PAD_GATE_CLEAR then
			local lat = (if count == 1 then 0 else spread * 0.5) + GOLD_PAD_BESIDE_PUMP
			padPos = (plotPos :: Vector3) + toward * out + right * lat + Vector3.new(0, 0.3, 0)
		end
		local pad = Instance.new("Part")
		pad.Name = "PremiumPad_" .. GOLDEN_KEY
		pad.Size = Vector3.new(7, 0.45, 7)
		pad.CFrame = CFrame.lookAt(padPos, padPos + toward)
		pad.Anchored = true
		pad.CanCollide = true
		pad.Color = g.Color
		pad.Material = g.Material
		pad.Reflectance = g.Reflectance
		pad.TopSurface = Enum.SurfaceType.Smooth
		pad.BottomSurface = Enum.SurfaceType.Smooth
		pad:SetAttribute("PlotId", plotId)
		pad:SetAttribute("OfferKind", "DevProduct")
		pad:SetAttribute("OfferKey", GOLDEN_KEY)
		WorldLabel.Create(pad, "Golden Pump", {
			Name = "WE_PremiumBillboard", -- the Shop client's OWNED look finds the pad label by this name
			Sub = "R$",
			Color = g.Color,
			MaxDistance = g.LabelMaxDistance,
			Offset = Vector3.new(0, 5.5, 0),
			BaseLabel = true, -- WorldLabelConfig.BaseLabelTag: counted by the client LabelGovernor
		})
		CollectionService:AddTag(pad, GOLD_PAD_TAG) -- PremiumPadService attaches through its tag listener
		pad.Parent = folder
	end

	if RunService:IsStudio() then
		print(string.format("[PlotOilPump] plot=%d walls=%d pumps=%d", plotId, walls, count))
	end
end

--[[ v69: idempotent — syncs only when the plot's pumps do not match its owner / walls level (missing, other
	owner, walls under MinWallsLevel, or folder lost to a map rebuild). Safe to call on every plot-ready. ]]
function PlotOilPumpService.EnsurePlot(plotId: number)
	if not PlotOilPumpConfig.Enabled then
		return
	end
	local ownerUserId = if BaseService and BaseService.GetOwnerUserId then BaseService.GetOwnerUserId(plotId) else nil
	local owner = if ownerUserId then Players:GetPlayerByUserId(ownerUserId) else nil
	local want = owner ~= nil and wallsLevelFor(owner) >= (PlotOilPumpConfig.MinWallsLevel or 2)
	local folder: Folder? = pumpsByPlot[plotId]
	local inSync = if want
		then folder ~= nil and folder.Parent ~= nil and folder:GetAttribute("OwnerUserId") == ownerUserId
		else folder == nil
	if not inSync then
		PlotOilPumpService.SyncPlot(plotId)
	end
end

function PlotOilPumpService.Init(deps: { [string]: any })
	BaseService = deps.BaseService
	DataService = deps.DataService
	EconomyService = deps.EconomyService
	VisualAssetService = deps.VisualAssetService
	MonetizationService = deps.MonetizationService

	if not PlotOilPumpConfig.Enabled then
		return
	end

	if BaseService and BaseService.GetUpgradeChangedEvent then
		BaseService.GetUpgradeChangedEvent().Event:Connect(function(_userId: number, plotId: number?, structureId: string?, _level: number?)
			if structureId == "DefensiveWalls" and typeof(plotId) == "number" then
				task.defer(function()
					task.wait(0.2)
					PlotOilPumpService.SyncPlot(plotId :: number)
				end)
			end
		end)
	end

	-- v69: pumps follow the LOADED save whenever the owner's plot is (re)built — join (DataService v67 fires
	-- OnProfileLoaded only after the real save is read; BaseService then fires OnPlotReady), a freed plot handed
	-- out, prestige, map rebuild. Replaces the fixed 1.5 s / 4 s timers (missed a later save → no pumps all session).
	local hookedPlotReady = false
	if BaseService and BaseService.OnPlotReady then
		local okHook, errHook = pcall(BaseService.OnPlotReady, function(_player: Player, plotId: number)
			PlotOilPumpService.EnsurePlot(plotId)
		end)
		hookedPlotReady = okHook
		if not okHook then
			warn("[PlotOilPump] OnPlotReady hook failed:", errHook)
		end
	end
	if DataService and DataService.OnProfileLoaded then
		-- Belt: late ensure for the loaded owner's plot (no-op when already in sync); sole path if the hook failed
		DataService.OnProfileLoaded(function(player: Player, _profile: any)
			for _, delaySec in ipairs(if hookedPlotReady then { 10 } else { 1.5, 4, 10 }) do
				task.delay(delaySec, function()
					local plotId = if player.Parent and BaseService and BaseService.GetOwnedPlotId
						then BaseService.GetOwnedPlotId(player)
						else nil
					if typeof(plotId) == "number" then
						PlotOilPumpService.EnsurePlot(plotId)
					end
				end)
			end
		end)
	end

	Players.PlayerRemoving:Connect(function(player)
		for plotId, folder in pairs(pumpsByPlot) do
			if folder:GetAttribute("OwnerUserId") == player.UserId then
				clearPlot(plotId)
			end
		end
	end)

	local tickSec = PlotOilPumpConfig.TickSeconds or 5
	local cash = PlotOilPumpConfig.CashPerTick or 18
	local reason = PlotOilPumpConfig.Reason or "plot_oil"
	RunService.Heartbeat:Connect(function(dt)
		accum += dt
		if accum < tickSec then
			return
		end
		accum = 0
		if not EconomyService or not EconomyService.AccruePendingCash then
			return
		end
		for _, folder in pairs(pumpsByPlot) do
			if folder.Parent then
				local ownerId = folder:GetAttribute("OwnerUserId")
				if typeof(ownerId) == "number" then
					local owner = Players:GetPlayerByUserId(ownerId)
					if owner then
						local n = 0
						for _, ch in ipairs(folder:GetChildren()) do
							if ch:IsA("Model") and string.find(ch.Name, "PlotOilPump", 1, true) then
								n += 1
							end
						end
						if n > 0 then
							-- F4: the owner's "+$18 / every 5s" label is client-side (ProducerLabels); no server pop
							EconomyService.AccruePendingCash(owner, cash * n, reason)
						end
					end
				end
			end
		end
	end)

	print("[WAR EMPIRE] PlotOilPumpService ready (walls≥2 → near-plot pumps → PendingCash)")
end

return PlotOilPumpService
