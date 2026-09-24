--!strict
--[[
	Client audio (W1 SND): pooled one-shots, music, ambience and engine loops. Every key, id, volume and licence source
	lives in Shared/Configs/SoundConfig.luau; AudioHooks maps existing remotes / HUD signals onto keys.

	API
	  Init()                            idempotent (UIController and AudioHooks both call it); starts the base theme
	  Play(key, at?) -> boolean         one-shot. at = Vector3 | BasePart | Attachment | Model → 3D at that point,
	                                    nil → 2D. Returns false (never errors) for: unknown key, Id 0 / "", SFX muted,
	                                    the key's cooldown, a lower-priority Stinger inside the collapse window, a 3D
	                                    point beyond MaxDistance, the voice cap with nothing lower to steal, the server
	  Loop(channel, key?, fade?) -> boolean
	                                    sets a loop channel ("Music" | "Ambience" | "Engine" | any name) to `key`
	                                    (nil stops it) with a crossfade. A muted channel remembers its key and resumes
	                                    when unmuted. true = audible now
	  SetLoopPitch(channel, pitch)      engine pitch (AudioHooks samples the chassis speed at 10 Hz)
	  GetLoop(channel) -> string?       the channel's key (QA)
	  SetNextNotificationKey(key?)      AudioHooks: the typed key for NotificationController's next PlayNotification
	  HasSound(key) -> boolean          key exists with a playable Id
	  GetStats() -> Stats               counters (tests / Studio)
	  unchanged legacy API: PlayClick() · PlayNotification() · GetMusicVolume() · GetSfxVolume()

	PHONES (CLAUDE.md §1): no RenderStepped / Heartbeat work here; at most Mix.MaxConcurrent one-shots (2D + 3D) and
	Mix.MaxConcurrent2D of them 2D; per-key cooldowns; Sounds are pooled (no Instance churn per play) and 3D voices
	are pooled Attachments under Workspace.Terrain (always present under StreamingEnabled). Client only: nothing
	here runs on the server.
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local ClientSettings = require(script.Parent.ClientSettings)
local Shared = ReplicatedStorage:WaitForChild("Shared")
local SoundConfig = require(Shared.Configs.SoundConfig)

type SoundDef = SoundConfig.SoundDef

type Voice = {
	Key: string,
	Sound: Sound,
	Attachment: Attachment?,
	Positional: boolean,
	BusyUntil: number,
	StartedAt: number,
	Priority: number,
	Serial: number,
}

type Channel = {
	Name: string,
	Key: string?,
	Slots: { Sound }, -- two Sounds per channel, alternated for crossfades
	Gen: { number }, -- per slot: bumps on every (re)start so a pending fade-out stop never hits a reused slot
	Active: number, -- slot index that carries Key (0 = none)
	Target: number, -- volume the active slot fades to
	Resume: { [string]: number }, -- TimePosition per key (music picks up where it left off)
}

type StingerMark = { Voice: Voice, Serial: number, Priority: number, At: number }

export type Stats = {
	Started: number, -- one-shots that began playing
	Replaced: number, -- Stingers cut by a higher-priority Stinger inside the window
	LoopStarts: number, -- loop channels that began playing audibly
	Active: number,
	Active2D: number,
	Active3D: number,
	PeakActive: number,
	Dropped: { [string]: number }, -- Missing · Muted · Cooldown · Collapsed · Cap · Far · Server · Loop · Error
	ByKey: { [string]: number },
	LastKey: string?,
}

local AudioController = {}

local Mix = SoundConfig.Mix
local STOP_FADE = 0.4 -- s: MaxSeconds one-shots fade out instead of cutting

local initDone = false
local folder: Folder? = nil
local pools: { [string]: { Voice } } = {}
local playing: { Voice } = {}
local lastPlayedAt: { [string]: number } = {}
local lastStinger: StingerMark? = nil
local channels: { [string]: Channel } = {}
local pendingNotify: { Key: string, At: number }? = nil
local serial = 0
local warned: { [string]: boolean } = {}

local stats: Stats = {
	Started = 0,
	Replaced = 0,
	LoopStarts = 0,
	Active = 0,
	Active2D = 0,
	Active3D = 0,
	PeakActive = 0,
	Dropped = {},
	ByKey = {},
	LastKey = nil,
}

local function now(): number
	return os.clock()
end

local function drop(reason: string): boolean
	stats.Dropped[reason] = (stats.Dropped[reason] or 0) + 1
	return false
end

-- Sounds are a client concern: a require from server code must never create one.
local function isServerContext(): boolean
	local ok, server = pcall(function(): boolean
		return RunService:IsServer() and not RunService:IsClient()
	end)
	return ok and server == true
end

local function rawDef(key: string): SoundDef?
	local d = (SoundConfig.Sounds :: any)[key]
	if type(d) == "table" then
		return d :: SoundDef
	end
	return nil
end

local function defOf(key: string): SoundDef?
	local d = rawDef(key)
	if d == nil and not warned[key] then
		warned[key] = true
		warn("[AudioController] unknown sound key:", key)
	end
	return d
end

-- "rbxassetid://<n>" for a positive asset id, the string itself for an engine path; nil = disabled / missing
local function soundIdOf(def: SoundDef?): string?
	if def == nil then
		return nil
	end
	local id: any = def.Id
	if type(id) == "number" then
		if id >= 1 and id < math.huge then
			return "rbxassetid://" .. tostring(math.floor(id))
		end
		return nil
	elseif type(id) == "string" then
		if id ~= "" then
			return id
		end
	end
	return nil
end

local function masterFor(def: SoundDef): number
	if def.Bus == "Music" then
		return Mix.MusicMaster
	end
	return Mix.SfxMaster
end

local function volumeOf(def: SoundDef): number
	return math.clamp(def.Volume, 0, 1) * masterFor(def)
end

local function pitchOf(def: SoundDef): number
	local p = def.Pitch
	if type(p) == "number" and p > 0 then
		return p
	end
	return 1
end

local function maxDistOf(def: SoundDef): number
	if def.MaxDistance > 0 then
		return def.MaxDistance
	end
	return Mix.DefaultMaxDistance
end

local function rollOffOf(name: string): Enum.RollOffMode
	local ok, item = pcall(function(): any
		return (Enum.RollOffMode :: any)[name]
	end)
	if ok and typeof(item) == "EnumItem" then
		return item :: Enum.RollOffMode
	end
	return Enum.RollOffMode.InverseTapered
end

local function allowedFor(def: SoundDef): boolean
	if def.Bus == "Music" then
		return ClientSettings.ShouldPlayMusic()
	end
	return ClientSettings.ShouldPlaySfx()
end

local function ensureFolder(): Folder
	local f = folder
	if f and f.Parent then
		return f
	end
	local existing = SoundService:FindFirstChild("WarEmpireAudio")
	if existing and existing:IsA("Folder") then
		folder = existing
		return existing
	end
	local nf = Instance.new("Folder")
	nf.Name = "WarEmpireAudio"
	nf.Parent = SoundService
	folder = nf
	return nf
end

local function tweenVolume(s: Sound, target: number, seconds: number)
	if seconds <= 0 then
		s.Volume = target
		return
	end
	local ok = pcall(function()
		TweenService:Create(s, TweenInfo.new(seconds, Enum.EasingStyle.Linear), { Volume = target }):Play()
	end)
	if not ok then
		s.Volume = target
	end
end

local function listenerPos(): Vector3?
	local cam = Workspace.CurrentCamera
	if cam then
		local ok, p = pcall(function(): Vector3
			return cam.CFrame.Position
		end)
		if ok and typeof(p) == "Vector3" then
			return p
		end
	end
	return nil
end

local function finite(v: Vector3): boolean
	return v.X == v.X and v.Y == v.Y and v.Z == v.Z and math.abs(v.X) < math.huge and math.abs(v.Y) < math.huge and math.abs(v.Z) < math.huge
end

local function positionOf(at: any): Vector3?
	local ty = typeof(at)
	local pos: Vector3? = nil
	if ty == "Vector3" then
		pos = at :: Vector3
	elseif ty == "Instance" then
		local inst = at :: Instance
		pcall(function()
			if inst:IsA("BasePart") then
				pos = inst.Position
			elseif inst:IsA("Attachment") then
				pos = inst.WorldPosition
			elseif inst:IsA("Model") then
				pos = inst:GetPivot().Position
			end
		end)
	end
	if pos and finite(pos) then
		return pos
	end
	return nil
end

---------------------------------------------------------------------------------------------------------------
-- one-shot voices
---------------------------------------------------------------------------------------------------------------

local function prune(t: number)
	for i = #playing, 1, -1 do
		if playing[i].BusyUntil <= t then
			table.remove(playing, i)
		end
	end
end

local function stopVoice(v: Voice)
	v.BusyUntil = 0
	local i = table.find(playing, v)
	if i then
		table.remove(playing, i)
	end
	pcall(function()
		v.Sound:Stop()
	end)
end

local function count2D(): number
	local n = 0
	for _, v in ipairs(playing) do
		if not v.Positional then
			n += 1
		end
	end
	return n
end

-- the busy voice to steal for a new one of `priority`: lowest priority first, then the oldest; nil = keep them all
local function victimFor(priority: number, positional: boolean?): Voice?
	local best: Voice? = nil
	for _, v in ipairs(playing) do
		if positional == nil or v.Positional == positional then
			local b = best
			if b == nil or v.Priority < b.Priority or (v.Priority == b.Priority and v.StartedAt < b.StartedAt) then
				best = v
			end
		end
	end
	if best and best.Priority <= priority then
		return best
	end
	return nil
end

local function newVoice(key: string, def: SoundDef, positional: boolean): Voice
	local s = Instance.new("Sound")
	s.Name = key
	s.SoundId = soundIdOf(def) or ""
	s.Looped = false
	s.Volume = volumeOf(def)
	local att: Attachment? = nil
	if positional then
		local a = Instance.new("Attachment")
		a.Name = "WE_Audio"
		a.Parent = Workspace.Terrain
		s.Parent = a
		att = a
	else
		s.Parent = ensureFolder()
	end
	local v: Voice = {
		Key = key,
		Sound = s,
		Attachment = att,
		Positional = positional,
		BusyUntil = 0,
		StartedAt = 0,
		Priority = 1,
		Serial = 0,
	}
	pcall(function()
		s.Ended:Connect(function()
			v.BusyUntil = 0
		end)
	end)
	return v
end

local function acquire(key: string, def: SoundDef, positional: boolean, t: number): Voice
	local poolKey = if positional then key .. "@3D" else key
	local pool = pools[poolKey]
	if pool == nil then
		pool = {}
		pools[poolKey] = pool
	end
	local list = pool :: { Voice }
	for _, v in ipairs(list) do
		if v.BusyUntil <= t then
			return v
		end
	end
	if #list < math.max(1, Mix.PoolPerKey) then
		local v = newVoice(key, def, positional)
		table.insert(list, v)
		return v
	end
	local oldest = list[1]
	for _, v in ipairs(list) do
		if v.StartedAt < oldest.StartedAt then
			oldest = v
		end
	end
	stopVoice(oldest)
	return oldest
end

local function lengthOf(def: SoundDef, s: Sound): number
	local maxS = def.MaxSeconds
	if maxS and maxS > 0 then
		return maxS + STOP_FADE
	end
	local tl: number? = nil
	pcall(function()
		tl = s.TimeLength
	end)
	if tl and tl > 0 then
		return tl / pitchOf(def)
	end
	return def.LengthSeconds or Mix.DefaultLengthSeconds
end

local function startVoice(v: Voice, def: SoundDef, pos: Vector3?, t: number, priority: number)
	local s = v.Sound
	local id = soundIdOf(def) or ""
	if s.SoundId ~= id then
		s.SoundId = id
	end
	s.Volume = volumeOf(def)
	s.PlaybackSpeed = pitchOf(def)
	local att = v.Attachment
	if att and pos then
		att.WorldPosition = pos
		s.RollOffMode = rollOffOf(def.RollOff)
		s.RollOffMinDistance = def.MinDistance or Mix.MinDistance
		s.RollOffMaxDistance = maxDistOf(def)
	end
	s.TimePosition = 0
	s:Play()
	serial += 1
	v.Serial = serial
	v.StartedAt = t
	v.Priority = priority
	v.BusyUntil = t + lengthOf(def, s)
	table.insert(playing, v)
	local maxS = def.MaxSeconds
	if maxS and maxS > 0 then
		local mine = v.Serial
		task.delay(maxS, function()
			if v.Serial ~= mine or v.BusyUntil <= 0 then
				return
			end
			tweenVolume(s, 0, STOP_FADE)
			task.delay(STOP_FADE, function()
				if v.Serial == mine and v.BusyUntil > 0 then
					stopVoice(v)
				end
			end)
		end)
	end
end

--[[ One-shot `key` (SoundConfig.Sounds). at = Vector3 | BasePart | Attachment | Model plays it in 3D there; nil = 2D.
	true = it started. Never errors (missing / disabled ids return false). ]]
function AudioController.Play(key: string, at: any?): boolean
	if type(key) ~= "string" then
		return drop("Missing")
	end
	if isServerContext() then
		return drop("Server")
	end
	if not initDone then
		pcall(AudioController.Init)
	end
	local def = defOf(key)
	if def == nil or soundIdOf(def) == nil then
		return drop("Missing")
	end
	local bus = def.Bus or "World"
	if bus == "Music" or bus == "Loop" then
		return drop("Loop") -- loops go through AudioController.Loop
	end
	if not ClientSettings.ShouldPlaySfx() then
		return drop("Muted")
	end
	local t = now()
	local last = lastPlayedAt[key]
	if last ~= nil and t - last < math.max(0, def.CooldownSeconds) then
		return drop("Cooldown")
	end
	local pos: Vector3? = nil
	if at ~= nil then
		pos = positionOf(at)
		if pos == nil then
			return drop("Missing")
		end
		local ear = listenerPos()
		if ear and (ear - pos).Magnitude > maxDistOf(def) then
			return drop("Far")
		end
	end
	local positional = pos ~= nil
	local priority = def.Priority or 1
	prune(t)

	-- one audible Stinger per window: the higher priority wins (PurchaseResult + cash float + toast = one sound)
	if bus == "Stinger" then
		local mark = lastStinger
		if mark and t - mark.At < Mix.StingerWindowSeconds then
			if priority <= mark.Priority then
				return drop("Collapsed")
			end
			if mark.Voice.Serial == mark.Serial and mark.Voice.BusyUntil > t then
				stopVoice(mark.Voice)
				stats.Replaced += 1
			end
		end
	end

	-- voice caps (steal the lowest priority / oldest, or drop this one)
	if not positional and count2D() >= Mix.MaxConcurrent2D then
		local victim = victimFor(priority, false)
		if victim == nil then
			return drop("Cap")
		end
		stopVoice(victim)
	end
	if #playing >= Mix.MaxConcurrent then
		local victim = victimFor(priority, nil)
		if victim == nil then
			return drop("Cap")
		end
		stopVoice(victim)
	end

	local okAcquire, voice = pcall(acquire, key, def, positional, t)
	if not okAcquire or voice == nil then
		return drop("Error")
	end
	local v = voice :: Voice
	local okStart = pcall(startVoice, v, def, pos, t, priority)
	if not okStart then
		stopVoice(v)
		return drop("Error")
	end
	lastPlayedAt[key] = t
	if bus == "Stinger" then
		lastStinger = { Voice = v, Serial = v.Serial, Priority = priority, At = t }
	end
	stats.Started += 1
	stats.ByKey[key] = (stats.ByKey[key] or 0) + 1
	stats.LastKey = key
	if #playing > stats.PeakActive then
		stats.PeakActive = #playing
	end
	return true
end

---------------------------------------------------------------------------------------------------------------
-- loop channels (music, ambience, engine)
---------------------------------------------------------------------------------------------------------------

local function channelOf(name: string): Channel
	local c = channels[name]
	if c == nil then
		local nc: Channel = { Name = name, Key = nil, Slots = {}, Gen = { 0, 0 }, Active = 0, Target = 0, Resume = {} }
		channels[name] = nc
		return nc
	end
	return c
end

local function slotSound(c: Channel, idx: number): Sound
	local s = c.Slots[idx]
	if s and s.Parent then
		return s
	end
	local ns = Instance.new("Sound")
	ns.Name = c.Name .. "_" .. tostring(idx)
	ns.Looped = true
	ns.Volume = 0
	ns.Parent = ensureFolder()
	c.Slots[idx] = ns
	return ns
end

local function fadeOutSlot(c: Channel, idx: number, seconds: number)
	local slot: Sound? = c.Slots[idx]
	if slot == nil then
		return
	end
	local s = slot :: Sound
	c.Gen[idx] += 1
	local gen = c.Gen[idx]
	tweenVolume(s, 0, seconds)
	task.delay(math.max(0, seconds), function()
		if c.Gen[idx] == gen then
			pcall(function()
				s:Stop()
			end)
		end
	end)
end

-- (re)apply the channel's state after a settings change or a same-key Loop call; true = audible
local function applyChannel(c: Channel, fade: number): boolean
	local key = c.Key
	if key == nil or c.Active == 0 then
		return false
	end
	local def = rawDef(key)
	local slot: Sound? = c.Slots[c.Active]
	if def == nil or slot == nil then
		return false
	end
	local s = slot :: Sound
	if allowedFor(def) then
		c.Gen[c.Active] += 1
		if s.IsPlaying and math.abs(s.Volume - c.Target) < 1e-3 then
			return true -- already there (the 1.5 s ambience check lands here: no tween churn)
		end
		if not s.IsPlaying then
			local okResume = pcall(function()
				if s.TimePosition > 0 then
					s:Resume()
				else
					s:Play()
				end
			end)
			if not okResume then
				pcall(function()
					s:Play()
				end)
			end
			stats.LoopStarts += 1
		end
		tweenVolume(s, c.Target, fade)
		return true
	end
	pcall(function()
		s.Volume = 0
		s:Pause()
	end)
	return false
end

--[[ Set loop channel `channel` to `key` (nil = stop) with a `fade`-second crossfade (default Mix.LoopFadeSeconds).
	A missing / disabled key stops the channel. true = the key is audible now (false while muted: it resumes later). ]]
function AudioController.Loop(channel: string, key: string?, fade: number?): boolean
	if type(channel) ~= "string" or isServerContext() then
		return false
	end
	if not initDone then
		pcall(AudioController.Init)
	end
	local c = channelOf(channel)
	local seconds = if type(fade) == "number" then math.max(0, fade) else Mix.LoopFadeSeconds
	local want: string? = key
	local def: SoundDef? = nil
	if want ~= nil then
		def = defOf(want)
		if def == nil or soundIdOf(def) == nil then
			drop("Missing")
			want = nil
			def = nil
		end
	end
	if c.Key == want then
		return applyChannel(c, seconds)
	end
	-- fade out whatever the channel carries now (music remembers where it was)
	if c.Active ~= 0 then
		local cur = c.Slots[c.Active]
		local curKey = c.Key
		if cur and curKey then
			pcall(function()
				c.Resume[curKey] = cur.TimePosition
			end)
		end
		fadeOutSlot(c, c.Active, seconds)
	end
	local prevActive = c.Active
	c.Key = want
	c.Active = 0
	if want == nil or def == nil then
		return false
	end
	local d = def :: SoundDef
	local idx = if prevActive == 1 then 2 else 1
	local s = slotSound(c, idx)
	c.Gen[idx] += 1
	s.SoundId = soundIdOf(d) or ""
	s.Looped = true
	s.PlaybackSpeed = pitchOf(d)
	s.Volume = 0
	c.Active = idx
	c.Target = volumeOf(d)
	if d.Bus == "Music" then
		local at = c.Resume[want]
		pcall(function()
			s.TimePosition = if at and at > 0 then at else 0
		end)
	else
		pcall(function()
			s.TimePosition = 0
		end)
	end
	if not allowedFor(d) then
		return false
	end
	s:Play()
	stats.LoopStarts += 1
	tweenVolume(s, c.Target, seconds)
	return true
end

--[[ Engine pitch etc.: writes PlaybackSpeed on the channel's active Sound (skips changes < Engine.PitchEpsilon). ]]
function AudioController.SetLoopPitch(channel: string, pitch: number)
	local c = channels[channel]
	if c == nil or c.Active == 0 or type(pitch) ~= "number" or pitch ~= pitch then
		return
	end
	local slot: Sound? = c.Slots[c.Active]
	if slot == nil then
		return
	end
	local s = slot :: Sound
	local p = math.clamp(pitch, 0.1, 4)
	if math.abs(s.PlaybackSpeed - p) >= SoundConfig.Engine.PitchEpsilon then
		s.PlaybackSpeed = p
	end
end

function AudioController.GetLoop(channel: string): string?
	local c = channels[channel]
	return if c then c.Key else nil
end

---------------------------------------------------------------------------------------------------------------
-- settings, init, legacy API
---------------------------------------------------------------------------------------------------------------

local function applySettings()
	if not ClientSettings.ShouldPlaySfx() then
		-- every pooled voice, not only the ones still counted busy (a file longer than its LengthSeconds hint)
		for _, pool in pairs(pools) do
			for _, v in ipairs(pool) do
				stopVoice(v)
			end
		end
	end
	for _, c in pairs(channels) do
		applyChannel(c, Mix.LoopFadeSeconds)
	end
end

function AudioController.Init()
	if initDone or isServerContext() then
		return
	end
	initDone = true
	ensureFolder()
	-- warm one 2D voice per UI / Stinger key so the first cue does not wait on a cold asset load
	for key, def in pairs(SoundConfig.Sounds) do
		if (def.Bus == "Stinger" or def.Bus == "UI") and soundIdOf(def) ~= nil and pools[key] == nil then
			pools[key] = { newVoice(key, def, false) }
		end
	end
	ClientSettings.OnChanged(applySettings)
	AudioController.Loop("Music", SoundConfig.Music.Base, SoundConfig.Music.FadeSeconds)
end

--[[ AudioHooks: NotificationController's next PlayNotification (within Hooks.NotificationTypeWindowSeconds) plays
	`key` instead of the plain UI.Notify ping. nil clears it. ]]
function AudioController.SetNextNotificationKey(key: string?)
	if key == nil then
		pendingNotify = nil
		return
	end
	pendingNotify = { Key = key, At = now() }
end

function AudioController.HasSound(key: string): boolean
	return soundIdOf(rawDef(key)) ~= nil
end

function AudioController.GetStats(): Stats
	prune(now())
	local n2, n3 = 0, 0
	for _, v in ipairs(playing) do
		if v.Positional then
			n3 += 1
		else
			n2 += 1
		end
	end
	return {
		Started = stats.Started,
		Replaced = stats.Replaced,
		LoopStarts = stats.LoopStarts,
		Active = #playing,
		Active2D = n2,
		Active3D = n3,
		PeakActive = stats.PeakActive,
		Dropped = table.clone(stats.Dropped),
		ByKey = table.clone(stats.ByKey),
		LastKey = stats.LastKey,
	}
end

--[[ UI button activate — respects SFX toggle. ]]
function AudioController.PlayClick()
	AudioController.Play("UI.Click")
end

--[[ Toast / reward ping — respects SFX toggle. The line's type (set by AudioHooks from the Notification remote in
	the same frame) picks the key; deferred one step so that hook has run whichever handler fired first. ]]
function AudioController.PlayNotification()
	if not ClientSettings.ShouldPlaySfx() then
		return
	end
	task.defer(function()
		local key = "UI.Notify"
		local p = pendingNotify
		if p and now() - p.At <= SoundConfig.Hooks.NotificationTypeWindowSeconds then
			key = p.Key
		end
		pendingNotify = nil
		AudioController.Play(key)
	end)
end

function AudioController.GetMusicVolume(): number
	return Mix.LegacyMusicVolume
end

function AudioController.GetSfxVolume(): number
	return Mix.LegacySfxVolume
end

return AudioController
