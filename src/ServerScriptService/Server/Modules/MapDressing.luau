--!strict
--[[
	WAR EMPIRE — MapDressing (world visual substance)
	Fills the expanded ~4800 map between plots / ring / territories with
	military Part-kit clusters (desert outposts, adobe, tents, hangars, depots, camps…).
	Visual / immersion only — no gameplay tags that affect buy pads or capture.
	Called from MapSetup.Run after bases/territories/spawns (deferred).
	Quality Low (~60–70% fewer clusters) vs Full. Studio usually SKIPS entirely
	(DevConfig.StudioSkipWorldDressing) — ForceDress attribute to opt in.
	Regenerate: delete WarEmpireSetup + Play, or admin resetmap.
]]

local MapDressing = {}

-- v70: plots are 320 wide now (BaseLayoutConfig.PlotSize); plot-ring props must stay outside the base footprint
local PLOT_SIZE: number = (function(): number
	local ok, cfg = pcall(function()
		return require(game:GetService("ReplicatedStorage").Shared.Configs.BaseLayoutConfig) :: any
	end)
	return if ok and type(cfg) == "table" and type(cfg.PlotSize) == "number" then cfg.PlotSize else 320
end)()

-- Palette aligned with StructureVisualConfig / MapSetup (Concrete / Metal / Neon)
local COL = {
	Concrete = Color3.fromRGB(85, 85, 78),
	ConcreteDark = Color3.fromRGB(60, 60, 55),
	Metal = Color3.fromRGB(58, 72, 88),
	MetalDark = Color3.fromRGB(45, 50, 55),
	Olive = Color3.fromRGB(70, 78, 55),
	OliveDark = Color3.fromRGB(50, 55, 42),
	Sand = Color3.fromRGB(150, 130, 90),
	Sandbag = Color3.fromRGB(130, 115, 80),
	Rust = Color3.fromRGB(120, 70, 45),
	Fuel = Color3.fromRGB(180, 140, 50),
	Ammo = Color3.fromRGB(88, 58, 50),
	NeonGold = Color3.fromRGB(230, 190, 60),
	NeonBlue = Color3.fromRGB(90, 160, 220),
	NeonCyan = Color3.fromRGB(70, 180, 220),
	NeonGreen = Color3.fromRGB(90, 160, 80),
	NeonOrange = Color3.fromRGB(220, 140, 60),
	NeonRed = Color3.fromRGB(200, 90, 70),
	Asphalt = Color3.fromRGB(48, 50, 46),
	Wood = Color3.fromRGB(95, 75, 50),
	Wire = Color3.fromRGB(100, 105, 95),
	Crate = Color3.fromRGB(95, 80, 55),
	Drum = Color3.fromRGB(70, 85, 55),
	DrumAccent = Color3.fromRGB(200, 90, 50),
	Vehicle = Color3.fromRGB(55, 65, 48),
	VehicleAccent = Color3.fromRGB(90, 140, 70),
	Ruin = Color3.fromRGB(95, 90, 75),
	Light = Color3.fromRGB(255, 230, 160),
	Sign = Color3.fromRGB(50, 55, 45),
	SignFace = Color3.fromRGB(200, 180, 80),
	Tent = Color3.fromRGB(195, 175, 130),
	TentDark = Color3.fromRGB(160, 140, 100),
	TentPole = Color3.fromRGB(90, 70, 45),
	Adobe = Color3.fromRGB(185, 150, 105),
	AdobeDark = Color3.fromRGB(155, 120, 80),
	AdobeWindow = Color3.fromRGB(70, 110, 130),
	WoodTower = Color3.fromRGB(110, 85, 55),
	WoodDark = Color3.fromRGB(85, 65, 42),
	FlagCloth = Color3.fromRGB(200, 70, 55),
	CampfireStone = Color3.fromRGB(110, 105, 95),
	CampfireGlow = Color3.fromRGB(255, 140, 50),
	Dock = Color3.fromRGB(50, 75, 95),
}

local function ensureFolder(name: string, parent: Instance): Folder
	local existing = parent:FindFirstChild(name)
	if existing then
		existing:Destroy()
	end
	local f = Instance.new("Folder")
	f.Name = name
	f.Parent = parent
	return f
end

local function p(props: { [string]: any }): Part
	local part = Instance.new("Part")
	part.Anchored = true
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.CanCollide = if props.CanCollide ~= nil then props.CanCollide else false
	part.CanQuery = if props.CanQuery ~= nil then props.CanQuery else false
	part.CanTouch = false
	part.CastShadow = if props.CastShadow ~= nil then props.CastShadow else false
	if props.Name then
		part.Name = props.Name
	end
	if props.Size then
		part.Size = props.Size
	end
	if props.CFrame then
		part.CFrame = props.CFrame
	elseif props.Position then
		part.Position = props.Position
	end
	if props.Color then
		part.Color = props.Color
	end
	if props.Material then
		part.Material = props.Material
	end
	if props.Transparency then
		part.Transparency = props.Transparency
	end
	if props.Shape then
		part.Shape = props.Shape
	end
	if props.Parent then
		part.Parent = props.Parent
	end
	part:SetAttribute("WE_Decor", true)
	part:SetAttribute("WE_MapDress", true)
	return part
end

local function at(origin: Vector3, ox: number, oy: number, oz: number): Vector3
	return origin + Vector3.new(ox, oy, oz)
end


-- ── Kit builders (modest part counts) ─────────────────────────────────────

local function kitWatchtower(folder: Folder, origin: Vector3, yawDeg: number)
	-- Wooden desert watchtower + simple flag (original Part kit)
	local cf = CFrame.new(origin) * CFrame.Angles(0, math.rad(yawDeg), 0)
	-- Four legs
	for _, ox in ipairs({ -2.2, 2.2 }) do
		for _, oz in ipairs({ -2.2, 2.2 }) do
			p({
				Name = "TowerLeg",
				Size = Vector3.new(0.7, 16, 0.7),
				CFrame = cf * CFrame.new(ox, 8, oz),
				Color = COL.WoodTower,
				Material = Enum.Material.Wood,
				CanCollide = true,
				CanQuery = true,
				Parent = folder,
			})
		end
	end
	-- Cross braces
	p({
		Name = "TowerBrace",
		Size = Vector3.new(5.2, 0.35, 0.35),
		CFrame = cf * CFrame.new(0, 6, 0),
		Color = COL.WoodDark,
		Material = Enum.Material.Wood,
		Parent = folder,
	})
	p({
		Name = "TowerBrace2",
		Size = Vector3.new(0.35, 0.35, 5.2),
		CFrame = cf * CFrame.new(0, 10, 0),
		Color = COL.WoodDark,
		Material = Enum.Material.Wood,
		Parent = folder,
	})
	p({
		Name = "TowerCabin",
		Size = Vector3.new(6.5, 3.4, 6.5),
		CFrame = cf * CFrame.new(0, 16.5, 0),
		Color = COL.Adobe,
		Material = Enum.Material.Wood,
		CanCollide = true,
		CanQuery = true,
		Parent = folder,
	})
	p({
		Name = "TowerRoof",
		Size = Vector3.new(7.5, 0.55, 7.5),
		CFrame = cf * CFrame.new(0, 18.4, 0),
		Color = COL.WoodDark,
		Material = Enum.Material.Wood,
		Parent = folder,
	})
	p({
		Name = "TowerWindow",
		Size = Vector3.new(1.4, 1.1, 0.25),
		CFrame = cf * CFrame.new(0, 16.6, -3.3),
		Color = COL.AdobeWindow,
		Material = Enum.Material.Glass,
		Parent = folder,
	})
	-- Flag pole + cloth
	p({
		Name = "FlagPole",
		Size = Vector3.new(0.25, 7, 0.25),
		CFrame = cf * CFrame.new(2.8, 22, 2.8),
		Color = COL.MetalDark,
		Material = Enum.Material.Metal,
		Parent = folder,
	})
	p({
		Name = "FlagCloth",
		Size = Vector3.new(2.8, 1.6, 0.12),
		CFrame = cf * CFrame.new(4.2, 24.2, 2.8),
		Color = COL.FlagCloth,
		Material = Enum.Material.Fabric,
		Parent = folder,
	})
	p({
		Name = "TowerAccent",
		Size = Vector3.new(6.7, 0.22, 6.7),
		CFrame = cf * CFrame.new(0, 14.9, 0),
		Color = COL.NeonGold,
		Material = Enum.Material.Neon,
		Parent = folder,
	})
end

local function kitBunker(folder: Folder, origin: Vector3, yawDeg: number)
	local cf = CFrame.new(origin) * CFrame.Angles(0, math.rad(yawDeg), 0)
	p({
		Name = "BunkerBody",
		Size = Vector3.new(14, 5, 10),
		CFrame = cf * CFrame.new(0, 2.5, 0),
		Color = COL.Concrete,
		Material = Enum.Material.Concrete,
		CanCollide = true,
		CanQuery = true,
		Parent = folder,
	})
	p({
		Name = "BunkerRoof",
		Size = Vector3.new(15.5, 1.2, 11.5),
		CFrame = cf * CFrame.new(0, 5.6, 0),
		Color = COL.ConcreteDark,
		Material = Enum.Material.Concrete,
		CanCollide = true,
		CanQuery = true,
		Parent = folder,
	})
	p({
		Name = "BunkerDoor",
		Size = Vector3.new(2.4, 3.2, 0.4),
		CFrame = cf * CFrame.new(0, 1.8, -5.1),
		Color = COL.MetalDark,
		Material = Enum.Material.Metal,
		Parent = folder,
	})
	p({
		Name = "BunkerSlit",
		Size = Vector3.new(4, 0.6, 0.35),
		CFrame = cf * CFrame.new(0, 3.8, -5.15),
		Color = COL.NeonGreen,
		Material = Enum.Material.Neon,
		Parent = folder,
	})
	p({
		Name = "BunkerAccent",
		Size = Vector3.new(14.5, 0.2, 0.35),
		CFrame = cf * CFrame.new(0, 5.1, -5.4),
		Color = COL.NeonGold,
		Material = Enum.Material.Neon,
		Parent = folder,
	})
end

