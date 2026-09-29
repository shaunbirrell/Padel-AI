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

	v1b (lane L3b; spec_droppers.md §3.7, §3.8, §7, §8, §10.3, §21 R1 and revision 3): the cash plate's answer to the
	player's own tap and the ATM collect sparkle. The server pays first and then sends the grabber ONE owner-only
	unreliable packet (dropPoint, amount, left, eta) on Remotes.GetUnreliableEvent(Constants.RemoteNames.DropperFx);
	nothing here sends anything back, reads money for a decision or grants anything (a lost packet loses a look, never cash).
	  * Junk is ignored: dropPoint a finite Vector3 within ManualDropperConfig.FxMaxPayloadStuds of the character,
	    amount in 1..FxMaxPayloadAmount, left in 0..1000, eta in 0..3600 (all finite).
	  * A pooled green bundle (2 parts, one reused Tween each) falls BundleDropStuds onto the drop point in
	    BundleSeconds, then hides.
	  * EVERY paid grab shows ONE world pop "+$N" over the plate at once, with the Drop.Coin chirp (the one pooled pop:
	    PopTextPx, a governed base label with the UIStroke "CashPopGlow" and the WorldLabelConfig.PriorityAttribute, so the
	    LabelGovernor keeps it first and the cap of 3 holds). Nothing holds, cancels or attributes it (revision 3, a lead
	    decision: at least one "+$", at most two). When the ATM collects the grab at once (the walk-in circle), its own
	    pill float shows the same money at the cash pill as well, exactly as today; that is HEAD's double signal.
	  * The grabbed plate's own "$75" tag hides while its pop shows (WorldLabel.SetShown), so the pop takes its place.
	  * Refix 1: a zoomed-out camera (the pop's path beyond its MaxDistance) still gets the pop: it is drawn
	    PopNearCameraStuds from the camera on the line of sight to the plate, so it covers the plate on screen, and the
	    chirp plays there (popSpot; one camera read per grab).
	  * The plate response answers the player's own tap, so it ignores Fx.HideWhen except "Dead". ReducedMotion keeps
	    the pop and the chirp and drops the bundle fall and the pop rise. Fx.Enabled = false drops the bundle only.
	  * "Recharging" (the budget holds no bundle): both of the player's plates (same PlotId) read RechargeTag and their
	    prompt pills are hidden (PromptController.SetSuppressed) until the next bundle is ready. Two sources, the same
	    server clock: the packet's left = 0 / eta (fast), and the server-authoritative Player attribute
	    ManualDropperConfig.RechargeAttribute (Workspace:GetServerTimeNow() when the next bundle is ready; nil once the
	    budget holds one), which is reliable, so it still works when that unreliable packet is lost, and it is stamped
	    again on a same-server rejoin and on a refused tap. A 4 Hz check runs only while a recharge is pending (it also
	    catches a plate that streams in). The server stays the judge: a tap during it gets the throttled toast.
	    Refix 2: while a tag reads RechargeTag it carries WorldLabelConfig.PriorityAttribute (the LabelGovernor keeps it
	    first, within the cap of 3; cleared when the recharge ends), and a late left >= 1 packet does not end a recharge
	    the server's attribute still stands behind.
	  * ATM sparkle: WE_PendingCash dropping from > 0 to 0 within Fx.AtmRadius of WE_AtmPos: Fx.AtmEmit sparkles
	    (AtmEmitLow on low FX) at WE_AtmPos + 4 studs, through the same gates and bucket as the line sparkles.
	No per-frame work: the pop and bundle ends are one task.delay each, the recharge check is 4 Hz while pending only.
	Everything is found through the packet's world position, the plate tag and Player attributes, so nothing assumes a
	streamed part exists.
]]

