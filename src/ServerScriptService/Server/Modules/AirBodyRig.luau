--!strict
--[[ air-looks (2026-09-28): the extras a store AIRCRAFT body needs on top of the vscale fit (VisualAssetService
	fitBodyToKit / placeKitOnBody). Every one of them is read from the vehicle's VisualAssetConfig ref and does nothing
	when the ref leaves it out, so kit-only aircraft and every car / boat body are unchanged.

	  • AnchorShift (ref.BodyAnchor = a BodySeats name): a Roblox-size aircraft is far longer than its kit, and its
	    cockpit sits well ahead of the body's box centre, past the kit's collidable box, where placeKitOnBody would clamp
	    the pilot seat back into the fuselage. Instead the whole BODY moves along the kit's length (chassis Z; it stays
	    centred across) so that seat's body point lands level with the kit seat of the same name: the pilot sits in the
	    cockpit, the kit (physics, collisions, the drive movers, the HUD) stays exactly where it was. Other BodySeats move
	    with the body (placeKitOnBody still keeps every seat inside the kit's box).
	  • KitFloor (ref.BodyFloor = "Collide"): an aircraft has no physics wheels, so the fit would put the body's lowest
	    point on the chassis bottom while the kit's skids / wheels (its lowest collidable parts) stand lower on the pad:
	    the parked body would float. This gives the lowest collidable kit point (seats excepted) instead.
	  • Apply, after placeKitOnBody:
	      - BodyMounts: each named kit part (the AirWeaponService muzzle mounts: Nose, WingL, StubWingL, Cockpit ...) is
	        re-welded with its front face centre on a point of the body (unscaled body box frame, like BodySeats), so guns
	        fire from the body's nose and missiles leave its wing rails (AirWeaponService adds MuzzleForward / MuzzleDrop
	        to that face). Only non-colliding, non-seat kit parts move; the chassis never does.
	      - RotorParts: the named body (or kit) parts get a Motor6D to the chassis instead of their WeldConstraint, with
	        the joint's Y axis on the rotor axis, tagged WE_RotorJoint (attribute WE_RotorRps). Each client turns them
	        (AircraftBodyClient: Motor6D.Transform, local only, never replicated); the server never moves them, so
	        physics and replication are unchanged.
	      - ChaseCamera: WE_CamMinZoom on the model = the body's reach from the pilot seat (its farthest end: tail, nose
	        or wing tip) + AirBody.ChaseCameraMargin, capped at ChaseCameraMax, for AircraftBodyClient's seated camera.
	      - BodyHitBoxes (air2 fix1, with AirBody.BodyHitBoxes on): invisible hit plates (Parts "WE_HitPlate": Transparency 1,
	        CanQuery, never CanCollide / CanTouch, Massless, welded) over the fitted body (unscaled boxes, like BodySeats),
	        so a shot hits the aircraft players see. The kit's hidden non-colliding parts (its old nose, wings, fins ...)
	        stop taking shots; the chassis, the seats and the visible gear keep theirs. Physics and collisions unchanged.
	      - A BodyMounts kit part (a muzzle point on the body) never takes a shot (CanQuery false): moved to a wing tip it
	        would be a hit box beside the aircraft.
	      - BodyGear (air2 fix1): drawn landing gear (Folder "WE_GearDress" in the body: a strut and a wheel per leg), the
	        wheel on the kit's floor line (its lowest collidable point), the strut up into the body box over the leg. Never
	        collides, massless, no shadow; it takes shots like the body plates. The hidden kit gear still stands the jet.
	      - TailGuard (air2 fix1, with AirBody.TailGuard.Enabled): WE_TailGuard on the model = "MinPitch,LeadSeconds;x,y,z;..."
	        the four bottom corners of every body part box in the chassis frame, Margin lower (the drawn gear excepted).
	        The driver's plane law (VehicleDriveClient Laws.TailGuard) keeps them over the ground near the ground.
	  • StripSigns: a store body's BillboardGui / SurfaceGui signs always go (whole model or pack piece), its decals with
	    ref.StripDecals.
	Kit parts are moved with an unweld / set / weld (a CFrame set on a welded part would move the whole aircraft). ]]

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- server module: the Rojo place ships ReplicatedStorage.Shared, so index it (no WaitForChild without a timeout)
local VisualAssetConfig = require(ReplicatedStorage.Shared.Configs.VisualAssetConfig)

