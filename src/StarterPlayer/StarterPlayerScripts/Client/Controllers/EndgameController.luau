--!strict
--[[
	claude-bud JOB 39 (2026-09-30): ENDGAME PROGRESSION, the client (EndgameConfig, owner-first). Phase 1:
	  * THE PLAZA STATIONS (PlazaServicesConfig): for a player a station's part is live for, this builds the station
	    interior LOCALLY inside its plaza house (the frame the server published in ReplicatedStorage.WE_PlazaStations):
	    the Command Office = a map table, the "Chief of Staff" (a static Part figure, no Humanoid, not damageable), a
	    flag stand, a filing cabinet, a ceiling lamp (one PointLight, no shadows), the Empire board upstairs (a plaque
	    per milestone, gold once reached) and the door sign (one SurfaceGui, MaxDistance 40). 39 parts, no Neon. Nobody the job
	    is not live for gets anything (no parts, no prompt).
	  * the NPC's ProximityPrompt (HoldDuration 0, 12 studs; created here, so only live players ever see it) opens
	    THE STATION PANEL (one shared layout): the level, "+24% cash", the next card (cost, effect, "ready in 12:05"
	    from WE_Cash / WE_IncomePerSec), BUY (>= 64 v), the max state, the next rebirth's base price. It closes when
	    you take damage or walk away (CloseRange), like the plaza's contested PvP rule wants.
	  * THE BASE EMPIRE PANEL (the EMPIRE button in the Base panel): each live station's next goal, price and ETA and
	    a PIN button (the one ObjectiveMarker pin: tap-to-pin, no fast travel), with the Empire Level ring.
	Buying: RequestEndgameBuy(kind, id) only; the server checks everything (EndgameService.Purchase).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local EndgameController = {}

local Shared = ReplicatedStorage:WaitForChild("Shared", 60)
if not Shared then
	warn("[WAR EMPIRE] EndgameController: no ReplicatedStorage.Shared after 60 s; not started")
	return EndgameController
end
local Constants = require(Shared.Constants)
local Remotes = require(Shared.Remotes)
local UIUtil = require(Shared.Util.UIUtil)
local TycoonMath = require(Shared.Util.TycoonMath)
local HudConfig = require(Shared.Configs.HudConfig)
local MapConfig = require(Shared.Configs.MapConfig)
local EndgameConfig = require(Shared.Configs.EndgameConfig)
local PlazaServicesConfig = require(Shared.Configs.PlazaServicesConfig)

local PanelShell = require(script.Parent.Parent.Modules.PanelShell)
local ObjectiveMarker = require(script.Parent.Parent.Modules.ObjectiveMarker)

local PSC = PlazaServicesConfig
local player = Players.LocalPlayer

-- ── the station builders (pure: a Model of anchored parts in the house frame; the tests count them) ────────────
local M = Enum.Material
local function put(model: Model, name: string, size: Vector3, cf: CFrame, color: Color3, mat: Enum.Material, collide: boolean?, shape: Enum.PartType?): Part
	local p = Instance.new("Part")
	p.Name = name
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = mat
	p.Anchored = true
	p.CanCollide = collide == true
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	if shape then
		p.Shape = shape
	end
	p.Parent = model
	return p
end

-- a static uniformed figure (feet at f, facing f.LookVector); returns its Head (the prompt's anchor)
local function figure(model: Model, f: CFrame, uniform: Color3, trim: Color3, hat: Color3): Part
	local skin = Color3.fromRGB(196, 150, 118)
	local boots = Color3.fromRGB(38, 34, 30)
	for _, s in ipairs({ -1, 1 }) do
		put(model, "NpcBoot", Vector3.new(0.9, 0.5, 1.2), f * CFrame.new(0.5 * s, 0.25, -0.1), boots, M.SmoothPlastic)
		put(model, "NpcLeg", Vector3.new(0.85, 2.3, 0.85), f * CFrame.new(0.5 * s, 1.65, 0), uniform, M.Fabric)
		put(model, "NpcArm", Vector3.new(0.75, 2.1, 0.75), f * CFrame.new(1.4 * s, 3.8, 0), uniform, M.Fabric)
		put(model, "NpcShoulderBoard", Vector3.new(0.8, 0.12, 0.9), f * CFrame.new(1.2 * s, 4.95, 0), trim, M.Metal)
	end
	put(model, "NpcTorso", Vector3.new(2, 2.1, 1), f * CFrame.new(0, 3.85, 0), uniform, M.Fabric)
	put(model, "NpcBelt", Vector3.new(2.05, 0.3, 1.05), f * CFrame.new(0, 2.95, 0), boots, M.SmoothPlastic)
	local head = put(model, "Head", Vector3.new(1.1, 1.15, 1.1), f * CFrame.new(0, 5.5, 0), skin, M.SmoothPlastic)
	put(model, "NpcBeret", Vector3.new(1.25, 0.35, 1.25), f * CFrame.new(0.05, 6.15, 0.05) * CFrame.Angles(0, 0, math.rad(-8)), hat, M.Fabric)
	return head
end

-- the door sign: one board, one SurfaceGui (MaxDistance 40), facing the street (the house's -Z)
local function doorSign(model: Model, house: CFrame, text: string)
	local board = put(model, "StationSign", Vector3.new(7, 1.0, 0.12), house * CFrame.new(0, 10.05, -8.7 - 0.5), Color3.fromRGB(34, 38, 44), M.Wood)
	local g = Instance.new("SurfaceGui")
	g.Name = "SignGui"
	g.Face = Enum.NormalId.Front
	g.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	g.PixelsPerStud = 40
	g.LightInfluence = 0
	g.MaxDistance = PSC.SignMaxDistance
	g.Parent = board
	local t = Instance.new("TextLabel")
	t.BackgroundTransparency = 1
	t.Size = UDim2.fromScale(1, 1)
	t.Font = Enum.Font.GothamBlack
	t.TextScaled = true
	t.TextColor3 = Color3.fromRGB(255, 210, 90)
	t.Text = text
	t.Parent = g
end

local Builders: { [string]: (house: CFrame, st: any) -> (Model, Part) } = {}

-- the Command Office inside NE_N1 (ground floor: the table, the Chief of Staff, flag stand, cabinet, lamp; upstairs:
-- the Empire board on the left wall). Clear of the door (x -3 .. 3 at the front), the stair (x > 4.2) and the crates.
Builders.Command = function(house: CFrame, st: any): (Model, Part)
	local m = Instance.new("Model")
	m.Name = "Station_Command"
	local wood = Color3.fromRGB(96, 66, 42)
	local steel = Color3.fromRGB(62, 66, 70)
	-- the map table (top collides so you cannot walk through it; nothing answers a ray)
	local tc = house * CFrame.new(-2.5, 0, -1.5)
	put(m, "MapTableTop", Vector3.new(4.6, 0.25, 3), tc * CFrame.new(0, 3.3, 0), wood, M.WoodPlanks, true)
	for _, c in ipairs({ { -2, -1.2 }, { 2, -1.2 }, { -2, 1.2 }, { 2, 1.2 } }) do
		put(m, "MapTableLeg", Vector3.new(0.3, 2.9, 0.3), tc * CFrame.new(c[1], 1.75, c[2]), wood, M.Wood)
	end
	put(m, "MapSheet", Vector3.new(4.2, 0.04, 2.6), tc * CFrame.new(0, 3.445, 0), Color3.fromRGB(176, 170, 128), M.Fabric)
	local markers = {
		{ X = -1.2, Z = -0.5, C = Color3.fromRGB(170, 40, 40) },
		{ X = 0.6, Z = 0.4, C = Color3.fromRGB(40, 70, 170) },
		{ X = 1.4, Z = -0.7, C = Color3.fromRGB(50, 130, 60) },
	}
	for i, mk in ipairs(markers) do
		put(m, "MapMarker" .. i, Vector3.new(0.35, 0.35, 0.35), tc * CFrame.new(mk.X, 3.64, mk.Z), mk.C, M.SmoothPlastic)
	end
	put(m, "Rug", Vector3.new(6, 0.05, 5), house * CFrame.new(-2.5, 0.325, -1), Color3.fromRGB(110, 36, 34), M.Fabric)
	-- the Chief of Staff behind the table, facing the door
	local head = figure(m, house * CFrame.new(st.NpcAt), Color3.fromRGB(74, 84, 58), Color3.fromRGB(214, 176, 72), Color3.fromRGB(120, 28, 30))
	-- a flag stand (a plain command banner: no nation, no insignia) and a filing cabinet
	local fs = house * CFrame.new(-6.6, 0.3, -5.5)
	put(m, "FlagBase", Vector3.new(1.4, 0.3, 1.4), fs * CFrame.new(0, 0.15, 0), steel, M.Metal)
	put(m, "FlagPole", Vector3.new(6, 0.2, 0.2), fs * CFrame.new(0, 3.3, 0) * CFrame.Angles(0, 0, math.rad(90)), Color3.fromRGB(200, 170, 80), M.Metal, false, Enum.PartType.Cylinder)
	put(m, "FlagBanner", Vector3.new(0.08, 2.2, 1.6), fs * CFrame.new(0, 4.8, 0.9), Color3.fromRGB(46, 70, 50), M.Fabric)
	local cab = house * CFrame.new(-7.3, 0.3, -1.8)
	put(m, "Cabinet", Vector3.new(1.2, 3.2, 1.6), cab * CFrame.new(0, 1.6, 0), Color3.fromRGB(88, 96, 90), M.Metal)
	put(m, "CabinetDrawers", Vector3.new(0.06, 2.6, 1.2), cab * CFrame.new(0.63, 1.6, 0), steel, M.Metal)
	-- the ceiling lamp: one PointLight, no shadows
	put(m, "LampRod", Vector3.new(0.15, 1.0, 0.15), house * CFrame.new(-2.5, 10.5, -1.5), steel, M.Metal)
	local shade = put(m, "LampShade", Vector3.new(1.6, 0.5, 1.6), house * CFrame.new(-2.5, 9.8, -1.5), Color3.fromRGB(236, 224, 190), M.SmoothPlastic)
	local light = Instance.new("PointLight")
	light.Range = PSC.LightRange
	light.Brightness = PSC.LightBrightness
	light.Shadows = false
	light.Color = Color3.fromRGB(255, 236, 190)
	light.Parent = shade
	-- upstairs: the Empire board on the left wall (clear of its window at z -1.8 .. 1.8): one plaque per milestone
	local bd = house * CFrame.new(-7.85, 15.2, -5.2)
	put(m, "BoardFrame", Vector3.new(0.2, 3.4, 4.6), bd, wood, M.Wood)
	put(m, "BoardCork", Vector3.new(0.1, 3, 4.2), bd * CFrame.new(0.12, 0, 0), Color3.fromRGB(170, 130, 90), M.Fabric)
	put(m, "BoardTitle", Vector3.new(0.06, 0.45, 3.6), bd * CFrame.new(0.2, 1.15, 0), Color3.fromRGB(120, 28, 30), M.SmoothPlastic)
	for i = 1, 6 do
		local row = (i - 1) // 3
		local col = (i - 1) % 3
		local p = put(m, "Milestone" .. i, Vector3.new(0.06, 0.8, 1.0), bd * CFrame.new(0.2, 0.25 - row * 1.05, -1.25 + col * 1.25), Color3.fromRGB(120, 124, 128), M.Metal)
		p:SetAttribute("WE_Milestone", i * 5)
	end
	doorSign(m, house, st.Sign)
	return m, head
end

-- phase 2: the Engineering Bureau's covered drafting stand in the Office Building's forecourt (the frame's -Z faces
-- away from the building, toward the players): a deck, a canvas canopy on 4 posts with the ENGINEERS valance sign, a
-- tilted drafting table with a blueprint, the Engineer (hard hat), a toolbox, a plan tube, 2 cones, one work lamp.
Builders.Engineers = function(f: CFrame, st: any): (Model, Part)
	local m = Instance.new("Model")
	m.Name = "Station_Engineers"
	local steel = Color3.fromRGB(62, 66, 70)
	local canvas = Color3.fromRGB(196, 168, 110)
	put(m, "StandDeck", Vector3.new(9, 0.3, 6.5), f * CFrame.new(0, 0.15, 1), Color3.fromRGB(150, 120, 80), M.WoodPlanks, true)
	for _, c in ipairs({ { -4.2, -2 }, { 4.2, -2 }, { -4.2, 3.8 }, { 4.2, 3.8 } }) do
		put(m, "CanopyPost", Vector3.new(0.35, 8, 0.35), f * CFrame.new(c[1], 4.3, c[2]), steel, M.Metal)
	end
	put(m, "CanopyRoof", Vector3.new(9.4, 0.2, 6.6), f * CFrame.new(0, 8.4, 0.9) * CFrame.Angles(math.rad(-6), 0, 0), canvas, M.Fabric)
	-- the sign rides on the valance (one SurfaceGui)
	local valance = put(m, "CanopyValance", Vector3.new(9.4, 1.1, 0.12), f * CFrame.new(0, 7.8, -2.35), Color3.fromRGB(34, 38, 44), M.Fabric)
	local g = Instance.new("SurfaceGui")
	g.Name = "SignGui"
	g.Face = Enum.NormalId.Front
	g.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	g.PixelsPerStud = 40
	g.LightInfluence = 0
	g.MaxDistance = PSC.SignMaxDistance
	g.Parent = valance
	local t = Instance.new("TextLabel")
	t.BackgroundTransparency = 1
	t.Size = UDim2.fromScale(1, 1)
	t.Font = Enum.Font.GothamBlack
	t.TextScaled = true
	t.TextColor3 = Color3.fromRGB(255, 210, 90)
	t.Text = st.Sign
	t.Parent = g
	-- the drafting table between the Engineer and the customer
	local tb = f * CFrame.new(0, 0.3, -0.4)
	for _, c in ipairs({ { -1.8, -1.0 }, { 1.8, -1.0 }, { -1.8, 1.0 }, { 1.8, 1.0 } }) do
		put(m, "DraftLeg", Vector3.new(0.2, 3.1, 0.2), tb * CFrame.new(c[1], 1.55, c[2]), steel, M.Metal)
	end
	local top = tb * CFrame.new(0, 3.2, 0) * CFrame.Angles(math.rad(-14), 0, 0)
	put(m, "DraftTop", Vector3.new(4.2, 0.15, 2.6), top, Color3.fromRGB(222, 214, 190), M.Wood, true)
	put(m, "Blueprint", Vector3.new(3.4, 0.03, 2.1), top * CFrame.new(0, 0.09, 0), Color3.fromRGB(46, 86, 160), M.SmoothPlastic)
	put(m, "PlanTube", Vector3.new(2.4, 0.3, 0.3), top * CFrame.new(0, 0.25, -1.05) * CFrame.Angles(0, 0, 0), Color3.fromRGB(120, 90, 60), M.SmoothPlastic, false, Enum.PartType.Cylinder)
	local head = figure(m, f * CFrame.new(st.NpcAt), Color3.fromRGB(70, 80, 96), Color3.fromRGB(230, 150, 40), Color3.fromRGB(240, 196, 40))
	put(m, "Toolbox", Vector3.new(1.6, 0.8, 0.8), f * CFrame.new(3.2, 0.7, 2.6), Color3.fromRGB(170, 40, 40), M.Metal)
	put(m, "ToolboxHandle", Vector3.new(1.0, 0.15, 0.15), f * CFrame.new(3.2, 1.2, 2.6), steel, M.Metal)
	for _, x in ipairs({ -4.8, 4.8 }) do
		put(m, "Cone", Vector3.new(0.7, 1.1, 0.7), f * CFrame.new(x, 0.55, -3.2), Color3.fromRGB(236, 110, 30), M.SmoothPlastic)
	end
	local lamp = put(m, "WorkLamp", Vector3.new(0.8, 0.5, 0.8), f * CFrame.new(0, 7.6, 0.6), Color3.fromRGB(236, 224, 190), M.SmoothPlastic)
	put(m, "WorkLampCord", Vector3.new(0.08, 0.6, 0.08), f * CFrame.new(0, 8.05, 0.6), steel, M.Metal)
	local light = Instance.new("PointLight")
	light.Range = PSC.LightRange
	light.Brightness = PSC.LightBrightness
	light.Shadows = false
	light.Color = Color3.fromRGB(255, 236, 190)
	light.Parent = lamp
	return m, head
end

-- phase 3: the Recruitment Office inside NE_E1 (the cafe): a service counter, lockers on the left wall, the Drill
-- Sergeant behind the counter, a flag stand, a practice-rifle rack at the back, a bench, a rug, a stool, one lamp.
Builders.Recruits = function(house: CFrame, st: any): (Model, Part)
	local m = Instance.new("Model")
	m.Name = "Station_Recruits"
	local wood = Color3.fromRGB(96, 66, 42)
	local steel = Color3.fromRGB(62, 66, 70)
	local olive = Color3.fromRGB(80, 92, 62)
	local cc = house * CFrame.new(-3, 0.3, -1.2)
	put(m, "CounterBody", Vector3.new(6, 3.2, 1.4), cc * CFrame.new(0, 1.6, 0), wood, M.WoodPlanks, true)
	put(m, "CounterTop", Vector3.new(6.4, 0.2, 1.8), cc * CFrame.new(0, 3.3, 0), Color3.fromRGB(200, 196, 186), M.Marble)
	put(m, "CounterKick", Vector3.new(6, 0.4, 0.1), cc * CFrame.new(0, 0.2, -0.75), Color3.fromRGB(40, 36, 30), M.SmoothPlastic)
	put(m, "Clipboard", Vector3.new(0.8, 0.05, 1.0), cc * CFrame.new(-1.6, 3.43, -0.2) * CFrame.Angles(0, math.rad(12), 0), Color3.fromRGB(230, 226, 214), M.SmoothPlastic)
	put(m, "HelmetDisplay", Vector3.new(1.1, 0.6, 1.2), cc * CFrame.new(1.8, 3.7, 0), olive, M.Metal, false, Enum.PartType.Ball)
	for i, z in ipairs({ -4.2, -3.0, -1.8 }) do
		local lk = house * CFrame.new(-7.25, 0.3, z)
		put(m, "Locker", Vector3.new(1.3, 5, 1.15), lk * CFrame.new(0, 2.5, 0), if i == 2 then Color3.fromRGB(70, 84, 64) else olive, M.Metal)
		put(m, "LockerVents", Vector3.new(0.06, 0.8, 0.8), lk * CFrame.new(0.66, 4.1, 0), steel, M.DiamondPlate)
	end
	local head = figure(m, house * CFrame.new(st.NpcAt), Color3.fromRGB(64, 78, 52), Color3.fromRGB(214, 176, 72), Color3.fromRGB(40, 52, 36))
	local fs = house * CFrame.new(-6.6, 0.3, -6.4)
	put(m, "FlagBase", Vector3.new(1.4, 0.3, 1.4), fs * CFrame.new(0, 0.15, 0), steel, M.Metal)
	put(m, "FlagPole", Vector3.new(6, 0.2, 0.2), fs * CFrame.new(0, 3.3, 0) * CFrame.Angles(0, 0, math.rad(90)), Color3.fromRGB(200, 170, 80), M.Metal, false, Enum.PartType.Cylinder)
	put(m, "FlagBanner", Vector3.new(0.08, 2.2, 1.6), fs * CFrame.new(0, 4.8, 0.9), Color3.fromRGB(38, 60, 88), M.Fabric)
	local rk = house * CFrame.new(1.5, 0.3, 7.3)
	put(m, "RackFrame", Vector3.new(3.2, 3.6, 0.4), rk * CFrame.new(0, 1.8, 0), wood, M.Wood)
	for i, x in ipairs({ -0.9, 0, 0.9 }) do
		put(m, "RackRifle" .. i, Vector3.new(0.22, 2.9, 0.28), rk * CFrame.new(x, 1.9, -0.3) * CFrame.Angles(0, 0, math.rad(4)), Color3.fromRGB(34, 34, 36), M.Metal)
	end
	put(m, "BenchSeat", Vector3.new(3.2, 0.25, 1.1), house * CFrame.new(0.5, 1.9, -5.4), wood, M.WoodPlanks)
	put(m, "BenchLegs", Vector3.new(2.8, 1.6, 0.8), house * CFrame.new(0.5, 1.1, -5.4), steel, M.Metal)
	put(m, "Rug", Vector3.new(5, 0.05, 4), house * CFrame.new(-2.5, 0.325, -3.6), Color3.fromRGB(46, 70, 64), M.Fabric)
	put(m, "Stool", Vector3.new(1, 2.2, 1), house * CFrame.new(-0.6, 1.4, 1.4), steel, M.Metal, false, Enum.PartType.Cylinder)
	put(m, "LampRod", Vector3.new(0.15, 1.0, 0.15), house * CFrame.new(-2.5, 10.5, -1.5), steel, M.Metal)
	local shade = put(m, "LampShade", Vector3.new(1.6, 0.5, 1.6), house * CFrame.new(-2.5, 9.8, -1.5), Color3.fromRGB(236, 224, 190), M.SmoothPlastic)
	local light = Instance.new("PointLight")
	light.Range = PSC.LightRange
	light.Brightness = PSC.LightBrightness
	light.Shadows = false
	light.Color = Color3.fromRGB(255, 236, 190)
	light.Parent = shade
	doorSign(m, house, st.Sign)
	return m, head
end

-- phase 4: the Armory Workshop inside SW_S1: a gunsmith's bench (top, legs, a vise, a gun on it), a wall rack of four
-- guns on the left wall, a tool board, the Gunsmith (a leather apron), two ammo crates, a stool, one lamp, the sign.
Builders.Armory = function(house: CFrame, st: any): (Model, Part)
	local m = Instance.new("Model")
	m.Name = "Station_Armory"
	local wood = Color3.fromRGB(96, 66, 42)
	local steel = Color3.fromRGB(62, 66, 70)
	local gun = Color3.fromRGB(34, 34, 36)
	local bc = house * CFrame.new(-2.5, 0.3, -1.3)
	put(m, "BenchTop", Vector3.new(5.6, 0.3, 2.2), bc * CFrame.new(0, 3.2, 0), wood, M.WoodPlanks, true)
	put(m, "BenchLegs", Vector3.new(5.2, 2.9, 0.3), bc * CFrame.new(0, 1.55, 0.8), steel, M.Metal)
	put(m, "BenchLegs", Vector3.new(5.2, 2.9, 0.3), bc * CFrame.new(0, 1.55, -0.8), steel, M.Metal)
	put(m, "Vise", Vector3.new(0.6, 0.6, 0.8), bc * CFrame.new(2.2, 3.65, 0), Color3.fromRGB(40, 90, 150), M.Metal)
	put(m, "BenchGunBody", Vector3.new(2.6, 0.3, 0.25), bc * CFrame.new(-0.4, 3.52, 0.1) * CFrame.Angles(0, math.rad(8), 0), gun, M.Metal)
	put(m, "BenchGunStock", Vector3.new(0.8, 0.45, 0.22), bc * CFrame.new(-1.8, 3.5, 0.3) * CFrame.Angles(0, math.rad(8), 0), wood, M.Wood)
	put(m, "BenchGunMag", Vector3.new(0.25, 0.5, 0.18), bc * CFrame.new(-0.2, 3.25, 0.12), gun, M.Metal)
	local rk = house * CFrame.new(-7.6, 0.3, -3.2) * CFrame.Angles(0, math.rad(90), 0)
	put(m, "WallRack", Vector3.new(4.4, 4.2, 0.3), rk * CFrame.new(0, 3.2, 0), wood, M.Wood)
	put(m, "WallRackRail", Vector3.new(4.4, 0.2, 0.5), rk * CFrame.new(0, 1.3, -0.25), steel, M.Metal)
	for i, x in ipairs({ -1.5, -0.5, 0.5, 1.5 }) do
		put(m, "RackGun" .. i, Vector3.new(0.24, 3.2, 0.3), rk * CFrame.new(x, 3.0, -0.3) * CFrame.Angles(0, 0, math.rad(3)), gun, M.Metal)
		put(m, "RackGunStock" .. i, Vector3.new(0.34, 0.7, 0.3), rk * CFrame.new(x, 1.7, -0.3), wood, M.Wood)
	end
	put(m, "ToolBoard", Vector3.new(3.4, 2.2, 0.15), house * CFrame.new(-2.5, 5.6, 7.75), Color3.fromRGB(150, 124, 90), M.Wood)
	for i, x in ipairs({ -1, 0, 1 }) do
		put(m, "Tool" .. i, Vector3.new(0.15, 1.2 - i * 0.15, 0.1), house * CFrame.new(-2.5 + x, 5.5, 7.65), steel, M.Metal)
	end
	local head = figure(m, house * CFrame.new(st.NpcAt), Color3.fromRGB(88, 70, 52), Color3.fromRGB(150, 110, 70), Color3.fromRGB(56, 48, 40))
	put(m, "Apron", Vector3.new(2.05, 2.6, 0.12), house * CFrame.new(st.NpcAt) * CFrame.new(0, 3.2, -0.55), Color3.fromRGB(110, 76, 48), M.Fabric)
	for i, c in ipairs({ { 1.4, 5.4 }, { 1.4, 3.9 } }) do
		put(m, "AmmoCrate" .. i, Vector3.new(1.8, 1.1, 1.2), house * CFrame.new(c[1], 0.85 + (i - 1) * 0, c[2]), Color3.fromRGB(86, 96, 60), M.Wood)
	end
	put(m, "LampRod", Vector3.new(0.15, 1.0, 0.15), house * CFrame.new(-2.5, 10.5, -1.5), steel, M.Metal)
	local shade = put(m, "LampShade", Vector3.new(1.6, 0.5, 1.6), house * CFrame.new(-2.5, 9.8, -1.5), Color3.fromRGB(236, 224, 190), M.SmoothPlastic)
	local light = Instance.new("PointLight")
	light.Range = PSC.LightRange
	light.Brightness = PSC.LightBrightness
	light.Shadows = false
	light.Color = Color3.fromRGB(255, 236, 190)
	light.Parent = shade
	doorSign(m, house, st.Sign)
	return m, head
end

-- phase 4: the Field Hospital stand in the Hospital's forecourt (the frame's -Z faces the players): a deck, a canvas
-- canopy on 4 posts with the HOSPITAL valance sign, a white plus on a green board, the reception desk, the Field Medic,
-- two stretcher beds, an IV stand, a med crate, one lamp.
Builders.Hospital = function(f: CFrame, st: any): (Model, Part)
	local m = Instance.new("Model")
	m.Name = "Station_Hospital"
	local steel = Color3.fromRGB(150, 156, 160)
	local green = Color3.fromRGB(40, 110, 70)
	put(m, "StandDeck", Vector3.new(11, 0.3, 8), f * CFrame.new(0, 0.15, 1.8), Color3.fromRGB(170, 170, 164), M.Concrete, true)
	for _, c in ipairs({ { -5.2, -2 }, { 5.2, -2 }, { -5.2, 5.6 }, { 5.2, 5.6 } }) do
		put(m, "CanopyPost", Vector3.new(0.35, 8, 0.35), f * CFrame.new(c[1], 4.3, c[2]), steel, M.Metal)
	end
	put(m, "CanopyRoof", Vector3.new(11.4, 0.2, 8.2), f * CFrame.new(0, 8.4, 1.8) * CFrame.Angles(math.rad(-5), 0, 0), Color3.fromRGB(230, 232, 226), M.Fabric)
	local valance = put(m, "CanopyValance", Vector3.new(11.4, 1.1, 0.12), f * CFrame.new(0, 7.8, -2.35), green, M.Fabric)
	local g = Instance.new("SurfaceGui")
	g.Name = "SignGui"
	g.Face = Enum.NormalId.Front
	g.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	g.PixelsPerStud = 40
	g.LightInfluence = 0
	g.MaxDistance = PSC.SignMaxDistance
	g.Parent = valance
	local t = Instance.new("TextLabel")
	t.BackgroundTransparency = 1
	t.Size = UDim2.fromScale(1, 1)
	t.Font = Enum.Font.GothamBlack
	t.TextScaled = true
	t.TextColor3 = Color3.fromRGB(255, 255, 255)
	t.Text = st.Sign
	t.Parent = g
	-- the plus board (white on green) beside the desk
	put(m, "PlusBoard", Vector3.new(2.6, 2.6, 0.2), f * CFrame.new(4.2, 5.4, 5.4), green, M.SmoothPlastic)
	put(m, "PlusBar", Vector3.new(1.8, 0.5, 0.06), f * CFrame.new(4.2, 5.4, 5.28), Color3.fromRGB(255, 255, 255), M.SmoothPlastic)
	put(m, "PlusBar", Vector3.new(0.5, 1.8, 0.06), f * CFrame.new(4.2, 5.4, 5.28), Color3.fromRGB(255, 255, 255), M.SmoothPlastic)
	-- the reception desk between the medic and the players
	put(m, "DeskBody", Vector3.new(4.6, 3.1, 1.2), f * CFrame.new(0, 1.85, -0.3), Color3.fromRGB(220, 222, 218), M.SmoothPlastic, true)
	put(m, "DeskTop", Vector3.new(5, 0.2, 1.6), f * CFrame.new(0, 3.5, -0.3), Color3.fromRGB(120, 124, 128), M.Metal)
	put(m, "DeskStripe", Vector3.new(4.62, 0.35, 0.05), f * CFrame.new(0, 2.4, -0.93), green, M.SmoothPlastic)
	put(m, "MedCase", Vector3.new(1.2, 0.6, 0.8), f * CFrame.new(-1.4, 3.9, -0.3), Color3.fromRGB(240, 240, 236), M.SmoothPlastic)
	local head = figure(m, f * CFrame.new(st.NpcAt), Color3.fromRGB(226, 228, 224), green, green)
	-- two stretcher beds and an IV stand on the deck
	for i, x in ipairs({ -3.6, 3.6 }) do
		local b = f * CFrame.new(x, 0.3, 3.6)
		put(m, "BedFrame" .. i, Vector3.new(2.4, 1.6, 5.4), b * CFrame.new(0, 0.8, 0), steel, M.Metal)
		put(m, "BedMattress" .. i, Vector3.new(2.2, 0.4, 5.2), b * CFrame.new(0, 1.8, 0), Color3.fromRGB(80, 120, 96), M.Fabric)
		put(m, "BedPillow" .. i, Vector3.new(1.6, 0.35, 0.9), b * CFrame.new(0, 2.15, 2.0), Color3.fromRGB(240, 240, 236), M.Fabric)
	end
	put(m, "IVPole", Vector3.new(0.12, 5.4, 0.12), f * CFrame.new(-1.8, 3.0, 5.6), steel, M.Metal)
	put(m, "IVBag", Vector3.new(0.5, 0.8, 0.2), f * CFrame.new(-1.8, 5.3, 5.5), Color3.fromRGB(200, 226, 236), M.Glass)
	put(m, "MedCrate", Vector3.new(1.6, 1.0, 1.2), f * CFrame.new(1.6, 0.8, 6.2), Color3.fromRGB(240, 240, 236), M.SmoothPlastic)
	put(m, "MedCrateBand", Vector3.new(1.62, 0.3, 1.22), f * CFrame.new(1.6, 0.8, 6.2), green, M.SmoothPlastic)
	local lamp = put(m, "WorkLamp", Vector3.new(0.8, 0.5, 0.8), f * CFrame.new(0, 7.6, 1.6), Color3.fromRGB(236, 236, 230), M.SmoothPlastic)
	local light = Instance.new("PointLight")
	light.Range = PSC.LightRange
	light.Brightness = PSC.LightBrightness
	light.Shadows = false
	light.Color = Color3.fromRGB(240, 246, 255)
	light.Parent = lamp
	return m, head
end

-- phase 5: the Intel Office inside NW_W1 (the radio shop): a radio desk with a set, a handset and an antenna, a map wall
-- with pins, the Signals Officer, a chair, a filing cabinet, one lamp, the INTEL sign.
Builders.Intel = function(house: CFrame, st: any): (Model, Part)
	local m = Instance.new("Model")
	m.Name = "Station_Intel"
	local wood = Color3.fromRGB(96, 66, 42)
	local steel = Color3.fromRGB(62, 66, 70)
	local dc = house * CFrame.new(-2.5, 0.3, -1.3)
	put(m, "DeskTop", Vector3.new(4.8, 0.25, 2.2), dc * CFrame.new(0, 3.1, 0), wood, M.WoodPlanks, true)
	put(m, "DeskPedestal", Vector3.new(1.4, 2.9, 2), dc * CFrame.new(-1.6, 1.5, 0), wood, M.Wood)
	put(m, "DeskPedestal", Vector3.new(1.4, 2.9, 2), dc * CFrame.new(1.6, 1.5, 0), wood, M.Wood)
	put(m, "RadioSet", Vector3.new(1.8, 1.0, 1.0), dc * CFrame.new(-0.6, 3.72, 0.3), Color3.fromRGB(72, 80, 60), M.Metal)
	put(m, "RadioDial", Vector3.new(0.4, 0.4, 0.06), dc * CFrame.new(-1.0, 3.8, -0.22), Color3.fromRGB(220, 200, 120), M.SmoothPlastic)
	put(m, "RadioAntenna", Vector3.new(0.08, 1.6, 0.08), dc * CFrame.new(0.1, 4.95, 0.5), steel, M.Metal)
	put(m, "Handset", Vector3.new(0.9, 0.25, 0.3), dc * CFrame.new(0.9, 3.35, -0.2), Color3.fromRGB(30, 30, 32), M.SmoothPlastic)
	put(m, "Logbook", Vector3.new(0.9, 0.08, 1.2), dc * CFrame.new(1.6, 3.27, 0.2), Color3.fromRGB(150, 40, 36), M.SmoothPlastic)
	local head = figure(m, house * CFrame.new(st.NpcAt), Color3.fromRGB(64, 72, 88), Color3.fromRGB(214, 176, 72), Color3.fromRGB(34, 40, 56))
	-- the map wall on the back wall (clear of the back window upstairs; the ground floor back wall has none)
	local mw = house * CFrame.new(-3, 4.6, 7.75)
	put(m, "MapWallFrame", Vector3.new(6.4, 3.8, 0.2), mw, wood, M.Wood)
	put(m, "MapWall", Vector3.new(6, 3.4, 0.08), mw * CFrame.new(0, 0, -0.12), Color3.fromRGB(176, 170, 128), M.Fabric)
	for i, c in ipairs({ { -2, 0.8 }, { -0.6, -0.4 }, { 0.8, 1.0 }, { 2.1, -0.9 }, { 1.2, 0.1 }, { -1.5, -1.1 } }) do
		put(m, "MapPin" .. i, Vector3.new(0.22, 0.22, 0.22), mw * CFrame.new(c[1], c[2], -0.2), if i % 2 == 0 then Color3.fromRGB(170, 40, 40) else Color3.fromRGB(40, 70, 170), M.SmoothPlastic, false, Enum.PartType.Ball)
	end
	put(m, "MapString", Vector3.new(2.6, 0.05, 0.05), mw * CFrame.new(-0.7, 0.2, -0.2) * CFrame.Angles(0, 0, math.rad(35)), Color3.fromRGB(200, 40, 40), M.Fabric)
	put(m, "ChairSeat", Vector3.new(1.4, 0.25, 1.4), house * CFrame.new(-2.5, 1.9, 2.4), wood, M.Wood)
	put(m, "ChairBack", Vector3.new(1.4, 1.6, 0.2), house * CFrame.new(-2.5, 2.8, 3.1), wood, M.Wood)
	put(m, "ChairLegs", Vector3.new(1.2, 1.6, 1.2), house * CFrame.new(-2.5, 1.0, 2.4), steel, M.Metal)
	local cab = house * CFrame.new(-7.3, 0.3, -1.8)
	put(m, "Cabinet", Vector3.new(1.2, 3.2, 1.6), cab * CFrame.new(0, 1.6, 0), Color3.fromRGB(88, 96, 90), M.Metal)
	put(m, "CabinetDrawers", Vector3.new(0.06, 2.6, 1.2), cab * CFrame.new(0.63, 1.6, 0), steel, M.Metal)
	put(m, "LampRod", Vector3.new(0.15, 1.0, 0.15), house * CFrame.new(-2.5, 10.5, -1.5), steel, M.Metal)
	local shade = put(m, "LampShade", Vector3.new(1.6, 0.5, 1.6), house * CFrame.new(-2.5, 9.8, -1.5), Color3.fromRGB(236, 224, 190), M.SmoothPlastic)
	local light = Instance.new("PointLight")
	light.Range = PSC.LightRange
	light.Brightness = PSC.LightBrightness
	light.Shadows = false
	light.Color = Color3.fromRGB(255, 236, 190)
	light.Parent = shade
	doorSign(m, house, st.Sign)
	return m, head
end

-- phase 5: the Black Market on SW_S1's upper floor: a counter of crates, the Trader behind it facing the stair, a
-- covered rack, a hanging lamp (no second light: the Armory's is downstairs; this one is a dim unlit lantern), a board.
Builders.BlackMarket = function(house: CFrame, st: any): (Model, Part)
	local m = Instance.new("Model")
	m.Name = "Station_BlackMarket"
	local crate = Color3.fromRGB(110, 86, 58)
	local dark = Color3.fromRGB(34, 34, 36)
	local up = house * CFrame.new(0, 11.4, 0)
	for i, x in ipairs({ -0.9, 0.9, 2.7 }) do
		put(m, "CounterCrate" .. i, Vector3.new(1.8, 2.8, 1.6), up * CFrame.new(x - 0.4, 1.4, -3.9) * CFrame.Angles(0, math.rad(i * 3), 0), crate, M.WoodPlanks, true)
	end
	put(m, "CounterCloth", Vector3.new(5.6, 0.08, 1.8), up * CFrame.new(0.5, 2.85, -3.9), Color3.fromRGB(60, 24, 30), M.Fabric)
	put(m, "Lockbox", Vector3.new(0.9, 0.5, 0.6), up * CFrame.new(1.4, 3.15, -3.8), dark, M.Metal)
	put(m, "Pouch", Vector3.new(0.6, 0.4, 0.6), up * CFrame.new(-0.6, 3.1, -3.7), Color3.fromRGB(150, 120, 60), M.Fabric, false, Enum.PartType.Ball)
	-- the Trader faces +Z (the stair arrives at the back of the room)
	local head = figure(m, house * CFrame.new(st.NpcAt) * CFrame.Angles(0, math.pi, 0), Color3.fromRGB(46, 42, 40), Color3.fromRGB(120, 90, 60), Color3.fromRGB(28, 26, 24))
	put(m, "RackTarp", Vector3.new(0.2, 3.6, 3.4), up * CFrame.new(-7.6, 1.9, -5.4), Color3.fromRGB(70, 80, 60), M.Fabric)
	put(m, "RackPole", Vector3.new(0.15, 4, 0.15), up * CFrame.new(-7.4, 2, -3.6), dark, M.Metal)
	put(m, "Lantern", Vector3.new(0.6, 0.9, 0.6), up * CFrame.new(0.5, 8.6, -5), Color3.fromRGB(200, 170, 110), M.Glass)
	put(m, "LanternChain", Vector3.new(0.06, 1.8, 0.06), up * CFrame.new(0.5, 9.9, -5), dark, M.Metal)
	-- the board behind the Trader (one SurfaceGui, MaxDistance 40)
	local board = put(m, "MarketBoard", Vector3.new(4.2, 1.2, 0.15), up * CFrame.new(0.5, 6.4, -7.7), dark, M.Wood)
	local g = Instance.new("SurfaceGui")
	g.Name = "SignGui"
	g.Face = Enum.NormalId.Back
	g.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	g.PixelsPerStud = 40
	g.LightInfluence = 0
	g.MaxDistance = PSC.SignMaxDistance
	g.Parent = board
	local t = Instance.new("TextLabel")
	t.BackgroundTransparency = 1
	t.Size = UDim2.fromScale(1, 1)
	t.Font = Enum.Font.GothamBlack
	t.TextScaled = true
	t.TextColor3 = Color3.fromRGB(255, 210, 90)
	t.Text = st.Sign
	t.Parent = g
	-- v157: the Black Market is live for everyone; while the Armory downstairs is not (its ARMORY sign is the
	-- building's), the door carries a BLACK MARKET sign so a player can find the stall (1 part, 1 SurfaceGui)
	if not EndgameConfig.LiveFor(player.UserId, "Mastery") then
		doorSign(m, house, st.Sign)
	end
	return m, head
end

-- phase 5: the Fixer's side desk in the bank hall: a desk, a briefcase, a blueprint roll, two cash stacks, a floor
-- safe, the Fixer (a dark suit), a small HEIST board (one SurfaceGui). No light (the hall is lit).
Builders.Heist = function(f: CFrame, st: any): (Model, Part)
	local m = Instance.new("Model")
	m.Name = "Station_Heist"
	local wood = Color3.fromRGB(70, 46, 32)
	local dark = Color3.fromRGB(30, 30, 32)
	local dc = f * CFrame.new(0, 0, -0.4)
	put(m, "DeskTop", Vector3.new(3.6, 0.2, 1.8), dc * CFrame.new(0, 3.1, 0), wood, M.WoodPlanks, true)
	put(m, "DeskPedestal", Vector3.new(1.0, 3.0, 1.6), dc * CFrame.new(-1.2, 1.5, 0), wood, M.Wood)
	put(m, "DeskPedestal", Vector3.new(1.0, 3.0, 1.6), dc * CFrame.new(1.2, 1.5, 0), wood, M.Wood)
	put(m, "Briefcase", Vector3.new(1.4, 0.35, 1.0), dc * CFrame.new(-0.8, 3.38, 0.1) * CFrame.Angles(0, math.rad(10), 0), dark, M.SmoothPlastic)
	put(m, "BriefcaseHandle", Vector3.new(0.5, 0.12, 0.12), dc * CFrame.new(-0.8, 3.6, -0.35), Color3.fromRGB(150, 130, 90), M.Metal)
	put(m, "BlueprintRoll", Vector3.new(1.6, 0.25, 0.25), dc * CFrame.new(0.9, 3.33, 0.3) * CFrame.Angles(0, math.rad(-20), 0), Color3.fromRGB(46, 86, 160), M.SmoothPlastic, false, Enum.PartType.Cylinder)
	for i, x in ipairs({ 0.3, 0.55 }) do
		put(m, "CashStack" .. i, Vector3.new(0.6, 0.18 * i, 0.3), dc * CFrame.new(x, 3.2 + 0.09 * i, -0.4), Color3.fromRGB(110, 150, 90), M.SmoothPlastic)
	end
	local sf = f * CFrame.new(1.9, 0, 0.9)
	put(m, "SafeBody", Vector3.new(1.6, 1.8, 1.4), sf * CFrame.new(0, 0.9, 0), Color3.fromRGB(60, 64, 66), M.Metal)
	put(m, "SafeDoor", Vector3.new(1.2, 1.4, 0.08), sf * CFrame.new(0, 0.9, -0.74), Color3.fromRGB(80, 84, 86), M.Metal)
	put(m, "SafeDial", Vector3.new(0.1, 0.4, 0.4), sf * CFrame.new(0, 1.0, -0.8) * CFrame.Angles(0, math.rad(90), 0), Color3.fromRGB(200, 180, 110), M.Metal, false, Enum.PartType.Cylinder)
	local head = figure(m, f * CFrame.new(st.NpcAt), Color3.fromRGB(34, 34, 40), Color3.fromRGB(120, 120, 128), Color3.fromRGB(24, 24, 28))
	local board = put(m, "HeistBoard", Vector3.new(2.6, 0.8, 0.1), f * CFrame.new(0, 6.4, 2.4), dark, M.Wood)
	local g = Instance.new("SurfaceGui")
	g.Name = "SignGui"
	g.Face = Enum.NormalId.Front
	g.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	g.PixelsPerStud = 40
	g.LightInfluence = 0
	g.MaxDistance = PSC.SignMaxDistance
	g.Parent = board
	local t = Instance.new("TextLabel")
	t.BackgroundTransparency = 1
	t.Size = UDim2.fromScale(1, 1)
	t.Font = Enum.Font.GothamBlack
	t.TextScaled = true
	t.TextColor3 = Color3.fromRGB(255, 210, 90)
	t.Text = st.Sign
	t.Parent = g
	return m, head
end

function EndgameController.BuildStation(kind: string, house: CFrame): (Model?, Part?)
	local st = PSC.Stations[kind]
	local b = Builders[kind]
	if st == nil or b == nil then
		return nil, nil
	end
	local m, head = b(house, st)
	m.ModelStreamingMode = Enum.ModelStreamingMode.Atomic
	return m, head
end

-- ── state + panels ───────────────────────────────────────────────────────────────────────────────────────────
local state: { [string]: any } = {}
local built: { [string]: any } = {} -- station kind -> the local Model
local stationOpen: string? = nil
local stationPanel: Frame? = nil
local empirePanel: Frame? = nil
local empireOpen = false
local stationShell: PanelShell.Shell? = nil
local empireShell: PanelShell.Shell? = nil
local L: { [string]: TextLabel } = {}
local buyBtn: TextButton? = nil
local empireRows: Frame? = nil
local ringLabel: TextLabel? = nil
-- phase 2: the LIST station panel (one layout for every multi-item station: Engineers, the HQ console, later phases)
local listOpen: string? = nil
local listPanel: Frame? = nil
local listRows: Frame? = nil
local listTitle: TextLabel? = nil
local listSub: TextLabel? = nil
local listShell: PanelShell.Shell? = nil
local hqConsole: BasePart? = nil
local LIST_TITLES = { Engineers = "ENGINEERING BUREAU", HQ = "HQ UPGRADE", Recruits = "RECRUITMENT OFFICE", Hospital = "FIELD HOSPITAL", Armory = "ARMORY WORKSHOP", Workshop = "VEHICLE WORKSHOP", Intel = "INTEL OFFICE", BlackMarket = "BLACK MARKET", Heist = "THE FIXER" }
local depotConsole: BasePart? = nil

local function short(n: number): string
	if n >= 1e9 then
		return string.format("$%.2fB", n / 1e9)
	elseif n >= 1e6 then
		return string.format("$%.1fM", n / 1e6)
	elseif n >= 1e3 then
		return string.format("$%.0fK", n / 1e3)
	end
	return "$" .. tostring(math.floor(n))
end

-- "Ready" or "ready in 12:05" for a price, from the wallet and the steady income (display only)
function EndgameController.EtaText(cost: number, cash: number, perSec: number): string
	if cash >= cost then
		return "Ready"
	end
	if perSec <= 0 then
		return "Earn " .. short(cost - cash) .. " more"
	end
	return "ready in " .. TycoonMath.FormatEta((cost - cash) / perSec)
end

local function wallet(): (number, number)
	return tonumber(player:GetAttribute("WE_Cash")) or 0, tonumber(player:GetAttribute("WE_IncomePerSec")) or 0
end

local function refreshBoards()
	local e = state.Empire
	local lvl = if typeof(e) == "table" then (tonumber(e.Level) or 0) else 0
	local m = built.Command
	if m then
		for i = 1, 6 do
			local p = m:FindFirstChild("Milestone" .. i)
			if p and p:IsA("BasePart") then
				p.Color = if lvl >= i * 5 then Color3.fromRGB(230, 190, 60) else Color3.fromRGB(120, 124, 128)
			end
		end
	end
end

local function refreshStation()
	local kind = stationOpen
	if kind == nil or stationPanel == nil then
		return
	end
	local cash, perSec = wallet()
	if kind == "Command" then
		local e = state.Empire
		if typeof(e) ~= "table" then
			L.Level.Text = "Loading..."
			return
		end
		L.Level.Text = string.format("EMPIRE %d", e.Level)
		L.Pct.Text = string.format("+%d%% cash on all income", e.Pct)
		local btn = buyBtn :: TextButton
		if typeof(e.NextCost) == "number" then
			L.Next.Text = string.format("NEXT  EMPIRE %d  +%d%% cash", e.Level + 1, e.NextPct)
			L.Price.Text = "$" .. TycoonMath.Commas(e.NextCost)
			L.Eta.Text = EndgameController.EtaText(e.NextCost, cash, perSec)
			btn.Visible = true
			local can = cash >= e.NextCost
			btn.Text = if can then "BUY" else "NEED " .. short(e.NextCost - cash)
			btn.BackgroundColor3 = if can then Color3.fromRGB(46, 170, 82) else Color3.fromRGB(70, 76, 84)
			btn.AutoButtonColor = can
		else
			L.Next.Text = "EMPIRE LEVEL MAXED"
			L.Price.Text = ""
			L.Eta.Text = "Empire Marshal"
			btn.Visible = false
		end
		local foot = "Kept through rebirth"
		if typeof(e.Milestone) == "string" then
			foot = string.format("Level %d: %s", e.Level + 1, e.Milestone)
		end
		L.Foot.Text = foot
		local r = state.Rebirth
		L.Foot2.Text = if typeof(r) == "table" and typeof(r.NextBase) == "number" then "Next rebirth base: " .. short(r.NextBase) else ""
	end
end

local function stationPoint(kind: string): Vector3?
	if kind == "HQ" then
		local c = hqConsole
		return if c and c.Parent then c.Position else nil
	end
	if kind == "Workshop" then
		local c = depotConsole
		return if c and c.Parent then c.Position else nil
	end
	local pts = state.Stations
	local p = if typeof(pts) == "table" then pts[kind] else nil
	if typeof(p) ~= "table" then
		return nil
	end
	return Vector3.new(p.X, p.Y, p.Z)
end

-- ── Code Bot v171: the SCOUT REPORT result card (Shaun 2026-10-01 12:08: "the scout report I paid for did nothing") ──
-- The purchase worked, but its only output was a 1.8 s toast and one grey INFO row 5th in the Intel list (under the
-- three contracts and the weekly target), lost on a server move. Now the server pushes "ScoutReport" right after the
-- buy and this card shows every number until he closes it; the report also leads the Intel list (VIEW reopens it).
function EndgameController.ScoutLines(rep: { [string]: any }): { [string]: string }
	local function n(v: any): string
		local x = tonumber(v)
		return if x then tostring(math.floor(x)) else "?"
	end
	local gate = if tonumber(rep.GateHp) then (if tonumber(rep.GateMax) then n(rep.GateHp) .. " / " .. n(rep.GateMax) else n(rep.GateHp)) .. " HP" else "unknown"
	local def = {}
	local d = rep.Defence
	if typeof(d) == "table" then
		for _, tr in ipairs(EndgameConfig.Defence.Tracks) do
			table.insert(def, string.format("%s %s", tr, n(d[tr] or 0)))
		end
	end
	local ago = math.max(0, math.floor((os.time() - (tonumber(rep.At) or os.time())) / 60))
	return {
		Title = "SCOUT REPORT: " .. string.upper(tostring(rep.Name or "?")),
		Line1 = string.format("Base tier %s · gate %s", n(rep.Tier or 0), gate),
		Line2 = string.format("%s turrets online · %s guards", n(rep.Turrets or 0), n(rep.Guards or 0)),
		Line3 = if #def > 0 then "Defences: " .. table.concat(def, ", ") else "Defences: none bought",
		Line4 = if typeof(rep.Verdict) == "string" and rep.Verdict ~= "" then "Your army: " .. rep.Verdict else "Your army: no verdict (no soldiers?)",
		Line5 = if ago < 1 then "Scouted just now" else string.format("Scouted %d min ago", ago),
	}
end

local scoutGui: ScreenGui? = nil
function EndgameController.ShowScoutCard(rep: { [string]: any })
	local pg = player:FindFirstChildOfClass("PlayerGui")
	if pg == nil or typeof(rep) ~= "table" then
		return
	end
	local old = scoutGui
	if old then
		old:Destroy()
	end
	local L = EndgameController.ScoutLines(rep)
	local sg = Instance.new("ScreenGui")
	sg.Name = "WE_ScoutReport"
	sg.ResetOnSpawn = false
	PanelShell.Screen(sg, HudConfig.DisplayOrder.Panels + 2) -- over the Intel list (60), under the toasts (70)
	sg.Parent = pg
	scoutGui = sg
	local TAP = PanelShell.TouchMinV()
	local f = Instance.new("Frame")
	f.Name = "Card"
	f.AnchorPoint = Vector2.new(0.5, 0.5)
	f.Position = UDim2.fromScale(0.5, 0.5)
	f.Size = UDim2.fromOffset(520, 300 + TAP)
	f.BackgroundColor3 = Color3.fromRGB(18, 20, 16)
	f.BorderSizePixel = 0
	f.Parent = sg
	UIUtil.Corner(f, 14)
	local st = Instance.new("UIStroke")
	st.Color = Constants.Colors.GoldBright
	st.Thickness = 2
	st.Parent = f
	local function line(text: string, y: number, size: number, color: Color3, font: Enum.Font)
		local l = Instance.new("TextLabel")
		l.BackgroundTransparency = 1
		l.Position = UDim2.fromOffset(20, y)
		l.Size = UDim2.new(1, -40, 0, size + 10)
		l.Font = font
		l.TextSize = PanelShell.Text(size)
		l.TextColor3 = color
		l.TextXAlignment = Enum.TextXAlignment.Left
		l.TextWrapped = true
		l.Text = text
		l.Parent = f
	end
	line(L.Title, 14, 24, Constants.Colors.GoldBright, HudConfig.Fonts.Display)
	line(L.Line1, 64, 20, Color3.fromRGB(255, 255, 255), Enum.Font.GothamBold)
	line(L.Line2, 102, 20, Color3.fromRGB(255, 255, 255), Enum.Font.GothamBold)
	line(L.Line3, 140, 18, Color3.fromRGB(225, 225, 215), Enum.Font.GothamMedium)
	line(L.Line4, 176, 18, Color3.fromRGB(150, 235, 120), Enum.Font.GothamBold)
	line(L.Line5, 212, 16, Color3.fromRGB(200, 200, 190), Enum.Font.GothamMedium)
	local b = Instance.new("TextButton")
	b.Name = "Close"
	b.AnchorPoint = Vector2.new(0.5, 1)
	b.Position = UDim2.new(0.5, 0, 1, -14)
	b.Size = UDim2.fromOffset(200, TAP)
	b.BackgroundColor3 = Color3.fromRGB(46, 170, 82)
	b.Font = HudConfig.Fonts.Display
	b.TextSize = PanelShell.Text(18)
	b.TextColor3 = Color3.fromRGB(255, 255, 255)
	b.Text = "GOT IT"
	b.Parent = f
	UIUtil.Corner(b, 8)
	b.Activated:Connect(function()
		sg:Destroy()
		if scoutGui == sg then
			scoutGui = nil
		end
	end)
end

type Row = { Name: string, Sub: string, Price: number?, Need: string?, Kind: string, Id: string, Done: string?, Gold: boolean?, Label: string? }

-- the rows a list station shows (from the server's EndgameState; display only)
function EndgameController.ListRows(kind: string, s: { [string]: any }): { Row }
	local out: { Row } = {}
	if kind == "Engineers" and typeof(s.Defence) == "table" then
		for _, r in ipairs(s.Defence) do
			table.insert(out, {
				Name = string.format("%s  L%d/%d", r.Name, r.Level, r.Max),
				Sub = if r.Next then "Next: " .. r.Next else "Now: " .. tostring(r.Now),
				Price = r.NextCost,
				Need = r.Need,
				Kind = "Defence",
				Id = r.Id,
				Done = if r.NextCost == nil then "MAX" else nil,
			})
		end
	elseif kind == "Recruits" and typeof(s.Elite) == "table" then
		for _, r in ipairs(s.Elite) do
			table.insert(out, {
				Name = string.format("%s  %s", string.upper(r.Name), string.upper(r.TierName)),
				Sub = if r.NextName then string.format("+%d%% HP / damage. Next: %s", r.Pct, string.upper(r.NextName)) else string.format("+%d%% HP / damage", r.Pct),
				Price = r.NextCost,
				Need = r.Need,
				Kind = "Elite",
				Id = r.Id,
				Done = if r.NextCost == nil then "MAX" else nil,
			})
		end
		local rt = s.Retrain
		if typeof(rt) == "table" and (tonumber(rt.Count) or 0) > 0 then
			table.insert(out, {
				Name = string.format("RE-TRAIN %d SOLDIER(S)", rt.Count),
				Sub = "They came back untrained",
				Price = rt.Price,
				Need = nil,
				Kind = "Retrain",
				Id = "Now",
				Done = nil,
			})
		end
	elseif kind == "Armory" and typeof(s.Armory) == "table" then
		local a = s.Armory
		local eq = a.Equipped
		for _, g in ipairs(a.Guns or {}) do
			table.insert(out, {
				Name = string.format("%s  MASTERY %d/%d", string.upper(g.Name), g.Mastery, g.Max),
				Sub = "+3% damage, +2% rate, +4% range a level",
				Price = g.NextCost, Need = nil, Kind = "Mastery", Id = g.Id,
				Done = if g.NextCost == nil then "MAX" else nil,
			})
		end
		if typeof(eq) == "string" then
			for _, at in ipairs(a.Attach or {}) do
				table.insert(out, {
					Name = string.format("%s (your %s)", string.upper(at.Name), eq),
					Sub = if at.Id == "RedDot" then "+10% range" elseif at.Id == "Grip" then "-15% spread" elseif at.Id == "ExtendedMag" then "+25% magazine" else "Coming soon",
					Price = if at.Owned or at.Soon then nil else at.Cost, Need = nil, Kind = "Attach", Id = eq .. ":" .. at.Id,
					Done = if at.Owned then "FITTED" elseif at.Soon then "SOON" else nil,
				})
			end
			for _, cm in ipairs(a.Camos or {}) do
				if cm.Owned then
					table.insert(out, {
						Name = string.format("%s CAMO", string.upper(cm.Id)), Sub = if cm.On then "On your gun" else "Owned", Price = 0, Need = nil,
						Kind = "EquipCamo", Id = eq .. ":" .. (if cm.On then "None" else cm.Id), Label = if cm.On then "TAKE OFF" else "PUT ON",
					})
				else
					table.insert(out, {
						Name = string.format("%s CAMO", string.upper(cm.Id)), Sub = string.format("%d Gold  (you have %d)", cm.Gold, a.Gold or 0), Price = cm.Gold, Need = nil,
						Kind = "Camo", Id = eq .. ":" .. cm.Id, Gold = true,
					})
				end
			end
		end
	elseif kind == "Intel" and typeof(s.Intel) == "table" then
		local it = s.Intel
		-- Code Bot v171: the paid scouting report leads the list (it sat 5th, under the contracts, as a grey INFO row);
		-- VIEW opens the result card again
		local rep = it.Report
		if typeof(rep) == "table" then
			local L = EndgameController.ScoutLines(rep)
			table.insert(out, {
				Name = L.Title, Sub = L.Line1 .. ". " .. L.Line2,
				Price = 0, Need = nil, Kind = "ScoutView", Id = "Report", Label = "VIEW",
			})
		end
		for i, r in ipairs(it.Rows or {}) do
			local done = r.Have >= r.Need
			table.insert(out, {
				Name = string.upper(r.Text), Sub = string.format("%d/%d  reward %s", r.Have, r.Need, short(it.Reward or 0)),
				Price = if done and not r.Paid then 0 else nil, Need = nil, Kind = "Claim", Id = "D" .. i,
				Done = if r.Paid then "PAID" elseif not done then string.format("%d/%d", r.Have, r.Need) else nil, Label = "CLAIM",
			})
		end
		local h = it.Hvt
		if typeof(h) == "table" then
			local done = h.Have >= h.Need
			table.insert(out, {
				Name = string.upper(h.Text), Sub = string.format("%d/%d  reward %s + 50 Gold", h.Have, h.Need, short(it.HvtReward or 0)),
				Price = if done and not h.Paid then 0 else nil, Need = nil, Kind = "Claim", Id = "HVT",
				Done = if h.Paid then "PAID" elseif not done then string.format("%d/%d", h.Have, h.Need) else nil, Label = "CLAIM",
			})
		end
		for _, b in ipairs(it.Bases or {}) do
			table.insert(out, { Name = "SCOUT " .. string.upper(b.Name), Sub = "Turrets, guards, defences and the SEND verdict", Price = it.ScoutPrice, Need = nil, Kind = "Scout", Id = tostring(b.PlotId) })
		end
		for _, rb in ipairs(it.RaidedBy or {}) do
			table.insert(out, {
				Name = "RAIDED BY " .. string.upper(tostring(rb.Name)), Sub = "Revenge: SEND your army (the normal SEND rules)",
				Price = if rb.PlotId then 0 else nil, Need = nil, Kind = "Revenge", Id = tostring(rb.PlotId), Label = "SEND", Done = if rb.PlotId then nil else "GONE",
			})
		end
	elseif kind == "BlackMarket" and typeof(s.Market) == "table" then
		local mk = s.Market
		local days = math.floor((tonumber(mk.EndsIn) or 0) / 86400)
		local hours = math.floor(((tonumber(mk.EndsIn) or 0) % 86400) / 3600)
		for _, r in ipairs(mk.Rows or {}) do
			table.insert(out, {
				Name = string.upper(r.Name), Sub = string.format("%s, this week only (new stock in %dd %dh)", r.Kind, days, hours),
				Price = if r.Owned then nil else r.Price, Need = nil, Kind = "Market", Id = r.Id, Gold = r.Gold, Done = if r.Owned then "OWNED" else nil,
			})
		end
		for _, r in ipairs(mk.Owned or {}) do
			table.insert(out, {
				Name = string.upper(r.Name), Sub = "Yours", Price = 0, Need = nil, Kind = "MarketEquip",
				Id = if r.On then "None:" .. r.Kind else r.Id, Label = if r.On then "TAKE OFF" else "PUT ON",
			})
		end
		-- v157: the Black Market camos you own go on the gun in your hand (the server checks the gun and the camo)
		local held = mk.Held
		for _, cm in ipairs(mk.Camos or {}) do
			if typeof(held) == "string" then
				table.insert(out, {
					Name = string.format("%s (your %s)", string.upper(tostring(cm.Name)), tostring(mk.HeldName or held)),
					Sub = if cm.On then "On your gun" else "Yours: put it on the gun in your hand",
					Price = 0, Need = nil, Kind = "EquipCamo", Id = held .. ":" .. (if cm.On then "None" else tostring(cm.Id)),
					Label = if cm.On then "TAKE OFF" else "PUT ON",
				})
			else
				table.insert(out, {
					Name = string.upper(tostring(cm.Name)), Sub = "Yours: hold a gun to put it on",
					Price = nil, Need = nil, Kind = "Info", Id = "Camo" .. tostring(cm.Id), Done = "OWNED",
				})
			end
		end
	elseif kind == "Heist" and typeof(s.Heist) == "table" then
		local hs = s.Heist
		local nx = hs.Next
		table.insert(out, {
			Name = if nx then string.upper(nx.Name) .. string.format(" (VAULT %d)", hs.Kit + 2) else "EVERY KIT OWNED",
			Sub = if nx then string.format("Pays %d min of your income, +%d guards, %d s hold", nx.Minutes, nx.Guards, nx.Hold) else "Raid the Deep Vault at the bank",
			Price = if nx then nx.Cost else nil, Need = nil, Kind = "Heist", Id = "Next", Done = if nx then nil else "MAX",
		})
	elseif kind == "Workshop" and typeof(s.Workshop) == "table" then
		for _, w in ipairs(s.Workshop) do
			table.insert(out, {
				Name = string.format("%s VEHICLES  L%d/%d", string.upper(w.Id), w.Level, w.Max),
				Sub = string.format("+%d%% HP, +%d%% speed now. Plates at L3, gold trim at L5", w.Hp, w.Speed),
				Price = w.NextCost, Need = nil, Kind = "Workshop", Id = w.Id,
				Done = if w.NextCost == nil then "MAX" else nil,
			})
		end
	elseif kind == "Hospital" and typeof(s.Hospital) == "table" then
		local h = s.Hospital
		table.insert(out, { Name = "FREE HEAL", Sub = if h.HealIn > 0 then string.format("Ready in %d s", h.HealIn) else "Back to full health", Price = if h.HealIn > 0 then nil else 0, Need = nil, Kind = "Heal", Id = "Now", Done = if h.HealIn > 0 then "WAIT" else nil })
		table.insert(out, { Name = string.format("MED KIT  %d/%d", h.MedKits, h.MedKitMax), Sub = "+50 HP over 3 s. Hold the MED KIT button", Price = if h.MedKits < h.MedKitMax then h.MedKitPrice else nil, Need = nil, Kind = "MedKit", Id = "One", Done = if h.MedKits >= h.MedKitMax then "FULL" else nil })
		table.insert(out, { Name = string.format("COMBAT MEDICINE  L%d/%d", h.Medicine, h.MedicineMax), Sub = string.format("+%d max HP now, +10 a level", h.Medicine * 10), Price = h.MedicineNext, Need = nil, Kind = "Medicine", Id = "Next", Done = if h.MedicineNext == nil then "MAX" else nil })
		table.insert(out, { Name = "FIELD SURGEON", Sub = "Get up where you fall (10 s, half HP)", Price = if h.Revive < 1 then h.RevivePrice else nil, Need = nil, Kind = "Revive", Id = "One", Done = if h.Revive >= 1 then "READY" else nil })
	elseif kind == "HQ" then
		local t = s.Tier
		if typeof(t) == "table" then
			local nx = t.Next
			table.insert(out, {
				Name = if nx then string.format("BASE TIER %d: %s", nx.Tier, string.upper(nx.Name)) else "BASE TIER MAX",
				Sub = if t.Level > 0 then "Now: Tier " .. t.Level .. " " .. tostring(t.Name) else "Your base grows: walls, towers, guns",
				Price = if nx then nx.Cost else nil,
				Need = if nx then nx.Need else nil,
				Kind = "Tier",
				Id = "Next",
				Done = if nx == nil then "MAX" else nil,
			})
		end
		local wh = s.Warheads
		if typeof(wh) == "table" then
			table.insert(out, { Name = "TACTICAL WARHEAD", Sub = "Loads one silo slot now (the cooldowns stay)", Price = wh.TacticalCost, Need = wh.TacticalNeed, Kind = "Warhead", Id = "Tactical" })
			table.insert(out, {
				Name = "HEAVY WARHEAD", Sub = "Your next launch: x1.3 radius, x1.2 damage", Price = if wh.Heavy >= 1 then nil else wh.HeavyCost,
				Need = wh.HeavyNeed, Kind = "Warhead", Id = "Heavy", Done = if wh.Heavy >= 1 then "READY" else nil,
			})
		end
		local rb = s.Rebuild
		if typeof(rb) == "table" then
			table.insert(out, {
				Name = "REBUILD DEFENCES NOW",
				Sub = if rb.Need then "The gate or a gun is down" else "Everything is standing",
				Price = if rb.Need then rb.Price else nil,
				Need = nil,
				Kind = "Rebuild",
				Id = "Now",
				Done = if rb.Need then nil else "OK",
			})
		end
	end
	return out
end

local setListOpen: (kind: string?) -> () -- forward (refreshList's REVENGE row closes the panel)

local function refreshList()
	local kind = listOpen
	local host = listRows
	if kind == nil or host == nil then
		return
	end
	for _, c in ipairs(host:GetChildren()) do
		if c:IsA("Frame") then
			c:Destroy()
		end
	end
	local cash, perSec = wallet()
	local TAP = PanelShell.TouchMinV()
	local rows = EndgameController.ListRows(kind, state)
	local sub = listSub
	if sub then
		sub.Text = if #rows == 0 then "Loading..." elseif kind == "HQ" then "Kept through rebirth" elseif kind == "Recruits" then "Train each soldier type. Kept through rebirth" elseif kind == "Hospital" then "Heal, Med Kits, more max HP, a revive" elseif kind == "Armory" then "Upgrade your guns. Attachments and camos for the gun in your hand" elseif kind == "Workshop" then "Tougher, faster vehicles. Applies on the next spawn" elseif kind == "Intel" then "Daily contracts, the weekly target, scouting, revenge" elseif kind == "BlackMarket" then "Cosmetics only. New stock every Monday" elseif kind == "Heist" then "Heist kits open bigger vaults at this bank" else "Tougher turrets, gate and vault"
	end
	for i, r in ipairs(rows) do
		local row = Instance.new("Frame")
		row.Name = "Row_" .. r.Id
		row.LayoutOrder = i
		row.Size = UDim2.new(1, 0, 0, TAP + 30)
		row.BackgroundColor3 = PanelShell.Colors.Row
		row.BorderSizePixel = 0
		row.Parent = host
		UIUtil.Corner(row, 8)
		local nm = Instance.new("TextLabel")
		nm.BackgroundTransparency = 1
		nm.Position = UDim2.fromOffset(12, 4)
		nm.Size = UDim2.new(1, -(150 + 24), 0, PanelShell.Text(16) + 4)
		nm.Font = Enum.Font.GothamBold
		nm.TextSize = PanelShell.Text(16)
		nm.TextColor3 = Constants.Colors.GoldBright
		nm.TextXAlignment = Enum.TextXAlignment.Left
		nm.TextTruncate = Enum.TextTruncate.AtEnd
		nm.Text = r.Name
		nm.Parent = row
		local sb = Instance.new("TextLabel")
		sb.BackgroundTransparency = 1
		sb.Position = UDim2.fromOffset(12, 6 + PanelShell.Text(16) + 4)
		sb.Size = UDim2.new(1, -(150 + 24), 0, PanelShell.Text(16) * 2 + 4)
		sb.Font = Enum.Font.GothamMedium
		sb.TextSize = PanelShell.Text(16)
		sb.TextColor3 = Constants.Colors.Text
		sb.TextXAlignment = Enum.TextXAlignment.Left
		sb.TextYAlignment = Enum.TextYAlignment.Top
		sb.TextWrapped = true
		local extra = ""
		if r.Price and r.Price > 0 and not r.Gold then
			extra = "  " .. short(r.Price) .. "  " .. EndgameController.EtaText(r.Price, cash, perSec)
		end
		sb.Text = r.Sub .. extra
		sb.Parent = row
		local b = Instance.new("TextButton")
		b.Name = "Buy"
		b.AnchorPoint = Vector2.new(1, 0.5)
		b.Position = UDim2.new(1, -8, 0.5, 0)
		b.Size = UDim2.fromOffset(150, TAP)
		b.Font = HudConfig.Fonts.Display
		b.TextSize = PanelShell.Text(18)
		b.TextColor3 = Color3.fromRGB(255, 255, 255)
		b.BorderSizePixel = 0
		b.Parent = row
		UIUtil.Corner(b, 8)
		UIUtil.TextOutline(b, 1.2)
		local gold = if typeof(state.Armory) == "table" then tonumber(state.Armory.Gold) or 0 else 0
		local can = r.Done == nil and r.Need == nil and r.Price ~= nil and (if r.Gold then gold >= (r.Price :: number) else cash >= (r.Price :: number))
		b.Text = if r.Done then r.Done
			elseif r.Need then "LOCKED"
			elseif r.Label then r.Label
			elseif r.Gold then (if can then string.format("%d GOLD", r.Price :: number) else "NEED GOLD")
			elseif can and r.Price == 0 then "GET"
			elseif can then "BUY"
			else "NEED " .. short((r.Price or 0) - cash)
		b.BackgroundColor3 = if can then Color3.fromRGB(46, 170, 82) else Color3.fromRGB(70, 76, 84)
		b.AutoButtonColor = can
		if r.Need then
			sb.Text = r.Sub .. "  (" .. r.Need .. ")"
		end
		b.Activated:Connect(function()
			if r.Kind == "ScoutView" then
				local rp = if typeof(state.Intel) == "table" then state.Intel.Report else nil
				if typeof(rp) == "table" then
					EndgameController.ShowScoutCard(rp)
				end
			elseif can and r.Kind == "Revenge" then
				-- the Intel Office's revenge: the JOB 38 SEND (the server re-checks every fairness rule)
				task.spawn(Remotes.FireServer, Constants.RemoteNames.RequestArmySend, tonumber(r.Id))
				setListOpen(nil)
			elseif can then
				task.spawn(Remotes.FireServer, Constants.RemoteNames.RequestEndgameBuy, r.Kind, r.Id)
			end
		end)
	end
end

function setListOpen(kind: string?)
	listOpen = kind
	local p = listPanel
	if p then
		p.Visible = kind ~= nil
	end
	local t = listTitle
	if t and kind then
		t.Text = LIST_TITLES[kind] or kind
	end
	local sh = listShell
	if sh then
		sh.Sync(kind ~= nil)
	end
	if kind then
		refreshList()
		task.spawn(Remotes.FireServer, Constants.RemoteNames.RequestEndgameState)
		task.spawn(function()
			local tick = 0
			while listOpen == kind do
				task.wait(0.5)
				if listOpen ~= kind then
					break
				end
				tick += 1
				if tick % 4 == 0 then
					refreshList() -- the ETAs (every 2 s; a buy's push refreshes at once)
				end
				local pt = stationPoint(kind)
				local c = player.Character
				local r = c and c:FindFirstChild("HumanoidRootPart")
				if pt and r and r:IsA("BasePart") and (r.Position - pt).Magnitude > EndgameConfig.Station.CloseRange then
					setListOpen(nil)
				end
			end
		end)
	end
end

local function setStationOpen(kind: string?)
	stationOpen = kind
	local p = stationPanel
	if p then
		p.Visible = kind ~= nil
		local st = if kind then PSC.Stations[kind] else nil
		if st then
			L.Title.Text = st.Title
		end
	end
	local sh = stationShell
	if sh then
		sh.Sync(kind ~= nil)
	end
	if kind then
		refreshStation()
		task.spawn(Remotes.FireServer, Constants.RemoteNames.RequestEndgameState)
		task.spawn(function()
			while stationOpen == kind do
				task.wait(0.5) -- 2 Hz: the ETA and the walk-away check
				if stationOpen ~= kind then
					break
				end
				refreshStation()
				local pt = stationPoint(kind)
				local c = player.Character
				local r = c and c:FindFirstChild("HumanoidRootPart")
				if pt and r and r:IsA("BasePart") and (r.Position - pt).Magnitude > EndgameConfig.Station.CloseRange then
					setStationOpen(nil)
				end
			end
		end)
	end
end

local function empireRowsRefresh()
	local host = empireRows
	if host == nil then
		return
	end
	for _, c in ipairs(host:GetChildren()) do
		if c:IsA("Frame") then
			c:Destroy()
		end
	end
	local e = state.Empire
	local ring = ringLabel
	if ring then
		ring.Text = if typeof(e) == "table" then tostring(e.Level) else "-"
		ring.Visible = EndgameConfig.LiveFor(player.UserId, "EmpireLevel") -- v157: no empty ring for Black-Market-only players
	end
	local cash, perSec = wallet()
	local TAP = PanelShell.TouchMinV()
	local order = 0
	local kinds: { string } = {}
	if EndgameConfig.LiveFor(player.UserId, "BaseTier") then
		table.insert(kinds, "HQ")
	end
	for _, k in ipairs(PSC.Order) do
		table.insert(kinds, k)
	end
	for _, kind in ipairs(kinds) do
		local st = if kind == "HQ" then { Part = "BaseTier", Title = "HQ UPGRADE (your base)", Sign = "HQ" } else PSC.Stations[kind]
		if st and EndgameConfig.LiveFor(player.UserId, st.Part) then
			order += 1
			local row = Instance.new("Frame")
			row.Name = kind
			row.LayoutOrder = order
			row.Size = UDim2.new(1, 0, 0, TAP + 16)
			row.BackgroundColor3 = PanelShell.Colors.Row
			row.BorderSizePixel = 0
			row.Parent = host
			UIUtil.Corner(row, 8)
			local name = Instance.new("TextLabel")
			name.BackgroundTransparency = 1
			name.Position = UDim2.fromOffset(12, 6)
			name.Size = UDim2.new(1, -(TAP + 110), 0, PanelShell.Text(16) + 4)
			name.Font = Enum.Font.GothamBold
			name.TextSize = PanelShell.Text(16)
			name.TextColor3 = Constants.Colors.GoldBright
			name.TextXAlignment = Enum.TextXAlignment.Left
			name.Text = st.Title
			name.Parent = row
			local goal = Instance.new("TextLabel")
			goal.BackgroundTransparency = 1
			goal.Position = UDim2.fromOffset(12, 8 + PanelShell.Text(16) + 4)
			goal.Size = UDim2.new(1, -(TAP + 110), 0, PanelShell.Text(16) + 4)
			goal.Font = Enum.Font.GothamMedium
			goal.TextSize = PanelShell.Text(16)
			goal.TextColor3 = Constants.Colors.Text
			goal.TextXAlignment = Enum.TextXAlignment.Left
			goal.TextTruncate = Enum.TextTruncate.AtEnd
			goal.Text = "..."
			if kind == "Command" and typeof(e) == "table" then
				goal.Text = if typeof(e.NextCost) == "number"
					then string.format("EMPIRE %d  %s  %s", e.Level + 1, short(e.NextCost), EndgameController.EtaText(e.NextCost, cash, perSec))
					else "EMPIRE MAX"
			elseif kind == "HQ" or kind == "Engineers" or kind == "Recruits" or kind == "Hospital" or kind == "Armory" then
				local best: Row? = nil
				for _, r in ipairs(EndgameController.ListRows(kind, state)) do
					if r.Price and r.Price > 0 and not r.Gold and r.Kind ~= "Rebuild" and r.Kind ~= "Retrain" and r.Kind ~= "MedKit" and r.Kind ~= "Revive" and (best == nil or (r.Price :: number) < ((best :: Row).Price :: number)) then
						best = r
					end
				end
				local b = best
				goal.Text = if b then string.format("%s  %s  %s", b.Name, short(b.Price :: number), EndgameController.EtaText(b.Price :: number, cash, perSec)) else "ALL MAXED"
			elseif kind == "BlackMarket" then
				goal.Text = "Cosmetics for Cash + Gold. New stock every Monday"
			end
			goal.Parent = row
			local pin = Instance.new("TextButton")
			pin.Name = "Pin"
			pin.AnchorPoint = Vector2.new(1, 0.5)
			pin.Position = UDim2.new(1, -8, 0.5, 0)
			pin.Size = UDim2.fromOffset(96, TAP)
			pin.BackgroundColor3 = Color3.fromRGB(200, 150, 40)
			pin.Font = HudConfig.Fonts.Display
			pin.TextSize = PanelShell.Text(18)
			pin.TextColor3 = Color3.fromRGB(255, 255, 255)
			pin.Text = "PIN"
			pin.Parent = row
			UIUtil.Corner(pin, 8)
			UIUtil.TextOutline(pin, 1.2)
			pin.Activated:Connect(function()
				local pt = stationPoint(kind)
				if pt == nil and kind == "HQ" then
					local c = hqConsole
					pt = if c then c.Position else nil
				end
				if pt then
					ObjectiveMarker.ShowWith({ Short = st.Sign, X = pt.X, Y = pt.Y, Z = pt.Z }, {
						Pin = true,
						ArriveStuds = MapConfig.PinArriveStuds,
						TimeoutSeconds = MapConfig.PinTimeoutSeconds,
					})
					EndgameController.CloseEmpire()
				end
			end)
		end
	end
end

local function setEmpireOpen(open: boolean)
	empireOpen = open
	local p = empirePanel
	if p then
		p.Visible = open
	end
	local sh = empireShell
	if sh then
		sh.Sync(open)
	end
	if open then
		empireRowsRefresh()
		task.spawn(Remotes.FireServer, Constants.RemoteNames.RequestEndgameState)
	end
end

function EndgameController.OpenEmpire()
	if player:GetAttribute("WE_EndgameLive") == true then
		setEmpireOpen(true)
	end
end

function EndgameController.CloseEmpire()
	setEmpireOpen(false)
end

function EndgameController.OpenStation(kind: string)
	if player:GetAttribute("WE_EndgameLive") ~= true then
		return
	end
	if kind == "Command" then
		setStationOpen(kind)
	elseif LIST_TITLES[kind] then
		setListOpen(kind)
	end
end

local function label(parent: Instance, name: string, y: number, h: number, size: number, color: Color3, font: Enum.Font?): TextLabel
	local t = Instance.new("TextLabel")
	t.Name = name
	t.BackgroundTransparency = 1
	t.Position = UDim2.fromOffset(16, y)
	t.Size = UDim2.new(1, -32, 0, h)
	t.Font = font or Enum.Font.GothamBold
	t.TextSize = PanelShell.Text(size)
	t.TextColor3 = color
	t.TextWrapped = true
	t.Text = ""
	t.Parent = parent
	L[name] = t
	return t
end

local function buildPanels(pg: PlayerGui)
	local screen = Instance.new("ScreenGui")
	screen.Name = "WarEmpireEndgame"
	PanelShell.Screen(screen)
	screen.Parent = pg
	local touch = PanelShell.IsTouch()
	local TAP = PanelShell.TouchMinV()
	local tH = PanelShell.Text(16) + 8

	-- the station panel
	local big = PanelShell.Text(30) + 8
	local panelH = (TAP + 8) + big + tH + 12 + tH * 3 + 12 + TAP + 12 + tH * 2 + 16
	local panel = Instance.new("Frame")
	panel.Name = "StationPanel"
	panel.AnchorPoint = Vector2.new(0.5, 0.5)
	panel.Position = UDim2.fromScale(0.5, 0.5)
	panel.Size = if touch then UDim2.new(0.62, 0, 0, panelH) else UDim2.fromOffset(440, panelH)
	panel.BackgroundColor3 = Constants.Colors.Panel
	panel.BorderSizePixel = 0
	panel.Active = true
	panel.Visible = false
	panel.Parent = screen
	UIUtil.Corner(panel, 12)
	UIUtil.Stroke(panel)
	do
		local cap = Instance.new("UISizeConstraint")
		cap.MinSize = Vector2.new(if touch then 420 else 380, 0)
		cap.MaxSize = Vector2.new(if touch then 620 else 440, panelH)
		cap.Parent = panel
	end
	stationPanel = panel
	local title = PanelShell.Title(panel, "COMMAND OFFICE")
	L.Title = title
	PanelShell.CloseButton(panel, function()
		setStationOpen(nil)
	end)
	local y = TAP + 8
	label(panel, "Level", y, big, 30, Constants.Colors.GoldBright, HudConfig.Fonts.Display)
	y += big
	label(panel, "Pct", y, tH, 16, Constants.Colors.Cash)
	y += tH + 12
	label(panel, "Next", y, tH, 16, Constants.Colors.Text)
	y += tH
	label(panel, "Price", y, tH, 18, Constants.Colors.Text, HudConfig.Fonts.Display)
	y += tH
	label(panel, "Eta", y, tH, 16, PanelShell.Colors.Muted, Enum.Font.GothamMedium)
	y += tH + 12
	local btn = Instance.new("TextButton")
	btn.Name = "Buy"
	btn.Position = UDim2.fromOffset(16, y)
	btn.Size = UDim2.new(1, -32, 0, TAP)
	btn.BackgroundColor3 = Color3.fromRGB(46, 170, 82)
	btn.Font = HudConfig.Fonts.Display
	btn.TextSize = PanelShell.Text(24)
	btn.TextColor3 = Color3.fromRGB(255, 255, 255)
	btn.Text = "BUY"
	btn.BorderSizePixel = 0
	btn.Parent = panel
	UIUtil.Corner(btn, 10)
	UIUtil.TextOutline(btn, 1.5)
	btn.Activated:Connect(function()
		if stationOpen == "Command" then
			task.spawn(Remotes.FireServer, Constants.RemoteNames.RequestEndgameBuy, "Empire", "Next")
		end
	end)
	buyBtn = btn
	y += TAP + 12
	label(panel, "Foot", y, tH, 16, PanelShell.Colors.Muted, Enum.Font.GothamMedium)
	y += tH
	label(panel, "Foot2", y, tH, 16, PanelShell.Colors.Muted, Enum.Font.GothamMedium)
	stationShell = PanelShell.Attach({
		Id = "Station",
		Screen = screen,
		Panel = panel,
		IsOpen = function(): boolean
			return stationOpen ~= nil
		end,
		Close = function()
			setStationOpen(nil)
		end,
	})

	-- phase 2: the LIST station panel (Engineers, HQ)
	local lp = Instance.new("Frame")
	lp.Name = "ListPanel"
	lp.AnchorPoint = Vector2.new(0.5, 0.5)
	lp.Position = UDim2.fromScale(0.5, 0.5)
	lp.Size = if touch then UDim2.new(0.74, 0, 0.88, 0) else UDim2.fromOffset(520, 440)
	lp.BackgroundColor3 = Constants.Colors.Panel
	lp.BorderSizePixel = 0
	lp.Active = true
	lp.Visible = false
	lp.Parent = screen
	UIUtil.Corner(lp, 12)
	UIUtil.Stroke(lp)
	do
		local cap = Instance.new("UISizeConstraint")
		cap.MinSize = Vector2.new(if touch then 460 else 420, 0)
		cap.MaxSize = Vector2.new(if touch then 760 else 520, 560)
		cap.Parent = lp
	end
	listPanel = lp
	listTitle = PanelShell.Title(lp, "ENGINEERING BUREAU")
	PanelShell.CloseButton(lp, function()
		setListOpen(nil)
	end)
	local lsub = Instance.new("TextLabel")
	lsub.BackgroundTransparency = 1
	lsub.Position = UDim2.fromOffset(16, TAP + 8)
	lsub.Size = UDim2.new(1, -32, 0, tH)
	lsub.Font = Enum.Font.GothamMedium
	lsub.TextSize = PanelShell.Text(16)
	lsub.TextColor3 = PanelShell.Colors.Muted
	lsub.TextXAlignment = Enum.TextXAlignment.Left
	lsub.Text = ""
	lsub.Parent = lp
	listSub = lsub
	local lrows = Instance.new("ScrollingFrame")
	lrows.Name = "Rows"
	lrows.Position = UDim2.fromOffset(12, TAP + 8 + tH + 6)
	lrows.Size = UDim2.new(1, -24, 1, -(TAP + 8 + tH + 18))
	lrows.BackgroundTransparency = 1
	lrows.BorderSizePixel = 0
	lrows.ScrollBarThickness = if touch then 6 else 4
	lrows.AutomaticCanvasSize = Enum.AutomaticSize.Y
	lrows.CanvasSize = UDim2.fromOffset(0, 0)
	lrows.Parent = lp
	local llay = Instance.new("UIListLayout")
	llay.Padding = UDim.new(0, 8)
	llay.SortOrder = Enum.SortOrder.LayoutOrder
	llay.Parent = lrows
	listRows = lrows :: any
	listShell = PanelShell.Attach({
		Id = "StationList",
		Screen = screen,
		Panel = lp,
		IsOpen = function(): boolean
			return listOpen ~= nil
		end,
		Close = function()
			setListOpen(nil)
		end,
	})

	-- the base EMPIRE panel
	local ep = Instance.new("Frame")
	ep.Name = "EmpirePanel"
	ep.AnchorPoint = Vector2.new(0.5, 0.5)
	ep.Position = UDim2.fromScale(0.5, 0.5)
	ep.Size = if touch then UDim2.new(0.7, 0, 0.86, 0) else UDim2.fromOffset(480, 420)
	ep.BackgroundColor3 = Constants.Colors.Panel
	ep.BorderSizePixel = 0
	ep.Active = true
	ep.Visible = false
	ep.Parent = screen
	UIUtil.Corner(ep, 12)
	UIUtil.Stroke(ep)
	do
		local cap = Instance.new("UISizeConstraint")
		cap.MinSize = Vector2.new(if touch then 440 else 400, 0)
		cap.MaxSize = Vector2.new(if touch then 700 else 480, 520)
		cap.Parent = ep
	end
	empirePanel = ep
	PanelShell.Title(ep, "EMPIRE")
	PanelShell.CloseButton(ep, function()
		setEmpireOpen(false)
	end)
	-- the Empire Level ring
	local ring = Instance.new("TextLabel")
	ring.Name = "Ring"
	ring.AnchorPoint = Vector2.new(1, 0)
	ring.Position = UDim2.new(1, -(TAP + 20), 0, 6)
	ring.Size = UDim2.fromOffset(TAP, TAP)
	ring.BackgroundColor3 = Color3.fromRGB(40, 34, 20)
	ring.Font = HudConfig.Fonts.Display
	ring.TextSize = PanelShell.Text(22)
	ring.TextColor3 = Constants.Colors.GoldBright
	ring.Text = "-"
	ring.Parent = ep
	do
		local c = Instance.new("UICorner")
		c.CornerRadius = UDim.new(0.5, 0)
		c.Parent = ring
		local s = Instance.new("UIStroke")
		s.Color = Constants.Colors.Gold
		s.Thickness = 3
		s.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
		s.Parent = ring
	end
	ringLabel = ring
	local hint = Instance.new("TextLabel")
	hint.BackgroundTransparency = 1
	hint.Position = UDim2.fromOffset(16, TAP + 8)
	hint.Size = UDim2.new(1, -32, 0, tH)
	hint.Font = Enum.Font.GothamMedium
	hint.TextSize = PanelShell.Text(16)
	hint.TextColor3 = PanelShell.Colors.Muted
	hint.TextXAlignment = Enum.TextXAlignment.Left
	hint.Text = "Buy upgrades at the plaza. PIN shows the way."
	hint.Parent = ep
	local list = Instance.new("ScrollingFrame")
	list.Name = "Rows"
	list.Position = UDim2.fromOffset(12, TAP + 8 + tH + 6)
	list.Size = UDim2.new(1, -24, 1, -(TAP + 8 + tH + 18))
	list.BackgroundTransparency = 1
	list.BorderSizePixel = 0
	list.ScrollBarThickness = if touch then 6 else 4
	list.AutomaticCanvasSize = Enum.AutomaticSize.Y
	list.CanvasSize = UDim2.fromOffset(0, 0)
	list.Parent = ep
	local lay = Instance.new("UIListLayout")
	lay.Padding = UDim.new(0, 8)
	lay.SortOrder = Enum.SortOrder.LayoutOrder
	lay.Parent = list
	empireRows = list :: any
	empireShell = PanelShell.Attach({
		Id = "Empire",
		Screen = screen,
		Panel = ep,
		IsOpen = function(): boolean
			return empireOpen
		end,
		Close = function()
			setEmpireOpen(false)
		end,
	})
end

-- build / drop the local station copies (live players only)
local function syncStations()
	local folder = ReplicatedStorage:FindFirstChild(PSC.FolderName)
	local live = player:GetAttribute("WE_EndgameLive") == true
	for kind, st in pairs(PSC.Stations) do
		local want = live and EndgameConfig.LiveFor(player.UserId, st.Part)
		local v = if folder then folder:FindFirstChild(kind) else nil
		if want and v and v:IsA("CFrameValue") and built[kind] == nil then
			local m, head = EndgameController.BuildStation(kind, v.Value)
			if m and head then
				local pr = Instance.new("ProximityPrompt")
				pr.Name = "StationPrompt"
				pr.ActionText = st.Action
				pr.ObjectText = st.Npc
				pr.HoldDuration = 0
				pr.MaxActivationDistance = PSC.PromptRange
				pr.RequiresLineOfSight = false
				pr.Parent = head
				pr.Triggered:Connect(function()
					EndgameController.OpenStation(kind)
				end)
				m.Parent = Workspace
				built[kind] = m
				refreshBoards()
			end
		elseif not want and built[kind] then
			built[kind]:Destroy()
			built[kind] = nil
			if stationOpen == kind then
				setStationOpen(nil)
			end
		end
	end
end

-- phase 3: the Mythic aura: one light ParticleEmitter on a Mythic soldier (Rate 3, LightEmission 0.3, no light), only
-- at Graphics Quality >= 4 (automatic quality: keyboard devices only, never phones)
local function auraAllowed(): boolean
	local ok, lvl = pcall(function(): number
		return (UserSettings():GetService("UserGameSettings") :: any).SavedQualityLevel.Value
	end)
	if not ok then
		return false
	end
	if lvl == 0 then
		local UIS = game:GetService("UserInputService")
		local okP, pi = pcall(function(): any
			return (UIS :: any).PreferredInput
		end)
		return okP and pi == Enum.PreferredInput.KeyboardAndMouse
	end
	return lvl >= 4
end

local function syncAura(model: Instance)
	if not model:IsA("Model") then
		return
	end
	local root = model:FindFirstChild("HumanoidRootPart")
	if root == nil then
		return
	end
	local has = root:FindFirstChild("WE_MythicAura")
	local want = model:GetAttribute("WE_EliteTier") == 4 and auraAllowed()
	if want and has == nil then
		local e = Instance.new("ParticleEmitter")
		e.Name = "WE_MythicAura"
		e.Rate = 3
		e.Lifetime = NumberRange.new(0.8, 1.2)
		e.Speed = NumberRange.new(0.5, 1)
		e.Size = NumberSequence.new(0.35, 0)
		e.LightEmission = 0.3
		e.Transparency = NumberSequence.new(0.4, 1)
		e.Color = ColorSequence.new(Color3.fromRGB(255, 214, 110))
		e.SpreadAngle = Vector2.new(180, 180)
		e.Parent = root
	elseif not want and has then
		has:Destroy()
	end
end

local function watchSquad(model: Instance)
	syncAura(model)
	model:GetAttributeChangedSignal("WE_EliteTier"):Connect(function()
		syncAura(model)
	end)
end

-- phase 4: the MED KIT button (right edge, clear of the thumbstick / jump zones; hold 0.6 s) and the GET UP button (after
-- a death while a Field Surgeon token is carried, 10 s). Both only for live players, both touch-first (>= 64 v).
local medBtn: TextButton? = nil
local upBtn: TextButton? = nil
local function makeHudButtons(pg: PlayerGui)
	local sg = Instance.new("ScreenGui")
	sg.Name = "WarEmpireMedic"
	sg.ResetOnSpawn = false
	PanelShell.Screen(sg)
	sg.Parent = pg
	local TAP = PanelShell.TouchMinV()
	local mb = Instance.new("TextButton")
	mb.Name = "MedKit"
	mb.AnchorPoint = Vector2.new(1, 0.5)
	mb.Position = UDim2.new(1, -12, 0.42, 0)
	mb.Size = UDim2.fromOffset(TAP + 40, TAP)
	mb.BackgroundColor3 = Color3.fromRGB(40, 110, 70)
	mb.Font = HudConfig.Fonts.Display
	mb.TextSize = PanelShell.Text(16)
	mb.TextColor3 = Color3.fromRGB(255, 255, 255)
	mb.Text = "MED KIT"
	mb.Visible = false
	mb.Parent = sg
	UIUtil.Corner(mb, 10)
	UIUtil.TextOutline(mb, 1.2)
	local fill = Instance.new("Frame")
	fill.Name = "Hold"
	fill.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
	fill.BackgroundTransparency = 0.7
	fill.Size = UDim2.fromScale(0, 1)
	fill.BorderSizePixel = 0
	fill.Parent = mb
	local holding = 0
	mb.InputBegan:Connect(function(io: InputObject)
		if io.UserInputType ~= Enum.UserInputType.Touch and io.UserInputType ~= Enum.UserInputType.MouseButton1 then
			return
		end
		holding += 1
		local my = holding
		task.spawn(function()
			local t0 = os.clock()
			while holding == my and os.clock() - t0 < 0.6 do
				fill.Size = UDim2.fromScale((os.clock() - t0) / 0.6, 1)
				task.wait(0.05)
			end
			if holding == my then
				holding += 1
				task.spawn(Remotes.FireServer, Constants.RemoteNames.RequestEndgameBuy, "UseMedKit", "One")
			end
			fill.Size = UDim2.fromScale(0, 1)
		end)
	end)
	mb.InputEnded:Connect(function()
		holding += 1
	end)
	medBtn = mb
	local ub = Instance.new("TextButton")
	ub.Name = "GetUp"
	ub.AnchorPoint = Vector2.new(0.5, 0.5)
	ub.Position = UDim2.fromScale(0.5, 0.62)
	ub.Size = UDim2.fromOffset(240, TAP + 8)
	ub.BackgroundColor3 = Color3.fromRGB(46, 170, 82)
	ub.Font = HudConfig.Fonts.Display
	ub.TextSize = PanelShell.Text(22)
	ub.TextColor3 = Color3.fromRGB(255, 255, 255)
	ub.Text = "GET UP"
	ub.Visible = false
	ub.Parent = sg
	UIUtil.Corner(ub, 12)
	UIUtil.TextOutline(ub, 1.5)
	ub.Activated:Connect(function()
		ub.Visible = false
		task.spawn(Remotes.FireServer, Constants.RemoteNames.RequestEndgameBuy, "UseRevive", "One")
	end)
	upBtn = ub
end

-- MED KIT shows while he carries kits and is hurt (checked on health / attribute changes: no loop)
local function syncMed(h: Humanoid?)
	local b = medBtn
	if b == nil then
		return
	end
	local n = tonumber(player:GetAttribute("WE_MedKits")) or 0
	b.Visible = n > 0 and h ~= nil and h.Health > 0 and h.Health < h.MaxHealth
	b.Text = string.format("MED KIT x%d", n)
end

-- phase 5: the R40 Legend Parade: 6 static honour-guard figures lining the owner's parade road (client-only Parts,
-- built only within 300 studs of the viewer, dropped past 350)
local parades: { [number]: any } = {} -- owner UserId -> the local parade Model
local function syncParades()
	local c = player.Character
	local r = c and c:FindFirstChild("HumanoidRootPart")
	local me = if r and r:IsA("BasePart") then r.Position else nil
	local want: { [number]: any } = {}
	for _, p in ipairs(Players:GetPlayers()) do
		local cf = p:GetAttribute("WE_ParadeCF")
		if typeof(cf) == "CFrame" and me then
			local d = (cf.Position - me).Magnitude
			if d < 300 or (parades[p.UserId] ~= nil and d < 350) then
				want[p.UserId] = cf
			end
		end
	end
	for uid, m in pairs(parades) do
		if want[uid] == nil then
			m:Destroy()
			parades[uid] = nil
		end
	end
	for uid, cf in pairs(want) do
		if parades[uid] == nil then
			local m = Instance.new("Model")
			m.Name = "WE_LegendParade"
			for _, x in ipairs({ -9, 9 }) do
				for _, z in ipairs({ -4, 2, 8 }) do
					local f = cf * CFrame.new(x, 0, z) * CFrame.Angles(0, math.rad(if x < 0 then -90 else 90), 0)
					figure(m, f, Color3.fromRGB(120, 28, 30), Color3.fromRGB(214, 176, 72), Color3.fromRGB(30, 30, 34))
					put(m, "ParadeRifle", Vector3.new(0.22, 3.2, 0.28), f * CFrame.new(0.95, 3.4, -0.55), Color3.fromRGB(34, 34, 36), M.Metal)
				end
			end
			m.Parent = Workspace
			parades[uid] = m
		end
	end
end

local function watchDamage(char: Model)
	char:GetAttributeChangedSignal("WE_GunCamo"):Connect(function()
		local gun = char:FindFirstChild("WE_Gun")
		if gun then
			local okW, WV = pcall(function(): any
				return require(script.Parent.Parent.Modules.WeaponVisuals)
			end)
			if okW and WV and WV.ApplyCamo then
				WV.ApplyCamo(gun, char:GetAttribute("WE_GunCamo"))
			end
		end
	end)
	local hum = char:WaitForChild("Humanoid", 10)
	if hum == nil or not hum:IsA("Humanoid") then
		return
	end
	local last = hum.Health
	syncMed(hum)
	hum.Died:Connect(function()
		local ub = upBtn
		if ub and player:GetAttribute("WE_Revive") == true then
			ub.Visible = true
			task.spawn(function()
				for s = EndgameConfig.Hospital.Revive.WithinSeconds, 1, -1 do
					if not ub.Visible then
						return
					end
					ub.Text = string.format("GET UP (%d)", s)
					task.wait(1)
				end
				ub.Visible = false
			end)
		end
	end)
	hum.HealthChanged:Connect(function(h: number)
		if h < last and stationOpen ~= nil then
			setStationOpen(nil) -- the plaza is contested PvP: taking damage closes the shop
		end
		if h < last and listOpen ~= nil then
			setListOpen(nil)
		end
		syncMed(hum)
		last = h
	end)
end

function EndgameController.Init()
	if EndgameConfig.Live.Enabled ~= true then
		return
	end
	local pg = player:WaitForChild("PlayerGui", 30)
	if not pg or not pg:IsA("PlayerGui") then
		warn("[WAR EMPIRE] EndgameController: no PlayerGui after 30 s; off")
		return
	end
	buildPanels(pg)
	makeHudButtons(pg)
	-- Code Bot v168: a done contract points the tracker (compass pill + world marker) at the Intel Office until claimed
	do
		local okG, IG = pcall(function(): any
			return require(script.Parent.Parent.Modules.IntelGuide)
		end)
		if okG and IG and IG.Start then
			pcall(IG.Start)
		end
	end
	task.spawn(function()
		while true do
			task.wait(2)
			pcall(syncParades)
		end
	end)
	player:GetAttributeChangedSignal("WE_MedKits"):Connect(function()
		local c = player.Character
		syncMed(c and c:FindFirstChildOfClass("Humanoid"))
	end)
	Remotes.BindEvent(Constants.RemoteNames.FeaturePush, function(kind: any, data: any)
		if kind == "ScoutReport" and typeof(data) == "table" then
			EndgameController.ShowScoutCard(data) -- Code Bot v171: the paid result, on screen until closed
			return
		end
		if kind ~= "EndgameState" or typeof(data) ~= "table" then
			return
		end
		state = data
		refreshBoards()
		refreshStation()
		refreshList()
		if empireOpen then
			empireRowsRefresh()
		end
	end)
	player:GetAttributeChangedSignal("WE_EndgameLive"):Connect(function()
		syncStations()
		if player:GetAttribute("WE_EndgameLive") == true then
			task.spawn(Remotes.FireServer, Constants.RemoteNames.RequestEndgameState)
		end
	end)
	player:GetAttributeChangedSignal("WE_EmpireLevel"):Connect(function()
		task.spawn(Remotes.FireServer, Constants.RemoteNames.RequestEndgameState)
	end)
	player.CharacterAdded:Connect(function(c: Model)
		task.spawn(watchDamage, c)
	end)
	do
		local CollectionService = game:GetService("CollectionService")
		CollectionService:GetInstanceAddedSignal("WE_SquadUnit"):Connect(watchSquad)
		for _, m in ipairs(CollectionService:GetTagged("WE_SquadUnit")) do
			watchSquad(m)
		end
	end
	if player.Character then
		task.spawn(watchDamage, player.Character)
	end
	-- the station frames arrive once the server's world is built (a slow poll; nothing per frame)
	task.spawn(function()
		for _ = 1, 90 do
			syncStations()
			local folder = ReplicatedStorage:FindFirstChild(PSC.FolderName)
			if folder then
				folder.ChildAdded:Connect(syncStations)
				break
			end
			task.wait(2)
		end
	end)
	if player:GetAttribute("WE_EndgameLive") == true then
		task.spawn(Remotes.FireServer, Constants.RemoteNames.RequestEndgameState)
	end
	task.spawn(function()
		local ConsoleLocator = require(Shared.Util.ConsoleLocator)
		while true do
			task.wait(2)
			local want = player:GetAttribute("WE_EndgameLive") == true
				and (EndgameConfig.LiveFor(player.UserId, "BaseTier") or EndgameConfig.LiveFor(player.UserId, "Defence"))
			local pid = tonumber(player:GetAttribute("WE_PlotId"))
			-- phase 4: the Vehicle Workshop prompt on his own Vehicle Depot console
			local wantW = player:GetAttribute("WE_EndgameLive") == true and EndgameConfig.LiveFor(player.UserId, "Workshop")
			local depot = if wantW and pid then ConsoleLocator.Find(pid, "VehicleDepot") else nil
			if depot ~= depotConsole then
				local oldD = depotConsole
				if oldD then
					local pr0 = oldD:FindFirstChild("WE_WorkshopPrompt")
					if pr0 then
						pr0:Destroy()
					end
				end
				depotConsole = depot
				if depot then
					local prW = Instance.new("ProximityPrompt")
					prW.Name = "WE_WorkshopPrompt"
					prW.ActionText = "Workshop"
					prW.ObjectText = "Vehicle upgrades"
					prW.HoldDuration = 0
					prW.KeyboardKeyCode = Enum.KeyCode.F -- the console's own buy prompt keeps E
					prW.UIOffset = Vector2.new(0, 72)
					prW.MaxActivationDistance = 10
					prW.RequiresLineOfSight = false
					prW.Parent = depot
					prW.Triggered:Connect(function()
						EndgameController.OpenStation("Workshop")
					end)
				end
			end
			local console = if want and pid then ConsoleLocator.Find(pid, "CommandCenter") else nil
			if console ~= hqConsole then
				local old = hqConsole
				if old then
					local pr = old:FindFirstChild("WE_HQPrompt")
					if pr then
						pr:Destroy()
					end
				end
				hqConsole = console
				if console then
					local pr = Instance.new("ProximityPrompt")
					pr.Name = "WE_HQPrompt"
					pr.ActionText = "HQ Upgrade"
					pr.ObjectText = "Base Tier"
					pr.HoldDuration = 0
					pr.KeyboardKeyCode = Enum.KeyCode.F -- the console's own buy prompt keeps E
					pr.UIOffset = Vector2.new(0, 72)
					pr.MaxActivationDistance = 10
					pr.RequiresLineOfSight = false
					pr.Parent = console
					pr.Triggered:Connect(function()
						EndgameController.OpenStation("HQ")
					end)
				end
			end
		end
	end)
end

return EndgameController