local CollectionService = game:GetService("CollectionService")
local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Shared = ReplicatedStorage:WaitForChild("Shared", 60) -- BusinessVisuals already waited for it; bounded anyway
local BusinessConfig = require(Shared.Configs.BusinessConfig)
local SoundConfig = require(Shared.Configs.SoundConfig)
local Constants = require(Shared.Constants)
local Remotes = require(Shared.Remotes)
local ManualDropperConfig = require(Shared.Configs.ManualDropperConfig)
local WorldLabelConfig = require(Shared.Configs.WorldLabelConfig)
local WorldLabel = require(Shared.Util.WorldLabel)

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
	-- v1b plate: Packets, Junk, Dead, Pops, NoPop, Bundles, Recharge (a recharge started), RechargeAttr (one came from
	-- the server attribute), Restored, NoRemote, Bound (the DropperFx listener is connected)
	Plate: { [string]: number },
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
	Plate = {},
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
	-- claude-bud JOB 8: the automatic low tier (QualityGovernor: small screen / low FPS) also means low FX
	if game:GetService("Players").LocalPlayer:GetAttribute("WE_LowQuality") == true then
		return true
	end
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

---------------------------------------------------------------------------------------------------------------
-- v1b: the cash plate's answer to the player's own tap (DropperFx) and the ATM collect sparkle
---------------------------------------------------------------------------------------------------------------

local MD = ManualDropperConfig
local PLATE_TAG = "WE_ManualDropper" -- ManualDropperService's plate tag
local PLATE_LABEL = "WE_DropperLabel" -- the plate's "$75" tag (a governed base label, owner-only)
local PLATE_PROMPT = "DropPrompt" -- the plate's "Grab Cash" prompt (its pill is PromptController's)
local COIN_KEY = "Drop.Coin"
local DEAD_FLAG = "Dead" -- the one Fx.HideWhen flag the plate response obeys
local PRIORITY_ATTR = WorldLabelConfig.PriorityAttribute
local OWNER_ATTR = WorldLabelConfig.OwnerAttribute -- the plate tag's owner (the server keeps it on the plot owner)

local function cfgNum(v: any, default: number): number
	local n = tonumber(v)
	if n == nil or n ~= n or math.abs(n) == math.huge then
		return default
	end
	return n
end

local MAX_AMOUNT = cfgNum(MD.FxMaxPayloadAmount, 10000)
local MAX_STUDS = cfgNum(MD.FxMaxPayloadStuds, 60)
local BUNDLE_SECONDS = math.max(0.05, cfgNum(MD.BundleSeconds, 0.35))
local BUNDLE_DROP = math.max(0, cfgNum(MD.BundleDropStuds, 3.5))
local BUNDLE_SIZE: Vector3 = if typeof(MD.BundleSize) == "Vector3" then MD.BundleSize else Vector3.new(1.4, 0.6, 0.9)
local BUNDLE_COLOR: Color3 = if typeof(MD.BundleColor) == "Color3" then MD.BundleColor else Color3.fromRGB(86, 150, 80)
local BUNDLE_LIFT = Vector3.new(0, BUNDLE_SIZE.Y * 0.5, 0) -- the drop point is where the bundle's BOTTOM lands
local BUNDLE_FALL = Vector3.new(0, BUNDLE_DROP, 0)
local POP_SECONDS = math.max(0.1, cfgNum(MD.PopupDuration, 0.55))
local POP_START = Vector3.new(0, 1.2, 0) -- HEAD's pop start over the plate top
local POP_END = POP_START + Vector3.new(0, math.max(0, cfgNum(MD.PopupRiseStuds, 3.2)), 0)
local POP_FADE_TO = 0.85 -- HEAD's end transparency
-- refix 1 (review rv4_feedback_1): a pop whose path would pass the pop's MaxDistance from the camera (a zoomed-out phone
-- camera: the grab prompt reaches 12 studs, the default max zoom is 400) is drawn this far from the camera on the same
-- line of sight instead: it still covers the plate on screen, the engine and the LabelGovernor draw it, and the chirp
-- plays there. Clamped below to leave room for the rise inside MaxDistance.
local POP_NEAR_CAMERA = math.max(4, cfgNum(MD.PopNearCameraStuds, 24))
local RECHARGE_TEXT: string = if type(MD.RechargeTag) == "string" then MD.RechargeTag else "Recharging"
local RECHARGE_CHECK = 0.25 -- s: the "Recharging" check runs at 4 Hz, only while a recharge is pending
-- the server's reliable "Recharging" source: a Player attribute = Workspace:GetServerTimeNow() when the next bundle is
-- ready, nil while the budget holds one (ManualDropperService stamps it; a lost DropperFx packet or a rejoin keeps it)
local RECHARGE_ATTR: string = if type(MD.RechargeAttribute) == "string" then MD.RechargeAttribute else "WE_DropRechargeAt"
local ATM_LIFT = Vector3.new(0, 4, 0)

