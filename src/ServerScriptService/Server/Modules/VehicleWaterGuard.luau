--!strict
--[[
	fb4 water rule — the server half (VehicleConfig.Drive.WaterRule; geometry in Shared/Util/WaterRule).
	Owner, phone, 2026-09-28: "I can drive on water which shouldn't happen". WE_Water parts collide with nothing, so a car
	rolled on the sand one stud under the see-through sheet.

	VehicleService calls Step(rec, t) from its Heartbeat tick for every live vehicle. Step works at most WaterRule.Hz
	times a second per vehicle: a flat-rectangle test of the chassis centre against VehicleService's WE_Water list
	(turned into plain numbers only when that list changes). No scans and no per-frame work.
	  * Car mode, in water: WE_WaterState = "Bog", WE_WaterExit = the way out (WaterRule.Bog: the flat outward normal of
	    the bank it came over, on the line back to where it was at the last check before it went in; a shallow drift
	    that finds no land on that line takes the bank nearest that check). Cap(model) gives the drive law a ONE-WAY
	    bog: BogAwaySpeed for a move that takes it deeper along that normal (the throttle is cut), up to
	    max(BogExitMin, BogExitFrac x max speed) for one that does not (reverse included). Message to every rider once
	    (at most every MessageGapSeconds). Amphibious ids: "Wade" (WadeSpeedFrac x max speed), except in another
	    player's plot water ("Bog" at BogSpeed both ways, ForeignGraceSeconds). Plane mode: "Ditch" (no cap, PlaneMessage);
	    its grace waits while the pilot can still lift off (seated, at PlaneLiftFrac x WE_TakeoffSpeed or more), up to
	    GraceMaxSeconds after it touched the water.
	  * A driven Car chassis held over deep water with nothing solid under it counts as in the water (one ray, only then),
	    and so does any chassis whose wheel line is more than WheelBelow under the surface (under the sand).
	  * Out again (the centre less than ExitDepth inside) before the grace ends, on the entry side: the attributes clear,
	    the vehicle is kept. Out on ANOTHER shore (the line from the entry, on the land it came from, runs over
	    CrossDeepStuds of deep water; the entry is always on land, so this always runs): it crossed, so it sinks at once.
	    Out of the water at two checks in a row on either side of it (a client that jumped the chassis across, or a lag
	    burst round a water notch): the validator's correction puts it back where it was (no sink, no message). A move the
	    server makes itself (VehicleService's correction PivotTo calls Moved) is never taken for such a jump.
	  * A ground vehicle that went in on public (or its own) water and reaches another player's DockWater / SeaGateWater
	    (it slid along toward that base through an open sea gate): Sink at once.
	  * Grace over (GraceSeconds after it stopped going deeper; each time it gets ProgressStuds shallower than ever
	    before at least ProgressHoldSeconds are left, up to GraceMaxSeconds after the bog), or still too fast once the
	    bog has settled: Sink. Every seat is emptied and disabled, the prompts go off, the server takes the physics,
	    each rider is put on dry land facing away from the water (round the entry; else the R2.3 exit spot beside the
	    vehicle; else the nearest bank with a clear line from the vehicle and never on another player's plot; never a
	    spot on the far side of the water from the entry; else, with no distance cap, the nearest clear dry spot inside
	    PlayArea on rings out to DitchShoreStuds, never on another player's plot; a ditched plane: the spot beside it,
	    else that nearest dry spot), the vehicle loses its collisions and sinks for SinkSeconds, then VehicleService
	    removes it the normal way (no charge, no repair lock, the garage shows it) and the owner gets SinkMessage once
	    the water line has gone (one message at a time).
	While sinking, Step returns true and VehicleService skips the rest of that vehicle's tick (no idle law over it).
	Heli and Boat modes are never checked. Everything a rider touches (Notify, seats, ownership, removal) goes through
	the functions VehicleService hands to Bind(). Headless tests: _State(model), _Rects().
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared", 60)
local Constants = require(Shared.Constants)
local VehicleConfig = require(Shared.Configs.VehicleConfig)
local AdminConfig = require(Shared.Configs.AdminConfig)
local WaterRule = require(Shared.Util.WaterRule)

export type Deps = {
	WaterParts: () -> { BasePart }, -- every WE_Water part (VehicleService's list; a new table when it changes)
	PlotIdOf: (player: Player?) -> number?, -- the player's own BasePlotId (nil = none / not loaded)
	Notify: (player: Player, message: string, kind: string, duration: number?) -> (),
	TakePhysics: (rec: any) -> (), -- Authority "Server" + the server owns every assembly
	Eject: (seat: BasePart) -> (),
	Destroy: (rec: any, message: string?) -> (),
	Correct: (rec: any, cf: CFrame, t: number) -> (), -- the validator's correction back to cf (quiet: no toast, no strike)
	Service: any, -- VehicleService (R2.3 _ExitSpot / _ExitTaken / _ExitHold)
}

type State = {
	InWater: boolean,
	Kind: string, -- "Bog" | "Wade" | "Ditch" while InWater
	Since: number,
	GraceFrom: number, -- the grace counts from here (the bog, moved on while it still went deeper early on)
	Deepest: number, -- the deepest check so far during BogSettleSeconds (studs inside, along Exit)
	Best: number, -- the shallowest check since then (getting out keeps the grace)
	Fast: number,
	Speed: number, -- a plane on the water: its flat speed at the last check (gaining speed = a take-off run)
	Cap: number?, -- the drive law's cap: deeper along Exit (one-way bog) or both ways
	ExitCap: number?, -- not deeper along Exit (one-way bog only)
	Out: CFrame?, -- the chassis at the last check that was not in the water
	OutHigh: boolean, -- ... standing on something over the water there (kerb, pontoon, pier): no crossing test from it
	Exit: Vector3?, -- a ground vehicle's bog: the flat unit outward normal of the bank it came over (the way out)
	Ref: Vector3?, -- ... a point on that bank: depth = (Ref - chassis) . Exit
	Entry: CFrame?, -- ... on the land it came from, where riders go back to (nil: amphibious, plane, or none known)
	Foreign: boolean, -- in another player's plot water
	Clearance: number,
	NextAt: number,
	Sinking: boolean,
	SinkEnd: number,
	Sunk: boolean,
	Why: string?, -- why it sank: "grace" | "fast" | "cross" | "foreign" (tests)
	Jumps: number, -- corrections back across the water (tests)
	Placed: number, -- riders put on dry land by the sink (tests)
	Riders: number, -- riders in the vehicle when it sank (tests)
}

local VehicleWaterGuard = {}

local deps: Deps? = nil
local states: { [Model]: State } = setmetatable({}, { __mode = "k" }) :: any
local lastMessageAt: { [Player]: number } = setmetatable({}, { __mode = "k" }) :: any
local toastUntil: { [Player]: number } = setmetatable({}, { __mode = "k" }) :: any -- the water line shows until then
local rectsFrom: { BasePart }? = nil
local rects: { WaterRule.Rect } = {}

local function rule(): any
	return (VehicleConfig.Drive :: any).WaterRule
end

function VehicleWaterGuard.Bind(d: Deps)
	deps = d
end

-- the water rectangles, rebuilt only when VehicleService hands out a new WE_Water list (every Drive.Water.RefreshSeconds)
local function currentRects(): { WaterRule.Rect }
	local d = deps
	if d == nil then
		return rects
	end
	local parts = d.WaterParts()
	if parts ~= rectsFrom then
		rectsFrom = parts
		rects = WaterRule.Build(parts)
	end
	return rects
end

-- "Ground" | "Amphibious" | "Plane" | nil (never checked)
local function kindOf(rec: any): string?
	local mode = rec.Mode
	if mode == "Car" then
		local amph: any = rule().Amphibious
		local id = rec.Def and rec.Def.Id
		if typeof(amph) == "table" and id ~= nil and amph[id] == true then
			return "Amphibious"
		end
		-- v90: a rollout-gated wader (the Bridge Layer, owner-only first), judged by the vehicle's owner on the server
		local ro: any = rule().AmphibiousRollout
		local gate = if typeof(ro) == "table" and id ~= nil then ro[id] else nil
		if gate == "all" then
			return "Amphibious"
		end
		local owner: any = rec.Owner
		if gate == "owner" and typeof(owner) == "Instance" and owner:IsA("Player") and AdminConfig.IsPlaytestOwner(owner.UserId) == true then
			return "Amphibious"
		end
		return "Ground"
	elseif mode == "Plane" then
		return "Plane"
	end
	return nil
end

local function seatsOf(rec: any): { BasePart }
	local list: { BasePart } = { rec.Seat }
	for _, s in ipairs(rec.Passengers) do
		table.insert(list, s)
	end
	return list
end

local function riderOf(seat: BasePart): (Player?, Humanoid?)
	local occ = if seat.Parent then (seat :: any).Occupant else nil
	if occ == nil or not occ:IsA("Humanoid") then
		return nil, nil
	end
	local ch = occ.Parent
	local player: Player? = if ch then Players:GetPlayerFromCharacter(ch) else nil
	return player, occ
end

local function tell(rec: any, t: number)
	local d = deps
	local cfg = rule()
	local msg = cfg.Message
	if rec.Mode == "Plane" and typeof(cfg.PlaneMessage) == "string" and cfg.PlaneMessage ~= "" then
		msg = cfg.PlaneMessage
	end
	if d == nil or typeof(msg) ~= "string" or msg == "" then
		return
	end
	local dur = math.max(2, cfg.GraceSeconds)
	for _, s in ipairs(seatsOf(rec)) do
		local player = riderOf(s)
		if player and t - (lastMessageAt[player] or -math.huge) >= cfg.MessageGapSeconds then
			lastMessageAt[player] = t
			toastUntil[player] = t + dur
			d.Notify(player, msg, "Warn", dur)
		end
	end
end

-- after the removal: SinkMessage to the owner (whose garage has it back), once the water line has gone
local function tellSunk(rec: any, t: number)
	local d = deps
	local cfg = rule()
	local msg = cfg.SinkMessage
	local owner: Player? = rec.Owner
	if d == nil or owner == nil or typeof(msg) ~= "string" or msg == "" then
		return
	end
	local dur = tonumber(cfg.SinkMessageSeconds) or 3
	local wait = (toastUntil[owner] or -math.huge) - t
	if wait > 0 then
		task.delay(wait + 0.1, function()
			if owner.Parent then
				d.Notify(owner, msg, "Info", dur)
			end
		end)
	elseif owner.Parent then
		d.Notify(owner, msg, "Info", dur)
	end
end

local function setState(model: Model, value: string?)
	if model:GetAttribute("WE_WaterState") ~= value then
		model:SetAttribute("WE_WaterState", value)
	end
end

-- WE_WaterExit: the one-way bog's way out (a flat unit normal) for the driver's client; it uses this as soon as it
-- arrives (its own mirror's until then)
local function setExit(model: Model, value: Vector3?)
	if model:GetAttribute("WE_WaterExit") ~= value then
		model:SetAttribute("WE_WaterExit", value)
	end
end

-- true when the straight line a → b (flat; heights are not tested, so holding the chassis up changes nothing) runs
-- over CrossDeepStuds of deep water in a row and is at least CrossMinStuds long: the vehicle came out on another
-- shore. Never from / to a point where it stood on something over the water (a kerb, pontoon, pier).
local function crossed(a: Vector3, aHigh: boolean, b: Vector3, bHigh: boolean): boolean
	local cfg = rule()
	if aHigh or bHigh then
		return false
	end
	local dx, dz = b.X - a.X, b.Z - a.Z
	if dx * dx + dz * dz < cfg.CrossMinStuds * cfg.CrossMinStuds then
		return false
	end
	return WaterRule.DeepRun(currentRects(), a.X, a.Z, b.X, b.Z, nil, cfg.EnterDepth, cfg.WheelAbove, cfg.WheelBelow, cfg.CrossStep)
		>= cfg.CrossDeepStuds
end

-- ── riders ashore ──────────────────────────────────────────────────────────────────────────────────────────────────
local function flatRot(chassis: BasePart): CFrame
	local look = chassis.CFrame.LookVector
	local f = Vector3.new(look.X, 0, look.Z)
	f = if f.Magnitude > 0.05 then f.Unit else Vector3.new(0, 0, -1)
	return CFrame.lookAt(Vector3.zero, f).Rotation
end

local function characters(): { Instance }
	local list: { Instance } = {}
	for _, p in ipairs(Players:GetPlayers()) do
		if p.Character then
			table.insert(list, p.Character)
		end
	end
	return list
end

-- a driven Car chassis over the water: is something solid (a kerb, pontoon, pier, deck, another vehicle) holding it up
-- above minY? One ray straight down to bottomY; nil hit or the sand under the water = nothing
local function supported(rec: any, pos: Vector3, minY: number, bottomY: number): boolean
	local exclude = characters()
	table.insert(exclude, rec.Model)
	local rp = RaycastParams.new()
	rp.FilterType = Enum.RaycastFilterType.Exclude
	rp.FilterDescendantsInstances = exclude
	rp.RespectCanCollide = true
	local hit = Workspace:Raycast(pos, Vector3.new(0, math.min(-1, bottomY - pos.Y), 0), rp)
	return hit ~= nil and hit.Position.Y > minY
end

-- the rider's own plot pad (any other WE_BasePlot pad holding (x, z) is someone else's plot); pads = the tagged pads,
-- fetched once per rider by the caller
local function onForeignPlot(pads: { Instance }, x: number, z: number, ownPlot: number?): boolean
	for _, pad in ipairs(pads) do
		if pad:IsA("BasePart") and tonumber(pad:GetAttribute("PlotId")) ~= ownPlot then
			local lp = pad.CFrame:PointToObjectSpace(Vector3.new(x, pad.Position.Y, z))
			if math.abs(lp.X) <= pad.Size.X * 0.5 and math.abs(lp.Z) <= pad.Size.Z * 0.5 then
				return true
			end
		end
	end
	return false
end

type Ctx = {
	Model: Model,
	Char: Instance,
	Hip: number,
	Rot: CFrame,
	Rays: RaycastParams,
	Stand: OverlapParams,
	WheelY: number,
	Floor: number, -- the lowest bank: a ray reaches down to it even from a vehicle held up over the water
	OwnPlot: number?,
	Pads: { Instance }, -- every WE_BasePlot pad (fetched once per rider)
}

-- a clear dry stand spot round `anchor` (rings of 3 studs, 8 directions), seen from `from`; nil when none
local function ringSpot(c: Ctx, anchor: Vector3, from: Vector3, noForeign: boolean): CFrame?
	local cfg = rule()
	local ex: any = (VehicleConfig.Drive :: any).ExitSpot
	local hw, standH = ex.HalfWidth, ex.StandHeight
	local box = Vector3.new(hw * 2, standH, hw * 2)
	local svc = (deps :: Deps).Service
	local rs = currentRects()
	for ring = 0, 3 do
		for k = 0, (if ring == 0 then 0 else 7) do
			local a = k * math.pi / 4
			local x, z = anchor.X + math.cos(a) * ring * 3, anchor.Z + math.sin(a) * ring * 3
			local top = c.WheelY + ex.StepUp
			local drop = ex.StepUp + ex.MaxDrop + math.max(0, c.WheelY - c.Floor)
			local hit = Workspace:Raycast(Vector3.new(x, top, z), Vector3.new(0, -drop, 0), c.Rays)
			if
				hit
				and hit.Material ~= Enum.Material.Water
				and not CollectionService:HasTag(hit.Instance, Constants.Tags.Water)
				and not WaterRule.InAny(rs, x, z, cfg.ShoreMargin)
				and not (noForeign and onForeignPlot(c.Pads, x, z, c.OwnPlot))
			then
				local gy = hit.Position.Y
				local stand = CFrame.new(x, gy + c.Hip, z) * c.Rot
				if
					#Workspace:GetPartBoundsInBox(CFrame.new(x, gy + 0.3 + standH * 0.5, z) * c.Rot, box, c.Stand) == 0
					and not (svc._ExitTaken and svc._ExitTaken(stand, c.Char))
					and Workspace:Raycast(from, stand.Position - from, c.Rays) == nil
				then
					return stand
				end
			end
		end
	end
	return nil
end

-- where this rider stands after the sink (nil = no clear dry spot: left as Roblox's jump-out leaves him)
local function shoreSpot(rec: any, st: State, seat: BasePart, hum: Humanoid, hrp: BasePart): CFrame?
	local cfg = rule()
	local d = deps :: Deps
	local char = hum.Parent :: Instance
	local hh = hum.HipHeight
	local hip = (if typeof(hh) == "number" and hh > 0.05 then hh + hrp.Size.Y * 0.5 else 3) + 0.05
	local exclude = characters()
	table.insert(exclude, rec.Model)
	local rp = RaycastParams.new()
	rp.FilterType = Enum.RaycastFilterType.Exclude
	rp.FilterDescendantsInstances = exclude
	rp.RespectCanCollide = true
	local op = OverlapParams.new()
	op.FilterType = Enum.RaycastFilterType.Exclude
	op.FilterDescendantsInstances = { char, rec.Model }
	op.RespectCanCollide = true
	op.MaxParts = 1
	local pos = rec.Chassis.Position
	local floor = math.huge
	for _, r in ipairs(currentRects()) do
		floor = math.min(floor, r.Top - 1)
	end
	local wheelY = pos.Y - st.Clearance
	if floor < math.huge and wheelY < floor then
		wheelY = floor -- a chassis under the sand (Step counts it as in the water): look for ground from the floor up
	end
	local c: Ctx = {
		Model = rec.Model,
		Char = char,
		Hip = hip,
		Rot = flatRot(rec.Chassis),
		Rays = rp,
		Stand = op,
		WheelY = wheelY,
		Floor = if floor < math.huge then floor else wheelY,
		OwnPlot = d.PlotIdOf(Players:GetPlayerFromCharacter(char)),
		Pads = CollectionService:GetTagged(Constants.Tags.BasePlot),
	}
	-- a sunk vehicle is never a way across: with an entry, a spot on the far side of the water from it is never used
	local entry = st.Entry
	local function entrySide(spot: CFrame?): CFrame?
		if spot == nil or entry == nil then
			return spot
		end
		local e = entry.Position
		local p = spot.Position
		return if crossed(e, false, p, false) then nil else spot
	end
	-- 1) back where the vehicle went in: round its entry, seen from there
	if entry and (entry.Position - pos).Magnitude <= cfg.ReturnMaxStuds then
		local spot = ringSpot(c, entry.Position, entry.Position + Vector3.new(0, 2, 0), false)
		if spot then
			return spot
		end
	end
	-- 2) the R2.3 exit spot beside the vehicle (dry, clear, a clear line from inside the kit)
	local function exitSpot(): CFrame?
		local svc = d.Service
		if svc._ExitSpot then
			local ok, spot = pcall(svc._ExitSpot, rec.Model, rec.Chassis, seat, hip, char)
			if ok and spot then
				return entrySide(spot)
			end
		end
		return nil
	end
	-- 3) the nearest bank, seen from the vehicle, never on another player's plot
	local function bankSpot(): CFrame?
		local from = pos + Vector3.new(0, 3, 0)
		for _, p in ipairs(WaterRule.ShorePoints(currentRects(), pos.X, pos.Z, cfg.ShoreStep, cfg.ShoreSearchStuds, cfg.ShoreMargin)) do
			local spot = entrySide(ringSpot(c, Vector3.new(p.X, pos.Y, p.Z), from, true))
			if spot then
				return spot
			end
		end
		return nil
	end
	-- 4) no distance cap: the nearest clear dry spot on rings round the vehicle (ShoreStep apart up to
	-- ShoreSearchStuds, then DitchStep apart up to DitchShoreStuds), inside PlayArea (the dry land inside the ring
	-- canal and north of the sea), never on another player's plot, never on the far side of the water from the entry.
	-- The rings start just inside the nearest bank the 16 exact rays find (nothing nearer can be dry along them).
	local function landSpot(): CFrame?
		local rs = currentRects()
		local maxR = tonumber(cfg.DitchShoreStuds) or 0
		local nx, _, _, _, d0 = WaterRule.NearestBank(rs, pos.X, pos.Z, maxR)
		if nx == nil then
			return nil
		end
		local area: any = cfg.PlayArea
		local ax = if typeof(area) == "table" then tonumber(area.X) else nil
		local az0 = if typeof(area) == "table" then tonumber(area.ZMin) else nil
		local az1 = if typeof(area) == "table" then tonumber(area.ZMax) else nil
		local step, far = math.max(1, cfg.ShoreStep), math.max(1, tonumber(cfg.DitchStep) or cfg.ShoreStep)
		local arc = math.max(4, tonumber(cfg.DitchArcStuds) or 24)
		local tries = math.max(1, tonumber(cfg.DitchTries) or 40)
		local ex: any = (VehicleConfig.Drive :: any).ExitSpot
		local r = math.max(step, d0 - 2 * step)
		while r <= maxR and tries > 0 do
			local n = math.clamp(math.ceil(2 * math.pi * r / arc), 16, 128)
			for k = 0, n - 1 do
				local a = k * 2 * math.pi / n
				local x, z = pos.X + math.cos(a) * r, pos.Z + math.sin(a) * r
				if
					(ax == nil or math.abs(x) <= ax)
					and (az0 == nil or z >= az0)
					and (az1 == nil or z <= az1)
					and not WaterRule.InAny(rs, x, z, cfg.ShoreMargin)
					and not onForeignPlot(c.Pads, x, z, c.OwnPlot)
				then
					local from = Vector3.new(x, c.WheelY + ex.StepUp + 0.5, z)
					local spot = entrySide(ringSpot(c, Vector3.new(x, pos.Y, z), from, true))
					if spot then
						return spot
					end
					tries -= 1
					if tries <= 0 then
						return nil
					end
				end
			end
			r += if r < cfg.ShoreSearchStuds then step else far
		end
		return nil
	end
	-- a ditched plane: nobody is left out at sea, however far it rolled (in another player's plot water: off that plot
	-- first, as below)
	if st.Kind == "Ditch" then
		if st.Foreign then
			return landSpot() or exitSpot()
		end
		return exitSpot() or landSpot()
	end
	-- in another player's plot water the bank outside that plot comes before the spot beside the vehicle
	if st.Foreign then
		return bankSpot() or exitSpot() or landSpot()
	end
	return exitSpot() or bankSpot() or landSpot()
end

-- one rider, once the seat has let go of him (retried every 0.1 s, PlaceTries times)
local function placeRider(rec: any, st: State, seat: BasePart, hum: Humanoid, tries: number)
	local char = hum.Parent
	local hrp = if char then char:FindFirstChild("HumanoidRootPart") else nil
	if not (char and char:IsA("Model") and hrp and hrp:IsA("BasePart")) or hum.Health <= 0 or rec.Chassis.Parent == nil then
		return
	end
	if hum.SeatPart ~= nil and hum.SeatPart ~= seat then
		return -- already in another seat
	end
	local root: BasePart? = hrp.AssemblyRootPart
	if hum.SeatPart == seat or (root ~= nil and root == rec.Chassis.AssemblyRootPart) then
		if tries > 1 then
			task.delay(0.1, placeRider, rec, st, seat, hum, tries - 1) -- the seat has not let go of him yet
		end
		return
	end
	local ok, spot = pcall(shoreSpot, rec, st, seat, hum, hrp)
	if not ok or spot == nil then
		return
	end
	-- facing away from the water (the way out, else away from the vehicle): the garage's "in front of you" is land
	local away = st.Exit or (spot.Position - rec.Chassis.Position)
	away = Vector3.new(away.X, 0, away.Z)
	if away.Magnitude > 0.5 then
		spot = CFrame.new(spot.Position) * CFrame.lookAt(Vector3.zero, away.Unit).Rotation
	end
	require(script.Parent.MoveDebug).Note(char, "PivotTo", "VehicleWaterGuard.placeRider") -- v123 tagged
	char:PivotTo(spot)
	pcall(function()
		hrp.AssemblyLinearVelocity = Vector3.zero
		hrp.AssemblyAngularVelocity = Vector3.zero
	end)
	local svc = (deps :: Deps).Service
	if svc._ExitHold then
		svc._ExitHold(spot, char) -- R2.2: the next rider gets another spot
	end
	st.Placed += 1
end

local function sink(rec: any, st: State, t: number)
	local cfg = rule()
	local d = deps :: Deps
	local model: Model = rec.Model
	st.Sinking = true
	st.SinkEnd = t + cfg.SinkSeconds
	setState(model, "Sink")
	-- nobody boards or stays: every seat off, then empty; the Drive / Ride prompts off
	local riders: { { Seat: BasePart, Hum: Humanoid } } = {}
	for _, s in ipairs(seatsOf(rec)) do
		local _, hum = riderOf(s)
		if hum then
			table.insert(riders, { Seat = s, Hum = hum })
		end
		local seatAny: any = s
		pcall(function()
			seatAny.Disabled = true
		end)
		d.Eject(s)
	end
	st.Riders = #riders
	for _, name in ipairs({ "WE_DrivePrompt", "WE_RidePrompt" }) do
		local where = if name == "WE_DrivePrompt" then rec.Seat else rec.Chassis
		local prompt = where:FindFirstChild(name)
		if prompt and prompt:IsA("ProximityPrompt") then
			prompt.Enabled = false
			prompt:SetAttribute("WE_Open", false)
		end
	end
	d.TakePhysics(rec)
	task.defer(function()
		for _, r in ipairs(riders) do
			placeRider(rec, st, r.Seat, r.Hum, math.max(1, cfg.PlaceTries))
		end
		-- the sink: no collisions (the one pass over this model's parts, once), straight down, level
		if rec.Chassis.Parent == nil then
			return
		end
		for _, p in ipairs(model:GetDescendants()) do
			if p:IsA("BasePart") and p.CanCollide then
				p.CanCollide = false
			end
		end
		pcall(function()
			local f = rec.Force
			rec.LV.MaxAxesForce = Vector3.new(f, f, f)
			rec.LV.VectorVelocity = Vector3.new(0, -cfg.SinkSpeed, 0)
			rec.AO.CFrame = flatRot(rec.Chassis)
		end)
	end)
end

local function leave(model: Model, st: State)
	st.InWater = false
	st.Cap = nil
	st.ExitCap = nil
	st.Exit = nil
	st.Ref = nil
	st.Entry = nil
	st.Fast = 0
	st.Why = nil
	setState(model, nil)
	setExit(model, nil)
end

--[[ One tick for one vehicle (VehicleService tickRecord, every Heartbeat). Returns true while the vehicle is sinking:
	the caller then skips the rest of its tick. ]]
function VehicleWaterGuard.Step(rec: any, t: number): boolean
	local cfg = rule()
	local d = deps
	if d == nil or typeof(cfg) ~= "table" or cfg.Enabled ~= true then
		return false
	end
	local model: Model = rec.Model
	local st = states[model]
	if st and st.Sinking then
		if t >= st.SinkEnd and not st.Sunk then
			st.Sunk = true
			d.Destroy(rec, nil)
			tellSunk(rec, t) -- "Vehicle safe in garage", once the water line has gone
		end
		return true
	end
	if st and t < st.NextAt then
		return false
	end
	local kind = kindOf(rec)
	if kind == nil or model:GetAttribute("WE_Destroyed") == true then
		if st and st.InWater then
			leave(model, st)
		end
		return false
	end
	local s: State
	if st then
		s = st
	else
		s = {
			InWater = false,
			Kind = "",
			Since = t,
			GraceFrom = t,
			Deepest = 0,
			Best = 0,
			Fast = 0,
			Speed = 0,
			Cap = nil,
			ExitCap = nil,
			Out = nil,
			OutHigh = false,
			Exit = nil,
			Ref = nil,
			Entry = nil,
			Foreign = false,
			Clearance = tonumber(model:GetAttribute("WE_GroundClearance")) or 1,
			NextAt = t,
			Sinking = false,
			SinkEnd = 0,
			Sunk = false,
			Why = nil,
			Placed = 0,
			Riders = 0,
			Jumps = 0,
		}
		states[model] = s
	end
	s.NextAt = t + 1 / math.max(1, cfg.Hz)
	local cf = rec.Chassis.CFrame
	local pos = cf.Position
	local rs = currentRects()
	local own = d.PlotIdOf(rec.Owner)
	local wheelY = pos.Y - s.Clearance
	-- in = EnterDepth inside; out again = less than ExitDepth inside
	local depthNow = if s.InWater then cfg.ExitDepth or cfg.EnterDepth else cfg.EnterDepth
	local centre, deep, foreign, top = WaterRule.Probe(rs, pos.X, pos.Z, wheelY, depthNow, cfg.WheelAbove, own, cfg.WheelBelow)
	if
		not centre
		and top ~= nil
		and kind ~= "Plane"
		and wheelY > top + cfg.WheelAbove
		and wheelY - top <= cfg.HoverMaxStuds
		and (rec.Seat :: any).Occupant ~= nil
		and not supported(rec, pos, top + cfg.WheelAbove, top - cfg.WheelBelow)
	then
		-- held over the water with nothing under it (a client that floats the chassis): it stands where it would sink to
		centre, deep, foreign = WaterRule.Probe(rs, pos.X, pos.Z, top, depthNow, cfg.WheelAbove, own, cfg.WheelBelow)
	elseif not centre and top ~= nil and wheelY < top - cfg.WheelBelow then
		-- under the water's floor (nothing is down there: a client that holds the chassis under the sand): it is in the
		-- water over it, and never counts as standing on something high
		centre, deep, foreign = WaterRule.Probe(rs, pos.X, pos.Z, top, depthNow, cfg.WheelAbove, own, cfg.WheelBelow)
	end
	-- on something over the water (a kerb, pontoon, pier) or in the air over it: never counted for a crossing
	local high = top ~= nil and not centre and wheelY > top + cfg.WheelAbove
	if not deep then
		if s.InWater then
			-- out again: a ground vehicle out on ANOTHER shore crossed the water (riders go back round the entry)
			-- (the entry is on land by construction, so only the exit point can be exempt: on a kerb / pontoon / pier)
			if s.Kind == "Bog" and s.Entry and crossed(s.Entry.Position, false, pos, high) then
				s.Why = "cross"
				sink(rec, s, t)
				return true
			end
			leave(model, s)
		elseif kind == "Ground" and s.Out and crossed(s.Out.Position, s.OutHigh, pos, high) then
			-- out of the water at this check and the last one, on either side of it: the chassis jumped across (a
			-- modified client, or a lag burst round a water notch). The validator's correction puts it back where it
			-- was: no sink, no message (lag never costs a vehicle)
			s.Jumps += 1
			d.Correct(rec, s.Out, t)
			return false
		end
		s.Out = cf
		s.OutHigh = high
		return false
	end
	local want = if kind == "Plane" then "Ditch" elseif kind == "Amphibious" and not foreign then "Wade" else "Bog"
	if not s.InWater or s.Kind ~= want then
		s.InWater = true
		s.Kind = want
		s.Since = t
		s.GraceFrom = t
		s.Fast = 0
		local v0 = rec.Chassis.AssemblyLinearVelocity
		s.Speed = if typeof(v0) == "Vector3" then math.sqrt(v0.X * v0.X + v0.Z * v0.Z) else 0
		s.Foreign = foreign
		-- the one-way bog (ground vehicles only): the way out is the outward normal of the bank it came over (on the
		-- line back to where it was at the last check before it went in); the entry is on that land, EntryPush past it
		s.Exit, s.Ref, s.Entry = nil, nil, nil
		if want == "Bog" and kind == "Ground" then
			local o = s.Out
			local op = if o then o.Position else pos
			local nx, nz, rx, rz, ex, ez = WaterRule.Bog(rs, pos.X, pos.Z, op.X, op.Z, cfg.EntryPush, cfg.EntrySearchStuds)
			if nx ~= nil then
				s.Exit = Vector3.new(nx, 0, nz)
				s.Ref = Vector3.new(rx, pos.Y, rz)
				if o then
					s.Entry = CFrame.new(ex, op.Y, ez) * o.Rotation
				end
			end
		end
		local depth0 = if s.Exit and s.Ref then (s.Ref - pos):Dot(s.Exit) else 0
		s.Deepest = depth0
		s.Best = depth0
		local maxS = tonumber(rec.Params.MaxSpeed) or 40
		s.ExitCap = if s.Exit then math.max(cfg.BogExitMin, cfg.BogExitFrac * maxS) else nil
		s.Cap = if s.Exit then cfg.BogAwaySpeed
			elseif want == "Bog" then cfg.BogSpeed
			elseif want == "Wade" then cfg.WadeSpeedFrac * maxS
			else nil
		setState(model, want)
		setExit(model, s.Exit)
		if want ~= "Wade" then
			tell(rec, t)
		end
	end
	if want == "Wade" then
		return false
	end
	if kind == "Ground" and foreign and not s.Foreign then
		-- it went in on public (or its own) water and is now in another player's plot water: it slid along the water
		-- toward that base (through an open sea gate), which no back-out move does
		s.Why = "foreign"
		sink(rec, s, t)
		return true
	end
	local grace = if kind == "Amphibious" then cfg.ForeignGraceSeconds else cfg.GraceSeconds
	if kind == "Plane" then
		-- the pilot can still take off (a touch-and-go, a long landing that ran into the sea, or a take-off run from
		-- the water): the grace waits while it rolls at its lift-off speed or more, or gains speed, up to
		-- PlaneLiftMaxSeconds after it touched the water. Braking, rolling to a stop or stopped: the grace runs (ditched)
		local v = rec.Chassis.AssemblyLinearVelocity
		local sp = if typeof(v) == "Vector3" then math.sqrt(v.X * v.X + v.Z * v.Z) else 0
		local vto = tonumber(model:GetAttribute("WE_TakeoffSpeed")) or math.huge
		if
			(rec.Seat :: any).Occupant ~= nil
			and t - s.Since < (tonumber(cfg.PlaneLiftMaxSeconds) or 0)
			and (sp >= vto * (tonumber(cfg.PlaneLiftFrac) or 1) or sp > s.Speed + (tonumber(cfg.PlaneGainStuds) or math.huge))
		then
			s.GraceFrom = t
		end
		s.Speed = sp
	end
	local n, ref = s.Exit, s.Ref
	if n and ref then
		local depth = (ref - pos):Dot(n) -- studs inside, along the way out
		-- the grace counts from when it stopped going deeper (only early on: a client that creeps on is caught below)
		if depth > s.Deepest + 0.5 and t - s.Since <= cfg.BogSettleSeconds then
			s.Deepest = depth
			s.Best = depth
			s.GraceFrom = t
		end
		-- getting out (a shallow drift backs out slowly): each ProgressStuds shallower than ever leaves at least
		-- ProgressHoldSeconds, up to GraceMaxSeconds after the bog
		if depth < s.Best - cfg.ProgressStuds then
			s.Best = depth
			if t - s.Since <= cfg.GraceMaxSeconds then
				s.GraceFrom = math.max(s.GraceFrom, t - grace + cfg.ProgressHoldSeconds)
			end
		end
	end
	local over = t - s.GraceFrom >= grace
	if over then
		s.Why = "grace"
	elseif want == "Bog" then
		-- a client that ignores the bog (it has had BogSettleSeconds to act): faster than its cap, or going deeper
		local v = rec.Chassis.AssemblyLinearVelocity
		local vx, vz = 0, 0
		if typeof(v) == "Vector3" then
			vx, vz = v.X, v.Z
		end
		local val: any = (VehicleConfig.Drive :: any).Validation
		local limit = (s.ExitCap or s.Cap or cfg.BogSpeed) * val.SpeedTolerance + val.SpeedSlack
		local deeper = if n then -(vx * n.X + vz * n.Z) else 0 -- studs/s deeper along the way out
		local tooFast = math.sqrt(vx * vx + vz * vz) > limit
			or (n ~= nil and deeper > (s.Cap or 0) * val.SpeedTolerance + val.SpeedSlack)
		if t - s.Since >= cfg.BogSettleSeconds and tooFast then
			s.Fast += 1
			over = s.Fast >= cfg.FastSamples
			s.Why = if over then "fast" else nil
		else
			s.Fast = 0
		end
	end
	if over then
		sink(rec, s, t)
		return true
	end
	return false
end

--[[ The drive law's water cap while this vehicle bogs / wades (VehicleService senseFor): (cap, exit, exitCap). With a
	way out (exit: the one-way bog's flat unit normal) cap is the speed of a move that takes it deeper along exit and
	exitCap that of one that does not; without one, cap holds both ways. nil, nil, nil when it is not in water. ]]
function VehicleWaterGuard.Cap(model: Model): (number?, Vector3?, number?)
	local st = states[model]
	if st and st.InWater and not st.Sinking then
		return st.Cap, st.Exit, st.ExitCap
	end
	return nil, nil, nil
end

--[[ VehicleService moved the chassis itself (the validator's correction PivotTo to its last valid point): that point is
	where it was "at the last check", so the next check never takes the server's own move for a jump across water. ]]
function VehicleWaterGuard.Moved(model: Model, cf: CFrame)
	local st = states[model]
	if st then
		st.Out = cf
		st.OutHigh = false
	end
end

--[[ VehicleService _OnSeatLeft for a Plane: a rider who leaves a plane that sits on the water (EXIT while it is
	ditched) goes ashore the same way as at the sink (the spot beside it, else the nearest dry land, no distance cap).
	The R2.3 exit move covers Car mode only. true when the guard placed (or will place) him. ]]
function VehicleWaterGuard.Left(rec: any, seat: BasePart, hum: Humanoid): boolean
	local st = states[rec.Model]
	if st == nil or not st.InWater or st.Kind ~= "Ditch" or st.Sinking then
		return false
	end
	task.defer(placeRider, rec, st, seat, hum, math.max(1, rule().PlaceTries))
	return true
end

-- true from the sink until the removal (VehicleService _OnSeatLeft: the R2.3 exit move stays out of it)
function VehicleWaterGuard.Sinking(model: Model): boolean
	local st = states[model]
	return st ~= nil and st.Sinking
end

-- test hooks (headless stand-in)
function VehicleWaterGuard._State(model: Model): any
	return states[model]
end
function VehicleWaterGuard._Rects(): { WaterRule.Rect }
	return currentRects()
end

return VehicleWaterGuard
