--!strict
--[[
	claude-bud JOB 40 part E (2026-09-30): the BASE OWNER MARKERS (BaseMarkerConfig), client only. One BillboardGui per
	plot from ReplicatedStorage.WE_BaseMarkers (BaseMarkerService's data), adorned to a local invisible anchor part
	HeightStuds over the plot centre, AlwaysOnTop (the ONE documented world-label exception), MaxDistance 5000:
	  * a compact pill: the owner's nation flag (NationTexture, the same art NationFlag uses; a plain army-green chip
	    without one), DisplayName (16 px), @username (12 px, muted), a gold rank chip (RebirthConfig title + R<n>;
	    hidden at R0). Own base: a green "YOU" tint; a clan-mate's base: the ally blue. OPEN BASE: grey, 60 %.
	  * one 10 Hz step for all markers together: fade by the viewer's distance (hidden inside 60 studs: the v123 sign
	    takes over, full past 90), size between MaxPx (near) and MinPx (far), compact (flag + rank) past
	    CompactFarStuds or when two overlap on screen (the farther one).
	Only for a viewer BaseMarkerConfig is live for. Nothing per frame; rebuilt on data changes only.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local BaseMarkerController = {}

local Shared = ReplicatedStorage:WaitForChild("Shared", 60)
if not Shared then
	warn("[WAR EMPIRE] BaseMarkerController: no ReplicatedStorage.Shared after 60 s; not started")
	return BaseMarkerController
end
local BaseMarkerConfig = require(Shared.Configs.BaseMarkerConfig)
local RebirthConfig = require(Shared.Configs.RebirthConfig)
local HudConfig = require(Shared.Configs.HudConfig)

local C = BaseMarkerConfig.Colors
local player = Players.LocalPlayer

type Marker = {
	Conf: Instance,
	Anchor: Part,
	Gui: BillboardGui,
	Pill: CanvasGroup,
	Flag: ImageLabel,
	NameL: TextLabel,
	UserL: TextLabel,
	Rank: TextLabel,
	Open: boolean,
}

local markers: { [Instance]: Marker } = {}
local holder: Folder? = nil

local function hold(): Folder
	local h = holder
	if h and h.Parent then
		return h
	end
	local f = Instance.new("Folder")
	f.Name = "WE_BaseMarkerAnchors" -- client-only
	f.Parent = Workspace
	holder = f
	return f
end

local function myClanId(): string?
	-- my own base's record carries my clan id (the server's data); nil = no clan
	local root = ReplicatedStorage:FindFirstChild(BaseMarkerConfig.FolderName)
	for _, c in ipairs(if root then root:GetChildren() else {}) do
		if c:GetAttribute("Owner") == player.UserId then
			local id = c:GetAttribute("ClanId")
			return if typeof(id) == "string" then id else nil
		end
	end
	return nil
end

local function label(parent: Instance, name: string, font: Enum.Font, color: Color3): TextLabel
	local t = Instance.new("TextLabel")
	t.Name = name
	t.BackgroundTransparency = 1
	t.Font = font
	t.TextColor3 = color
	t.TextXAlignment = Enum.TextXAlignment.Left
	t.TextTruncate = Enum.TextTruncate.AtEnd
	t.TextStrokeTransparency = 0.6
	t.Parent = parent
	return t
end

