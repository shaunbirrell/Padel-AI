--!strict
--[[
	F4 (owner's 11 features, lane G): ONE small owner-only floating label over the nearest of the player's own
	producers: the Training Yard "+$40" / "every 5s" and each plot oil pump "+$18" / "every 5s". Client-only: nobody
	else sees it, and the server makes no billboard for it (SoldierService / PlotOilPumpService pops are gone with F4).

	Numbers: the yard shows the server-stamped WE_TickTraining (the last training grant, multipliers in; EconomyService
	writes it only on change and only while EconomyConfig.ProducerLabels.Enabled); a pump shows
	PlotOilPumpConfig.CashPerTick (plot oil is paid without multipliers). The sub line reads the tick seconds from
	config (SoldierConfig.TrainingIncome.TickSeconds / PlotOilPumpConfig.TickSeconds). Display only.
	Anchors: cached from the OWN plot only (Workspace.WarEmpireSetup.Bases.Plot<n>): TrainingYard.YardPad and the
	PrimaryPart of each WE_PlotOilPumps model. FindFirstChild with nil checks, ChildAdded / ChildRemoved on those
	folders, and a retry every second while a part is not streamed in; no whole-tree scan, no unbounded wait.
	The own plot id is BaseStateUpdate / PlayerStateUpdate PlotId, else the plot holding the server-stamped WE_AtmPos /
	WE_ConsolePos_CommandCenter.
	Pick: EconomyConfig.ProducerLabels.ScanHz times a second (one Heartbeat accumulator), the nearest anchor within
	RadiusStuds of the character (the yard only while it pays: no soldiers, no yard label). Only the Adornee moves; the
	text is written only when it changes. A pulse (UIScale 1 -> 1.15 -> 1 over PulseSeconds, one reused tween) plays on
	each income tick (WE_PassiveTick / WE_TickTraining, or every tick seconds when neither arrives).
	Hidden: Driving, Dead or Modal (HudLayout flags), nothing within RadiusStuds, or the yard without training income.
	"Training income" = the last SoldierStateUpdate / PlayerStateUpdate TrainingIncomePerTick > 0 (WE_TickTraining
	keeps the last grant after the soldiers are dismissed: the server writes it only on a grant), and WE_TickTraining
	> 0; before any push reports it, WE_TickTraining > 0 alone.
	The label: WorldLabel.Create (Name "WE_ProducerLabel", TextSize 18 / sub 14, 6 x 1.6 studs, 4.5 studs up,
	MaxDistance 24, never drawn over walls), tagged as a base label so the LabelGovernor counts it; shown / hidden with
	WorldLabel.SetShown. Off (Init returns at once) while EconomyConfig.ProducerLabels.Enabled is false.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared", 60) -- Bootstrap already waited for it; bounded anyway
local Constants = require(Shared.Constants)
local Remotes = require(Shared.Remotes)
local BaseConfig = require(Shared.Configs.BaseConfig)
local EconomyConfig = require(Shared.Configs.EconomyConfig)
local HudConfig = require(Shared.Configs.HudConfig)
local PlotOilPumpConfig = require(Shared.Configs.PlotOilPumpConfig)
local SoldierConfig = require(Shared.Configs.SoldierConfig)
local TycoonMath = require(Shared.Util.TycoonMath)
local PlotFrame = require(Shared.Util.PlotFrame)
local WorldLabel = require(Shared.Util.WorldLabel)

local HudLayout = require(script.Parent.HudLayout)

local ProducerLabels = {}

local CFG = EconomyConfig.ProducerLabels
local LABEL_NAME = "WE_ProducerLabel"
local FOLDER_NAME = "WE_ProducerLabelLocal"
local LABEL_STUDS = Vector2.new(6, 1.6)
local LABEL_OFFSET = Vector3.new(0, 4.5, 0)
local PULSE_SCALE = 1.15
local RETRY_SECONDS = 1 -- a producer part not streamed in yet: look again this often
local HIDE_FLAGS = { "Driving", "Dead", "Modal" }
local KIND_YARD = 1
local KIND_PUMP = 2
local YARD_SECONDS = math.max(1, math.floor((SoldierConfig.TrainingIncome :: any).TickSeconds or 5))
local PUMP_SECONDS = math.max(1, math.floor(PlotOilPumpConfig.TickSeconds or 5))
local PUMP_FOLDER = PlotOilPumpConfig.FolderName or "WE_PlotOilPumps"
local HALF_PAD = BaseConfig.PlotSize.X * 0.5
-- server-stamped world positions on the own plot (the plot id when no state push has named it yet)
local PLOT_HINT_ATTRS = { "WE_AtmPos", "WE_ConsolePos_CommandCenter" }

local player = Players.LocalPlayer
local started = false

local plotId: number? = nil
local plotName = "" -- "Plot<n>" (built once per plot change)
-- anchors: dense parallel arrays, rebuilt only when a watched folder changes or a part is still missing
local anchorPart: { BasePart } = {}
local anchorKind: { number } = {}
local anchorN = 0
local anchorsDirty = true
local anchorsIncomplete = false
local retryAt = 0
local watched: { [Instance]: boolean } = setmetatable({} :: any, { __mode = "k" })

local gui: BillboardGui? = nil
local pulseTween: Tween? = nil
local shownKind = 0
local shownAmount = -1
local visible = false
local trainingPays: boolean? = nil -- last pushed TrainingIncomePerTick > 0 (nil = no push seen yet)
local lastServerTickAt = -math.huge
local lastPulseAt = -math.huge

-- ── pure helpers (tests call these) ───────────────────────────────────────────────────────────────────────────

-- ("+$40", "every 5s") for 40 every 5 seconds
function ProducerLabels.Text(amount: number, seconds: number): (string, string)
	local n = tonumber(amount) or 0
	if n ~= n then
		n = 0
	end
	local secs = math.max(1, math.floor((tonumber(seconds) or 5) + 0.5))
	return "+" .. TycoonMath.ShortCash(n), string.format("every %ds", secs)
end

--[[ The nearest of parts[1..n] within `radius` studs of `pos` (kinds[i] == KIND_YARD is skipped unless yardOn), or
	nil. A part that left the world is skipped. Pure. ]]
function ProducerLabels.Pick(parts: { BasePart }, kinds: { number }, n: number, pos: Vector3, radius: number, yardOn: boolean): number?
	local best: number? = nil
	local bestD2 = radius * radius
	for i = 1, n do
		local p = parts[i]
		if (kinds[i] ~= KIND_YARD or yardOn) and p.Parent ~= nil then
			local a = p.Position
			local dx, dy, dz = a.X - pos.X, a.Y - pos.Y, a.Z - pos.Z
			local d2 = dx * dx + dy * dy + dz * dz
			if d2 <= bestD2 then
				best, bestD2 = i, d2
			end
		end
	end
	return best
end

ProducerLabels.KindYard = KIND_YARD
ProducerLabels.KindPump = KIND_PUMP

-- ── own plot ──────────────────────────────────────────────────────────────────────────────────────────────────

local function plotAt(pos: Vector3): number?
	local half = HALF_PAD + 24
	for id = 1, BaseConfig.MaxPlots do
		local pp = PlotFrame.PlotPosition(id)
		if pp ~= nil then
			local l = PlotFrame.PlotCFrame(pp):PointToObjectSpace(pos)
			if math.abs(l.X) <= half and math.abs(l.Z) <= half then
				return id
			end
		end
	end
	return nil
end

local function setPlot(id: number?)
	if id == plotId then
		return
	end
	plotId = id
	plotName = if id ~= nil then "Plot" .. tostring(id) else ""
	anchorsDirty = true
end

local function ownPlot(): number?
	if plotId == nil then
		for _, name in ipairs(PLOT_HINT_ATTRS) do
			local v = player:GetAttribute(name)
			if typeof(v) == "Vector3" then
				local id = plotAt(v)
				if id ~= nil then
					setPlot(id)
					break
				end
			end
		end
	end
	return plotId
end

-- ── anchors ───────────────────────────────────────────────────────────────────────────────────────────────────

local function markDirty()
	anchorsDirty = true
end

-- ChildAdded / ChildRemoved on a producer folder -> rebuild the anchors (once per folder instance)
local function watch(container: Instance)
	if watched[container] then
		return
	end
	watched[container] = true
	container.ChildAdded:Connect(markDirty)
	container.ChildRemoved:Connect(markDirty)
end

local function addAnchor(part: Instance?, kind: number)
	if part ~= nil and part:IsA("BasePart") then
		anchorN += 1
		anchorPart[anchorN] = part
		anchorKind[anchorN] = kind
	end
end

local function collect()
	anchorsDirty = false
	anchorsIncomplete = false
	for i = anchorN, 1, -1 do
		anchorPart[i] = nil :: any
		anchorKind[i] = nil :: any
	end
	anchorN = 0
	local pid = ownPlot()
	if pid == nil then
		anchorsIncomplete = true
		return
	end
	local setup = Workspace:FindFirstChild("WarEmpireSetup")
	local bases = if setup then setup:FindFirstChild("Bases") else nil
	local plot = if bases then bases:FindFirstChild(plotName) else nil
	if plot == nil then
		anchorsIncomplete = true
		return
	end
	watch(plot)
	local yard = plot:FindFirstChild("TrainingYard")
	if yard ~= nil then
		watch(yard)
		local pad = yard:FindFirstChild("YardPad")
		if pad == nil then
			anchorsIncomplete = true -- the yard pad has not streamed in yet
		end
		addAnchor(pad, KIND_YARD)
	else
		anchorsIncomplete = true
	end
	local pumps = plot:FindFirstChild(PUMP_FOLDER)
	if pumps ~= nil then
		watch(pumps)
		for _, m in ipairs(pumps:GetChildren()) do
			if m:IsA("Model") then
				local pp = m.PrimaryPart
				if pp == nil then
					anchorsIncomplete = true -- this pump's pad has not streamed in yet
				end
				addAnchor(pp, KIND_PUMP)
			end
		end
	end
end

-- ── the label ─────────────────────────────────────────────────────────────────────────────────────────────────

local function localFolder(): Folder
	local f = Workspace:FindFirstChild(FOLDER_NAME)
	if f and f:IsA("Folder") then
		return f
	end
	local nf = Instance.new("Folder")
	nf.Name = FOLDER_NAME
	nf.Parent = Workspace
	return nf
end

local function ensureLabel(anchor: BasePart): BillboardGui
	local g = gui
	if g ~= nil and g.Parent ~= nil then
		return g
	end
	local title, sub = ProducerLabels.Text(0, YARD_SECONDS)
	local opts: WorldLabel.Options = {
		Name = LABEL_NAME,
		Sub = sub,
		Color = HudConfig.Colors.Positive,
		TextSize = CFG.TextSize,
		Studs = LABEL_STUDS,
		Offset = LABEL_OFFSET,
		MaxDistance = CFG.MaxDistance,
		BaseLabel = true,
		Parent = localFolder(), -- local folder: the label survives its anchor streaming out
	}
	local ng = WorldLabel.Create(anchor, title, opts)
	WorldLabel.SetShown(ng, false) -- shown by the scan below once its text is right
	local s = Instance.new("UIScale")
	s.Scale = 1
	s.Parent = ng
	pulseTween = TweenService:Create(s, TweenInfo.new(math.max(0.05, CFG.PulseSeconds * 0.5), Enum.EasingStyle.Quad, Enum.EasingDirection.Out, 0, true), { Scale = PULSE_SCALE })
	gui = ng
	shownKind = 0
	shownAmount = -1
	visible = false
	return ng
end

local function hide()
	local g = gui
	if g ~= nil and visible then
		visible = false
		WorldLabel.SetShown(g, false)
	end
end

local function pulse()
	local t = pulseTween
	if t ~= nil and visible then
		lastPulseAt = os.clock()
		t:Play()
	end
end

local function trainingAmount(): number
	local v = tonumber(player:GetAttribute("WE_TickTraining"))
	if v == nil or v ~= v or v == math.huge then
		return 0
	end
	return math.max(0, math.floor(v))
end

local function hiddenByFlags(): boolean
	for _, name in ipairs(HIDE_FLAGS) do
		if HudLayout.GetFlag(name) then
			return true
		end
	end
	return false
end

local function scan()
	local now = os.clock()
	if anchorsDirty or (anchorsIncomplete and now >= retryAt) then
		retryAt = now + RETRY_SECONDS
		collect()
	end
	if anchorN == 0 or hiddenByFlags() then
		hide()
		return
	end
	local char = player.Character
	local hrp = if char then char:FindFirstChild("HumanoidRootPart") else nil
	if hrp == nil or not hrp:IsA("BasePart") then
		hide()
		return
	end
	local training = trainingAmount()
	local yardOn = training > 0 and trainingPays ~= false -- no soldiers (dismissed): no yard label
	local i = ProducerLabels.Pick(anchorPart, anchorKind, anchorN, (hrp :: BasePart).Position, CFG.RadiusStuds, yardOn)
	if i == nil then
		hide()
		return
	end
	local anchor = anchorPart[i]
	local kind = anchorKind[i]
	local amount = if kind == KIND_YARD then training else math.max(0, math.floor(PlotOilPumpConfig.CashPerTick))
	local g = ensureLabel(anchor)
	if g.Adornee ~= anchor then
		g.Adornee = anchor -- only the adornee moves
	end
	if kind ~= shownKind or amount ~= shownAmount then
		shownKind, shownAmount = kind, amount
		local title, sub = ProducerLabels.Text(amount, if kind == KIND_YARD then YARD_SECONDS else PUMP_SECONDS)
		WorldLabel.SetText(g, title, sub)
	end
	if not visible then
		visible = true
		WorldLabel.SetShown(g, true)
	end
	-- no server tick seen for two ticks (businesses off): pulse on the local clock instead
	if now - lastServerTickAt > 2 * YARD_SECONDS and now - lastPulseAt >= YARD_SECONDS then
		pulse()
	end
end

-- SoldierStateUpdate / PlayerStateUpdate: does the yard pay right now (pre-multiplier training $ per tick)?
local function applyTraining(perTick: any)
	if typeof(perTick) == "number" then
		trainingPays = perTick > 0
	end
end

local function onServerTick()
	lastServerTickAt = os.clock()
	pulse()
end

-- test / debug: (label shown, title text, anchor count)
function ProducerLabels.State(): (boolean, string, number)
	local g = gui
	local title = if g ~= nil then g:FindFirstChild("Title") else nil
	return visible, (if title and title:IsA("TextLabel") then title.Text else ""), anchorN
end

function ProducerLabels.Scan()
	scan()
end

function ProducerLabels.Init()
	if started or CFG.Enabled ~= true then
		return
	end
	started = true
	Remotes.BindEvent(Constants.RemoteNames.BaseStateUpdate, function(base: any)
		if typeof(base) == "table" and typeof(base.PlotId) == "number" then
			setPlot(base.PlotId)
		end
	end)
	Remotes.BindEvent(Constants.RemoteNames.PlayerStateUpdate, function(state: any)
		if typeof(state) ~= "table" then
			return
		end
		if typeof(state.Base) == "table" and typeof(state.Base.PlotId) == "number" then
			setPlot(state.Base.PlotId)
		end
		applyTraining(state.TrainingIncomePerTick)
	end)
	Remotes.BindEvent(Constants.RemoteNames.SoldierStateUpdate, function(payload: any)
		if typeof(payload) == "table" then
			applyTraining(payload.TrainingIncomePerTick)
		end
	end)
	for _, name in ipairs(PLOT_HINT_ATTRS) do
		player:GetAttributeChangedSignal(name):Connect(markDirty)
	end
	player:GetAttributeChangedSignal("WE_PassiveTick"):Connect(onServerTick)
	player:GetAttributeChangedSignal("WE_TickTraining"):Connect(onServerTick)
	HudLayout.FlagChanged:Connect(function(name: string, on: boolean)
		if on and table.find(HIDE_FLAGS, name) ~= nil then
			hide() -- at once, not on the next scan
		end
	end)
	local period = 1 / math.clamp(CFG.ScanHz, 1, 10) -- <= 10 Hz (CLAUDE.md UI refresh cap)
	local acc = period -- first scan on the first beat
	RunService.Heartbeat:Connect(function(dt: number)
		acc += dt
		if acc < period then
			return
		end
		acc = 0 -- reset, never catch up
		scan()
	end)
end

return ProducerLabels
