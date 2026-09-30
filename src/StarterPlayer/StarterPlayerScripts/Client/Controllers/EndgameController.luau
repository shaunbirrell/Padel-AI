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
local LIST_TITLES = { Engineers = "ENGINEERING BUREAU", HQ = "HQ UPGRADE" }

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
	local pts = state.Stations
	local p = if typeof(pts) == "table" then pts[kind] else nil
	if typeof(p) ~= "table" then
		return nil
	end
	return Vector3.new(p.X, p.Y, p.Z)
end

type Row = { Name: string, Sub: string, Price: number?, Need: string?, Kind: string, Id: string, Done: string? }

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
		sub.Text = if #rows == 0 then "Loading..." else (if kind == "HQ" then "Kept through rebirth" else "Tougher turrets, gate and vault")
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
		if r.Price then
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
		local can = r.Done == nil and r.Need == nil and r.Price ~= nil and cash >= (r.Price :: number)
		b.Text = if r.Done then r.Done elseif r.Need then "LOCKED" elseif can then "BUY" else "NEED " .. short((r.Price or 0) - cash)
		b.BackgroundColor3 = if can then Color3.fromRGB(46, 170, 82) else Color3.fromRGB(70, 76, 84)
		b.AutoButtonColor = can
		if r.Need then
			sb.Text = r.Sub .. "  (" .. r.Need .. ")"
		end
		b.Activated:Connect(function()
			if can then
				task.spawn(Remotes.FireServer, Constants.RemoteNames.RequestEndgameBuy, r.Kind, r.Id)
			end
		end)
	end
end

local function setListOpen(kind: string?)
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
			elseif kind == "HQ" or kind == "Engineers" then
				local best: Row? = nil
				for _, r in ipairs(EndgameController.ListRows(kind, state)) do
					if r.Price and r.Kind ~= "Rebuild" and (best == nil or (r.Price :: number) < ((best :: Row).Price :: number)) then
						best = r
					end
				end
				local b = best
				goal.Text = if b then string.format("%s  %s  %s", b.Name, short(b.Price :: number), EndgameController.EtaText(b.Price :: number, cash, perSec)) else "ALL MAXED"
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

local function watchDamage(char: Model)
	local hum = char:WaitForChild("Humanoid", 10)
	if hum == nil or not hum:IsA("Humanoid") then
		return
	end
	local last = hum.Health
	hum.HealthChanged:Connect(function(h: number)
		if h < last and stationOpen ~= nil then
			setStationOpen(nil) -- the plaza is contested PvP: taking damage closes the shop
		end
		if h < last and listOpen ~= nil then
			setListOpen(nil)
		end
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
	Remotes.BindEvent(Constants.RemoteNames.FeaturePush, function(kind: any, data: any)
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
