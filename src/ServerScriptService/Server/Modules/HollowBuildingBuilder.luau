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
local GEN = 3 -- v73 distinct shells: live models built by GEN 2 rebuild once

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

-- v73: WedgePart in building space. Roblox wedge: the slope faces local -Z (and up), the tall face is local +Z.
local function wedgeAt(ctx: Ctx, name: string, size: Vector3, localCF: CFrame, color: Color3, material: Enum.Material, collide: boolean?): WedgePart
	local w = Instance.new("WedgePart")
	w.Name = name
	w.Anchored = true
	w.Size = size
	w.CFrame = ctx.origin * localCF
	w.Color = color
	w.Material = material
	w.TopSurface = Enum.SurfaceType.Smooth
	w.BottomSurface = Enum.SurfaceType.Smooth
	w.CanCollide = if collide == nil then true else collide
	w.CanTouch = false
	w.CanQuery = w.CanCollide
	w.CastShadow = true
	w.Parent = ctx.model
	return w
end

-- v73: vertical cylinder (Roblox cylinders run along local X) standing on y0 in building space
local function column(ctx: Ctx, name: string, diameter: number, height: number, x: number, y0: number, z: number, color: Color3, material: Enum.Material, collide: boolean?): Part
	local p = part(ctx, name, Vector3.new(height, diameter, diameter), ctx.origin * CFrame.new(x, y0 + height * 0.5, z) * CFrame.Angles(0, 0, math.pi * 0.5), color, material, collide)
	p.Shape = Enum.PartType.Cylinder
	return p
end

-- v73: window list entry = a number (centre, default width) or { X = centre, W = width }
local function winAt(e: any, defW: number): (number, number)
	if typeof(e) == "table" then
		return tonumber(e.X) or 0, tonumber(e.W) or defW
	end
	return tonumber(e) or 0, defW
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

--[[ v70 light budget (HUD spec §5, mobile P1-12; CLAUDE.md: at most 40 lights per base at L5, was 120). The fitting
	parts all stay; only these carry no PointLight:
	  - ceiling fittings other than the one nearest each floor's centre (one light per floor);
	  - entry lamps and terminal lamps (the lamp part still reads as lit);
	  - red warning beacons on masts / pylons / towers (WARNING_BEACONS);
	  - every second fitting of the same name inside one interior / installation module (a row of 3 hangar lamps
	    keeps 2, a pair of floodlamps keeps 1).
	StructureVisualConfig.BuildingLights.LightEveryOther = false turns the last rule off. ]]
local WARNING_BEACONS: { [string]: boolean } = { TowerBeacon = true, PylonBeacon = true, TowerLamp = true, MastBeacon = true }
local TERMINAL_PROMPT_RANGE = 12 -- mobile P1-19: 8 → 12 studs (the thumbstick overshoots a small range)

-- v70: every SurfaceGui draws near-only (CLAUDE.md budget: MaxDistance <= 80). Screens and signs inside a building
-- only need the room (SURFACE_NEAR); outdoor building / installation signs SURFACE_FAR.
local SURFACE_NEAR = 40
local SURFACE_FAR = 80

