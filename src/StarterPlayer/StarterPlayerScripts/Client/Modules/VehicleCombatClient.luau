--!strict
--[[
	VehicleCombatClient (W2 CC-2): the client half of vehicle HP. Display only — the server (VehicleHealth) owns HP
	and writes WE_HP / WE_MaxHP (≤ 10 Hz) and WE_Destroyed on the vehicle Model; nothing here is sent back.
	Numbers: VehicleCombatConfig.Ui.

	  * Occupant HUD bar: while Humanoid.SeatPart is in a vehicle with WE_MaxHP > 0. 230 × 10 real px in its own
	    ScreenGui (no UIScale). Touch: HudLayout top-centre stack at Ui.HudBar.TouchStackOrder (24, right above the
	    SPD pill at 25). Desktop / gamepad: bottom-right, just above the SPD pill. Gold frame on premium vehicles;
	    the fill flashes red below Ui.HudBar.LowFrac (one looping tween, no Lua per frame).
	  * Over-vehicle bars: client BillboardGuis (PlayerGui, Adornee = Chassis) — stud-scaled, never AlwaysOnTop,
	    MaxDistance ≤ 40, no text. Shown Ui.OverBar.ShowSeconds after that vehicle's WE_HP drops, and on your own
	    parked vehicle while HP < MaxHP; never on the vehicle you sit in; a pool of MaxShown (3): the most recent win.
	  * Wreck: WE_Destroyed → one burst from a pooled Attachment + ParticleEmitter under Workspace.Terrain (Emit only,
	    no parts) and AudioController.Play("Explosion.Large", chassis) (false / silent until that key exists). Once per
	    model.
	  * Phones: no RenderStepped / Heartbeat work. Everything runs from attribute / seat / tag signals, and repaints are
	    coalesced to Ui.RefreshHz (10 Hz). Safe under StreamingEnabled (vehicles come and go with their tag signals;
	    no WaitForChild without a timeout) and headless (every optional module is required in pcall).
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared", 60)
local Constants = require(Shared.Constants)
local VehicleCombatConfig = require(Shared.Configs.VehicleCombatConfig)

local UI = VehicleCombatConfig.Ui
local HB = UI.HudBar
local OB = UI.OverBar
local REFRESH_SECONDS = 1 / math.max(1, UI.RefreshHz)

local VehicleCombatClient = {}

type Info = {
	Conns: { RBXScriptConnection },
	LastHP: number?,
	ShowUntil: number,
	Wrecked: boolean,
}
type Candidate = { Model: Model, Chassis: BasePart, Frac: number, Rank: number }

local COLOR_BG = Color3.fromRGB(16, 18, 22)
local COLOR_FILL = Color3.fromRGB(90, 196, 235) -- "armor" cyan: not mistaken for the green capture bar above it
local COLOR_LOW = Color3.fromRGB(200, 40, 36)
local COLOR_LOW_FLASH = Color3.fromRGB(255, 120, 96)
local COLOR_STROKE = Color3.fromRGB(0, 0, 0)
local COLOR_GOLD = Color3.fromRGB(235, 192, 64)
local WRECK_EMIT = 24

local started = false
local tracked: { [Model]: Info } = {}
local seated: Model? = nil
local hudGui: ScreenGui? = nil
local hudBar: Frame? = nil
local hudFill: Frame? = nil
local hudStroke: UIStroke? = nil
local lowTween: Tween? = nil
local lowOn = false
local stacked = false
local overPool: { BillboardGui } = {}
local overFill: { [BillboardGui]: Frame } = {}
local burstAtt: Attachment? = nil
local burstEmitter: ParticleEmitter? = nil
local refreshQueued = false
local lastRefreshAt = -math.huge
local expiryAt = math.huge -- earliest pending over-bar expiry already scheduled
local humConn: RBXScriptConnection? = nil
local stats = { Refreshes = 0, Bursts = 0, OverShown = 0, HudShown = false }

local function now(): number
	return os.clock()
end

local function localPlayer(): Player?
	return Players.LocalPlayer
end

-- optional sibling module (HudLayout / AudioController): nil when missing or failing (headless tests)
local siblingCache: { [string]: any } = {}
local function sibling(name: string): any
	local cached = siblingCache[name]
	if cached ~= nil then
		return if cached == false then nil else cached
	end
	local ok, m = pcall(function(): any
		local here: any = script
		local mod = here.Parent and here.Parent:FindFirstChild(name)
		if mod and mod:IsA("ModuleScript") then
			local req: any = require
			return req(mod)
		end
		return nil
	end)
	local value = if ok and typeof(m) == "table" then m else false
	siblingCache[name] = value
	return if value == false then nil else value
end

local function preferredTouch(): boolean
	local ok, v = pcall(function(): any
		return (UserInputService :: any).PreferredInput
	end)
	return ok and typeof(v) == "EnumItem" and (v :: EnumItem).Name == "Touch"
end

-- same switch as VehicleDriveClient's SPD pill (touch → the top-centre stack)
local function isTouch(): boolean
	return UserInputService.TouchEnabled == true or preferredTouch()
end

local function num(v: any): number?
	local n = tonumber(v)
	if n == nil or n ~= n then
		return nil
	end
	return n
end

local function chassisOf(model: Model): BasePart?
	local p = model.PrimaryPart
	if p then
		return p
	end
	local c = model:FindFirstChild("Chassis")
	return if c and c:IsA("BasePart") then c else nil
end

-- (fraction 0..1, has HP) from the replicated attributes
local function hpFrac(model: Model): (number, boolean)
	local maxHP = num(model:GetAttribute("WE_MaxHP"))
	if maxHP == nil or maxHP <= 0 then
		return 0, false
	end
	if model:GetAttribute("WE_Destroyed") == true then
		return 0, true
	end
	local hp = num(model:GetAttribute("WE_HP")) or maxHP
	return math.clamp(hp / maxHP, 0, 1), true
end

-- the vehicle a seat belongs to: the nearest ancestor tagged WE_Vehicle, else one carrying WE_MaxHP / VehicleId
local function vehicleOf(inst: Instance?): Model?
	local cur: Instance? = inst
	while cur ~= nil and cur ~= Workspace do
		if cur:IsA("Model") then
			if
				CollectionService:HasTag(cur, Constants.Tags.Vehicle)
				or cur:GetAttribute("WE_MaxHP") ~= nil
				or cur:GetAttribute("VehicleId") ~= nil
			then
				return cur
			end
		end
		cur = cur.Parent
	end
	return nil
end

-- ── HUD bar ─────────────────────────────────────────────────────────────────────────────────────

local function corner(parent: Instance, r: number)
	local c = Instance.new("UICorner")
	c.CornerRadius = UDim.new(0, r)
	c.Parent = parent
end

local function placeHud()
	local bar = hudBar
	if bar == nil then
		return
	end
	local HL = if isTouch() then sibling("HudLayout") else nil
	if HL and typeof(HL.RegisterTopStack) == "function" then
		if stacked then
			return
		end
		bar.AnchorPoint = Vector2.new(0.5, 0)
		bar.Position = UDim2.new(0.5, 0, 0, 0)
		local ok = pcall(HL.RegisterTopStack, "VehicleHP", bar, HB.TouchStackOrder, { Space = "Screen" })
		if ok then
			stacked = true
			return
		end
	end
	if stacked then
		stacked = false
		local L = sibling("HudLayout")
		if L and typeof(L.UnregisterTopStack) == "function" then
			pcall(L.UnregisterTopStack, "VehicleHP")
		end
	end
	bar.AnchorPoint = Vector2.new(1, 1)
	bar.Position = UDim2.new(1, -HB.DesktopRight, 1, -HB.DesktopBottom)
end

local function ensureHud(): Frame?
	local bar = hudBar
	if bar and bar.Parent then
		return bar
	end
	local lp = localPlayer()
	local pg = if lp then lp:FindFirstChildOfClass("PlayerGui") else nil
	if pg == nil then
		return nil
	end
	local gui = Instance.new("ScreenGui")
	gui.Name = "WE_VehicleHP"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = false
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.DisplayOrder = 56 -- with the SPD pill's gui (above the dock 55, below panels 60)
	gui.Enabled = true
	local b = Instance.new("Frame")
	b.Name = "WE_VehicleHPBar"
	b.Size = UDim2.fromOffset(HB.Width, HB.Height)
	b.BackgroundColor3 = COLOR_BG
	b.BackgroundTransparency = 0.2
	b.BorderSizePixel = 0
	b.Active = false
	b.Visible = false
	b.Parent = gui
	corner(b, math.floor(HB.Height / 2))
	local stroke = Instance.new("UIStroke")
	stroke.Color = COLOR_STROKE
	stroke.Transparency = 0.35
	stroke.Thickness = 1
	stroke.Parent = b
	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.Size = UDim2.fromScale(1, 1)
	fill.BackgroundColor3 = COLOR_FILL
	fill.BorderSizePixel = 0
	fill.Active = false
	fill.Parent = b
	corner(fill, math.floor(HB.Height / 2))
	gui.Parent = pg
	hudGui = gui
	hudBar = b
	hudFill = fill
	hudStroke = stroke
	stacked = false
	placeHud()
	return b
end

local function setLow(on: boolean)
	local fill = hudFill
	if fill == nil or on == lowOn then
		return
	end
	lowOn = on
	local tw = lowTween
	if tw then
		tw:Cancel()
		lowTween = nil
	end
	if on then
		fill.BackgroundColor3 = COLOR_LOW
		local ok, made = pcall(function(): Tween
			return TweenService:Create(
				fill,
				TweenInfo.new(0.35, Enum.EasingStyle.Linear, Enum.EasingDirection.InOut, -1, true),
				{ BackgroundColor3 = COLOR_LOW_FLASH }
			)
		end)
		if ok and made then
			lowTween = made
			made:Play()
		end
	else
		fill.BackgroundColor3 = COLOR_FILL
	end
end

local function paintHud()
	local model = seated
	local frac, has = 0, false
	if model then
		frac, has = hpFrac(model)
	end
	if not has then
		local bar = hudBar
		if bar and bar.Visible then
			bar.Visible = false
		end
		setLow(false)
		stats.HudShown = false
		return
	end
	local bar = ensureHud()
	local fill = hudFill
	if bar == nil or fill == nil or model == nil then
		return
	end
	fill.Size = UDim2.fromScale(frac, 1)
	local premium = model:GetAttribute("WE_Premium") == true
	local stroke = hudStroke
	if stroke then
		stroke.Color = if premium then COLOR_GOLD else COLOR_STROKE
		stroke.Thickness = if premium then 2 else 1
		stroke.Transparency = if premium then 0 else 0.35
	end
	setLow(frac < HB.LowFrac)
	if not bar.Visible then
		bar.Visible = true
	end
	stats.HudShown = true
end

-- ── over-vehicle bars ───────────────────────────────────────────────────────────────────────────

local function overGui(i: number): BillboardGui?
	local g = overPool[i]
	if g and g.Parent then
		return g
	end
	local lp = localPlayer()
	local pg = if lp then lp:FindFirstChildOfClass("PlayerGui") else nil
	if pg == nil then
		return nil
	end
	local bb = Instance.new("BillboardGui")
	bb.Name = "WE_VehicleHPOver"
	bb.Size = UDim2.fromScale(OB.WidthStuds, OB.HeightStuds) -- studs: shrinks with distance
	bb.AlwaysOnTop = false
	bb.LightInfluence = 0
	bb.MaxDistance = math.min(40, OB.MaxDistance)
	bb.ResetOnSpawn = false
	bb.Enabled = false
	local back = Instance.new("Frame")
	back.Name = "Back"
	back.Size = UDim2.fromScale(1, 1)
	back.BackgroundColor3 = COLOR_BG
	back.BackgroundTransparency = 0.25
	back.BorderSizePixel = 0
	back.Parent = bb
	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.Size = UDim2.fromScale(1, 1)
	fill.BackgroundColor3 = COLOR_FILL
	fill.BorderSizePixel = 0
	fill.Parent = back
	bb.Parent = pg
	overPool[i] = bb
	overFill[bb] = fill
	return bb
end

local function labelHeight(model: Model, chassis: BasePart): number
	local ly = num(model:GetAttribute("WE_LabelY"))
	if ly ~= nil and ly > 0 then
		return math.clamp(ly - 0.75, 1, 30) -- just under the owner nameplate (VehicleDriveClient, at WE_LabelY)
	end
	return chassis.Size.Y * 0.5 + 2
end

local function scheduleExpiry(at: number)
	if at >= expiryAt then
		return
	end
	expiryAt = at
	task.delay(math.max(0, at - now()) + 0.05, function()
		if expiryAt == at then
			expiryAt = math.huge
		end
		VehicleCombatClient._Refresh()
	end)
end

local function paintOver()
	local lp = localPlayer()
	local myId = if lp then lp.UserId else -1
	local t = now()
	local list: { Candidate } = {}
	local nextExpiry = math.huge
	for model, info in pairs(tracked) do
		if model ~= seated and model.Parent ~= nil and not info.Wrecked then
			local chassis = chassisOf(model)
			local frac, has = hpFrac(model)
			if chassis and has then
				local recent = info.ShowUntil > t
				local ownHurt = model:GetAttribute("OwnerUserId") == myId and frac < 0.999
				if recent or ownHurt then
					table.insert(list, { Model = model, Chassis = chassis, Frac = frac, Rank = if recent then info.ShowUntil else 0 })
				end
				if recent and info.ShowUntil < nextExpiry then
					nextExpiry = info.ShowUntil
				end
			end
		end
	end
	table.sort(list, function(a: Candidate, b: Candidate): boolean
		return a.Rank > b.Rank
	end)
	local shown = 0
	for i = 1, OB.MaxShown do
		local c = list[i]
		local g = if c or overPool[i] then overGui(i) else nil
		if g then
			if c then
				g.Adornee = c.Chassis
				g.StudsOffsetWorldSpace = Vector3.new(0, labelHeight(c.Model, c.Chassis), 0)
				local fill = overFill[g]
				if fill then
					fill.Size = UDim2.fromScale(c.Frac, 1)
					fill.BackgroundColor3 = if c.Frac < HB.LowFrac then COLOR_LOW else COLOR_FILL
				end
				g.Enabled = true
				shown += 1
			elseif g.Enabled or (g :: any).Adornee ~= nil then
				g.Enabled = false;
				(g :: any).Adornee = nil
			end
		end
	end
	stats.OverShown = shown
	if nextExpiry < math.huge then
		scheduleExpiry(nextExpiry)
	end
end

-- ── wreck burst ─────────────────────────────────────────────────────────────────────────────────

local function ensureBurst(): ParticleEmitter?
	local em = burstEmitter
	local att = burstAtt
	if em and att and att.Parent then
		return em
	end
	local terrain = Workspace:FindFirstChildOfClass("Terrain")
	if terrain == nil then
		return nil
	end
	local a = Instance.new("Attachment")
	a.Name = "WE_VehicleWreckFx"
	local e = Instance.new("ParticleEmitter")
	e.Name = "Burst"
	e.Rate = 0
	e.Enabled = true
	e.Lifetime = NumberRange.new(0.6, 1.3)
	e.Speed = NumberRange.new(8, 22)
	e.SpreadAngle = Vector2.new(180, 180)
	e.Drag = 3
	e.LightEmission = 0.6
	e.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 2.5), NumberSequenceKeypoint.new(1, 6) })
	e.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.1), NumberSequenceKeypoint.new(1, 1) })
	e.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 196, 96)),
		ColorSequenceKeypoint.new(0.4, Color3.fromRGB(230, 90, 40)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(40, 36, 34)),
	})
	e.Parent = a
	a.Parent = terrain
	burstAtt = a
	burstEmitter = e
	return e
