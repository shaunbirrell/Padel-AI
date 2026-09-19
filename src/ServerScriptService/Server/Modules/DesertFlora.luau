--!strict
--[[
	WAR EMPIRE — DesertFlora (procedural Part-kit vegetation)
	Saguaro / Joshua / palm / barrel cactus / dry grass tufts.
	Inspiration-only desert tycoon look — original Part kits, mobile-friendly counts.
	Called from MapSetup.Run after MapDressing (deferred).
	CanCollide false; CastShadow false on ALL flora (Studio/laptop perf).
	Sparse mode default — ~70% fewer plants than prior dense pass.
]]

local DesertFlora = {}

local GROUND_TOP_Y = 0.5
local HALF = 3200 -- matches MapSetup GROUND_SIZE/2

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
	local cluster = Instance.new("Folder")
	cluster.Name = name
	cluster.Parent = folder
	builder(cluster, pos, scale)
end

function DesertFlora.Dress(root: Instance, opts: { Sparse: boolean? }?)
	local flora = ensureFolder("DesertFlora", root)
	local sparse = if opts and opts.Sparse ~= nil then opts.Sparse else true

	-- PERF: sparse by default. CastShadow=false on all flora parts (see p()).
	local rimCount = if sparse then 6 else 12
	local rimR = HALF - 180
	for i = 1, rimCount do
		local ang = (i / rimCount) * math.pi * 2
		local jitter = ((i * 37) % 50) - 25
		local r = rimR + jitter
		local pos = Vector3.new(math.cos(ang) * r, GROUND_TOP_Y, math.sin(ang) * r)
		local kind = i % 4
		if kind == 0 then
			placeAt(flora, "Saguaro_Rim_" .. i, pos, kitSaguaro, 0.9)
		elseif kind == 1 then
			placeAt(flora, "Joshua_Rim_" .. i, pos, kitJoshua, 0.95)
		elseif kind == 2 then
			placeAt(flora, "Palm_Rim_" .. i, pos, kitPalm, 0.8)
		else
			placeAt(flora, "Barrel_Rim_" .. i, pos, kitBarrel, 0.95)
		end
	end

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
		if i % 2 == 0 then
			placeAt(flora, "Saguaro_Mid_" .. i, pos, kitSaguaro, 1.0)
		else
			placeAt(flora, "Palm_Mid_" .. i, pos, kitPalm, 0.95)
		end
		if not sparse and i == 1 then
			placeAt(flora, "Rock_Mid_" .. i, pos + Vector3.new(10, 0, -8), kitRockOutcrop, 0.9)
			local tuft = Instance.new("Folder")
			tuft.Name = "Grass_Mid_" .. i
			tuft.Parent = flora
			kitGrassTuft(tuft, pos + Vector3.new(-6, 0, 5))
		end
	end

	-- Plot-adjacent flora: sparse = 2 palms only; full = 4
	local plotOffsets = if sparse
		then {
			Vector3.new(-800, GROUND_TOP_Y, -400),
			Vector3.new(800, GROUND_TOP_Y, 400),
		}
		else {
			Vector3.new(-800, GROUND_TOP_Y, -400),
			Vector3.new(-800, GROUND_TOP_Y, 400),
			Vector3.new(800, GROUND_TOP_Y, -400),
			Vector3.new(800, GROUND_TOP_Y, 400),
		}
	for i, pos in ipairs(plotOffsets) do
		placeAt(flora, "Palm_Plot_" .. i, pos + Vector3.new(110, 0, 40), kitPalm, 0.85)
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