local AirBodyRig = {}

AirBodyRig.RotorTag = "WE_RotorJoint"
AirBodyRig.RotorJointName = "WE_RotorJoint"
AirBodyRig.HitPlateName = "WE_HitPlate"
AirBodyRig.GearName = "WE_GearDress"

local AXES: { [string]: CFrame } = {
	Y = CFrame.identity,
	X = CFrame.Angles(0, 0, -math.pi / 2), -- joint Y -> chassis X
	Z = CFrame.Angles(math.pi / 2, 0, 0), -- joint Y -> chassis Z
}

-- chassis-frame half extent of a part along Y, and its full extents
local function extents(rel: CFrame, size: Vector3): Vector3
	local h = size * 0.5
	local r, u, l = rel.RightVector, rel.UpVector, rel.LookVector
	return Vector3.new(
		math.abs(r.X) * h.X + math.abs(u.X) * h.Y + math.abs(l.X) * h.Z,
		math.abs(r.Y) * h.X + math.abs(u.Y) * h.Y + math.abs(l.Y) * h.Z,
		math.abs(r.Z) * h.X + math.abs(u.Z) * h.Y + math.abs(l.Z) * h.Z
	)
end

-- the box Roblox draws for a part (as VisualAssetService drawnSize: a round Part is drawn smaller than its Size box)
local function drawn(p: BasePart): Vector3
	local size = p.Size
	if p:IsA("Part") then
		if p.Shape == Enum.PartType.Cylinder then
			local d = math.min(size.Y, size.Z)
			return Vector3.new(size.X, d, d)
		elseif p.Shape == Enum.PartType.Ball then
			local d = math.min(size.X, size.Y, size.Z)
			return Vector3.new(d, d, d)
		end
	end
	return size
end

local function isSeat(p: Instance): boolean
	return p:IsA("Seat") or p:IsA("VehicleSeat")
end

-- The lowest point of the kit's collidable parts (seats excepted) in the chassis frame, else `fallback`.
function AirBodyRig.KitFloor(hostModel: Model, primary: BasePart, fallback: number): number
	local low: number? = nil
	for _, d in ipairs(hostModel:GetDescendants()) do
		if d:IsA("BasePart") and d.CanCollide and not isSeat(d) then
			local rel = primary.CFrame:ToObjectSpace(d.CFrame)
			local b = rel.Position.Y - extents(rel, d.Size).Y
			if low == nil or b < low then
				low = b
			end
		end
	end
	return if low ~= nil then math.min(low, fallback) else fallback
end

-- The chassis-frame X / Z move that puts ref.BodySeats[ref.BodyAnchor] (scaled by s, turned by yawDeg, measured from
-- the body box centre as fitBodyToKit places it) over the kit seat named ref.BodyAnchor. Zero when not configured.
function AirBodyRig.AnchorShift(hostModel: Model, primary: BasePart, ref: any, s: number, yawDeg: number): Vector3
	local name = ref.BodyAnchor
	local seats = ref.BodySeats
	if typeof(name) ~= "string" or typeof(seats) ~= "table" then
		return Vector3.zero
	end
	local top = seats[name]
	local kitSeat = hostModel:FindFirstChild(name)
	if typeof(top) ~= "Vector3" or kitSeat == nil or not kitSeat:IsA("BasePart") then
		return Vector3.zero
	end
	local k = primary.CFrame:PointToObjectSpace(kitSeat.Position)
	local v = CFrame.Angles(0, math.rad(yawDeg), 0) * (top * s)
	-- along the kit's length only: the body stays centred across the kit (its seats' X still clamp into the kit box)
	return Vector3.new(0, 0, k.Z - v.Z)
end

