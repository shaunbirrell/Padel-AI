--!strict
--[[
	WAR EMPIRE — MapDressing (the world outside the bases)
	Called from MapSetup.Run after bases / territories / spawns (deferred). Studio usually SKIPS it
	(DevConfig.StudioSkipWorldDressing) — the ForceDress attribute opts in. Regenerate: delete WarEmpireSetup + Play, or
	admin resetmap.

	World v2 W3 (gap/world_v2_spec.md §4, roadmap §2.4 WORLD-B builder 2): every prop now belongs to a place. Dress runs,
	in this order, each step guarded so a failure warns and the rest still builds:
	  1. WorldPOI.Build     — the named places (every enabled POI in WorldConfig.POIs), WorldDressing.POI_<Id>
	  2. DocksideDressing   — the legacy South Docks quay kit, as-is while the Port POI is off (inside the Port
	                          footprint); W3 step 2: once WorldPOI has built the Port, the quay kit is not built at all
	  3. WorldDress.Build   — the travel dressing between the places: road rhythm, junction kits, canal / shore features,
	                          natural scatter (WorldDressing.Rhythm / Junctions / Shore / Scatter)
	  4. Waterways.CullDressing — the safety net (nothing in the water, on a plot pad or in a road lane)
	  5. WorldHygiene.Enforce   — rules H1–H10 (H1 orphans are destroyed in W3)
	The old coordinate-list sections (checkpoints, outposts, hangars, depots, camps, road furniture, landmarks, warzone
	fills, plot densify, horizon hosts) and every third-party catalog host are gone.
	Quality (MapSetup: live = "Full"; Studio = DevConfig.WorldDressQuality): "Low" = POIs at 60 %, every other road
	rhythm cluster, no scatter (WorldDressConfig.Quality).
	v70 waterways (spec_final §9): nothing stands in the water or on a plot pad; WE_AllowInWater exempts the harbour piers.
]]

local MapDressing = {}

-- v70: Modules/Waterways (water rects + dressing cull), loaded lazily so a Waterways error never blocks MapSetup
local waterwaysMod: any = nil
local function getWaterways(): any?
	if waterwaysMod == nil then
		local ok, m = pcall(function(): any
			return require(script.Parent.Waterways) :: any
		end)
		waterwaysMod = if ok and type(m) == "table" then m else false
		if not ok then
			warn("[MapDressing] Waterways unavailable:", m)
		end
	end
	return if waterwaysMod then waterwaysMod else nil
end

-- World v2 W1: Modules/WorldHygiene (rules H1–H10), loaded lazily and guarded like Waterways: a missing module or an
-- error never stops the dressing
local hygieneMod: any = nil
local function getWorldHygiene(): any?
	if hygieneMod == nil then
		local ok, m = pcall(function(): any
			local mod = script.Parent:FindFirstChild("WorldHygiene")
			return if mod and mod:IsA("ModuleScript") then require(mod) :: any else nil
		end)
		hygieneMod = if ok and type(m) == "table" then m else false
		if not ok then
			warn("[MapDressing] WorldHygiene unavailable:", m)
		end
	end
	return if hygieneMod then hygieneMod else nil
end

-- World v2 W3: WorldPOI / WorldDress / WorldKits, each loaded lazily inside pcall like Waterways (a missing module or a
-- require error warns once and that step is skipped; the rest of the dressing still builds)
local worldMods: { [string]: any } = {}
local function getWorldModule(name: string): any?
	local cached = worldMods[name]
	if cached == nil then
		local ok, m = pcall(function(): any
			local mod = script.Parent:FindFirstChild(name)
			return if mod and mod:IsA("ModuleScript") then require(mod) :: any else nil
		end)
		cached = if ok and type(m) == "table" then m else false
		worldMods[name] = cached
		if not ok then
			warn("[MapDressing] " .. name .. " unavailable:", m)
		end
	end
	return if cached then cached else nil
end