local function kitHangar(folder: Folder, origin: Vector3, yawDeg: number)
	local cf = CFrame.new(origin) * CFrame.Angles(0, math.rad(yawDeg), 0)
	local hangarPad = p({
		Name = "HangarPad",
		Size = Vector3.new(28, 0.6, 22),
		CFrame = cf * CFrame.new(0, 0.3, 0),
		Color = COL.Asphalt,
		Material = Enum.Material.Asphalt,
		CanCollide = true,
		CanQuery = true,
		Parent = folder,
	})
	p({
		Name = "HangarBody",
		Size = Vector3.new(24, 10, 18),
		CFrame = cf * CFrame.new(0, 5.3, 0),
		Color = COL.Metal,
		Material = Enum.Material.Metal,
		CanCollide = true,
		CanQuery = true,
		Parent = folder,
	})
	p({
		Name = "HangarRoof",
		Size = Vector3.new(26, 1, 20),
		CFrame = cf * CFrame.new(0, 10.8, 0),
		Color = COL.MetalDark,
		Material = Enum.Material.Metal,
		Parent = folder,
	})
	p({
		Name = "HangarDoor",
		Size = Vector3.new(16, 8, 0.5),
		CFrame = cf * CFrame.new(0, 4.2, -9.1),
		Color = COL.MetalDark,
		Material = Enum.Material.Metal,
		Parent = folder,
	})
	p({
		Name = "HangarAccent",
		Size = Vector3.new(16.5, 0.3, 0.4),
		CFrame = cf * CFrame.new(0, 8.5, -9.2),
		Color = COL.NeonBlue,
		Material = Enum.Material.Neon,
		Parent = folder,
	})
	-- Optional free Hangar catalog overlay (skipped when StudioSkipWorldDressing)
	pcall(function()
		local vas = require(script.Parent.Parent.Services.VisualAssetService)
		if hangarPad and hangarPad:IsA("BasePart") then
			vas.TryAttachBuildingVisual(hangarPad, "Hangar")
		end
	end)
end

local function kitFuelDepot(folder: Folder, origin: Vector3, yawDeg: number)
	local cf = CFrame.new(origin) * CFrame.Angles(0, math.rad(yawDeg), 0)
	p({
		Name = "FuelPad",
		Size = Vector3.new(16, 0.5, 12),
		CFrame = cf * CFrame.new(0, 0.25, 0),
		Color = COL.ConcreteDark,
		Material = Enum.Material.Concrete,
		CanCollide = true,
		CanQuery = true,
		Parent = folder,
	})
	for i, ox in ipairs({ -4.5, 0, 4.5 }) do
		p({
			Name = "FuelTank" .. i,
			Size = Vector3.new(7, 3.6, 3.6),
			-- Cylinder default axis is +X; rotate so tanks stand upright
			CFrame = cf * CFrame.new(ox, 3.8, 0) * CFrame.Angles(0, 0, math.rad(90)),
			Color = COL.Fuel,
			Material = Enum.Material.Metal,
			Shape = Enum.PartType.Cylinder,
			CanCollide = true,
			CanQuery = true,
			Parent = folder,
		})
	end
	p({
		Name = "FuelShed",
		Size = Vector3.new(5, 4, 5),
		CFrame = cf * CFrame.new(0, 2.2, 5.5),
		Color = COL.OliveDark,
		Material = Enum.Material.Metal,
		CanCollide = true,
		CanQuery = true,
		Parent = folder,
	})
	p({
		Name = "FuelAccent",
		Size = Vector3.new(15, 0.2, 0.3),
		CFrame = cf * CFrame.new(0, 0.6, -5.5),
		Color = COL.NeonOrange,
		Material = Enum.Material.Neon,
		Parent = folder,
	})
	-- Mesh dress ON Part-kit cluster only (PreferMesh stays OFF for gameplay structures)
	local fuelHost = p({
		Name = "FuelDressHost",
		Size = Vector3.new(4, 2, 4),
		CFrame = cf * CFrame.new(0, 2, 0),
		Transparency = 1,
		CanCollide = false,
		Parent = folder,
	})
	pcall(function()
		local vas = require(script.Parent.Parent.Services.VisualAssetService)
		if vas and vas.TryAttachPropVisual then
			vas.TryAttachPropVisual(fuelHost, "FuelTanks")
		end
	end)
end

local function kitAmmoShed(folder: Folder, origin: Vector3, yawDeg: number)
	local cf = CFrame.new(origin) * CFrame.Angles(0, math.rad(yawDeg), 0)
	p({
		Name = "AmmoBody",
		Size = Vector3.new(10, 5, 8),
		CFrame = cf * CFrame.new(0, 2.7, 0),
		Color = COL.Ammo,
		Material = Enum.Material.Metal,
		CanCollide = true,
		CanQuery = true,
		Parent = folder,
	})
	p({
		Name = "AmmoRoof",
		Size = Vector3.new(11, 0.6, 9),
		CFrame = cf * CFrame.new(0, 5.5, 0),
		Color = COL.ConcreteDark,
		Material = Enum.Material.Metal,
		Parent = folder,
	})
	p({
		Name = "AmmoDoor",
		Size = Vector3.new(2.2, 3, 0.35),
		CFrame = cf * CFrame.new(0, 1.7, -4.1),
		Color = COL.MetalDark,
		Material = Enum.Material.Metal,
		Parent = folder,
	})
	p({
		Name = "AmmoAccent",
		Size = Vector3.new(10.4, 0.2, 0.3),
		CFrame = cf * CFrame.new(0, 5.2, -4.2),
		Color = COL.NeonRed,
		Material = Enum.Material.Neon,
		Parent = folder,
	})
	-- Crate stack beside shed
	for i = 0, 2 do
		p({
			Name = "AmmoCrate",
			Size = Vector3.new(2.2, 1.4, 1.8),
			CFrame = cf * CFrame.new(6.5, 0.9 + i * 1.45, -1 + (i % 2) * 0.4),
			Color = COL.Crate,
			Material = Enum.Material.Wood,
			Parent = folder,
		})
	end
	local ammoHost = p({
		Name = "AmmoDressHost",
		Size = Vector3.new(3, 2, 3),
		CFrame = cf * CFrame.new(0, 3, 0),
		Transparency = 1,
		CanCollide = false,
		Parent = folder,
	})
	pcall(function()
		local vas = require(script.Parent.Parent.Services.VisualAssetService)
		if vas and vas.TryAttachPropVisual then
			vas.TryAttachPropVisual(ammoHost, "AmmoShed")
		end
	end)
end

local function kitRadioTower(folder: Folder, origin: Vector3, yawDeg: number)
	local cf = CFrame.new(origin) * CFrame.Angles(0, math.rad(yawDeg), 0)
	p({
		Name = "RadioBase",
		Size = Vector3.new(4, 1.2, 4),
		CFrame = cf * CFrame.new(0, 0.6, 0),
		Color = COL.Concrete,
		Material = Enum.Material.Concrete,
		CanCollide = true,
		CanQuery = true,
		Parent = folder,
	})
	p({
		Name = "RadioMast",
		Size = Vector3.new(0.8, 28, 0.8),
		CFrame = cf * CFrame.new(0, 15, 0),
		Color = COL.Metal,
		Material = Enum.Material.Metal,
		CanCollide = true,
		CanQuery = true,
		Parent = folder,
	})
	p({
		Name = "RadioDish",
		Size = Vector3.new(0.4, 5, 5),
		CFrame = cf * CFrame.new(0, 22, 0) * CFrame.Angles(0, 0, math.rad(90)),
		Color = COL.MetalDark,
		Material = Enum.Material.Metal,
		Shape = Enum.PartType.Cylinder,
		Parent = folder,
	})
	p({
		Name = "RadioTip",
		Size = Vector3.new(1.2, 1.2, 1.2),
		CFrame = cf * CFrame.new(0, 29.5, 0),
		Color = COL.NeonCyan,
		Material = Enum.Material.Neon,
		Shape = Enum.PartType.Ball,
		Parent = folder,
	})
	p({
		Name = "RadioHut",
		Size = Vector3.new(5, 3.5, 5),
		CFrame = cf * CFrame.new(5, 1.9, 0),
		Color = COL.Olive,
		Material = Enum.Material.Metal,
		CanCollide = true,
		CanQuery = true,
		Parent = folder,
	})
end

local function kitCheckpoint(folder: Folder, origin: Vector3, yawDeg: number)
	local cf = CFrame.new(origin) * CFrame.Angles(0, math.rad(yawDeg), 0)
	-- Gate posts
	for _, ox in ipairs({ -8, 8 }) do
		p({
			Name = "GatePost",
			Size = Vector3.new(1.4, 8, 1.4),
			CFrame = cf * CFrame.new(ox, 4, 0),
			Color = COL.Concrete,
			Material = Enum.Material.Concrete,
			CanCollide = true,
			CanQuery = true,
			Parent = folder,
		})
	end
	p({
		Name = "GateBar",
		Size = Vector3.new(14, 0.5, 0.5),
		CFrame = cf * CFrame.new(0, 3.5, 0),
		Color = COL.NeonOrange,
		Material = Enum.Material.Neon,
		Parent = folder,
	})
	p({
		Name = "GateBooth",
		Size = Vector3.new(4, 4, 4),
		CFrame = cf * CFrame.new(-12, 2.2, 2),
		Color = COL.OliveDark,
		Material = Enum.Material.Metal,
		CanCollide = true,
		CanQuery = true,
		Parent = folder,
	})
	p({
		Name = "GateRoof",
		Size = Vector3.new(4.5, 0.4, 4.5),
		CFrame = cf * CFrame.new(-12, 4.4, 2),
		Color = COL.ConcreteDark,
		Material = Enum.Material.Metal,
		Parent = folder,
	})
	p({
		Name = "GateAccent",
		Size = Vector3.new(4.6, 0.2, 0.3),
		CFrame = cf * CFrame.new(-12, 4.2, 0),
		Color = COL.NeonGold,
		Material = Enum.Material.Neon,
		Parent = folder,
	})
	-- Barrier arms beside road
	p({
		Name = "BarrierArm",
		Size = Vector3.new(10, 0.35, 0.35),
		CFrame = cf * CFrame.new(3, 1.2, 3),
		Color = COL.NeonOrange,
		Material = Enum.Material.Neon,
		Parent = folder,
	})
end

local function kitSandbagLine(folder: Folder, origin: Vector3, yawDeg: number, length: number?)
	local cf = CFrame.new(origin) * CFrame.Angles(0, math.rad(yawDeg), 0)
	local n = length or 5
	for i = 0, n - 1 do
		p({
			Name = "Sandbag",
			Size = Vector3.new(2.4, 1.1, 1.4),
			CFrame = cf * CFrame.new((i - (n - 1) / 2) * 2.5, 0.55, 0),
			Color = COL.Sandbag,
			Material = Enum.Material.Sand,
			CanCollide = true,
			CanQuery = true,
			Parent = folder,
		})
		p({
			Name = "SandbagTop",
			Size = Vector3.new(2.2, 1.0, 1.2),
			CFrame = cf * CFrame.new((i - (n - 1) / 2) * 2.5, 1.5, 0.1),
			Color = COL.Sand,
			Material = Enum.Material.Sand,
			Parent = folder,
		})
	end
