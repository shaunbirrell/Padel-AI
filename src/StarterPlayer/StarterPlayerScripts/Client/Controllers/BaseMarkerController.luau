--!strict
--[[
	claude-bud JOB 40 part E (2026-09-30): the BASE OWNER MARKERS (BaseMarkerConfig), client only. One BillboardGui per
	plot from ReplicatedStorage.WE_BaseMarkers (BaseMarkerService's data), adorned to a local invisible anchor part over
	the plot centre, AlwaysOnTop (the ONE documented world-label exception).

	JOB 40E FIX (the owner's phone screenshots: too big, too low, empty grey tags, "VETERAN" in the view):
	  * a SLIM pill sized to its own text: a small nation flag (NationTexture; an army-green chip without one) + the
	    short name, 14 px real at scale 1; the @handle and a short "R3" appear only inside DetailStuds. "YOU" on the own
	    base; a clan-mate's name in the ally blue. No rebirth title, no "OPEN BASE": a base without a live owner and a
	    name has NO tag at all (BaseMarkerConfig.HasTag).
	  * one 10 Hz step for all tags together: the anchor floats HeightAt(dist) over the base (150-260 studs, in the sky),
	    the pill scales ScaleAt(dist) (1.0 far .. 1.2 near, a UIScale), fades in near the base (the v123 sign takes over
	    inside 60 studs) and out far away, and VisibleSet keeps the own tag + the nearest MaxShown rivals with no two
	    overlapping on screen (the farther one hides).
	Only for a viewer BaseMarkerConfig is live for. Nothing per frame; texts are measured on data changes only.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local TextService = game:GetService("TextService")

local BaseMarkerController = {}

local Shared = ReplicatedStorage:WaitForChild("Shared", 60)
if not Shared then
	warn("[WAR EMPIRE] BaseMarkerController: no ReplicatedStorage.Shared after 60 s; not started")
	return BaseMarkerController
end
local BaseMarkerConfig = require(Shared.Configs.BaseMarkerConfig)

local B = BaseMarkerConfig
local C = B.Colors
local player = Players.LocalPlayer
local NAME_FONT = Enum.Font.GothamBold
local USER_FONT = Enum.Font.Gotham

type Marker = {
	Conf: Instance,
	Anchor: Part,
	Gui: BillboardGui,
	Pill: CanvasGroup,
	Scale: UIScale,
	Flag: ImageLabel,
	NameL: TextLabel,
	UserL: TextLabel,
	Rank: TextLabel,
	Has: boolean, -- a live owner + a name: the only case that draws
	Mine: boolean,
	W: number, -- the slim pill width at scale 1
	WDetail: number, -- the width with the @handle / R line
	Detail: boolean,
	Height: number, -- the anchor's current height over the plot
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
	local root = ReplicatedStorage:FindFirstChild(B.FolderName)
	for _, c in ipairs(if root then root:GetChildren() else {}) do
		if c:GetAttribute("Owner") == player.UserId then
			local id = c:GetAttribute("ClanId")
			return if typeof(id) == "string" then id else nil
		end
	end
	return nil
end

local function textW(text: string, size: number, font: Enum.Font): number
	local ok, v = pcall(function()
		return TextService:GetTextSize(text, size, font, Vector2.new(1000, 100))
	end)
	return if ok then (v :: Vector2).X else #text * size * 0.55
end

local function label(parent: Instance, name: string, font: Enum.Font, color: Color3, size: number): TextLabel
	local t = Instance.new("TextLabel")
	t.Name = name
	t.BackgroundTransparency = 1
	t.Font = font
	t.TextSize = size
	t.TextColor3 = color
	t.TextXAlignment = Enum.TextXAlignment.Left
	t.TextYAlignment = Enum.TextYAlignment.Center
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
	g.MaxDistance = B.MaxDistance
	g.LightInfluence = 0
	g.Size = UDim2.fromOffset(100, B.PillHeight)
	g.Adornee = anchor
	g.ResetOnSpawn = false
	g.Enabled = false -- nothing shows until the data says there is a live owner with a name
	g.Parent = anchor
	local pill = Instance.new("CanvasGroup") -- one GroupTransparency fades the whole pill
	pill.Name = "Pill"
	pill.AnchorPoint = Vector2.new(0.5, 0.5)
	pill.Position = UDim2.fromScale(0.5, 0.5)
	pill.Size = UDim2.fromOffset(100, B.PillHeight)
	pill.BackgroundColor3 = C.Plate
	pill.BackgroundTransparency = 0.3
	pill.BorderSizePixel = 0
	pill.Parent = g
	local scale = Instance.new("UIScale")
	scale.Parent = pill
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, math.floor(B.PillHeight / 2))
	corner.Parent = pill
	local stroke = Instance.new("UIStroke")
	stroke.Color = C.Stroke
	stroke.Thickness = 1
	stroke.Parent = pill
	local fh = B.PillHeight - 10
	local flag = Instance.new("ImageLabel")
	flag.Name = "Flag"
	flag.Position = UDim2.fromOffset(B.PadPx, 5)
	flag.Size = UDim2.fromOffset(math.floor(fh * 4 / 3), fh)
	flag.BackgroundColor3 = C.NoFlag
	flag.BorderSizePixel = 0
	flag.ScaleType = Enum.ScaleType.Stretch
	flag.Parent = pill
	local fc = Instance.new("UICorner")
	fc.CornerRadius = UDim.new(0, 3)
	fc.Parent = flag
	local nameL = label(pill, "Name", NAME_FONT, C.Name, B.NameTextSize)
	local userL = label(pill, "User", USER_FONT, C.Muted, B.UserTextSize)
	local rank = label(pill, "Rank", NAME_FONT, C.Rank, B.UserTextSize)
	rank.TextXAlignment = Enum.TextXAlignment.Right
	return {
		Conf = conf, Anchor = anchor, Gui = g, Pill = pill, Scale = scale, Flag = flag, NameL = nameL, UserL = userL,
		Rank = rank, Has = false, Mine = false, W = 100, WDetail = 100, Detail = false, Height = B.HeightStuds,
	}
end

-- lay the pill out at scale 1: one line (flag + name) or, near, two (+ @handle and R<n>)
local function layout(m: Marker, detail: boolean)
	m.Detail = detail
	local h = if detail then B.DetailHeight else B.PillHeight
	local w = if detail then m.WDetail else m.W
	local fh = B.PillHeight - 10
	local x0 = B.PadPx + math.floor(fh * 4 / 3) + 5
	m.Pill.Size = UDim2.fromOffset(w, h)
	m.NameL.Position = UDim2.fromOffset(x0, 2)
	m.NameL.Size = UDim2.new(1, -(x0 + B.PadPx), 0, B.PillHeight - 4)
	m.UserL.Visible = detail and not m.Mine
	m.Rank.Visible = detail and m.Rank.Text ~= ""
	m.UserL.Position = UDim2.fromOffset(B.PadPx, B.PillHeight - 2)
	m.UserL.Size = UDim2.new(1, -(B.PadPx * 2 + 30), 0, h - B.PillHeight)
	m.Rank.Position = UDim2.new(1, -(B.PadPx + 30), 0, B.PillHeight - 2)
	m.Rank.Size = UDim2.fromOffset(30, h - B.PillHeight)
end

local function paint(m: Marker)
	local conf = m.Conf
	local owner = conf:GetAttribute("Owner")
	local nm = conf:GetAttribute("Name")
	m.Has = B.HasTag(owner, nm)
	if not m.Has then
		m.Gui.Enabled = false -- no live owner / no name yet: never a grey or empty tag
		return
	end
	local mine = owner == player.UserId
	m.Mine = mine
	local myClan = myClanId()
	local ally = not mine and myClan ~= nil and conf:GetAttribute("ClanId") == myClan
	local clan = conf:GetAttribute("Clan")
	local name = tostring(nm)
	local text = if mine then B.Text.You elseif typeof(clan) == "string" and clan ~= "" then string.format("[%s] %s", clan, name) else name
	m.NameL.Text = text
	m.NameL.TextColor3 = if mine then C.You elseif ally then C.Ally else C.Name
	local user = "@" .. tostring(conf:GetAttribute("User") or "")
	m.UserL.Text = user
	local rt = B.RankText(tonumber(conf:GetAttribute("Prestige")) or 0)
	m.Rank.Text = rt or ""
	local fh = B.PillHeight - 10
	local x0 = B.PadPx + math.floor(fh * 4 / 3) + 5
	local nameW = math.min(B.MaxNameWidth, textW(text, B.NameTextSize, NAME_FONT))
	m.W = math.ceil(x0 + nameW + B.PadPx + 2)
	local lineW = B.PadPx + math.min(B.MaxNameWidth, textW(user, B.UserTextSize, USER_FONT)) + 6 + (if rt then 30 else 0) + B.PadPx
	m.WDetail = math.ceil(math.max(m.W, if mine then 0 else lineW))
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
	layout(m, m.Detail)
end

local function place(m: Marker, height: number)
	local pos = m.Conf:GetAttribute("Pos")
	if typeof(pos) == "Vector3" then
		m.Height = height
		m.Anchor.CFrame = CFrame.new(pos + Vector3.new(0, height, 0))
	end
end

local function add(conf: Instance)
	if markers[conf] or not conf:IsA("Configuration") then
		return
	end
	local m = build(conf)
	markers[conf] = m
	place(m, B.HeightStuds)
	paint(m)
	conf.AttributeChanged:Connect(function(k: string)
		if k == "Pos" then
			place(m, m.Height)
		else
			paint(m)
		end
	end)
end

-- the 10 Hz step (all tags together): height, scale, fade, then which ones show
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
		if m.Has and typeof(pos) == "Vector3" then
			local flat = Vector3.new(pos.X - me.X, 0, pos.Z - me.Z).Magnitude
			local hgt = B.HeightAt(flat)
			if math.abs(hgt - m.Height) > 1 then
				place(m, hgt)
			end
			local detail = flat <= B.DetailStuds
			if detail ~= m.Detail then
				layout(m, detail)
			end
			local s = B.ScaleAt(flat)
			local w, h = m.Pill.Size.X.Offset * s, m.Pill.Size.Y.Offset * s
			m.Scale.Scale = s
			m.Gui.Size = UDim2.fromOffset(math.ceil(w), math.ceil(h))
			local fade = B.Fade(flat)
			m.Pill.GroupTransparency = 1 - fade
			local v, onScreen = cam:WorldToViewportPoint(m.Anchor.Position)
			if fade > 0 and onScreen then
				table.insert(list, { Key = conf, Dist = flat, X = v.X, Y = v.Y, W = w, H = h, Mine = m.Mine })
			else
				m.Gui.Enabled = false
			end
		else
			m.Gui.Enabled = false
		end
	end
	local show = B.VisibleSet(list)
	for _, t in ipairs(list) do
		markers[t.Key].Gui.Enabled = show[t.Key] == true
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
		root.ChildRemoved:Connect(function(conf: Instance)
			local m = markers[conf]
			if m then
				m.Anchor:Destroy()
				markers[conf] = nil
			end
		end)
		while true do
			task.wait(1 / BaseMarkerConfig.UpdateHz)
			pcall(step)
		end
	end)
end

return BaseMarkerController
