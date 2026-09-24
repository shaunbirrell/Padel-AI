--!strict
--[[
	v66: walk-in structures (Command Center first). Config: StructureVisualConfig.HollowBuildings.

	Builds Model "WE_Building" under the upgrade plinth:
	  L1  ground floor: real doorway, glass windows, lit interior (desk, monitors, map table, lockers, radio)
	  L2+ comms annex (east) + roof radio mast + floodlights
	  L3+ second storey with interior stairs and a railed stairwell
	  L4+ roof access (climbable truss through a hatch) + satellite dish
	  L5  rooftop helipad marking, gold trim, tall flag

	Placement: the building sits BEHIND its pad and shifted sideways so the doorway is well outside the
	walk-over buy hit box (UpgradePadService: plinth half-size + 4 margin = ±8 studs). Walking inside
	never re-triggers a purchase. +Z (building front) faces the plot spawn.

	The kit's "Body" part is only the foundation slab (see StructureKitBuilder), so EnsureKit / applyKitVisuals
	invariants (Body exists, solid at L1+) still hold. Everything else lives in the Model and is rebuilt when
	the level changes.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local StructureVisualConfig = require(Shared.Configs.StructureVisualConfig)

local HollowBuildingBuilder = {}

local MODEL_NAME = "WE_Building"
local GEN = 1

type Opening = {
	Center: number, -- along the wall's local X
	Width: number,
	Bottom: number, -- above the wall base
	Height: number,
	Glass: boolean,
}

type Ctx = {
	model: Model,
	origin: CFrame,
	c: any,
	col: any,
	level: number,
}

local function cfgFor(structureId: string): any?
	local all = (StructureVisualConfig :: any).HollowBuildings
	if typeof(all) ~= "table" then
		return nil
	end
	local c = all[structureId]
	if typeof(c) ~= "table" or c.Enabled == false then
		return nil
	end
	return c
end

function HollowBuildingBuilder.IsHollow(structureId: string): boolean
	return cfgFor(structureId) ~= nil
end

local function groundY(plinth: BasePart): number
	local parent = plinth.Parent
	local pad = parent and parent:FindFirstChild("PlotPad")
	if pad and pad:IsA("BasePart") then
		return pad.Position.Y + pad.Size.Y * 0.5
	end
	local bs = plinth:GetAttribute("BaseSize")
	local h = if typeof(bs) == "Vector3" then (bs :: Vector3).Y else plinth.Size.Y
	return plinth.Position.Y - h * 0.5
end

-- Offset of the footprint centre from the plinth, in plinth space (ground level).
local function footprintOffset(plinth: BasePart, c: any): Vector3
	local gy = groundY(plinth)
	return Vector3.new(c.OffsetX or 0, gy - plinth.Position.Y, -((c.FrontGap or 10) + c.Depth * 0.5))
end

local function originFor(plinth: BasePart, c: any): CFrame
	local rot = plinth.CFrame - plinth.CFrame.Position
	return CFrame.new(plinth.Position) * rot * CFrame.new(footprintOffset(plinth, c))
end

--[[ Foundation slab for StructureKitBuilder's "Body": (size, local offset from plinth). ]]
function HollowBuildingBuilder.FoundationSpec(plinth: BasePart, structureId: string): (Vector3?, Vector3?)
	local c = cfgFor(structureId)
	if not c then
		return nil, nil
	end
	return Vector3.new(c.Width, 0.8, c.Depth), footprintOffset(plinth, c)
end

function HollowBuildingBuilder.FoundationColor(structureId: string): Color3?
	local c = cfgFor(structureId)
	return if c and c.Colors then c.Colors.Floor else nil
end

-- ── primitives ──────────────────────────────────────────────────────────────

local function part(ctx: Ctx, name: string, size: Vector3, cf: CFrame, color: Color3, material: Enum.Material, collide: boolean?): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = material
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.CanCollide = if collide == nil then true else collide
	p.CanTouch = false
	-- Walls/floors stay queryable so weapon raycasts and camera occlusion treat the building as solid.
	p.CanQuery = p.CanCollide
	p.CastShadow = true
	p.Parent = ctx.model
	return p
end

local function box(ctx: Ctx, name: string, size: Vector3, pos: Vector3, color: Color3, material: Enum.Material, collide: boolean?): Part
	return part(ctx, name, size, ctx.origin * CFrame.new(pos), color, material, collide)
end

local function light(host: BasePart, range: number, brightness: number, color: Color3)
	local l = Instance.new("PointLight")
	l.Range = range
	l.Brightness = brightness
	l.Color = color
	l.Shadows = false
	l.Parent = host
end

local function surfaceText(host: BasePart, face: Enum.NormalId, lines: { string }, textColor: Color3, bg: Color3, font: Enum.Font?)
	local sg = Instance.new("SurfaceGui")
	sg.Name = "WE_Screen"
	sg.Face = face
	sg.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	sg.PixelsPerStud = 40
	sg.LightInfluence = 0
	sg.Parent = host
	local frame = Instance.new("Frame")
	frame.Size = UDim2.fromScale(1, 1)
	frame.BackgroundColor3 = bg
	frame.BorderSizePixel = 0
	frame.Parent = sg
	local pad = Instance.new("UIPadding")
	pad.PaddingLeft = UDim.new(0.06, 0)
	pad.PaddingRight = UDim.new(0.06, 0)
	pad.PaddingTop = UDim.new(0.08, 0)
	pad.PaddingBottom = UDim.new(0.08, 0)
	pad.Parent = frame
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Vertical
	layout.VerticalAlignment = Enum.VerticalAlignment.Center
	layout.Parent = frame
	for i, text in ipairs(lines) do
		local lbl = Instance.new("TextLabel")
		lbl.BackgroundTransparency = 1
		lbl.Size = UDim2.fromScale(1, 1 / #lines)
		lbl.LayoutOrder = i
		lbl.Font = font or Enum.Font.GothamBold
		lbl.Text = text
		lbl.TextColor3 = textColor
		lbl.TextScaled = true
		lbl.Parent = frame
	end
end

--[[
	Wall along its local X (length len) with base at y=baseY in wallCF space; thickness along local Z,
	local +Z = outside. Openings are cut as piers / sills / lintels; glass openings get a pane + ledge,
	doorways get a metal frame.
]]
local function wall(ctx: Ctx, name: string, wallCF: CFrame, len: number, height: number, baseY: number, openings: { Opening })
	local c = ctx.c
	local col = ctx.col
	local t = c.WallThickness
	table.sort(openings, function(a, b)
		return a.Center < b.Center
	end)
	local x0 = -len * 0.5
	local x1 = len * 0.5
	local function seg(a: number, b: number, y0: number, y1: number)
		if b - a < 0.05 or y1 - y0 < 0.05 then
			return
		end
		part(ctx, name, Vector3.new(b - a, y1 - y0, t), wallCF * CFrame.new((a + b) * 0.5, (y0 + y1) * 0.5, 0), col.Wall, Enum.Material.Concrete)
	end
	local cursor = x0
	for _, o in ipairs(openings) do
		local oa = math.max(x0, o.Center - o.Width * 0.5)
		local ob = math.min(x1, o.Center + o.Width * 0.5)
		if oa >= cursor then
			seg(cursor, oa, baseY, baseY + height)
			seg(oa, ob, baseY, baseY + o.Bottom)
			seg(oa, ob, baseY + o.Bottom + o.Height, baseY + height)
			local w = ob - oa
			local midY = baseY + o.Bottom + o.Height * 0.5
			if o.Glass then
				local pane = part(ctx, name .. "Glass", Vector3.new(w, o.Height, 0.2), wallCF * CFrame.new((oa + ob) * 0.5, midY, 0), col.Glass, Enum.Material.Glass)
				pane.Transparency = 0.45
				pane.Reflectance = 0.08
				pane.CastShadow = false
				-- divider + outside ledge
				part(ctx, name .. "Mullion", Vector3.new(0.2, o.Height, 0.3), wallCF * CFrame.new((oa + ob) * 0.5, midY, 0), col.Trim, Enum.Material.Metal, false)
				part(ctx, name .. "Ledge", Vector3.new(w + 0.6, 0.3, 0.7), wallCF * CFrame.new((oa + ob) * 0.5, baseY + o.Bottom - 0.15, t * 0.5 + 0.2), col.Trim, Enum.Material.Metal, false)
			else
				local frameT = t + 0.3
				part(ctx, name .. "DoorFrame", Vector3.new(0.35, o.Height, frameT), wallCF * CFrame.new(oa + 0.175, midY, 0), col.Metal, Enum.Material.Metal, false)
				part(ctx, name .. "DoorFrame", Vector3.new(0.35, o.Height, frameT), wallCF * CFrame.new(ob - 0.175, midY, 0), col.Metal, Enum.Material.Metal, false)
				part(ctx, name .. "DoorFrame", Vector3.new(w, 0.35, frameT), wallCF * CFrame.new((oa + ob) * 0.5, baseY + o.Bottom + o.Height - 0.175, 0), col.Metal, Enum.Material.Metal, false)
			end
			cursor = ob
		end
	end
	seg(cursor, x1, baseY, baseY + height)
end

-- Horizontal slab in building space with an optional rectangular hole (hx0, hx1, hz0, hz1).
local function slab(ctx: Ctx, name: string, x0: number, x1: number, z0: number, z1: number, yBottom: number, thick: number, color: Color3, material: Enum.Material, hole: { number }?)
	local function piece(a0: number, a1: number, b0: number, b1: number)
		if a1 - a0 < 0.05 or b1 - b0 < 0.05 then
			return
		end
		box(ctx, name, Vector3.new(a1 - a0, thick, b1 - b0), Vector3.new((a0 + a1) * 0.5, yBottom + thick * 0.5, (b0 + b1) * 0.5), color, material)
	end
	if not hole then
		piece(x0, x1, z0, z1)
		return
	end
	local hx0 = math.clamp(hole[1], x0, x1)
	local hx1 = math.clamp(hole[2], x0, x1)
	local hz0 = math.clamp(hole[3], z0, z1)
	local hz1 = math.clamp(hole[4], z0, z1)
	piece(x0, x1, z0, hz0)
	piece(x0, x1, hz1, z1)
	piece(x0, hx0, hz0, hz1)
	piece(hx1, x1, hz0, hz1)
end

local function railing(ctx: Ctx, a: Vector3, b: Vector3, height: number)
	local col = ctx.col
	local dir = b - a
	local len = dir.Magnitude
	if len < 0.1 then
		return
	end
	local mid = (a + b) * 0.5
	local look = CFrame.lookAt(mid, mid + dir) -- local -Z along the rail
	part(ctx, "Rail", Vector3.new(0.25, 0.25, len), ctx.origin * look * CFrame.new(0, height, 0), col.Metal, Enum.Material.Metal)
	part(ctx, "Rail", Vector3.new(0.18, 0.18, len), ctx.origin * look * CFrame.new(0, height * 0.5, 0), col.Metal, Enum.Material.Metal, false)
	local posts = math.max(2, math.floor(len / 3) + 1)
	for i = 0, posts - 1 do
		local p = a + dir * (i / (posts - 1))
		box(ctx, "RailPost", Vector3.new(0.25, height, 0.25), p + Vector3.new(0, height * 0.5, 0), col.Metal, Enum.Material.Metal, false)
	end
end

-- facing: unit X or Z direction the sitter looks toward (backrest goes on the opposite side)
local function chair(ctx: Ctx, pos: Vector3, facing: Vector3)
	local col = ctx.col
	local backSize = if math.abs(facing.X) > 0.5 then Vector3.new(0.3, 1.8, 1.6) else Vector3.new(1.6, 1.8, 0.3)
	box(ctx, "ChairLeg", Vector3.new(0.3, 1.5, 0.3), pos + Vector3.new(0, 0.75, 0), col.Metal, Enum.Material.Metal, false)
	box(ctx, "ChairSeat", Vector3.new(1.6, 0.3, 1.6), pos + Vector3.new(0, 1.65, 0), col.Dark, Enum.Material.Fabric)
	box(ctx, "ChairBack", backSize, pos - facing * 0.65 + Vector3.new(0, 2.7, 0), col.Dark, Enum.Material.Fabric, false)
end

local function sandbags(ctx: Ctx, x0: number, x1: number, z: number, baseY: number)
	local col = ctx.col
	local n = math.max(1, math.floor((x1 - x0) / 2.1))
	local w = (x1 - x0) / n
	for i = 0, n - 1 do
		box(ctx, "Sandbag", Vector3.new(w - 0.1, 1.0, 1.5), Vector3.new(x0 + w * (i + 0.5), baseY + 0.5, z), col.Sandbag, Enum.Material.Fabric)
	end
	for i = 0, n - 2 do
		box(ctx, "Sandbag", Vector3.new(w - 0.1, 1.0, 1.4), Vector3.new(x0 + w * (i + 1), baseY + 1.5, z), col.Sandbag, Enum.Material.Fabric)
	end
end

-- ── building ────────────────────────────────────────────────────────────────

local function build(ctx: Ctx)
	local c = ctx.c
	local col = ctx.col
	local lv = ctx.level
	local W, D, t = c.Width, c.Depth, c.WallThickness
	local H1, H2 = c.StoryHeight, c.UpperStoryHeight
	local hw, hd = W * 0.5, D * 0.5
	local twoStory = lv >= c.TwoStoryLevel
	local hasAnnex = lv >= c.AnnexLevel
	local roofAccess = lv >= c.RoofAccessLevel and twoStory
	local helipad = lv >= c.HelipadLevel

	local y1 = 0.4 -- ground floor top (foundation slab = kit Body)
	local y2 = y1 + H1 + 0.8 -- upper floor top
	local roofBottom = if twoStory then y2 + H2 else y1 + H1
	local roofTop = roofBottom + 0.8

	local doorX, doorW, doorH = c.DoorX, c.DoorWidth, c.DoorHeight
	local winW, winH, winBottom = c.WindowWidth, c.WindowHeight, c.WindowBottom

	-- Stairwell (L3+) along the back wall, climbing toward +X.
	local stairW = 4.5
	local stairRise = y2 - y1
	local stepCount = math.ceil(stairRise / 0.8)
	local stepRise = stairRise / stepCount
	local stepRun = 1.2
	local stairX0 = -hw + t + 0.5
	local stairX1 = stairX0 + stepCount * stepRun
	local stairZ0 = -hd + t
	local stairZ1 = stairZ0 + stairW

	-- Annex (L2+) on the east side, flush with the back wall.
	local annexW, annexD, annexH = c.AnnexWidth, c.AnnexDepth, c.AnnexHeight
	local annexZc = -hd + annexD * 0.5

	-- Walls: ground storey
	local frontCF = ctx.origin * CFrame.new(0, 0, hd - t * 0.5)
	local backCF = ctx.origin * CFrame.new(0, 0, -hd + t * 0.5) * CFrame.Angles(0, math.pi, 0)
	local eastCF = ctx.origin * CFrame.new(hw - t * 0.5, 0, 0) * CFrame.Angles(0, math.pi * 0.5, 0) -- local +X = world -Z
	local westCF = ctx.origin * CFrame.new(-hw + t * 0.5, 0, 0) * CFrame.Angles(0, -math.pi * 0.5, 0) -- local +X = world +Z
	local sideLen = D - 2 * t

	local frontOpen: { Opening } = {
		{ Center = doorX, Width = doorW, Bottom = 0, Height = doorH, Glass = false },
	}
	for _, wx in ipairs(c.FrontWindowsX) do
		table.insert(frontOpen, { Center = wx, Width = winW, Bottom = winBottom, Height = winH, Glass = true })
	end
	wall(ctx, "WallFront", frontCF, W, H1, y1, frontOpen)

	local backOpen: { Opening } = {}
	if not twoStory then
		for _, wx in ipairs(c.BackWindowsX) do
			-- back wall local X is mirrored (rotated 180°)
			table.insert(backOpen, { Center = -wx, Width = winW, Bottom = winBottom, Height = winH, Glass = true })
		end
	end
	wall(ctx, "WallBack", backCF, W, H1, y1, backOpen)

	local westOpen: { Opening } = {}
	for _, wz in ipairs(c.WestWindowsZ) do
		table.insert(westOpen, { Center = wz, Width = winW, Bottom = winBottom, Height = winH, Glass = true })
	end
	wall(ctx, "WallWest", westCF, sideLen, H1, y1, westOpen)

	local eastOpen: { Opening } = {}
	if hasAnnex then
		table.insert(eastOpen, { Center = -annexZc, Width = 4, Bottom = 0, Height = 7.5, Glass = false })
	end
	wall(ctx, "WallEast", eastCF, sideLen, H1, y1, eastOpen)

	-- Upper storey
	if twoStory then
		local upFront: { Opening } = {}
		for _, wx in ipairs(c.UpperWindowsX) do
			table.insert(upFront, { Center = wx, Width = winW, Bottom = 3.2, Height = 3.0, Glass = true })
		end
		wall(ctx, "WallFront2", frontCF, W, H2, y2, upFront)
		local upBack: { Opening } = {}
		for _, wx in ipairs(c.BackWindowsX) do
			table.insert(upBack, { Center = -wx, Width = winW, Bottom = 3.2, Height = 3.0, Glass = true })
		end
		wall(ctx, "WallBack2", backCF, W, H2, y2, upBack)
		wall(ctx, "WallWest2", westCF, sideLen, H2, y2, { { Center = 0, Width = winW, Bottom = 3.2, Height = 3.0, Glass = true } })
		wall(ctx, "WallEast2", eastCF, sideLen, H2, y2, { { Center = 0, Width = winW, Bottom = 3.2, Height = 3.0, Glass = true } })
		-- storey band
		box(ctx, "StoreyBand", Vector3.new(W + 0.4, 0.8, 0.3), Vector3.new(0, y2 - 0.4, hd + 0.15), col.Trim, Enum.Material.Metal, false)
		box(ctx, "StoreyBand", Vector3.new(W + 0.4, 0.8, 0.3), Vector3.new(0, y2 - 0.4, -hd - 0.15), col.Trim, Enum.Material.Metal, false)
		box(ctx, "StoreyBand", Vector3.new(0.3, 0.8, D + 0.4), Vector3.new(hw + 0.15, y2 - 0.4, 0), col.Trim, Enum.Material.Metal, false)
		box(ctx, "StoreyBand", Vector3.new(0.3, 0.8, D + 0.4), Vector3.new(-hw - 0.15, y2 - 0.4, 0), col.Trim, Enum.Material.Metal, false)

		-- Upper floor with stairwell hole
		slab(ctx, "Floor2", -hw + t, hw - t, -hd + t, hd - t, y2 - 0.8, 0.8, col.Floor, Enum.Material.Concrete, { stairX0 - 0.2, stairX1, stairZ0 - 0.1, stairZ1 + 0.2 })
		-- Solid concrete steps
		for k = 1, stepCount do
			local top = y1 + k * stepRise
			box(ctx, "Stair", Vector3.new(stepRun, top - y1, stairW), Vector3.new(stairX0 + (k - 0.5) * stepRun, y1 + (top - y1) * 0.5, (stairZ0 + stairZ1) * 0.5), col.Stair, Enum.Material.Concrete)
		end
		-- Railing around the stairwell on the upper floor (open at the top step, +X end)
		railing(ctx, Vector3.new(stairX0 - 0.2, y2, stairZ1 + 0.3), Vector3.new(stairX1 - 2.4, y2, stairZ1 + 0.3), 3)
	end

	-- Roof slab + parapet
	local roofHole: { number }? = nil
	local trussX = hw - t - 1.3
	local trussZ = hd - t - 1.3
	if roofAccess then
		roofHole = { trussX - 1.6, trussX + 1.6, trussZ - 1.6, trussZ + 1.6 }
	end
	slab(ctx, "Roof", -hw, hw, -hd, hd, roofBottom, 0.8, col.Roof, Enum.Material.Concrete, roofHole)
	local parH = 1.4
	box(ctx, "Parapet", Vector3.new(W, parH, t), Vector3.new(0, roofTop + parH * 0.5, hd - t * 0.5), col.Wall, Enum.Material.Concrete)
	box(ctx, "Parapet", Vector3.new(W, parH, t), Vector3.new(0, roofTop + parH * 0.5, -hd + t * 0.5), col.Wall, Enum.Material.Concrete)
	box(ctx, "Parapet", Vector3.new(t, parH, D - 2 * t), Vector3.new(hw - t * 0.5, roofTop + parH * 0.5, 0), col.Wall, Enum.Material.Concrete)
	box(ctx, "Parapet", Vector3.new(t, parH, D - 2 * t), Vector3.new(-hw + t * 0.5, roofTop + parH * 0.5, 0), col.Wall, Enum.Material.Concrete)
	local capColor = if helipad then col.Accent else col.Trim
	box(ctx, "ParapetCap", Vector3.new(W + 0.3, 0.3, t + 0.3), Vector3.new(0, roofTop + parH + 0.15, hd - t * 0.5), capColor, Enum.Material.Metal, false)
	box(ctx, "ParapetCap", Vector3.new(W + 0.3, 0.3, t + 0.3), Vector3.new(0, roofTop + parH + 0.15, -hd + t * 0.5), capColor, Enum.Material.Metal, false)
	box(ctx, "ParapetCap", Vector3.new(t + 0.3, 0.3, D), Vector3.new(hw - t * 0.5, roofTop + parH + 0.15, 0), capColor, Enum.Material.Metal, false)
	box(ctx, "ParapetCap", Vector3.new(t + 0.3, 0.3, D), Vector3.new(-hw + t * 0.5, roofTop + parH + 0.15, 0), capColor, Enum.Material.Metal, false)

	-- Rooftop plant
	box(ctx, "ACUnit", Vector3.new(3, 1.6, 2.4), Vector3.new(-hw + 5, roofTop + 0.8, -hd + 3), col.Metal, Enum.Material.DiamondPlate)
	box(ctx, "ACUnit", Vector3.new(3, 1.6, 2.4), Vector3.new(-hw + 9, roofTop + 0.8, -hd + 3), col.Metal, Enum.Material.DiamondPlate)
	box(ctx, "Vent", Vector3.new(1.2, 1.4, 1.2), Vector3.new(hw - 3, roofTop + 0.7, 0), col.Dark, Enum.Material.Metal)

	-- Entrance: awning, sign, sandbags
	local awnY = y1 + doorH + 1.0
	box(ctx, "Awning", Vector3.new(doorW + 3, 0.35, 3.6), Vector3.new(doorX, awnY, hd + 1.8), col.Trim, Enum.Material.Metal)
	box(ctx, "AwningPost", Vector3.new(0.35, awnY - y1, 0.35), Vector3.new(doorX - doorW * 0.5 - 1.2, y1 + (awnY - y1) * 0.5, hd + 3.3), col.Metal, Enum.Material.Metal)
	box(ctx, "AwningPost", Vector3.new(0.35, awnY - y1, 0.35), Vector3.new(doorX + doorW * 0.5 + 1.2, y1 + (awnY - y1) * 0.5, hd + 3.3), col.Metal, Enum.Material.Metal)
	local entryLamp = box(ctx, "EntryLamp", Vector3.new(1.4, 0.2, 0.8), Vector3.new(doorX, awnY - 0.3, hd + 1.4), col.Light, Enum.Material.Neon, false)
	light(entryLamp, 14, 1.4, col.Light)
	local signW = math.min(W - 6, 14)
	local sign = box(ctx, "Sign", Vector3.new(signW, 2.0, 0.3), Vector3.new(c.SignX or 0, awnY + 1.6, hd + 0.15), col.Dark, Enum.Material.Metal, false)
	-- NormalId.Back is the +Z face = the building front
	surfaceText(sign, Enum.NormalId.Back, { c.SignText or "COMMAND CENTER" }, col.Accent, col.Dark, Enum.Font.GothamBlack)
	sandbags(ctx, doorX + doorW * 0.5 + 1.6, doorX + doorW * 0.5 + 6.5, hd + 1.6, 0)

	-- Flag
	local flagX = -hw - 2.5
	-- always clear the roofline (two-storey from L3), taller again at L5
	local poleH = roofTop + parH + (if helipad then 9 else 4)
	box(ctx, "FlagPole", Vector3.new(0.4, poleH, 0.4), Vector3.new(flagX, poleH * 0.5, hd + 1), col.Metal, Enum.Material.Metal)
	box(ctx, "Flag", Vector3.new(0.12, 3.6, 6), Vector3.new(flagX, poleH - 2.2, hd + 1 - 3.2), col.Flag, Enum.Material.Fabric, false)
	if helipad then
		box(ctx, "FlagTip", Vector3.new(0.9, 0.9, 0.9), Vector3.new(flagX, poleH + 0.4, hd + 1), col.Accent, Enum.Material.Neon, false).Shape = Enum.PartType.Ball
	end

	-- Ground-floor interior
	local deskX = -hw + t + 1.4
	box(ctx, "Desk", Vector3.new(2.2, 2.8, 9), Vector3.new(deskX, y1 + 1.4, 0), col.Dark, Enum.Material.Metal)
	box(ctx, "DeskTop", Vector3.new(2.8, 0.3, 9.4), Vector3.new(deskX + 0.2, y1 + 2.95, 0), col.Metal, Enum.Material.Metal)
	local screenLines = {
		{ "SITREP", "ALL SECTORS", "GREEN" },
		{ "RADAR", "◆  ◇  ◆", "SWEEP" },
		{ "INTEL", "OUTPOSTS", "CONTESTED" },
	}
	for i, mz in ipairs({ -3, 0, 3 }) do
		local mon = box(ctx, "Monitor", Vector3.new(0.25, 1.6, 2.5), Vector3.new(deskX - 0.5, y1 + 3.9, mz), col.Dark, Enum.Material.Metal, false)
		surfaceText(mon, Enum.NormalId.Right, screenLines[i], col.Screen, Color3.fromRGB(8, 20, 12), Enum.Font.Code)
	end
	chair(ctx, Vector3.new(deskX + 2.4, y1, -1.6), Vector3.new(-1, 0, 0))
	chair(ctx, Vector3.new(deskX + 2.4, y1, 1.6), Vector3.new(-1, 0, 0))

	local mapX = (stairX0 + hw) * 0.5 - 1
	box(ctx, "MapTableBase", Vector3.new(6, 2.6, 3.6), Vector3.new(mapX, y1 + 1.3, 1.5), col.Dark, Enum.Material.Metal)
	local mapTop = box(ctx, "MapTable", Vector3.new(6.6, 0.25, 4.2), Vector3.new(mapX, y1 + 2.72, 1.5), col.Trim, Enum.Material.Metal)
	do
		local sg = Instance.new("SurfaceGui")
		sg.Name = "WE_MapSurface"
		sg.Face = Enum.NormalId.Top
		sg.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
		sg.PixelsPerStud = 40
		sg.LightInfluence = 0
		sg.Parent = mapTop
		local bg = Instance.new("Frame")
		bg.Size = UDim2.fromScale(1, 1)
		bg.BackgroundColor3 = Color3.fromRGB(60, 78, 52)
		bg.BorderSizePixel = 0
		bg.Parent = sg
		local grid = Instance.new("UIGridLayout")
		grid.CellSize = UDim2.fromScale(0.3, 0.3)
		grid.CellPadding = UDim2.fromScale(0.033, 0.033)
		grid.HorizontalAlignment = Enum.HorizontalAlignment.Center
		grid.VerticalAlignment = Enum.VerticalAlignment.Center
		grid.Parent = bg
		local cells = { "N", "", "OIL", "", "HQ", "", "FORT", "", "S" }
		for i, label in ipairs(cells) do
			local cell = Instance.new("TextLabel")
			cell.LayoutOrder = i
			cell.BackgroundColor3 = if label == "HQ" then col.Accent else Color3.fromRGB(96, 120, 78)
			cell.BorderSizePixel = 0
			cell.Font = Enum.Font.GothamBold
			cell.Text = label
			cell.TextScaled = true
			cell.TextColor3 = if label == "HQ" then col.Dark else Color3.fromRGB(230, 235, 220)
			cell.Parent = bg
		end
	end
	box(ctx, "Runner", Vector3.new(3.4, 0.06, hd - 3), Vector3.new(doorX, y1 + 0.03, hd * 0.5 + 1.5), col.Rug, Enum.Material.Fabric, false)

	for i = 0, 1 do
		local lz = hd - t - 1.0 - i * 1.7
		box(ctx, "Locker", Vector3.new(1.4, 7, 1.6), Vector3.new(-hw + t + 0.7, y1 + 3.5, lz), col.Locker, Enum.Material.Metal)
		box(ctx, "LockerSeam", Vector3.new(0.1, 6.4, 0.08), Vector3.new(-hw + t + 1.42, y1 + 3.5, lz), col.Dark, Enum.Material.Metal, false)
	end

	box(ctx, "RadioRack", Vector3.new(2, 5, 1.4), Vector3.new(hw - t - 1.2, y1 + 2.5, -hd + t + 0.8), col.Dark, Enum.Material.Metal)
	for i = 0, 2 do
		box(ctx, "RackLed", Vector3.new(0.3, 0.3, 0.1), Vector3.new(hw - t - 1.6 + i * 0.4, y1 + 3.8, -hd + t + 1.55), if i == 1 then col.Accent else col.Screen, Enum.Material.Neon, false)
	end

	local wallScreen = box(ctx, "WallScreen", Vector3.new(0.2, 4, 7), Vector3.new(hw - t - 0.1, y1 + 5, hd - t - 4.5), col.Dark, Enum.Material.Metal, false)
	surfaceText(wallScreen, Enum.NormalId.Left, { "WAR EMPIRE · HQ", "LEVEL " .. tostring(lv), "BUILD. CONQUER. DOMINATE." }, col.Accent, Color3.fromRGB(10, 14, 12), Enum.Font.GothamBold)

	for _, lz in ipairs({ -hd * 0.45, hd * 0.4 }) do
		local lamp = box(ctx, "CeilingLight", Vector3.new(4, 0.2, 1.2), Vector3.new(0, y1 + H1 - 0.15, lz), col.Light, Enum.Material.Neon, false)
		light(lamp, 22, 1.2, col.Light)
	end

	-- Annex (comms room)
	if hasAnnex then
		local ax0 = hw
		local ax1 = hw + annexW
		local az0 = -hd
		local az1 = -hd + annexD
		local axc = (ax0 + ax1) * 0.5
		box(ctx, "AnnexFloor", Vector3.new(annexW, 0.8, annexD), Vector3.new(axc, 0, annexZc), col.Floor, Enum.Material.Concrete)
		local aBack = ctx.origin * CFrame.new(axc, 0, az0 + t * 0.5) * CFrame.Angles(0, math.pi, 0)
		local aFront = ctx.origin * CFrame.new(axc, 0, az1 - t * 0.5)
		local aEast = ctx.origin * CFrame.new(ax1 - t * 0.5, 0, annexZc) * CFrame.Angles(0, math.pi * 0.5, 0)
		wall(ctx, "AnnexBack", aBack, annexW, annexH, y1, {})
		wall(ctx, "AnnexFront", aFront, annexW, annexH, y1, { { Center = 0, Width = 4, Bottom = 3.4, Height = 2.8, Glass = true } })
		wall(ctx, "AnnexEast", aEast, annexD - 2 * t, annexH, y1, {})
		box(ctx, "AnnexRoof", Vector3.new(annexW + 0.4, 0.8, annexD + 0.4), Vector3.new(axc, y1 + annexH + 0.4, annexZc), col.Roof, Enum.Material.Concrete)
		box(ctx, "Generator", Vector3.new(4, 3, 2.4), Vector3.new(axc + 1.5, y1 + 1.5, az0 + t + 1.5), col.Locker, Enum.Material.DiamondPlate)
		box(ctx, "GeneratorStripe", Vector3.new(4.05, 0.5, 2.45), Vector3.new(axc + 1.5, y1 + 2.4, az0 + t + 1.5), col.Accent, Enum.Material.SmoothPlastic, false)
		box(ctx, "RadioRack", Vector3.new(1.4, 5, 2), Vector3.new(ax1 - t - 0.8, y1 + 2.5, annexZc + 2), col.Dark, Enum.Material.Metal)
		local aLamp = box(ctx, "CeilingLight", Vector3.new(3, 0.2, 1), Vector3.new(axc, y1 + annexH - 0.15, annexZc), col.Light, Enum.Material.Neon, false)
		light(aLamp, 16, 1.1, col.Light)
		local signA = box(ctx, "AnnexSign", Vector3.new(5, 1.2, 0.25), Vector3.new(axc, y1 + annexH - 1.2, az1 + 0.15), col.Dark, Enum.Material.Metal, false)
		surfaceText(signA, Enum.NormalId.Back, { "COMMS" }, col.Accent, col.Dark, Enum.Font.GothamBlack)

		-- Radio mast on the main roof
		local mx, mz = -hw + 2, -hd + 2
		box(ctx, "MastBase", Vector3.new(1.6, 1, 1.6), Vector3.new(mx, roofTop + 0.5, mz), col.Metal, Enum.Material.Metal)
		box(ctx, "Mast", Vector3.new(0.4, 14, 0.4), Vector3.new(mx, roofTop + 8, mz), col.Metal, Enum.Material.Metal, false)
		for i = 1, 3 do
			box(ctx, "MastBar", Vector3.new(2.4 - i * 0.5, 0.15, 0.15), Vector3.new(mx, roofTop + 3 + i * 3.2, mz), col.Metal, Enum.Material.Metal, false)
		end
		local beacon = box(ctx, "MastBeacon", Vector3.new(0.7, 0.7, 0.7), Vector3.new(mx, roofTop + 15.3, mz), Color3.fromRGB(255, 50, 40), Enum.Material.Neon, false)
		beacon.Shape = Enum.PartType.Ball
		light(beacon, 10, 2, Color3.fromRGB(255, 60, 40))

		-- Floodlights on the front parapet corners
		for _, fx in ipairs({ -hw + 1, hw - 1 }) do
			box(ctx, "Floodlight", Vector3.new(1.2, 0.8, 0.8), Vector3.new(fx, roofTop + parH + 0.8, hd - 0.2), col.Metal, Enum.Material.Metal, false)
			local lens = box(ctx, "FloodLens", Vector3.new(1.0, 0.6, 0.1), Vector3.new(fx, roofTop + parH + 0.8, hd + 0.25), col.Light, Enum.Material.Neon, false)
			local spot = Instance.new("SpotLight")
			spot.Face = Enum.NormalId.Back
			spot.Angle = 70
			spot.Range = 30
			spot.Brightness = 1.5
			spot.Color = col.Light
			spot.Parent = lens
		end
	end

	-- Upper floor interior
	if twoStory then
		box(ctx, "StrategyTable", Vector3.new(7, 2.6, 3.2), Vector3.new(2, y2 + 1.3, 3), col.Dark, Enum.Material.Metal)
		box(ctx, "StrategyTop", Vector3.new(7.4, 0.25, 3.6), Vector3.new(2, y2 + 2.72, 3), col.Trim, Enum.Material.Metal)
		for _, cx in ipairs({ -0.5, 2, 4.5 }) do
			chair(ctx, Vector3.new(cx, y2, 5.8), Vector3.new(0, 0, -1))
		end
		for i = 0, 1 do
			local bz = hd - t - 2 - i * 3.4
			local bx = -hw + t + 1.3
			box(ctx, "Bunk", Vector3.new(2.4, 0.5, 3), Vector3.new(bx, y2 + 1.2, bz), col.Locker, Enum.Material.Metal)
			box(ctx, "Bunk", Vector3.new(2.4, 0.5, 3), Vector3.new(bx, y2 + 4.0, bz), col.Locker, Enum.Material.Metal)
			box(ctx, "Mattress", Vector3.new(2.2, 0.3, 2.8), Vector3.new(bx, y2 + 1.6, bz), col.Rug, Enum.Material.Fabric, false)
			box(ctx, "Mattress", Vector3.new(2.2, 0.3, 2.8), Vector3.new(bx, y2 + 4.4, bz), col.Rug, Enum.Material.Fabric, false)
		end
		box(ctx, "WeaponRack", Vector3.new(0.6, 4, 4), Vector3.new(hw - t - 0.4, y2 + 2, 4.5), col.Dark, Enum.Material.Metal)
		for i = 0, 3 do
			box(ctx, "RackRifle", Vector3.new(0.3, 3.2, 0.3), Vector3.new(hw - t - 0.9, y2 + 2.1, 3 + i * 1.0), col.Metal, Enum.Material.Metal, false)
		end
		for _, lz in ipairs({ -hd * 0.3, hd * 0.45 }) do
			local lamp = box(ctx, "CeilingLight", Vector3.new(4, 0.2, 1.2), Vector3.new(0, y2 + H2 - 0.15, lz), col.Light, Enum.Material.Neon, false)
			light(lamp, 20, 1.1, col.Light)
		end
	end

	-- Roof access: climbable truss through a hatch
	if roofAccess then
		local climb = (roofTop - y2) + 2
		local trussH = math.ceil(climb / 2) * 2
		local truss = Instance.new("TrussPart")
		truss.Name = "RoofLadder"
		truss.Anchored = true
		truss.Size = Vector3.new(2, trussH, 2)
		truss.CFrame = ctx.origin * CFrame.new(trussX, y2 + trussH * 0.5, trussZ)
		truss.Color = col.Metal
		truss.Material = Enum.Material.Metal
		truss.CanTouch = false
		truss.Parent = ctx.model
		railing(ctx, Vector3.new(trussX - 1.8, roofTop, trussZ - 1.8), Vector3.new(trussX + 1.8, roofTop, trussZ - 1.8), 3)
		railing(ctx, Vector3.new(trussX - 1.8, roofTop, trussZ - 1.8), Vector3.new(trussX - 1.8, roofTop, trussZ + 1.2), 3)

		-- Satellite dish
		local dx, dz = hw - 6, -hd + 4.5
		box(ctx, "DishMount", Vector3.new(0.6, 2.4, 0.6), Vector3.new(dx, roofTop + 1.2, dz), col.Metal, Enum.Material.Metal)
		local dish = part(ctx, "Dish", Vector3.new(0.4, 5, 5), ctx.origin * CFrame.new(dx, roofTop + 3.2, dz) * CFrame.Angles(0, math.rad(-120), math.rad(35)), Color3.fromRGB(220, 222, 218), Enum.Material.SmoothPlastic)
		dish.Shape = Enum.PartType.Cylinder
	end

	-- Rooftop helipad marking
	if helipad then
		local hx, hz = 2, 1.5
		local ring = part(ctx, "HelipadRing", Vector3.new(0.06, 12, 12), ctx.origin * CFrame.new(hx, roofTop + 0.03, hz) * CFrame.Angles(0, 0, math.pi * 0.5), col.Accent, Enum.Material.SmoothPlastic, false)
		ring.Shape = Enum.PartType.Cylinder
		local inner = part(ctx, "HelipadInner", Vector3.new(0.06, 10.6, 10.6), ctx.origin * CFrame.new(hx, roofTop + 0.05, hz) * CFrame.Angles(0, 0, math.pi * 0.5), col.Dark, Enum.Material.SmoothPlastic, false)
		inner.Shape = Enum.PartType.Cylinder
		box(ctx, "HelipadH", Vector3.new(0.8, 0.06, 5), Vector3.new(hx - 1.6, roofTop + 0.08, hz), col.Accent, Enum.Material.SmoothPlastic, false)
		box(ctx, "HelipadH", Vector3.new(0.8, 0.06, 5), Vector3.new(hx + 1.6, roofTop + 0.08, hz), col.Accent, Enum.Material.SmoothPlastic, false)
		box(ctx, "HelipadH", Vector3.new(2.4, 0.06, 0.8), Vector3.new(hx, roofTop + 0.08, hz), col.Accent, Enum.Material.SmoothPlastic, false)
	end
end

local function findModel(plinth: BasePart): Model?
	local m = plinth:FindFirstChild(MODEL_NAME)
	if m and m:IsA("Model") then
		return m
	end
	return nil
end

--[[ Build / rebuild / remove the walk-in building for this plinth at `level`. Idempotent. ]]
function HollowBuildingBuilder.Sync(plinth: BasePart, structureId: string, level: number)
	local c = cfgFor(structureId)
	local existing = findModel(plinth)
	local lv = math.clamp(math.floor(tonumber(level) or 0), 0, 5)
	if not c or lv < 1 then
		if existing then
			existing:Destroy()
		end
		return
	end
	if existing and existing:GetAttribute("WE_BuildingLevel") == lv and existing:GetAttribute("WE_BuildingGen") == GEN then
		return
	end
	if existing then
		existing:Destroy()
	end
	local model = Instance.new("Model")
	model.Name = MODEL_NAME
	model:SetAttribute("WE_BuildingLevel", lv)
	model:SetAttribute("WE_BuildingGen", GEN)
	model:SetAttribute("StructureId", structureId)
	local ctx: Ctx = {
		model = model,
		origin = originFor(plinth, c),
		c = c,
		col = c.Colors,
		level = lv,
	}
	local ok, err = pcall(build, ctx)
	if not ok then
		warn("[HollowBuilding] build failed", structureId, lv, err)
	end
	model.Parent = plinth
end

--[[ Remove every walk-in building under a plot folder (plot released). ]]
function HollowBuildingBuilder.ClearUnder(root: Instance)
	for _, d in ipairs(root:GetDescendants()) do
		if d:IsA("Model") and d.Name == MODEL_NAME then
			d:Destroy()
		end
	end
end

return HollowBuildingBuilder