end

local function kitWireFence(folder: Folder, origin: Vector3, yawDeg: number, segments: number?)
	local cf = CFrame.new(origin) * CFrame.Angles(0, math.rad(yawDeg), 0)
	local n = segments or 4
	for i = 0, n do
		p({
			Name = "WirePost",
			Size = Vector3.new(0.35, 3.2, 0.35),
			CFrame = cf * CFrame.new((i - n / 2) * 4, 1.6, 0),
			Color = COL.Wire,
			Material = Enum.Material.Metal,
			CanCollide = true,
			CanQuery = true,
			Parent = folder,
		})
	end
	for row = 0, 2 do
		p({
			Name = "WireRail",
			Size = Vector3.new(n * 4 + 0.5, 0.12, 0.12),
			CFrame = cf * CFrame.new(0, 0.6 + row * 0.9, 0),
			Color = COL.Wire,
			Material = Enum.Material.Metal,
			Parent = folder,
		})
	end
end

local function kitRuinedWall(folder: Folder, origin: Vector3, yawDeg: number)
	local cf = CFrame.new(origin) * CFrame.Angles(0, math.rad(yawDeg), 0)
	p({
		Name = "RuinA",
		Size = Vector3.new(12, 6, 1.8),
		CFrame = cf * CFrame.new(-3, 3, 0),
		Color = COL.Ruin,
		Material = Enum.Material.Concrete,
		CanCollide = true,
		CanQuery = true,
		Parent = folder,
	})
	p({
		Name = "RuinB",
		Size = Vector3.new(5, 3.5, 1.6),
		CFrame = cf * CFrame.new(6, 1.75, 0.4),
		Color = COL.ConcreteDark,
		Material = Enum.Material.Concrete,
		CanCollide = true,
		CanQuery = true,
		Parent = folder,
	})
	p({
		Name = "RuinRubble",
		Size = Vector3.new(4, 1.2, 3),
		CFrame = cf * CFrame.new(4, 0.6, 2),
		Color = COL.Sandbag,
		Material = Enum.Material.Slate,
		Parent = folder,
	})
end

local function kitVehicleSilhouette(folder: Folder, origin: Vector3, yawDeg: number, kind: string?)
	local cf = CFrame.new(origin) * CFrame.Angles(0, math.rad(yawDeg), 0)
	local k = kind or "jeep"
	if k == "truck" then
		p({
			Name = "DecoyCab",
			Size = Vector3.new(4, 3.2, 5),
			CFrame = cf * CFrame.new(0, 2.2, -4),
			Color = COL.Vehicle,
			Material = Enum.Material.Metal,
			Parent = folder,
		})
		p({
			Name = "DecoyBed",
			Size = Vector3.new(4.2, 2.2, 8),
			CFrame = cf * CFrame.new(0, 1.6, 3),
			Color = COL.OliveDark,
			Material = Enum.Material.Metal,
			Parent = folder,
		})
	elseif k == "tank" then
		p({
			Name = "DecoyHull",
			Size = Vector3.new(6, 2.4, 10),
			CFrame = cf * CFrame.new(0, 1.6, 0),
			Color = COL.Vehicle,
			Material = Enum.Material.Metal,
			Parent = folder,
		})
		p({
			Name = "DecoyTurret",
			Size = Vector3.new(4, 1.8, 4),
			CFrame = cf * CFrame.new(0, 3.4, -0.5),
			Color = COL.Olive,
			Material = Enum.Material.Metal,
			Parent = folder,
		})
		p({
			Name = "DecoyBarrel",
			Size = Vector3.new(0.55, 0.55, 7),
			CFrame = cf * CFrame.new(0, 3.5, -5),
			Color = COL.MetalDark,
			Material = Enum.Material.Metal,
			Parent = folder,
		})
	else
		-- jeep
		p({
			Name = "DecoyBody",
			Size = Vector3.new(3.6, 1.8, 6.5),
			CFrame = cf * CFrame.new(0, 1.4, 0),
			Color = COL.Vehicle,
			Material = Enum.Material.Metal,
			Parent = folder,
		})
		p({
			Name = "DecoyCabin",
			Size = Vector3.new(3.4, 1.5, 2.8),
			CFrame = cf * CFrame.new(0, 2.8, -0.8),
			Color = COL.OliveDark,
			Material = Enum.Material.Metal,
			Parent = folder,
		})
	end
	p({
		Name = "DecoyAccent",
		Size = Vector3.new(2.5, 0.15, 0.3),
		CFrame = cf * CFrame.new(0, 2.4, -3.2),
		Color = COL.VehicleAccent,
		Material = Enum.Material.Neon,
		Parent = folder,
	})
	-- Muted DISPLAY plate — never looks spawnable
	local plate = p({
		Name = "DISPLAY",
		Size = Vector3.new(1.6, 0.12, 0.7),
		CFrame = cf * CFrame.new(0, 0.9, 3.2),
		Color = Color3.fromRGB(40, 42, 38),
		Material = Enum.Material.Metal,
		CanCollide = false,
		Parent = folder,
	})
	plate:SetAttribute("WE_DisplayOnly", true)
	-- Wheels (deco)
	for _, ox in ipairs({ -1.6, 1.6 }) do
		for _, oz in ipairs({ -2.2, 2.2 }) do
			p({
				Name = "DecoyWheel",
				Size = Vector3.new(0.7, 1.4, 1.4),
				CFrame = cf * CFrame.new(ox, 0.7, oz),
				Color = COL.MetalDark,
				Material = Enum.Material.Rubber,
				Shape = Enum.PartType.Cylinder,
				Parent = folder,
			})
		end
	end
end

local function kitOilDrums(folder: Folder, origin: Vector3, count: number?)
	local n = count or 4
	for i = 0, n - 1 do
		local ox = (i % 2) * 1.8
		local oz = math.floor(i / 2) * 1.8
		p({
			Name = "OilDrum",
			Size = Vector3.new(2.2, 1.4, 1.4),
			CFrame = CFrame.new(at(origin, ox, 1.1, oz)) * CFrame.Angles(0, 0, math.rad(90)),
			Color = if i % 2 == 0 then COL.Drum else COL.DrumAccent,
			Material = Enum.Material.Metal,
			Shape = Enum.PartType.Cylinder,
			Parent = folder,
		})
	end
end

local function kitCrateStack(folder: Folder, origin: Vector3)
	for i = 0, 3 do
		p({
			Name = "Crate",
			Size = Vector3.new(2.4, 1.6, 2.0),
			Position = at(origin, (i % 2) * 2.5, 0.8 + math.floor(i / 2) * 1.65, (i % 2) * 0.3),
			Color = COL.Crate,
			Material = Enum.Material.Wood,
			Parent = folder,
		})
	end
	p({
		Name = "CrateAccent",
		Size = Vector3.new(2.2, 0.12, 0.2),
		Position = at(origin, 0, 2.5, 0),
		Color = COL.NeonGold,
		Material = Enum.Material.Neon,
		Parent = folder,
	})
end

local function kitLightPole(folder: Folder, origin: Vector3)
	p({
		Name = "Pole",
		Size = Vector3.new(0.4, 12, 0.4),
		Position = at(origin, 0, 6, 0),
		Color = COL.MetalDark,
		Material = Enum.Material.Metal,
		CanCollide = true,
		CanQuery = true,
		Parent = folder,
	})
	p({
		Name = "Arm",
		Size = Vector3.new(3.5, 0.3, 0.3),
		Position = at(origin, 1.5, 11.5, 0),
		Color = COL.Metal,
		Material = Enum.Material.Metal,
		Parent = folder,
	})
	p({
		Name = "Lamp",
		Size = Vector3.new(1.2, 0.6, 1.2),
		Position = at(origin, 3, 11.2, 0),
		Color = COL.Light,
		Material = Enum.Material.Neon,
		Parent = folder,
	})
end

local function kitRoadSign(folder: Folder, origin: Vector3, yawDeg: number)
	local cf = CFrame.new(origin) * CFrame.Angles(0, math.rad(yawDeg), 0)
	p({
		Name = "SignPost",
		Size = Vector3.new(0.35, 6, 0.35),
		CFrame = cf * CFrame.new(0, 3, 0),
		Color = COL.MetalDark,
		Material = Enum.Material.Metal,
		CanCollide = true,
		CanQuery = true,
		Parent = folder,
	})
	p({
		Name = "SignFace",
		Size = Vector3.new(4, 2.2, 0.25),
		CFrame = cf * CFrame.new(0, 5.5, 0),
		Color = COL.Sign,
		Material = Enum.Material.Metal,
		Parent = folder,
	})
	p({
		Name = "SignStripe",
		Size = Vector3.new(3.6, 0.35, 0.28),
		CFrame = cf * CFrame.new(0, 5.5, 0),
		Color = COL.SignFace,
		Material = Enum.Material.Neon,
		Parent = folder,
	})
end

local function kitCampfire(folder: Folder, origin: Vector3)
	-- Stone ring + glow
	for i = 0, 5 do
		local ang = i * 60
		local rad = 1.6
		p({
			Name = "FireStone",
			Size = Vector3.new(0.9, 0.55, 0.7),
			CFrame = CFrame.new(origin + Vector3.new(math.cos(math.rad(ang)) * rad, 0.3, math.sin(math.rad(ang)) * rad)),
			Color = COL.CampfireStone,
			Material = Enum.Material.Slate,
			Parent = folder,
		})
	end
	p({
		Name = "CampGlow",
		Size = Vector3.new(1.4, 0.7, 1.4),
		Position = origin + Vector3.new(0, 0.55, 0),
		Color = COL.CampfireGlow,
		Material = Enum.Material.Neon,
		Parent = folder,
	})
	p({
		Name = "CampLog",
		Size = Vector3.new(1.8, 0.35, 0.35),
		CFrame = CFrame.new(origin + Vector3.new(0, 0.4, 0)) * CFrame.Angles(0, math.rad(30), 0),
		Color = COL.WoodDark,
		Material = Enum.Material.Wood,
		Parent = folder,
	})
end

