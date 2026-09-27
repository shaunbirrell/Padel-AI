--!strict
--[[
	Droppers v1a: the business-line feedback moments (spec_droppers.md §3.7, §7, §10.3). CLIENT ONLY and owner only:
	it sends nothing to the server, reads no money and creates no money. BusinessVisuals decides WHEN (the tick-locked
	ship, a real level rise, the first product of a new level landing, the welder hit); this module decides whether
	it may show and how much, then draws it.

	API (every position is a Vector3 the caller already cached; nothing here reads a server part)
	  Init()           once, never yields (BusinessVisuals.Init boots it, pcall'd, before its own guard: no
	                   Bootstrap edit). Pools are made on first use.
	  Ship(pos)        the nearest own line shipped its heap: ShipEmit gold sparkles (ShipEmitLow on low FX) and the
	                   "Biz.Ship" tink (at most one per the key's CooldownSeconds, 4 s). pos = the bin top.
	  LevelUp(pos)     a real rise of an own line's Level (first sight is never a rise; the caller keeps seenLevel):
	                   LevelEmit gold sparkles (LevelEmitLow), at most one burst per Fx.LevelBurstGap.
	  FirstLand(pos)   the first product of the new level landed: one "Biz.FirstLand" clack.
	  Sparks(pos)      the fin welder hit: Fx.WeldSparks fire sparks at the tip, own lines within Machines.WeldRadius.
	  IsQuiet() -> boolean   a Fx.HideWhen HudLayout flag is on (Driving / Dead / Modal / RecentCombat)
	  IsLowFx() -> boolean   saved Graphics Quality 1..LowQualityLevel, or Automatic on touch (not PrefersKeys)
	  GetStats() -> Stats    counters for tests
	Each effect call returns true when it showed or played something.

	Gating, in order: Fx.Enabled; a finite Vector3; no Fx.HideWhen flag (one message at a time: nothing while you
	drive, fight, are dead or have a panel open); a character within the effect's radius (Ship: PopRadius, LevelUp /
	FirstLand: ActiveRadius, Sparks: Machines.WeldRadius). Then particles skip under GuiService.ReducedMotionEnabled
	(sounds stay), and every particle goes through ONE token bucket: at most Fx.MaxParticlesPerSecond emitted in any
	1 s window. Each spent token comes back exactly 1 s after it was spent (a sliding window, not a refill rate, so a
	window can never hold a full bucket plus its refill). Lifetimes are clamped to that window, so at most
	MaxParticlesPerSecond particles are alive.

	PHONES (CLAUDE.md §1): no per-frame loop at all (no Heartbeat, no stepped callback, no thread per effect); the bucket
	refills lazily on use. Two pooled emitters (sparkles, fire sparks) with Rate = 0 (:Emit only), each on its own
	Attachment under Workspace.Terrain (always present under StreamingEnabled), the engine's own particle textures
	(0 asset loads), LightEmission <= 0.3 and no light objects. No Instance is made after the first use of each
	emitter; nothing is ever destroyed here. Sounds go through AudioController (a lazy, pcall'd sibling require;
	read-only use), which pools its voices and enforces the per-key cooldowns and the voice cap.
	A missing HudLayout / AudioController never breaks a line: the flags read as off and the sound is skipped.

	v1b (lane L3b) adds the DropperFx plate response and the ATM sparkle to this module; they share the bucket.
]]

local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared", 60) -- BusinessVisuals already waited for it; bounded anyway
local BusinessConfig = require(Shared.Configs.BusinessConfig)
local SoundConfig = require(Shared.Configs.SoundConfig)

local ProductionFx = {}

export type Stats = {
	Inits: number, -- Init calls that did the work (1 after boot)
	Emitted: number, -- particles emitted (after the bucket)
	EmitCalls: number,
	Denied: number, -- particles the bucket refused
	ByKind: { [string]: number }, -- particles per effect: Ship, LevelUp, Sparks
	Sounds: { [string]: number }, -- AudioController.Play calls that started, per key
	Calls: { [string]: number }, -- effect calls per API name
	Dropped: { [string]: number }, -- Off, Bad, Quiet, NoCharacter, Far, ReducedMotion, Gap, Cooldown, NoEmitter, NoAudio, NotPlayed
}

local V = BusinessConfig.Visual
local FX = V.Fx
local player = Players.LocalPlayer

local WINDOW = 1 -- s: the MaxParticlesPerSecond window
local SHIP_KEY = "Biz.Ship"
local FIRST_LAND_KEY = "Biz.FirstLand"