-- Palette of the Dockside kits (aligned with StructureVisualConfig / MapSetup)
local COL = {
	ConcreteDark = Color3.fromRGB(60, 60, 55),
	Metal = Color3.fromRGB(58, 72, 88),
	MetalDark = Color3.fromRGB(45, 50, 55),
	Olive = Color3.fromRGB(70, 78, 55),
	OliveDark = Color3.fromRGB(50, 55, 42),
	Sand = Color3.fromRGB(150, 130, 90),
	Sandbag = Color3.fromRGB(130, 115, 80),
	Fuel = Color3.fromRGB(180, 140, 50),
	Ammo = Color3.fromRGB(88, 58, 50),
	NeonGold = Color3.fromRGB(230, 190, 60),
	NeonOrange = Color3.fromRGB(220, 140, 60),
	NeonRed = Color3.fromRGB(200, 90, 70),
	Crate = Color3.fromRGB(95, 80, 55),
	Drum = Color3.fromRGB(70, 85, 55),
	DrumAccent = Color3.fromRGB(200, 90, 50),
	Vehicle = Color3.fromRGB(55, 65, 48),
	VehicleAccent = Color3.fromRGB(90, 140, 70),
	Light = Color3.fromRGB(255, 230, 160),
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

-- W3 step 2 (spec w3s2 §6 lane P): the POI that replaces the Dockside quay kit once WorldPOI has built it
local DOCKSIDE_POI = "Port"


-- ── Dockside kits (legacy, as-is until the Port POI step; World v2 W3 kept only what DocksideDressing uses) ──

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

-- ── Dress ─────────────────────────────────────────────────────────────────────────────────────────────────────────

-- Builds WarEmpireSetup.WorldDressing (replaces an old one; idempotent). opts.Quality: "Full" | "Low" (default Low).
function MapDressing.Dress(root: Instance, opts: { Quality: string? }?)
	local requested = tostring((opts and opts.Quality) or "Low")
	local wd = getWorldModule("WorldDress")
	local quality: string = if string.lower(requested) == "full" then "Full" else "Low"
	if wd then
		local okQ, q = pcall(wd.Quality, requested)
		if okQ and type(q) == "string" then
			quality = q
		end
	end
	local full = quality == "Full"
	local dressing = ensureFolder("WorldDressing", root)

	-- the terrain rock log restarts with every build (the sim dumps it; live fills Workspace.Terrain once per rock)
	local wk = getWorldModule("WorldKits")
	if wk then
		local okT, errT = pcall(wk.ResetTerrainLog)
		if not okT then
			warn("[MapDressing] WorldKits.ResetTerrainLog failed:", errT)
		end
	end

	-- one occupancy (keep-outs + every placed cluster) shared by the POIs and the travel dressing
	local occ: any = nil
	if wd then
		local okO, o = pcall(function(): any
			return wd.NewOccupancy(wd.Zones())
		end)
		if okO then
			occ = o
		else
			warn("[MapDressing] WorldDress keep-outs failed:", o)
		end
	end

	-- 1) POIs (every enabled place; W3 step 2 adds the 17 layouts as their enable steps flip them on)
	local wp = getWorldModule("WorldPOI")
	local portBuilt = false
	if wp then
		local okP, errP = pcall(wp.Build, dressing, quality, occ)
		if not okP then
			warn("[MapDressing] WorldPOI.Build failed:", errP)
		elseif type(errP) == "table" and type(errP.POIs) == "table" then
			for _, row in ipairs(errP.POIs) do
				if type(row) == "table" and row.Id == DOCKSIDE_POI and row.Built == true then
					portBuilt = true
				end
			end
		end
	end

	-- 2) the legacy quay kit, as-is (inside the reserved Port footprint) — only while the Port POI is not built
	-- 7) Dockside — v70: re-laid round the South Docks harbour (water x -240..240, z 1364..1490). Piers stand in the
	-- harbour off the quay (WE_AllowInWater); crates / drums / lights on the quay (z 1330..1360) beside them, never in
	-- front of a pier. Piers at x -220 / -185 / 185 / 220 stay clear of the capture lens (|x| <= 56), the slips
	-- (|x| 64..108) and P4's channel mouth (x -148..-108). Low: 2 piers; Full: 4.
	if not portBuilt then
		local f = Instance.new("Folder")
		f.Name = "DocksideDressing"
		f.Parent = dressing
		local pierXs = if full then { -220, -185, 185, 220 } else { -185, 185 }
		for i, x in ipairs(pierXs) do
			local pier = p({
				Name = "Pier" .. i,
				Size = Vector3.new(10, 1.2, 36),
				Position = Vector3.new(x, 2.0, 1382), -- z 1364..1400, deck top 2.6
				Color = COL.Dock,
				Material = Enum.Material.Wood,
				CanCollide = true,
				CanQuery = true,
				Parent = f,
			})
			pier:SetAttribute("WE_AllowInWater", true)
			kitCrateStack(f, Vector3.new(x - 12, 0.5, 1350))
			if full then
				kitOilDrums(f, Vector3.new(x + 8, 0.5, 1340), 3)
				kitLightPole(f, Vector3.new(x + 7, 0.5, 1358))
			end
		end
		if full then
			kitAmmoShed(f, Vector3.new(-320, 0.5, 1380), 0)
			kitFuelDepot(f, Vector3.new(320, 0.5, 1380), 180)
			kitVehicleSilhouette(f, Vector3.new(170, 0.5, 1330), 0, "truck")
			kitSandbagLine(f, Vector3.new(0, 0.5, 1340), 0, 6)
		end
	end

	-- 3) travel dressing between the places: road rhythm, junction kits, canal / shore features, natural scatter
	if wd then
		local okD, errD = pcall(wd.Build, dressing, quality, occ)
		if not okD then
			warn("[MapDressing] WorldDress.Build failed:", errD)
		end
	end

	-- 4) v70 safety net (spec §9.12): nothing in the water or on a plot pad (WE_AllowInWater exempts the harbour piers)
	local culled = 0
	local ww = getWaterways()
	if ww then
		local okCull, res = pcall(ww.CullDressing, dressing)
		if okCull and type(res) == "number" then
			culled = res
		elseif not okCull then
			warn("[MapDressing] water cull failed:", res)
		end
	end

	-- 5) World v2 hygiene rules over what is left (spec §5.1; H1 orphans destroyed in W3; logs one summary line)
	local wh = getWorldHygiene()
	if wh then
		local okHy, errHy = pcall(wh.Enforce, dressing)
		if not okHy then
			warn("[MapDressing] WorldHygiene.Enforce failed:", errHy)
		end
	end

	-- CastShadow is governed by H9 (WorldKits sets it only on parts >= 8 studs; Enforce clears small casters)
	local partCount = 0
	for _, d in ipairs(dressing:GetDescendants()) do
		if d:IsA("BasePart") then
			partCount += 1
		end
	end
	print("[WAR EMPIRE] MapDressing complete: quality=" .. string.lower(quality) .. " parts=" .. tostring(partCount) .. " culled=" .. tostring(culled) .. " order=POI+Dockside+WorldDress")
end

return MapDressing