local function kitAdobeBuilding(folder: Folder, origin: Vector3, yawDeg: number)
	local cf = CFrame.new(origin) * CFrame.Angles(0, math.rad(yawDeg), 0)
	p({
		Name = "AdobeBody",
		Size = Vector3.new(12, 7, 9),
		CFrame = cf * CFrame.new(0, 3.5, 0),
		Color = COL.Adobe,
		Material = Enum.Material.Sandstone,
		CanCollide = true,
		CanQuery = true,
		Parent = folder,
	})
	p({
		Name = "AdobeRoof",
		Size = Vector3.new(13.2, 1.0, 10.2),
		CFrame = cf * CFrame.new(0, 7.3, 0),
		Color = COL.AdobeDark,
		Material = Enum.Material.Sandstone,
		CanCollide = true,
		CanQuery = true,
		Parent = folder,
	})
	p({
		Name = "AdobeDoor",
		Size = Vector3.new(2.2, 3.4, 0.35),
		CFrame = cf * CFrame.new(0, 1.8, -4.55),
		Color = COL.WoodDark,
		Material = Enum.Material.Wood,
		Parent = folder,
	})
	for _, ox in ipairs({ -3.5, 3.5 }) do
		p({
			Name = "AdobeWindow",
			Size = Vector3.new(1.6, 1.4, 0.25),
			CFrame = cf * CFrame.new(ox, 4.2, -4.5),
			Color = COL.AdobeWindow,
			Material = Enum.Material.Glass,
			Parent = folder,
		})
	end
	p({
		Name = "AdobeAccent",
		Size = Vector3.new(12.4, 0.2, 0.3),
		CFrame = cf * CFrame.new(0, 6.8, -4.6),
		Color = COL.NeonGold,
		Material = Enum.Material.Neon,
		Parent = folder,
	})
end

local function kitRichTent(folder: Folder, origin: Vector3, yawDeg: number)
	-- Canvas folds, poles, guy-line Parts (original — not copied meshes)
	local cf = CFrame.new(origin) * CFrame.Angles(0, math.rad(yawDeg), 0)
	p({
		Name = "TentFloor",
		Size = Vector3.new(9, 0.25, 7),
		CFrame = cf * CFrame.new(0, 0.12, 0),
		Color = COL.TentDark,
		Material = Enum.Material.Fabric,
		Parent = folder,
	})
	-- Main canvas body
	p({
		Name = "TentBody",
		Size = Vector3.new(8.2, 3.8, 6.2),
		CFrame = cf * CFrame.new(0, 2.1, 0),
		Color = COL.Tent,
		Material = Enum.Material.Fabric,
		CanCollide = true,
		CanQuery = true,
		Parent = folder,
	})
	-- Ridge / fold panels
	p({
		Name = "TentRidge",
		Size = Vector3.new(8.5, 0.7, 1.4),
		CFrame = cf * CFrame.new(0, 4.3, 0),
		Color = COL.TentDark,
		Material = Enum.Material.Fabric,
		Parent = folder,
	})
	p({
		Name = "TentFoldL",
		Size = Vector3.new(0.35, 3.5, 6.0),
		CFrame = cf * CFrame.new(-3.9, 2.0, 0),
		Color = COL.TentDark,
		Material = Enum.Material.Fabric,
		Parent = folder,
	})
	p({
		Name = "TentFoldR",
		Size = Vector3.new(0.35, 3.5, 6.0),
		CFrame = cf * CFrame.new(3.9, 2.0, 0),
		Color = COL.TentDark,
		Material = Enum.Material.Fabric,
		Parent = folder,
	})
	-- Center + corner poles
	p({
		Name = "TentPole",
		Size = Vector3.new(0.3, 5.2, 0.3),
		CFrame = cf * CFrame.new(0, 2.6, 0),
		Color = COL.TentPole,
		Material = Enum.Material.Wood,
		Parent = folder,
	})
	for _, ox in ipairs({ -4.2, 4.2 }) do
		for _, oz in ipairs({ -3.2, 3.2 }) do
			p({
				Name = "TentStake",
				Size = Vector3.new(0.22, 1.2, 0.22),
				CFrame = cf * CFrame.new(ox, 0.6, oz),
				Color = COL.TentPole,
				Material = Enum.Material.Wood,
				Parent = folder,
			})
			-- Guy lines (thin Parts)
			p({
				Name = "GuyLine",
				Size = Vector3.new(0.08, 0.08, 4.2),
				CFrame = cf * CFrame.new(ox * 0.5, 2.4, oz * 0.5) * CFrame.Angles(math.rad(28), 0, math.rad(ox > 0 and -12 or 12)),
				Color = Color3.fromRGB(180, 170, 140),
				Material = Enum.Material.Fabric,
				CastShadow = false,
				Parent = folder,
			})
		end
	end
	p({
		Name = "TentDoorFlap",
		Size = Vector3.new(2.0, 2.8, 0.2),
		CFrame = cf * CFrame.new(0, 1.5, -3.15),
		Color = COL.TentDark,
		Material = Enum.Material.Fabric,
		Parent = folder,
	})
end

local function kitCamp(folder: Folder, origin: Vector3, yawDeg: number)
	local cf = CFrame.new(origin) * CFrame.Angles(0, math.rad(yawDeg), 0)
	kitRichTent(folder, (cf * CFrame.new(0, 0, 0)).Position, yawDeg)
	kitRichTent(folder, (cf * CFrame.new(12, 0, 4)).Position, yawDeg + 15)
	kitAdobeBuilding(folder, (cf * CFrame.new(-14, 0, 2)).Position, yawDeg)
	kitCampfire(folder, (cf * CFrame.new(6, 0, -6)).Position)
	kitCrateStack(folder, (cf * CFrame.new(-6, 0, 6)).Position)
	kitOilDrums(folder, (cf * CFrame.new(-5, 0, -5)).Position, 2)
	kitSandbagLine(folder, (cf * CFrame.new(0, 0, 10)).Position, yawDeg, 4)
end

local function kitRunway(folder: Folder, origin: Vector3, yawDeg: number, length: number?)
	local cf = CFrame.new(origin) * CFrame.Angles(0, math.rad(yawDeg), 0)
	local len = length or 80
	p({
		Name = "RunwayPad",
		Size = Vector3.new(14, 0.25, len),
		CFrame = cf * CFrame.new(0, 0.2, 0),
		Color = COL.Asphalt,
		Material = Enum.Material.Asphalt,
		CanCollide = true,
		CanQuery = true,
		Parent = folder,
	})
	-- Centerline dashes
	local dashes = math.floor(len / 12)
	for i = 0, dashes - 1 do
		local z = -len / 2 + 6 + i * 12
		p({
			Name = "RunwayDash",
			Size = Vector3.new(1.2, 0.15, 6),
			CFrame = cf * CFrame.new(0, 0.35, z),
			Color = COL.NeonGold,
			Material = Enum.Material.Neon,
			Parent = folder,
		})
	end
	-- Threshold chevrons
	p({
		Name = "RunwayThresh",
		Size = Vector3.new(12, 0.15, 2),
		CFrame = cf * CFrame.new(0, 0.35, -len / 2 + 4),
		Color = Color3.fromRGB(240, 240, 240),
		Material = Enum.Material.Neon,
		Parent = folder,
	})
	p({
		Name = "RunwayThresh2",
		Size = Vector3.new(12, 0.15, 2),
		CFrame = cf * CFrame.new(0, 0.35, len / 2 - 4),
		Color = Color3.fromRGB(240, 240, 240),
		Material = Enum.Material.Neon,
		Parent = folder,
	})
end

local function kitOutpost(folder: Folder, origin: Vector3, yawDeg: number)
	local cf = CFrame.new(origin) * CFrame.Angles(0, math.rad(yawDeg), 0)
	-- Compact fortified desert outpost: adobe + wooden tower + tent + sandbags + fence
	kitAdobeBuilding(folder, (cf * CFrame.new(0, 0, 0)).Position, yawDeg)
	kitWatchtower(folder, (cf * CFrame.new(12, 0, 10)).Position, yawDeg + 20)
	kitRichTent(folder, (cf * CFrame.new(-12, 0, 6)).Position, yawDeg - 10)
	kitSandbagLine(folder, (cf * CFrame.new(0, 0, -10)).Position, yawDeg, 5)
	kitSandbagLine(folder, (cf * CFrame.new(8, 0, -8)).Position, yawDeg + 40, 3)
	kitWireFence(folder, (cf * CFrame.new(-14, 0, -2)).Position, yawDeg + 90, 3)
	kitAmmoShed(folder, (cf * CFrame.new(-8, 0, 14)).Position, yawDeg)
	kitCampfire(folder, (cf * CFrame.new(6, 0, -6)).Position)
	kitLightPole(folder, (cf * CFrame.new(14, 0, -8)).Position)
end


-- ── Capture clear zone (20–30 studs around flags / collectors approach) ──
local CAPTURE_CLEAR_XZ: { Vector3 } = {
	Vector3.new(0, 0, 0),
	Vector3.new(0, 0, -1300),
	Vector3.new(0, 0, 1300),
	Vector3.new(1300, 0, 0),
	Vector3.new(-1300, 0, 0),
	Vector3.new(950, 0, 950),
	Vector3.new(-950, 0, -950),
	Vector3.new(1800, 0, -750),
	Vector3.new(-1800, 0, 750),
	Vector3.new(1450, 0, -1450),
	Vector3.new(-1450, 0, 1450),
}
-- Plot pad centers — keep jeep drive / garage exits clear
local PLOT_CLEAR_XZ: { Vector3 } = {
	Vector3.new(-800, 0, -400),
	Vector3.new(-800, 0, 400),
	Vector3.new(0, 0, -800),
	Vector3.new(0, 0, 800),
	Vector3.new(800, 0, -400),
	Vector3.new(800, 0, 400),
}

local function tooCloseToGameplay(pos: Vector3, radius: number?): boolean
	local r = radius or 28
	local px, pz = pos.X, pos.Z
	for _, c in ipairs(CAPTURE_CLEAR_XZ) do
		local dx, dz = px - c.X, pz - c.Z
		if math.sqrt(dx * dx + dz * dz) < r then
			return true
		end
	end
	-- Keep collectors / garage approach around plot pads (~45 stud soft clear for big props)
	local plotR = math.max(r, 40)
	for _, c in ipairs(PLOT_CLEAR_XZ) do
		local dx, dz = px - c.X, pz - c.Z
		if math.sqrt(dx * dx + dz * dz) < plotR then
			return true
		end
	end
	return false
end

local function tryPropAttach(host: BasePart, propKey: string): boolean
	local ok, result = pcall(function(): boolean
		local vas = require(script.Parent.Parent.Services.VisualAssetService)
		if not (vas and vas.TryAttachPropVisual) then
			return false
		end
		return vas.TryAttachPropVisual(host, propKey) == true
	end)
	if not ok then
		warn("[MapDressing] InsertService/prop reject", propKey, result)
		return false
	end
	return result == true
end