-- emitter look (motion only; texture, colour, lifetime and LightEmission come from BusinessConfig.Visual.Fx)
local LOOK = {
	SparkleSpeed = NumberRange.new(2.5, 5),
	SparkleSpread = Vector2.new(40, 40),
	SparkleFall = Vector3.new(0, -4, 0),
	SparkleSize = { 0.8, 0.15 }, -- studs at birth / death: about 7-10 px at 20-28 studs on an 800x360 phone
	SparkColor = Color3.fromRGB(255, 190, 90), -- warm tint on the engine spark texture
	SparkSpeed = NumberRange.new(6, 11),
	SparkSpread = Vector2.new(55, 55),
	SparkFall = Vector3.new(0, -35, 0),
	SparkSize = { 0.2, 0.05 },
}

local LIGHT_EMISSION = math.clamp(tonumber(FX.LightEmission) or 0.3, 0, 0.3)

local initDone = false
local siblingCache: { [string]: any } = {}

-- the two pooled emitters (made on first use, re-made only if something removed them)
local sparkleAtt: Attachment? = nil
local sparkleEm: ParticleEmitter? = nil
local sparkAtt: Attachment? = nil
local sparkEm: ParticleEmitter? = nil

-- token bucket: ringT / ringN hold the last grants (time, particles); one slot per possible grant in a window
local maxPerSecond = math.max(0, math.floor(tonumber(FX.MaxParticlesPerSecond) or 16))
local ringSize = math.max(1, maxPerSecond)
local ringT: { number } = table.create(ringSize, -math.huge)
local ringN: { number } = table.create(ringSize, 0)
local ringHead = 0

local lastBurstAt = -math.huge
local lastSoundAt: { [string]: number } = {}

local stats: Stats = {
	Inits = 0,
	Emitted = 0,
	EmitCalls = 0,
	Denied = 0,
	ByKind = {},
	Sounds = {},
	Calls = {},
	Dropped = {},
}

