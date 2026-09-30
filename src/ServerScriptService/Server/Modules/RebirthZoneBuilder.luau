--!strict
--[[
	claude-bud JOB 33 (2026-09-30): the geometry of the 7 rebirth zones (RebirthZonesConfig). Server only; called by
	RebirthZoneService.

	Build(zoneId, level, frame, annex, trim, parent) -> console part
	  frame = the annex's ground frame: local +Z faces the base, -Z faces away.
	  Every zone has a concrete yard with curbs in the base's TRIM colour (the rank shows) and a console at the front
	  (the service adds its prompts).
	  level 0 = the empty yard (BUILD); levels 1..3 add the complex, each level visibly more:
	  * Tank Factory: a hangar and a parked tank, then containers and a second tank, then a chimney stack and a third
	    tank.
	  * Nuclear Silo: a silo ring with a standing missile, launch pad and control bunker, then a radar dome and a fuel
	    tank, then blast walls and a second missile on its transporter.
	  * Artillery Battery: 2 / 4 / 6 gun emplacements, an ammo bunker, and a watchtower at level 3.
	  * Drone Hangar: a hangar, launch pad and drones, then more drones and a radar dome, then a second hangar.
	  * Elite Barracks: a 2 / 3 / 4-storey barracks with a flag, and a watchtower at level 3.
	  * Oil Refinery: fuel tanks, a flare stack and pipes, then a distillation tower, then a second tower, a pipe rack
	    and drums.
	  * Bunker Complex: 1 / 2 / 3 bunkers, sandbag lines, tank traps, and a watchtower from level 2.
	Locked(zoneId, tier, frame, annex, parent): a see-through fence round the yard and a sign "Unlocks at Rebirth N"
	(a BillboardGui, MaxDistance 40).
	Everything goes through WorldKits (the one anchored-part factory: never Neon, shadows only on big parts), in clusters
	of <= 64 studs. Kits are built plain (NoDetail): a zone's part count never depends on the world detail allowance.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local RebirthConfig = require(Shared.Configs.RebirthConfig)
local WorldKits = require(script.Parent.WorldKits)

local RebirthZoneBuilder = {}

local M = Enum.Material
local C = {
	Yard = Color3.fromRGB(96, 96, 92),
	Steel = Color3.fromRGB(110, 114, 118),
	SteelDark = Color3.fromRGB(58, 60, 64),
	Olive = Color3.fromRGB(86, 94, 58),
	White = Color3.fromRGB(226, 226, 220),
	Red = Color3.fromRGB(170, 44, 40),
	Hazard = Color3.fromRGB(214, 170, 40),
	Concrete = Color3.fromRGB(150, 146, 136),
	Wall = Color3.fromRGB(176, 164, 136),
	Window = Color3.fromRGB(40, 52, 62),
	Sand = Color3.fromRGB(186, 164, 118),
}

local function rotY(d: number): CFrame
	return CFrame.Angles(0, math.rad(d), 0)
end

-- one small cluster (<= 64 studs) for one item
local function newCluster(zoneId: string, name: string): Model
	return WorldKits.NewCluster(name, { Source = "rebirth", Kind = zoneId, Anchor = "plot", AnchorX = 0, AnchorZ = 0, Tier = 1 })
end

local function finish(cl: Model, parent: Instance)
	WorldKits.Finish(cl, parent)
end

local function part(cl: Model, name: string, size: Vector3, cf: CFrame, color: Color3, mat: Enum.Material, collide: boolean, shape: Enum.PartType?): Part
	return WorldKits.Part({ Name = name, Size = size, CFrame = cf, Color = color, Material = mat, Collide = collide, CastShadow = true, Shape = shape }, cl)
end

-- a WorldKits kit as its own cluster
local function kit(zoneId: string, parent: Instance, frame: CFrame, kitId: string, x: number, z: number, yaw: number, opts: { [string]: any }?)
	local cl = newCluster(zoneId, zoneId .. "_" .. kitId)
	local o: { [string]: any } = { NoDetail = true }
	for k, v in pairs(opts or {}) do
		o[k] = v
	end
	WorldKits.Add(cl, kitId, frame * CFrame.new(x, 0, z) * rotY(yaw), o :: any)
	finish(cl, parent)
end

-- ── custom pieces ─────────────────────────────────────────────────────────────────────────────────────────────────
local function tank(zoneId: string, parent: Instance, cf: CFrame)
	-- 7 parts: 2 tracks, hull, glacis, turret, barrel, hatch (a parked tank, gun toward local -X)
	local cl = newCluster(zoneId, zoneId .. "_Tank")
	part(cl, "ZoneTankTrack", Vector3.new(9, 1.6, 1.3), cf * CFrame.new(0, 0.8, -2.4), C.SteelDark, M.Metal, true)
	part(cl, "ZoneTankTrack", Vector3.new(9, 1.6, 1.3), cf * CFrame.new(0, 0.8, 2.4), C.SteelDark, M.Metal, true)
	part(cl, "ZoneTankHull", Vector3.new(8.4, 1.4, 4.2), cf * CFrame.new(0.2, 1.6, 0), C.Olive, M.Metal, true)
	part(cl, "ZoneTankGlacis", Vector3.new(4.2, 1.2, 1.6), cf * CFrame.new(-4.9, 1.5, 0) * rotY(90), C.Olive, M.Metal, true, Enum.PartType.Wedge)
	local t = cf * CFrame.new(0.6, 3, 0)
	part(cl, "ZoneTankTurret", Vector3.new(3.8, 1.4, 3.4), t, C.Olive, M.Metal, true)
	part(cl, "ZoneTankBarrel", Vector3.new(6, 0.45, 0.45), t * CFrame.new(-4.8, 0.1, 0), C.SteelDark, M.Metal, false, Enum.PartType.Cylinder)
	part(cl, "ZoneTankHatch", Vector3.new(0.3, 1.1, 1.1), t * CFrame.new(0.6, 0.85, 0.4) * CFrame.Angles(0, 0, math.rad(90)), C.SteelDark, M.Metal, false, Enum.PartType.Cylinder)
	finish(cl, parent)
end

local function gun(zoneId: string, parent: Instance, frame: CFrame, x: number, z: number)
	-- an emplacement: a sandbag arc (kit) + turntable, barrel (raised, facing away from the base), shield (3 parts)
	kit(zoneId, parent, frame, "SandbagArc", x, z + 3, 180)
	local cl = newCluster(zoneId, zoneId .. "_Gun")
	local cf = frame * CFrame.new(x, 0, z)
	part(cl, "ZoneGunBase", Vector3.new(1.4, 3.2, 3.2), cf * CFrame.new(0, 0.7, 0) * CFrame.Angles(0, 0, math.rad(90)), C.SteelDark, M.Metal, true, Enum.PartType.Cylinder)
	part(cl, "ZoneGunBarrel", Vector3.new(8, 0.6, 0.6), cf * CFrame.new(0, 2.6, -3) * rotY(90) * CFrame.Angles(0, 0, math.rad(20)), C.Olive, M.Metal, false, Enum.PartType.Cylinder)
	part(cl, "ZoneGunShield", Vector3.new(3, 2, 0.3), cf * CFrame.new(0, 2.2, -0.8), C.Olive, M.Metal, true)
	finish(cl, parent)
end

local function drone(zoneId: string, parent: Instance, cf: CFrame)
	-- 3 parts: body + 2 crossed arms
	local cl = newCluster(zoneId, zoneId .. "_Drone")
	part(cl, "ZoneDroneBody", Vector3.new(1.6, 0.6, 1.6), cf, C.SteelDark, M.Metal, false)
	part(cl, "ZoneDroneArm", Vector3.new(4.2, 0.2, 0.3), cf * rotY(45), C.Steel, M.Metal, false)
	part(cl, "ZoneDroneArm", Vector3.new(4.2, 0.2, 0.3), cf * rotY(-45), C.Steel, M.Metal, false)
	finish(cl, parent)
end

local function vcyl(cl: Model, name: string, cf: CFrame, h: number, d: number, color: Color3, mat: Enum.Material, collide: boolean): Part
	-- a vertical cylinder standing on cf (a Cylinder's axis is X: turned to Y)
	return part(cl, name, Vector3.new(h, d, d), cf * CFrame.new(0, h * 0.5, 0) * CFrame.Angles(0, 0, math.rad(90)), color, mat, collide, Enum.PartType.Cylinder)
end

local function missile(cl: Model, cf: CFrame)
	-- 3 parts: body, nose, fin cross
	vcyl(cl, "ZoneMissile", cf, 20, 3, C.White, M.SmoothPlastic, true)
	part(cl, "ZoneMissileNose", Vector3.new(3, 3, 3), cf * CFrame.new(0, 20.6, 0), C.Red, M.SmoothPlastic, false, Enum.PartType.Ball)
	part(cl, "ZoneMissileFins", Vector3.new(5, 2, 0.3), cf * CFrame.new(0, 1, 0), C.Red, M.SmoothPlastic, false)
end

local function tower(zoneId: string, parent: Instance, cf: CFrame, h: number, d: number)
	-- 4 parts: column, 2 rings, a top platform (a refinery distillation tower)
	local cl = newCluster(zoneId, zoneId .. "_Tower")
	vcyl(cl, "ZoneTowerColumn", cf, h, d, C.Steel, M.Metal, true)
	vcyl(cl, "ZoneTowerRing", cf * CFrame.new(0, h * 0.35, 0), 0.6, d + 1, C.SteelDark, M.Metal, false)
	vcyl(cl, "ZoneTowerRing", cf * CFrame.new(0, h * 0.7, 0), 0.6, d + 1, C.SteelDark, M.Metal, false)
	part(cl, "ZoneTowerTop", Vector3.new(d + 2, 0.5, d + 2), cf * CFrame.new(0, h + 0.25, 0), C.Hazard, M.DiamondPlate, true)
	finish(cl, parent)
end

local function barracks(zoneId: string, parent: Instance, cf: CFrame, storeys: number, trim: Color3)
	-- a multi-storey barracks, 40 x 16: body, a window band per storey, door, trim parapet, flag pole + flag
	local cl = newCluster(zoneId, zoneId .. "_Barracks")
	local H = 8
	part(cl, "ZoneBarracksBody", Vector3.new(40, H * storeys, 16), cf * CFrame.new(0, H * storeys * 0.5, 0), C.Wall, M.Concrete, true)
	for s = 1, storeys do
		part(cl, "ZoneBarracksWindows", Vector3.new(36, 2, 0.3), cf * CFrame.new(0, (s - 1) * H + 4.5, 8.1), C.Window, M.Glass, false)
	end
	part(cl, "ZoneBarracksDoor", Vector3.new(6, 6, 0.3), cf * CFrame.new(0, 3, 8.2), C.SteelDark, M.Metal, false)
	part(cl, "ZoneBarracksParapet", Vector3.new(40.6, 1, 16.6), cf * CFrame.new(0, H * storeys + 0.5, 0), trim, M.Concrete, true)
	part(cl, "ZoneFlagPole", Vector3.new(0.4, 10, 0.4), cf * CFrame.new(17, H * storeys + 5, 6), C.Steel, M.Metal, false)
	part(cl, "ZoneFlag", Vector3.new(0.1, 2.4, 4), cf * CFrame.new(17, H * storeys + 8.6, 8.1), trim, M.Fabric, false)
	finish(cl, parent)
end

-- ── the yard, the console, the locked fence ───────────────────────────────────────────────────────────────────────
local function yard(zoneId: string, parent: Instance, frame: CFrame, W: number, D: number, trim: Color3): Part
	-- the yard in two halves (a cluster may be at most 64 studs across; the yard is 74 wide), each with its curbs
	for _, s in ipairs({ -1, 1 }) do
		local cl = newCluster(zoneId, zoneId .. "_Yard")
		local hx = s * W * 0.25
		part(cl, "ZoneYard", Vector3.new(W * 0.5, 0.4, D), frame * CFrame.new(hx, 0.2, 0), C.Yard, M.Concrete, true)
		for _, t in ipairs({ -1, 1 }) do
			part(cl, "ZoneCurb", Vector3.new(W * 0.5, 0.5, 0.8), frame * CFrame.new(hx, 0.45, t * (D * 0.5 - 0.4)), trim, M.Concrete, false)
		end
		part(cl, "ZoneCurb", Vector3.new(0.8, 0.5, D - 1.6), frame * CFrame.new(s * (W * 0.5 - 0.4), 0.45, 0), trim, M.Concrete, false)
		finish(cl, parent)
	end
	-- the console at the front (toward the base): a post and a tilted panel
	local cc = newCluster(zoneId, zoneId .. "_Console")
	part(cc, "ZoneConsolePost", Vector3.new(1.2, 3, 0.8), frame * CFrame.new(0, 1.9, D * 0.5 - 3), C.SteelDark, M.Metal, true)
	local panel = part(cc, "ZoneConsole", Vector3.new(2.6, 1.6, 0.3), frame * CFrame.new(0, 3.6, D * 0.5 - 2.8) * CFrame.Angles(math.rad(-25), 0, 0), trim, M.SmoothPlastic, true)
	finish(cc, parent)
	return panel
end

function RebirthZoneBuilder.Locked(zoneId: string, tier: number, frame: CFrame, W: number, D: number, parent: Instance)
	local look: any = RebirthConfig.LockedLook
	local fenceColor = if typeof(look) == "table" and typeof(look.FenceColor) == "Color3" then look.FenceColor else C.SteelDark
	-- the fence in two halves (each cluster <= 64 across): the half front and back panels + that side's panel
	for _, s in ipairs({ -1, 1 }) do
		local cl = newCluster(zoneId, zoneId .. "_Locked")
		local hx = s * W * 0.25
		for _, t in ipairs({ -1, 1 }) do
			local f1 = part(cl, "ZoneFence", Vector3.new(W * 0.5, 4, 0.3), frame * CFrame.new(hx, 2.2, t * D * 0.5), fenceColor, M.DiamondPlate, true)
			f1.Transparency = 0.45
		end
		local f2 = part(cl, "ZoneFence", Vector3.new(0.3, 4, D), frame * CFrame.new(s * W * 0.5, 2.2, 0), fenceColor, M.DiamondPlate, true)
		f2.Transparency = 0.45
		finish(cl, parent)
	end
	local cl = newCluster(zoneId, zoneId .. "_Sign")
	part(cl, "ZoneSignPost", Vector3.new(0.5, 7, 0.5), frame * CFrame.new(0, 3.5, D * 0.5 + 2), C.SteelDark, M.Metal, true)
	local board = part(cl, "ZoneSign", Vector3.new(8, 3, 0.3), frame * CFrame.new(0, 6.5, D * 0.5 + 2.2), C.Hazard, M.SmoothPlastic, false)
	local bb = Instance.new("BillboardGui")
	bb.Name = "WE_ZoneLockedSign"
	bb.Size = UDim2.fromOffset(190, 44)
	bb.StudsOffset = Vector3.new(0, 2.6, 0)
	bb.MaxDistance = 40
	bb.LightInfluence = 0
	local t = Instance.new("TextLabel")
	t.BackgroundTransparency = 0.25
	t.BackgroundColor3 = Color3.fromRGB(20, 20, 16)
	t.Size = UDim2.fromScale(1, 1)
	t.Font = Enum.Font.GothamBlack
	t.TextSize = 16
	t.TextColor3 = C.Hazard
	t.TextWrapped = true
	local z = RebirthConfig.Zones[zoneId]
	t.Text = string.format("%s\nUnlocks at Rebirth %d", string.upper(z and z.DisplayName or zoneId), tier)
	t.Parent = bb
	bb.Parent = board
	finish(cl, parent)
end

-- ── the 7 complexes ───────────────────────────────────────────────────────────────────────────────────────────────
local build: { [string]: (zoneId: string, level: number, frame: CFrame, parent: Instance, trim: Color3) -> () } = {}

build.WestYard = function(z, L, f, p, _trim)
	if L >= 1 then
		kit(z, p, f, "Hangar", 0, -6, 180, { Width = 28 })
		tank(z, p, f * CFrame.new(-26, 0, 10) * rotY(90))
	end
	if L >= 2 then
		kit(z, p, f, "ContainerStack", 27, -14, 90, { Count = 2 })
		tank(z, p, f * CFrame.new(26, 0, 12) * rotY(90))
	end
	if L >= 3 then
		kit(z, p, f, "FlareStack", -28, -22, 0)
		tank(z, p, f * CFrame.new(13, 0, 18) * rotY(90))
	end
end

build.StrategicYard = function(z, L, f, p, _trim)
	if L >= 1 then
		local cl = newCluster(z, z .. "_Silo")
		local c = f * CFrame.new(0, 0, -6)
		part(cl, "ZoneLaunchPad", Vector3.new(18, 0.3, 18), c * CFrame.new(0, 0.55, 0), C.Hazard, M.Concrete, true)
		vcyl(cl, "ZoneSiloRing", c * CFrame.new(0, 0.5, 0), 2, 14, C.Concrete, M.Concrete, true)
		missile(cl, c * CFrame.new(0, 2.5, 0))
		finish(cl, p)
		kit(z, p, f, "Bunker", 24, -10, 180)
	end
	if L >= 2 then
		kit(z, p, f, "RadarDome", -25, -12, 0)
		kit(z, p, f, "FuelTank", -26, 14, 0, { Scale = 0.7 })
	end
	if L >= 3 then
		kit(z, p, f, "Revetment", -10, 9, 0)
		kit(z, p, f, "Revetment", 10, 9, 0)
		local cl = newCluster(z, z .. "_Transporter")
		local c = f * CFrame.new(24, 0, 14)
		part(cl, "ZoneTransporter", Vector3.new(14, 2, 3.4), c * CFrame.new(0, 1.4, 0), C.Olive, M.Metal, true)
		part(cl, "ZoneTransporterCab", Vector3.new(3, 3, 3.4), c * CFrame.new(-8, 1.9, 0), C.Olive, M.Metal, true)
		part(cl, "ZoneMissileLying", Vector3.new(13, 2.4, 2.4), c * CFrame.new(1, 3.6, 0), C.White, M.SmoothPlastic, false, Enum.PartType.Cylinder)
		part(cl, "ZoneMissileLyingNose", Vector3.new(2.4, 2.4, 2.4), c * CFrame.new(7.6, 3.6, 0), C.Red, M.SmoothPlastic, false, Enum.PartType.Ball)
		finish(cl, p)
	end
end

build.WestStrip = function(z, L, f, p, _trim)
	local spots = { { -24, -12 }, { -8, -12 }, { 8, -12 }, { -24, 8 }, { -8, 8 }, { 8, 8 } }
	for i = 1, math.min(6, L * 2) do
		gun(z, p, f, spots[i][1], spots[i][2])
	end
	if L >= 1 then
		kit(z, p, f, "Bunker", 26, -14, 180)
	end
	if L >= 3 then
		kit(z, p, f, "Watchtower", 28, 14, 180)
	end
end

build.DroneBay = function(z, L, f, p, _trim)
	if L >= 1 then
		kit(z, p, f, "Hangar", -14, -8, 180, { Width = 20 })
		kit(z, p, f, "HoldPad", 17, -6, 0, { R = 7 })
		drone(z, p, f * CFrame.new(14, 0.9, -6))
		drone(z, p, f * CFrame.new(20, 0.9, -6))
	end
	if L >= 2 then
		drone(z, p, f * CFrame.new(15, 6, -3) * rotY(20))
		drone(z, p, f * CFrame.new(20, 9, -9) * rotY(-15))
		kit(z, p, f, "RadarDome", 28, 16, 0)
	end
	if L >= 3 then
		kit(z, p, f, "Hangar", -14, 16, 180, { Width = 16 })
		drone(z, p, f * CFrame.new(10, 12, 4))
		drone(z, p, f * CFrame.new(24, 14, 2))
	end
end

build.EastYard = function(z, L, f, p, trim)
	if L >= 1 then
		barracks(z, p, f * CFrame.new(0, 0, -10), L + 1, trim)
	end
	if L >= 3 then
		kit(z, p, f, "Watchtower", 30, 14, 180)
	end
end

build.EastStrip = function(z, L, f, p, _trim)
	if L >= 1 then
		kit(z, p, f, "FuelTank", -24, -14, 0)
		kit(z, p, f, "FuelTank", -24, 6, 0)
		kit(z, p, f, "FlareStack", 27, -21, 0)
		kit(z, p, f, "PipeRun", 2, -25, 0, { Length = 40 })
	end
	if L >= 2 then
		tower(z, p, f * CFrame.new(6, 0, -10), 34, 6)
		kit(z, p, f, "FuelTank", 22, 10, 0, { Scale = 0.8 })
	end
	if L >= 3 then
		tower(z, p, f * CFrame.new(-6, 0, 12), 28, 5)
		kit(z, p, f, "PipeRun", 8, 18, 0, { Length = 40, Variant = "rack" })
		kit(z, p, f, "DrumGroup", -30, 22, 0, { Count = 3 })
	end
end

build.WestFlank = function(z, L, f, p, _trim)
	if L >= 1 then
		kit(z, p, f, "Bunker", -18, -14, 180)
		kit(z, p, f, "SandbagLine", -18, 4, 0, { Length = 20 })
		kit(z, p, f, "TankTrap", 14, -4, 0)
		kit(z, p, f, "TankTrap", 22, -4, 30)
	end
	if L >= 2 then
		kit(z, p, f, "Bunker", 18, -14, 180)
		kit(z, p, f, "Watchtower", 0, -20, 180)
	end
	if L >= 3 then
		kit(z, p, f, "Bunker", -18, 14, 180)
		kit(z, p, f, "SandbagLine", 18, 12, 0, { Length = 20 })
		kit(z, p, f, "TankTrap", 10, 20, 15)
		kit(z, p, f, "TankTrap", 26, 20, 45)
	end
end

function RebirthZoneBuilder.Build(zoneId: string, level: number, frame: CFrame, W: number, D: number, trim: Color3, parent: Instance): Part
	local console = yard(zoneId, parent, frame, W, D, trim)
	local fn = build[zoneId]
	if fn and level >= 1 then
		fn(zoneId, math.clamp(level, 1, 3), frame, parent, trim)
	end
	return console
end

function RebirthZoneBuilder.Has(zoneId: string): boolean
	return build[zoneId] ~= nil
end

return RebirthZoneBuilder
