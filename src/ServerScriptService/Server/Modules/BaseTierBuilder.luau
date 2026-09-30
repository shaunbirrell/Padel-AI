--!strict
--[[
	claude-bud JOB 39 phase 2 (2026-09-30): BASE TIER visuals (JOB 39 §2.3 / §11.1). The base visibly grows, Fort ->
	Capital, from Parts (PreferMesh OFF, own design, docs/ROBLOX-BUILD-GUIDE.md §2: layered pieces, trims, material
	variation; no single-box towers or walls). Pure builder: Build(ctx, tier) returns a Model; EndgameService parents it
	under the plot folder as WE_BaseTier and rebuilds it when the tier, the Command Center level or the walls change.
	Cumulative: tier 3 = the T1 + T2 + T3 pieces.
	  T1 Fort        roofs on the gate posts (eave, two steps, a finial) + one HQ storey with a window band
	  T2 Citadel     a lattice comms mast with a dish and a beacon, a sandbagged roof deck, the first AutoGun nest's ammo
	  T3 Stronghold  four corner bastions on the wall ring (skirt, body, string course, parapet, merlons, deck) and a
	                 gatehouse frame (piers + lintel + crest), clear of the 10-stud opening
	  T4 Bastion     a floodlit flag tower beside the HQ (ONE SpotLight, no shadows), the second nest's ammo, flag masts
	                 on the gate roofs
	  T5 Capital     a stone kerb round the parade ground, a bronze commander statue on a plinth, a row of four banners
	                 with the gold Capital trim
	Budgets: <= EndgameConfig.BaseTier.MaxPartsPerTier (120) parts and <= MaxLightsPerTier (2) lights per tier;
	tools/sim/run_endgame_test.py builds every tier with this module and counts. Banners are plain colours: no nation,
	no insignia. Decorative pieces never collide or answer a ray; the bastions and the statue plinth do (cover).
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local EndgameConfig = require(Shared.Configs.EndgameConfig)

local BaseTierBuilder = {}

export type Ctx = {
	Ground: CFrame, -- the plot frame at the pad's top (plot-local +Z = the front / gate side)
	PadCentre: Vector3,
	HalfX: number, -- the wall ring's half extents (world X / Z, axis aligned like SyncPerimeterWalls)
	HalfZ: number,
	WallTop: number, -- world Y of the wall tops
	GroundY: number,
	Posts: { { CFrame: CFrame, Size: Vector3 } }, -- the gate posts (roofs sit on them)
	Gate: CFrame?, -- GateDefenseService gate frame (local -Z = inside)
	Nests: { CFrame }, -- the Base Tier AutoGun nests (T2 first, T4 second)
	HQ: { CFrame: CFrame, Size: Vector3 }?, -- the Command Center building's box
	BannerColor: Color3?, -- phase 5: the Black Market banner colour (nil = the base green)
	Crest: boolean?, -- phase 5: the R35 Bastion Crest (a gold crest over the gate)
	Trophy: boolean?, -- phase 5: the Black Market trophy cannon on the parade ground
}

local M = Enum.Material
local C = {
	Body = Color3.fromRGB(200, 186, 150),
	Trim = Color3.fromRGB(226, 220, 204),
	Gold = Color3.fromRGB(214, 178, 64),
	Roof = Color3.fromRGB(84, 86, 80),
	Concrete = Color3.fromRGB(150, 146, 136),
	ConcreteDark = Color3.fromRGB(112, 110, 104),
	Steel = Color3.fromRGB(64, 68, 72),
	Sand = Color3.fromRGB(186, 168, 122),
	Olive = Color3.fromRGB(86, 96, 60),
	Glass = Color3.fromRGB(120, 160, 180),
	Bronze = Color3.fromRGB(140, 98, 52),
	Banner = Color3.fromRGB(40, 70, 52),
	Red = Color3.fromRGB(170, 40, 40),
}

local function put(m: Model, name: string, size: Vector3, cf: CFrame, color: Color3, mat: Enum.Material, solid: boolean?, shape: Enum.PartType?): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = mat
	p.Anchored = true
	p.CanCollide = solid == true
	p.CanQuery = solid == true
	p.CanTouch = false
	p.CastShadow = solid == true and size.Magnitude > 8
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	if shape then
		p.Shape = shape
	end
	p:SetAttribute("WE_TierPiece", true)
	p.Parent = m
	return p
end

local function tierFolder(m: Model, t: number): Model
	local f = Instance.new("Model")
	f.Name = "Tier" .. t
	f.Parent = m
	return f
end

-- a gate post's roof: eave, two steps, a finial (4 parts)
local function postRoof(m: Model, post: { CFrame: CFrame, Size: Vector3 })
	local top = post.CFrame * CFrame.new(0, post.Size.Y * 0.5, 0)
	local sx, sz = post.Size.X, post.Size.Z
	put(m, "GateRoofEave", Vector3.new(sx + 1.4, 0.4, sz + 1.4), top * CFrame.new(0, 0.2, 0), C.Trim, M.Concrete)
	put(m, "GateRoofStep", Vector3.new(sx + 0.6, 0.9, sz + 0.6), top * CFrame.new(0, 0.85, 0), C.Roof, M.Slate)
	put(m, "GateRoofStep", Vector3.new(math.max(sx * 0.55, 0.8), 0.8, math.max(sz * 0.55, 0.8)), top * CFrame.new(0, 1.7, 0), C.Roof, M.Slate)
	put(m, "GateRoofFinial", Vector3.new(0.7, 0.7, 0.7), top * CFrame.new(0, 2.45, 0), C.Gold, M.Metal, false, Enum.PartType.Ball)
end

-- the extra HQ storey (18 parts): plinth band, 4 walls of lower panel + glass band + upper panel, roof slab, coping ring
local function hqStorey(m: Model, hq: { CFrame: CFrame, Size: Vector3 }): (CFrame, number, number)
	local T = hq.CFrame * CFrame.new(0, hq.Size.Y * 0.5, 0)
	local w, d = math.max(hq.Size.X - 3, 8), math.max(hq.Size.Z - 3, 8)
	put(m, "StoreyPlinth", Vector3.new(w + 0.6, 0.5, d + 0.6), T * CFrame.new(0, 0.25, 0), C.Trim, M.Concrete)
	local sides = {
		{ F = CFrame.new(0, 0, -d * 0.5), Len = w },
		{ F = CFrame.new(0, 0, d * 0.5), Len = w },
		{ F = CFrame.new(-w * 0.5, 0, 0) * CFrame.Angles(0, math.rad(90), 0), Len = d },
		{ F = CFrame.new(w * 0.5, 0, 0) * CFrame.Angles(0, math.rad(90), 0), Len = d },
	}
	for _, s in ipairs(sides) do
		local f = T * s.F
		local len = s.Len
		put(m, "StoreyWall", Vector3.new(len, 2, 0.6), f * CFrame.new(0, 1.5, 0), C.Body, M.Plaster)
		put(m, "StoreyWindowBand", Vector3.new(len - 1, 1.6, 0.3), f * CFrame.new(0, 3.3, 0), C.Glass, M.Glass).Transparency = 0.35
		put(m, "StoreyWall", Vector3.new(len, 2.2, 0.6), f * CFrame.new(0, 5.2, 0), C.Body, M.Plaster)
	end
	put(m, "StoreyRoof", Vector3.new(w + 1, 0.5, d + 1), T * CFrame.new(0, 6.55, 0), C.Roof, M.Concrete)
	for _, s in ipairs(sides) do
		local f = T * s.F
		put(m, "StoreyCoping", Vector3.new(s.Len + 1.2, 0.3, 0.5), f * CFrame.new(0, 6.95, 0), C.Gold, M.Metal)
	end
	return T * CFrame.new(0, 6.8, 0), w, d
end

-- ammo boxes + an extra sandbag layer at a nest (10 parts)
local function nestDressing(m: Model, at: CFrame)
	local g = at
	for i, x in ipairs({ -1.6, 0, 1.6 }) do
		local b = g * CFrame.new(x, 0.45, 3.4) * CFrame.Angles(0, math.rad(i * 7), 0)
		put(m, "AmmoBox", Vector3.new(1.4, 0.8, 0.9), b, C.Olive, M.Metal)
		put(m, "AmmoBoxLid", Vector3.new(1.45, 0.12, 0.95), b * CFrame.new(0, 0.45, 0), C.Steel, M.Metal)
	end
	for i = 0, 3 do
		local a = math.rad(-60 + i * 40)
		put(m, "NestSandbag", Vector3.new(2.2, 0.9, 1.1), g * CFrame.Angles(0, a, 0) * CFrame.new(0, 2.3, -3.3), C.Sand, M.Sand)
	end
end

-- a corner bastion on the wall ring (12 parts)
local function bastion(m: Model, pos: Vector3, groundY: number, top: number)
	local h = math.max(top - groundY + 1.5, 8)
	local base = CFrame.new(pos.X, groundY, pos.Z)
	put(m, "BastionSkirt", Vector3.new(12, 2.5, 12), base * CFrame.new(0, 1.25, 0), C.ConcreteDark, M.Concrete, true)
	put(m, "BastionBody", Vector3.new(10, h, 10), base * CFrame.new(0, h * 0.5, 0), C.Concrete, M.Concrete, true)
	put(m, "BastionBand", Vector3.new(10.6, 0.6, 10.6), base * CFrame.new(0, h * 0.55, 0), C.Trim, M.Concrete)
	put(m, "BastionDeck", Vector3.new(9.2, 0.4, 9.2), base * CFrame.new(0, h + 0.2, 0), C.ConcreteDark, M.Concrete, true)
	for i = 0, 3 do
		local f = base * CFrame.Angles(0, math.rad(90 * i), 0)
		put(m, "BastionParapet", Vector3.new(10.4, 2.2, 0.8), f * CFrame.new(0, h + 1.1, -4.8), C.Concrete, M.Concrete, true)
		put(m, "BastionMerlon", Vector3.new(1.4, 1.2, 1.4), f * CFrame.new(4.5, h + 2.8, -4.5), C.Trim, M.Concrete)
	end
end

-- a flag on a mast: pole, banner, gold finial (3 parts); `trim` adds the Capital strip (1 more)
local bannerColor: Color3 = C.Banner
local function flagMast(m: Model, base: CFrame, height: number, trim: boolean)
	put(m, "FlagMast", Vector3.new(height, 0.3, 0.3), base * CFrame.new(0, height * 0.5, 0) * CFrame.Angles(0, 0, math.rad(90)), C.Steel, M.Metal, true, Enum.PartType.Cylinder)
	put(m, "FlagBanner", Vector3.new(0.1, 2.6, 4), base * CFrame.new(0, height - 1.6, 2.1), bannerColor, M.Fabric)
	put(m, "FlagFinial", Vector3.new(0.6, 0.6, 0.6), base * CFrame.new(0, height + 0.3, 0), C.Gold, M.Metal, false, Enum.PartType.Ball)
	if trim then
		put(m, "CapitalTrim", Vector3.new(0.12, 0.35, 4), base * CFrame.new(0, height - 3.0, 2.1), C.Gold, M.Metal)
	end
end

local function statue(m: Model, base: CFrame)
	put(m, "StatuePlinthBase", Vector3.new(6, 1.2, 6), base * CFrame.new(0, 0.6, 0), C.ConcreteDark, M.Granite, true)
	put(m, "StatuePlinth", Vector3.new(4.4, 4, 4.4), base * CFrame.new(0, 3.2, 0), C.Concrete, M.Granite, true)
	put(m, "StatuePlinthCap", Vector3.new(5, 0.5, 5), base * CFrame.new(0, 5.45, 0), C.Trim, M.Marble)
	put(m, "StatuePlaque", Vector3.new(2.4, 1, 0.1), base * CFrame.new(0, 3.4, -2.26), C.Gold, M.Metal)
	-- the bronze commander, x1.6 of a soldier, facing the gate (plot +Z = the frame's -Z here: see the caller)
	local f = base * CFrame.new(0, 5.7, 0)
	local k = 1.6
	for _, s in ipairs({ -1, 1 }) do
		put(m, "StatueBoot", Vector3.new(0.9 * k, 0.5 * k, 1.2 * k), f * CFrame.new(0.5 * k * s, 0.25 * k, -0.1 * k), C.Bronze, M.Metal)
		put(m, "StatueLeg", Vector3.new(0.85 * k, 2.3 * k, 0.85 * k), f * CFrame.new(0.5 * k * s, 1.65 * k, 0), C.Bronze, M.Metal)
		put(m, "StatueEpaulette", Vector3.new(0.8 * k, 0.15 * k, 0.9 * k), f * CFrame.new(1.2 * k * s, 4.95 * k, 0), C.Bronze, M.Metal)
	end
	put(m, "StatueCoat", Vector3.new(2.1 * k, 2.4 * k, 1.1 * k), f * CFrame.new(0, 3.75 * k, 0), C.Bronze, M.Metal)
	put(m, "StatueCoatSkirt", Vector3.new(2.3 * k, 1.1 * k, 1.3 * k), f * CFrame.new(0, 2.6 * k, 0.05 * k), C.Bronze, M.Metal)
	put(m, "StatueArm", Vector3.new(0.75 * k, 2.1 * k, 0.75 * k), f * CFrame.new(-1.4 * k, 3.8 * k, 0), C.Bronze, M.Metal)
	-- the right arm raised, pointing out over the parade ground
	put(m, "StatueArm", Vector3.new(0.75 * k, 2.1 * k, 0.75 * k), f * CFrame.new(1.45 * k, 4.6 * k, -0.7 * k) * CFrame.Angles(math.rad(70), 0, 0), C.Bronze, M.Metal)
	put(m, "StatueHead", Vector3.new(1.1 * k, 1.15 * k, 1.1 * k), f * CFrame.new(0, 5.5 * k, 0), C.Bronze, M.Metal)
	put(m, "StatueCap", Vector3.new(1.3 * k, 0.4 * k, 1.3 * k), f * CFrame.new(0, 6.2 * k, 0), C.Bronze, M.Metal)
	put(m, "StatueVisor", Vector3.new(1.0 * k, 0.1 * k, 0.5 * k), f * CFrame.new(0, 6.05 * k, -0.8 * k), C.Bronze, M.Metal)
end

--[[ Build the tier `tier` (1..5) look for one base. Returns the Model (unparented), its part count and light count. ]]
function BaseTierBuilder.Build(ctx: Ctx, tier: number): (Model, number, number)
	local root = Instance.new("Model")
	root.Name = "WE_BaseTier"
	root.ModelStreamingMode = Enum.ModelStreamingMode.Atomic
	local t = math.clamp(math.floor(tier), 0, #EndgameConfig.BaseTier.Tiers)
	root:SetAttribute("WE_Tier", t)
	bannerColor = ctx.BannerColor or C.Banner
	local G = ctx.Ground
	local roofTop: CFrame? = nil
	local rw, rd = 0, 0
	local lights = 0

	if t >= 1 then
		local m = tierFolder(root, 1)
		for i, p in ipairs(ctx.Posts) do
			if i <= 4 then
				postRoof(m, p)
			end
		end
		if ctx.HQ then
			roofTop, rw, rd = hqStorey(m, ctx.HQ :: any)
		end
	end
	if t >= 2 then
		local m = tierFolder(root, 2)
		local rt = roofTop
		if rt then
			-- the comms mast in the back corner of the new storey's roof
			local mb = rt * CFrame.new(rw * 0.5 - 2.5, 0, rd * 0.5 - 2.5)
			for _, c in ipairs({ { -0.9, -0.9 }, { 0.9, -0.9 }, { -0.9, 0.9 }, { 0.9, 0.9 } }) do
				put(m, "MastLeg", Vector3.new(0.3, 10, 0.3), mb * CFrame.new(c[1], 5, c[2]), C.Steel, M.Metal)
			end
			put(m, "MastBrace", Vector3.new(0.18, 10.2, 0.18), mb * CFrame.new(0, 5, -0.9) * CFrame.Angles(0, 0, math.rad(10)), C.Steel, M.Metal)
			put(m, "MastBrace", Vector3.new(0.18, 10.2, 0.18), mb * CFrame.new(-0.9, 5, 0) * CFrame.Angles(math.rad(10), 0, 0), C.Steel, M.Metal)
			put(m, "MastPlatform", Vector3.new(2.6, 0.25, 2.6), mb * CFrame.new(0, 10.1, 0), C.Steel, M.DiamondPlate)
			local dish = mb * CFrame.new(0, 8, -1.4) * CFrame.Angles(0, math.rad(90), math.rad(-20))
			put(m, "MastDish", Vector3.new(0.3, 3.2, 3.2), dish, Color3.fromRGB(228, 228, 222), M.SmoothPlastic, false, Enum.PartType.Cylinder)
			put(m, "MastDishFeed", Vector3.new(0.2, 0.2, 1.4), dish * CFrame.new(0, 0, 0) * CFrame.new(-0.8, 0, 0), C.Steel, M.Metal)
			put(m, "MastDishMount", Vector3.new(0.6, 0.6, 0.6), mb * CFrame.new(0, 8, -0.6), C.Steel, M.Metal)
			put(m, "MastBeacon", Vector3.new(0.5, 0.5, 0.5), mb * CFrame.new(0, 10.5, 0), C.Red, M.SmoothPlastic, false, Enum.PartType.Ball)
			-- the sandbagged roof deck: a bag row inside each roof edge, two high on the front, two ammo crates
			for i, e in ipairs({ { 0, -(rd * 0.5 - 1), rw - 3, 0 }, { 0, rd * 0.5 - 1, rw - 3, 0 }, { -(rw * 0.5 - 1), 0, rd - 3, 90 }, { rw * 0.5 - 1, 0, rd - 3, 90 } }) do
				local f = rt * CFrame.new(e[1], 0.45, e[2]) * CFrame.Angles(0, math.rad(e[4]), 0)
				put(m, "DeckSandbags", Vector3.new(e[3], 0.9, 1.1), f, C.Sand, M.Sand)
				if i <= 2 then
					put(m, "DeckSandbags", Vector3.new(e[3] - 2, 0.8, 1.0), f * CFrame.new(0, 0.85, 0), C.Sand, M.Sand)
				end
			end
			put(m, "DeckCrate", Vector3.new(1.6, 1.2, 1.2), rt * CFrame.new(-rw * 0.25, 0.6, 0), C.Olive, M.Wood)
			put(m, "DeckCrate", Vector3.new(1.2, 1.0, 1.2), rt * CFrame.new(-rw * 0.25 + 1.6, 0.5, 0.3), C.Olive, M.Wood)
		end
		if ctx.Nests[1] then
			nestDressing(m, ctx.Nests[1])
		end
	end
	if t >= 3 then
		local m = tierFolder(root, 3)
		for _, sx in ipairs({ -1, 1 }) do
			for _, sz in ipairs({ -1, 1 }) do
				bastion(m, Vector3.new(ctx.PadCentre.X + sx * ctx.HalfX, 0, ctx.PadCentre.Z + sz * ctx.HalfZ), ctx.GroundY, ctx.WallTop)
			end
		end
		local gate = ctx.Gate
		if gate then
			local gh = math.max(ctx.WallTop - ctx.GroundY, 12)
			for _, s in ipairs({ -1, 1 }) do
				put(m, "GatehousePlinth", Vector3.new(3.4, 1.2, 4.6), gate * CFrame.new(6.6 * s, 0.6, 0), C.ConcreteDark, M.Concrete)
				put(m, "GatehousePier", Vector3.new(2.5, gh + 2, 4), gate * CFrame.new(6.6 * s, (gh + 2) * 0.5, 0), C.Concrete, M.Concrete)
			end
			put(m, "GatehouseLintel", Vector3.new(16, 2, 4.2), gate * CFrame.new(0, gh + 1, 0), C.Concrete, M.Concrete)
			put(m, "GatehouseCrest", Vector3.new(6, 1.6, 2), gate * CFrame.new(0, gh + 2.8, 0), C.Gold, M.Metal)
		end
	end
	if t >= 4 then
		local m = tierFolder(root, 4)
		local fb = G * CFrame.new(24, 0, -40)
		put(m, "TowerPlinth", Vector3.new(6, 1.2, 6), fb * CFrame.new(0, 0.6, 0), C.ConcreteDark, M.Concrete, true)
		put(m, "TowerShaft", Vector3.new(4.4, 10, 4.4), fb * CFrame.new(0, 6.2, 0), C.Concrete, M.Concrete, true)
		put(m, "TowerBand", Vector3.new(4.8, 0.5, 4.8), fb * CFrame.new(0, 11.4, 0), C.Trim, M.Concrete)
		put(m, "TowerShaft", Vector3.new(3.6, 8, 3.6), fb * CFrame.new(0, 15.6, 0), C.Concrete, M.Concrete, true)
		put(m, "TowerPlatform", Vector3.new(6, 0.5, 6), fb * CFrame.new(0, 19.85, 0), C.Steel, M.DiamondPlate, true)
		for i = 0, 3 do
			put(m, "TowerRail", Vector3.new(6, 1, 0.2), fb * CFrame.Angles(0, math.rad(90 * i), 0) * CFrame.new(0, 20.6, -2.9), C.Steel, M.Metal)
		end
		local lamp = put(m, "TowerFloodlight", Vector3.new(1.2, 0.8, 1.2), fb * CFrame.new(0, 20.5, 2) * CFrame.Angles(math.rad(-35), 0, 0), Color3.fromRGB(236, 230, 210), M.Metal)
		local sl = Instance.new("SpotLight")
		sl.Face = Enum.NormalId.Front
		sl.Angle = 55
		sl.Range = 18
		sl.Brightness = 0.8
		sl.Shadows = false
		sl.Color = Color3.fromRGB(255, 236, 190)
		sl.Parent = lamp
		lights += 1
		flagMast(m, fb * CFrame.new(0, 20.1, 0), 7, false)
		if ctx.Nests[2] then
			nestDressing(m, ctx.Nests[2])
		end
		for i, p in ipairs(ctx.Posts) do
			if i <= 2 then
				local top = p.CFrame * CFrame.new(0, p.Size.Y * 0.5 + 2.8, 0)
				put(m, "GateMast", Vector3.new(4.5, 0.25, 0.25), top * CFrame.new(0, 2.25, 0) * CFrame.Angles(0, 0, math.rad(90)), C.Steel, M.Metal, false, Enum.PartType.Cylinder)
				put(m, "GateBanner", Vector3.new(0.1, 1.8, 2.6), top * CFrame.new(0, 3.3, 1.4), bannerColor, M.Fabric)
			end
		end
	end
	if t >= 5 then
		local m = tierFolder(root, 5)
		-- the stone kerb round the parade ground (BaseLayoutConfig Roads.Plaza: centre 0, 8; 60 x 50)
		put(m, "ParadeKerb", Vector3.new(61, 0.3, 0.6), G * CFrame.new(0, 0.15, 8 - 25.3), C.Trim, M.Marble)
		put(m, "ParadeKerb", Vector3.new(61, 0.3, 0.6), G * CFrame.new(0, 0.15, 8 + 25.3), C.Trim, M.Marble)
		put(m, "ParadeKerb", Vector3.new(0.6, 0.3, 50), G * CFrame.new(-30.3, 0.15, 8), C.Trim, M.Marble)
		put(m, "ParadeKerb", Vector3.new(0.6, 0.3, 50), G * CFrame.new(30.3, 0.15, 8), C.Trim, M.Marble)
		-- the statue faces the gate (plot +Z): its frame's -Z must point to +Z
		statue(m, G * CFrame.new(-18, 0, 20) * CFrame.Angles(0, math.rad(180), 0))
		for _, x in ipairs({ -30, -18, 18, 30 }) do
			flagMast(m, G * CFrame.new(x, 0, -14), 14, true)
		end
	end
	-- phase 5 extras (any tier): the R35 Bastion Crest over the gate, the Black Market trophy cannon on the parade ground
	local gate = ctx.Gate
	if ctx.Crest and gate then
		local m = tierFolder(root, 0)
		m.Name = "Crest"
		local ch = math.max(ctx.WallTop - ctx.GroundY, 12) + 4.6
		put(m, "CrestShield", Vector3.new(2.6, 3.0, 0.4), gate * CFrame.new(0, ch, -2.3), C.Gold, M.Metal)
		put(m, "CrestInlay", Vector3.new(1.6, 2.0, 0.1), gate * CFrame.new(0, ch, -2.55), bannerColor, M.SmoothPlastic)
		put(m, "CrestPoint", Vector3.new(1.4, 1.4, 0.4), gate * CFrame.new(0, ch - 1.6, -2.3) * CFrame.Angles(0, 0, math.rad(45)), C.Gold, M.Metal)
	end
	if ctx.Trophy then
		local m = tierFolder(root, 0)
		m.Name = "Trophy"
		local tb = G * CFrame.new(18, 0, 20) * CFrame.Angles(0, math.rad(180), 0)
		put(m, "TrophyPlinth", Vector3.new(7, 1, 4.4), tb * CFrame.new(0, 0.5, 0), C.ConcreteDark, M.Granite, true)
		put(m, "TrophyPlinthCap", Vector3.new(7.4, 0.3, 4.8), tb * CFrame.new(0, 1.15, 0), C.Trim, M.Marble)
		for _, s in ipairs({ -1, 1 }) do
			put(m, "TrophyWheel", Vector3.new(0.5, 2.6, 2.6), tb * CFrame.new(1.3 * s, 2.6, 0.6) * CFrame.Angles(0, 0, math.rad(90)), C.Bronze, M.Metal, false, Enum.PartType.Cylinder)
			put(m, "TrophyHub", Vector3.new(0.7, 0.6, 0.6), tb * CFrame.new(1.3 * s, 2.6, 0.6) * CFrame.Angles(0, 0, math.rad(90)), C.Gold, M.Metal, false, Enum.PartType.Cylinder)
		end
		put(m, "TrophyCarriage", Vector3.new(1.8, 0.7, 3.4), tb * CFrame.new(0, 2.2, 0.9), C.Bronze, M.Wood)
		put(m, "TrophyTrail", Vector3.new(0.6, 0.5, 2.6), tb * CFrame.new(0, 1.6, 2.6) * CFrame.Angles(math.rad(-14), 0, 0), C.Bronze, M.Wood)
		put(m, "TrophyBarrel", Vector3.new(4.6, 0.8, 0.8), tb * CFrame.new(0, 3.1, -0.6) * CFrame.Angles(0, math.rad(90), math.rad(12)), C.Bronze, M.Metal, false, Enum.PartType.Cylinder)
		put(m, "TrophyMuzzle", Vector3.new(0.5, 1.0, 1.0), tb * CFrame.new(0, 3.55, -2.8) * CFrame.Angles(0, math.rad(90), math.rad(12)), C.Gold, M.Metal, false, Enum.PartType.Cylinder)
		put(m, "TrophyBreech", Vector3.new(0.9, 0.9, 0.9), tb * CFrame.new(0, 2.75, 1.5), C.Bronze, M.Metal, false, Enum.PartType.Ball)
		for i, x in ipairs({ -2.6, -2.0, 2.3 }) do
			put(m, "TrophyShot" .. i, Vector3.new(0.6, 0.6, 0.6), tb * CFrame.new(x, 1.6, -1.4), C.Steel, M.Metal, false, Enum.PartType.Ball)
		end
		put(m, "TrophyPlaque", Vector3.new(2.2, 0.6, 0.08), tb * CFrame.new(0, 0.6, -2.24), C.Gold, M.Metal)
	end

	local parts = 0
	for _, d in ipairs(root:GetDescendants()) do
		if d:IsA("BasePart") then
			parts += 1
		end
	end
	root:SetAttribute("WE_TierParts", parts)
	return root, parts, lights
end

return BaseTierBuilder