local function build(conf: Instance): Marker
	local anchor = Instance.new("Part")
	anchor.Name = "Marker_" .. conf.Name
	anchor.Size = Vector3.new(0.2, 0.2, 0.2)
	anchor.Transparency = 1
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.CanTouch = false
	anchor.CastShadow = false
	anchor.Parent = hold()
	local g = Instance.new("BillboardGui")
	g.Name = "WE_BaseMarker"
	g:SetAttribute("WE_LabelRole", "basemarker")
	g.AlwaysOnTop = BaseMarkerConfig.AlwaysOnTop -- the ONE documented exception (CLAUDE.md world labels)
	g.MaxDistance = BaseMarkerConfig.MaxDistance
	g.LightInfluence = 0
	g.Size = UDim2.fromOffset(BaseMarkerConfig.MaxPx.X, BaseMarkerConfig.MaxPx.Y)
	g.Adornee = anchor
	g.ResetOnSpawn = false
	g.Parent = anchor
	local pill = Instance.new("CanvasGroup") -- one GroupTransparency fades the whole pill
	pill.Name = "Pill"
	pill.Size = UDim2.fromScale(1, 1)
	pill.BackgroundColor3 = C.Plate
	pill.BackgroundTransparency = 0.25
	pill.BorderSizePixel = 0
	pill.Parent = g
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0.3, 0)
	corner.Parent = pill
	local stroke = Instance.new("UIStroke")
	stroke.Color = C.Stroke
	stroke.Thickness = 1
	stroke.Parent = pill
	local flag = Instance.new("ImageLabel")
	flag.Name = "Flag"
	flag.AnchorPoint = Vector2.new(0, 0.5)
	flag.Position = UDim2.new(0, 6, 0.5, 0)
	flag.Size = UDim2.new(0.6, 0, 0.6, 0)
	flag.SizeConstraint = Enum.SizeConstraint.RelativeYY
	flag.BackgroundColor3 = C.NoFlag
	flag.BorderSizePixel = 0
	flag.ScaleType = Enum.ScaleType.Stretch
	flag.Parent = pill
	local ar = Instance.new("UIAspectRatioConstraint")
	ar.AspectRatio = 4 / 3
	ar.Parent = flag
	local fc = Instance.new("UICorner")
	fc.CornerRadius = UDim.new(0, 4)
	fc.Parent = flag
	local nameL = label(pill, "Name", Enum.Font.GothamBold, C.Name)
	local userL = label(pill, "User", Enum.Font.Gotham, C.Muted)
	local rank = label(pill, "Rank", HudConfig.Fonts.Display, Color3.fromRGB(30, 26, 14))
	rank.BackgroundTransparency = 0
	rank.BackgroundColor3 = C.Rank
	rank.TextXAlignment = Enum.TextXAlignment.Center
	local rc = Instance.new("UICorner")
	rc.CornerRadius = UDim.new(0.3, 0)
	rc.Parent = rank
	return { Conf = conf, Anchor = anchor, Gui = g, Pill = pill, Flag = flag, NameL = nameL, UserL = userL, Rank = rank, Open = true }
end

-- lay the pill out: full (flag, name, @user, rank) or compact (flag + rank)
local function layout(m: Marker, compact: boolean)
	local h = m.Gui.Size.Y.Offset
	local nameSize = math.max(14, math.floor(h * 0.3))
	local userSize = math.max(12, math.floor(h * 0.22))
	local flagW = math.floor(h * 0.6 * 4 / 3)
	local x0 = 6 + flagW + 6
	m.NameL.Visible = not compact
	m.UserL.Visible = not compact and not m.Open
	m.NameL.TextSize = nameSize
	m.UserL.TextSize = userSize
	m.NameL.Position = UDim2.fromOffset(x0, if m.Open then math.floor(h * 0.5 - nameSize * 0.6) else 4)
	m.NameL.Size = UDim2.new(1, -(x0 + 6), 0, nameSize + 2)
	m.UserL.Position = UDim2.fromOffset(x0, 6 + nameSize)
	m.UserL.Size = UDim2.new(1, -(x0 + 70), 0, userSize + 2)
	local rankW = math.max(56, math.floor(h * 1.3))
	m.Rank.TextSize = userSize
	if compact then
		m.Rank.Position = UDim2.fromOffset(x0, math.floor(h * 0.5 - (userSize + 6) * 0.5))
	else
		m.Rank.Position = UDim2.new(1, -(rankW + 6), 0, 6 + nameSize)
	end
	m.Rank.Size = UDim2.fromOffset(rankW, userSize + 4)
end