end

local function wreckBurst(model: Model)
	local info = tracked[model]
	if info == nil or info.Wrecked then
		return
	end
	info.Wrecked = true
	local chassis = chassisOf(model)
	if chassis == nil then
		return
	end
	local em = ensureBurst()
	local att = burstAtt
	if em and att then
		pcall(function()
			att.WorldPosition = chassis.Position
			em:Emit(WRECK_EMIT)
		end)
		stats.Bursts += 1
	end
	local audio = sibling("AudioController")
	if audio and typeof(audio.Play) == "function" then
		pcall(audio.Play, "Explosion.Large", chassis)
	end
end

-- ── refresh scheduling (≤ Ui.RefreshHz) ────────────────────────────────────────────────────────

function VehicleCombatClient._Refresh()
	lastRefreshAt = now()
	stats.Refreshes += 1
	pcall(paintHud)
	pcall(paintOver)
end

local function requestRefresh()
	if refreshQueued then
		return
	end
	refreshQueued = true
	local wait = math.max(0, lastRefreshAt + REFRESH_SECONDS - now())
	task.delay(wait, function()
		refreshQueued = false
		VehicleCombatClient._Refresh()
	end)
end

-- ── tracking ────────────────────────────────────────────────────────────────────────────────────

local function untrack(model: Model)
	local info = tracked[model]
	if info == nil then
		return
	end
	tracked[model] = nil
	for _, c in ipairs(info.Conns) do
		c:Disconnect()
	end
	table.clear(info.Conns)
	requestRefresh()
