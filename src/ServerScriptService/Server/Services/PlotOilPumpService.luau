--!strict
--[[
	Near-plot oil pumpjacks outside DefensiveWalls (toward warzone / map origin).
	Income → PendingCash. Part kit + optional IndustrialPack dress.
	Does NOT touch OilRig Alpha/Bravo far POIs.
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

	local income = Instance.new("Part")
	income.Name = "IncomePad"
	income.Size = Vector3.new(4, 0.4, 4)
	income.CFrame = at * CFrame.new(0, 0.5, 4.5)
	income.Anchored = true
	income.CanCollide = false
	income.Color = Color3.fromRGB(40, 90, 50)
	income.Material = Enum.Material.Neon
	income.Transparency = 0.35
	income.Parent = model

	local bb = Instance.new("BillboardGui")
	bb.Name = "OilIncomeBillboard"
	bb.Size = UDim2.fromOffset(90, 28)
	bb.StudsOffset = Vector3.new(0, 3.2, 0)
	bb.AlwaysOnTop = false
	bb.MaxDistance = PlotOilPumpConfig.BillboardMaxDistance or 80
	bb.Parent = income
	local lbl = Instance.new("TextLabel")
	lbl.Name = "Label"
	lbl.Size = UDim2.fromScale(1, 1)
	lbl.BackgroundColor3 = Color3.fromRGB(20, 40, 25)
	lbl.BackgroundTransparency = 0.25
	lbl.Text = "+$" .. tostring(PlotOilPumpConfig.CashPerTick or 18) .. "/tick"
	lbl.TextColor3 = Color3.fromRGB(120, 255, 140)
	lbl.TextScaled = true
	lbl.Font = Enum.Font.GothamBold
	lbl.Parent = bb
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 4)
	corner.Parent = lbl

	model.PrimaryPart = pad
	model.Parent = parent

	if VisualAssetService and VisualAssetService.TryAttachPropVisual then
		task.defer(function()
			pcall(function()
				VisualAssetService.TryAttachPropVisual(tower, PlotOilPumpConfig.VisualPropKey or "IndustrialPack")
			end)
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

local function applyGoldenDress(model: Model)
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BasePart") then
			if d.Name == "Pad" or d.Name == "Derrick" or d.Name == "WalkingBeam" or d.Name == "HorseHead" then
				d.Color = Color3.fromRGB(255, 195, 60)
				d.Material = Enum.Material.Neon
			elseif d.Name == "IncomePad" then
				d.Color = Color3.fromRGB(255, 210, 80)
			end
		elseif d:IsA("TextLabel") and d.Name == "Label" then
			d.TextColor3 = Color3.fromRGB(255, 230, 120)
			d.BackgroundColor3 = Color3.fromRGB(60, 45, 10)
		end
	end
	model:SetAttribute("WE_GoldenPump", true)
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
	local out = half + (PlotOilPumpConfig.WallClearanceStuds or 18)
	local spread = PlotOilPumpConfig.LateralSpreadStuds or 22
	local count = math.clamp(PlotOilPumpConfig.PumpsPerPlot or 2, 1, 2)

	for i = 1, count do
		local lat = if count == 1 then 0 elseif i == 1 then -spread * 0.5 else spread * 0.5
		local pos = (plotPos :: Vector3) + toward * out + right * lat + Vector3.new(0, 0.5, 0)
		local look = CFrame.lookAt(pos, pos + toward)
		local pump = buildPumpKit(look, folder, i)
		pump:SetAttribute("PlotId", plotId)
		pump:SetAttribute("OwnerUserId", ownerUserId)
		local hasGold = owner
			and MonetizationService
			and MonetizationService.PlayerOwnsEntitlement
			and MonetizationService.PlayerOwnsEntitlement(owner, "GoldenPumpjack")
		if hasGold then
			applyGoldenDress(pump)
		end
		pcall(function()
			CollectionService:AddTag(pump, TAG)
		end)
	end

	if RunService:IsStudio() then
		print(string.format("[PlotOilPump] plot=%d walls=%d pumps=%d", plotId, walls, count))
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

	if DataService and DataService.OnProfileLoaded then
		DataService.OnProfileLoaded(function(player: Player, profile: any)
			task.defer(function()
				task.wait(1.5)
				if player.Parent and profile and typeof(profile.BasePlotId) == "number" then
					PlotOilPumpService.SyncPlot(profile.BasePlotId)
				end
			end)
			task.delay(4, function()
				if player.Parent and profile and typeof(profile.BasePlotId) == "number" then
					PlotOilPumpService.SyncPlot(profile.BasePlotId)
				end
			end)
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
							EconomyService.AccruePendingCash(owner, cash * n, reason)
							-- Floating +$/tick pops on each pump (competitor video feel)
							for _, ch in ipairs(folder:GetChildren()) do
								if ch:IsA("Model") and string.find(ch.Name, "PlotOilPump", 1, true) then
									local incomePad = ch:FindFirstChild("IncomePad")
									local anchor = if incomePad and incomePad:IsA("BasePart") then incomePad else ch.PrimaryPart
									if anchor and anchor:IsA("BasePart") then
										local pop = Instance.new("BillboardGui")
										pop.Name = "WE_OilCashPop"
										pop.Size = UDim2.fromOffset(90, 26)
										pop.StudsOffset = Vector3.new(0, 4.5, 0)
										pop.AlwaysOnTop = false
										pop.MaxDistance = 28
										pop.Parent = anchor
										local popLab = Instance.new("TextLabel")
										popLab.Size = UDim2.fromScale(1, 1)
										popLab.BackgroundTransparency = 1
										popLab.Font = Enum.Font.GothamBold
										popLab.TextScaled = true
										popLab.TextColor3 = Color3.fromRGB(100, 255, 140)
										popLab.TextStrokeTransparency = 0.35
										popLab.Text = string.format("+$%d", cash)
										popLab.Parent = pop
										task.spawn(function()
											for i = 1, 6 do
												pop.StudsOffset = Vector3.new(0, 4.5 + i * 0.35, 0)
												popLab.TextTransparency = i / 7
												task.wait(0.1)
											end
											pop:Destroy()
										end)
									end
								end
							end
						end
					end
				end
			end
		end
	end)

	print("[WAR EMPIRE] PlotOilPumpService ready (walls≥2 → near-plot pumps → PendingCash)")
end

return PlotOilPumpService
