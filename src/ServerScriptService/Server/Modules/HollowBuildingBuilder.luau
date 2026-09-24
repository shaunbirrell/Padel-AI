--!strict
--[[
	Walk-in structures. Config: StructureVisualConfig.HollowBuildings (Defaults + one entry per structure).

	Builds Model "WE_Building" under the structure's upgrade slot:
	  shell     real doorway (or wide garage door), glass windows, floor, flat roof + parapet, entrance, sign
	  levels    TwoStoryLevel → second storey + interior stairs; AnnexLevel → side annex, mast, floodlights;
	            RoofAccessLevel → truss ladder through a roof hatch + dish; GoldCapLevel → gold parapet; flag
	  interior  Modules/Interiors/<Interior>.luau — function(ictx, api) that furnishes the rooms
	            (ictx = geometry + keep-out zones, api = building-local part helpers + item terminals)

	v68: with BaseLayoutConfig the building is centred on its site (WE_SiteCFrame) and bought/upgraded at the
	console inside it. Legacy (no site): it sits behind its pad with the doorway shifted clear of the pad.

	The kit's "Body" part is only the foundation slab (see StructureKitBuilder), so EnsureKit / applyKitVisuals
	invariants (Body exists, solid at L1+) still hold. Everything else lives in the Model and is rebuilt when
	the level changes.
]]

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local StructureVisualConfig = require(Shared.Configs.StructureVisualConfig)
local BaseLayoutConfig = require(Shared.Configs.BaseLayoutConfig)

local HollowBuildingBuilder = {}

local MODEL_NAME = "WE_Building"
local GEN = 2

type Opening = {
	Center: number, -- along the wall's local X
	Width: number,
	Bottom: number, -- above the wall base
	Height: number,
	Glass: boolean,
	Garage: boolean?,
}

type Ctx = {
	model: Model,
	origin: CFrame,
	c: any,
	col: any,
	level: number,
	structureId: string,
}

export type Rect = { X0: number, X1: number, Z0: number, Z1: number }

local function merged(defaults: any, specific: any): any
	local out = {}
	if typeof(defaults) == "table" then
		for k, v in pairs(defaults) do
			out[k] = v
		end
	end
	for k, v in pairs(specific) do
		out[k] = v
	end
	local colors = {}
	if typeof(defaults) == "table" and typeof(defaults.Colors) == "table" then
		for k, v in pairs(defaults.Colors) do
			colors[k] = v
		end
	end
	if typeof(specific.Colors) == "table" then
		for k, v in pairs(specific.Colors) do
			colors[k] = v
		end
	end
	out.Colors = colors
	return out
end

local function cfgFor(structureId: string): any?
	local all = (StructureVisualConfig :: any).HollowBuildings
	if typeof(all) ~= "table" or structureId == "Defaults" then
		return nil
	end
	local c = all[structureId]
	if typeof(c) ~= "table" or c.Enabled == false then
		return nil
	end
	return merged(all.Defaults, c)
end

-- v68 outdoor installations (StructureVisualConfig.Installations): not walk-in shells but a detailed model
-- from Modules/Installations/<Module>.luau on the same foundation slab. Needs BaseLayoutConfig (site frames).
local function instCfgFor(structureId: string): any?
	if not BaseLayoutConfig.Enabled then
		return nil
	end
	local all = (StructureVisualConfig :: any).Installations
	if typeof(all) ~= "table" then
		return nil
	end
	local c = all[structureId]
	if typeof(c) ~= "table" or c.Enabled == false then
		return nil
	end
	local hb = (StructureVisualConfig :: any).HollowBuildings
	return merged(if typeof(hb) == "table" then hb.Defaults else nil, c)
end

function HollowBuildingBuilder.IsHollow(structureId: string): boolean
	return cfgFor(structureId) ~= nil or instCfgFor(structureId) ~= nil
end

function HollowBuildingBuilder.IsInstallation(structureId: string): boolean
	return cfgFor(structureId) == nil and instCfgFor(structureId) ~= nil
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

local function siteCFrame(plinth: BasePart): CFrame?
	local cf = plinth:GetAttribute("WE_SiteCFrame")
	if typeof(cf) == "CFrame" then
		return cf
	end
	return nil
end

-- Offset of the footprint centre from the kit frame (StructureKitBuilder site frame), at ground level.
-- v68 layout: the building is centred on its site. Legacy pads: behind the pad, shifted sideways.
local function footprintOffset(plinth: BasePart, c: any): Vector3
	local gy = groundY(plinth)
	local site = siteCFrame(plinth)
	if site then
		return Vector3.new(0, gy - site.Position.Y, 0)
	end
	return Vector3.new(c.OffsetX or 0, gy - plinth.Position.Y, -((c.FrontGap or 10) + c.Depth * 0.5))