end

local function track(inst: Instance)
	if not inst:IsA("Model") or tracked[inst] ~= nil then
		return
	end
	local model: Model = inst
	local info: Info = { Conns = {}, LastHP = num(model:GetAttribute("WE_HP")), ShowUntil = -math.huge, Wrecked = false }
	tracked[model] = info
	table.insert(
		info.Conns,
		model:GetAttributeChangedSignal("WE_HP"):Connect(function()
			local hp = num(model:GetAttribute("WE_HP"))
			local last = info.LastHP
			if hp ~= nil and last ~= nil and hp < last - 0.01 then
				info.ShowUntil = now() + OB.ShowSeconds
			end
			info.LastHP = hp
			requestRefresh()
		end)
	)
	table.insert(info.Conns, model:GetAttributeChangedSignal("WE_MaxHP"):Connect(requestRefresh))
	table.insert(
		info.Conns,
		model:GetAttributeChangedSignal("WE_Destroyed"):Connect(function()
			if model:GetAttribute("WE_Destroyed") == true then
				wreckBurst(model)
			end
			requestRefresh()
		end)
	)
	if model:GetAttribute("WE_Destroyed") == true then
		info.Wrecked = true -- streamed in already wrecked: no burst
	end
	requestRefresh()
end

local function onSeatChanged(hum: Humanoid)
	local seat = hum.SeatPart
	local model = vehicleOf(seat)
	if model and tracked[model] == nil then
		track(model)
	end
	seated = model
	requestRefresh()