local function tryAsphaltDecal(roadPart: BasePart)
	pcall(function()
		local vas = require(script.Parent.Parent.Services.VisualAssetService)
		if vas and vas.ApplyAsphaltDecal then
			vas.ApplyAsphaltDecal(roadPart)
		end
	end)
end

-- Part-kit jersey (fallback if mesh insert fails) + optional catalog overlay
local function kitJersey(folder: Folder, origin: Vector3, yawDeg: number)
	local cf = CFrame.new(origin) * CFrame.Angles(0, math.rad(yawDeg + ((origin.X + origin.Z) % 11) - 5), 0)
	local body = p({
		Name = "JerseyBody",
		Size = Vector3.new(4.5, 2.2, 1.1),
		CFrame = cf * CFrame.new(0, 1.1, 0),
		Color = COL.Concrete,
		Material = Enum.Material.Concrete,
		CanCollide = true,
		CanQuery = true,
		Parent = folder,
	})
	p({
		Name = "JerseyBase",
		Size = Vector3.new(5.2, 0.45, 1.6),
		CFrame = cf * CFrame.new(0, 0.22, 0),
		Color = COL.ConcreteDark,
		Material = Enum.Material.Concrete,
		CanCollide = true,
		Parent = folder,
	})
	tryPropAttach(body, "JerseyBarrier")
end

local function kitChevronWedges(folder: Folder, origin: Vector3, yawDeg: number)
	local cf = CFrame.new(origin) * CFrame.Angles(0, math.rad(yawDeg), 0)
	for i = 0, 3 do
		p({
			Name = "ChevronWedge" .. i,
			Size = Vector3.new(2.2, 0.12, 1.1),
			CFrame = cf * CFrame.new(0, 0.08, -i * 2.4) * CFrame.Angles(0, 0, math.rad(18)),
			Color = Color3.fromRGB(245, 245, 245),
			Material = Enum.Material.SmoothPlastic,
			CanCollide = false,
			Parent = folder,
		})
	end
end

local function kitAsphaltStrip(folder: Folder, origin: Vector3, yawDeg: number, length: number?, width: number?)
	local cf = CFrame.new(origin) * CFrame.Angles(0, math.rad(yawDeg), 0)
	local len = length or 48
	local w = width or 14
	local road = p({
		Name = "AsphaltStrip",
		Size = Vector3.new(w, 0.18, len),
		CFrame = cf * CFrame.new(0, 0.1, 0),
		Color = COL.Asphalt,
		Material = Enum.Material.Asphalt,
		CanCollide = false,
		Parent = folder,
	})
	tryAsphaltDecal(road)
end

local function kitMesaHost(folder: Folder, origin: Vector3, yawDeg: number)
	local cf = CFrame.new(origin) * CFrame.Angles(0, math.rad(yawDeg), 0)
	local host = p({
		Name = "MesaHost",
		Size = Vector3.new(28, 18, 22),
		CFrame = cf * CFrame.new(0, 9, 0),
		Color = Color3.fromRGB(168, 95, 58),
		Material = Enum.Material.Sandstone,
		CanCollide = true,
		CanQuery = true,
		Parent = folder,
	})
	-- Cap (Part fallback silhouette if mesh fails)
	p({
		Name = "MesaCap",
		Size = Vector3.new(20, 4, 16),
		CFrame = cf * CFrame.new(0, 20, 0),
		Color = Color3.fromRGB(185, 120, 80),
		Material = Enum.Material.Sandstone,
		CanCollide = false,
		Parent = folder,
	})
	tryPropAttach(host, "DesertMesa")
end

local function kitDesertRockScatter(folder: Folder, origin: Vector3)
	local host = p({
		Name = "DesertRockHost",
		Size = Vector3.new(4, 2.5, 3.5),
		Position = origin + Vector3.new(0, 1.2, 0),
		Color = Color3.fromRGB(160, 110, 75),
		Material = Enum.Material.Rock,
		CanCollide = true,
		Parent = folder,
	})
	tryPropAttach(host, "DesertRock")
end

local function kitFloraCluster(folder: Folder, origin: Vector3)
	local host = p({
		Name = "FloraHost",
		Size = Vector3.new(2, 4, 2),
		Position = origin + Vector3.new(0, 2, 0),
		Color = COL.Olive,
		Material = Enum.Material.Grass,
		CanCollide = false,
		Transparency = 1,
		Parent = folder,
	})
	-- Prefer DesertPlants pack; Palm used on far ring hosts separately
	tryPropAttach(host, "DesertPlants")
end

local function kitWreckSite(folder: Folder, origin: Vector3, yawDeg: number)
	local cf = CFrame.new(origin) * CFrame.Angles(0, math.rad(yawDeg), 0)
	kitVehicleSilhouette(folder, origin, yawDeg, "tank")
	local host = p({
		Name = "TankWreckHost",
		Size = Vector3.new(8, 4, 12),
		CFrame = cf * CFrame.new(0, 2, 0),
		Transparency = 1,
		CanCollide = false,
		Parent = folder,
	})
	tryPropAttach(host, "TankWreck")
	kitOilDrums(folder, (cf * CFrame.new(8, 0, 4)).Position, 3)
	kitCrateStack(folder, (cf * CFrame.new(-7, 0, 5)).Position)
	p({
		Name = "WreckScorchPad",
		Size = Vector3.new(16, 0.2, 12),
		CFrame = cf * CFrame.new(0, 0.05, 0),
		Color = Color3.fromRGB(35, 32, 28),
		Material = Enum.Material.Asphalt,
		CanCollide = false,
		Parent = folder,
	})
end

local function kitRuinLandmark(folder: Folder, origin: Vector3, yawDeg: number)
	local cf = CFrame.new(origin) * CFrame.Angles(0, math.rad(yawDeg), 0)
	kitRuinedWall(folder, origin, yawDeg)
	local host = p({
		Name = "RuinBuildingHost",
		Size = Vector3.new(14, 10, 12),
		CFrame = cf * CFrame.new(0, 5, 0),
		Color = COL.Ruin,
		Material = Enum.Material.Concrete,
		CanCollide = true,
		CanQuery = true,
		Parent = folder,
	})
	tryPropAttach(host, "RuinedBuilding")
	local wallHost = p({
		Name = "RuinWallHost",
		Size = Vector3.new(10, 6, 1.5),
		CFrame = cf * CFrame.new(8, 3, 4),
		Color = COL.Ruin,
		Material = Enum.Material.Concrete,
		CanCollide = true,
		Parent = folder,
	})
	tryPropAttach(wallHost, "RuinedWall")
end

local function kitCamoOverCrates(folder: Folder, origin: Vector3)
	kitCrateStack(folder, origin)
	local host = p({
		Name = "CamoNetHost",
		Size = Vector3.new(8, 1, 6),
		Position = origin + Vector3.new(0, 4.5, 0),
		Color = COL.OliveDark,
		Material = Enum.Material.Fabric,
		CanCollide = false,
		Transparency = 0.4,
		Parent = folder,
	})
	tryPropAttach(host, "CamoNet")
end

local function kitPortableLight(folder: Folder, origin: Vector3, fullQuality: boolean)
	kitLightPole(folder, origin)
	local host = p({
		Name = "PortableLightHost",
		Size = Vector3.new(2, 8, 2),
		Position = origin + Vector3.new(0, 4, 0),
		Transparency = 1,
		CanCollide = false,
		Parent = folder,
	})
	tryPropAttach(host, "PortableLightTower")
	if fullQuality then
		local pl = Instance.new("PointLight")
		pl.Name = "WE_PortableLight"
		pl.Brightness = 0.85
		pl.Range = 28
		pl.Color = COL.Light
		pl.Parent = host
	end
end

local function kitHesco(folder: Folder, origin: Vector3, yawDeg: number)
	local cf = CFrame.new(origin) * CFrame.Angles(0, math.rad(yawDeg), 0)
	local host = p({
		Name = "HescoHost",
		Size = Vector3.new(5, 3.2, 2.2),
		CFrame = cf * CFrame.new(0, 1.6, 0),
		Color = COL.Sandbag,
		Material = Enum.Material.Sand,
		CanCollide = true,
		CanQuery = true,
		Parent = folder,
	})
	tryPropAttach(host, "Hesco")
end


-- Sparse optional cluster label (short MaxDistance — mobile friendly)
local function clusterLabel(parent: BasePart, text: string)
	local bb = Instance.new("BillboardGui")
	bb.Name = "DressLabel"
	bb.Size = UDim2.fromOffset(160, 28)
	bb.StudsOffset = Vector3.new(0, 8, 0)
	bb.AlwaysOnTop = false
	bb.MaxDistance = 55
	bb.Parent = parent
	local lab = Instance.new("TextLabel")
	lab.Size = UDim2.fromScale(1, 1)
	lab.BackgroundColor3 = Color3.fromRGB(10, 12, 14)
	lab.BackgroundTransparency = 0.35
	lab.Text = text
	lab.TextColor3 = Color3.fromRGB(220, 230, 210)
	lab.TextScaled = true
	lab.Font = Enum.Font.GothamBold
	lab.BorderSizePixel = 0
	lab.Parent = bb
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, 4)
	c.Parent = lab
end

-- ── Placement plan ────────────────────────────────────────────────────────

local function placeCluster(parent: Folder, name: string, origin: Vector3, builder: (Folder, Vector3, number) -> (), yawDeg: number, label: string?)
	local folder = Instance.new("Folder")
	folder.Name = name
	folder.Parent = parent
	builder(folder, origin, yawDeg)
	if label then
		local anchor = p({
			Name = "LabelAnchor",
			Size = Vector3.new(1, 1, 1),
			Position = origin + Vector3.new(0, 6, 0),
			Transparency = 1,
			CanCollide = false,
			CastShadow = false,
			Parent = folder,
		})
		clusterLabel(anchor, label)
	end
end