local function paint(m: Marker)
	local conf = m.Conf
	local owner = conf:GetAttribute("Owner")
	local open = typeof(owner) ~= "number"
	m.Open = open
	m.Gui.Enabled = not open or BaseMarkerConfig.ShowOpenBases
	if open then
		m.NameL.Text = BaseMarkerConfig.Text.Open
		m.NameL.TextColor3 = C.Open
		m.Rank.Visible = false
		m.Flag.Image = ""
		m.Flag.BackgroundColor3 = C.Open
		m.Pill.BackgroundTransparency = 1 - (1 - 0.25) * BaseMarkerConfig.OpenOpacity
		return
	end
	local mine = owner == player.UserId
	local myClan = myClanId()
	local ally = not mine and myClan ~= nil and conf:GetAttribute("ClanId") == myClan
	local clan = conf:GetAttribute("Clan")
	local nm = tostring(conf:GetAttribute("Name") or "?")
	m.NameL.Text = if typeof(clan) == "string" and clan ~= "" then string.format("[%s] %s", clan, nm) else nm
	m.NameL.TextColor3 = if mine then C.You elseif ally then C.Ally else C.Name
	m.UserL.Text = (if mine then BaseMarkerConfig.Text.You .. "  " else "") .. "@" .. tostring(conf:GetAttribute("User") or "")
	m.Pill.BackgroundTransparency = 0.25
	local rt = BaseMarkerConfig.RankText(tonumber(conf:GetAttribute("Prestige")) or 0, RebirthConfig.TitleFor)
	m.Rank.Visible = rt ~= nil
	m.Rank.Text = rt or ""
	local nation = conf:GetAttribute("Nation")
	local src: any = nil
	if typeof(nation) == "string" then
		local okT, NT = pcall(function(): any
			return require(Shared.Util.NationTexture)
		end)
		src = if okT and NT and NT.Source then NT.Source(nation) else nil
	end
	if src then
		m.Flag.Image = src.Image
		m.Flag.ImageRectOffset = Vector2.new(src.Rect.X, src.Rect.Y)
		m.Flag.ImageRectSize = Vector2.new(src.Rect.W, src.Rect.H)
		m.Flag.BackgroundTransparency = 1
	else
		m.Flag.Image = ""
		m.Flag.BackgroundTransparency = 0
		m.Flag.BackgroundColor3 = C.NoFlag
	end
end

local function place(m: Marker)
	local pos = m.Conf:GetAttribute("Pos")
	if typeof(pos) == "Vector3" then
		m.Anchor.CFrame = CFrame.new(pos + Vector3.new(0, BaseMarkerConfig.HeightStuds, 0))
	end
end

local function add(conf: Instance)
	if markers[conf] or not conf:IsA("Configuration") then
		return
	end
	local m = build(conf)
	markers[conf] = m
	place(m)
	paint(m)
	layout(m, false)
	conf.AttributeChanged:Connect(function(k: string)
		if k == "Pos" then
			place(m)
		else
			paint(m)
		end
	end)
end

-- the 10 Hz step (all markers together): fade, size, compact
local function step()
	local cam = Workspace.CurrentCamera
	local c = player.Character
	local r = c and c:FindFirstChild("HumanoidRootPart")
	local me = if r and r:IsA("BasePart") then r.Position elseif cam then cam.CFrame.Position else nil
	if me == nil or cam == nil then
		return
	end
	local list = {}
	for conf, m in pairs(markers) do
		local pos = conf:GetAttribute("Pos")
		if typeof(pos) == "Vector3" then
			local flat = Vector3.new(pos.X - me.X, 0, pos.Z - me.Z).Magnitude
			local fade = BaseMarkerConfig.Fade(flat)
			m.Gui.Enabled = fade > 0 and (not m.Open or BaseMarkerConfig.ShowOpenBases)
			local sz = BaseMarkerConfig.SizeAt(flat)
			if m.Open then
				sz = sz * 0.8
			end
			m.Gui.Size = UDim2.fromOffset(math.floor(sz.X), math.floor(sz.Y))
			m.Pill.GroupTransparency = 1 - fade
			local v, onScreen = cam:WorldToViewportPoint(m.Anchor.Position)
			if onScreen and m.Gui.Enabled then
				table.insert(list, { Key = conf, Dist = flat, X = v.X, Y = v.Y })
			end
		end
	end
	local compact = BaseMarkerConfig.CompactSet(list)
	for conf, m in pairs(markers) do
		layout(m, compact[conf] == true)
	end
end

function BaseMarkerController.Init()
	if BaseMarkerConfig.Live.Enabled ~= true or not BaseMarkerConfig.LiveFor(player.UserId) then
		return -- OFF / not live for this viewer: no marker (the v123 sign and the map unchanged)
	end
	task.spawn(function()
		local root = ReplicatedStorage:WaitForChild(BaseMarkerConfig.FolderName, 120)
		if root == nil then
			warn("[WAR EMPIRE] BaseMarkerController: no marker data after 120 s")
			return
		end
		for _, conf in ipairs(root:GetChildren()) do
			add(conf)
		end
		root.ChildAdded:Connect(add)
		while true do
			task.wait(1 / BaseMarkerConfig.UpdateHz)
			pcall(step)
		end
	end)
end

return BaseMarkerController