end

local function bindCharacter(character: Model)
	task.spawn(function()
		local found = character:FindFirstChildOfClass("Humanoid") or character:WaitForChild("Humanoid", 10)
		if not (found and found:IsA("Humanoid")) then
			return
		end
		local hum: Humanoid = found
		local old = humConn
		if old then
			old:Disconnect()
		end
		humConn = hum:GetPropertyChangedSignal("SeatPart"):Connect(function()
			onSeatChanged(hum)
		end)
		onSeatChanged(hum)
	end)
end

function VehicleCombatClient.Init()
	if started then
		return
	end
	started = true
	local tag = Constants.Tags.Vehicle
	CollectionService:GetInstanceAddedSignal(tag):Connect(track)
	CollectionService:GetInstanceRemovedSignal(tag):Connect(function(inst: Instance)
		if inst:IsA("Model") then
			untrack(inst)
		end
	end)
	for _, inst in ipairs(CollectionService:GetTagged(tag)) do
		track(inst)
	end
	local lp = localPlayer()
	if lp then
		lp.CharacterAdded:Connect(function(character: Model)
			seated = nil
			bindCharacter(character)
		end)
		lp.CharacterRemoving:Connect(function()
			seated = nil
			requestRefresh()
		end)
		local ch = lp.Character
		if ch then
			bindCharacter(ch)
		end
	end
	pcall(function()
		(UserInputService :: any):GetPropertyChangedSignal("PreferredInput"):Connect(function()
			placeHud()
		end)
	end)
	requestRefresh()
end

-- tests / Studio
function VehicleCombatClient._Stats(): { Refreshes: number, Bursts: number, OverShown: number, HudShown: boolean, Tracked: number }
	local n = 0
	for _ in pairs(tracked) do
		n += 1
	end
	return { Refreshes = stats.Refreshes, Bursts = stats.Bursts, OverShown = stats.OverShown, HudShown = stats.HudShown, Tracked = n }
end

function VehicleCombatClient._Seated(): Model?
	return seated
end

function VehicleCombatClient._HudBar(): Frame?
	return hudBar
end

function VehicleCombatClient._Gui(): ScreenGui?
	return hudGui
end

return VehicleCombatClient
