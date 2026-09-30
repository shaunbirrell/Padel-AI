--!strict
--[[
	claude-bud JOB 30 (2026-09-30): the full-screen WORLD MAP (MapConfig, Shared/Util/MapAreas, server MapService).

	OPENS from the MAP rail tile, or M when the player prefers keys (Missions moved to N). It is a registered Modal
	panel ("Map"): one panel at a time, and the black dim closes it on touch.

	LAYOUT (phone landscape first):
	  * The map canvas is a square on the RIGHT, the tap surface: it never sits in the left 40 % of the safe area
	    (thumbstick). North (-Z) is up.
	  * The left column holds:
	    - the title;
	    - the buttons GO / TRAVEL / CLEAR PIN, in its TOP THIRD (the allowed zone), each TouchMinV tall;
	    - the selected place's card (text only);
	    - the legend.
	  * Close X at the canvas's top-right.

	DRAWS (world -> canvas by scale, so it fits any screen):
	  * cached once: sea, land, the named areas (WorldConfig.POIs joined to their outposts, MapAreas) with <= 10
	    labels;
	  * live, from RequestMapLive every RefreshSeconds while open:
	    - every base (yours green, "<Name>'s Empire" on tap);
	    - outposts (yours green, enemy red, neutral gold);
	    - the bank, supply crates / the airdrop, job spots;
	  * the player's own arrow (position + facing) and the pin.

	TAPS on the canvas (a tap = press and release within 12 px):
	  * on the pin: removes it;
	  * on a base: its card;
	  * inside an area: its card (what is there: kind, outpost bonus and owner, enemies, jobs), with GO (pin the tapped
	    point) and TRAVEL (when you hold it);
	  * open ground: a PIN at once.

	THE PIN is the ONE objective marker: ObjectiveMarker.ShowWith({ Short = "PIN", ... }, { Pin = true, ArriveStuds =
	15 }). It uses the same GO line and compass as missions and airdrops. It beats their targets while it is set, and
	ends ConsoleWaypoint's line (ShowWith calls ConsoleWaypoint.Clear()). It clears on arrival, by tapping it, or with
	CLEAR PIN.

	COST: nothing runs while the map is closed. While it is open: one loop at RefreshSeconds (one server call and
	pooled marker frames moved by scale; no new instances after the first fill, no workspace scans).
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared", 60)
if not Shared then
	warn("[WAR EMPIRE] MapController: no ReplicatedStorage.Shared after 60 s; not started")
	return {}
end
local Constants = require(Shared.Constants)
local Remotes = require(Shared.Remotes)
local MapConfig = require(Shared.Configs.MapConfig)
local HudConfig = require(Shared.Configs.HudConfig)
local TerritoryConfig = require(Shared.Configs.TerritoryConfig)
local RetentionConfig = require(Shared.Configs.RetentionConfig)
local MapAreas = require(Shared.Util.MapAreas)

local PanelShell = require(script.Parent.Parent.Modules.PanelShell)
local ObjectiveMarker = require(script.Parent.Parent.Modules.ObjectiveMarker)
local AudioController = require(script.Parent.Parent.Modules.AudioController)

local MapController = {}

local PANEL_ID = "Map"
local C = MapConfig.Colors
local E = MapConfig.Extent

local player = Players.LocalPlayer
local open = false
local shell: PanelShell.Shell? = nil
local panel: Frame? = nil
local canvas: TextButton? = nil
local staticBuilt = false
local liveLayer: Frame? = nil
local pool: { [string]: GuiObject } = {}
local lastLive: any = nil
local inFlight = false
local loopToken = 0

-- the card
local cardTitle: TextLabel? = nil
local cardBody: TextLabel? = nil
local goBtn: TextButton? = nil
local travelBtn: TextButton? = nil
local clearBtn: TextButton? = nil
local selected: { Kind: string, Id: string, X: number, Z: number }? = nil

local function isLive(): boolean
	return RetentionConfig.Live(MapConfig, player.UserId)
end

-- world (x, z) -> canvas scale (u, v); and back
local function toUV(x: number, z: number): (number, number)
	return (x - E.X0) / (E.X1 - E.X0), (z - E.Z0) / (E.Z1 - E.Z0)
end
local function toWorld(u: number, v: number): (number, number)
	return E.X0 + u * (E.X1 - E.X0), E.Z0 + v * (E.Z1 - E.Z0)
end

local function corner(p: Instance, r: UDim)
	local c = Instance.new("UICorner")
	c.CornerRadius = r
	c.Parent = p
end

local function text(parent: Instance, s: string, size: number, color: Color3, font: Enum.Font?): TextLabel
	local l = Instance.new("TextLabel")
	l.BackgroundTransparency = 1
	l.Font = font or Enum.Font.GothamBold
	l.TextSize = PanelShell.Text(size)
	l.TextColor3 = color
	l.TextStrokeTransparency = 0.5
	l.Text = s
	l.Parent = parent
	return l
end

local function button(parent: Instance, name: string, label: string, w: number): TextButton
	local b = Instance.new("TextButton")
	b.Name = name
	b.Size = UDim2.fromOffset(w, PanelShell.TouchMinV())
	b.BackgroundColor3 = Color3.fromRGB(58, 62, 44)
	b.TextColor3 = C.Text
	b.Font = Enum.Font.GothamBlack
	b.TextSize = PanelShell.Text(20)
	b.Text = label
	b.AutoButtonColor = true
	b.Visible = false
	corner(b, UDim.new(0, 8))
	local st = Instance.new("UIStroke")
	st.Color = C.Accent
	st.Thickness = 1.5
	st.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	st.Parent = b
	b.Parent = parent
	return b
end

-- ── the cached layer ──────────────────────────────────────────────────────────────────────────────────────────────
local function buildStatic(cv: GuiObject)
	if staticBuilt then
		return
	end
	staticBuilt = true
	-- dry land (x +-1760, z -1760..1490; south of it is the bay)
	local u0, v0 = toUV(-1760, -1760)
	local u1, v1 = toUV(1760, 1490)
	local land = Instance.new("Frame")
	land.Name = "Land"
	land.BackgroundColor3 = C.Land
	land.BorderSizePixel = 0
	land.Position = UDim2.fromScale(u0, v0)
	land.Size = UDim2.fromScale(u1 - u0, v1 - v0)
	land.ZIndex = 2
	land.Parent = cv
	corner(land, UDim.new(0.03, 0))
	for _, a in ipairs(MapAreas.List()) do
		local f = Instance.new("Frame")
		f.Name = "Area_" .. a.Id
		f.BorderSizePixel = 0
		f.BackgroundColor3 = if a.Territory then C.Outpost else C.Area
		f.BackgroundTransparency = if a.Territory then 0.55 else 0.65
		f.ZIndex = 3
		local r = a.Rect
		if r then
			local ra, rb = toUV(r.X0, r.Z0)
			local rc, rd = toUV(r.X1, r.Z1)
			f.Position = UDim2.fromScale(ra, rb)
			f.Size = UDim2.fromScale(rc - ra, rd - rb)
			corner(f, UDim.new(0.12, 0))
		else
			local cu, cv2 = toUV(a.X, a.Z)
			local su = a.R * 2 / (E.X1 - E.X0)
			f.AnchorPoint = Vector2.new(0.5, 0.5)
			f.Position = UDim2.fromScale(cu, cv2)
			f.Size = UDim2.fromScale(su, su * (E.X1 - E.X0) / (E.Z1 - E.Z0))
			corner(f, UDim.new(0.5, 0))
		end
		f.Parent = cv
		if MapConfig.LabelIds[a.Id] then
			local cu, cv2 = toUV(a.X, a.Z)
			local l = text(cv, string.upper(a.Name):gsub(" APPROACH", ""):sub(1, 16), 18, C.Text)
			l.Name = "Label_" .. a.Id
			l.AnchorPoint = Vector2.new(0.5, 0.5)
			l.Position = UDim2.fromScale(cu, cv2)
			l.Size = UDim2.fromOffset(220, PanelShell.Text(18) + 4)
			l.ZIndex = 6
		end
	end
end

-- ── pooled live markers ───────────────────────────────────────────────────────────────────────────────────────────
local function marker(key: string, x: number, z: number, color: Color3, size: number, shape: string, label: string?)
	local layer = liveLayer
	if layer == nil then
		return
	end
	local m: GuiObject? = pool[key]
	if not m then
		local f: GuiObject
		if shape == "arrow" or shape == "pin" or shape == "$" then
			local t = text(layer, if shape == "arrow" then "▲" elseif shape == "pin" then "▼" else "$", size, color, Enum.Font.GothamBlack)
			t.TextStrokeTransparency = 0
			f = t
		else
			local fr = Instance.new("Frame")
			fr.BorderSizePixel = 0
			fr.BackgroundColor3 = color
			if shape == "circle" then
				corner(fr, UDim.new(0.5, 0))
			elseif shape == "diamond" then
				fr.Rotation = 45
			end
			local st = Instance.new("UIStroke")
			st.Color = Color3.new(0, 0, 0)
			st.Thickness = 1
			st.Parent = fr
			f = fr
		end
		f.Name = key
		f.AnchorPoint = Vector2.new(0.5, 0.5)
		f.Size = UDim2.fromOffset(size, size)
		f.ZIndex = 8
		f.Parent = layer
		if label then
			local l = text(f, label, 16, C.Text)
			l.Name = "Tag"
			l.AnchorPoint = Vector2.new(0.5, 0)
			l.Position = UDim2.new(0.5, 0, 1, 2)
			l.Size = UDim2.fromOffset(160, PanelShell.Text(16) + 2)
			l.Rotation = if shape == "diamond" then -45 else 0
			l.ZIndex = 9
		end
		pool[key] = f
		m = f
	end
	local mm = m :: any
	local u, v = toUV(x, z)
	mm.Position = UDim2.fromScale(u, v)
	if mm:IsA("Frame") then
		(mm :: Frame).BackgroundColor3 = color
	elseif mm:IsA("TextLabel") then
		(mm :: TextLabel).TextColor3 = color
	end
	mm.Visible = true
end

local seen: { [string]: boolean } = {}
local function mark(key: string, ...: any)
	seen[key] = true
	marker(key, ...)
end

local function territoryPos(id: string): Vector3?
	local d = TerritoryConfig.Territories[id] -- keyed by Id
	return if d then d.Position else nil
end

local function myRoot(): BasePart?
	local ch = player.Character
	local r = ch and ch:FindFirstChild("HumanoidRootPart")
	return if r and r:IsA("BasePart") then r else nil
end

local function paint()
	table.clear(seen)
	local live = lastLive
	if typeof(live) == "table" then
		if typeof(live.Bank) == "table" then
			mark("Bank", live.Bank.X, live.Bank.Z, C.Bank, 26, "$", nil)
		end
		for _, b in ipairs(live.Bases or {}) do
			mark("Base" .. tostring(b.P), b.X, b.Z, if b.Mine then C.BaseMine else C.Base, if b.Mine then 22 else 16, "square", if b.Mine then "YOU" else nil)
		end
		for _, o in ipairs(live.Outposts or {}) do
			local p = territoryPos(o.Id)
			if p then
				local col = if o.Mine then C.OutpostMine elseif o.O == "Neutral" then C.Outpost else C.OutpostEnemy
				mark("Out" .. o.Id, p.X, p.Z, col, 16, "diamond", nil)
			end
		end
		for i, d in ipairs(live.Drops or {}) do
			mark("Drop" .. tostring(i), d.X, d.Z, C.Drop, if d.A then 22 else 14, "circle", if d.A then "AIRDROP" else nil)
		end
		for i, j in ipairs(live.Jobs or {}) do
			mark("Job" .. tostring(i), j.X, j.Z, C.Job, 12, "circle", nil)
		end
	end
	if ObjectiveMarker.Pinned() then
		local t = ObjectiveMarker.Current()
		if t then
			mark("Pin", t.X, t.Z, C.Pin, 30, "pin", nil)
		end
	end
	local root = myRoot()
	if root then
		local p = root.Position
		mark("Me", p.X, p.Z, C.Me, 28, "arrow", nil)
		local me = pool.Me
		if me then
			local lv = root.CFrame.LookVector
			me.Rotation = math.deg(math.atan2(lv.X, -lv.Z)) -- north (-Z) is up
		end
	end
	for key, m in pairs(pool) do
		if not seen[key] then
			m.Visible = false
		end
	end
	if clearBtn then
		clearBtn.Visible = ObjectiveMarker.Pinned()
	end
end

-- ── the card ──────────────────────────────────────────────────────────────────────────────────────────────────────
local function outpostState(id: string?): (string?, boolean)
	local live = lastLive
	if id == nil or typeof(live) ~= "table" then
		return nil, false
	end
	for _, o in ipairs(live.Outposts or {}) do
		if o.Id == id then
			return o.O, o.Mine == true
		end
	end
	return nil, false
end

local function jobsIn(a: MapAreas.Area): string?
	local live = lastLive
	if typeof(live) ~= "table" then
		return nil
	end
	local kinds: { [string]: boolean } = {}
	local list: { string } = {}
	for _, j in ipairs(live.Jobs or {}) do
		if MapAreas.Inside(a, j.X, j.Z) and not kinds[j.S] then
			kinds[j.S] = true
			table.insert(list, j.S)
		end
	end
	return if #list > 0 then "Jobs: " .. table.concat(list, ", ") else nil
end

local function travelText(): string?
	local live = lastLive
	local left = if typeof(live) == "table" then tonumber(live.TravelIn) or -1 else -1
	if left < 0 then
		return nil
	end
	return if left > 0 then string.format("TRAVEL %d:%02d", math.floor(left / 60), left % 60) else "TRAVEL"
end

local function showCard(title: string?, lines: { string }, canGo: boolean, travelTarget: string?)
	if cardTitle then
		cardTitle.Text = title or ""
	end
	if cardBody then
		cardBody.Text = table.concat(lines, "\n")
	end
	if goBtn then
		goBtn.Visible = canGo
	end
	if travelBtn then
		local tt = if travelTarget then travelText() else nil
		travelBtn.Visible = tt ~= nil
		travelBtn.Text = tt or "TRAVEL"
		travelBtn:SetAttribute("Target", travelTarget)
	end
end

local function selectArea(a: MapAreas.Area, x: number, z: number)
	selected = { Kind = "Area", Id = a.Id, X = x, Z = z }
	local lines: { string } = {}
	table.insert(lines, MapConfig.KindInfo[a.Kind] or "Area")
	local owner, mine = outpostState(a.Territory)
	if a.Territory then
		table.insert(lines, "Outpost: " .. (if mine then "yours" elseif owner == "Neutral" or owner == nil then "free to capture" elseif owner == "Contested" then "under attack" else "enemy held"))
		if a.Bonus then
			table.insert(lines, a.Bonus)
		end
	end
	if a.Tier and MapConfig.EnemyText[a.Tier] then
		table.insert(lines, MapConfig.EnemyText[a.Tier])
	end
	local jobs = jobsIn(a)
	if jobs then
		table.insert(lines, jobs)
	end
	showCard(a.Name, lines, true, if mine then a.Territory else nil)
end

local function selectBase(b: any)
	selected = { Kind = "Base", Id = tostring(b.P), X = b.X, Z = b.Z }
	local title = if b.Mine then "Your base" elseif typeof(b.N) == "string" then b.N else "Unclaimed base"
	showCard(title, { if b.Mine then "Home: build, collect, recruit" else "Player base" }, true, if b.Mine then "Base" else nil)
end

local function pinAt(x: number, z: number)
	local y = 5
	local hit = Workspace:Raycast(Vector3.new(x, 600, z), Vector3.new(0, -1200, 0))
	if hit then
		y = hit.Position.Y
	end
	pcall(AudioController.PlayClick)
	ObjectiveMarker.ShowWith({ Short = MapConfig.PinLabel, X = x, Y = y, Z = z }, {
		Pin = true,
		ArriveStuds = MapConfig.PinArriveStuds,
		TimeoutSeconds = MapConfig.PinTimeoutSeconds,
	})
	paint()
end

local function onTap(pos: Vector2)
	local cv = canvas
	if cv == nil then
		return
	end
	local ap, as = cv.AbsolutePosition, cv.AbsoluteSize
	if as.X <= 0 or as.Y <= 0 then
		return
	end
	local u, v = (pos.X - ap.X) / as.X, (pos.Y - ap.Y) / as.Y
	if u < 0 or u > 1 or v < 0 or v > 1 then
		return
	end
	local x, z = toWorld(u, v)
	local pxPerStud = as.X / (E.X1 - E.X0)
	-- 1. the pin
	if ObjectiveMarker.Pinned() then
		local t = ObjectiveMarker.Current()
		if t and math.sqrt((t.X - x) ^ 2 + (t.Z - z) ^ 2) * pxPerStud <= MapConfig.PinTapPx then
			ObjectiveMarker.ClearPin()
			selected = nil
			showCard("Pin removed", {}, false, nil)
			paint()
			return
		end
	end
	-- 2. a base
	local live = lastLive
	if typeof(live) == "table" then
		for _, b in ipairs(live.Bases or {}) do
			if math.sqrt((b.X - x) ^ 2 + (b.Z - z) ^ 2) * pxPerStud <= 22 then
				selectBase(b)
				return
			end
		end
	end
	-- 3. an area (its card; GO pins the tapped point)
	local a = MapAreas.At(x, z)
	if a then
		selectArea(a, x, z)
		return
	end
	-- 4. open ground: a pin at once
	selected = nil
	pinAt(x, z)
	showCard("Pin set", { "Follow the gold line" }, false, nil)
end

-- ── open / close / refresh ────────────────────────────────────────────────────────────────────────────────────────
local function fetch()
	if inFlight then
		return
	end
	inFlight = true
	task.spawn(function()
		local fn = Remotes.TryGetFunction(Constants.RemoteNames.RequestMapLive)
		if fn then
			local ok, res = pcall(function()
				return fn:InvokeServer()
			end)
			if ok and typeof(res) == "table" then
				lastLive = res
			end
		end
		inFlight = false
	end)
end

local function setOpen(v: boolean)
	if v and not isLive() then
		return
	end
	open = v
	local p = panel
	if p then
		p.Visible = v
	end
	if shell then
		shell.Sync(v)
	end
	loopToken += 1
	if not v then
		return
	end
	local cv = canvas
	if cv then
		buildStatic(cv)
	end
	showCard("World map", { "Tap a place to see it", "Tap open ground to pin" }, false, nil)
	local my = loopToken
	task.spawn(function()
		while open and loopToken == my do
			fetch()
			paint()
			task.wait(math.max(0.5, MapConfig.RefreshSeconds))
		end
	end)
end

function MapController.Toggle()
	setOpen(not open)
end

function MapController.Open()
	setOpen(true)
end

function MapController.Close()
	setOpen(false)
end

function MapController.IsOpen(): boolean
	return open
end

function MapController.Init()
	if MapConfig.Enabled ~= true then
		return
	end
	local pg = player:FindFirstChildOfClass("PlayerGui") or player:WaitForChild("PlayerGui", 30)
	if not (pg and pg:IsA("PlayerGui")) then
		warn("[WAR EMPIRE] MapController: no PlayerGui after 30 s; map off")
		return
	end
	local screen = Instance.new("ScreenGui")
	screen.Name = "WarEmpireMap"
	PanelShell.Screen(screen)
	screen.Parent = pg

	local root = Instance.new("Frame")
	root.Name = "Panel"
	root.Size = UDim2.fromScale(1, 1)
	root.BackgroundColor3 = C.Background
	root.BackgroundTransparency = 0.02
	root.BorderSizePixel = 0
	root.Active = true
	root.Visible = false
	root.Parent = screen
	panel = root

	-- the canvas: a square on the right (never in the left 40 % of the safe area)
	local cv = Instance.new("TextButton")
	cv.Name = "Canvas"
	cv.AutoButtonColor = false
	cv.Text = ""
	cv.AnchorPoint = Vector2.new(1, 0.5)
	cv.Position = UDim2.new(1, -8, 0.5, 0)
	cv.Size = UDim2.new(0.58, 0, 1, -12)
	cv.BackgroundColor3 = C.Sea
	cv.BorderSizePixel = 0
	cv.ClipsDescendants = true
	cv.Parent = root
	local ar = Instance.new("UIAspectRatioConstraint")
	ar.AspectRatio = (E.X1 - E.X0) / (E.Z1 - E.Z0)
	ar.Parent = cv
	corner(cv, UDim.new(0, 10))
	local cst = Instance.new("UIStroke")
	cst.Color = C.Accent
	cst.Thickness = 2
	cst.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	cst.Parent = cv
	canvas = cv
	local layer = Instance.new("Frame")
	layer.Name = "Live"
	layer.BackgroundTransparency = 1
	layer.Size = UDim2.fromScale(1, 1)
	layer.ZIndex = 8
	layer.Parent = cv
	liveLayer = layer
	PanelShell.CloseButton(cv, function()
		setOpen(false)
	end, { ZIndex = 12 })
	local N = text(cv, "N", 18, C.Accent, Enum.Font.GothamBlack)
	N.Position = UDim2.fromOffset(8, 6)
	N.Size = UDim2.fromOffset(24, 24)
	N.ZIndex = 10

	-- a tap = press and release within 12 px (a drag or a scroll is not a tap)
	local downAt: Vector2? = nil
	cv.InputBegan:Connect(function(input: InputObject)
		if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1 then
			downAt = Vector2.new(input.Position.X, input.Position.Y)
		end
	end)
	cv.InputEnded:Connect(function(input: InputObject)
		if input.UserInputType == Enum.UserInputType.Touch or input.UserInputType == Enum.UserInputType.MouseButton1 then
			local p = Vector2.new(input.Position.X, input.Position.Y)
			local d = downAt
			downAt = nil
			if d and (p - d).Magnitude <= 12 then
				onTap(p)
			end
		end
	end)

	-- the left column: title, the buttons (top third), the card (text only), the legend
	local col = Instance.new("Frame")
	col.Name = "Side"
	col.BackgroundTransparency = 1
	col.Position = UDim2.fromOffset(12, 8)
	col.Size = UDim2.new(0.42, -24, 1, -16)
	col.Parent = root
	local title = text(col, "WORLD MAP", 24, C.Accent, Enum.Font.GothamBlack)
	title.TextXAlignment = Enum.TextXAlignment.Left
	title.Size = UDim2.new(1, 0, 0, PanelShell.Text(24) + 6)
	local TAP = PanelShell.TouchMinV()
	local row = Instance.new("Frame")
	row.Name = "Buttons"
	row.BackgroundTransparency = 1
	row.Position = UDim2.fromOffset(0, PanelShell.Text(24) + 10)
	row.Size = UDim2.new(1, 0, 0, TAP)
	row.Parent = col
	local rl = Instance.new("UIListLayout")
	rl.FillDirection = Enum.FillDirection.Horizontal
	rl.Padding = UDim.new(0, 8)
	rl.Parent = row
	local goB = button(row, "Go", "GO", 96)
	local travelB = button(row, "Travel", "TRAVEL", 150)
	local clearB = button(row, "ClearPin", "CLEAR PIN", 150)
	goBtn, travelBtn, clearBtn = goB, travelB, clearB
	local ct = text(col, "", 22, C.Text, Enum.Font.GothamBlack)
	ct.TextXAlignment = Enum.TextXAlignment.Left
	ct.TextTruncate = Enum.TextTruncate.AtEnd
	ct.Position = UDim2.fromOffset(0, PanelShell.Text(24) + 18 + TAP)
	ct.Size = UDim2.new(1, 0, 0, PanelShell.Text(22) + 4)
	cardTitle = ct
	local cb = text(col, "", 18, C.Muted, Enum.Font.GothamMedium)
	cb.TextXAlignment = Enum.TextXAlignment.Left
	cb.TextYAlignment = Enum.TextYAlignment.Top
	cb.TextWrapped = true
	cb.Position = UDim2.fromOffset(0, PanelShell.Text(24) + 26 + TAP + PanelShell.Text(22))
	cb.Size = UDim2.new(1, 0, 0.5, 0)
	cardBody = cb
	local legend = text(col, "■ Base   ◆ Outpost   ● Crate / Job   $ Bank   ▲ You", 16, C.Muted, Enum.Font.GothamMedium)
	legend.TextXAlignment = Enum.TextXAlignment.Left
	legend.TextWrapped = true
	legend.AnchorPoint = Vector2.new(0, 1)
	legend.Position = UDim2.fromScale(0, 1)
	legend.Size = UDim2.new(1, 0, 0, (PanelShell.Text(16) + 4) * 2)

	goB.Activated:Connect(function()
		local s = selected
		if s then
			pinAt(s.X, s.Z)
			setOpen(false)
		end
	end)
	travelB.Activated:Connect(function()
		local target = travelB:GetAttribute("Target")
		if typeof(target) ~= "string" then
			return
		end
		pcall(AudioController.PlayClick)
		task.spawn(function()
			local fn = Remotes.TryGetFunction(Constants.RemoteNames.RequestFastTravel)
			if fn == nil then
				return
			end
			local ok, res = pcall(function()
				return fn:InvokeServer(target)
			end)
			if ok and typeof(res) == "table" and res.Ok == true then
				setOpen(false)
				return
			end
			local reason = if ok and typeof(res) == "table" then tostring(res.Reason) else "Failed"
			local copy = ({
				Cooldown = "Fast travel is recharging",
				InCombat = "Not while under fire",
				Seated = "Leave the vehicle first",
				Contested = "It is under attack",
				Locked = "Capture it first",
				NoBase = "You have no base yet",
			} :: { [string]: string })[reason] or "Can't travel now"
			if cardBody then
				cardBody.Text = copy
			end
		end)
	end)
	clearB.Activated:Connect(function()
		ObjectiveMarker.ClearPin()
		paint()
	end)

	shell = PanelShell.Attach({
		Id = PANEL_ID,
		Screen = screen,
		Panel = root,
		IsOpen = function(): boolean
			return open
		end,
		Close = function()
			setOpen(false)
		end,
	})

	-- M opens it when the player prefers keys (Missions moved to N); never a touch-only feature
	UserInputService.InputBegan:Connect(function(input, gp)
		if gp or input.KeyCode ~= (HudConfig.Keys :: any).Map then
			return
		end
		setOpen(not open)
	end)
end

return MapController