local function surfaceText(host: BasePart, face: Enum.NormalId, lines: { string }, textColor: Color3, bg: Color3, font: Enum.Font?, maxDistance: number?)
	local sg = Instance.new("SurfaceGui")
	sg.Name = "WE_Screen"
	sg.Face = face
	sg.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	sg.PixelsPerStud = 40
	sg.LightInfluence = 0
	sg.MaxDistance = math.min(maxDistance or SURFACE_NEAR, SURFACE_FAR)
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
	-- v73 distinct shells: per-building wall material / frame colour (StructureVisualConfig.HollowBuildings)
	local wallMat: Enum.Material = c.WallMaterial or Enum.Material.Concrete
	local frameCol: Color3 = col.Frame or col.Trim
	local function seg(a: number, b: number, y0: number, y1: number)
		if b - a < 0.05 or y1 - y0 < 0.05 then
			return
		end
		part(ctx, name, Vector3.new(b - a, y1 - y0, t), wallCF * CFrame.new((a + b) * 0.5, (y0 + y1) * 0.5, 0), col.Wall, wallMat)
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
				if c.WindowMullion ~= false and w > 2 then
					-- one mullion per ~4.5 studs (a ribbon window reads as a row of panes, a normal window keeps one)
					local n = if w >= 9 then math.floor(w / 4.5) else 1
					for k = 1, n do
						local mx = oa + w * k / (n + 1)
						part(ctx, name .. "Mullion", Vector3.new(0.2, o.Height, 0.3), wallCF * CFrame.new(mx, midY, 0), frameCol, Enum.Material.Metal, false)
					end
				end
				if c.WindowLedge ~= false then
					part(ctx, name .. "Ledge", Vector3.new(w + 0.6, 0.3, 0.7), wallCF * CFrame.new((oa + ob) * 0.5, baseY + o.Bottom - 0.15, t * 0.5 + 0.2), frameCol, Enum.Material.Metal, false)
				end
			elseif o.Garage then
				local frameT = t + 0.4
				for _, edge in ipairs({ oa + 0.3, ob - 0.3 }) do
					part(ctx, name .. "GarageFrame", Vector3.new(0.6, o.Height, frameT), wallCF * CFrame.new(edge, midY, 0), col.Accent, Enum.Material.SmoothPlastic, false)
				end
				part(ctx, name .. "GarageHeader", Vector3.new(w, 0.6, frameT), wallCF * CFrame.new((oa + ob) * 0.5, baseY + o.Bottom + o.Height - 0.3, 0), col.Metal, Enum.Material.Metal, false)
				local drum = part(ctx, name .. "ShutterDrum", Vector3.new(w - 0.6, 1.4, 1.4), wallCF * CFrame.new((oa + ob) * 0.5, baseY + o.Bottom + o.Height - 0.5, -t * 0.5 - 0.7), col.Metal, Enum.Material.DiamondPlate, false)
				drum.Shape = Enum.PartType.Cylinder
			else
				-- v73: a heavier, coloured frame reads as a blast-door portal (Armory) at no extra parts
				local fw: number = c.DoorFrameWidth or 0.35
				local frameT = t + (c.DoorFrameDepth or 0.3)
				local dcol: Color3 = col.DoorFrame or col.Metal
				part(ctx, name .. "DoorFrame", Vector3.new(fw, o.Height, frameT), wallCF * CFrame.new(oa + fw * 0.5, midY, 0), dcol, Enum.Material.Metal, false)
				part(ctx, name .. "DoorFrame", Vector3.new(fw, o.Height, frameT), wallCF * CFrame.new(ob - fw * 0.5, midY, 0), dcol, Enum.Material.Metal, false)
				part(ctx, name .. "DoorFrame", Vector3.new(w, fw, frameT), wallCF * CFrame.new((oa + ob) * 0.5, baseY + o.Bottom + o.Height - fw * 0.5, 0), dcol, Enum.Material.Metal, false)
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
	-- the lamp is a small interactive cue (kept Neon, spec §5); no PointLight (v70 light budget)
	part(ctx, name .. "Lamp", Vector3.new(0.4, 0.2, 0.4), frame * CFrame.new(0.8, 3.25, 0.35), col.Screen, Enum.Material.Neon, false)
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "WE_PanelPrompt"
	prompt.ActionText = actionText
	prompt.ObjectText = objectText
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = TERMINAL_PROMPT_RANGE
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
	-- v70 light budget (see WARNING_BEACONS): modules call api.light per fitting; the budget rules apply here
	local fittings: { [string]: number } = {}
	local everyOther = LIGHTS.LightEveryOther ~= false
	local function budgetLight(host: BasePart, range: number, brightness: number, color: Color3)
		if WARNING_BEACONS[host.Name] then
			return
		end
		local n = (fittings[host.Name] or 0) + 1
		fittings[host.Name] = n
		if everyOther and n % 2 == 0 then
			return
		end
		light(host, range, brightness, color)
	end
	local api = {
		box = function(name: string, size: Vector3, pos: Vector3, color: Color3, material: Enum.Material, collide: boolean?): Part
			return tagged(box(ctx, name, size, pos, color, material, collide))
		end,
		part = function(name: string, size: Vector3, localCF: CFrame, color: Color3, material: Enum.Material, collide: boolean?): Part
			return tagged(part(ctx, name, size, ctx.origin * localCF, color, material, collide))
		end,
		light = budgetLight,
		surfaceText = function(host: BasePart, face: Enum.NormalId, lines: { string }, textColor: Color3, bg: Color3, font: Enum.Font?, maxDistance: number?)
			surfaceText(host, face, lines, textColor, bg, font, maxDistance or (if tag == "WE_Installation" then SURFACE_FAR else SURFACE_NEAR))
		end,
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
	-- v73 distinct shells (StructureVisualConfig.HollowBuildings): roof form, wall material, entrance, signatures
	local roofStyle: string = c.RoofStyle or "Flat"
	local entrance: string = c.Entrance or (if garage then "Canopy" else "Awning")
	local sig: { [string]: boolean } = {}
	for _, s in ipairs(c.Signatures or {}) do
		sig[s] = true
	end
	local wallMat: Enum.Material = c.WallMaterial or Enum.Material.Concrete
	local frameCol: Color3 = col.Frame or col.Trim
	local roofCol: Color3 = col.RoofSkin or col.Roof
	local roofMat: Enum.Material = c.RoofMaterial or Enum.Material.Metal

	local y1 = 0.4 -- ground floor top (foundation slab = kit Body)
	local y2 = y1 + H1 + 0.8 -- upper floor top
	local roofBottom = if twoStory then y2 + H2 else y1 + H1
	local slabT = if roofStyle == "Lid" then (c.LidThickness or 1.6) else 0.8
	local roofTop = roofBottom + slabT

	local doorX, doorW, doorH = c.DoorX, c.DoorWidth, c.DoorHeight
	local winW, winH, winBottom = c.WindowWidth, c.WindowHeight, c.WindowBottom
	local upW, upH, upBottom = c.UpperWindowWidth or winW, c.UpperWindowHeight or 3.0, c.UpperWindowBottom or 3.2

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
	for _, e in ipairs(c.FrontWindowsX or {}) do
		local wx, ww = winAt(e, winW)
		table.insert(frontOpen, { Center = wx, Width = ww, Bottom = winBottom, Height = winH, Glass = true })
	end
	wall(ctx, "WallFront", frontCF, W, H1, y1, frontOpen)

	local backOpen: { Opening } = {}
	if not twoStory then
		for _, e in ipairs(c.BackWindowsX or {}) do
			local wx, ww = winAt(e, winW)
			-- back wall local X is mirrored (rotated 180°)
			table.insert(backOpen, { Center = -wx, Width = ww, Bottom = winBottom, Height = winH, Glass = true })
		end
	end
	wall(ctx, "WallBack", backCF, W, H1, y1, backOpen)

	local westOpen: { Opening } = {}
	for _, e in ipairs(c.WestWindowsZ or {}) do
		local wz, ww = winAt(e, winW)
		table.insert(westOpen, { Center = wz, Width = ww, Bottom = winBottom, Height = winH, Glass = true })
	end
	wall(ctx, "WallWest", westCF, sideLen, H1, y1, westOpen)

	local eastOpen: { Opening } = {}
	if hasAnnex then
		table.insert(eastOpen, { Center = -annexZc, Width = 4, Bottom = 0, Height = 7.5, Glass = false })
	else
		for _, e in ipairs(c.EastWindowsZ or {}) do
			local wz, ww = winAt(e, winW)
			table.insert(eastOpen, { Center = -wz, Width = ww, Bottom = winBottom, Height = winH, Glass = true })
		end
	end
	wall(ctx, "WallEast", eastCF, sideLen, H1, y1, eastOpen)

	-- Upper storey
	if twoStory then
		local upFront: { Opening } = {}
		for _, e in ipairs(c.UpperWindowsX or c.FrontWindowsX or {}) do
			local wx, ww = winAt(e, upW)
			table.insert(upFront, { Center = wx, Width = ww, Bottom = upBottom, Height = upH, Glass = true })
		end
		wall(ctx, "WallFront2", frontCF, W, H2, y2, upFront)
		local upBack: { Opening } = {}
		for _, e in ipairs(c.UpperBackWindowsX or c.BackWindowsX or {}) do
			local wx, ww = winAt(e, upW)
			table.insert(upBack, { Center = -wx, Width = ww, Bottom = upBottom, Height = upH, Glass = true })
		end
		wall(ctx, "WallBack2", backCF, W, H2, y2, upBack)
		local upSide: { Opening } = {}
		if c.UpperSideWindows ~= false then
			upSide = { { Center = 0, Width = upW, Bottom = upBottom, Height = upH, Glass = true } }
		end
		wall(ctx, "WallWest2", westCF, sideLen, H2, y2, table.clone(upSide))
		wall(ctx, "WallEast2", eastCF, sideLen, H2, y2, table.clone(upSide))
		box(ctx, "StoreyBand", Vector3.new(W + 0.4, 0.8, 0.3), Vector3.new(0, y2 - 0.4, hd + 0.15), frameCol, Enum.Material.Metal, false)
		box(ctx, "StoreyBand", Vector3.new(W + 0.4, 0.8, 0.3), Vector3.new(0, y2 - 0.4, -hd - 0.15), frameCol, Enum.Material.Metal, false)
		box(ctx, "StoreyBand", Vector3.new(0.3, 0.8, D + 0.4), Vector3.new(hw + 0.15, y2 - 0.4, 0), frameCol, Enum.Material.Metal, false)
		box(ctx, "StoreyBand", Vector3.new(0.3, 0.8, D + 0.4), Vector3.new(-hw - 0.15, y2 - 0.4, 0), frameCol, Enum.Material.Metal, false)

		slab(ctx, "Floor2", -hw + t, hw - t, -hd + t, hd - t, y2 - 0.8, 0.8, col.Floor, Enum.Material.Concrete, { stairX0 - 0.2, stairX1, stairZ0 - 0.1, stairZ1 + 0.2 })
		for k = 1, stepCount do
			local top = y1 + k * stepRise
			box(ctx, "Stair", Vector3.new(stepRun, top - y1, stairW), Vector3.new(stairX0 + (k - 0.5) * stepRun, y1 + (top - y1) * 0.5, (stairZ0 + stairZ1) * 0.5), col.Stair, Enum.Material.Concrete)
		end
		railing(ctx, Vector3.new(stairX0 - 0.2, y2, stairZ1 + 0.3), Vector3.new(stairX1 - 2.4, y2, stairZ1 + 0.3), 3)
	end

	-- Roof: the ceiling slab (every style) + the building's own roof form
	local roofHole: { number }? = nil
	local trussX = hw - t - 1.3
	local trussZ = hd - t - 1.3
	if roofAccess then
		roofHole = { trussX - 1.6, trussX + 1.6, trussZ - 1.6, trussZ + 1.6 }
	end
	local parH = 1.4
	if roofStyle == "Lid" then
		-- bunker lid: one thick slab overhanging every wall, no parapet (Armory)
		local ov: number = c.LidOverhang or 1.2
		slab(ctx, "Roof", -hw - ov, hw + ov, -hd - ov, hd + ov, roofBottom, slabT, col.Roof, Enum.Material.Concrete, roofHole)
		parH = 0
		if goldCap then
			box(ctx, "LidTrim", Vector3.new(W + 2 * ov + 0.1, 0.35, 0.35), Vector3.new(0, roofTop - 0.175, hd + ov), col.Gold, Enum.Material.Metal, false)
		end
	else
		slab(ctx, "Roof", -hw, hw, -hd, hd, roofBottom, 0.8, col.Roof, Enum.Material.Concrete, roofHole)
	end
	if roofStyle == "Flat" then
		box(ctx, "Parapet", Vector3.new(W, parH, t), Vector3.new(0, roofTop + parH * 0.5, hd - t * 0.5), col.Wall, wallMat)
		box(ctx, "Parapet", Vector3.new(W, parH, t), Vector3.new(0, roofTop + parH * 0.5, -hd + t * 0.5), col.Wall, wallMat)
		box(ctx, "Parapet", Vector3.new(t, parH, D - 2 * t), Vector3.new(hw - t * 0.5, roofTop + parH * 0.5, 0), col.Wall, wallMat)
		box(ctx, "Parapet", Vector3.new(t, parH, D - 2 * t), Vector3.new(-hw + t * 0.5, roofTop + parH * 0.5, 0), col.Wall, wallMat)
		local capColor = if goldCap then col.Gold else frameCol
		box(ctx, "ParapetCap", Vector3.new(W + 0.3, 0.3, t + 0.3), Vector3.new(0, roofTop + parH + 0.15, hd - t * 0.5), capColor, Enum.Material.Metal, false)
		box(ctx, "ParapetCap", Vector3.new(W + 0.3, 0.3, t + 0.3), Vector3.new(0, roofTop + parH + 0.15, -hd + t * 0.5), capColor, Enum.Material.Metal, false)
		box(ctx, "ParapetCap", Vector3.new(t + 0.3, 0.3, D), Vector3.new(hw - t * 0.5, roofTop + parH + 0.15, 0), capColor, Enum.Material.Metal, false)
		box(ctx, "ParapetCap", Vector3.new(t + 0.3, 0.3, D), Vector3.new(-hw + t * 0.5, roofTop + parH + 0.15, 0), capColor, Enum.Material.Metal, false)
	elseif roofStyle == "Gable" then
		-- pitched roof, ridge along X: two wedges back to back on the ceiling slab (Barracks)
		local rise: number = c.RoofRise or 6
		local ov: number = c.RoofOverhang or 1
		local run = hd + ov
		local len = W + 2 * ov
		wedgeAt(ctx, "RoofPitch", Vector3.new(len, rise, run), CFrame.new(0, roofTop + rise * 0.5, run * 0.5) * CFrame.Angles(0, math.pi, 0), roofCol, roofMat)
		wedgeAt(ctx, "RoofPitch", Vector3.new(len, rise, run), CFrame.new(0, roofTop + rise * 0.5, -run * 0.5), roofCol, roofMat)
		box(ctx, "RoofRidge", Vector3.new(len + 0.2, 0.45, 0.9), Vector3.new(0, roofTop + rise, 0), if goldCap then col.Gold else frameCol, Enum.Material.Metal, false)
		parH = rise
	elseif roofStyle == "Vault" then
		-- segmental barrel vault across the facade (hangar), glazed arch end at the front (Vehicle Depot)
		local rise: number = c.RoofRise or 9
		local ov: number = c.RoofOverhang or 0.6
		local a = hw + ov
		local R = (a * a + rise * rise) / (2 * rise)
		local yc = roofTop + rise - R
		local th0 = math.asin(a / R)
		local n: number = c.VaultSegments or 8
		local dth = 2 * th0 / n
		local chord = 2 * R * math.sin(dth * 0.5)
		local th = 0.6
		local len = D + 2 * (c.RoofEndOverhang or 1.2)
		local rm = R * math.cos(dth * 0.5) + th * 0.5
		for i = 0, n - 1 do
			local phi = -th0 + (i + 0.5) * dth
			part(ctx, "VaultPlank", Vector3.new(chord + 0.3, th, len), ctx.origin * CFrame.new(rm * math.sin(phi), yc + rm * math.cos(phi), 0) * CFrame.Angles(0, 0, -phi), roofCol, roofMat)
		end
		local strips: number = c.VaultEndStrips or 4
		local hs = rise / strips
		for s = 0, strips - 1 do
			local yb = roofTop + s * hs
			local yq = math.min(roofTop + (s + 1) * hs, roofTop + rise - 0.35)
			local half = math.min(hw, math.sqrt(math.max(0, R * R - (yq - yc) ^ 2)))
			if half > 0.5 and yq > yb + 0.1 then
				local g = box(ctx, "VaultEndGlass", Vector3.new(2 * half, yq - yb, 0.3), Vector3.new(0, (yb + yq) * 0.5, hd - t * 0.5), col.Glass, Enum.Material.Glass, false)
				g.Transparency = 0.3
				box(ctx, "VaultEnd", Vector3.new(2 * half, yq - yb, t), Vector3.new(0, (yb + yq) * 0.5, -hd + t * 0.5), col.Wall, wallMat)
			end
		end
		if goldCap then
			box(ctx, "VaultCrown", Vector3.new(0.9, 0.3, len + 0.1), Vector3.new(0, roofTop + rise + th + 0.1, 0), col.Gold, Enum.Material.Metal, false)
		end
		parH = rise + th
	elseif roofStyle == "Sawtooth" then
		-- factory sawtooth: ridges run front to back so the zigzag reads from the road (Warehouse)
		local teeth: number = c.SawTeeth or 4
		local rise: number = c.RoofRise or 4.5
		local tw = W / teeth
		local len = D + 1
		for k = 0, teeth - 1 do
			local cx = -hw + (k + 0.5) * tw
			wedgeAt(ctx, "SawTooth", Vector3.new(len, rise, tw), CFrame.new(cx, roofTop + rise * 0.5, 0) * CFrame.Angles(0, math.pi * 0.5, 0), roofCol, roofMat)
			local g = box(ctx, "SawGlass", Vector3.new(0.2, rise - 0.7, len - 1.2), Vector3.new(cx + tw * 0.5 + 0.12, roofTop + rise * 0.5 - 0.15, 0), col.Glass, Enum.Material.Glass, false)
			g.Transparency = 0.25
		end
		if goldCap then
			box(ctx, "SawTrim", Vector3.new(W + 0.2, 0.35, 0.35), Vector3.new(0, roofTop + 0.18, hd + 0.35), col.Gold, Enum.Material.Metal, false)
		end
		parH = rise
	end

	-- Rooftop plant
	if c.RoofPlant ~= false then
		box(ctx, "ACUnit", Vector3.new(3, 1.6, 2.4), Vector3.new(-hw + 5, roofTop + 0.8, -hd + 3), col.Metal, Enum.Material.DiamondPlate)
		box(ctx, "ACUnit", Vector3.new(3, 1.6, 2.4), Vector3.new(-hw + 9, roofTop + 0.8, -hd + 3), col.Metal, Enum.Material.DiamondPlate)
		box(ctx, "Vent", Vector3.new(1.2, 1.4, 1.2), Vector3.new(hw - 3, roofTop + 0.7, 0), col.Dark, Enum.Material.Metal)
	end
	if c.Skylights and roofStyle == "Flat" then
		for i, sx in ipairs({ -hw * 0.45, 0, hw * 0.45 }) do
			local sky = box(ctx, "Skylight" .. i, Vector3.new(5, 0.5, 3.4), Vector3.new(sx, roofTop + 0.25, hd * 0.2), col.Glass, Enum.Material.Glass, false)
			sky.Transparency = 0.35
		end
	end

	-- Entrance (v73: one style per building)
	local awnY = y1 + doorH + 1.0
	if entrance == "Canopy" then
		box(ctx, "Canopy", Vector3.new(doorW + 4, 0.4, 4.6), Vector3.new(doorX, awnY, hd + 2.3), col.Metal, Enum.Material.DiamondPlate)
	elseif entrance == "HangarDoors" then
		-- two hangar door leaves rolled open to either side on a track beam across the facade (Vehicle Depot)
		local leafW: number = c.HangarLeafWidth or 8
		for _, sx in ipairs({ -1, 1 }) do
			box(ctx, "HangarLeaf", Vector3.new(leafW, doorH + 0.6, 0.5), Vector3.new(doorX + sx * (doorW * 0.5 + leafW * 0.5), y1 + (doorH + 0.6) * 0.5, hd + 0.45), col.Door or col.Metal, Enum.Material.Metal, false)
		end
		box(ctx, "HangarTrack", Vector3.new(W, 0.6, 0.7), Vector3.new(0, y1 + doorH + 0.4, hd + 0.5), col.Dark, Enum.Material.Metal, false)
	elseif entrance == "Portico" then
		-- two columns, an entablature and a pediment over the door (Command Center)
		local pw = doorW + 4.4
		for _, sx in ipairs({ -1, 1 }) do
			column(ctx, "PorticoColumn", 1.2, awnY - y1, doorX + sx * (pw * 0.5 - 0.9), y1, hd + 3.6, frameCol, Enum.Material.Concrete)
		end
		box(ctx, "PorticoBeam", Vector3.new(pw, 0.8, 4.6), Vector3.new(doorX, awnY + 0.4, hd + 2.3), col.Wall, wallMat)
		local rise, run = 2.2, pw * 0.5
		wedgeAt(ctx, "Pediment", Vector3.new(4.6, rise, run), CFrame.new(doorX - run * 0.5, awnY + 0.8 + rise * 0.5, hd + 2.3) * CFrame.Angles(0, math.pi * 0.5, 0), frameCol, Enum.Material.Metal)
		wedgeAt(ctx, "Pediment", Vector3.new(4.6, rise, run), CFrame.new(doorX + run * 0.5, awnY + 0.8 + rise * 0.5, hd + 2.3) * CFrame.Angles(0, -math.pi * 0.5, 0), frameCol, Enum.Material.Metal)
	elseif entrance == "LeanTo" then
		-- sloped hut porch roof on two posts (Barracks)
		wedgeAt(ctx, "PorchRoof", Vector3.new(doorW + 3, 1.2, 3.8), CFrame.new(doorX, awnY, hd + 1.9) * CFrame.Angles(0, math.pi, 0), roofCol, roofMat)
		for _, sx in ipairs({ -1, 1 }) do
			box(ctx, "AwningPost", Vector3.new(0.4, awnY - 0.6 - y1, 0.4), Vector3.new(doorX + sx * (doorW * 0.5 + 1.2), y1 + (awnY - 0.6 - y1) * 0.5, hd + 3.4), frameCol, Enum.Material.Wood)
		end
	elseif entrance == "CamoNet" then
		-- camouflage net on two poles, sagging away from the wall (Special Forces)
		local netW: number = c.NetWidth or (doorW + 10)
		local netX: number = c.NetX or doorX
		local net = part(ctx, "CamoNet", Vector3.new(netW, 0.15, 6.6), ctx.origin * CFrame.new(netX, awnY + 0.3, hd + 3.2) * CFrame.Angles(math.rad(9), 0, 0), col.Net or col.Trim, Enum.Material.Fabric, false)
		net.CanQuery = false
		for _, sx in ipairs({ -1, 1 }) do
			box(ctx, "AwningPost", Vector3.new(0.3, awnY - 0.3 - y1, 0.3), Vector3.new(netX + sx * (netW * 0.5 - 1), y1 + (awnY - 0.3 - y1) * 0.5, hd + 5.8), col.Metal, Enum.Material.Metal)
		end
	elseif entrance == "BlastDoor" then
		-- heavy door leaf rolled aside + hazard band; the door frame itself is the thick yellow portal (Armory)
		local leafX = doorX - doorW - 0.2
		box(ctx, "BlastLeaf", Vector3.new(doorW + 0.4, doorH + 0.4, 0.6), Vector3.new(leafX, y1 + (doorH + 0.4) * 0.5, hd + 0.4), col.Door or col.Metal, Enum.Material.DiamondPlate)
		box(ctx, "BlastLeafBand", Vector3.new(doorW + 0.45, 0.7, 0.64), Vector3.new(leafX, y1 + doorH * 0.55, hd + 0.4), col.Accent, Enum.Material.SmoothPlastic, false)
	elseif entrance == "Slab" then
		-- cantilevered flat canopy, no posts (Research Lab)
		box(ctx, "Awning", Vector3.new(doorW + 3, 0.35, 3.6), Vector3.new(doorX, awnY, hd + 1.8), frameCol, Enum.Material.Metal)
	else
		box(ctx, "Awning", Vector3.new(doorW + 3, 0.35, 3.6), Vector3.new(doorX, awnY, hd + 1.8), frameCol, Enum.Material.Metal)
		box(ctx, "AwningPost", Vector3.new(0.35, awnY - y1, 0.35), Vector3.new(doorX - doorW * 0.5 - 1.2, y1 + (awnY - y1) * 0.5, hd + 3.3), col.Metal, Enum.Material.Metal)
		box(ctx, "AwningPost", Vector3.new(0.35, awnY - y1, 0.35), Vector3.new(doorX + doorW * 0.5 + 1.2, y1 + (awnY - y1) * 0.5, hd + 3.3), col.Metal, Enum.Material.Metal)
	end
	if garage then
		for _, sx in ipairs({ -1, 1 }) do
			-- stands on the ground outside the foundation slab (was 0.4 in the air); top unchanged at y1 + 1.6
			box(ctx, "BollardHazard", Vector3.new(0.9, y1 + 1.6, 0.9), Vector3.new(doorX + sx * (doorW * 0.5 + 1.2), (y1 + 1.6) * 0.5, hd + 1.2), col.Accent, Enum.Material.SmoothPlastic)
		end
	end
	-- entry lamp fitting only (v70 light budget: no PointLight)
	-- v73: the fitting hangs under whatever covers the door (flush under the portico beam / porch roof); with no
	-- cover over it (camo net slopes up to the wall, blast door, hangar track) it is wall-mounted above the door
	local lampY, lampZ = awnY - 0.3, hd + 1.4
	if entrance == "Portico" then
		lampY = awnY - 0.1
	elseif entrance == "LeanTo" then
		lampY = awnY - 0.7
	elseif entrance == "CamoNet" or entrance == "BlastDoor" then
		lampZ = hd + 0.4
	elseif entrance == "HangarDoors" then
		lampY, lampZ = y1 + doorH + 0.4, hd + 1.25
	end
	box(ctx, "EntryLamp", Vector3.new(1.4, 0.2, 0.8), Vector3.new(doorX, lampY, lampZ), LIGHTS.FixtureColor or col.Light, FIXTURE_MATERIAL, false)
	local signW: number = c.SignWidth or math.min(W - 6, 16)
	local signY = math.min(awnY + 1.6, y1 + H1 - 1.2)
	local signX = c.SignX or 0
	-- only slide the sign sideways if it would hang down over the doorway
	if math.abs(signX - doorX) < (signW + doorW) * 0.5 and signY - 1 < y1 + doorH + 0.4 then
		signX = if doorX > 0 then doorX - doorW * 0.5 - signW * 0.5 - 1 else doorX + doorW * 0.5 + signW * 0.5 + 1
	end
	local sign = box(ctx, "Sign", Vector3.new(signW, 2.0, 0.3), Vector3.new(signX, signY, hd + 0.15), col.SignBoard or col.Dark, Enum.Material.Metal, false)
	-- NormalId.Back is the +Z face = the building front
	surfaceText(sign, Enum.NormalId.Back, { c.SignText or "COMMAND CENTER" }, col.Accent, col.SignBoard or col.Dark, Enum.Font.GothamBlack, SURFACE_FAR)
	if not garage and c.EntranceSandbags ~= false then
		sandbags(ctx, doorX + doorW * 0.5 + 1.6, doorX + doorW * 0.5 + 6.5, hd + 1.6, 0)
	end

	-- Flag
	if lv >= (c.FlagLevel or 1) then
		local flagX = -hw - 2.5
		-- always clear the roofline (two-storey from L3), taller again at L5
		local poleH = roofTop + parH + (if helipad then 9 else 4)
		box(ctx, "FlagPole", Vector3.new(0.4, poleH, 0.4), Vector3.new(flagX, poleH * 0.5, hd + 1), col.Metal, Enum.Material.Metal)
		-- v73: the cloth is 0.12 thick along X; its Left / Right faces are the nation-flag decal host (WE_FlagHost)
		local cloth = box(ctx, "Flag", Vector3.new(0.12, 3.6, 6), Vector3.new(flagX, poleH - 2.2, hd + 1 - 3.2), col.Flag, Enum.Material.Fabric, false)
		cloth:SetAttribute("WE_FlagHost", true)
		if goldCap then
			-- v70: painted gold ball (was Neon: spec §5, no neon that is not a light source)
			box(ctx, "FlagTip", Vector3.new(0.9, 0.9, 0.9), Vector3.new(flagX, poleH + 0.4, hd + 1), col.Gold, Enum.Material.SmoothPlastic, false).Shape = Enum.PartType.Ball
		end
	end

	-- v73 signature features (one or two per building; StructureVisualConfig.HollowBuildings.<Id>.Signatures)
	if sig.ControlCab and twoStory then
		-- rooftop control cab with a glass band: the HQ is the tallest block on the base (Command Center)
		local cx, cz, cw, cd, ch = -hw + 4.6, 2, 7, 10, 4.6
		box(ctx, "CabBody", Vector3.new(cw, ch, cd), Vector3.new(cx, roofTop + ch * 0.5, cz), col.Wall, wallMat)
		local band = box(ctx, "CabGlass", Vector3.new(cw + 0.12, 1.8, cd + 0.12), Vector3.new(cx, roofTop + ch - 1.5, cz), col.Glass, Enum.Material.Glass, false)
		band.Transparency = 0.15
		box(ctx, "CabRoof", Vector3.new(cw + 1.2, 0.5, cd + 1.2), Vector3.new(cx, roofTop + ch + 0.25, cz), frameCol, Enum.Material.Metal)
	end
	if sig.Berms then
		-- earth berms banked against both side walls (Armory)
		local bh: number = c.BermHeight or 5
		local br: number = c.BermRun or 5
		wedgeAt(ctx, "Berm", Vector3.new(D - 1, bh, br), CFrame.new(-hw - br * 0.5, y1 + bh * 0.5 - 0.4, 0) * CFrame.Angles(0, math.pi * 0.5, 0), col.Berm or col.Sandbag, Enum.Material.Ground)
		wedgeAt(ctx, "Berm", Vector3.new(D - 1, bh, br), CFrame.new(hw + br * 0.5, y1 + bh * 0.5 - 0.4, 0) * CFrame.Angles(0, -math.pi * 0.5, 0), col.Berm or col.Sandbag, Enum.Material.Ground)
	end
	if sig.Bastions then
		-- sloped concrete buttresses at the front corners (Armory)
		for _, sx in ipairs({ -1, 1 }) do
			wedgeAt(ctx, "Buttress", Vector3.new(2.6, H1 - 1.5, 3), CFrame.new(sx * (hw - 1.3), y1 + (H1 - 1.5) * 0.5, hd + 1.5) * CFrame.Angles(0, math.pi, 0), col.Wall, wallMat)
		end
	end
	if sig.Slits then
		-- dark firing slits painted on the blind facade (no wall cut: 1 part each)
		for _, sx in ipairs(c.SlitX or { -11, -5 }) do
			box(ctx, "Slit", Vector3.new(3, 0.6, 0.12), Vector3.new(sx, y1 + 5.6, hd + 0.06), col.Dark, Enum.Material.SmoothPlastic, false)
		end
	end
	if sig.VentStacks then
		for _, p in ipairs({ Vector2.new(-hw + 6, -hd + 5), Vector2.new(hw - 8, -hd + 5) }) do
			column(ctx, "VentStack", 1.4, 2.2, p.X, roofTop, p.Y, col.Metal, Enum.Material.Metal)
		end
	end
	if sig.LatticeMast then
		-- tall lattice comms mast beside the building + dish (Special Forces). Not climbable: CanCollide off.
		local mh: number = c.MastHeight or 40
		local mx, mz = hw + 2.4, -hd + 2.4
		local mast = Instance.new("TrussPart")
		mast.Name = "CommsMast"
		mast.Anchored = true
		mast.Size = Vector3.new(2, mh, 2)
		mast.CFrame = ctx.origin * CFrame.new(mx, mh * 0.5, mz)
		mast.Color = col.Metal
		mast.Material = Enum.Material.Metal
		mast.CanCollide = false
		mast.CanQuery = false
		mast.CanTouch = false
		mast.Parent = ctx.model
		box(ctx, "MastArm", Vector3.new(0.3, 0.3, 6), Vector3.new(mx, mh - 2, mz), col.Metal, Enum.Material.Metal, false)
		local dish = part(ctx, "Dish", Vector3.new(0.4, 4.2, 4.2), ctx.origin * CFrame.new(mx, mh - 6, mz + 1.4) * CFrame.Angles(0, math.rad(-70), math.rad(20)), Color3.fromRGB(210, 212, 206), Enum.Material.SmoothPlastic, false)
		dish.Shape = Enum.PartType.Cylinder
	end
	if sig.SolarDish then
		-- solar panels tilted toward the avenue + a small dish on the flat roof (Research Lab). Not a radome: the Radar
		-- installation owns the dome silhouette. Panels and dish sit on the roof slab, clear of the parapet; no collision.
		local a = math.rad(22)
		for _, e in ipairs(c.SolarPanels or { { X = -8.5, Z = -3 }, { X = -0.5, Z = -3 } }) do
			local panel = part(ctx, "SolarPanel", Vector3.new(7, 0.3, 3.4), ctx.origin * CFrame.new(e.X, roofTop + 0.15 * math.cos(a) + 1.7 * math.sin(a), e.Z) * CFrame.Angles(a, 0, 0), col.Solar or col.Glass, Enum.Material.SmoothPlastic, false)
			panel.Reflectance = 0.12
		end
		local d = c.DishAt or { X = hw - 6, Z = -hd + 5 }
		box(ctx, "DishMount", Vector3.new(0.6, 2.2, 0.6), Vector3.new(d.X, roofTop + 1.1, d.Z), col.Metal, Enum.Material.Metal, false)
		local dish = part(ctx, "Dish", Vector3.new(0.4, 4.2, 4.2), ctx.origin * CFrame.new(d.X, roofTop + 3, d.Z) * CFrame.Angles(0, math.rad(-120), math.rad(35)), Color3.fromRGB(220, 222, 218), Enum.Material.SmoothPlastic, false)
		dish.Shape = Enum.PartType.Cylinder
	end
	if sig.FacadeBand and not twoStory then
		box(ctx, "FacadeBand", Vector3.new(W + 0.2, 1.2, 0.2), Vector3.new(0, roofBottom - 0.6, hd + 0.1), frameCol, Enum.Material.SmoothPlastic, false)
	end
	if sig.LoadingDock then
		-- raised loading dock left of the roller door (Warehouse)
		local dx0, dx1 = -hw + 0.8, doorX - doorW * 0.5 - 2.2
		box(ctx, "LoadingDock", Vector3.new(dx1 - dx0, 1.6, 4), Vector3.new((dx0 + dx1) * 0.5, 0.8, hd + 2), col.Floor, Enum.Material.Concrete)
		box(ctx, "DockBumper", Vector3.new(dx1 - dx0, 0.5, 0.3), Vector3.new((dx0 + dx1) * 0.5, 1.1, hd + 4.15), col.Dark, Enum.Material.Rubber, false)
	end
	if sig.Chimney then
		local ch = roofTop + parH + 4
		column(ctx, "Chimney", 2.2, ch, -hw + 3, 0, -hd - 1.3, col.Wall, wallMat)
	end
	if sig.StoveChimney then
		-- brick stove chimney through the back roof slope, near one gable end (Barracks)
		local ch = parH + 1.6
		box(ctx, "Chimney", Vector3.new(1.4, ch, 1.4), Vector3.new(hw - 4, roofTop + ch * 0.5, -hd * 0.3), col.Chimney or col.Dark, Enum.Material.Brick)
	end

	-- Ceiling lights: fittings in two rows (ground) / one row (upper), spaced ~9 studs. v70 light budget: only the
	-- fitting nearest each floor's centre carries a PointLight (one light per floor; the rest are unlit fittings).
	local lampCount = math.max(2, math.floor(W / 9))
	local litIndex = math.ceil(lampCount / 2)
	for i = 1, lampCount do
		local lx = -hw + W * (i - 0.5) / lampCount
		for row, lz in ipairs({ -hd * 0.4, hd * 0.35 }) do
			local lamp = box(ctx, "CeilingLight", Vector3.new(4, 0.2, 1.2), Vector3.new(lx, y1 + H1 - 0.15, lz), LIGHTS.FixtureColor or col.Light, FIXTURE_MATERIAL, false)
			if i == litIndex and row == 1 then
				light(lamp, 20, 1.0, col.Light)
			end
		end
	end
	if twoStory then
		for i = 1, lampCount do
			local lx = -hw + W * (i - 0.5) / lampCount
			local lamp = box(ctx, "CeilingLight", Vector3.new(4, 0.2, 1.2), Vector3.new(lx, y2 + H2 - 0.15, hd * 0.3), LIGHTS.FixtureColor or col.Light, FIXTURE_MATERIAL, false)
			if i == litIndex then
				light(lamp, 18, 1.0, col.Light)
			end
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
		surfaceText(signA, Enum.NormalId.Back, { c.AnnexSignText or "COMMS" }, col.Accent, col.Dark, Enum.Font.GothamBlack, SURFACE_FAR)

		local mx, mz = -hw + 2, -hd + 2
		box(ctx, "MastBase", Vector3.new(1.6, 1, 1.6), Vector3.new(mx, roofTop + 0.5, mz), col.Metal, Enum.Material.Metal)
		box(ctx, "Mast", Vector3.new(0.4, 14, 0.4), Vector3.new(mx, roofTop + 8, mz), col.Metal, Enum.Material.Metal, false)
		for i = 1, 3 do
			box(ctx, "MastBar", Vector3.new(2.4 - i * 0.5, 0.15, 0.15), Vector3.new(mx, roofTop + 3 + i * 3.2, mz), col.Metal, Enum.Material.Metal, false)
		end
		-- v70 (HUD spec §5): no red beacon ball / light on the mast top

		for _, fx in ipairs({ -hw + 1, hw - 1 }) do
			box(ctx, "Floodlight", Vector3.new(1.2, 0.8, 0.8), Vector3.new(fx, roofTop + parH + 0.8, hd - 0.2), col.Metal, Enum.Material.Metal, false)
			local lens = box(ctx, "FloodLens", Vector3.new(1.0, 0.6, 0.1), Vector3.new(fx, roofTop + parH + 0.8, hd + 0.25), LIGHTS.FixtureColor or col.Light, FIXTURE_MATERIAL, false)
			local spot = Instance.new("SpotLight")
			spot.Face = Enum.NormalId.Back
			spot.Angle = 70
			spot.Range = math.min(30, LIGHTS.SpotMaxRange or 30)
			spot.Brightness = 1.5 * (LIGHTS.BrightnessScale or 1)
			spot.Color = col.Light
			spot.Shadows = false
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
