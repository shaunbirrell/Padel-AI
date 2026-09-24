--!strict
--[[
	WAR EMPIRE — DesertFlora (procedural Part-kit vegetation)
	Saguaro / Joshua / palm / barrel cactus / dry grass tufts.
	Inspiration-only desert tycoon look — original Part kits, mobile-friendly counts.
	Called from MapSetup.Run after MapDressing (deferred).
	CanCollide false; CastShadow false on ALL flora (Studio/laptop perf).
	Sparse mode default — ~70% fewer plants than prior dense pass.
	v70 waterways (spec_final §9): no plant in the water or on a plot pad (spots there are skipped whole);
	Waterways.CullDressing is the safety net at the end.
	World v2 W1 (spec §1.6, roadmap §2.2 WORLD-A): the rim ring (r ~3020, now inside the Terrain canyon) and the lone
	Palm_Mid_* palms are gone; WorldHygiene.Enforce runs over DesertFlora after the cull.
]]

local DesertFlora = {}

local GROUND_TOP_Y = 0.5

local COL = {
	Cactus = Color3.fromRGB(62, 110, 58),
	CactusDark = Color3.fromRGB(48, 88, 48),
	CactusLight = Color3.fromRGB(78, 130, 72),
	JoshuaTrunk = Color3.fromRGB(95, 78, 52),
	JoshuaLeaf = Color3.fromRGB(70, 95, 45),
	PalmTrunk = Color3.fromRGB(110, 85, 55),
	PalmLeaf = Color3.fromRGB(55, 120, 55),
	Barrel = Color3.fromRGB(72, 105, 55),
	Grass = Color3.fromRGB(150, 130, 70),
	GrassDry = Color3.fromRGB(170, 145, 85),
	Rock = Color3.fromRGB(160, 110, 75),
}

-- World v2 W1: Modules/WorldHygiene (rules H1–H10), loaded lazily and guarded like Waterways
local hygieneMod: any = nil
local function getWorldHygiene(): any?
	if hygieneMod == nil then
		local ok, m = pcall(function(): any
			local mod = script.Parent:FindFirstChild("WorldHygiene")
			return if mod and mod:IsA("ModuleScript") then require(mod) :: any else nil
		end)
		hygieneMod = if ok and type(m) == "table" then m else false
		if not ok then
			warn("[DesertFlora] WorldHygiene unavailable:", m)
		end
	end
	return if hygieneMod then hygieneMod else nil
end

-- v70: Modules/Waterways (water rects + dressing cull), loaded lazily so a Waterways error never blocks MapSetup
local waterwaysMod: any = nil
local function getWaterways(): any?
	if waterwaysMod == nil then
		local ok, m = pcall(function(): any
			return require(script.Parent.Waterways) :: any
		end)
		waterwaysMod = if ok and type(m) == "table" then m else false
	end
	return if waterwaysMod then waterwaysMod else nil
end

local function onWaterOrPlot(pos: Vector3, margin: number): boolean
	local ww = getWaterways()
	if not ww then
		return false
	end
	local ok, res = pcall(function(): boolean
		return ww.IsWaterXZ(pos.X, pos.Z, margin) or ww.IsOnPlotPadXZ(pos.X, pos.Z, margin)
	end)
	return ok and res == true
end

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
	part.CanQuery = false
	part.CanTouch = false
	part.CastShadow = if props.CastShadow ~= nil then props.CastShadow else false -- deco: never cast shadows (Studio perf)
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
	part:SetAttribute("WE_Flora", true)
	return part
end