---------------------------------------------------------------------------------------------------------------
-- helpers (no closures are made per call: the pcall'd readers are module functions)
---------------------------------------------------------------------------------------------------------------

local function drop(reason: string): boolean
	stats.Dropped[reason] = (stats.Dropped[reason] or 0) + 1
	return false
end

local function count(t: { [string]: number }, key: string, n: number)
	t[key] = (t[key] or 0) + n
end

-- lazy, pcall'd sibling require (cached; a missing or throwing module reads as nil forever)
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

local function readReducedMotion(): any
	return (GuiService :: any).ReducedMotionEnabled
end

local function readQuality(): any
	return (UserSettings():GetService("UserGameSettings") :: any).SavedQualityLevel.Value
end

local function readPreferredInput(): any
	return (UserInputService :: any).PreferredInput
end

local function reducedMotion(): boolean
	local ok, v = pcall(readReducedMotion)
	return ok and v == true
end

local function savedQuality(): number
	local ok, q = pcall(readQuality)
	return if ok and typeof(q) == "number" then q else 0 -- 0 = Automatic (or unknown)
end

-- true = keyboard / gamepad, false = touch, nil = unknown (HudLayout.PrefersKeys first: the one device rule)
local function prefersKeys(): boolean?
	local hud = sibling("HudLayout")
	if hud and typeof(hud.PrefersKeys) == "function" then
		local ok, v = pcall(hud.PrefersKeys)
		if ok and typeof(v) == "boolean" then
			return v
		end
	end
	local ok, v = pcall(readPreferredInput)
	if ok and typeof(v) == "EnumItem" then
		return (v :: EnumItem).Name ~= "Touch"
	end
	return nil
end

local function characterPos(): Vector3?
	local char = player.Character
	local hrp = char and char:FindFirstChild("HumanoidRootPart")
	if hrp and hrp:IsA("BasePart") then
		return hrp.Position
	end
	return nil
end

local function finitePos(pos: any): boolean
	if typeof(pos) ~= "Vector3" then
		return false
	end
	local p = pos :: Vector3
	local x, y, z = p.X, p.Y, p.Z
	return x == x and y == y and z == z and math.abs(x) < math.huge and math.abs(y) < math.huge and math.abs(z) < math.huge
end

-- a particle never outlives the bucket window, so at most MaxParticlesPerSecond are alive
local function lifetimeOf(v: any): number
	local s = tonumber(v) or 0.5
	if s ~= s then
		s = 0.5
	end
	return math.clamp(s, 0.05, WINDOW)
end

---------------------------------------------------------------------------------------------------------------
-- gating (spec §3.7 "Gating" and "Low FX")
---------------------------------------------------------------------------------------------------------------

--[[ true while any Fx.HideWhen HudLayout flag is on: no pops, sparkles or sounds (lines keep moving). ]]
function ProductionFx.IsQuiet(): boolean
	local hud = sibling("HudLayout")
	if hud == nil or typeof(hud.GetFlag) ~= "function" then
		return false
	end
	for _, name in ipairs(FX.HideWhen) do
		if hud.GetFlag(name) == true then
			return true
		end
	end
	return false
end

--[[ "Low FX": saved Graphics Quality 1..LowQualityLevel, or Automatic (0) while the device prefers touch. ]]
function ProductionFx.IsLowFx(): boolean
	local q = savedQuality()
	if q > 0 then
		return q <= V.LowQualityLevel
	end
	return prefersKeys() == false
end

-- nil = go; otherwise the reason the effect is skipped
local function gate(pos: any, radius: number): string?
	if FX.Enabled ~= true then
		return "Off"
	end
	if not finitePos(pos) then
		return "Bad"
	end
	if ProductionFx.IsQuiet() then
		return "Quiet"
	end
	local at = characterPos()
	if at == nil then
		return "NoCharacter"
	end
	if (at - (pos :: Vector3)).Magnitude > radius then
		return "Far"
	end
	return nil
end

---------------------------------------------------------------------------------------------------------------
-- token bucket (MaxParticlesPerSecond): each spent token returns exactly WINDOW seconds after it was spent
---------------------------------------------------------------------------------------------------------------

-- grants up to `want` particles now. The ring overwrites its oldest grant; that grant is always outside the
-- window, because ringSize grants of >= 1 particle inside the window would already fill the bucket.
local function grant(want: number, now: number): number
	local used = 0
	for i = 1, ringSize do
		if now - ringT[i] < WINDOW then
			used += ringN[i]
		end
	end
	local n = math.min(want, maxPerSecond - used)
	if n <= 0 then
		return 0
	end
	ringHead = ringHead % ringSize + 1
	ringT[ringHead] = now
	ringN[ringHead] = n
	return n
end

---------------------------------------------------------------------------------------------------------------
-- emitters
---------------------------------------------------------------------------------------------------------------

local function newEmitter(name: string, spark: boolean): (Attachment?, ParticleEmitter?)
	local terrain = Workspace:FindFirstChildOfClass("Terrain")
	if terrain == nil then
		return nil, nil
	end
	local a = Instance.new("Attachment")
	a.Name = name
	local e = Instance.new("ParticleEmitter")
	e.Name = "Burst"
	e.Rate = 0 -- :Emit only; nothing runs between bursts
	e.Enabled = true
	e.LockedToPart = false
	e.LightEmission = LIGHT_EMISSION
	e.EmissionDirection = Enum.NormalId.Top
	if spark then
		local life = lifetimeOf(FX.SparkLifetime)
		e.Texture = FX.SparkTexture
		e.Color = ColorSequence.new(LOOK.SparkColor)
		e.Lifetime = NumberRange.new(life * 0.6, life)
		e.Speed = LOOK.SparkSpeed
		e.SpreadAngle = LOOK.SparkSpread
		e.Acceleration = LOOK.SparkFall
		e.Drag = 1
		e.Size = NumberSequence.new({
			NumberSequenceKeypoint.new(0, LOOK.SparkSize[1]),
			NumberSequenceKeypoint.new(1, LOOK.SparkSize[2]),
		})
		e.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(1, 1) })
	else
		local life = lifetimeOf(FX.SparkleLifetime)
		e.Texture = FX.SparkleTexture
		e.Color = ColorSequence.new(FX.SparkleColor)
		e.Lifetime = NumberRange.new(life * 0.6, life)
		e.Speed = LOOK.SparkleSpeed
		e.SpreadAngle = LOOK.SparkleSpread
		e.Acceleration = LOOK.SparkleFall
		e.Drag = 2
		e.RotSpeed = NumberRange.new(-120, 120)
		e.Size = NumberSequence.new({
			NumberSequenceKeypoint.new(0, LOOK.SparkleSize[1]),
			NumberSequenceKeypoint.new(1, LOOK.SparkleSize[2]),
		})
		e.Transparency = NumberSequence.new({
			NumberSequenceKeypoint.new(0, 0),
			NumberSequenceKeypoint.new(0.7, 0.2),
			NumberSequenceKeypoint.new(1, 1),
		})
	end
	e.Parent = a
	a.Parent = terrain
	return a, e
end

local function emitterFor(spark: boolean): (Attachment?, ParticleEmitter?)
	if spark then
		local a, e = sparkAtt, sparkEm
		if a and e and a.Parent and e.Parent == a then
			return a, e
		end
		sparkAtt, sparkEm = newEmitter("WE_ProductionSparks", true)
		return sparkAtt, sparkEm
	end
	local a, e = sparkleAtt, sparkleEm
	if a and e and a.Parent and e.Parent == a then
		return a, e
	end
	sparkleAtt, sparkleEm = newEmitter("WE_ProductionSparkles", false)
	return sparkleAtt, sparkleEm
end