local plateStarted = false
local remoteBinding = false
local plates: { [BasePart]: boolean } = {} -- every tagged plate streamed in on this client
local lastPlotId: number? = nil -- the plot of the last plate a packet matched (both plates share one budget)

-- pools (made once; never destroyed here)
local fxFolder: Folder? = nil
local bundles: { BasePart } = {}
local bundleTween: { any } = {}
local bundleLand: { Vector3 } = {}
local bundleToken: { number } = { 0, 0 }
local bundleNext = 0
local popAnchor: Attachment? = nil
local popGui: BillboardGui? = nil
local popTitle: TextLabel? = nil
local popRise: Tween? = nil
local popFade: Tween? = nil
local popToken = 0
local popTag: BillboardGui? = nil -- the plate tag hidden while the pop shows

-- "Recharging" (the budget holds no bundle): until when (os.clock), on which plot, and what was written
local rechargeUntil = 0
local rechargePlot: number? = nil
local rechargeChecking = false
local suppressedPrompts: { [ProximityPrompt]: boolean } = {}
local tagText: { [BillboardGui]: string } = {} -- a tag we wrote RechargeTag on -> its text before that
-- refix 2: a tag we gave the LabelGovernor priority while it reads RechargeTag (cleared when the recharge ends)
local priorityTags: { [BillboardGui]: boolean } = {}

local lastPending = 0 -- the last WE_PendingCash seen (the ATM sparkle fires on > 0 -> 0)

local function plateCount(key: string)
	count(stats.Plate, key, 1)
end

-- a Controllers-folder module, lazily and pcall'd (PromptController is a C5 file: read-only use)
local function controller(name: string): any
	local key = "Controllers/" .. name
	local cached = siblingCache[key]
	if cached ~= nil then
		return if cached == false then nil else cached
	end
	local ok, m = pcall(function(): any
		local here: any = script
		local modules = here.Parent
		local ctrls = modules and modules.Parent and modules.Parent:FindFirstChild("Controllers")
		local mod = ctrls and ctrls:FindFirstChild(name)
		if mod and mod:IsA("ModuleScript") then
			local req: any = require
			return req(mod)
		end
		return nil
	end)
	local value = if ok and typeof(m) == "table" then m else false
	siblingCache[key] = value
	return if value == false then nil else value
end

local function isDead(): boolean
	local hud = sibling("HudLayout")
	if hud == nil or typeof(hud.GetFlag) ~= "function" then
		return false
	end
	local ok, v = pcall(hud.GetFlag, DEAD_FLAG)
	return ok and v == true
end

-- the LabelGovernor decides at once (its 4 Hz pass would leave the shown pop held for up to 0.25 s)
local function governorPass()
	local gov = sibling("LabelGovernor")
	if gov and typeof(gov.Pass) == "function" then
		pcall(gov.Pass)
	end
end

local function finiteIn(v: any, lo: number, hi: number): boolean
	return typeof(v) == "number" and v == v and v >= lo and v <= hi
end

-- spec §10.3: the server never sends values outside these ranges; anything else is dropped (0 errors)
local function validPayload(dropPoint: any, amount: any, left: any, eta: any): boolean
	if not finitePos(dropPoint) then
		return false
	end
	if not (finiteIn(amount, 1, MAX_AMOUNT) and finiteIn(left, 0, 1000) and finiteIn(eta, 0, 3600)) then
		return false
	end
	local at = characterPos()
	return at ~= nil and (at - (dropPoint :: Vector3)).Magnitude <= MAX_STUDS
end

---------------------------------------------------------------------------------------------------------------
-- plates (found through their tag: streaming-safe, never assumed present)
---------------------------------------------------------------------------------------------------------------

local function trackPlate(inst: Instance)
	if inst:IsA("BasePart") then
		plates[inst] = true
	end
end

local function untrackPlate(inst: Instance)
	plates[inst :: BasePart] = nil
end