local function kitSaguaro(folder: Folder, origin: Vector3, scale: number?)
	local s = scale or 1
	local h = 10 * s
	p({
		Name = "SaguaroTrunk",
		Size = Vector3.new(1.4 * s, h, 1.4 * s),
		Position = origin + Vector3.new(0, h * 0.5, 0),
		Color = COL.Cactus,
		Material = Enum.Material.SmoothPlastic,
		Parent = folder,
	})
	-- Arms
	local armY = h * 0.55
	p({
		Name = "SaguaroArmL",
		Size = Vector3.new(0.9 * s, 4.2 * s, 0.9 * s),
		CFrame = CFrame.new(origin + Vector3.new(-1.6 * s, armY + 1.2 * s, 0)),
		Color = COL.CactusDark,
		Material = Enum.Material.SmoothPlastic,
		Parent = folder,
	})
	p({
		Name = "SaguaroElbowL",
		Size = Vector3.new(2.2 * s, 0.85 * s, 0.85 * s),
		Position = origin + Vector3.new(-0.9 * s, armY, 0),
		Color = COL.Cactus,
		Material = Enum.Material.SmoothPlastic,
		Parent = folder,
	})
	if s > 0.85 then
		p({
			Name = "SaguaroArmR",
			Size = Vector3.new(0.85 * s, 3.4 * s, 0.85 * s),
			Position = origin + Vector3.new(1.5 * s, armY + 0.6 * s, 0.2 * s),
			Color = COL.CactusLight,
			Material = Enum.Material.SmoothPlastic,
			Parent = folder,
		})
		p({
			Name = "SaguaroElbowR",
			Size = Vector3.new(2.0 * s, 0.8 * s, 0.8 * s),
			Position = origin + Vector3.new(0.85 * s, armY - 0.4 * s, 0.2 * s),
			Color = COL.Cactus,
			Material = Enum.Material.SmoothPlastic,
			Parent = folder,
		})
	end
end

local function kitJoshua(folder: Folder, origin: Vector3, scale: number?)
	local s = scale or 1
	local trunkH = 7 * s
	p({
		Name = "JoshuaTrunk",
		Size = Vector3.new(1.1 * s, trunkH, 1.1 * s),
		Position = origin + Vector3.new(0, trunkH * 0.5, 0),
		Color = COL.JoshuaTrunk,
		Material = Enum.Material.Wood,
		Parent = folder,
	})
	-- Forked branches + spiky leaf clusters
	local forks = {
		{ 1.8, 0.6, 0.4, 25 },
		{ -1.6, 0.4, -0.5, -30 },
		{ 0.3, 1.0, 1.5, 10 },
	}
	for i, f in ipairs(forks) do
		local bx, by, bz, yaw = f[1] * s, trunkH * 0.55 + f[2] * s, f[3] * s, f[4]
		p({
			Name = "JoshuaFork" .. i,
			Size = Vector3.new(0.7 * s, 3.2 * s, 0.7 * s),
			CFrame = CFrame.new(origin + Vector3.new(bx, by + 1.2 * s, bz)) * CFrame.Angles(0, math.rad(yaw), math.rad(18)),
			Color = COL.JoshuaTrunk,
			Material = Enum.Material.Wood,
			Parent = folder,
		})
		p({
			Name = "JoshuaLeaf" .. i,
			Size = Vector3.new(2.4 * s, 0.35 * s, 2.4 * s),
			Position = origin + Vector3.new(bx, by + 2.8 * s, bz),
			Color = COL.JoshuaLeaf,
			Material = Enum.Material.Grass,
			Parent = folder,
		})
	end
end

local function kitPalm(folder: Folder, origin: Vector3, scale: number?)
	local s = scale or 1
	local trunkH = 12 * s
	p({
		Name = "PalmTrunk",
		Size = Vector3.new(1.2 * s, trunkH, 1.2 * s),
		Position = origin + Vector3.new(0, trunkH * 0.5, 0),
		Color = COL.PalmTrunk,
		Material = Enum.Material.Wood,
		Parent = folder,
	})
	-- Fronds as radial slabs
	for i = 0, 5 do
		local ang = i * 60
		p({
			Name = "PalmFrond" .. i,
			Size = Vector3.new(0.35 * s, 0.25 * s, 5.5 * s),
			CFrame = CFrame.new(origin + Vector3.new(0, trunkH + 0.2 * s, 0))
				* CFrame.Angles(0, math.rad(ang), 0)
				* CFrame.new(0, 0, -2.2 * s)
				* CFrame.Angles(math.rad(-25), 0, 0),
			Color = COL.PalmLeaf,
			Material = Enum.Material.Grass,
			Parent = folder,
		})
	end
	p({
		Name = "PalmCrown",
		Size = Vector3.new(1.6 * s, 1.0 * s, 1.6 * s),
		Position = origin + Vector3.new(0, trunkH + 0.4 * s, 0),
		Color = COL.PalmLeaf,
		Material = Enum.Material.Grass,
		Parent = folder,
	})
