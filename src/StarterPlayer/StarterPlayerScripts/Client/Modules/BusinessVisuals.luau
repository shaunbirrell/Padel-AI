--!strict
--[[
	v72 war businesses: the CLIENT-ONLY look (BusinessConfig.Visual / .Products / .Machines). Money never comes from
	here: it sends nothing to the server and the server reads nothing from it. Init is a no-op while
	BusinessConfig.Enabled is false (it still boots ProductionFx first, see Init).

	Droppers v1a (spec_droppers.md §3.2, §3.3, §3.5, §3.6, §3.11, §7, §8):
	Products  tick-locked: exactly k = ProductsPerTick[L] products land in the bin per WE_PassiveTick window (5 s),
	          the last one LandLeadSeconds before the tick. A smoothed tick phase absorbs replication jitter; k is
	          clamped to what the pool can carry and re-evaluated on every tick. Pooled local Parts ride YOUR lines'
	          belts at BeltSpeedByLevel[L], spawn in the tier's raw look, turn done at the machine hit (Color, and
	          Material when it differs) and drop into the bin. MaxCratesPerLine per line; LowQualityPool with
	          k <= LowQualityMaxK at a saved Graphics Quality 1..LowQualityLevel (or on Automatic + touch while
	          AutomaticTouchIsLow). Size / Shape change only on a look tier change (re-skinned in place).
	Heap      one local Part per active own line rises out of the bin by RiseByLevel[L] / k per landing (clamped at
	          k) and sinks in SinkSteps steps on the tick (the ship).
	Machine   one local Part per active own line (press, boom, stamp, welder) with one reused Tween per measure():
	          one stroke per product, timed to hit it. The rest pose is written before every Play (while the tween
	          is idle; a stroke due mid-play is skipped), after every Cancel and after measure(), so it never drifts.
	Pops      "+$N" (TycoonMath.PopText = floor(IncomePerTick[level] x WE_IncomeMult)) over the 2 nearest own bins
	          within PopRadius on each WE_PassiveTick, at bin centre + PopOffset (x along the line toward the bin end),
	          animated at 10 Hz. They are base labels (WorldLabel.SetShown), so the LabelGovernor counts them.
	          Fix round 2: while the top-centre chip is up (NEXT / tutorial step: a ScreenGui over every billboard) a
	          pop whose title would land under it steps down toward PopDodge.LowOffset, to a spot the camera sees
	          (popOffsetFor; a few projections and rays per tick, none per frame). At a console the chip is hidden:
	          PopOffset.
	FX        ProductionFx (sibling module, lazy pcall'd require): Ship, LevelUp, FirstLand, Sparks. Level-up effects
	          fire only on a RISE of a line already seen at a known level (seenLevel): joining, a line streaming in,
	          a plot hand-out, a respawn or a local folder rebuild never play them. Pops and FX are skipped while a
	          Visual.Fx.HideWhen HUD flag is set; lines, heaps and machines keep running.
	Loop      one Heartbeat accumulator: a ScanHz (4 Hz) scan that may allocate (ownership, level, parts, distance,
	          measure() only on a change), a <= UpdateHz (max 20) step between the STEP markers that only indexes
	          cached CFrame tables and writes cached values (one Workspace:BulkMoveTo), and a 10 Hz pop animation.
	Culling   own lines within ActiveRadius of the character only; other players' lines stay static.
	Streaming-safe: lines come and go with the BusinessConfig.Tag tag; parts are looked up with FindFirstChild on
	the scan, never WaitForChild, and the step never reads a server part. Every local instance lives in the local
	folder and is pooled (hidden when idle), never destroyed.
]]

local CollectionService = game:GetService("CollectionService")
local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared", 60) -- Bootstrap already waited for it; bounded anyway
local BusinessConfig = require(Shared.Configs.BusinessConfig)
local EconomyConfig = require(Shared.Configs.EconomyConfig)
local HudConfig = require(Shared.Configs.HudConfig)
local TycoonGuideConfig = require(Shared.Configs.TycoonGuideConfig)
local TycoonMath = require(Shared.Util.TycoonMath)
local WorldLabel = require(Shared.Util.WorldLabel)

local BusinessVisuals = {}

type ProductLook = BusinessConfig.ProductLook
type MachineDef = BusinessConfig.MachineDef

type Line = {
	model: Model,
	def: BusinessConfig.BusinessDef,
	mdef: MachineDef?, -- nil: this business names no machine
	level: number, -- the level the line is planned for (own, active lines)
	seenLevel: number?, -- spec §3.7: nil until the first own sighting; level-up effects only on a rise
	active: boolean,
	tier: string, -- look tier the parts wear ("" before the first own sighting)
	look: ProductLook,
	-- products (pooled parts on loan to this line; per slot)
	crates: { BasePart },
	startAt: { number }, -- spawn clock, -1 = idle (hidden)
	doneAt: { number }, -- raw -> done swap clock (the machine hit), -1 = done
	strokeAt: { number }, -- this product's machine stroke clock, -1 = none pending
	-- production clock plan (feel §8)
	k: number,
	spacing: number,
	speed: number,
	beltTime: number,
	travelTotal: number,
	hitDelay: number,
	strokeLead: number,
	nextLand: number,
	fill: number, -- landings since the last ship (clamped at k)
	firstLand: boolean, -- the next landing is the first product of a new level (FirstLand)
	-- heap
	heap: BasePart?,
	heapCF: { CFrame }, -- [fill + 1], fill 0..k
	sinkCF: { CFrame }, -- [1..SinkSteps], the last one is the rest pose
	sink: number, -- 0 = not sinking, else the sinkCF index shown on the next step
	heapShown: number, -- code of the heap pose last moved (-1 = move it on the next step)
	-- machine
	machine: BasePart?,
	tween: Tween?,
	restCF: CFrame,
	sparks: boolean,
	weldNear: boolean,
	-- BeltFx (flag)
	skin: BasePart?,
	skinTex: Texture?,
	scrollU: boolean,
	decal: Decal?,
	decalT: number,
	-- geometry cached by measure(): the step never reads a server part
	path: { CFrame },
	pathN: number,
	park: CFrame,
	frame: CFrame, -- business-local frame (the Kit frame, +X toward the bin)
	binCF: CFrame,
	binSize: Vector3,
	binTop: Vector3,
	tip: Vector3,
	popOffset: Vector3,
	popLow: Vector3, -- fix round 2: PopDodge.LowOffset in world space (the lowest anchor while the chip is up)
	-- measure() runs again only when one of these changes
	mBelt: BasePart?,
	mBeltCF: CFrame,
	mBeltSize: Vector3,
	mBinCF: CFrame,
	mBinSize: Vector3,
	mLevel: number,
	mPool: number,
	mLow: boolean,
	popMark: number,
}