local function emitAt(em: ParticleEmitter, att: Attachment, pos: Vector3, n: number)
	att.WorldPosition = pos
	em:Emit(n)
end

-- `want` particles of one kind at pos, through ReducedMotion and the bucket; returns the number emitted
local function burst(kind: string, pos: Vector3, want: number, spark: boolean): number
	local w = math.floor(want)
	if w <= 0 then
		return 0
	end
	if reducedMotion() then
		drop("ReducedMotion")
		return 0
	end
	local att, em = emitterFor(spark)
	if att == nil or em == nil then
		drop("NoEmitter")
		return 0
	end
	local n = grant(w, os.clock())
	if n < w then
		stats.Denied += w - n
	end
	if n <= 0 then
		return 0
	end
	local ok = pcall(emitAt, em, att, pos, n)
	if not ok then
		drop("NoEmitter")
		return 0
	end
	stats.Emitted += n
	stats.EmitCalls += 1
	count(stats.ByKind, kind, n)
	return n
end

---------------------------------------------------------------------------------------------------------------
-- sounds (AudioController, lazily; the key's CooldownSeconds is also kept here so a skipped play costs nothing)
---------------------------------------------------------------------------------------------------------------

local function sound(key: string, pos: Vector3): boolean
	local now = os.clock()
	local def = (SoundConfig.Sounds :: any)[key]
	local gap = if type(def) == "table" then math.max(0, tonumber(def.CooldownSeconds) or 0) else 0
	local last = lastSoundAt[key]
	if last ~= nil and now - last < gap then
		return drop("Cooldown")
	end
	local audio = sibling("AudioController")
	if audio == nil or typeof(audio.Play) ~= "function" then
		return drop("NoAudio")
	end
	local ok, played = pcall(audio.Play, key, pos)
	if ok and played == true then
		lastSoundAt[key] = now
		count(stats.Sounds, key, 1)
		return true
	end
	return drop("NotPlayed")
end

---------------------------------------------------------------------------------------------------------------
-- API
---------------------------------------------------------------------------------------------------------------

--[[ Ship: the nearest own line shipped (each WE_PassiveTick). Sparkles at the bin top + the tink (<= 1 per 4 s). ]]
function ProductionFx.Ship(pos: Vector3): boolean
	count(stats.Calls, "Ship", 1)
	local why = gate(pos, V.PopRadius)
	if why then
		return drop(why)
	end
	local n = burst("Ship", pos, if ProductionFx.IsLowFx() then FX.ShipEmitLow else FX.ShipEmit, false)
	local played = sound(SHIP_KEY, pos)
	return n > 0 or played
end

--[[ LevelUp: a real rise of an own line's Level (the caller's seenLevel rule). One burst per LevelBurstGap. ]]
function ProductionFx.LevelUp(pos: Vector3): boolean
	count(stats.Calls, "LevelUp", 1)
	local why = gate(pos, V.ActiveRadius)
	if why then
		return drop(why)
	end
	local now = os.clock()
	if now - lastBurstAt < FX.LevelBurstGap then
		return drop("Gap")
	end
	local n = burst("LevelUp", pos, if ProductionFx.IsLowFx() then FX.LevelEmitLow else FX.LevelEmit, false)
	if n > 0 then
		lastBurstAt = now
	end
	return n > 0
end

--[[ FirstLand: the first product of a newly bought level landed in the heap. One metal clack. ]]
function ProductionFx.FirstLand(pos: Vector3): boolean
	count(stats.Calls, "FirstLand", 1)
	local why = gate(pos, V.ActiveRadius)
	if why then
		return drop(why)
	end
	return sound(FIRST_LAND_KEY, pos)
end

--[[ Sparks: the fin welder hit a rocket (own lines within Machines.WeldRadius). ]]
function ProductionFx.Sparks(pos: Vector3): boolean
	count(stats.Calls, "Sparks", 1)
	local why = gate(pos, V.Machines.WeldRadius)
	if why then
		return drop(why)
	end
	return burst("Sparks", pos, FX.WeldSparks, true) > 0
end

--[[ Once, never yields: nothing here waits or loops. Emitters and sibling requires are made on first use.
	(v1b, lane L3b: the DropperFx listener binds here through a deferred, bounded remote wait.) ]]
function ProductionFx.Init()
	if initDone then
		return
	end
	initDone = true
	stats.Inits += 1
end

function ProductionFx.GetStats(): Stats
	return {
		Inits = stats.Inits,
		Emitted = stats.Emitted,
		EmitCalls = stats.EmitCalls,
		Denied = stats.Denied,
		ByKind = table.clone(stats.ByKind),
		Sounds = table.clone(stats.Sounds),
		Calls = table.clone(stats.Calls),
		Dropped = table.clone(stats.Dropped),
	}
end

return ProductionFx