end

local function kitBarrel(folder: Folder, origin: Vector3, scale: number?)
	local s = scale or 1
	p({
		Name = "BarrelBody",
		Size = Vector3.new(2.4 * s, 2.2 * s, 2.4 * s),
		CFrame = CFrame.new(origin + Vector3.new(0, 1.1 * s, 0)) * CFrame.Angles(0, 0, math.rad(90)),
		Color = COL.Barrel,
		Material = Enum.Material.SmoothPlastic,
		Shape = Enum.PartType.Cylinder,
		Parent = folder,
	})
	p({
		Name = "BarrelTop",
		Size = Vector3.new(1.6 * s, 0.5 * s, 1.6 * s),
		Position = origin + Vector3.new(0, 2.3 * s, 0),
		Color = COL.CactusLight,
		Material = Enum.Material.SmoothPlastic,
		Parent = folder,
	})
end

local function kitGrassTuft(folder: Folder, origin: Vector3)
	for i = 0, 2 do
		local ox = (i - 1) * 0.55
		p({
			Name = "GrassBlade",
			Size = Vector3.new(0.25, 1.4 + (i % 2) * 0.5, 0.25),
			CFrame = CFrame.new(origin + Vector3.new(ox, 0.9, (i % 2) * 0.3))
				* CFrame.Angles(0, math.rad(i * 40), math.rad(8)),
			Color = if i % 2 == 0 then COL.Grass else COL.GrassDry,
			Material = Enum.Material.Grass,
			CastShadow = false,
			Parent = folder,
		})
	end
end

local function kitRockOutcrop(folder: Folder, origin: Vector3, scale: number?)
	local s = scale or 1
	p({
		Name = "Outcrop",
		Size = Vector3.new(8 * s, 3.5 * s, 6 * s),
		Position = origin + Vector3.new(0, 1.6 * s, 0),
		Color = COL.Rock,
		Material = Enum.Material.Sandstone,
		CanCollide = true,
		Parent = folder,
	})
	p({
		Name = "OutcropCap",
		Size = Vector3.new(5 * s, 1.8 * s, 4 * s),
		Position = origin + Vector3.new(1.2 * s, 3.8 * s, -0.5 * s),
		Color = COL.Rock:Lerp(Color3.fromRGB(180, 130, 90), 0.3),
		Material = Enum.Material.Sandstone,
		CanCollide = false,
		Parent = folder,
	})
end

local function placeAt(folder: Folder, name: string, pos: Vector3, builder: (Folder, Vector3, number?) -> (), scale: number?)
	if onWaterOrPlot(pos, 6) then
		return -- v70: never a plant in the water or on a plot pad
	end
	local cluster = Instance.new("Folder")
	cluster.Name = name
	cluster.Parent = folder
	builder(cluster, pos, scale)
end

-- World v2 (spec §8.2): the Part kits stay, exported for Phase 2 (WorldKits: oasis palms, natural scatter). Each builds
-- one plant into `folder` at `origin` (ground level) with an optional scale.
DesertFlora.Kits = {
	Saguaro = kitSaguaro,
	Joshua = kitJoshua,
	Palm = kitPalm,
	Barrel = kitBarrel,
	GrassTuft = kitGrassTuft,
	RockOutcrop = kitRockOutcrop,
}

