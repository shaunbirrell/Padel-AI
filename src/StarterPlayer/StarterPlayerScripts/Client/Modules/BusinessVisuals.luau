--!strict
--[[
	v72 war businesses: the CLIENT-ONLY look (BusinessConfig.Visual / .Crates). Money never comes from here: it sends
	nothing to the server and the server reads nothing from it. Init is a no-op while BusinessConfig.Enabled is false.

	Crates  pooled local Parts ride YOUR lines' belts and drop into the bin: at most Visual.MaxCratesPerLine per line
	        (1 while the saved Graphics Quality is 1..LowQualityLevel), only while your character is within
	        ActiveRadius of the belt and the line is level 1+. One Heartbeat accumulator runs a 4 Hz scan (ownership,
	        level, parts, distance, belt geometry) and a <= UpdateHz (max 20) step that moves every live crate with ONE
	        Workspace:BulkMoveTo into preallocated arrays; the step itself only does arithmetic on cached values.
	        Crates are never destroyed while the game runs: idle ones are hidden and go back to a pool per crate look,
	        so after warm-up (<= MaxCratesPerLine per own line) no Instance is created.
	Pops    "+$N" (TycoonMath.PopText = floor(IncomePerTick[level] x WE_IncomeMult)) over the bins of your nearest lines
	        each time the server bumps the Player attribute WE_PassiveTick (every 5 s): at most MaxPopsPerTick, only
	        for lines whose bin is within PopRadius of your character. MaxPopsPerTick pooled WorldLabel billboards,
	        animated at 10 Hz by the same Heartbeat (no thread per pop).
	Streaming-safe: lines come and go with the BusinessConfig.Tag tag (stream in / out); parts are looked up with
	FindFirstChild on the scan, never WaitForChild, and the step never touches a server part. Other players' lines
	stay static (their Models are tracked but skipped). Owner-only by construction: everything here is local.
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared", 60) -- Bootstrap already waited for it; bounded anyway
local BusinessConfig = require(Shared.Configs.BusinessConfig)
local HudConfig = require(Shared.Configs.HudConfig)
local TycoonMath = require(Shared.Util.TycoonMath)
local WorldLabel = require(Shared.Util.WorldLabel)

local BusinessVisuals = {}

type CrateLook = { Size: Vector3, Color: Color3, Material: Enum.Material, Shape: Enum.PartType? }

type Line = {
	model: Model,
	def: BusinessConfig.BusinessDef,
	look: CrateLook?,
	level: number,
	active: boolean,
	crates: { BasePart },
	startAt: { number }, -- per crate: clock when it entered the belt (-1 = idle, hidden)
	nextAt: number,
	popMark: number,
	-- belt geometry (world), refreshed by the scan so the step never reads a part
	rot: CFrame, -- belt rotation, no position
	p0: Vector3, -- crate centre at the belt start
	p1: Vector3, -- crate centre at the belt end
	along: Vector3, -- p1 - p0
	drop: Vector3, -- p1 -> crate centre sunk half into the bin's top face
	travel: number, -- seconds on the belt
	every: number, -- seconds between crates at this level
}

type Pop = { gui: BillboardGui, title: TextLabel?, startAt: number }

local V = BusinessConfig.Visual
local player = Players.LocalPlayer

-- look-only constants (proposed BusinessConfig.Visual keys; see build/C/assumptions.md)
local SCAN_EVERY = 0.25 -- 4 Hz ownership / distance / geometry scan
local DROP_FRAC = 0.25 -- the drop into the bin lasts this share of the belt time
local POP_EVERY = 0.1 -- pop animation at 10 Hz (CLAUDE.md UI refresh cap)
local POP_SECONDS = 1.2 -- a pop is on screen this long
local POP_HOLD = 0.5 -- fully opaque for the first half, then it fades out
local POP_RISE = 1.5 -- studs it floats up over its life
local POP_OFFSET = Vector3.new(0, 3, 0) -- above the bin's centre
local POP_STUDS = Vector2.new(3, 1.2)
local POP_NAME = "WE_BizCashPop"
local FOLDER_NAME = "WE_BusinessCratesLocal"

local STEP_EVERY = 1 / math.clamp(V.UpdateHz, 1, 20) -- never more than 20 BulkMoveTo calls per second

local started = false
local clock = 0 -- seconds since Init, summed from Heartbeat dt
local lines: { [Model]: Line } = {}
local activeCount = 0
local maxCrates = V.MaxCratesPerLine
local folder: Folder? = nil
local free: { [string]: { BasePart } } = {} -- idle crates by crate look (BusinessDef.Product)
local pops: { Pop } = {}
local popsLive = 0
local popSerial = 0
-- BulkMoveTo buffers: grown once, entries overwritten in place, stale tail trimmed each step
local movedParts: { BasePart } = {}
local movedCFrames: { CFrame } = {}

local function savedQuality(): number
	local ok, level = pcall(function()
		return (UserSettings():GetService("UserGameSettings") :: any).SavedQualityLevel.Value
	end)
	return if ok and typeof(level) == "number" then level else 0 -- 0 = Automatic (or unknown)
end

local function cratesPerLine(): number
	local q = savedQuality()
	if q > 0 and q <= V.LowQualityLevel then
		return 1
	end
	return V.MaxCratesPerLine
end

-- our local folder went away (and every pooled crate / pop with it): forget them, they are rebuilt lazily
local function forgetPool()
	folder = nil
	table.clear(free)
	table.clear(pops)
	popsLive = 0
	for _, l in pairs(lines) do
		table.clear(l.crates)
		table.clear(l.startAt)
		l.active = false
	end
	table.clear(movedParts)
	table.clear(movedCFrames)
end

local function crateFolder(): Folder
	local f = folder
	if f and f.Parent then
		return f
	end
	if f then
		forgetPool() -- a pop can land before the next scan notices: never hand out crates / pops from a dead folder
	end
	local nf = Instance.new("Folder")
	nf.Name = FOLDER_NAME
	nf.Parent = Workspace
	folder = nf
	return nf
end

local function isMine(m: Instance): boolean
	return m:GetAttribute("OwnerUserId") == player.UserId
end

local function levelOf(m: Instance): number
	local v = tonumber(m:GetAttribute("Level"))
	if v == nil or v ~= v then
		return 0
	end
	return math.floor(v)
end

local function characterPos(): Vector3?
	local char = player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	if hrp and hrp:IsA("BasePart") then
		return hrp.Position
	end
	return nil
end

local function newCrate(look: CrateLook): BasePart
	local p = Instance.new("Part")
	p.Name = "Crate"
	p.Anchored = true
	p.CanCollide = false
	p.CanTouch = false
	p.CanQuery = false
	p.CastShadow = false
	p.Size = look.Size
	p.Color = look.Color
	p.Material = look.Material
	if look.Shape then
		p.Shape = look.Shape
	end
	p.Transparency = 1 -- idle crates are hidden, never destroyed (pool)
	p.Parent = crateFolder()
	return p
end

local function takeCrate(l: Line): BasePart?
	local look = l.look
	if look == nil then
		return nil
	end
	local list = free[l.def.Product]
	local n = if list then #list else 0
	if list and n > 0 then
		local c = list[n]
		list[n] = nil
		return c
	end
	return newCrate(look)
end

-- hide the LAST crate of the line and give it back to the pool
local function releaseLast(l: Line)
	local i = #l.crates
	local c = l.crates[i]
	l.crates[i] = nil
	l.startAt[i] = nil
	if c.Transparency ~= 1 then
		c.Transparency = 1
	end
	local list = free[l.def.Product]
	if list == nil then
		list = {}
		free[l.def.Product] = list
	end
	table.insert(list, c)
end

local function releaseAll(l: Line)
	for _ = 1, #l.crates do
		releaseLast(l)
	end
	l.active = false
end

-- grow / shrink the line's crates to the current per-line cap (pool first, new Part only while warming up)
local function fit(l: Line)
	while #l.crates > maxCrates do
		releaseLast(l)
	end
	while #l.crates < maxCrates do
		local c = takeCrate(l)
		if c == nil then
			break
		end
		table.insert(l.crates, c)
		table.insert(l.startAt, -1)
	end
end

-- belt geometry in world space; the belt runs along its local X toward the bin (sign from where the bin sits)
local function measure(l: Line, belt: BasePart, bin: BasePart, look: CrateLook)
	local bcf = belt.CFrame
	local len = belt.Size.X
	local dir = if bcf:PointToObjectSpace(bin.Position).X >= 0 then 1 else -1
	local lift = belt.Size.Y * 0.5 + look.Size.Y * 0.5
	local p0 = bcf:PointToWorldSpace(Vector3.new(-dir * 0.5 * len, lift, 0))
	local p1 = bcf:PointToWorldSpace(Vector3.new(dir * 0.5 * len, lift, 0))
	local sink = bin.Position + Vector3.new(0, bin.Size.Y * 0.5, 0)
	l.rot = bcf.Rotation
	l.p0 = p0
	l.p1 = p1
	l.along = p1 - p0
	l.drop = sink - p1
	l.travel = math.max(0.25, len / math.max(V.BeltSpeed, 0.1))
	local every = l.def.CrateEverySec
	l.every = math.max(0.2, every[math.clamp(l.level, 1, #every)] or 2)
end

local function track(inst: Instance)
	if not inst:IsA("Model") or lines[inst] or inst.Parent == nil then
		return
	end
	local id = inst:GetAttribute("BusinessId")
	local def = if typeof(id) == "string" then BusinessConfig.Get(id) else nil
	if def == nil then
		return
	end
	local zero = Vector3.zero
	lines[inst] = {
		model = inst,
		def = def,
		look = BusinessConfig.Crates[def.Product],
		level = 0,
		active = false,
		crates = {},
		startAt = {},
		nextAt = 0,
		popMark = 0,
		rot = CFrame.identity,
		p0 = zero,
		p1 = zero,
		along = zero,
		drop = zero,
		travel = 1,
		every = 2,
	}
end

local function untrack(inst: Instance)
	local l = lines[inst :: any]
	if l then
		releaseAll(l)
		lines[inst :: any] = nil
	end
end

-- 4 Hz: ownership, level, parts, distance -> active / idle, pool size, belt geometry
local function scan()
	local f = folder
	if f and f.Parent == nil then
		forgetPool()
	end
	local at = characterPos()
	local count = 0
	for m, l in pairs(lines) do
		if m.Parent == nil then
			untrack(m)
			continue
		end
		local want = false
		local look = l.look
		if at ~= nil and look ~= nil and isMine(m) then
			l.level = levelOf(m)
			if l.level >= 1 then
				local belt = m:FindFirstChild("Kit_Belt")
				local bin = m:FindFirstChild("Kit_Bin")
				if belt and bin and belt:IsA("BasePart") and bin:IsA("BasePart") and (belt.Position - at).Magnitude <= V.ActiveRadius then
					want = true
					measure(l, belt, bin, look)
				end
			end
		end
		if want then
			fit(l)
			if not l.active then
				l.nextAt = clock -- first crate on the next step
			end
			l.active = #l.crates > 0
		elseif l.active or #l.crates > 0 then
			releaseAll(l)
		end
		if l.active then
			count += 1
		end
	end
	activeCount = count
end

-- <= 20 Hz: advance every live crate along its belt, then a short drop into the bin; one BulkMoveTo for all
local function step(now: number)
	local n = 0
	if activeCount > 0 then
		for _, l in pairs(lines) do
			if l.active then
				local crates, startAt = l.crates, l.startAt
				if now >= l.nextAt then
					-- start the next crate as soon as one is free (if none is, try again next step)
					for i = 1, #crates do
						if startAt[i] < 0 then
							startAt[i] = now
							crates[i].Transparency = 0
							l.nextAt = now + l.every
							break
						end
					end
				end
				for i = 1, #crates do
					local s = startAt[i]
					if s >= 0 then
						local t = (now - s) / l.travel
						local pos: Vector3
						if t <= 1 then
							pos = l.p0 + l.along * t
						elseif t <= 1 + DROP_FRAC then
							pos = l.p1 + l.drop * ((t - 1) / DROP_FRAC)
						else
							startAt[i] = -1
							crates[i].Transparency = 1
							pos = l.p0 -- parked hidden at the belt start
						end
						n += 1
						movedParts[n] = crates[i]
						movedCFrames[n] = l.rot + pos
					end
				end
			end
		end
	end
	-- trim the stale tail without allocating (BulkMoveTo reads the whole arrays)
	for i = #movedParts, n + 1, -1 do
		movedParts[i] = nil
		movedCFrames[i] = nil
	end
	if n > 0 then
		Workspace:BulkMoveTo(movedParts, movedCFrames, Enum.BulkMoveMode.FireCFrameChanged)
	end
end

local function fadePop(p: Pop, f: number)
	local title = p.title
	if title then
		title.TextTransparency = f
		title.TextStrokeTransparency = f
	end
end

local function showPop(k: number, bin: BasePart, text: string)
	local p = pops[k]
	if p == nil or p.gui.Parent == nil then
		local opts: WorldLabel.Options = {
			Name = POP_NAME,
			Color = HudConfig.Colors.Positive,
			TextSize = V.PopTextPx,
			Studs = POP_STUDS,
			Offset = POP_OFFSET,
			Parent = crateFolder(), -- local folder: the pool survives the bin streaming out
		}
		local gui = WorldLabel.Create(bin, text, opts)
		local title = gui:FindFirstChild("Title")
		p = { gui = gui, title = if title and title:IsA("TextLabel") then title else nil, startAt = -1 }
		pops[k] = p
	else
		p.gui.Adornee = bin
		WorldLabel.SetText(p.gui, text)
		p.gui.StudsOffsetWorldSpace = POP_OFFSET
	end
	local pop = p :: Pop
	fadePop(pop, 0)
	pop.gui.Enabled = true
	if pop.startAt < 0 then
		popsLive += 1
	end
	pop.startAt = clock
end

-- 10 Hz: float up, hold, fade, then hide (the gui is kept for the next tick)
local function animatePops(now: number)
	if popsLive <= 0 then
		return
	end
	for _, p in ipairs(pops) do
		if p.startAt >= 0 then
			local k = (now - p.startAt) / POP_SECONDS
			if k >= 1 then
				p.startAt = -1
				popsLive -= 1
				p.gui.Enabled = false
			else
				p.gui.StudsOffsetWorldSpace = POP_OFFSET + Vector3.new(0, POP_RISE * k, 0)
				fadePop(p, if k <= POP_HOLD then 0 else (k - POP_HOLD) / (1 - POP_HOLD))
			end
		end
	end
end

-- WE_PassiveTick changed: "+$N" over the nearest owned lines (level 1+, bin within PopRadius of the character)
local function popTick()
	local at = characterPos()
	if at == nil then
		return
	end
	local mult = tonumber(player:GetAttribute("WE_IncomeMult"))
	if mult == nil or mult ~= mult or mult == math.huge then
		mult = 1
	end
	if (mult :: number) <= 0 then
		return -- nothing reaches the ATM: never show a gain
	end
	popSerial += 1
	local shown = 0 -- pool slots stay dense (animatePops walks them with ipairs)
	for _ = 1, V.MaxPopsPerTick do
		local best: Line? = nil
		local bestBin: BasePart? = nil
		local bestD, bestLv = V.PopRadius, 0
		for m, l in pairs(lines) do
			if l.popMark ~= popSerial and m.Parent ~= nil and isMine(m) then
				local lv = levelOf(m)
				local bin = if lv >= 1 then m:FindFirstChild("Kit_Bin") else nil
				if bin and bin:IsA("BasePart") then
					local d = (bin.Position - at).Magnitude
					if d <= bestD then
						best, bestBin, bestD, bestLv = l, bin, d, lv
					end
				end
			end
		end
		if best == nil or bestBin == nil then
			break
		end
		best.popMark = popSerial
		if TycoonMath.LevelIncomePerTick(best.def.Id, bestLv) > 0 then
			shown += 1
			showPop(shown, bestBin, TycoonMath.PopText(best.def.Id, bestLv, mult))
		end
	end
end

function BusinessVisuals.Init()
	if started or not BusinessConfig.Enabled then
		return
	end
	started = true
	maxCrates = cratesPerLine()
	pcall(function()
		local ugs = UserSettings():GetService("UserGameSettings") :: any
		ugs:GetPropertyChangedSignal("SavedQualityLevel"):Connect(function()
			maxCrates = cratesPerLine() -- applied by the next scan (surplus crates go back to the pool)
		end)
	end)
	for _, m in ipairs(CollectionService:GetTagged(BusinessConfig.Tag)) do
		track(m)
	end
	CollectionService:GetInstanceAddedSignal(BusinessConfig.Tag):Connect(function(m: Instance)
		task.defer(track, m)
	end)
	CollectionService:GetInstanceRemovedSignal(BusinessConfig.Tag):Connect(untrack)
	player:GetAttributeChangedSignal("WE_PassiveTick"):Connect(popTick)

	local scanAcc, stepAcc, popAcc = SCAN_EVERY, 0, 0 -- scan on the first beat
	RunService.Heartbeat:Connect(function(dt: number)
		clock += dt
		scanAcc += dt
		stepAcc += dt
		popAcc += dt
		if scanAcc >= SCAN_EVERY then
			scanAcc = 0
			scan()
		end
		if stepAcc >= STEP_EVERY then
			stepAcc = 0 -- reset, never catch up: a hitch can not burst above UpdateHz
			step(clock)
		end
		if popAcc >= POP_EVERY then
			popAcc = 0
			animatePops(clock)
		end
	end)
end

return BusinessVisuals