type Pop = { gui: BillboardGui, title: TextLabel?, startAt: number, offset: Vector3 }

local V = BusinessConfig.Visual
local player = Players.LocalPlayer

local SCAN_EVERY = 1 / math.clamp(V.ScanHz, 1, 10) -- 4 Hz ownership / distance / geometry scan
local POP_EVERY = 0.1 -- pop animation at 10 Hz (CLAUDE.md UI refresh cap)
local POP_STUDS = Vector2.new(3, 1.2)
local POP_NAME = "WE_BizCashPop"
local FOLDER_NAME = "WE_BusinessCratesLocal"
local PATH_HZ = math.clamp(V.PathHz, 5, 60) -- path samples per second of travel (built in measure())
local SINK_STEPS = math.max(1, math.floor(V.Heap.SinkSteps))
local TILE = math.max(0.1, V.BeltFx.TileStuds)
local SCROLL_SIGN = if V.BeltFx.ScrollSign < 0 then -1 else 1
local PLAYING = Enum.PlaybackState.Playing
local FLIP = CFrame.Angles(0, math.pi, 0)
local TICK_SECONDS = math.clamp(tonumber(EconomyConfig.PassiveIncome.TickSeconds) or 5, 1, 10)

-- the Kit "Belt" offset: the business-local origin sits here under the belt centre (spec §3.5 KitBeltOffset)
local KIT_BELT_OFFSET = Vector3.new(2, 2.4, 0)
for _, kp in ipairs(BusinessConfig.Kit) do
	if kp.Role == "Belt" then
		KIT_BELT_OFFSET = kp.Offset
	end
end

local STEP_EVERY = 1 / math.clamp(V.UpdateHz, 1, 20) -- never more than 20 BulkMoveTo calls per second

local started = false
local clock = 0 -- seconds since Init, summed from Heartbeat dt
local lines: { [Model]: Line } = {}
local activeList: { Line } = {} -- dense list of the active lines, rebuilt by the scan (the step walks it)
local activeCount = 0
local maxCrates = V.MaxCratesPerLine
local lowMode = false
local folder: Folder? = nil
local freeCrates: { BasePart } = {} -- idle products (any look: re-skinned when handed out)
local freeHeaps: { BasePart } = {}
local freeMachines: { BasePart } = {}
local freeSkins: { BasePart } = {}
local skinOf: { [BasePart]: ProductLook } = {} -- the look (Size / Shape) a product part currently wears
local skinTexOf: { [BasePart]: Texture } = {}
local fallbackLooks: { [string]: ProductLook } = {}
local pops: { Pop } = {}
local popsLive = 0
local popSerial = 0
-- BulkMoveTo buffers: pre-sized for every business at the full pool plus its heap (4 x (3 + 1) = 16 entries), entries
-- overwritten in place, the stale tail trimmed each step, so the step never grows them (the stand-in saw one array
-- growth in the first step that moved 12+ entries when they started empty)
local MOVED_CAP = #BusinessConfig.Order * (math.max(1, V.MaxCratesPerLine) + 1)
local movedParts: { BasePart } = table.create(MOVED_CAP)
local movedCFrames: { CFrame } = table.create(MOVED_CAP)

-- production clock (feel §8): the smoothed tick phase and period; the heap still ships on the observed tick
local tickAt = 0
local period = TICK_SECONDS
local tickSeen = false
local lastSeen = 0
local lastDt = -1

