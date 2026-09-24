--!strict
--[[
	WorldLabel: the one way to make a floating world label (HUD v70 spec §5; CLAUDE.md "World labels").
	Server or client. Never yields.

	API
	  WorldLabel.Create(adornee, text, opts?) -> BillboardGui
	      Plain outlined text, no card. Box is stud-scaled (Size = UDim2.fromScale(studsW, studsH)); text is a fixed
	      TextSize clamped to 14-20 real px (never TextScaled). AlwaysOnTop = false, LightInfluence = 0,
	      MaxDistance <= WorldLabelConfig.MaxDistance (40). adornee: BasePart | Attachment | Model (a Model uses its
	      PrimaryPart, else its first BasePart). The label is parented last, so it replicates fully built.
	  WorldLabel.Surface(part, face, text, opts?) -> SurfaceGui
	      Painted sign on one face (PixelsPerStud, LightInfluence 0, MaxDistance <= 80, clipped to the face).
	      Text is sized from the face height unless opts.TextSize is given (canvas px, 14-100).
	  WorldLabel.SetText(gui, text, sub?, subColor?)   update in place; sub nil/"" hides the second line
	  WorldLabel.SetOwner(gui, userId?)                only that player sees it (nil = everyone)
	  WorldLabel.SetRole(bb, role?)                    "objective" | "contested" -> AlwaysOnTop; nil -> off
	  WorldLabel.StartOwnerFilter() -> boolean         CLIENT, once (WorldPromptController.Init); false on the server

	opts (all optional)
	  Name         instance name; keep pinned names ("WE_FlagBillboard", "WE_GateSign"). Default "WE_WorldLabel" /
	               "WE_WorldSign"
	  Sub          second, smaller line ("$850", "RAID IN PROGRESS")
	  Color        title colour (default white);  SubColor (default HudConfig.Colors.Muted)
	  TextSize     title px (billboard: clamped 14-20, default 16; the sub line is 14)
	  Studs        Vector2 box size in studs (default HudConfig.WorldLabels.Default StudsW x StudsH)
	  Offset       Vector3 StudsOffsetWorldSpace from the adornee (default: StudsAbove over a part's top)
	  MaxDistance  studs; clamped to the cap (billboard 40, surface 80)
	  OwnerUserId  owner-only label (see below)
	  Role         "objective" | "contested": the only labels allowed AlwaysOnTop (billboard only)
	  PixelsPerStud  surface only (default 40)
	  Parent       default: the resolved adornee (billboard) / the part (surface)

	Owner-only (no PlayerGui copies): the label stays in Workspace with attribute WE_LabelOwner = UserId and the
	CollectionService tag "WE_OwnerLabel" (names in WorldLabelConfig). Each client's StartOwnerFilter sets
	Enabled = false LOCALLY on tagged labels owned by someone else and restores the server's value when the label
	becomes theirs; server Enabled changes keep working for the owner. Cosmetic only: the text still replicates to
	every client, so never put anything secret in a label. Limit: if the server turns a label off while the filter
	is already hiding it (no change event), handing that label to this player shows it again, so hide
	owner-only labels by Destroy or text rather than Enabled.

	WorldLabelPolicy (server) applies the same caps to every BillboardGui in Workspace, inside plots and out, and
	honours WE_LabelRole for AlwaysOnTop.
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")

local Configs = script.Parent.Parent.Configs
local HudConfig = require(Configs.HudConfig)
local WorldLabelConfig = require(Configs.WorldLabelConfig)

export type Role = "objective" | "contested"
export type Options = {
	Name: string?,
	Sub: string?,
	Color: Color3?,
	SubColor: Color3?,
	TextSize: number?,
	Studs: Vector2?,
	Offset: Vector3?,
	MaxDistance: number?,
	OwnerUserId: number?,
	Role: Role?,
	PixelsPerStud: number?,
	Parent: Instance?,
}

local WorldLabel = {}

local LOOK = HudConfig.WorldLabels.Default
local INK = HudConfig.Colors.Ink
local WHITE = HudConfig.Colors.White
local MUTED = HudConfig.Colors.Muted
local ROLE_ATTR = WorldLabelConfig.RoleAttribute
local OWNER_ATTR = WorldLabelConfig.OwnerAttribute
local OWNER_TAG = WorldLabelConfig.OwnerTag

local function clampSize(v: number, lo: number, hi: number): number
	return math.clamp(math.floor(v + 0.5), lo, hi)
end

local function capDistance(want: number?, default: number, cap: number): number
	local d = if want ~= nil and want > 0 then want else default
	return math.min(d, cap)
end

local function resolveAdornee(adornee: Instance): Instance?
	if adornee:IsA("BasePart") or adornee:IsA("Attachment") then
		return adornee
	end
	if adornee:IsA("Model") then
		return adornee.PrimaryPart or adornee:FindFirstChildWhichIsA("BasePart", true)
	end
	return nil
end

local function makeLine(parent: Instance, name: string, text: string, size: number, color: Color3, font: Enum.Font): TextLabel
	local t = Instance.new("TextLabel")
	t.Name = name
	t.BackgroundTransparency = 1
	t.BorderSizePixel = 0
	t.AnchorPoint = Vector2.new(0.5, 0.5)
	t.Size = UDim2.new(1, 0, 0, size + WorldLabelConfig.LinePad)
	t.Position = UDim2.fromScale(0.5, 0.5)
	t.Font = font
	t.Text = text
	t.TextSize = size
	t.TextScaled = false
	t.TextWrapped = false
	t.TextColor3 = color
	t.TextStrokeColor3 = INK
	t.TextStrokeTransparency = 0
	t.TextXAlignment = Enum.TextXAlignment.Center
	t.TextYAlignment = Enum.TextYAlignment.Center
	t.Parent = parent
	return t
end

-- Lines are stacked in fixed px around the box centre, so they never overlap however small the stud box gets on
-- screen (the text overflows the box symmetrically; ClipsDescendants stays off on billboards).
local function layout(title: TextLabel, sub: TextLabel)
	local pad = WorldLabelConfig.LinePad
	local want = UDim2.fromScale(0.5, 0.5)
	if sub.Visible then
		local hT = title.TextSize + pad
		local hS = sub.TextSize + pad
		want = UDim2.new(0.5, 0, 0.5, -hS / 2)
		local subPos = UDim2.new(0.5, 0, 0.5, hT / 2)
		if sub.Position ~= subPos then
			sub.Position = subPos
		end
	end
	if title.Position ~= want then
		title.Position = want
	end
end

local function addLines(gui: LayerCollector, text: string, opts: Options, titleSize: number, subSize: number)
	local font = LOOK.Font
	local title = makeLine(gui, "Title", text, titleSize, opts.Color or WHITE, font)
	local subText = opts.Sub
	local sub = makeLine(gui, "Sub", subText or "", subSize, opts.SubColor or MUTED, font)
	sub.Visible = subText ~= nil and subText ~= ""
	layout(title, sub)
end

function WorldLabel.SetOwner(gui: LayerCollector, userId: number?)
	if userId ~= nil and userId ~= 0 then
		if gui:GetAttribute(OWNER_ATTR) ~= userId then
			gui:SetAttribute(OWNER_ATTR, userId)
		end
		CollectionService:AddTag(gui, OWNER_TAG)
	else
		-- attribute first: a watching client restores the label on the attribute change
		if gui:GetAttribute(OWNER_ATTR) ~= nil then
			gui:SetAttribute(OWNER_ATTR, nil)
		end
		CollectionService:RemoveTag(gui, OWNER_TAG)
	end
end

function WorldLabel.SetRole(bb: BillboardGui, role: Role?)
	-- attribute before AlwaysOnTop: WorldLabelPolicy's AlwaysOnTop watcher reads the role
	if bb:GetAttribute(ROLE_ATTR) ~= role then
		bb:SetAttribute(ROLE_ATTR, role)
	end
	local top = role ~= nil and WorldLabelConfig.AlwaysOnTopRoles[role] == true
	if bb.AlwaysOnTop ~= top then
		bb.AlwaysOnTop = top
	end
end

function WorldLabel.SetText(gui: LayerCollector, text: string, sub: string?, subColor: Color3?)
	local title = gui:FindFirstChild("Title")
	local subLine = gui:FindFirstChild("Sub")
	if not (title and title:IsA("TextLabel") and subLine and subLine:IsA("TextLabel")) then
		return
	end
	if title.Text ~= text then
		title.Text = text
	end
	local show = sub ~= nil and sub ~= ""
	if show and sub ~= nil and subLine.Text ~= sub then
		subLine.Text = sub
	end
	if subColor ~= nil and subLine.TextColor3 ~= subColor then
		subLine.TextColor3 = subColor
	end
	if subLine.Visible ~= show then
		subLine.Visible = show
	end
	layout(title, subLine)
end

function WorldLabel.Create(adornee: Instance, text: string, opts: Options?): BillboardGui
	local o: Options = opts or {}
	local target = resolveAdornee(adornee)
	if target == nil then
		warn("[WorldLabel] no BasePart/Attachment to adorn for " .. adornee:GetFullName())
	end
	local studs = o.Studs or Vector2.new(LOOK.StudsW, LOOK.StudsH)
	local above = WorldLabelConfig.StudsAbove
	local offset: Vector3 = o.Offset
		or (if target ~= nil and target:IsA("BasePart") then Vector3.new(0, target.Size.Y * 0.5 + above, 0) else Vector3.new(0, above, 0))
	local minT, maxT = WorldLabelConfig.MinTextSize, WorldLabelConfig.MaxTextSize
	local titleSize = clampSize(o.TextSize or WorldLabelConfig.TextSize, minT, maxT)
	local subSize = math.min(clampSize(WorldLabelConfig.SubTextSize, minT, maxT), titleSize)

	local bb = Instance.new("BillboardGui")
	bb.Name = o.Name or "WE_WorldLabel"
	bb.Size = UDim2.fromScale(studs.X, studs.Y)
	bb.StudsOffsetWorldSpace = offset
	bb.MaxDistance = capDistance(o.MaxDistance, LOOK.MaxDistance, WorldLabelConfig.MaxDistance)
	bb.LightInfluence = 0
	bb.ClipsDescendants = false
	bb.Active = false
	bb.AlwaysOnTop = false
	if target ~= nil then
		bb.Adornee = target
	end
	addLines(bb, text, o, titleSize, subSize)
	if o.Role ~= nil then
		WorldLabel.SetRole(bb, o.Role)
	end
	if o.OwnerUserId ~= nil then
		WorldLabel.SetOwner(bb, o.OwnerUserId)
	end
	bb.Parent = o.Parent or target or adornee
	return bb
end

local function faceSize(part: BasePart, face: Enum.NormalId): Vector2
	local s = part.Size
	if face == Enum.NormalId.Left or face == Enum.NormalId.Right then
		return Vector2.new(s.Z, s.Y)
	elseif face == Enum.NormalId.Top or face == Enum.NormalId.Bottom then
		return Vector2.new(s.X, s.Z)
	end
	return Vector2.new(s.X, s.Y)
end

function WorldLabel.Surface(part: BasePart, face: Enum.NormalId, text: string, opts: Options?): SurfaceGui
	local o: Options = opts or {}
	local pps = if o.PixelsPerStud ~= nil and o.PixelsPerStud > 0 then o.PixelsPerStud else WorldLabelConfig.SurfacePixelsPerStud
	local faceH = faceSize(part, face).Y * pps
	local hasSub = o.Sub ~= nil and o.Sub ~= ""
	local minT, maxT = WorldLabelConfig.MinTextSize, WorldLabelConfig.SurfaceMaxTextSize
	local titleSize = clampSize(o.TextSize or faceH * (if hasSub then 0.42 else 0.55), minT, maxT)
	local subSize = math.min(clampSize(faceH * 0.28, minT, maxT), titleSize)

	local sg = Instance.new("SurfaceGui")
	sg.Name = o.Name or "WE_WorldSign"
	sg.Face = face
	sg.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	sg.PixelsPerStud = pps
	sg.MaxDistance = capDistance(o.MaxDistance, WorldLabelConfig.SurfaceDefaultMaxDistance, WorldLabelConfig.SurfaceMaxDistance)
	sg.LightInfluence = 0
	sg.ClipsDescendants = true
	sg.AlwaysOnTop = false
	sg.Adornee = part
	addLines(sg, text, o, titleSize, subSize)
	if o.OwnerUserId ~= nil then
		WorldLabel.SetOwner(sg, o.OwnerUserId)
	end
	sg.Parent = o.Parent or part
	return sg
end

-- ── client: owner-only filter ───────────────────────────────────────────────────────────────────────────────
local filterStarted = false
local watched: { [LayerCollector]: boolean } = setmetatable({} :: any, { __mode = "k" })
local serverEnabled: { [LayerCollector]: boolean } = setmetatable({} :: any, { __mode = "k" })
local forced: { [LayerCollector]: boolean } = setmetatable({} :: any, { __mode = "k" }) -- value this client wrote

local function ownerOf(gui: Instance): number?
	local v = gui:GetAttribute(OWNER_ATTR)
	if type(v) == "number" and v ~= 0 then
		return v
	end
	return nil
end

local function applyFilter(gui: LayerCollector, me: number)
	local owner = ownerOf(gui)
	if owner ~= nil and owner ~= me then
		if forced[gui] == nil then
			serverEnabled[gui] = gui.Enabled
		end
		forced[gui] = false
		if gui.Enabled then
			gui.Enabled = false
		end
	elseif forced[gui] ~= nil then
		forced[gui] = nil
		local want = serverEnabled[gui]
		if want ~= nil and gui.Enabled ~= want then
			gui.Enabled = want
		end
	end
end

local function watch(inst: Instance, me: number)
	if not (inst:IsA("BillboardGui") or inst:IsA("SurfaceGui")) then
		return
	end
	local gui = inst :: LayerCollector
	if watched[gui] then
		applyFilter(gui, me)
		return
	end
	watched[gui] = true
	serverEnabled[gui] = gui.Enabled
	gui:GetAttributeChangedSignal(OWNER_ATTR):Connect(function()
		applyFilter(gui, me)
	end)
	gui:GetPropertyChangedSignal("Enabled"):Connect(function()
		local f = forced[gui]
		if f ~= nil and gui.Enabled == f then
			return -- this client's own write (signals are deferred, so no re-entrancy flag)
		end
		serverEnabled[gui] = gui.Enabled
		applyFilter(gui, me)
	end)
	applyFilter(gui, me)
end

function WorldLabel.StartOwnerFilter(): boolean
	if filterStarted then
		return true
	end
	local lp = Players.LocalPlayer
	if lp == nil then
		return false
	end
	filterStarted = true
	local me = lp.UserId
	CollectionService:GetInstanceAddedSignal(OWNER_TAG):Connect(function(inst: Instance)
		watch(inst, me)
	end)
	for _, inst in ipairs(CollectionService:GetTagged(OWNER_TAG)) do
		watch(inst, me)
	end
	return true
end

return WorldLabel
