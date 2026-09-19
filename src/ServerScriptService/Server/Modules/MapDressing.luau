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
	p({
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

	-- 12) Plot-ring perimeter (Low: 3 edges)
	do
		local f = Instance.new("Folder")
		f.Name = "PlotRingPerimeter"
		f.Parent = dressing
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
	end

	local partCount = 0
	for _, d in ipairs(dressing:GetDescendants()) do
		if d:IsA("BasePart") then
			partCount += 1
			d.CastShadow = false
		end
	end
	print("[WAR EMPIRE] MapDressing complete: quality=" .. quality .. " parts=" .. tostring(partCount) .. " (CastShadow=false)")
end

return MapDressing