---------------------------------------------------------------------------------------------------------------
-- optional siblings (lazy, pcall'd): the module runs without them
---------------------------------------------------------------------------------------------------------------

local fxModule: any = nil
local fxTried = false
local fxBooted = false
local hudModule: any = nil
local hudTried = false

local function sibling(name: string): any
	local ok, mod = pcall(function(): any
		local parent = script.Parent
		local inst = if parent then parent:FindFirstChild(name) else nil
		if inst and inst:IsA("ModuleScript") then
			return require(inst) :: any
		end
		return nil
	end)
	if ok and type(mod) == "table" then
		return mod
	end
	return nil
end

-- droppers v1a ProductionFx (sparkles, tink, clack, welder sparks): Init, Ship, LevelUp, FirstLand, Sparks
local function productionFx(): any
	if not fxTried then
		fxTried = true
		fxModule = sibling("ProductionFx")
	end
	return fxModule
end

local function hudLayout(): any
	if not hudTried then
		hudTried = true
		hudModule = sibling("HudLayout")
	end
	return hudModule
end

-- Visual.Fx.HideWhen HUD flags (driving, dead, a panel, recent combat): no pops, sparkles or sounds
local function fxGated(): boolean
	local HudLayout = hudLayout()
	if HudLayout == nil or type(HudLayout.GetFlag) ~= "function" then
		return false -- no HudLayout, or C5's empty HudLayout table (Shared never arrived): nothing to gate on
	end
	for _, name in ipairs(V.Fx.HideWhen) do
		if HudLayout.GetFlag(name) == true then
			return true
		end
	end
	return false
end

-- one ProductionFx call with a cached position (no closure, no allocation); a missing or throwing module is a no-op
local function fx(name: string, at: Vector3)
	if not V.Fx.Enabled then
		return
	end
	local ProductionFx = productionFx()
	if ProductionFx == nil or fxGated() then
		return
	end
	local f = ProductionFx[name]
	if type(f) == "function" then
		pcall(f, at)
	end
end

-- a touch device (HudLayout.PrefersKeys: PreferredInput, never TouchEnabled); no HudLayout = not touch
local function touchInput(): boolean
	local HudLayout = hudLayout()
	if HudLayout == nil or type(HudLayout.PrefersKeys) ~= "function" then
		return false
	end
	local ok, keys = pcall(HudLayout.PrefersKeys)
	return ok and keys == false
end

---------------------------------------------------------------------------------------------------------------
-- quality, pools
---------------------------------------------------------------------------------------------------------------

local function savedQuality(): number
	local ok, level = pcall(function()
		return (UserSettings():GetService("UserGameSettings") :: any).SavedQualityLevel.Value
	end)
	return if ok and typeof(level) == "number" then level else 0 -- 0 = Automatic (or unknown)
end

-- (pool, low): a saved Graphics Quality 1..LowQualityLevel runs the light lines (LowQualityPool, k <= LowQualityMaxK);
-- Automatic stays full unless AutomaticTouchIsLow is set and the device is touch (OD-13 lever)
local function cratesPerLine(): (number, boolean)
	local q = savedQuality()
	if q > 0 and q <= V.LowQualityLevel then
		return V.LowQualityPool, true
	end
	if q <= 0 and V.AutomaticTouchIsLow == true and touchInput() then
		return V.LowQualityPool, true
	end
	return V.MaxCratesPerLine, false
end

local function requality()
	maxCrates, lowMode = cratesPerLine() -- applied by the next scan (surplus products go back to the pool)
end

local function restoreDecal(l: Line)
	local d = l.decal
	if d then
		l.decal = nil
		d.Transparency = l.decalT -- the belt's own Decal comes back when the scrolling skin goes
	end
end

-- our local folder went away (and every pooled part / pop with it): forget them, they are rebuilt lazily
local function forgetPool()
	folder = nil
	table.clear(freeCrates)
	table.clear(freeHeaps)
	table.clear(freeMachines)
	table.clear(freeSkins)
	table.clear(skinOf)
	table.clear(skinTexOf)
	table.clear(pops)
	popsLive = 0
	for _, l in pairs(lines) do
		table.clear(l.crates)
		table.clear(l.startAt)
		table.clear(l.doneAt)
		table.clear(l.strokeAt)
		local tw = l.tween
		if tw then
			tw:Cancel()
		end
		l.tween = nil
		l.heap = nil
		l.machine = nil
		restoreDecal(l)
		l.skin = nil
		l.skinTex = nil
		l.active = false
		l.mBelt = nil
	end
	table.clear(activeList)
	activeCount = 0
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

-- a pooled local part: anchored, no collide / query / touch, no shadow, hidden until handed out
local function newLocalPart(name: string): BasePart
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.CanCollide = false
	p.CanTouch = false
	p.CanQuery = false
	p.CastShadow = false
	p.Transparency = 1
	p.Parent = crateFolder()
	return p
end

-- the product look of a business at a look tier (BusinessConfig.Products; HEAD's Crates look as the fallback)
local function lookFor(def: BusinessConfig.BusinessDef, tier: string): ProductLook
	local byTier = BusinessConfig.Products[def.Id]
	local look = if byTier then byTier[tier] else nil
	if look then
		return look
	end
	local have = fallbackLooks[def.Product]
	if have then
		return have
	end
	local c = BusinessConfig.Crates[def.Product]
	local made: ProductLook = if c
		then { Size = c.Size, Shape = c.Shape, RawColor = c.Color, RawMaterial = c.Material, Color = c.Color, Material = c.Material }
		else {
			Size = Vector3.new(1.2, 0.8, 0.9),
			RawColor = Color3.fromRGB(120, 122, 118),
			RawMaterial = Enum.Material.Metal,
			Color = Color3.fromRGB(92, 104, 64),
			Material = Enum.Material.Metal,
		}
	fallbackLooks[def.Product] = made
	return made
end

-- dress a product part in `look` (Shape / Size only when the look changed), raw or done
local function wear(p: BasePart, look: ProductLook, done: boolean)
	if skinOf[p] ~= look then
		skinOf[p] = look
		if p:IsA("Part") then
			local shape = look.Shape or Enum.PartType.Block
			if p.Shape ~= shape then
				p.Shape = shape
			end
		end
		p.Size = look.Size
	end
	p.Color = if done then look.Color else look.RawColor
	p.Material = if done then look.Material else look.RawMaterial
end

local function takeCrate(): BasePart
	local n = #freeCrates
	if n > 0 then
		local c = freeCrates[n]
		freeCrates[n] = nil
		return c
	end
	return newLocalPart("Crate")
end

-- hide the LAST product of the line and give it back to the pool
local function releaseLast(l: Line)
	local i = #l.crates
	local c = l.crates[i]
	l.crates[i] = nil
	l.startAt[i] = nil
	l.doneAt[i] = nil
	l.strokeAt[i] = nil
	if c.Transparency ~= 1 then
		c.Transparency = 1
	end
	table.insert(freeCrates, c)
end

local function releaseHeap(l: Line)
	local h = l.heap
	if h then
		l.heap = nil
		h.Transparency = 1
		table.insert(freeHeaps, h)
	end
end

local function releaseMachine(l: Line)
	local tw = l.tween
	if tw then
		tw:Cancel() -- going idle: stop the stroke, then write the rest pose (a cancelled Tween leaves it mid-stroke)
	end
	l.tween = nil
	local mp = l.machine
	if mp then
		l.machine = nil
		mp.CFrame = l.restCF
		mp.Transparency = 1
		table.insert(freeMachines, mp)
	end
end

local function releaseSkin(l: Line)
	restoreDecal(l)
	local s = l.skin
	if s then
		l.skin = nil
		l.skinTex = nil
		local t = skinTexOf[s]
		if t then
			t.Transparency = 1
		end
		table.insert(freeSkins, s)
	end
end

local function releaseAll(l: Line)
	for _ = 1, #l.crates do
		releaseLast(l)
	end
	releaseHeap(l)
	releaseMachine(l)
	releaseSkin(l)
	l.active = false
	l.mBelt = nil -- measure() again (and take a heap / machine) when the line comes back
end

-- grow / shrink the line's products to the current pool (from the pool first; a new Part only while warming up)
local function fit(l: Line)
	while #l.crates > maxCrates do
		releaseLast(l)
	end
	while #l.crates < maxCrates do
		local c = takeCrate()
		wear(c, l.look, false)
		table.insert(l.crates, c)
		table.insert(l.startAt, -1)
		table.insert(l.doneAt, -1)
		table.insert(l.strokeAt, -1)
	end
end

-- a new look tier (Field L1-2, Works L3-4, Arsenal L5): the line's products are re-skinned in place (0 new
-- Instances); the heap and machine colours follow in fitHeap / fitMachine (measure() runs on every level change)
local function reskin(l: Line, tier: string)
	l.tier = tier
	local look = lookFor(l.def, tier)
	l.look = look
	for j, c in ipairs(l.crates) do
		wear(c, look, l.startAt[j] >= 0 and l.doneAt[j] < 0)
	end
end

---------------------------------------------------------------------------------------------------------------
-- the production clock (numbers only; spec §3.2, feel §8, synth/sched_lowq2.luau)
---------------------------------------------------------------------------------------------------------------

-- the heap poses for the current k and level (bin frame: rest top = bin top - RestSink; + rise(L) / k per landing)
local function fitHeap(l: Line)
	local H = V.Heap
	if not H.Enabled then
		releaseHeap(l)
		return
	end
	local h = l.heap
	if h == nil then
		h = freeHeaps[#freeHeaps]
		if h then
			freeHeaps[#freeHeaps] = nil
		else
			h = newLocalPart("Heap")
		end
		l.heap = h
	end
	local heap = h :: BasePart
	local look = l.look
	heap.Size = H.Size
	heap.Color = look.Color
	heap.Material = look.HeapMaterial or look.Material
	heap.Transparency = 0
	local rises = H.RiseByLevel
	local rise = rises[math.clamp(l.level, 1, #rises)] or 1
	local base = l.binSize.Y * 0.5 - H.RestSink - H.Size.Y * 0.5
	local k = math.max(1, l.k)
	table.clear(l.heapCF)
	for f = 0, k do
		l.heapCF[f + 1] = l.binCF * CFrame.new(0, base + rise * f / k, 0)
	end
	table.clear(l.sinkCF)
	for s = 1, SINK_STEPS do
		l.sinkCF[s] = l.binCF * CFrame.new(0, base + rise * (SINK_STEPS - s) / SINK_STEPS, 0)
	end
	l.heapShown = -1 -- move it on the next step
end

-- k = clamp(want, 1, floor(pool x period / travelTotal)), want = ProductsPerTick[L] (min LowQualityMaxK when low)
local function refreshK(l: Line, heapToo: boolean)
	local lv = math.max(1, l.level)
	local ppt = l.def.ProductsPerTick
	local want: number
	if ppt ~= nil and #ppt > 0 then
		want = ppt[math.clamp(lv, 1, #ppt)]
	else
		-- fallback while ProductsPerTick is nil: HEAD's CrateEverySec cadence, locked to the tick
		local every = l.def.CrateEverySec
		local e = math.max(0.2, every[math.clamp(lv, 1, #every)] or 2)
		want = math.floor(period / e + 0.5)
	end
	if lowMode then
		want = math.min(want, V.LowQualityMaxK)
	end
	local feasible = math.max(1, math.floor(maxCrates * period / l.travelTotal))
	local k = math.clamp(math.floor(want), 1, feasible)
	l.spacing = period / k
	if k ~= l.k then
		l.k = k
		if l.fill > k then
			l.fill = k
		end
		if heapToo then
			fitHeap(l)
		end
	end
end

-- snap the next landing onto the lattice tickAt + n x spacing - LandLeadSeconds (the nearest point, so a small tick
-- drift never skips or doubles a product); a spawn that is already due starts at once, and only a landing more than
-- half a spacing overdue is dropped
local function snap(l: Line, now: number)
	local s = l.spacing
	local lead = V.LandLeadSeconds
	local n = math.floor((l.nextLand + lead - tickAt) / s + 0.5)
	local t = tickAt + n * s - lead
	while t - l.travelTotal < now - 0.5 * s do
		t += s
	end
	l.nextLand = t
end

-- an observed WE_PassiveTick: update the smoothed phase / period, then ship every active line and re-plan it
local function onTick(now: number)
	if not tickSeen then
		tickSeen = true
		tickAt = now
	else
		local dtObs = now - lastSeen
		-- a different clock is adopted: a faster one (Studio FastPassiveIncome 1 s ticks) at once, a slower one only
		-- once two intervals in a row agree on it, because one long gap (a server hitch) is a stall, not a slower clock
		local faster = dtObs < period
		local agreed = lastDt > 0 and math.abs(dtObs - lastDt) <= 0.25 * dtObs
		if dtObs >= 0.5 and math.abs(dtObs - period) > 0.5 * period and (faster or agreed) then
			period = math.clamp(dtObs, 1, 10)
		end
		lastDt = dtObs
		local p = period
		local n = math.max(1, math.floor((now - tickAt) / p + 0.5))
		local pred = tickAt + n * p
		local err = now - pred
		if math.abs(err) > V.ResyncSeconds then
			tickAt = now -- join / hitch: re-anchor
		else
			tickAt = pred + V.PhaseGain * err
			if n == 1 then
				period = math.clamp(p + V.PeriodEma * V.PhaseGain * err, 1, 10)
			end
		end
	end
	lastSeen = now
	for i = 1, activeCount do
		local l = activeList[i]
		if l.active then
			-- ship: the heap sinks from where it stands (SinkSteps steps, <= 0.15 s)
			local f0 = l.fill
			l.fill = 0
			if l.heap ~= nil and f0 > 0 then
				l.sink = math.clamp(math.floor(SINK_STEPS - SINK_STEPS * f0 / math.max(1, l.k)) + 1, 1, SINK_STEPS)
			end
			refreshK(l, true)
			snap(l, now)
		end
	end
end

---------------------------------------------------------------------------------------------------------------
-- measure(): every cached CFrame / Vector3 the step uses (runs in the scan, only when something changed)
---------------------------------------------------------------------------------------------------------------

local function machineColor(l: Line): Color3
	local c = BusinessConfig.MachineColors[l.tier]
	if typeof(c) == "Color3" then
		return c
	elseif type(c) == "string" then
		local pal = (l.def.Palette :: any)[c]
		if typeof(pal) == "Color3" then
			return pal
		end
	end
	return Color3.fromRGB(52, 54, 50)
end

-- business-local arm pose: hinge, Yaw toward +Z, pitch (+ = tip up), arm centre half its length out (L1a contract)
local function hingeCF(M: MachineDef, hinge: Vector3, pitch: number): CFrame
	return CFrame.new(hinge)
		* CFrame.Angles(0, -math.rad(M.Yaw or 0), 0)
		* CFrame.Angles(0, 0, math.rad(pitch))
		* CFrame.new(M.Size.X * 0.5, 0, 0)
end

-- the line's machine: rest / hit poses in the Kit_Belt frame, one Tween (Reverses) to the hit, the rest pose written
local function fitMachine(l: Line, beltTop: number)
	local M = l.mdef
	if M == nil or not V.Machines.Enabled then
		releaseMachine(l)
		return
	end
	local mp = l.machine
	if mp == nil then
		mp = freeMachines[#freeMachines]
		if mp then
			freeMachines[#freeMachines] = nil
		else
			mp = newLocalPart("Machine")
		end
		l.machine = mp
	end
	local part = mp :: BasePart
	part.Size = M.Size
	part.Color = machineColor(l)
	part.Material = BusinessConfig.MachineMaterial
	part.Transparency = 0
	local restL: CFrame, hitL: CFrame
	local hinge = M.Hinge
	if hinge then
		restL = hingeCF(M, hinge, M.RestPitch or 0)
		hitL = hingeCF(M, hinge, M.HitPitch or 0)
	else
		local pos = M.Pos or Vector3.zero
		restL = CFrame.new(pos)
		local hitPos = M.HitPos
		if hitPos then
			hitL = CFrame.new(hitPos)
		elseif M.HitOnProduct then
			hitL = CFrame.new(pos.X, beltTop + l.look.Size.Y + M.Size.Y * 0.5, pos.Z) -- touches the product's top
		else
			hitL = restL
		end
	end
	local hit = l.frame * hitL
	l.restCF = l.frame * restL
	l.tip = if hinge
		then hit:PointToWorldSpace(Vector3.new(M.Size.X * 0.5, -M.Size.Y * 0.5, 0))
		else hit:PointToWorldSpace(Vector3.new(0, -M.Size.Y * 0.5, 0))
	l.sparks = M.Sparks == true
	l.strokeLead = M.StrokeDown
	local old = l.tween
	if old then
		old:Cancel()
	end
	local info = TweenInfo.new(math.max(0.05, M.StrokeDown), Enum.EasingStyle.Quad, Enum.EasingDirection.In, 0, true)
	l.tween = TweenService:Create(part, info, { CFrame = hit })
	part.CFrame = l.restCF -- after every measure(): a Tween plays from the value it finds, Reverses returns there
end

-- BeltFx (OD-7, ships OFF): a transparent skin over the belt whose Texture scrolls at the belt speed
local function fitSkin(l: Line, belt: BasePart)
	local B = V.BeltFx
	if not V.BeltFx.Enabled then
		releaseSkin(l)
		return
	end
	local s: BasePart, t: Texture
	local ls, lt = l.skin, l.skinTex
	if ls and lt then
		s, t = ls, lt
	else
		local n = #freeSkins
		if n > 0 then
			s = freeSkins[n]
			freeSkins[n] = nil
			t = skinTexOf[s]
		else
			s = newLocalPart("BeltSkin")
			t = Instance.new("Texture")
			t.Face = Enum.NormalId.Top
			t.Texture = B.Image
			t.Color3 = B.Tint
			t.StudsPerTileU = TILE
			t.StudsPerTileV = TILE
			t.Parent = s
			skinTexOf[s] = t
		end
		l.skin = s
		l.skinTex = t
	end
	s.Size = Vector3.new(belt.Size.X, 0.05, belt.Size.Z)
	s.CFrame = belt.CFrame * CFrame.new(0, belt.Size.Y * 0.5 + B.Lift - 0.025, 0) -- its top face sits Lift over the belt
	t.Transparency = 0
	l.scrollU = B.ScrollAxis ~= "V"
	if B.HideDressDecal then
		local d = belt:FindFirstChildOfClass("Decal")
		if d ~= l.decal then
			restoreDecal(l)
			if d then
				l.decal = d
				l.decalT = d.Transparency
				d.Transparency = 1 -- the dressed belt's own arrows hide while the scrolling skin shows
			end
		end
	end
end

local function measure(l: Line, belt: BasePart, bin: BasePart)
	local bcf = belt.CFrame
	local len = belt.Size.X
	-- the line runs along the belt's X toward the bin (sign from where the bin sits, as HEAD)
	local dir = if bcf:PointToObjectSpace(bin.Position).X >= 0 then 1 else -1
	local oriented = if dir > 0 then bcf else bcf * FLIP
	local frame = oriented * CFrame.new(-KIT_BELT_OFFSET)
	l.frame = frame
	l.binCF = bin.CFrame
	l.binSize = bin.Size
	l.binTop = bin.Position + Vector3.new(0, bin.Size.Y * 0.5, 0)
	l.popOffset = oriented:VectorToWorldSpace(V.PopOffset)
	l.popLow = oriented:VectorToWorldSpace(V.PopDodge.LowOffset)
	-- belt speed and times at this level
	local speeds = V.BeltSpeedByLevel
	local speed = math.max(0.1, speeds[math.clamp(l.level, 1, #speeds)] or V.BeltSpeed)
	l.speed = speed
	l.beltTime = math.max(0.25, len / speed)
	l.travelTotal = l.beltTime * (1 + math.max(0.05, V.DropFrac))
	local M = l.mdef
	l.hitDelay = if M then math.clamp(M.HitAlong, 0, len) / speed else 0
	-- the path: a CFrame every 1 / PathHz s of travel along the belt top, then the drop to the bin's top face centre
	local fxLift = if V.BeltFx.Enabled then V.BeltFx.Lift + 0.02 else 0
	local lift = belt.Size.Y * 0.5 + l.look.Size.Y * 0.5 + fxLift
	local p0 = frame * (KIT_BELT_OFFSET + Vector3.new(-0.5 * len, lift, 0))
	local p1 = frame * (KIT_BELT_OFFSET + Vector3.new(0.5 * len, lift, 0))
	local along = p1 - p0
	local drop = (bin.Position + Vector3.new(0, bin.Size.Y * 0.5, 0)) - p1
	local rot = frame.Rotation
	local beltTime, total = l.beltTime, l.travelTotal
	local n = math.ceil(total * PATH_HZ) + 1
	local path = l.path
	table.clear(path)
	for i = 1, n do
		local t = math.min((i - 1) / PATH_HZ, total)
		local pos = if t <= beltTime then p0 + along * (t / beltTime) else p1 + drop * ((t - beltTime) / (total - beltTime))
		path[i] = rot + pos
	end
	l.pathN = n
	l.park = path[1]
	refreshK(l, false)
	fitHeap(l)
	fitMachine(l, KIT_BELT_OFFSET.Y + belt.Size.Y * 0.5 + fxLift)
	fitSkin(l, belt)
	l.mBelt = belt
	l.mBeltCF = bcf
	l.mBeltSize = belt.Size
	l.mBinCF = bin.CFrame
	l.mBinSize = bin.Size
	l.mLevel = l.level
	l.mPool = maxCrates
	l.mLow = lowMode
end

-- an own line in range: look tier, pool size, measure() on a change, and a fresh plan when it (re)starts
local function prepare(l: Line, belt: BasePart, bin: BasePart, lv: number)
	local was = l.active
	l.level = lv
	local tier = BusinessConfig.LookTierFor(lv).Name
	if tier ~= l.tier then
		reskin(l, tier)
	end
	fit(l)
	if
		belt ~= l.mBelt
		or belt.CFrame ~= l.mBeltCF
		or belt.Size ~= l.mBeltSize
		or bin.CFrame ~= l.mBinCF
		or bin.Size ~= l.mBinSize
		or lv ~= l.mLevel
		or maxCrates ~= l.mPool
		or lowMode ~= l.mLow
	then
		measure(l, belt, bin)
		if was then
			snap(l, clock) -- a level / quality change mid-run: back onto the tick lattice (prototype case E)
		end
	end
	if not was then
		l.fill = 0
		l.sink = 0
		l.heapShown = -1
		l.firstLand = false
		l.nextLand = clock + l.travelTotal
		snap(l, clock)
	end
end

-- InstantFirstProduct: one product appears at the belt end and drops straight onto the heap (<= 0.9 s), so the
-- first beat after a buy is never empty
local function firstProduct(l: Line)
	local look = l.look
	for j = 1, #l.crates do
		if l.startAt[j] < 0 then
			local c = l.crates[j]
			c.Color = look.Color
			c.Material = look.Material
			local s = clock - l.beltTime
			c.CFrame = l.path[math.clamp(math.floor((clock - s) * PATH_HZ) + 1, 1, l.pathN)] -- placed before it shows
			c.Transparency = 0
			l.startAt[j] = s
			l.doneAt[j] = -1
			l.strokeAt[j] = -1
			return
		end
	end
end

-- a real level-up (a rise of a seen line, spec §3.7): gold burst, the first product, one clack when it lands
local function levelUp(l: Line)
	fx("LevelUp", l.binTop)
	l.firstLand = true
	if V.InstantFirstProduct then
		firstProduct(l)
	end
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
	local mkey = def.Machine
	local mdef: MachineDef? = if mkey then BusinessConfig.Machines[mkey] else nil
	local zero = Vector3.zero
	local ident = CFrame.identity
	lines[inst] = {
		model = inst,
		def = def,
		mdef = mdef,
		level = 0,
		seenLevel = nil, -- first sight is never a rise
		active = false,
		tier = "",
		look = lookFor(def, BusinessConfig.LookTierFor(1).Name),
		crates = {},
		startAt = {},
		doneAt = {},
		strokeAt = {},
		k = 0,
		spacing = TICK_SECONDS,
		speed = V.BeltSpeed,
		beltTime = 1,
		travelTotal = 1.25,
		hitDelay = 0,
		strokeLead = 0,
		nextLand = 0,
		fill = 0,
		firstLand = false,
		heap = nil,
		heapCF = {},
		sinkCF = {},
		sink = 0,
		heapShown = -1,
		machine = nil,
		tween = nil,
		restCF = ident,
		sparks = false,
		weldNear = false,
		skin = nil,
		skinTex = nil,
		scrollU = true,
		decal = nil,
		decalT = 0,
		path = {},
		pathN = 1,
		park = ident,
		frame = ident,
		binCF = ident,
		binSize = zero,
		binTop = zero,
		tip = zero,
		popOffset = zero,
		popLow = zero,
		mBelt = nil,
		mBeltCF = ident,
		mBeltSize = zero,
		mBinCF = ident,
		mBinSize = zero,
		mLevel = -1,
		mPool = -1,
		mLow = false,
		popMark = 0,
	}
end

local function untrack(inst: Instance)
	local l = lines[inst :: any]
	if l then
		releaseAll(l)
		l.seenLevel = nil -- streamed out / destroyed: the next sighting is a first sight
		lines[inst :: any] = nil
	end
end

-- 4 Hz: ownership, level (seenLevel), parts, distance -> active / idle, pools, measure() on a change
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
		local mine = isMine(m)
		local lv = if mine then levelOf(m) else 0
		local rose = false
		if mine then
			if l.seenLevel ~= nil and lv > l.seenLevel then
				rose = true -- a real buy (or admin set) on a line already seen: never join, stream-in, hand-out, respawn
			end
			l.seenLevel = lv -- kept while the character is missing and across a local folder rebuild
		else
			l.seenLevel = nil -- not ours (any more): the next own sighting is a first sight
		end
		local want = false
		if at ~= nil and mine and lv >= 1 then
			local belt = m:FindFirstChild("Kit_Belt")
			local bin = m:FindFirstChild("Kit_Bin")
			if belt and bin and belt:IsA("BasePart") and bin:IsA("BasePart") and (belt.Position - at).Magnitude <= V.ActiveRadius then
				want = true
				l.weldNear = (belt.Position - at).Magnitude <= V.Machines.WeldRadius
				prepare(l, belt, bin, lv)
			end
		end
		if want then
			l.active = #l.crates > 0
		elseif l.active or #l.crates > 0 or l.heap ~= nil or l.machine ~= nil or l.skin ~= nil then
			releaseAll(l)
		end
		if l.active then
			count += 1
			activeList[count] = l
			if rose then
				levelUp(l)
			end
		end
	end
	for i = #activeList, count + 1, -1 do
		activeList[i] = nil
	end
	activeCount = count
end

-- STEP BEGIN (spec §7: arithmetic on cached values only; this region builds no CFrame, Vector3, table or string)
-- <= 20 Hz: spawn on the tick lattice, strokes, the raw -> done swap, the path, landings into the heap, the heap pose,
-- the belt skin offset; one BulkMoveTo for everything that moved
local function step(now: number)
	local n = 0
	for li = 1, activeCount do
		local l = activeList[li]
		if l.active then
			local crates, startAt, doneAt, strokeAt = l.crates, l.startAt, l.doneAt, l.strokeAt
			local look = l.look
			-- 1. spawn: the next product leaves travelTotal before its planned landing
			if now >= l.nextLand - l.travelTotal then
				for j = 1, #crates do
					if startAt[j] < 0 then
						local c = crates[j]
						c.Color = look.RawColor
						c.Material = look.RawMaterial
						c.Transparency = 0
						startAt[j] = now
						doneAt[j] = now + l.hitDelay
						strokeAt[j] = if l.tween then math.max(now, now + l.hitDelay - l.strokeLead) else -1
						l.nextLand += l.spacing
						break
					end
				end
			end
			-- 2-3. each live product: its stroke, the swap at the hit, its path entry; past the end it lands
			for j = 1, #crates do
				local s = startAt[j]
				if s >= 0 then
					local c = crates[j]
					local st = strokeAt[j]
					if st >= 0 and now >= st then
						strokeAt[j] = -1
						local tw = l.tween
						local mp = l.machine
						if tw and mp and tw.PlaybackState ~= PLAYING then
							mp.CFrame = l.restCF -- the rest pose before every Play (a stroke due mid-play is skipped)
							tw:Play()
						end
					end
					local d = doneAt[j]
					if d >= 0 and now >= d then
						doneAt[j] = -1
						c.Color = look.Color
						if look.Material ~= look.RawMaterial then
							c.Material = look.Material
						end
						if l.sparks and l.weldNear then
							fx("Sparks", l.tip)
						end
					end
					n += 1
					movedParts[n] = c
					local idx = math.floor((now - s) * PATH_HZ) + 1
					if idx > l.pathN then
						startAt[j] = -1
						doneAt[j] = -1
						strokeAt[j] = -1
						c.Transparency = 1
						movedCFrames[n] = l.park
						if l.fill < l.k then
							l.fill += 1
						end
						if l.firstLand then
							l.firstLand = false
							fx("FirstLand", l.binTop)
						end
					else
						movedCFrames[n] = l.path[idx]
					end
				end
			end
			-- 4. the heap: one entry, only when its pose changed (by fill, or a sink step after the ship)
			local heap = l.heap
			if heap then
				local code = l.fill
				local cf = l.heapCF[code + 1]
				local s = l.sink
				if s > 0 then
					cf = l.sinkCF[s]
					if s >= SINK_STEPS then
						l.sink = 0
						code = 0 -- the last sink step is the rest pose
					else
						l.sink = s + 1
						code = 100 + s
					end
				end
				if code ~= l.heapShown and cf then
					l.heapShown = code
					n += 1
					movedParts[n] = heap
					movedCFrames[n] = cf
				end
			end
			-- 5. BeltFx (flag): one texture offset write
			local tex = l.skinTex
			if tex then
				local u = (now * l.speed) % TILE * SCROLL_SIGN
				if l.scrollU then
					tex.OffsetStudsU = u
				else
					tex.OffsetStudsV = u
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
-- STEP END

local function fadePop(p: Pop, f: number)
	local title = p.title
	if title then
		title.TextTransparency = f
		title.TextStrokeTransparency = f
	end
end

local function showPop(k: number, bin: BasePart, text: string, offset: Vector3)
	local p = pops[k]
	if p == nil or p.gui.Parent == nil then
		local opts: WorldLabel.Options = {
			Name = POP_NAME,
			Color = HudConfig.Colors.Positive,
			TextSize = V.PopTextPx,
			Studs = POP_STUDS,
			Offset = offset,
			Parent = crateFolder(), -- local folder: the pool survives the bin streaming out
			BaseLabel = true, -- F4: counted by the LabelGovernor
		}
		local gui = WorldLabel.Create(bin, text, opts)
		local title = gui:FindFirstChild("Title")
		p = { gui = gui, title = if title and title:IsA("TextLabel") then title else nil, startAt = -1, offset = offset }
		pops[k] = p
	else
		p.gui.Adornee = bin
		WorldLabel.SetText(p.gui, text)
		p.gui.StudsOffsetWorldSpace = offset
		p.offset = offset
	end
	local pop = p :: Pop
	fadePop(pop, 0)
	WorldLabel.SetShown(pop.gui, true) -- F4: through WorldLabel, so a governor hold is kept
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
			local k = (now - p.startAt) / V.PopSeconds
			if k >= 1 then
				p.startAt = -1
				popsLive -= 1
				WorldLabel.SetShown(p.gui, false)
			else
				p.gui.StudsOffsetWorldSpace = p.offset + Vector3.new(0, V.PopRise * k, 0)
				fadePop(p, if k <= V.PopHold then 0 else (k - V.PopHold) / (1 - V.PopHold))
			end
		end
	end
end

-- fix round 2: is the top-centre chip up? The NEXT chip's own rule (TycoonGuideConfig.ChipRule: in your plot, not at a
-- console, no panel / driving / death / recent combat) or the tutorial's step chip (PopDodge.TutorialFlag). The NEXT
-- chip's "Hide" button and "no pick yet" are not visible from here, so this errs toward "up" (a lower pop, never a
-- covered one).
local function chipUp(): boolean
	local HudLayout = hudLayout()
	if HudLayout == nil or type(HudLayout.GetFlag) ~= "function" or type(HudLayout.EvalRule) ~= "function" then
		return false
	end
	if HudLayout.GetFlag(V.PopDodge.TutorialFlag) == true then
		return true
	end
	return TycoonGuideConfig.Enabled == true and HudLayout.EvalRule(TycoonGuideConfig.ChipRule) == true
end

-- fix round 2: the chip's slot in viewport px (Camera:WorldToViewportPoint space, the topbar row included), grown by
-- PopDodge.MarginPx and reaching up to the screen top (the topbar pills sit there too): left x, right x, bottom y.
-- The slot is HudLayout's top stack: TopStack.Top v under the topbar, Objective.Height v tall, centred on the safe
-- content, min(Objective.MaxWidth, TopStackMaxWidthV) v wide (TutorialController.chipWidthV), all times Scale().
local function chipKeepOut(cam: Camera): (number, number, number)
	local HudLayout = hudLayout()
	if HudLayout == nil or type(HudLayout.Scale) ~= "function" or type(HudLayout.TopStackMaxWidthV) ~= "function" then
		return 0, 0, -1 -- no HudLayout: nothing to keep out of
	end
	local ok, s, maxW, content = pcall(function(): (number, number, Rect?)
		local r = if type(HudLayout.ContentRect) == "function" then HudLayout.ContentRect() else nil
		return HudLayout.Scale(), HudLayout.TopStackMaxWidthV(), r
	end)
	if not ok or type(s) ~= "number" or type(maxW) ~= "number" or s <= 0 then
		return 0, 0, -1
	end
	local TS = HudConfig.TopStack
	local vp = cam.ViewportSize
	local cx = vp.X * 0.5
	if typeof(content) == "Rect" and content.Width > 1 then
		cx = (content.Min.X + content.Max.X) * 0.5
	end
	local half = math.floor(math.min(TS.Objective.MaxWidth, maxW)) * s * 0.5 + V.PopDodge.MarginPx
	local top = GuiService:GetGuiInset().Y -- the topbar row: the safe content (and the top stack) starts under it
	return cx - half, cx + half, top + (TS.Top + TS.Objective.Height) * s + V.PopDodge.MarginPx
end

-- fix round 2: can the camera see this point? One Raycast from the camera, the character excluded (the kit, the heap,
-- other lines and any dressing count); a first hit that is (nearly) invisible counts as clear. Only for the few
-- chip-clear anchors on a tick, never per frame.
local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Exclude
local rayChar: Model? = nil
local function camSees(from: Vector3, to: Vector3): boolean
	local char = player.Character
	if char ~= rayChar then
		rayChar = char
		rayParams.FilterDescendantsInstances = if char then { char } else {}
	end
	local hit = Workspace:Raycast(from, to - from, rayParams)
	if hit == nil then
		return true
	end
	local inst = hit.Instance
	return inst:IsA("BasePart") and inst.Transparency >= 0.98
end

-- the pop sits at bin centre + PopOffset, x along the line toward the bin end (measured lines; else the bin's frame).
-- Fix round 2: while the chip is up and the title would land under it, the first of PopDodge.Steps + 1 anchors on
-- PopOffset -> LowOffset whose title, at the top of its opaque rise (PopRise x PopHold), projects clear of the chip's
-- slot AND that the camera sees (camSees); none clear of the chip: LowOffset (the lowest on screen). Chip-clear ones
-- all hidden by the scene: PopOffset when the camera sees it (it shows until it rises under the chip), else the first
-- chip-clear one. Once per pop per WE_PassiveTick (<= Steps + 1 projections, <= Steps + 2 rays), never per frame.
local function popOffsetFor(l: Line, bin: BasePart, text: string): Vector3
	local high = if l.active then l.popOffset else bin.CFrame:VectorToWorldSpace(V.PopOffset)
	local D = V.PopDodge
	if not D.Enabled or not chipUp() then
		return high
	end
	local cam = Workspace.CurrentCamera
	if cam == nil then
		return high
	end
	local x0, x1, yb = chipKeepOut(cam)
	if yb < 0 then
		return high
	end
	local low = if l.active then l.popLow else bin.CFrame:VectorToWorldSpace(D.LowOffset)
	local at = bin.Position + Vector3.new(0, V.PopRise * V.PopHold, 0)
	local halfW = (D.CharWidth * V.PopTextPx * #text + 2) * 0.5
	local halfH = V.PopTextPx * 0.5 + 1
	local n = math.max(1, math.floor(D.Steps))
	local eye = cam.CFrame.Position
	local firstClear: Vector3? = nil
	for i = 0, n do
		local off = high + (low - high) * (i / n)
		local p = cam:WorldToViewportPoint(at + off)
		if p.Z <= 0 then
			return high -- behind the camera: nothing to dodge
		end
		if p.X + halfW <= x0 or p.X - halfW >= x1 or p.Y - halfH >= yb then
			if camSees(eye, at + off) then
				return off
			end
			if firstClear == nil then
				firstClear = off
			end
		end
	end
	if firstClear ~= nil then
		return if camSees(eye, at + high) then high else firstClear
	end
	return low
end

-- WE_PassiveTick changed: the production clock and the ship (every active own line), then "+$N" over the nearest
-- owned lines (level 1+, bin within PopRadius of the character) and ProductionFx.Ship at the nearest, unless a
-- Fx.HideWhen HUD flag is set (the heaps still ship)
local function popTick()
	onTick(clock)
	local at = characterPos()
	if at == nil or fxGated() then
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
			local text = TycoonMath.PopText(best.def.Id, bestLv, mult)
			showPop(shown, bestBin, text, popOffsetFor(best, bestBin, text))
			if shown == 1 then
				-- the nearest line only: sparkles + the tink (ProductionFx caps and cools them down)
				fx("Ship", if best.active then best.binTop else bestBin.Position + Vector3.new(0, bestBin.Size.Y * 0.5, 0))
			end
		end
	end
end

function BusinessVisuals.Init()
	-- droppers v1a (spec §7): boot ProductionFx first, once and pcall'd, before the started / Enabled guard
	local ProductionFx = productionFx()
	if not fxBooted and ProductionFx ~= nil then
		fxBooted = true
		pcall(ProductionFx.Init)
	end
	if started or not BusinessConfig.Enabled then
		return
	end
	started = true
	requality()
	pcall(function()
		local ugs = UserSettings():GetService("UserGameSettings") :: any
		ugs:GetPropertyChangedSignal("SavedQualityLevel"):Connect(requality)
	end)
	local HudLayout = hudLayout()
	if HudLayout ~= nil then
		pcall(function()
			HudLayout.InputModeChanged:Connect(requality) -- Automatic + touch (AutomaticTouchIsLow) follows the device
		end)
	end
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