end

local function originFor(plinth: BasePart, c: any): CFrame
	local site = siteCFrame(plinth)
	if site then
		return site * CFrame.new(footprintOffset(plinth, c))
	end
	local rot = plinth.CFrame - plinth.CFrame.Position
	return CFrame.new(plinth.Position) * rot * CFrame.new(footprintOffset(plinth, c))
end

--[[ Foundation slab for StructureKitBuilder's "Body": (size, local offset in the kit frame). ]]
function HollowBuildingBuilder.FoundationSpec(plinth: BasePart, structureId: string): (Vector3?, Vector3?)
	local c = cfgFor(structureId) or instCfgFor(structureId)
	if not c then
		return nil, nil
	end
	return Vector3.new(c.Width, 0.8, c.Depth), footprintOffset(plinth, c)
end

function HollowBuildingBuilder.FoundationColor(structureId: string): Color3?
	local c = cfgFor(structureId) or instCfgFor(structureId)
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

local LIGHTS = (StructureVisualConfig :: any).BuildingLights or {}
local FIXTURE_MATERIAL: Enum.Material = LIGHTS.FixtureMaterial or Enum.Material.Neon

local function light(host: BasePart, range: number, brightness: number, color: Color3)
	local l = Instance.new("PointLight")
	l.Range = math.min(range, LIGHTS.MaxRange or range)
	l.Brightness = brightness * (LIGHTS.BrightnessScale or 1)
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
	doorways get a metal frame, garage openings a striped frame + rolled shutter drum.
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
				part(ctx, name .. "Mullion", Vector3.new(0.2, o.Height, 0.3), wallCF * CFrame.new((oa + ob) * 0.5, midY, 0), col.Trim, Enum.Material.Metal, false)
				part(ctx, name .. "Ledge", Vector3.new(w + 0.6, 0.3, 0.7), wallCF * CFrame.new((oa + ob) * 0.5, baseY + o.Bottom - 0.15, t * 0.5 + 0.2), col.Trim, Enum.Material.Metal, false)
			elseif o.Garage then
				local frameT = t + 0.4
				for _, edge in ipairs({ oa + 0.3, ob - 0.3 }) do
					part(ctx, name .. "GarageFrame", Vector3.new(0.6, o.Height, frameT), wallCF * CFrame.new(edge, midY, 0), col.Accent, Enum.Material.SmoothPlastic, false)
				end
				part(ctx, name .. "GarageHeader", Vector3.new(w, 0.6, frameT), wallCF * CFrame.new((oa + ob) * 0.5, baseY + o.Bottom + o.Height - 0.3, 0), col.Metal, Enum.Material.Metal, false)
				local drum = part(ctx, name .. "ShutterDrum", Vector3.new(w - 0.6, 1.4, 1.4), wallCF * CFrame.new((oa + ob) * 0.5, baseY + o.Bottom + o.Height - 0.5, -t * 0.5 - 0.7), col.Metal, Enum.Material.DiamondPlate, false)
				drum.Shape = Enum.PartType.Cylinder
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

--[[ Item terminal: a floor-standing screen with a ProximityPrompt that opens a client panel
	(attribute WE_OpenPanel on the prompt; ClientBootstrap routes it). Not an upgrade slot. ]]
local function terminal(ctx: Ctx, name: string, pos: Vector3, facingDeg: number, panel: string, actionText: string, objectText: string, screenLines: { string }?): Part
	local col = ctx.col
	local frame = ctx.origin * CFrame.new(pos) * CFrame.Angles(0, math.rad(facingDeg), 0)
	local body = part(ctx, name, Vector3.new(2.4, 3.2, 1.2), frame * CFrame.new(0, 1.6, 0), col.Dark, Enum.Material.Metal)
	local screen = part(ctx, name .. "Screen", Vector3.new(2.1, 1.3, 0.14), frame * CFrame.new(0, 3.55, 0.3) * CFrame.Angles(math.rad(-20), 0, 0), Color3.fromRGB(10, 24, 14), Enum.Material.SmoothPlastic, false)
	surfaceText(screen, Enum.NormalId.Back, screenLines or { string.upper(objectText), "TAP TO OPEN" }, col.Screen, Color3.fromRGB(8, 20, 12), Enum.Font.GothamBold)
	local lamp = part(ctx, name .. "Lamp", Vector3.new(0.4, 0.2, 0.4), frame * CFrame.new(0.8, 3.25, 0.35), col.Screen, Enum.Material.Neon, false)
	light(lamp, 6, 0.8, col.Screen)
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "WE_PanelPrompt"
	prompt.ActionText = actionText
	prompt.ObjectText = objectText
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 8
	prompt.RequiresLineOfSight = false
	prompt.KeyboardKeyCode = Enum.KeyCode.F
	prompt:SetAttribute("WE_OpenPanel", panel)
	prompt.Parent = body
	body:SetAttribute("WE_Terminal", panel)
	return body
end

-- Part helpers handed to interior / installation modules (building-local coordinates, parts tagged `tag`).
local function makeApi(ctx: Ctx, tag: string): any
	local function tagged(p: Part): Part
		p:SetAttribute(tag, true)
		return p
	end
	local api = {
		box = function(name: string, size: Vector3, pos: Vector3, color: Color3, material: Enum.Material, collide: boolean?): Part
			return tagged(box(ctx, name, size, pos, color, material, collide))
		end,
		part = function(name: string, size: Vector3, localCF: CFrame, color: Color3, material: Enum.Material, collide: boolean?): Part
			return tagged(part(ctx, name, size, ctx.origin * localCF, color, material, collide))
		end,
		light = light,
		surfaceText = surfaceText,
		chair = function(pos: Vector3, facing: Vector3)
			local before = #ctx.model:GetChildren()
			chair(ctx, pos, facing)
			local kids = ctx.model:GetChildren()
			for i = before + 1, #kids do
				local k = kids[i]
				if k:IsA("BasePart") then
					k:SetAttribute(tag, true)
				end
			end
		end,
		sandbags = function(x0: number, x1: number, z: number, baseY: number)
			local before = #ctx.model:GetChildren()
			sandbags(ctx, x0, x1, z, baseY)
			local kids = ctx.model:GetChildren()
			for i = before + 1, #kids do
				local k = kids[i]
				if k:IsA("BasePart") then
					k:SetAttribute(tag, true)
				end
			end
		end,
		terminal = function(name: string, pos: Vector3, facingDeg: number, panel: string, actionText: string, objectText: string, screenLines: { string }?): Part
			local before = #ctx.model:GetChildren()
			local body = terminal(ctx, name, pos, facingDeg, panel, actionText, objectText, screenLines)
			local kids = ctx.model:GetChildren()
			for i = before + 1, #kids do
				local k = kids[i]
				if k:IsA("BasePart") then
					k:SetAttribute(tag, true)
				end
			end
			return body
		end,
	}
	-- installations: shaped parts, climbable trusses, client-side spinning groups
	api.cylinder = function(name: string, size: Vector3, localCF: CFrame, color: Color3, material: Enum.Material, collide: boolean?): Part
		local p = tagged(part(ctx, name, size, ctx.origin * localCF, color, material, collide))
		p.Shape = Enum.PartType.Cylinder -- axis = local X
		return p
	end
	api.ball = function(name: string, diameter: number, pos: Vector3, color: Color3, material: Enum.Material, collide: boolean?): Part
		local p = tagged(box(ctx, name, Vector3.new(diameter, diameter, diameter), pos, color, material, collide))
		p.Shape = Enum.PartType.Ball
		return p
	end
	api.wedge = function(name: string, size: Vector3, localCF: CFrame, color: Color3, material: Enum.Material, collide: boolean?): WedgePart
		local w = Instance.new("WedgePart")
		w.Name = name
		w.Anchored = true
		w.Size = size
		w.CFrame = ctx.origin * localCF
		w.Color = color
		w.Material = material
		w.CanCollide = if collide == nil then true else collide
		w.CanTouch = false
		w.CanQuery = w.CanCollide
		w:SetAttribute(tag, true)
		w.Parent = ctx.model
		return w
	end
	api.truss = function(name: string, height: number, pos: Vector3, color: Color3): TrussPart
		local tp = Instance.new("TrussPart")
		tp.Name = name
		tp.Anchored = true
		tp.Size = Vector3.new(2, math.max(2, math.floor(height / 2 + 0.5) * 2), 2)
		tp.CFrame = ctx.origin * CFrame.new(pos.X, pos.Y + tp.Size.Y * 0.5, pos.Z)
		tp.Color = color
		tp.Material = Enum.Material.Metal
		tp.CanTouch = false
		tp:SetAttribute(tag, true)
		tp.Parent = ctx.model
		return tp
	end
	-- Group parts that the client spins around a vertical axis through `pivot` (building-local).
	-- Server copies stay still; Client/Modules/WorldSpinners rotates the tagged Model locally.
	api.spin = function(parts: { BasePart }, pivot: Vector3, rpm: number): Model
		local m = Instance.new("Model")
		m.Name = "WE_Spinner"
		m:SetAttribute("WE_SpinPivot", ctx.origin * CFrame.new(pivot))
		m:SetAttribute("WE_SpinRPM", rpm)
		for _, bp in ipairs(parts) do
			bp.Parent = m
		end
		m.Parent = ctx.model
		CollectionService:AddTag(m, "WE_Spinner")
		return m
	end
	return api
end

-- ── building ────────────────────────────────────────────────────────────────

local function consoleLocal(structureId: string): Vector3?
	local s = (BaseLayoutConfig.Structures :: any)[structureId]
	if BaseLayoutConfig.Enabled and s and s.WalkIn and s.Console then
		return Vector3.new(s.Console.X, 0, s.Console.Z)
	end
	return nil
end

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
	local goldCap = helipad or lv >= (c.GoldCapLevel or 5)
	local garage = c.DoorStyle == "Garage"

	local y1 = 0.4 -- ground floor top (foundation slab = kit Body)
	local y2 = y1 + H1 + 0.8 -- upper floor top
	local roofBottom = if twoStory then y2 + H2 else y1 + H1
	local roofTop = roofBottom + 0.8

	local doorX, doorW, doorH = c.DoorX, c.DoorWidth, c.DoorHeight
	local winW, winH, winBottom = c.WindowWidth, c.WindowHeight, c.WindowBottom

	-- Stairwell (two storeys) along the back wall, climbing toward +X.
	local stairW = 4.5
	local stairRise = y2 - y1
	local stepCount = math.ceil(stairRise / 0.8)
	local stepRise = stairRise / stepCount
	local stepRun = 1.2
	local stairX0 = -hw + t + 0.5
	local stairX1 = stairX0 + stepCount * stepRun
	local stairZ0 = -hd + t
	local stairZ1 = stairZ0 + stairW

	local annexW, annexD, annexH = c.AnnexWidth or 12, c.AnnexDepth or 14, c.AnnexHeight or 9
	local annexZc = -hd + annexD * 0.5

	-- Walls: ground storey
	local frontCF = ctx.origin * CFrame.new(0, 0, hd - t * 0.5)
	local backCF = ctx.origin * CFrame.new(0, 0, -hd + t * 0.5) * CFrame.Angles(0, math.pi, 0)
	local eastCF = ctx.origin * CFrame.new(hw - t * 0.5, 0, 0) * CFrame.Angles(0, math.pi * 0.5, 0) -- local +X = world -Z
	local westCF = ctx.origin * CFrame.new(-hw + t * 0.5, 0, 0) * CFrame.Angles(0, -math.pi * 0.5, 0) -- local +X = world +Z
	local sideLen = D - 2 * t

	local frontOpen: { Opening } = {
		{ Center = doorX, Width = doorW, Bottom = 0, Height = doorH, Glass = false, Garage = garage },
	}
	for _, wx in ipairs(c.FrontWindowsX or {}) do
		table.insert(frontOpen, { Center = wx, Width = winW, Bottom = winBottom, Height = winH, Glass = true })
	end
	wall(ctx, "WallFront", frontCF, W, H1, y1, frontOpen)

	local backOpen: { Opening } = {}
	if not twoStory then
		for _, wx in ipairs(c.BackWindowsX or {}) do
			-- back wall local X is mirrored (rotated 180°)
			table.insert(backOpen, { Center = -wx, Width = winW, Bottom = winBottom, Height = winH, Glass = true })
		end
	end
	wall(ctx, "WallBack", backCF, W, H1, y1, backOpen)

	local westOpen: { Opening } = {}
	for _, wz in ipairs(c.WestWindowsZ or {}) do
		table.insert(westOpen, { Center = wz, Width = winW, Bottom = winBottom, Height = winH, Glass = true })
	end
	wall(ctx, "WallWest", westCF, sideLen, H1, y1, westOpen)

	local eastOpen: { Opening } = {}
	if hasAnnex then
		table.insert(eastOpen, { Center = -annexZc, Width = 4, Bottom = 0, Height = 7.5, Glass = false })
	else
		for _, wz in ipairs(c.EastWindowsZ or {}) do
			table.insert(eastOpen, { Center = -wz, Width = winW, Bottom = winBottom, Height = winH, Glass = true })
		end
	end
	wall(ctx, "WallEast", eastCF, sideLen, H1, y1, eastOpen)

	-- Upper storey
	if twoStory then
		local upFront: { Opening } = {}
		for _, wx in ipairs(c.UpperWindowsX or c.FrontWindowsX or {}) do
			table.insert(upFront, { Center = wx, Width = winW, Bottom = 3.2, Height = 3.0, Glass = true })
		end
		wall(ctx, "WallFront2", frontCF, W, H2, y2, upFront)
		local upBack: { Opening } = {}
		for _, wx in ipairs(c.BackWindowsX or {}) do
			table.insert(upBack, { Center = -wx, Width = winW, Bottom = 3.2, Height = 3.0, Glass = true })
		end
		wall(ctx, "WallBack2", backCF, W, H2, y2, upBack)
		wall(ctx, "WallWest2", westCF, sideLen, H2, y2, { { Center = 0, Width = winW, Bottom = 3.2, Height = 3.0, Glass = true } })
		wall(ctx, "WallEast2", eastCF, sideLen, H2, y2, { { Center = 0, Width = winW, Bottom = 3.2, Height = 3.0, Glass = true } })
		box(ctx, "StoreyBand", Vector3.new(W + 0.4, 0.8, 0.3), Vector3.new(0, y2 - 0.4, hd + 0.15), col.Trim, Enum.Material.Metal, false)
		box(ctx, "StoreyBand", Vector3.new(W + 0.4, 0.8, 0.3), Vector3.new(0, y2 - 0.4, -hd - 0.15), col.Trim, Enum.Material.Metal, false)
		box(ctx, "StoreyBand", Vector3.new(0.3, 0.8, D + 0.4), Vector3.new(hw + 0.15, y2 - 0.4, 0), col.Trim, Enum.Material.Metal, false)
		box(ctx, "StoreyBand", Vector3.new(0.3, 0.8, D + 0.4), Vector3.new(-hw - 0.15, y2 - 0.4, 0), col.Trim, Enum.Material.Metal, false)

		slab(ctx, "Floor2", -hw + t, hw - t, -hd + t, hd - t, y2 - 0.8, 0.8, col.Floor, Enum.Material.Concrete, { stairX0 - 0.2, stairX1, stairZ0 - 0.1, stairZ1 + 0.2 })
		for k = 1, stepCount do
			local top = y1 + k * stepRise
			box(ctx, "Stair", Vector3.new(stepRun, top - y1, stairW), Vector3.new(stairX0 + (k - 0.5) * stepRun, y1 + (top - y1) * 0.5, (stairZ0 + stairZ1) * 0.5), col.Stair, Enum.Material.Concrete)
		end
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
	local capColor = if goldCap then col.Gold else col.Trim
	box(ctx, "ParapetCap", Vector3.new(W + 0.3, 0.3, t + 0.3), Vector3.new(0, roofTop + parH + 0.15, hd - t * 0.5), capColor, Enum.Material.Metal, false)
	box(ctx, "ParapetCap", Vector3.new(W + 0.3, 0.3, t + 0.3), Vector3.new(0, roofTop + parH + 0.15, -hd + t * 0.5), capColor, Enum.Material.Metal, false)
	box(ctx, "ParapetCap", Vector3.new(t + 0.3, 0.3, D), Vector3.new(hw - t * 0.5, roofTop + parH + 0.15, 0), capColor, Enum.Material.Metal, false)
	box(ctx, "ParapetCap", Vector3.new(t + 0.3, 0.3, D), Vector3.new(-hw + t * 0.5, roofTop + parH + 0.15, 0), capColor, Enum.Material.Metal, false)

	-- Rooftop plant
	box(ctx, "ACUnit", Vector3.new(3, 1.6, 2.4), Vector3.new(-hw + 5, roofTop + 0.8, -hd + 3), col.Metal, Enum.Material.DiamondPlate)
	box(ctx, "ACUnit", Vector3.new(3, 1.6, 2.4), Vector3.new(-hw + 9, roofTop + 0.8, -hd + 3), col.Metal, Enum.Material.DiamondPlate)
	box(ctx, "Vent", Vector3.new(1.2, 1.4, 1.2), Vector3.new(hw - 3, roofTop + 0.7, 0), col.Dark, Enum.Material.Metal)
	if c.Skylights then
		for i, sx in ipairs({ -hw * 0.45, 0, hw * 0.45 }) do
			local sky = box(ctx, "Skylight" .. i, Vector3.new(5, 0.5, 3.4), Vector3.new(sx, roofTop + 0.25, hd * 0.2), col.Glass, Enum.Material.Glass, false)
			sky.Transparency = 0.35
		end
	end

	-- Entrance: awning or garage canopy, lamp, sign, sandbags
	local awnY = y1 + doorH + 1.0
	if garage then
		box(ctx, "Canopy", Vector3.new(doorW + 4, 0.4, 4.6), Vector3.new(doorX, awnY, hd + 2.3), col.Metal, Enum.Material.DiamondPlate)
		for _, sx in ipairs({ -1, 1 }) do
			box(ctx, "BollardHazard", Vector3.new(0.9, 1.6, 0.9), Vector3.new(doorX + sx * (doorW * 0.5 + 1.2), y1 + 0.8, hd + 1.2), col.Accent, Enum.Material.SmoothPlastic)
		end
	else
		box(ctx, "Awning", Vector3.new(doorW + 3, 0.35, 3.6), Vector3.new(doorX, awnY, hd + 1.8), col.Trim, Enum.Material.Metal)
		box(ctx, "AwningPost", Vector3.new(0.35, awnY - y1, 0.35), Vector3.new(doorX - doorW * 0.5 - 1.2, y1 + (awnY - y1) * 0.5, hd + 3.3), col.Metal, Enum.Material.Metal)
		box(ctx, "AwningPost", Vector3.new(0.35, awnY - y1, 0.35), Vector3.new(doorX + doorW * 0.5 + 1.2, y1 + (awnY - y1) * 0.5, hd + 3.3), col.Metal, Enum.Material.Metal)
	end
	local entryLamp = box(ctx, "EntryLamp", Vector3.new(1.4, 0.2, 0.8), Vector3.new(doorX, awnY - 0.3, hd + 1.4), LIGHTS.FixtureColor or col.Light, FIXTURE_MATERIAL, false)
	light(entryLamp, 14, 1.4, col.Light)
	local signW = math.min(W - 6, 16)
	local signY = math.min(awnY + 1.6, y1 + H1 - 1.2)
	local signX = c.SignX or 0
	-- only slide the sign sideways if it would hang down over the doorway
	if math.abs(signX - doorX) < (signW + doorW) * 0.5 and signY - 1 < y1 + doorH + 0.4 then
		signX = if doorX > 0 then doorX - doorW * 0.5 - signW * 0.5 - 1 else doorX + doorW * 0.5 + signW * 0.5 + 1
	end
	local sign = box(ctx, "Sign", Vector3.new(signW, 2.0, 0.3), Vector3.new(signX, signY, hd + 0.15), col.Dark, Enum.Material.Metal, false)
	-- NormalId.Back is the +Z face = the building front
	surfaceText(sign, Enum.NormalId.Back, { c.SignText or "COMMAND CENTER" }, col.Accent, col.Dark, Enum.Font.GothamBlack)
	if not garage then
		sandbags(ctx, doorX + doorW * 0.5 + 1.6, doorX + doorW * 0.5 + 6.5, hd + 1.6, 0)
	end

	-- Flag
	if lv >= (c.FlagLevel or 1) then
		local flagX = -hw - 2.5
		-- always clear the roofline (two-storey from L3), taller again at L5
		local poleH = roofTop + parH + (if helipad then 9 else 4)
		box(ctx, "FlagPole", Vector3.new(0.4, poleH, 0.4), Vector3.new(flagX, poleH * 0.5, hd + 1), col.Metal, Enum.Material.Metal)
		box(ctx, "Flag", Vector3.new(0.12, 3.6, 6), Vector3.new(flagX, poleH - 2.2, hd + 1 - 3.2), col.Flag, Enum.Material.Fabric, false)
		if goldCap then
			box(ctx, "FlagTip", Vector3.new(0.9, 0.9, 0.9), Vector3.new(flagX, poleH + 0.4, hd + 1), col.Gold, Enum.Material.Neon, false).Shape = Enum.PartType.Ball
		end
	end

	-- Ceiling lights (ground floor): a row along the building, spaced ~9 studs
	local lampCount = math.max(2, math.floor(W / 9))
	for i = 1, lampCount do
		local lx = -hw + W * (i - 0.5) / lampCount
		for _, lz in ipairs({ -hd * 0.4, hd * 0.35 }) do
			local lamp = box(ctx, "CeilingLight", Vector3.new(4, 0.2, 1.2), Vector3.new(lx, y1 + H1 - 0.15, lz), LIGHTS.FixtureColor or col.Light, FIXTURE_MATERIAL, false)
			light(lamp, 20, 1.0, col.Light)
		end
	end
	if twoStory then
		for i = 1, lampCount do
			local lx = -hw + W * (i - 0.5) / lampCount
			local lamp = box(ctx, "CeilingLight", Vector3.new(4, 0.2, 1.2), Vector3.new(lx, y2 + H2 - 0.15, hd * 0.3), LIGHTS.FixtureColor or col.Light, FIXTURE_MATERIAL, false)
			light(lamp, 18, 1.0, col.Light)
		end
	end

	-- Annex (comms room) + mast + floodlights
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
		local aLamp = box(ctx, "CeilingLight", Vector3.new(3, 0.2, 1), Vector3.new(axc, y1 + annexH - 0.15, annexZc), LIGHTS.FixtureColor or col.Light, FIXTURE_MATERIAL, false)
		light(aLamp, 16, 1.1, col.Light)
		local signA = box(ctx, "AnnexSign", Vector3.new(5, 1.2, 0.25), Vector3.new(axc, y1 + annexH - 1.2, az1 + 0.15), col.Dark, Enum.Material.Metal, false)
		surfaceText(signA, Enum.NormalId.Back, { c.AnnexSignText or "COMMS" }, col.Accent, col.Dark, Enum.Font.GothamBlack)

		local mx, mz = -hw + 2, -hd + 2
		box(ctx, "MastBase", Vector3.new(1.6, 1, 1.6), Vector3.new(mx, roofTop + 0.5, mz), col.Metal, Enum.Material.Metal)
		box(ctx, "Mast", Vector3.new(0.4, 14, 0.4), Vector3.new(mx, roofTop + 8, mz), col.Metal, Enum.Material.Metal, false)
		for i = 1, 3 do
			box(ctx, "MastBar", Vector3.new(2.4 - i * 0.5, 0.15, 0.15), Vector3.new(mx, roofTop + 3 + i * 3.2, mz), col.Metal, Enum.Material.Metal, false)
		end
		local beacon = box(ctx, "MastBeacon", Vector3.new(0.7, 0.7, 0.7), Vector3.new(mx, roofTop + 15.3, mz), Color3.fromRGB(220, 50, 40), FIXTURE_MATERIAL, false)
		beacon.Shape = Enum.PartType.Ball
		light(beacon, 10, 2, Color3.fromRGB(255, 60, 40))

		for _, fx in ipairs({ -hw + 1, hw - 1 }) do
			box(ctx, "Floodlight", Vector3.new(1.2, 0.8, 0.8), Vector3.new(fx, roofTop + parH + 0.8, hd - 0.2), col.Metal, Enum.Material.Metal, false)
			local lens = box(ctx, "FloodLens", Vector3.new(1.0, 0.6, 0.1), Vector3.new(fx, roofTop + parH + 0.8, hd + 0.25), LIGHTS.FixtureColor or col.Light, FIXTURE_MATERIAL, false)
			local spot = Instance.new("SpotLight")
			spot.Face = Enum.NormalId.Back
			spot.Angle = 70
			spot.Range = math.min(30, LIGHTS.SpotMaxRange or 30)
			spot.Brightness = 1.5 * (LIGHTS.BrightnessScale or 1)
			spot.Color = col.Light
			spot.Parent = lens
		end
	end

	-- Roof access: climbable truss through a hatch + dish
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
		local dx, dz = hw - 6, -hd + 4.5
		box(ctx, "DishMount", Vector3.new(0.6, 2.4, 0.6), Vector3.new(dx, roofTop + 1.2, dz), col.Metal, Enum.Material.Metal)
		local dish = part(ctx, "Dish", Vector3.new(0.4, 5, 5), ctx.origin * CFrame.new(dx, roofTop + 3.2, dz) * CFrame.Angles(0, math.rad(-120), math.rad(35)), Color3.fromRGB(220, 222, 218), Enum.Material.SmoothPlastic)
		dish.Shape = Enum.PartType.Cylinder
	end

	-- Rooftop helipad marking
	if helipad then
		local hx, hz = 2, 1.5
		local ring = part(ctx, "HelipadRing", Vector3.new(0.06, 12, 12), ctx.origin * CFrame.new(hx, roofTop + 0.03, hz) * CFrame.Angles(0, 0, math.pi * 0.5), col.Gold, Enum.Material.SmoothPlastic, false)
		ring.Shape = Enum.PartType.Cylinder
		local inner = part(ctx, "HelipadInner", Vector3.new(0.06, 10.6, 10.6), ctx.origin * CFrame.new(hx, roofTop + 0.05, hz) * CFrame.Angles(0, 0, math.pi * 0.5), col.Dark, Enum.Material.SmoothPlastic, false)
		inner.Shape = Enum.PartType.Cylinder
		box(ctx, "HelipadH", Vector3.new(0.8, 0.06, 5), Vector3.new(hx - 1.6, roofTop + 0.08, hz), col.Gold, Enum.Material.SmoothPlastic, false)
		box(ctx, "HelipadH", Vector3.new(0.8, 0.06, 5), Vector3.new(hx + 1.6, roofTop + 0.08, hz), col.Gold, Enum.Material.SmoothPlastic, false)
		box(ctx, "HelipadH", Vector3.new(2.4, 0.06, 0.8), Vector3.new(hx, roofTop + 0.08, hz), col.Gold, Enum.Material.SmoothPlastic, false)
	end

	-- Interior furnishing (per building type)
	local keepOut: { Rect } = {
		-- doorway approach
		{ X0 = doorX - doorW * 0.5 - 1, X1 = doorX + doorW * 0.5 + 1, Z0 = hd - t - 6, Z1 = hd - t },
	}
	local con = consoleLocal(ctx.structureId)
	if con then
		table.insert(keepOut, { X0 = con.X - 2.2, X1 = con.X + 2.2, Z0 = con.Z - 2.2, Z1 = con.Z + 2.2 })
	end
	if twoStory then
		table.insert(keepOut, { X0 = stairX0 - 0.5, X1 = stairX1 + 0.5, Z0 = stairZ0, Z1 = stairZ1 + 1 })
	end
	if hasAnnex then
		table.insert(keepOut, { X0 = hw - t - 2, X1 = hw - t, Z0 = annexZc - 3, Z1 = annexZc + 3 })
	end
	local ictx = {
		StructureId = ctx.structureId,
		Level = lv,
		W = W,
		D = D,
		T = t,
		HalfW = hw,
		HalfD = hd,
		H1 = H1,
		H2 = H2,
		Y1 = y1,
		Y2 = y2,
		TwoStory = twoStory,
		DoorX = doorX,
		DoorWidth = doorW,
		DoorHeight = doorH,
		Garage = garage,
		Console = con,
		KeepOut = keepOut,
		-- inner faces of the ground-floor walls
		InX0 = -hw + t,
		InX1 = hw - t,
		InZ0 = -hd + t,
		InZ1 = hd - t,
		Colors = col,
	}
	local api = makeApi(ctx, "WE_Interior")
	local interiors = script.Parent:FindFirstChild("Interiors")
	local modScript = interiors and interiors:FindFirstChild(c.Interior or ctx.structureId)
	if modScript and modScript:IsA("ModuleScript") then
		local ok, fn = pcall(require, modScript)
		if ok and typeof(fn) == "function" then
			local okRun, errRun = pcall(fn, ictx, api)
			if not okRun then
				warn("[HollowBuilding] interior failed", ctx.structureId, errRun)
			end
		else
			warn("[HollowBuilding] interior module did not load", ctx.structureId, fn)
		end
	end
end

-- Kiosk position in the installation's local frame (keep-out for the module), if the layout has one.
local function kioskLocal(structureId: string): Vector3?
	local s = (BaseLayoutConfig.Structures :: any)[structureId]
	if not (s and s.Kiosk and s.Site) then
		return nil
	end
	local dx, dz = s.Kiosk.X - s.Site.X, s.Kiosk.Z - s.Site.Z
	local a = math.rad(-(s.Yaw or 0))
	return Vector3.new(dx * math.cos(a) + dz * math.sin(a), 0, -dx * math.sin(a) + dz * math.cos(a))
end

local function buildInstallation(ctx: Ctx)
	local c = ctx.c
	local ictx = {
		StructureId = ctx.structureId,
		Level = ctx.level,
		W = c.Width,
		D = c.Depth,
		HalfW = c.Width * 0.5,
		HalfD = c.Depth * 0.5,
		Y0 = 0.4, -- foundation top (the kit Body slab)
		Colors = ctx.col,
		Kiosk = kioskLocal(ctx.structureId),
	}
	local api = makeApi(ctx, "WE_Installation")
	local folder = script.Parent:FindFirstChild("Installations")
	local modScript = folder and folder:FindFirstChild(c.Module or ctx.structureId)
	if not (modScript and modScript:IsA("ModuleScript")) then
		warn("[HollowBuilding] installation module missing", ctx.structureId)
		return
	end
	local ok, fn = pcall(require, modScript)
	if ok and typeof(fn) == "function" then
		local okRun, errRun = pcall(fn, ictx, api)
		if not okRun then
			warn("[HollowBuilding] installation failed", ctx.structureId, errRun)
		end
	else
		warn("[HollowBuilding] installation module did not load", ctx.structureId, fn)
	end
end

local function findModel(plinth: BasePart): Model?
	local m = plinth:FindFirstChild(MODEL_NAME)
	if m and m:IsA("Model") then
		return m
	end
	return nil
end

--[[ Build / rebuild / remove the walk-in building (or outdoor installation) for this plinth at `level`. Idempotent. ]]
function HollowBuildingBuilder.Sync(plinth: BasePart, structureId: string, level: number)
	local c = cfgFor(structureId)
	local inst = if c then nil else instCfgFor(structureId)
	local existing = findModel(plinth)
	local lv = math.clamp(math.floor(tonumber(level) or 0), 0, 5)
	if (not c and not inst) or lv < 1 then
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
	local cfg = c or inst
	local ctx: Ctx = {
		model = model,
		origin = originFor(plinth, cfg),
		c = cfg,
		col = cfg.Colors,
		level = lv,
		structureId = structureId,
	}
	local ok, err = pcall(if inst then buildInstallation else build, ctx)
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