function MapDressing.Dress(root: Instance, opts: { Quality: string? }?)
	local quality = string.lower(tostring((opts and opts.Quality) or "Low"))
	local full = quality == "full"
	local dressing = ensureFolder("WorldDressing", root)

	-- PERF Low: ~60–70% fewer clusters than prior dense pass. CastShadow already false in p().

	-- 1) Road checkpoints
	local checkpoints = if full
		then {
			{ Name = "CP_N_Inner", Pos = Vector3.new(0, 0.5, -420), Yaw = 0, Label = "CHECKPOINT" },
			{ Name = "CP_E_Inner", Pos = Vector3.new(420, 0.5, 0), Yaw = 90, Label = "CHECKPOINT" },
			{ Name = "CP_S_Outer", Pos = Vector3.new(0, 0.5, 1050), Yaw = 180, Label = nil },
			{ Name = "CP_W_Outer", Pos = Vector3.new(-1050, 0.5, 0), Yaw = -90, Label = nil },
		}
		else {
			{ Name = "CP_N_Inner", Pos = Vector3.new(0, 0.5, -420), Yaw = 0, Label = "CHECKPOINT" },
			{ Name = "CP_E_Inner", Pos = Vector3.new(420, 0.5, 0), Yaw = 90, Label = nil },
		}
	for _, cp in ipairs(checkpoints) do
		placeCluster(dressing, cp.Name, cp.Pos, kitCheckpoint, cp.Yaw, cp.Label)
	end

	-- 2) Outposts
	local outposts = if full
		then {
			{ Name = "OP_NorthRidge", Pos = Vector3.new(90, 0.5, -1180), Yaw = 30, Label = "OUTPOST" },
			{ Name = "OP_EastArmory", Pos = Vector3.new(1180, 0.5, 90), Yaw = 100, Label = "OUTPOST" },
			{ Name = "OP_OilFields", Pos = Vector3.new(850, 0.5, 1080), Yaw = 45, Label = "OUTPOST" },
			{ Name = "OP_MidNE", Pos = Vector3.new(550, 0.5, -550), Yaw = 20, Label = nil },
		}
		else {
			{ Name = "OP_NorthRidge", Pos = Vector3.new(90, 0.5, -1180), Yaw = 30, Label = "OUTPOST" },
			{ Name = "OP_EastArmory", Pos = Vector3.new(1180, 0.5, 90), Yaw = 100, Label = nil },
		}
	for _, op in ipairs(outposts) do
		placeCluster(dressing, op.Name, op.Pos, kitOutpost, op.Yaw, op.Label)
	end

	-- 3) Hangars (Low: 1 hangar + light fuel; Full: prior airfield)
	do
		local f = Instance.new("Folder")
		f.Name = "AirfieldDressing"
		f.Parent = dressing
		kitHangar(f, Vector3.new(700, 0.5, -200), 90)
		if full then
			kitHangar(f, Vector3.new(700, 0.5, 200), 90)
			kitRunway(f, Vector3.new(780, 0.5, 0), 0, 100)
			kitFuelDepot(f, Vector3.new(640, 0.5, -280), 0)
			kitVehicleSilhouette(f, Vector3.new(660, 0.5, -140), 90, "truck")
			kitVehicleSilhouette(f, Vector3.new(660, 0.5, 140), 85, "jeep")
			kitLightPole(f, Vector3.new(740, 0.5, -60))
			kitLightPole(f, Vector3.new(740, 0.5, 60))
		else
			kitFuelDepot(f, Vector3.new(640, 0.5, -280), 0)
			kitLightPole(f, Vector3.new(740, 0.5, 0))
		end
	end

	-- 4) Depots
	local depots = if full
		then {
			{ Name = "Depot_NW", Pos = Vector3.new(-650, 0.5, -650), Yaw = 45, Kind = "fuel" },
			{ Name = "Ammo_NE", Pos = Vector3.new(650, 0.5, -650), Yaw = 135, Kind = "ammo" },
			{ Name = "Depot_FarE", Pos = Vector3.new(1600, 0.5, 200), Yaw = 0, Kind = "fuel" },
		}
		else {
			{ Name = "Depot_NW", Pos = Vector3.new(-650, 0.5, -650), Yaw = 45, Kind = "fuel" },
		}
	for _, d in ipairs(depots) do
		local f = Instance.new("Folder")
		f.Name = d.Name
		f.Parent = dressing
		if d.Kind == "fuel" then
			kitFuelDepot(f, d.Pos, d.Yaw)
			kitOilDrums(f, d.Pos + Vector3.new(10, 0, 6), if full then 4 else 2)
		else
			kitAmmoShed(f, d.Pos, d.Yaw)
			kitCrateStack(f, d.Pos + Vector3.new(8, 0, 4))
		end
	end

	-- 5) Radio
	do
		local f = Instance.new("Folder")
		f.Name = "Radio_N"
		f.Parent = dressing
		kitRadioTower(f, Vector3.new(180, 0.5, -1500), 0)
		if full then
			local f2 = Instance.new("Folder")
			f2.Name = "Radio_OilApproach"
			f2.Parent = dressing
			kitRadioTower(f2, Vector3.new(1100, 0.5, 1100), 45)
		end
	end

	-- 6) Camps
	local camps = if full
		then {
			{ Name = "Camp_N", Pos = Vector3.new(-280, 0.5, -700), Yaw = 15 },
			{ Name = "Camp_E", Pos = Vector3.new(900, 0.5, -350), Yaw = 90 },
			{ Name = "Camp_FarSE", Pos = Vector3.new(1400, 0.5, 900), Yaw = 40 },
		}
		else {
			{ Name = "Camp_N", Pos = Vector3.new(-280, 0.5, -700), Yaw = 15 },
		}
	for _, c in ipairs(camps) do
		local f = Instance.new("Folder")
		f.Name = c.Name
		f.Parent = dressing
		kitCamp(f, c.Pos, c.Yaw)
	end

	-- 7) Dockside (Low: 2 piers; Full: 5)
	do
		local f = Instance.new("Folder")
		f.Name = "DocksideDressing"
		f.Parent = dressing
		local pierXs = if full then { -200, -80, 80, 200, 350 } else { -80, 80 }
		for i, x in ipairs(pierXs) do
			p({
				Name = "Pier" .. i,
				Size = Vector3.new(18, 1.2, 40),
				Position = Vector3.new(x, 0.8, 1420),
				Color = COL.Dock,
				Material = Enum.Material.Wood,
				CanCollide = true,
				CanQuery = true,
				Parent = f,
			})
			kitCrateStack(f, Vector3.new(x - 4, 1.5, 1410))
			if full then
				kitOilDrums(f, Vector3.new(x + 5, 1.5, 1405), 3)
				kitLightPole(f, Vector3.new(x + 8, 0.5, 1440))
			end
		end
		if full then
			kitAmmoShed(f, Vector3.new(-320, 0.5, 1380), 0)
			kitFuelDepot(f, Vector3.new(320, 0.5, 1380), 180)
			kitVehicleSilhouette(f, Vector3.new(0, 0.5, 1360), 0, "truck")
			kitSandbagLine(f, Vector3.new(0, 0.5, 1340), 0, 6)
		end
	end

	-- 8–9) Approaches — Full only (heavy part cost)
	if full then
		local f = Instance.new("Folder")
		f.Name = "CoastalOilApproaches"
		f.Parent = dressing
		kitCheckpoint(f, Vector3.new(1650, 0.5, -750), 90)
		kitFuelDepot(f, Vector3.new(1580, 0.5, -820), 45)
		kitOilDrums(f, Vector3.new(1600, 0.5, -680), 6)
		kitCheckpoint(f, Vector3.new(-1650, 0.5, 750), -90)
		kitAmmoShed(f, Vector3.new(-1580, 0.5, 820), -45)

		local f2 = Instance.new("Folder")
		f2.Name = "FortApproaches"
		f2.Parent = dressing
		kitRuinedWall(f2, Vector3.new(1320, 0.5, -1320), 45)
		kitSandbagLine(f2, Vector3.new(1280, 0.5, -1450), 90, 5)
		kitVehicleSilhouette(f2, Vector3.new(1250, 0.5, -1380), 40, "tank")
		kitWatchtower(f2, Vector3.new(1200, 0.5, -1500), 30)
		kitRuinedWall(f2, Vector3.new(-1320, 0.5, 1320), -135)
		kitSandbagLine(f2, Vector3.new(-1280, 0.5, 1450), -90, 5)
		kitWatchtower(f2, Vector3.new(-1200, 0.5, 1500), -150)
	end

	-- 10) Road furniture (Low: 4 signs + 2 lights; Full: prior)
	do
		local f = Instance.new("Folder")
		f.Name = "RoadFurniture"
		f.Parent = dressing
		local signSpots = if full
			then {
				{ Vector3.new(40, 0.5, -250), 0 },
				{ Vector3.new(-40, 0.5, 250), 180 },
				{ Vector3.new(250, 0.5, 40), 90 },
				{ Vector3.new(-250, 0.5, -40), -90 },
				{ Vector3.new(40, 0.5, -800), 0 },
				{ Vector3.new(-40, 0.5, 800), 180 },
				{ Vector3.new(800, 0.5, 40), 90 },
				{ Vector3.new(-800, 0.5, -40), -90 },
				{ Vector3.new(40, 0.5, -1600), 0 },
				{ Vector3.new(-40, 0.5, 1600), 180 },
				{ Vector3.new(1600, 0.5, 40), 90 },
				{ Vector3.new(-1600, 0.5, -40), -90 },
			}
			else {
				{ Vector3.new(40, 0.5, -250), 0 },
				{ Vector3.new(250, 0.5, 40), 90 },
				{ Vector3.new(40, 0.5, -800), 0 },
				{ Vector3.new(800, 0.5, 40), 90 },
			}
		for _, s in ipairs(signSpots) do
			kitRoadSign(f, s[1], s[2])
		end
		local lightSpots = if full
			then {
				Vector3.new(30, 0.5, -600),
				Vector3.new(-30, 0.5, 600),
				Vector3.new(600, 0.5, 30),
				Vector3.new(-600, 0.5, -30),
				Vector3.new(30, 0.5, -1200),
				Vector3.new(-30, 0.5, 1200),
				Vector3.new(1200, 0.5, 30),
				Vector3.new(-1200, 0.5, -30),
				Vector3.new(400, 0.5, -400),
				Vector3.new(-400, 0.5, 400),
				Vector3.new(400, 0.5, 400),
				Vector3.new(-400, 0.5, -400),
			}
			else {
				Vector3.new(30, 0.5, -600),
				Vector3.new(600, 0.5, 30),
			}
		for _, lp in ipairs(lightSpots) do
			kitLightPole(f, lp)
		end
		if full then
			kitVehicleSilhouette(f, Vector3.new(120, 0.5, -500), 5, "jeep")
			kitVehicleSilhouette(f, Vector3.new(500, 0.5, 120), 95, "jeep")
			kitVehicleSilhouette(f, Vector3.new(200, 0.5, -1100), 10, "tank")
			kitVehicleSilhouette(f, Vector3.new(1100, 0.5, 200), 100, "truck")
		end
	end


	-- 10b) v35 landmarks — wrecked vehicle cluster + extra bunker / radio silhouette (perf-light)
	do
		local f = Instance.new("Folder")
		f.Name = "Landmarks_v35"
		f.Parent = dressing
		-- Wrecked vehicle prop cluster (mid-warzone)
		local wreckOrigin = Vector3.new(-350, 0.5, -450)
		kitVehicleSilhouette(f, wreckOrigin, 25, "jeep")
		kitVehicleSilhouette(f, wreckOrigin + Vector3.new(10, 0, 4), 110, "truck")
		kitCrateStack(f, wreckOrigin + Vector3.new(-6, 0, 6))
		kitOilDrums(f, wreckOrigin + Vector3.new(4, 0, -5), 3)
		kitSandbagLine(f, wreckOrigin + Vector3.new(0, 0, 12), 15, if full then 3 else 2)
		-- Scorch / debris pads
		p({
			Name = "WreckScorch",
			Size = Vector3.new(18, 0.2, 14),
			CFrame = CFrame.new(wreckOrigin + Vector3.new(2, 0.05, 2)),
			Color = Color3.fromRGB(35, 32, 28),
			Material = Enum.Material.Asphalt,
			CanCollide = false,
			Parent = f,
		})
		-- Extra bunker silhouette (SW approach)
		kitBunker(f, Vector3.new(-700, 0.5, 600), 210)
		if full then
			kitRadioTower(f, Vector3.new(-1200, 0.5, 200), 30)
			kitBunker(f, Vector3.new(550, 0.5, -700), 45)
		end
	end

	-- 11) Bunker line
	do
		local f = Instance.new("Folder")
		f.Name = "BunkerLine"
		f.Parent = dressing
		local bunkers = if full
			then {
				{ Vector3.new(0, 0.5, -900), 0 },
				{ Vector3.new(900, 0.5, 0), 90 },
				{ Vector3.new(-450, 0.5, 900), 195 },
			}
			else {
				{ Vector3.new(0, 0.5, -900), 0 },
			}
		for _, b in ipairs(bunkers) do
			kitBunker(f, b[1], b[2])
		end
	end

	-- 12) Plot-ring perimeter + Design densify 8–12 warzone props / plot (no neon/flat SWAT)
	do
		local f = Instance.new("Folder")
		f.Name = "PlotRingPerimeter"
		f.Parent = dressing
		local plotCenters = {
			Vector3.new(-800, 0.5, -400),
			Vector3.new(-800, 0.5, 400),
			Vector3.new(0, 0.5, -800),
			Vector3.new(0, 0.5, 800),
			Vector3.new(800, 0.5, -400),
			Vector3.new(800, 0.5, 400),
		}
		local plotEdges = if full
			then {
				{ Vector3.new(-800, 0.5, -650), 0 },
				{ Vector3.new(-800, 0.5, 650), 0 },
				{ Vector3.new(0, 0.5, -950), 0 },
				{ Vector3.new(0, 0.5, 950), 180 },
				{ Vector3.new(800, 0.5, -650), 180 },
				{ Vector3.new(800, 0.5, 650), 180 },
			}
			else {
				{ Vector3.new(-800, 0.5, -650), 0 },
				{ Vector3.new(0, 0.5, -950), 0 },
				{ Vector3.new(800, 0.5, 650), 180 },
			}
		for _, e in ipairs(plotEdges) do
			kitSandbagLine(f, e[1], e[2], if full then 4 else 2)
		end
		-- 8–12 clusters per plot (always; Low still gets 8)
		local densify = Instance.new("Folder")
		densify.Name = "PlotWarzoneDensify"
		densify.Parent = dressing
		local perPlot = if full then 12 else 8
		for pi, center in ipairs(plotCenters) do
			for i = 1, perPlot do
				local ang = (i / perPlot) * math.pi * 2 + pi * 0.35
				local rad = 55 + (i % 4) * 12
				local origin = center + Vector3.new(math.cos(ang) * rad, 0, math.sin(ang) * rad)
				local yaw = (i * 41 + pi * 17) % 180
				-- v70: rad 55–91 was outside the old 200 plots but is inside the 320 base now (sandbags / bunkers on
				-- the runway and rear zone). Skip anything inside the footprint + 12 until the waterways pass re-homes them.
				local inside = math.max(math.abs(origin.X - center.X), math.abs(origin.Z - center.Z)) < PLOT_SIZE * 0.5 + 12
				if inside then
					-- skipped (base interior)
				elseif i % 3 == 0 then
					kitSandbagLine(densify, origin, yaw, if full then 4 else 3)
				elseif i % 3 == 1 then
					kitCrateStack(densify, origin)
					kitOilDrums(densify, origin + Vector3.new(4, 0, 2), 2)
				else
					kitBunker(densify, origin, yaw)
				end
			end
		end
	end


	-- 13) Mid-map warzone fill (Low + Full) — sandbags, crates, trenches, debris near roads
	do
		local f = Instance.new("Folder")
		f.Name = "WarzoneFill"
		f.Parent = dressing
		local fills = if full
			then {
				Vector3.new(200, 0.5, -200), Vector3.new(-200, 0.5, 200), Vector3.new(350, 0.5, 350),
				Vector3.new(-350, 0.5, -350), Vector3.new(0, 0.5, -550), Vector3.new(550, 0.5, 0),
				Vector3.new(-550, 0.5, 0), Vector3.new(0, 0.5, 550), Vector3.new(750, 0.5, -400),
				Vector3.new(-750, 0.5, 400), Vector3.new(400, 0.5, -900), Vector3.new(-400, 0.5, 900),
			}
			else {
				Vector3.new(200, 0.5, -200), Vector3.new(-200, 0.5, 200), Vector3.new(0, 0.5, -550),
				Vector3.new(550, 0.5, 0), Vector3.new(-550, 0.5, 0), Vector3.new(350, 0.5, 350),
			}
		for i, origin in ipairs(fills) do
			kitSandbagLine(f, origin, (i * 37) % 180, if full then 5 else 3)
			kitCrateStack(f, origin + Vector3.new(8, 0, 4))
			kitOilDrums(f, origin + Vector3.new(-6, 0, 6), if full then 3 else 2)
			-- Simple trench cut (visual depression plate + berm)
			p({
				Name = "Trench" .. i,
				Size = Vector3.new(18, 1.2, 4),
				Position = origin + Vector3.new(0, 0.2, -10),
				Color = COL.Sandbag,
				Material = Enum.Material.Sand,
				CanCollide = true,
				CanQuery = true,
				Parent = f,
			})
			p({
				Name = "Debris" .. i,
				Size = Vector3.new(3 + (i % 3), 0.7, 2),
				Position = origin + Vector3.new(12, 0.6, -4),
				Color = COL.Ruin,
				Material = Enum.Material.Slate,
				CanCollide = true,
				CanQuery = true,
				Parent = f,
			})
			if full or i % 2 == 0 then
				kitBunker(f, origin + Vector3.new(-14, 0, 12), i * 40)
			end
		end
	end

	-- 14) v36 road warzone density — crater / sandbag / chevron clusters between plots (reuse kits)
	do
		local f = Instance.new("Folder")
		f.Name = "RoadWarzone_v36"
		f.Parent = dressing
		-- Roads between the 6 plot ring (~radius 800); keep part count modest
		local roadSpots = if full
			then {
				Vector3.new(-400, 0.5, -400), Vector3.new(400, 0.5, -400),
				Vector3.new(-400, 0.5, 400), Vector3.new(400, 0.5, 400),
				Vector3.new(0, 0.5, -400), Vector3.new(0, 0.5, 400),
				Vector3.new(-400, 0.5, 0), Vector3.new(400, 0.5, 0),
				Vector3.new(-200, 0.5, -600), Vector3.new(200, 0.5, 600),
				Vector3.new(-600, 0.5, 200), Vector3.new(600, 0.5, -200),
				Vector3.new(-150, 0.5, -150), Vector3.new(150, 0.5, 150),
			}
			else {
				Vector3.new(-400, 0.5, -400), Vector3.new(400, 0.5, 400),
				Vector3.new(0, 0.5, -400), Vector3.new(-400, 0.5, 0),
				Vector3.new(200, 0.5, 200), Vector3.new(-200, 0.5, 600),
				Vector3.new(600, 0.5, -200), Vector3.new(-150, 0.5, -150),
			}
		for i, origin in ipairs(roadSpots) do
			local yaw = (i * 41) % 180
			-- Crater scorch plate
			p({
				Name = "RoadCrater" .. i,
				Size = Vector3.new(10 + (i % 4), 0.18, 8 + (i % 3)),
				CFrame = CFrame.new(origin + Vector3.new(0, 0.04, 0)),
				Color = Color3.fromRGB(40, 36, 30),
				Material = Enum.Material.Asphalt,
				CanCollide = false,
				Parent = f,
			})
			p({
				Name = "RoadCraterRim" .. i,
				Size = Vector3.new(3.5, 0.8, 3.5),
				Position = origin + Vector3.new(2, 0.3, -1),
				Color = COL.Ruin,
				Material = Enum.Material.Slate,
				CanCollide = true,
				CanQuery = true,
				Parent = f,
			})
			kitSandbagLine(f, origin + Vector3.new(6, 0, 2), yaw, if full then 4 else 2)
			-- Chevron road marking (military approach stripe)
			p({
				Name = "RoadChevron" .. i,
				Size = Vector3.new(6, 0.12, 1.4),
				CFrame = CFrame.new(origin + Vector3.new(-4, 0.08, 0)) * CFrame.Angles(0, math.rad(yaw), 0),
				Color = Color3.fromRGB(230, 200, 80),
				Material = Enum.Material.Neon,
				CanCollide = false,
				Parent = f,
			})
			if full or i % 2 == 0 then
				kitCrateStack(f, origin + Vector3.new(-8, 0, 5))
			end
			if full and i % 3 == 0 then
				kitOilDrums(f, origin + Vector3.new(5, 0, -6), 2)
			end
		end
	end


	-- 15) P0 — Road rhythm: asphalt strips + jersey + chevrons at junctions
	do
		local f = Instance.new("Folder")
		f.Name = "RoadRhythm_P0"
		f.Parent = dressing
		-- Junction pads (road rhythm rule: RoadSign + LightPole + 2 jersey + chevrons)
		local junctions = if full
			then {
				{ Pos = Vector3.new(0, 0.5, -400), Yaw = 0 },
				{ Pos = Vector3.new(0, 0.5, 400), Yaw = 180 },
				{ Pos = Vector3.new(-400, 0.5, 0), Yaw = -90 },
				{ Pos = Vector3.new(400, 0.5, 0), Yaw = 90 },
				{ Pos = Vector3.new(-800, 0.5, 0), Yaw = -90 },
				{ Pos = Vector3.new(800, 0.5, 0), Yaw = 90 },
				{ Pos = Vector3.new(0, 0.5, -800), Yaw = 0 },
				{ Pos = Vector3.new(0, 0.5, 800), Yaw = 180 },
				{ Pos = Vector3.new(-400, 0.5, -400), Yaw = 45 },
				{ Pos = Vector3.new(400, 0.5, 400), Yaw = -45 },
			}
			else {
				{ Pos = Vector3.new(0, 0.5, -400), Yaw = 0 },
				{ Pos = Vector3.new(400, 0.5, 0), Yaw = 90 },
				{ Pos = Vector3.new(0, 0.5, 800), Yaw = 180 },
				{ Pos = Vector3.new(-800, 0.5, 0), Yaw = -90 },
			}
		for i, j in ipairs(junctions) do
			if not tooCloseToGameplay(j.Pos, 30) then
				kitAsphaltStrip(f, j.Pos, j.Yaw, 36, 14)
				kitChevronWedges(f, j.Pos + Vector3.new(0, 0, 0), j.Yaw)
				-- Jersey pair (staggered), never wall-to-wall
				kitJersey(f, j.Pos + Vector3.new(10, 0, 6), j.Yaw)
				kitJersey(f, j.Pos + Vector3.new(-10, 0, -6), j.Yaw + 180)
				if i % 2 == 1 then
					kitRoadSign(f, j.Pos + Vector3.new(14, 0, 0), j.Yaw)
				end
				if full or i % 2 == 0 then
					kitLightPole(f, j.Pos + Vector3.new(-14, 0, 8))
				end
			end
		end
		-- Mid-segment jersey every ~20 studs along plot ring roads (sparse)
		local shoulder = if full
			then {
				Vector3.new(22, 0.5, -200), Vector3.new(-22, 0.5, 200),
				Vector3.new(200, 0.5, 22), Vector3.new(-200, 0.5, -22),
				Vector3.new(22, 0.5, -600), Vector3.new(-22, 0.5, 600),
				Vector3.new(600, 0.5, 22), Vector3.new(-600, 0.5, -22),
				Vector3.new(22, 0.5, -1000), Vector3.new(-22, 0.5, 1000),
				Vector3.new(1000, 0.5, 22), Vector3.new(-1000, 0.5, -22),
			}
			else {
				Vector3.new(22, 0.5, -200), Vector3.new(200, 0.5, 22),
				Vector3.new(22, 0.5, -600), Vector3.new(600, 0.5, 22),
				Vector3.new(-22, 0.5, 600), Vector3.new(-600, 0.5, -22),
			}
		for _, origin in ipairs(shoulder) do
			if not tooCloseToGameplay(origin, 25) then
				local yaw = if math.abs(origin.X) > math.abs(origin.Z) then 90 else 0
				kitJersey(f, origin, yaw)
			end
		end
		-- Contested HESCO shoulders (Full only)
		if full then
			local hescoSpots = {
				Vector3.new(180, 0.5, -180), Vector3.new(-180, 0.5, 180),
				Vector3.new(320, 0.5, 280), Vector3.new(-320, 0.5, -280),
			}
			for i, origin in ipairs(hescoSpots) do
				if not tooCloseToGameplay(origin, 28) then
					kitHesco(f, origin, i * 40)
				end
			end
		end
	end

	-- 16) P0 — Horizon mesa + flora densify + desert rocks
	do
		local f = Instance.new("Folder")
		f.Name = "Horizon_P0"
		f.Parent = dressing
		local mesas = if full
			then {
				{ Pos = Vector3.new(2200, 2, 1800), Yaw = 225 },
				{ Pos = Vector3.new(-2200, 2, 1800), Yaw = -45 },
				{ Pos = Vector3.new(2200, 2, -1800), Yaw = 135 },
				{ Pos = Vector3.new(-2200, 2, -1800), Yaw = 45 },
				{ Pos = Vector3.new(0, 4, 2400), Yaw = 180 },
				{ Pos = Vector3.new(0, 4, -2400), Yaw = 0 },
				{ Pos = Vector3.new(2400, 3, 0), Yaw = -90 },
				{ Pos = Vector3.new(-2400, 3, 0), Yaw = 90 },
			}
			else {
				{ Pos = Vector3.new(2200, 2, 1800), Yaw = 225 },
				{ Pos = Vector3.new(-2200, 2, -1800), Yaw = 45 },
				{ Pos = Vector3.new(0, 4, 2400), Yaw = 180 },
				{ Pos = Vector3.new(2400, 3, 0), Yaw = -90 },
			}
		for _, m in ipairs(mesas) do
			kitMesaHost(f, m.Pos, m.Yaw)
			kitDesertRockScatter(f, m.Pos + Vector3.new(35, 0, 20))
			kitDesertRockScatter(f, m.Pos + Vector3.new(-30, 0, -25))
		end
		-- Far-ring palm hosts (catalog Palm / PalmAlt) every ~150–200 studs on rim sample
		local palmRim = if full then 10 else 6
		for i = 1, palmRim do
			local ang = (i / palmRim) * math.pi * 2
			local r = 2100 + ((i * 47) % 80)
			local pos = Vector3.new(math.cos(ang) * r, 0.5, math.sin(ang) * r)
			local host = p({
				Name = "PalmHorizonHost" .. i,
				Size = Vector3.new(2, 10, 2),
				Position = pos + Vector3.new(0, 5, 0),
				Transparency = 1,
				CanCollide = false,
				Parent = f,
			})
			tryPropAttach(host, "Palm")
		end
		-- Off-road flora clusters every ~100 studs (sampled)
		local floraSpots = if full
			then {
				Vector3.new(500, 0.5, 700), Vector3.new(-500, 0.5, -700),
				Vector3.new(700, 0.5, -500), Vector3.new(-700, 0.5, 500),
				Vector3.new(1100, 0.5, 400), Vector3.new(-1100, 0.5, -400),
				Vector3.new(400, 0.5, 1100), Vector3.new(-400, 0.5, -1100),
				Vector3.new(1500, 0.5, -300), Vector3.new(-1500, 0.5, 300),
			}
			else {
				Vector3.new(500, 0.5, 700), Vector3.new(-500, 0.5, -700),
				Vector3.new(1100, 0.5, 400), Vector3.new(-1100, 0.5, -400),
			}
		for _, origin in ipairs(floraSpots) do
			if not tooCloseToGameplay(origin, 30) then
				kitFloraCluster(f, origin)
				kitDesertRockScatter(f, origin + Vector3.new(12, 0, -8))
			end
		end
	end

	-- 17) P1 — Warzone fill (wrecks / ruins / camo / lights) — skip if near capture
	do
		local f = Instance.new("Folder")
		f.Name = "WarzoneFill_P1"
		f.Parent = dressing
		-- Wreck sites: existing (-350,-450) + new quadrants
		local wrecks = if full
			then {
				{ Pos = Vector3.new(-350, 0.5, -450), Yaw = 25 },
				{ Pos = Vector3.new(400, 0.5, 500), Yaw = 110 },
				{ Pos = Vector3.new(-800, 0.5, 300), Yaw = -30 },
				{ Pos = Vector3.new(900, 0.5, -700), Yaw = 70 },
			}
			else {
				{ Pos = Vector3.new(-350, 0.5, -450), Yaw = 25 },
				{ Pos = Vector3.new(400, 0.5, 500), Yaw = 110 },
			}
		for _, w in ipairs(wrecks) do
			if not tooCloseToGameplay(w.Pos, 30) then
				kitWreckSite(f, w.Pos, w.Yaw)
			end
		end
		local ruins = if full
			then {
				{ Pos = Vector3.new(250, 0.5, -700), Yaw = 20 },
				{ Pos = Vector3.new(-600, 0.5, 250), Yaw = 100 },
				{ Pos = Vector3.new(700, 0.5, 350), Yaw = -40 },
				{ Pos = Vector3.new(-300, 0.5, 750), Yaw = 160 },
			}
			else {
				{ Pos = Vector3.new(250, 0.5, -700), Yaw = 20 },
				{ Pos = Vector3.new(-600, 0.5, 250), Yaw = 100 },
			}
		for _, r in ipairs(ruins) do
			if not tooCloseToGameplay(r.Pos, 30) then
				kitRuinLandmark(f, r.Pos, r.Yaw)
			end
		end
		local camoSpots = if full
			then {
				Vector3.new(150, 0.5, -350), Vector3.new(-150, 0.5, 350),
				Vector3.new(450, 0.5, -150), Vector3.new(-450, 0.5, 150),
				Vector3.new(50, 0.5, -900), Vector3.new(-50, 0.5, 900),
			}
			else {
				Vector3.new(150, 0.5, -350), Vector3.new(-450, 0.5, 150),
				Vector3.new(50, 0.5, -900),
			}
		for _, origin in ipairs(camoSpots) do
			if not tooCloseToGameplay(origin, 28) then
				kitCamoOverCrates(f, origin)
			end
		end
		local lights = if full
			then {
				Vector3.new(100, 0.5, -1100), Vector3.new(-100, 0.5, 1100),
				Vector3.new(1100, 0.5, 100), Vector3.new(-1100, 0.5, -100),
				Vector3.new(850, 0.5, 850), Vector3.new(-850, 0.5, -850),
			}
			else {
				Vector3.new(100, 0.5, -1100), Vector3.new(1100, 0.5, 100),
			}
		for _, origin in ipairs(lights) do
			if not tooCloseToGameplay(origin, 28) then
				kitPortableLight(f, origin, full)
			end
		end
		-- Overlay CamoNet on vehicle DISPLAY silhouettes in RoadFurniture (Full)
		if full then
			for _, d in ipairs(dressing:GetDescendants()) do
				if d:IsA("BasePart") and (d.Name == "DecoyBody" or d.Name == "DecoyHull") then
					local parent = d.Parent
					if parent and parent:IsA("Folder") then
						local net = p({
							Name = "CamoNetOverVehicle",
							Size = Vector3.new(6, 0.8, 8),
							CFrame = d.CFrame * CFrame.new(0, 4, 0),
							Transparency = 0.5,
							CanCollide = false,
							Color = COL.OliveDark,
							Material = Enum.Material.Fabric,
							Parent = parent,
						})
						tryPropAttach(net, "CamoNet")
						break -- one sample only (perf)
					end
				end
			end
		end
	end


	local partCount = 0
	for _, d in ipairs(dressing:GetDescendants()) do
		if d:IsA("BasePart") then
			partCount += 1
			d.CastShadow = false
		end
	end
	print("[WAR EMPIRE] MapDressing complete: quality=" .. quality .. " parts=" .. tostring(partCount) .. " densify=P0+P1 (CastShadow=false)")
end

return MapDressing