function DesertFlora.Dress(root: Instance, opts: { Sparse: boolean? }?)
	local flora = ensureFolder("DesertFlora", root)
	local sparse = if opts and opts.Sparse ~= nil then opts.Sparse else true

	-- PERF: sparse by default. CastShadow=false on all flora parts (see p()).
	-- World v2 W1 (spec §1.6): no rim ring (r ~3020 is inside the Terrain canyon, past the ground wall)

	-- Mid-map: drastically cut (was 10 dual plants → 2–4 singles)
	local midSpots = if sparse
		then {
			Vector3.new(480, GROUND_TOP_Y, 520),
			Vector3.new(900, GROUND_TOP_Y, -900),
		}
		else {
			Vector3.new(350, GROUND_TOP_Y, 180),
			Vector3.new(180, GROUND_TOP_Y, -480),
			Vector3.new(620, GROUND_TOP_Y, -80),
			Vector3.new(480, GROUND_TOP_Y, 520),
			Vector3.new(1100, GROUND_TOP_Y, 200),
			Vector3.new(900, GROUND_TOP_Y, -900),
		}
	for i, pos in ipairs(midSpots) do
		-- World v2 W1 (spec §1.6): the lone Palm_Mid_* palms on open sand are gone (palms return at the Oasis POI)
		if i % 2 == 0 then
			placeAt(flora, "Saguaro_Mid_" .. i, pos, kitSaguaro, 1.0)
		end
		if not sparse and i == 1 then
			placeAt(flora, "Rock_Mid_" .. i, pos + Vector3.new(10, 0, -8), kitRockOutcrop, 0.9)
			local tuft = Instance.new("Folder")
			tuft.Name = "Grass_Mid_" .. i
			tuft.Parent = flora
			kitGrassTuft(tuft, pos + Vector3.new(-6, 0, 5))
		end
	end

	-- v70: the plot-adjacent palms (Palm_Plot_*, plot + (110, 0, 40)) are gone: at the 320 layout they stood inside the
	-- east building row of the base.

	-- Catalog overlays: DesertPlants / Palm(+PalmAlt) / Cactus / DesertRock MeshPart
	-- Cap attempts so PERF stays Part-kit-first even on live.
	do
		local attached = 0
		local maxAttach = if sparse then 6 else 18
		local okVas, vas = pcall(function()
			return require(script.Parent.Parent.Services.VisualAssetService)
		end)
		if okVas and vas and vas.IsInsertEnabled and vas.IsInsertEnabled() then
			for _, d in ipairs(flora:GetDescendants()) do
				if attached >= maxAttach then
					break
				end
				if d:IsA("BasePart") then
					local key: string? = nil
					if d.Name == "SaguaroTrunk" then
						key = if attached % 3 == 0 then "DesertPlants" elseif attached % 3 == 1 then "Cactus" else "CactusBase"
					elseif d.Name == "PalmTrunk" then
						key = "Palm" -- PalmAlt fallback inside TryAttachPropVisual
					elseif d.Name == "Outcrop" or d.Name == "OutcropCap" then
						key = "DesertRock"
					end
					if key then
						local okAtt = pcall(function()
							return vas.TryAttachPropVisual(d, key :: string)
						end)
						if okAtt then
							attached += 1
						end
					end
				end
			end
			if attached > 0 then
				print("[WAR EMPIRE] DesertFlora catalog props attached:", attached)
			end
		end
	end

	-- v70 safety net (spec §9.12): nothing in the water or on a plot pad
	local ww = getWaterways()
	if ww then
		local okCull, res = pcall(ww.CullDressing, flora)
		if not okCull then
			warn("[DesertFlora] water cull failed:", res)
		end
	end

	-- World v2 W1: hygiene rules over what is left (spec §5.1; logs one summary line)
	local wh = getWorldHygiene()
	if wh then
		local okHy, errHy = pcall(wh.Enforce, flora)
		if not okHy then
			warn("[DesertFlora] WorldHygiene.Enforce failed:", errHy)
		end
	end

	local partCount = 0
	for _, d in ipairs(flora:GetDescendants()) do
		if d:IsA("BasePart") then
			partCount += 1
			d.CastShadow = false
		end
	end
	print("[WAR EMPIRE] DesertFlora complete: " .. tostring(partCount) .. " flora parts (sparse=" .. tostring(sparse) .. ", CastShadow=false)")
end

return DesertFlora
