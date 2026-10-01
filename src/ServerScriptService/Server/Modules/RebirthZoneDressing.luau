--!strict
--[[
	claude-bud JOB 46 (2026-10-01): the dressing of a BUILT rebirth zone, so a bought area reads as a real place, not a
	slab with a tent. Server only; called by RebirthZoneService after the zone's Part build / store-prop swap.
	It goes on the annex's FRONT APRON (annex-local +Z, the strip between the base wall and the yard), in its own folder
	(Plot<n>/Dress_<zoneId>), so the store-prop swap (StorePropsService.dressZone keeps only the yard + console of the
	Zone_<Id> folder) never removes it and it never lands on a probe-verified store model inside the yard.
	  * an entrance gateway: two steel pylons on concrete footings, a header beam in the base's rank trim colour, a sign
	    board with the building's name and level (SurfaceGui, MaxDistance 80), hazard-striped kerbs, two street lamps;
	  * themed props (WorldKits kits + a few custom pieces): crates / drums / a crane for the Tank Factory, barriers and a
	    radio mast for the Silo, shell crates and sandbags for the Artillery, a launch pad and a mast for the Drones, an
	    obstacle course (hurdles, climbing wall, rope frame) and a flag for the Elite Barracks, drums and pipes for the
	    Refinery, sandbags / tank traps / barriers for the Bunker;
	  * the ACTIVITY KIOSK: a plinth, a post, a canopy and a lit panel in the trim colour; the service puts its prompt on
	    the panel ("ZoneActivityPanel").
	Parts only (WorldKits, never Neon, no lights), every cluster <= 64 studs, never one of the protected base building parts.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local RebirthZonesConfig = require(Shared.Configs.RebirthZonesConfig)
local WorldKits = require(script.Parent.WorldKits)

local RebirthZoneDressing = {}

local M = Enum.Material
local C = {
	Steel = Color3.fromRGB(110, 114, 118),
	SteelDark = Color3.fromRGB(52, 54, 58),
	Concrete = Color3.fromRGB(150, 146, 136),
	Hazard = Color3.fromRGB(214, 170, 40),
	Black = Color3.fromRGB(30, 30, 28),
	Wood = Color3.fromRGB(120, 88, 56),
	Olive = Color3.fromRGB(86, 94, 58),
	Rope = Color3.fromRGB(176, 150, 102),
	Sign = Color3.fromRGB(24, 28, 22),
}

local function rotY(d: number): CFrame
	return CFrame.Angles(0, math.rad(d), 0)
end

local function cluster(zoneId: string, name: string): Model
	return WorldKits.NewCluster(name, { Source = "rebirth", Kind = zoneId, Anchor = "plot", AnchorX = 0, AnchorZ = 0, Tier = 1 })
end

local function part(cl: Model, name: string, size: Vector3, cf: CFrame, color: Color3, mat: Enum.Material, collide: boolean): Part
	return WorldKits.Part({ Name = name, Size = size, CFrame = cf, Color = color, Material = mat, Collide = collide, CastShadow = size.Magnitude > 8 }, cl)
end

local function kit(zoneId: string, parent: Instance, cf: CFrame, kitId: string, opts: { [string]: any }?)
	local cl = cluster(zoneId, zoneId .. "_Dress_" .. kitId)
	local o: { [string]: any } = { NoDetail = true }
	for k, v in pairs(opts or {}) do
		o[k] = v
	end
	WorldKits.Add(cl, kitId, cf, o :: any)
	WorldKits.Finish(cl, parent)
end

local function signText(board: BasePart, text: string, color: Color3)
	for _, face in ipairs({ Enum.NormalId.Front, Enum.NormalId.Back }) do
		local g = Instance.new("SurfaceGui")
		g.Face = face
		g.MaxDistance = 80
		g.LightInfluence = 0
		g.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		g.PixelsPerStud = 30
		local l = Instance.new("TextLabel")
		l.BackgroundTransparency = 1
		l.Size = UDim2.fromScale(1, 1)
		l.Font = Enum.Font.GothamBlack
		l.TextScaled = true
		l.TextColor3 = color
		l.Text = text
		l.Parent = g
		g.Parent = board
	end
end

-- the entrance gateway on the apron (annex-local z = zg), the sign reads the building name + level
local function gateway(zoneId: string, parent: Instance, frame: CFrame, zg: number, trim: Color3, title: string)
	local cl = cluster(zoneId, zoneId .. "_Dress_Gate")
	for _, s in ipairs({ -1, 1 }) do
		local base = frame * CFrame.new(s * 13, 0, zg)
		part(cl, "GateFooting", Vector3.new(3, 1, 3), base * CFrame.new(0, 0.5, 0), C.Concrete, M.Concrete, true)
		part(cl, "GatePylon", Vector3.new(1.6, 11, 1.6), base * CFrame.new(0, 6.5, 0), C.SteelDark, M.Metal, true)
		part(cl, "GatePylonBand", Vector3.new(1.8, 0.5, 1.8), base * CFrame.new(0, 3.5, 0), C.Hazard, M.Metal, false)
		part(cl, "GatePylonCap", Vector3.new(2.2, 0.6, 2.2), base * CFrame.new(0, 12.3, 0), trim, M.Metal, false)
	end
	part(cl, "GateHeader", Vector3.new(27.6, 1.6, 1.4), frame * CFrame.new(0, 11.4, zg), trim, M.Metal, false)
	local board = part(cl, "GateSign", Vector3.new(22, 3, 0.4), frame * CFrame.new(0, 9, zg), C.Sign, M.SmoothPlastic, false)
	signText(board, title, C.Hazard)
	-- the striped kerb across the apron, with the gate gap
	for _, s in ipairs({ -1, 1 }) do
		for i = 0, 3 do
			part(cl, "ApronKerb", Vector3.new(4.5, 0.5, 0.8), frame * CFrame.new(s * (15.5 + i * 5), 0.25, zg), if i % 2 == 0 then C.Hazard else C.Black, M.Concrete, false)
		end
	end
	WorldKits.Finish(cl, parent)
	for _, s in ipairs({ -1, 1 }) do
		kit(zoneId, parent, frame * CFrame.new(s * 34, 0, zg + 1) * rotY(0), "StreetLamp")
	end
end

-- the activity kiosk (the service adds its prompt to the panel)
local function kiosk(zoneId: string, parent: Instance, frame: CFrame, x: number, z: number, trim: Color3, label: string): BasePart
	local cl = cluster(zoneId, zoneId .. "_Dress_Kiosk")
	local c = frame * CFrame.new(x, 0, z)
	part(cl, "KioskPlinth", Vector3.new(4.4, 0.6, 4.4), c * CFrame.new(0, 0.3, 0), C.Concrete, M.Concrete, true)
	part(cl, "KioskPost", Vector3.new(1.2, 3.4, 1.2), c * CFrame.new(0, 2.3, 0), C.SteelDark, M.Metal, true)
	local panel = part(cl, "ZoneActivityPanel", Vector3.new(3.2, 2, 0.4), c * CFrame.new(0, 4.2, 0.3) * CFrame.Angles(math.rad(-22), 0, 0), trim, M.SmoothPlastic, true)
	part(cl, "KioskScreen", Vector3.new(2.6, 1.4, 0.1), panel.CFrame * CFrame.new(0, 0, 0.22), C.Sign, M.Glass, false)
	for _, s in ipairs({ -1, 1 }) do
		part(cl, "KioskCanopyPost", Vector3.new(0.4, 7.4, 0.4), c * CFrame.new(s * 2, 3.7, -1.6), C.Steel, M.Metal, false)
	end
	part(cl, "KioskCanopy", Vector3.new(5.6, 0.4, 4.4), c * CFrame.new(0, 7.6, -0.2), trim, M.Metal, false)
	local tag = part(cl, "KioskTag", Vector3.new(5, 1.2, 0.3), c * CFrame.new(0, 6.7, 1.9), C.Sign, M.SmoothPlastic, false)
	signText(tag, label, C.Hazard)
	WorldKits.Finish(cl, parent)
	return panel
end

-- themed props on the apron sides (x beyond the gate, never inside the yard)
local themed: { [string]: (zoneId: string, parent: Instance, frame: CFrame, z: number, trim: Color3) -> () } = {}

themed.factory = function(z, p, f, za)
	kit(z, p, f * CFrame.new(-26, 0, za + 6), "CrateStack", { Count = 3 })
	kit(z, p, f * CFrame.new(-31, 0, za + 11) * rotY(90), "DrumGroup", { Count = 4 })
	kit(z, p, f * CFrame.new(28, 0, za + 9) * rotY(90), "ContainerStack", { Count = 1 })
end
themed.silo = function(z, p, f, za)
	kit(z, p, f * CFrame.new(-24, 0, za + 7), "Jersey")
	kit(z, p, f * CFrame.new(-29, 0, za + 7), "Jersey")
	kit(z, p, f * CFrame.new(-30, 0, za + 13), "RadioMast", { Height = 18 })
	kit(z, p, f * CFrame.new(27, 0, za + 10), "CrateStack", { Count = 2 })
end
themed.artillery = function(z, p, f, za)
	kit(z, p, f * CFrame.new(-26, 0, za + 8), "CrateStack", { Count = 4 })
	kit(z, p, f * CFrame.new(28, 0, za + 9), "SandbagLine", { Length = 10 })
	kit(z, p, f * CFrame.new(-31, 0, za + 13) * rotY(90), "SandbagLine", { Length = 8 })
end
themed.drones = function(z, p, f, za)
	kit(z, p, f * CFrame.new(-27, 0, za + 9), "HoldPad", { R = 5 })
	kit(z, p, f * CFrame.new(29, 0, za + 12), "RadioMast", { Height = 16 })
	kit(z, p, f * CFrame.new(24, 0, za + 7), "CrateStack", { Count = 2 })
end
themed.barracks = function(z, p, f, za, trim)
	-- an obstacle course: 3 hurdles, a climbing wall with rungs, a rope frame, a flag
	local cl = cluster(z, z .. "_Dress_Course")
	for i = 0, 2 do
		local c = f * CFrame.new(-30 + i * 5, 0, za + 8)
		for _, s in ipairs({ -1, 1 }) do
			part(cl, "HurdlePost", Vector3.new(0.4, 2.2, 0.4), c * CFrame.new(s * 1.8, 1.1, 0), C.Wood, M.Wood, true)
		end
		part(cl, "HurdleBar", Vector3.new(4, 0.3, 0.3), c * CFrame.new(0, 1.9, 0), C.Hazard, M.Wood, true)
	end
	local w = f * CFrame.new(-26, 0, za + 14)
	part(cl, "ClimbWall", Vector3.new(8, 6, 0.8), w * CFrame.new(0, 3, 0), C.Wood, M.WoodPlanks, true)
	for r = 1, 4 do
		part(cl, "ClimbRung", Vector3.new(7, 0.25, 0.3), w * CFrame.new(0, r * 1.3, 0.5), C.SteelDark, M.Metal, false)
	end
	local rf = f * CFrame.new(27, 0, za + 11)
	for _, s in ipairs({ -1, 1 }) do
		part(cl, "RopeFramePost", Vector3.new(0.6, 9, 0.6), rf * CFrame.new(s * 3.5, 4.5, 0), C.Wood, M.Wood, true)
	end
	part(cl, "RopeFrameBeam", Vector3.new(7.6, 0.6, 0.6), rf * CFrame.new(0, 9, 0), C.Wood, M.Wood, false)
	for _, x in ipairs({ -2, 0, 2 }) do
		part(cl, "ClimbRope", Vector3.new(0.25, 8, 0.25), rf * CFrame.new(x, 4.9, 0), C.Rope, M.Fabric, false)
	end
	part(cl, "FlagPole", Vector3.new(0.35, 12, 0.35), f * CFrame.new(33, 6, za + 4), C.Steel, M.Metal, false)
	part(cl, "Flag", Vector3.new(0.1, 2.4, 4), f * CFrame.new(33, 10.6, za + 6.1) * rotY(90), trim, M.Fabric, false)
	WorldKits.Finish(cl, p)
end
themed.refinery = function(z, p, f, za)
	kit(z, p, f * CFrame.new(-27, 0, za + 8), "DrumGroup", { Count = 4 })
	kit(z, p, f * CFrame.new(-31, 0, za + 13), "DrumGroup", { Count = 3 })
	kit(z, p, f * CFrame.new(27, 0, za + 11), "PipeRun", { Length = 14 })
end
themed.bunker = function(z, p, f, za)
	kit(z, p, f * CFrame.new(-27, 0, za + 9), "SandbagLine", { Length = 10 })
	kit(z, p, f * CFrame.new(26, 0, za + 8), "TankTrap")
	kit(z, p, f * CFrame.new(31, 0, za + 12), "TankTrap")
	kit(z, p, f * CFrame.new(-31, 0, za + 14), "Jersey")
end

--[[ Build the dressing of one built zone (level >= 1). frame = the annex ground frame (local +Z faces the base),
	D = the annex depth. Returns the activity panel (or nil when the zone has no Info). ]]
function RebirthZoneDressing.Build(zoneId: string, level: number, frame: CFrame, D: number, trim: Color3, parent: Instance): BasePart?
	local info = (RebirthZonesConfig :: any).Info[zoneId]
	local z = RebirthZonesConfig.Zones[zoneId]
	if info == nil or z == nil then
		return nil
	end
	local za = D * 0.5 + 2 -- the apron starts just outside the yard's front kerb
	gateway(zoneId, parent, frame, za + 3, trim, string.format("%s · L%d", string.upper(z.Name), level))
	local fn = themed[info.Theme]
	if fn then
		fn(zoneId, parent, frame, za, trim)
	end
	return kiosk(zoneId, parent, frame, 18, za + 9, trim, info.ActionText)
end

--[[ claude-bud JOB 50 part B (2026-10-01; RebirthZonesConfig.Rebuild.Visuals, owner-first): the zone RUN's props become
	part of the build, so the activity reads at a glance and every step marker stands on something real:
	  factory: a conveyor with crates at the line, a part-built flatbed truck at the loading spot;
	  silo: three arming consoles (angled panel in the trim colour, a dark screen);
	  artillery: six target stands (posts, a white board, a red bull);
	  barracks: start / finish gates with a hazard header (the JOB 46 course stays);
	  refinery: four valve stations (a riser, a cross pipe, a red hand wheel);
	  bunker: sandbag nests where the wave comes in.
	Plus the annex reads as a finished place: a low berm on three sides, painted lines across the apron, and ONE
	part-only lamp post at the gate (no Light objects: the JOB 46 / v173 rule; night lights are JOB 54). Parts only; never Neon; never a store-model name; never the yard. ]]
local function prop(zoneId: string, theme: string, label: string, parent: Instance, c: CFrame, trim: Color3)
	local cl = cluster(zoneId, zoneId .. "_Run_" .. theme)
	if theme == "factory" and label == "LOAD TRUCK" then
		part(cl, "TruckChassis", Vector3.new(4, 0.8, 9), c * CFrame.new(0, 1.2, 0), C.SteelDark, M.Metal, true)
		part(cl, "TruckCab", Vector3.new(4, 3, 3), c * CFrame.new(0, 3, -3.5), C.Olive, M.Metal, true)
		part(cl, "TruckWindow", Vector3.new(3.4, 1.2, 0.1), c * CFrame.new(0, 3.6, -5.02), C.Sign, M.Glass, false)
		part(cl, "TruckBedSide", Vector3.new(0.3, 1.2, 5.6), c * CFrame.new(-1.85, 2.2, 1.4), C.Olive, M.Metal, false)
		part(cl, "TruckBedSide", Vector3.new(0.3, 1.2, 5.6), c * CFrame.new(1.85, 2.2, 1.4), C.Olive, M.Metal, false)
		for _, w in ipairs({ { -2.1, -3.2 }, { 2.1, -3.2 }, { -2.1, 2.6 }, { 2.1, 2.6 } }) do
			part(cl, "TruckWheel", Vector3.new(0.8, 1.6, 1.6), c * CFrame.new(w[1], 0.8, w[2]), C.Black, M.Fabric, false)
		end
	elseif theme == "factory" then
		part(cl, "ConveyorBed", Vector3.new(7, 0.6, 2.2), c * CFrame.new(0, 1.3, -2), C.SteelDark, M.Metal, true)
		part(cl, "ConveyorBelt", Vector3.new(7, 0.15, 1.8), c * CFrame.new(0, 1.68, -2), C.Black, M.Fabric, false)
		part(cl, "Crate", Vector3.new(1.6, 1.6, 1.6), c * CFrame.new(-2, 2.55, -2), C.Wood, M.WoodPlanks, false)
		part(cl, "Crate", Vector3.new(1.6, 1.6, 1.6), c * CFrame.new(1.2, 2.55, -2), C.Wood, M.WoodPlanks, false)
	elseif theme == "silo" then
		part(cl, "ConsoleBody", Vector3.new(2.4, 2.6, 1.4), c * CFrame.new(0, 1.3, -1.6), C.SteelDark, M.Metal, true)
		part(cl, "ConsolePanel", Vector3.new(2.4, 0.2, 1.4), c * CFrame.new(0, 2.75, -1.45) * CFrame.Angles(math.rad(-25), 0, 0), trim, M.Metal, false)
		part(cl, "ConsoleScreen", Vector3.new(1.8, 0.05, 0.9), c * CFrame.new(0, 2.88, -1.4) * CFrame.Angles(math.rad(-25), 0, 0), C.Sign, M.Glass, false)
	elseif theme == "artillery" then
		for sx = -1, 1, 2 do
			part(cl, "TargetPost", Vector3.new(0.3, 3.4, 0.3), c * CFrame.new(sx * 1.4, 1.7, -1.6), C.Wood, M.Wood, false)
		end
		part(cl, "TargetBoard", Vector3.new(3, 3, 0.2), c * CFrame.new(0, 3.2, -1.6), Color3.fromRGB(235, 232, 220), M.SmoothPlastic, false)
		part(cl, "TargetBull", Vector3.new(1, 1, 0.22), c * CFrame.new(0, 3.2, -1.6), Color3.fromRGB(190, 40, 36), M.SmoothPlastic, false)
	elseif theme == "barracks" then
		for sx = -1, 1, 2 do
			part(cl, "GatePost", Vector3.new(0.5, 4, 0.5), c * CFrame.new(sx * 2.2, 2, -1.2), C.Wood, M.Wood, false)
		end
		part(cl, "GateBar", Vector3.new(4.9, 0.6, 0.4), c * CFrame.new(0, 4.1, -1.2), C.Hazard, M.Wood, false)
	elseif theme == "refinery" then
		part(cl, "ValveRiser", Vector3.new(0.8, 2.6, 0.8), c * CFrame.new(0, 1.3, -1.6), C.Steel, M.Metal, true)
		part(cl, "ValvePipe", Vector3.new(4, 0.7, 0.7), c * CFrame.new(0, 1.2, -1.6), C.Steel, M.Metal, false)
		part(cl, "ValveWheel", Vector3.new(0.2, 1.6, 1.6), c * CFrame.new(0, 2.8, -1.6) * CFrame.Angles(0, 0, math.rad(90)), Color3.fromRGB(180, 40, 36), M.Metal, false)
	end
	WorldKits.Finish(cl, parent)
end

local function sandbags(zoneId: string, parent: Instance, c: CFrame)
	local cl = cluster(zoneId, zoneId .. "_Run_nest")
	for i = -1, 1 do
		part(cl, "Sandbag", Vector3.new(2, 0.8, 1), c * CFrame.new(i * 2.1, 0.4, 2), C.Olive, M.Fabric, true)
		part(cl, "Sandbag", Vector3.new(2, 0.8, 1), c * CFrame.new(i * 2.1 + 1, 1.2, 2), C.Olive, M.Fabric, false)
	end
	WorldKits.Finish(cl, parent)
end

-- the run's props + the annex edge (berm, apron paint, one lamp); W / D = the annex. Returns the parts added.
function RebirthZoneDressing.BuildRunProps(zoneId: string, frame: CFrame, W: number, D: number, trim: Color3, parent: Instance): number
	local info = (RebirthZonesConfig :: any).Info[zoneId]
	local run = (RebirthZonesConfig :: any).Runs and (RebirthZonesConfig :: any).Runs[zoneId]
	if info == nil or run == nil then
		return 0
	end
	local before = #parent:GetDescendants()
	local done: { [string]: boolean } = {}
	for _, st in ipairs(run.Steps or {}) do
		local key = tostring(st[2]) .. "," .. tostring(st[3])
		if not done[key] then
			done[key] = true
			prop(zoneId, info.Theme, st[1], parent, frame * CFrame.new(st[2], 0, D / 2 + st[3]), trim)
		end
	end
	for _, at in ipairs(run.WaveAt or {}) do
		sandbags(zoneId, parent, frame * CFrame.new(at[1], 0, D / 2 + at[2]))
	end
	local edge = cluster(zoneId, zoneId .. "_Run_edge")
	part(edge, "BermBack", Vector3.new(W + 2, 0.6, 1.2), frame * CFrame.new(0, 0.3, -D / 2 - 1), C.Concrete, M.Concrete, false)
	for sx = -1, 1, 2 do
		part(edge, "BermSide", Vector3.new(1.2, 0.6, D + 2), frame * CFrame.new(sx * (W / 2 + 1), 0.3, 0), C.Concrete, M.Concrete, false)
	end
	for _, dz in ipairs({ 1, 17 }) do
		part(edge, "ApronLine", Vector3.new(W - 6, 0.06, 0.4), frame * CFrame.new(0, 0.05, D / 2 + dz), Color3.fromRGB(235, 232, 220), M.SmoothPlastic, false)
	end
	part(edge, "GateLamp", Vector3.new(0.8, 0.4, 0.8), frame * CFrame.new(0, 10.4, D / 2 + 5), Color3.fromRGB(255, 226, 170), M.SmoothPlastic, false)
	WorldKits.Finish(edge, parent)
	return #parent:GetDescendants() - before
end

return RebirthZoneDressing