-- unweld `part` from the chassis (WeldConstraints either side), set its CFrame, weld it again
local function reweld(primary: BasePart, part: BasePart, cf: CFrame)
	for _, holder in ipairs({ primary :: Instance, part :: Instance }) do
		for _, w in ipairs(holder:GetChildren()) do
			if w:IsA("WeldConstraint") and ((w.Part0 == primary and w.Part1 == part) or (w.Part0 == part and w.Part1 == primary)) then
				w:Destroy()
			end
		end
	end
	part.CFrame = cf
	local w = Instance.new("WeldConstraint")
	w.Part0 = primary
	w.Part1 = part
	w.Parent = primary
end

-- the fitted body's frame (chassis X / Z shift, lowest point, turned by the ref's Yaw, as fitBodyToKit placed it) and
-- the body's reach from the kit's DriverSeat in the chassis X / Z plane (its farthest end in any orbit direction)
local function bodyBase(hostModel: Model, primary: BasePart, clone: Model, ref: any): (CFrame?, number)
	local bottom, front, rear, side = math.huge, math.huge, -math.huge, 0
	for _, d in ipairs(clone:GetDescendants()) do
		if d:IsA("BasePart") then
			local rel = primary.CFrame:ToObjectSpace(d.CFrame)
			local e = extents(rel, drawn(d))
			bottom = math.min(bottom, rel.Position.Y - e.Y)
			front, rear = math.min(front, rel.Position.Z - e.Z), math.max(rear, rel.Position.Z + e.Z)
			side = math.max(side, math.abs(rel.Position.X) + e.X)
		end
	end
	if bottom == math.huge then
		return nil, 0
	end
	local seat = hostModel:FindFirstChild("DriverSeat")
	local seatZ = if seat and seat:IsA("BasePart") then primary.CFrame:PointToObjectSpace(seat.Position).Z else 0
	local reach = math.max(rear - seatZ, seatZ - front, side)
	local shift = clone:GetAttribute("WE_BodyShift")
	local sh = if typeof(shift) == "Vector3" then shift else Vector3.zero
	return primary.CFrame * CFrame.new(sh.X, bottom, sh.Z) * CFrame.Angles(0, math.rad(tonumber(ref.Yaw) or 0), 0), reach
end

local function namedParts(root: Instance, names: { string }): { BasePart }
	local want: { [string]: boolean } = {}
	for _, n in ipairs(names) do
		if typeof(n) == "string" then
			want[n] = true
		end
	end
	local out: { BasePart } = {}
	for _, d in ipairs(root:GetDescendants()) do
		if d:IsA("BasePart") and want[d.Name] and not isSeat(d) then
			table.insert(out, d)
		end
	end
	return out
end