local function plotOf(plate: BasePart): number?
	local id = plate:GetAttribute("PlotId")
	return if typeof(id) == "number" then id else nil
end

-- the plate the bundle falls on: its centre is the drop point's X/Z (the dress can raise the Y)
local function plateAt(pos: Vector3): BasePart?
	local best: BasePart? = nil
	local bestD = 2.5
	for plate in pairs(plates) do
		if plate.Parent ~= nil then
			local p = plate.Position
			local dx, dz = p.X - pos.X, p.Z - pos.Z
			local d = math.sqrt(dx * dx + dz * dz)
			if d <= bestD then
				best, bestD = plate, d
			end
		end
	end
	return best
end

local function tagOf(plate: BasePart?): BillboardGui?
	local tag = plate and plate:FindFirstChild(PLATE_LABEL)
	if tag and tag:IsA("BillboardGui") then
		return tag
	end
	return nil
end

-- the player's own plot without a packet (a rejoin, a lost packet): the last plot a packet matched, else a tracked plate
-- whose tag belongs to this player (the server keeps the tag's owner attribute on the plot owner, every 2 s)
local function ownPlot(): number?
	if lastPlotId ~= nil then
		return lastPlotId
	end
	for plate in pairs(plates) do
		local tag = tagOf(plate)
		if plate.Parent ~= nil and tag and tag:GetAttribute(OWNER_ATTR) == player.UserId then
			local id = plotOf(plate)
			if id ~= nil then
				lastPlotId = id
				return id
			end
		end
	end
	return nil
end

-- Workspace:GetServerTimeNow() (the clock the server stamps RechargeAttribute with); nil if it cannot be read
local function readServerTime(): any
	return (Workspace :: any):GetServerTimeNow()
end

local function serverNow(): number?
	local ok, t = pcall(readServerTime)
	if ok and typeof(t) == "number" and t == t and math.abs(t) < math.huge then
		return t
	end
	return nil
end

---------------------------------------------------------------------------------------------------------------
-- "Recharging" (the budget holds no bundle): both own plates' tags read RechargeTag and their pills hide until the
-- next bundle is ready. Started by a packet with left = 0 (eta) or by the server's RechargeAttribute (reliable).
---------------------------------------------------------------------------------------------------------------

local function writeRecharge()
	if rechargePlot == nil then
		rechargePlot = ownPlot() -- a rejoin: the plates (or their owner tag) may stream in after the attribute
		if rechargePlot == nil then
			return
		end
	end
	local pc = controller("PromptController")
	local ranked = false
	for plate in pairs(plates) do
		if plate.Parent ~= nil and plotOf(plate) == rechargePlot then
			local prompt = plate:FindFirstChild(PLATE_PROMPT)
			if prompt and prompt:IsA("ProximityPrompt") and pc and typeof(pc.SetSuppressed) == "function" then
				-- every tick (PromptController ignores a repeat): a prompt that streamed out and back in is hidden again
				if pcall(pc.SetSuppressed, prompt, true) then
					suppressedPrompts[prompt] = true
				end
			end
			local tag = tagOf(plate)
			local title = tag and tag:FindFirstChild("Title")
			if tag and title and title:IsA("TextLabel") then
				if tagText[tag] == nil and title.Text ~= RECHARGE_TEXT then
					tagText[tag] = title.Text
				end
				WorldLabel.SetText(tag, RECHARGE_TEXT)
				-- refix 2 (review rv4_feedback_2): "Recharging" answers the player's own taps, so the tag is kept first by
				-- the LabelGovernor like the pop (the ATM plate's tag was held off by the 3 premium-pad labels). It still
				-- counts toward the cap of 3; the pop hides this tag while it shows, so the two never compete.
				if tag:GetAttribute(PRIORITY_ATTR) ~= true then
					tag:SetAttribute(PRIORITY_ATTR, true)
					ranked = true
				end
				priorityTags[tag] = true
			end
		end
	end
	if ranked then
		governorPass() -- decide at once (the 4 Hz pass would leave it held for up to 0.25 s)
	end
end

local function endRecharge()
	rechargeUntil = 0
	local pc = controller("PromptController")
	for prompt in pairs(suppressedPrompts) do
		if pc and typeof(pc.SetSuppressed) == "function" then
			pcall(pc.SetSuppressed, prompt, false)
		end
	end
	table.clear(suppressedPrompts)
	for tag, text in pairs(tagText) do
		if tag.Parent ~= nil then
			WorldLabel.SetText(tag, text)
		end
	end
	table.clear(tagText)
	for tag in pairs(priorityTags) do
		if tag.Parent ~= nil then
			tag:SetAttribute(PRIORITY_ATTR, nil) -- refix 2: back to a plain governed label ("$75" ranks by distance)
		end
	end
	table.clear(priorityTags)
	governorPass()
	plateCount("Restored")
end

local function rechargeTick()
	local now = os.clock()
	if rechargeUntil <= 0 then
		rechargeChecking = false
		return
	end
	if now >= rechargeUntil then
		rechargeChecking = false
		endRecharge()
		return
	end
	writeRecharge() -- a plate that streamed in meanwhile gets it too (compare-first writes)
	task.delay(math.clamp(rechargeUntil - now, 0.01, RECHARGE_CHECK), rechargeTick)
end

-- the budget holds no bundle for `seconds` more (both sources land here; the later word wins, both come from the
-- server's own clock)
local function startRecharge(plotId: number?, seconds: number)
	if seconds <= 0 then
		return
	end
	if rechargeUntil > 0 and plotId ~= nil and rechargePlot ~= nil and rechargePlot ~= plotId then
		endRecharge() -- another plot (a plot hand-out): give the old one back first
	end
	if rechargeUntil <= 0 then
		plateCount("Recharge")
	end
	rechargeUntil = os.clock() + seconds
	if plotId ~= nil then
		rechargePlot = plotId
	end
	writeRecharge()
	if not rechargeChecking then
		rechargeChecking = true
		task.delay(math.min(seconds, RECHARGE_CHECK), rechargeTick)
	end
end

-- refix 2 (review rv4_feedback_2, Z4): the server's RechargeAttribute is set and still more than REORDER_SLACK seconds
-- in the future, so the budget holds no bundle now (an unreliable packet can arrive out of order)
local REORDER_SLACK = 0.1
local function attrSaysEmpty(): boolean
	local at = player:GetAttribute(RECHARGE_ATTR)
	local now = serverNow()
	return typeof(at) == "number" and at == at and now ~= nil and (at :: number) - now > REORDER_SLACK
end

-- a paid packet: left >= 1 ends a recharge at once, left = 0 starts one for eta. A left >= 1 packet that arrives while
-- the server's reliable attribute still says the budget is empty is an older packet delivered late: it is ignored
-- (the attribute turning nil, or the recharge's own end, gives the pill back).
local function applyRecharge(plotId: number?, left: number, eta: number)
	if left >= 1 then
		if rechargeUntil > 0 and not attrSaysEmpty() then
			endRecharge() -- a paid grab: the budget holds bundles again
		end
		return
	end
	startRecharge(plotId or ownPlot(), eta)
end

-- the server's RechargeAttribute changed (or was already set when this client started: a same-server rejoin). It is a
-- reliable attribute, so a lost left = 0 packet still hides the pill; nil = the budget holds a bundle again.
local function onRechargeAttr()
	local at = player:GetAttribute(RECHARGE_ATTR)
	if at == nil then
		if rechargeUntil > 0 then
			endRecharge()
		end
		return
	end
	local now = serverNow()
	if typeof(at) ~= "number" or at ~= at or now == nil then
		return
	end
	local seconds = (at :: number) - now
	if seconds > 0 and seconds <= 3600 then
		plateCount("RechargeAttr")
		startRecharge(ownPlot(), seconds)
	end
end

---------------------------------------------------------------------------------------------------------------
-- the bundle (2 pooled parts, one reused Tween each; a new Tween only when the landing point changes)
---------------------------------------------------------------------------------------------------------------

local function folder(): Folder
	local f = fxFolder
	if f and f.Parent then
		return f
	end
	local nf = Instance.new("Folder")
	nf.Name = "WE_ProductionFxLocal" -- local only: never under a server part
	nf.Parent = Workspace
	fxFolder = nf
	return nf
end

local function bundleAt(i: number): BasePart
	local b = bundles[i]
	if b and b.Parent then
		return b
	end
	local p = Instance.new("Part")
	p.Name = "WE_CashBundle"
	p.Size = BUNDLE_SIZE
	p.Color = BUNDLE_COLOR
	p.Material = Enum.Material.SmoothPlastic
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Transparency = 1
	p.Parent = folder()
	bundles[i] = p
	bundleTween[i] = nil
	return p
end

local function hideBundle(i: number, token: number)
	local b = bundles[i]
	if bundleToken[i] == token and b then
		b.Transparency = 1
	end
end

local function dropBundle(pos: Vector3): boolean
	if FX.Enabled ~= true or reducedMotion() then
		return false
	end
	bundleNext = bundleNext % 2 + 1
	local i = bundleNext
	local b = bundleAt(i)
	local land = pos + BUNDLE_LIFT
	local tw = bundleTween[i]
	local last: Vector3? = bundleLand[i]
	if tw == nil or last == nil or (last - land).Magnitude > 0.01 then
		if tw then
			tw:Cancel()
		end
		tw = TweenService:Create(b, TweenInfo.new(BUNDLE_SECONDS, Enum.EasingStyle.Quad, Enum.EasingDirection.In), {
			CFrame = CFrame.new(land),
		})
		bundleTween[i] = tw
		bundleLand[i] = land
	else
		tw:Cancel()
	end
	b.CFrame = CFrame.new(land + BUNDLE_FALL)
	b.Transparency = 0
	tw:Play()
	bundleToken[i] += 1
	task.delay(BUNDLE_SECONDS, hideBundle, i, bundleToken[i])
	plateCount("Bundles")
	return true
end

---------------------------------------------------------------------------------------------------------------
-- the one pooled world pop (a governed base label kept first by the LabelGovernor)
---------------------------------------------------------------------------------------------------------------

local function ensurePop(): BillboardGui?
	local gui, anchor = popGui, popAnchor
	if gui and anchor and gui.Parent == anchor and anchor.Parent then
		return gui
	end
	local terrain = Workspace:FindFirstChildOfClass("Terrain")
	if terrain == nil then
		return nil
	end
	local a = Instance.new("Attachment")
	a.Name = "WE_PlatePopAnchor"
	a.Parent = terrain
	local g = WorldLabel.Create(a, "+$0", {
		Name = "WE_PlateCashPop",
		Color = if typeof(MD.PopColor) == "Color3" then MD.PopColor else Color3.fromRGB(80, 255, 120),
		TextSize = cfgNum(MD.PopTextPx, 20),
		Studs = if typeof(MD.LabelStuds) == "Vector2" then MD.LabelStuds else Vector2.new(3, 1.2),
		Offset = POP_START,
		MaxDistance = cfgNum(MD.LabelMaxDistance, 30),
		BaseLabel = true, -- counted by the LabelGovernor (at most 3 base labels on screen)
	})
	g:SetAttribute(PRIORITY_ATTR, true) -- kept first by the LabelGovernor: it answers the player's own tap
	WorldLabel.SetShown(g, false)
	local title = g:FindFirstChild("Title")
	if title and title:IsA("TextLabel") then
		-- HEAD's dark green glow outline (replaces the ink text stroke on this label)
		local glow = Instance.new("UIStroke")
		glow.Name = "CashPopGlow"
		glow.Color = if typeof(MD.PopGlowColor) == "Color3" then MD.PopGlowColor else Color3.fromRGB(8, 36, 14)
		glow.Thickness = cfgNum(MD.PopGlowThickness, 1.4)
		glow.Parent = title
		popTitle = title
		popFade = TweenService:Create(title, TweenInfo.new(POP_SECONDS, Enum.EasingStyle.Linear), { TextTransparency = POP_FADE_TO })
	else
		popTitle = nil
		popFade = nil
	end
	popRise = TweenService:Create(g, TweenInfo.new(POP_SECONDS, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
		StudsOffsetWorldSpace = POP_END,
	})
	popAnchor, popGui = a, g
	return g
end

local function restorePopTag()
	local tag = popTag
	popTag = nil
	if tag then
		WorldLabel.SetShown(tag, true)
	end
end

local function endPop(token: number)
	if token ~= popToken then
		return -- a newer grab restarted the pop
	end
	local gui = popGui
	if gui then
		WorldLabel.SetShown(gui, false)
	end
	restorePopTag()
	governorPass()
end

-- refix 1: where the pop's anchor goes. At the plate (the packet's drop point) when the pop's whole path (start and end
-- of the rise) stays within MaxDistance - 1 of the camera; else on the camera -> pop-start line of sight, POP_NEAR_CAMERA
-- studs from the camera (clamped to MaxDistance - rise - 1), so it lands on the same screen point over the plate and is
-- always drawn. One camera read per paid grab; no per-frame work. A missing camera leaves it at the plate.
local function popSpot(pos: Vector3, maxDist: number): Vector3
	local cam = Workspace.CurrentCamera
	if cam == nil then
		return pos
	end
	local ok, camPos = pcall(function(): Vector3
		return cam.CFrame.Position
	end)
	if not ok or typeof(camPos) ~= "Vector3" or not finitePos(camPos) then
		return pos
	end
	local start = pos + POP_START
	local far = math.max((start - camPos).Magnitude, (pos + POP_END - camPos).Magnitude)
	if far <= maxDist - 1 then
		return pos
	end
	local rise = (POP_END - POP_START).Magnitude
	local near = math.min(POP_NEAR_CAMERA, math.max(4, maxDist - rise - 1))
	local ray = start - camPos
	if ray.Magnitude < 1e-3 then
		return pos
	end
	plateCount("PopNear")
	return camPos + ray.Unit * near - POP_START
end

-- the world "+$N" over the plate, with the chirp (the grab's one message and one sound)
local function showPop(pos: Vector3, amount: number, plate: BasePart?): boolean
	local gui = ensurePop()
	local anchor = popAnchor
	if gui == nil or anchor == nil then
		plateCount("NoPop")
		return false
	end
	popToken += 1
	local my = popToken
	local tag = tagOf(plate)
	if popTag and popTag ~= tag then
		restorePopTag() -- the previous pop's plate gets its tag back
	end
	if popRise then
		popRise:Cancel()
	end
	if popFade then
		popFade:Cancel()
	end
	local spot = popSpot(pos, gui.MaxDistance) -- refix 1: a far camera still gets the pop (and hears the chirp)
	anchor.WorldPosition = spot
	gui.StudsOffsetWorldSpace = POP_START
	local title = popTitle
	if title then
		title.TextTransparency = 0
	end
	WorldLabel.SetText(gui, string.format("+$%d", math.floor(amount + 0.5)))
	if tag then
		WorldLabel.SetShown(tag, false) -- the pop takes the tag's place (the cap of 3 holds)
		popTag = tag
	end
	WorldLabel.SetShown(gui, true)
	governorPass()
	if popRise and not reducedMotion() then
		popRise:Play()
	end
	if popFade then
		popFade:Play()
	end
	task.delay(POP_SECONDS, endPop, my)
	plateCount("Pops")
	sound(COIN_KEY, spot)
	return true
end

---------------------------------------------------------------------------------------------------------------
-- the grab (spec §3.7, revision 3): every paid packet shows one world pop and its chirp, at once
---------------------------------------------------------------------------------------------------------------

-- WE_PendingCash changed: the ATM paid out (> 0 -> 0) sparkles over the ATM. Nothing here reads a float or holds a pop.
local function onPendingCash()
	local v = tonumber(player:GetAttribute("WE_PendingCash")) or 0
	local was = lastPending
	lastPending = v
	if was > 0 and v <= 0 then
		local atm = player:GetAttribute("WE_AtmPos")
		if typeof(atm) == "Vector3" then
			ProductionFx.AtmCollect(atm)
		end
	end
end

local function onDropperFx(dropPoint: any, amount: any, left: any, eta: any)
	plateCount("Packets")
	if not validPayload(dropPoint, amount, left, eta) then
		plateCount("Junk")
		return
	end
	if isDead() then
		plateCount("Dead") -- no character in prompt or click range: a stray packet shows nothing
		return
	end
	local pos = dropPoint :: Vector3
	local plate = plateAt(pos)
	local plotId = if plate then plotOf(plate) else nil
	if plotId ~= nil then
		lastPlotId = plotId
	end
	applyRecharge(plotId or lastPlotId, math.floor(left :: number), eta :: number)
	dropBundle(pos)
	-- every paid grab: the world "+$N" over the plate and the chirp, at once. No hold, no cancel, no float attribution:
	-- when the ATM collects the grab at once its pill float shows it too (at most two signals, never zero).
	showPop(pos, amount :: number, plate)
end

---------------------------------------------------------------------------------------------------------------
-- the ATM collect sparkle (WE_PendingCash > 0 -> 0 near WE_AtmPos)
---------------------------------------------------------------------------------------------------------------

--[[ AtmCollect: the ATM paid out (the player's WE_PendingCash dropped to 0). Sparkles over the ATM. ]]
function ProductionFx.AtmCollect(atmPos: Vector3): boolean
	count(stats.Calls, "AtmCollect", 1)
	local why = gate(atmPos, FX.AtmRadius)
	if why then
		return drop(why)
	end
	return burst("Atm", atmPos + ATM_LIFT, if ProductionFx.IsLowFx() then FX.AtmEmitLow else FX.AtmEmit, false) > 0
end

-- deferred from Init: the bounded remote wait (Remotes.GetUnreliableEvent gives up after its own bound), then the pooled
-- pop (made now, so the LabelGovernor already tracks it before the first grab) and the listener.
-- The server makes WE_Remotes before any client runs; if the folder is not here yet, this binds when it appears
-- (a ChildAdded connection: no wait at all, and nothing is required or connected per frame meanwhile).
local function bindDropperFx()
	if ReplicatedStorage:FindFirstChild(Constants.RemotesFolderName) == nil then
		local conn: RBXScriptConnection? = nil
		conn = ReplicatedStorage.ChildAdded:Connect(function(child: Instance)
			if child.Name == Constants.RemotesFolderName and conn ~= nil then
				conn:Disconnect()
				conn = nil
				task.defer(bindDropperFx)
			end
		end)
		return
	end
	local ok, remote = pcall(function(): any
		return Remotes.GetUnreliableEvent(Constants.RemoteNames.DropperFx)
	end)
	if not ok or remote == nil then
		plateCount("NoRemote")
		remoteBinding = false
		return
	end
	pcall(ensurePop)
	remote.OnClientEvent:Connect(onDropperFx)
	plateCount("Bound")
end

-- the one task Init schedules: read RechargeAttribute once (it may be set before this client started: a same-server
-- rejoin with an empty budget), then the bounded remote bind. The read is pcall'd so it can never stop the bind.
local function afterInit()
	pcall(onRechargeAttr)
	bindDropperFx()
end

-- v1b listeners (from Init; never yields: connections only, the remote wait is deferred)
local function startPlate()
	if plateStarted then
		return
	end
	plateStarted = true
	lastPending = tonumber(player:GetAttribute("WE_PendingCash")) or 0
	player:GetAttributeChangedSignal("WE_PendingCash"):Connect(onPendingCash)
	for _, inst in ipairs(CollectionService:GetTagged(PLATE_TAG)) do
		trackPlate(inst)
	end
	CollectionService:GetInstanceAddedSignal(PLATE_TAG):Connect(trackPlate)
	CollectionService:GetInstanceRemovedSignal(PLATE_TAG):Connect(untrackPlate)
	-- "Recharging" from the server (reliable): watch it; the first read is in the one deferred start task below
	player:GetAttributeChangedSignal(RECHARGE_ATTR):Connect(onRechargeAttr)
	if not remoteBinding then
		remoteBinding = true
		task.defer(afterInit)
	end
end

--[[ Once, never yields: nothing here waits or loops. Emitters and sibling requires are made on first use.
	v1b: connects the plate / ATM / recharge listeners and defers the bounded DropperFx remote wait and the first
	recharge read (task.defer). ]]
function ProductionFx.Init()
	if initDone then
		return
	end
	initDone = true
	stats.Inits += 1
	xpcall(startPlate, function(err: any)
		warn("[ProductionFx] plate listeners failed:", err)
	end)
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
		Plate = table.clone(stats.Plate),
	}
end

return ProductionFx