-- one rotor: every part gets a Motor6D to the chassis whose joint frame sits on the spin centre with Y on the axis
local function rigRotor(hostModel: Model, primary: BasePart, clone: Model, spec: any): number
	if typeof(spec) ~= "table" or typeof(spec.Parts) ~= "table" then
		return 0
	end
	local axis: CFrame? = AXES[tostring(spec.Axis)]
	local rps = tonumber(spec.Rps) or 0
	if axis == nil or rps <= 0 then
		return 0
	end
	local root: Instance = if spec.Kit == true then hostModel else clone
	local parts = namedParts(root, spec.Parts)
	if spec.Kit == true then
		-- kit rotor parts only (never the body's own parts under the same name)
		local kit: { BasePart } = {}
		for _, p in ipairs(parts) do
			if not p:IsDescendantOf(clone) then
				table.insert(kit, p)
			end
		end
		parts = kit
	end
	if #parts == 0 then
		return 0
	end
	local centre = Vector3.zero
	local hub = if typeof(spec.Hub) == "string" then root:FindFirstChild(spec.Hub, true) else nil
	if hub and hub:IsA("BasePart") then
		centre = hub.Position
	else
		for _, p in ipairs(parts) do
			centre += p.Position
		end
		centre /= #parts
	end
	local joint = CFrame.new(centre) * (primary.CFrame - primary.CFrame.Position) * axis
	local n = 0
	for _, p in ipairs(parts) do
		for _, holder in ipairs({ primary :: Instance, p :: Instance }) do
			for _, w in ipairs(holder:GetChildren()) do
				if w:IsA("WeldConstraint") and ((w.Part0 == primary and w.Part1 == p) or (w.Part0 == p and w.Part1 == primary)) then
					w:Destroy()
				end
			end
		end
		local m = Instance.new("Motor6D")
		m.Name = AirBodyRig.RotorJointName
		m.Part0 = primary
		m.Part1 = p
		m.C0 = primary.CFrame:ToObjectSpace(joint)
		m.C1 = p.CFrame:ToObjectSpace(joint)
		m:SetAttribute("WE_RotorRps", rps)
		m.Parent = p
		CollectionService:AddTag(m, AirBodyRig.RotorTag)
		p.Massless = true
		p.CanCollide = false
		p.CanTouch = false
		n += 1
	end
	return n
end

-- A store body on a vehicle never shows the seller's signs: every BillboardGui / SurfaceGui (a floating name label such as
-- a helicopter's "Medical Helicopter" sign, CLAUDE.md world-label rules) goes, and with ref.StripDecals its Decals /
-- Textures too. Whole models AND pack pieces (ChildName): a piece already lost its decals when the pack was split
-- (extractPiece, StripDecals), but not its GUIs, and a trimmed body (OmitParts before the part count) is always a piece.
-- Returns how many objects went. Any vehicle family; a no-op for the live bodies (the Recon Plane and the APC carry none;
-- the jeep / buggy / van / pickup packs keep their only GUIs inside LocalScripts, which the loader strips).
function AirBodyRig.StripSigns(clone: Instance, ref: any): number
	local decals = ref.StripDecals == true
	local gone = 0
	for _, d in ipairs(clone:GetDescendants()) do
		if d.Parent ~= nil and (d:IsA("BillboardGui") or d:IsA("SurfaceGui") or (decals and (d:IsA("Decal") or d:IsA("Texture")))) then
			d:Destroy()
			gone += 1
		end
	end
	return gone
end

-- air2 fix1: the fitted body's hit plates (ref.BodyHitBoxes, unscaled body boxes) and the kit's hidden parts out of the
-- shot. Returns the number of plates made.
local function hitPlates(hostModel: Model, primary: BasePart, clone: Model, ref: any, base: CFrame, s: number): number
	local keep: { [string]: boolean } = {}
	for _, n in ipairs(ref.KeepVisible or {}) do
		if typeof(n) == "string" then
			keep[n] = true
		end
	end
	-- the kit's non-colliding parts under the body (hidden by HideKit) take no shot: the plates are the aircraft now
	for _, d in ipairs(hostModel:GetDescendants()) do
		if
			d:IsA("BasePart")
			and d ~= primary
			and not d.CanCollide
			and not isSeat(d)
			and not keep[d.Name]
			and not d:IsDescendantOf(clone)
			and d:GetAttribute("WE_PhysicsWheel") ~= true
		then
			d.CanQuery = false
		end
	end
	local n = 0
	for _, hb in ipairs(ref.BodyHitBoxes) do
		if typeof(hb) == "table" and typeof(hb.At) == "Vector3" and typeof(hb.Size) == "Vector3" then
			local p = Instance.new("Part")
			p.Name = AirBodyRig.HitPlateName
			p.Size = hb.Size * s
			p.CFrame = base * CFrame.new(hb.At * s)
			p.Transparency = 1
			p.CanCollide = false
			p.CanTouch = false
			p.CanQuery = true
			p.Massless = true
			p.CastShadow = false
			p.Anchored = false
			local w = Instance.new("WeldConstraint")
			w.Part0 = primary
			w.Part1 = p
			w.Parent = p
			p.Parent = hostModel
			n += 1
		end
	end
	return n
end

-- chassis-frame box of every part of the store body (the drawn gear, which Apply adds after, excepted)
local function bodyBoxes(primary: BasePart, clone: Model): { { number } }
	local out: { { number } } = {}
	for _, d in ipairs(clone:GetDescendants()) do
		if d:IsA("BasePart") and d.Parent ~= nil and d.Parent.Name ~= AirBodyRig.GearName then
			local rel = primary.CFrame:ToObjectSpace(d.CFrame)
			local e = extents(rel, drawn(d))
			local c = rel.Position
			table.insert(out, { c.X - e.X, c.Y - e.Y, c.Z - e.Z, c.X + e.X, c.Y + e.Y, c.Z + e.Z })
		end
	end
	return out
end

-- air2 fix1: drawn landing gear under the body (ref.BodyGear). Each leg: its wheel on the kit's floor line, its strut from
-- the wheel centre up into the lowest body box over the leg (the body's lowest point when none is over it). Returns the
-- number of parts made.
local function gearDress(hostModel: Model, primary: BasePart, clone: Model, gear: any, base: CFrame, s: number): number
	if typeof(gear.Legs) ~= "table" then
		return 0
	end
	local boxes = bodyBoxes(primary, clone)
	local bodyLow = math.huge
	for _, b in ipairs(boxes) do
		bodyLow = math.min(bodyLow, b[2])
	end
	local floor = AirBodyRig.KitFloor(hostModel, primary, -primary.Size.Y * 0.5)
	local strut = math.clamp(tonumber(gear.Strut) or 0.3, 0.05, 2)
	local into = math.clamp(tonumber(gear.Into) or 0.3, 0, 3)
	-- air2 fix2: the look comes from the config (JET_GEAR); these are only the fallbacks for a table without it
	local wheelCol: Color3 = if typeof(gear.WheelColor) == "Color3" then gear.WheelColor else Color3.fromRGB(28, 28, 30)
	local strutCol: Color3 = if typeof(gear.StrutColor) == "Color3" then gear.StrutColor else Color3.fromRGB(120, 122, 126)
	local wm: any, sm: any = gear.WheelMaterial, gear.StrutMaterial
	local wheelMat: Enum.Material = if typeof(wm) == "EnumItem" then (wm :: any) else Enum.Material.SmoothPlastic
	local strutMat: Enum.Material = if typeof(sm) == "EnumItem" then (sm :: any) else Enum.Material.Metal
	local folder = Instance.new("Folder")
	folder.Name = AirBodyRig.GearName
	local rot = primary.CFrame - primary.CFrame.Position
	local n = 0
	local function part(name: string, size: Vector3, at: Vector3, round: boolean)
		local p = Instance.new("Part")
		p.Name = name
		p.Size = size
		if round then
			p.Shape = Enum.PartType.Cylinder -- a Part cylinder turns about its X axis: the kit's across axis, rolling along Z
			p.Material = wheelMat
			p.Color = wheelCol
		else
			p.Material = strutMat
			p.Color = strutCol
		end
		p.CFrame = CFrame.new(primary.CFrame:PointToWorldSpace(at)) * rot
		p.Anchored = false
		p.CanCollide = false
		p.CanTouch = false
		p.CanQuery = true -- what players see takes the shot, like the body's hit plates
		p.Massless = true
		p.CastShadow = false
		local w = Instance.new("WeldConstraint")
		w.Part0 = primary
		w.Part1 = p
		w.Parent = p
		p.Parent = folder
		n += 1
	end
	for _, leg in ipairs(gear.Legs) do
		local wheel = if typeof(leg) == "table" then tonumber(leg.Wheel) else nil
		if typeof(leg) == "table" and typeof(leg.At) == "Vector3" and wheel and wheel > 0 then
			local at = primary.CFrame:PointToObjectSpace((base * CFrame.new(leg.At * s)).Position)
			local top: number? = nil
			for _, b in ipairs(boxes) do
				if at.X >= b[1] and at.X <= b[4] and at.Z >= b[3] and at.Z <= b[6] then
					top = math.min(top or math.huge, b[2])
				end
			end
			local sTop = (top or bodyLow) + into
			local wy = floor + wheel * 0.5
			if sTop > wy then
				part("GearStrut", Vector3.new(strut, sTop - wy, strut), Vector3.new(at.X, (wy + sTop) * 0.5, at.Z), false)
			end
			part("GearWheel", Vector3.new(wheel * 0.45, wheel, wheel), Vector3.new(at.X, wy, at.Z), true)
		end
	end
	folder.Parent = clone
	return n
end

-- air2 fix1: the body's lowest box corners for the driver's plane law (WE_TailGuard; VehicleDriveClient Laws.TailGuard)
local function tailGuard(hostModel: Model, primary: BasePart, clone: Model, cfg: any)
	local margin = math.clamp(tonumber(cfg.Margin) or 0.3, 0, 2)
	local minPitch = math.clamp(tonumber(cfg.MinPitch) or 3.5, 0, 15)
	local lead = math.clamp(tonumber(cfg.LeadSeconds) or 0.15, 0, 1)
	local pts: { string } = { string.format("%.2f,%.3f", minPitch, lead) }
	for _, b in ipairs(bodyBoxes(primary, clone)) do
		for _, x in ipairs({ b[1], b[4] }) do
			for _, z in ipairs({ b[3], b[6] }) do
				table.insert(pts, string.format("%.3f,%.3f,%.3f", x, b[2] - margin, z))
			end
		end
	end
	if #pts > 1 then
		hostModel:SetAttribute("WE_TailGuard", table.concat(pts, ";"))
	end
end

-- After placeKitOnBody (a fitted BodyScale body): BodyMounts, RotorParts, ChaseCamera, BodyHitBoxes, BodyGear and
-- TailGuard. Returns the number of rotor joints made (for tests). Never errors on a bad ref entry: it is skipped.
function AirBodyRig.Apply(hostModel: Model, primary: BasePart, clone: Model, ref: any): number
	if
		ref.BodyMounts == nil
		and ref.RotorParts == nil
		and ref.ChaseCamera ~= true
		and ref.BodyHitBoxes == nil
		and ref.BodyGear == nil
		and ref.TailGuard ~= true
	then
		return 0 -- every car / boat body and every aircraft ref without the air-looks fields
	end
	local base, reach = bodyBase(hostModel, primary, clone, ref)
	if base == nil then
		return 0
	end
	local s = math.clamp(tonumber(ref.BodyScale) or 1, 0.05, 4)
	if typeof(ref.BodyMounts) == "table" then
		for name, at in pairs(ref.BodyMounts) do
			local p = if typeof(name) == "string" then hostModel:FindFirstChild(name) else nil
			if p and p:IsA("BasePart") and p ~= primary and not isSeat(p) and not p.CanCollide and typeof(at) == "Vector3" then
				-- the part's FRONT face centre lands on the point, so the muzzle (front face + the weapon's MuzzleForward /
				-- MuzzleDrop) is the same for every kit scale
				local rot = p.CFrame - p.CFrame.Position
				reweld(primary, p, CFrame.new((base * CFrame.new(at * s)).Position) * rot * CFrame.new(0, 0, p.Size.Z * 0.5))
				p.CanQuery = false -- air2 fix1: a muzzle point, never a hit box beside the aircraft
			end
		end
	end
	local joints = 0
	if typeof(ref.RotorParts) == "table" then
		for _, spec in ipairs(ref.RotorParts) do
			joints += rigRotor(hostModel, primary, clone, spec)
		end
	end
	local cfg = (VisualAssetConfig :: any).AirBody or {}
	if ref.ChaseCamera == true then
		local zoom = reach + (tonumber(cfg.ChaseCameraMargin) or 6)
		hostModel:SetAttribute("WE_CamMinZoom", math.min(zoom, tonumber(cfg.ChaseCameraMax) or 60))
	end
	if cfg.BodyHitBoxes == true and typeof(ref.BodyHitBoxes) == "table" and #ref.BodyHitBoxes > 0 then
		hitPlates(hostModel, primary, clone, ref, base, s)
	end
	local guard = cfg.TailGuard
	if ref.TailGuard == true and typeof(guard) == "table" and guard.Enabled == true then
		tailGuard(hostModel, primary, clone, guard) -- before the gear: the drawn wheels stand on the ground
	end
	if typeof(ref.BodyGear) == "table" then
		gearDress(hostModel, primary, clone, ref.BodyGear, base, s)
	end
	return joints
end

return AirBodyRig
