--!strict
--[[
	SoundConfig — every sound the client plays (W1 SND audio pass). Config first: AudioController plays these keys,
	AudioHooks maps EXISTING remotes / HUD signals onto them. Sounds are created on the CLIENT only (never on the
	server; AudioController refuses to run there).

	LICENCE (roadmap §1.4, owner decision D4 = accept Roblox's licensed sound library, in-game only).
	Every Id is one of:
	  [PSE]  Roblox licensed library, Pro Sound Effects partner upload (Creator Store) — free inside Roblox experiences.
	  [APM]  Roblox licensed library, APM / KPM partner upload (Creator Store) — free inside Roblox experiences.
	  [RBX]  Roblox-owned: the engine sounds of Roblox's own "Light Utility Vehicle" (asset 6418221666, creator Roblox).
	  [ENG]  Engine built-in content path (rbxasset://sounds/…, ships with every Roblox client; already used in v70).
	  ⚠ [PSE]/[APM] audio must NOT be used in YouTube / TikTok promos (copyright claims are likely).
	Ids come from gap/reusable_parts.md §2.4 + §2.1 V-a (Creator Store search, 2026-09-24). The owner should preview each
	one in Studio (Toolbox › Creator Store › Audio › paste the id) before a publish; to swap a sound change its Id here.
	Id 0 (or "") disables a key: AudioController.Play then returns false and never errors.

	KEY FIELDS
	  Id               asset id (number) or an engine built-in path (string "rbxasset://sounds/…")
	  Volume           0..1, × Mix.SfxMaster (or Mix.MusicMaster for Bus "Music")
	  RollOff          Enum.RollOffMode name: "InverseTapered" | "Inverse" | "Linear" | "LinearSquare" (3D plays only)
	  MaxDistance      studs. A 3D play farther than this from the camera is skipped (it would be inaudible anyway)
	  Pitch            PlaybackSpeed
	  CooldownSeconds  the same key never starts again within this (no 40 coin sounds at the ATM)
	  Priority         1..5 (optional, default 1): voice stealing and the Stinger collapse keep the higher one
	  Bus              "UI"      button taps (no collapse)
	                   "Stinger" event cues (purchase, collect, capture, level, alarms, toasts): at most ONE per
	                             Mix.StingerWindowSeconds — the higher Priority wins, so one server event that
	                             arrives as 2–3 client signals (PurchaseResult + cash float + toast) is one sound
	                   "World"   positional one-shots (Play(key, at)); CC-3 / EVENTS add their keys here
	                   "Music"   music channel (ClientSettings music toggle)
	                   "Loop"    ambience / engine channels (ClientSettings SFX toggle)
	  MaxSeconds       stop a one-shot after this (long library files, e.g. the 30 s siren)
	  LengthSeconds    busy-time hint for the voice cap before the file length is known (default Mix.DefaultLengthSeconds)
	  MinDistance      3D RollOffMinDistance (default Mix.MinDistance)
]]

export type SoundDef = {
	Id: number | string,
	Volume: number,
	RollOff: string,
	MaxDistance: number,
	Pitch: number,
	CooldownSeconds: number,
	Priority: number?,
	Bus: string?,
	MaxSeconds: number?,
	LengthSeconds: number?,
	MinDistance: number?,
}

export type EngineProfile = {
	Key: string,
	PitchMin: number, -- PlaybackSpeed at standstill
	PitchMax: number, -- PlaybackSpeed at the vehicle's WE_MaxSpeed
}

export type EngineFamily = {
	Prefix: string, -- WE_KitFamily prefix (VehicleService kit families: WheeledLight, TrackedMBT, HeliLight, JetFighter …)
	Key: string,
	PitchMin: number,
	PitchMax: number,
}

local ENG_PING = "rbxasset://sounds/electronicpingshort.wav" -- [ENG] the v70 UI click (unchanged)
local ENG_SWITCH = "rbxasset://sounds/switch.wav" -- [ENG] the v70 toast ping (unchanged)

local SoundConfig = {}

SoundConfig.Sounds = {
	-- ── UI (button taps; every existing AudioController.PlayClick caller) ─────────────────────────────────────
	["UI.Click"] = { Id = ENG_PING, Volume = 0.55, RollOff = "Linear", MaxDistance = 0, Pitch = 1, CooldownSeconds = 0.05, Priority = 1, Bus = "UI", LengthSeconds = 0.3 }, -- [ENG] electronicpingshort.wav

	-- ── toasts (NotificationController's PlayNotification, typed by AudioHooks from the Notification remote) ──
	["UI.Notify"] = { Id = ENG_SWITCH, Volume = 0.55, RollOff = "Linear", MaxDistance = 0, Pitch = 1, CooldownSeconds = 0.3, Priority = 1, Bus = "Stinger", LengthSeconds = 0.4 }, -- [ENG] switch.wav (local toasts with no typed key)
	["Toast.Success"] = { Id = 9113849492, Volume = 0.45, RollOff = "Linear", MaxDistance = 0, Pitch = 1.2, CooldownSeconds = 0.4, Priority = 2, Bus = "Stinger", LengthSeconds = 1.2 }, -- [PSE] "Coins Or Keys Jingle 6" 9113849492, pitched up
	["Toast.Reward"] = { Id = 9113849492, Volume = 0.6, RollOff = "Linear", MaxDistance = 0, Pitch = 1, CooldownSeconds = 0.6, Priority = 2, Bus = "Stinger", LengthSeconds = 1.5 }, -- [PSE] "Coins Or Keys Jingle 6" 9113849492
	["Toast.Warn"] = { Id = ENG_PING, Volume = 0.5, RollOff = "Linear", MaxDistance = 0, Pitch = 0.7, CooldownSeconds = 1, Priority = 2, Bus = "Stinger", LengthSeconds = 0.4 }, -- [ENG] electronicpingshort.wav, low
	["Toast.Error"] = { Id = ENG_SWITCH, Volume = 0.6, RollOff = "Linear", MaxDistance = 0, Pitch = 0.6, CooldownSeconds = 1, Priority = 2, Bus = "Stinger", LengthSeconds = 0.5 }, -- [ENG] switch.wav, low

	-- ── cash / purchases ──────────────────────────────────────────────────────────────────────────────────────
	["Cash.Collect"] = { Id = 9113849492, Volume = 0.6, RollOff = "Linear", MaxDistance = 0, Pitch = 1, CooldownSeconds = 0.3, Priority = 3, Bus = "Stinger", LengthSeconds = 1.2 }, -- [PSE] "Coins Or Keys Jingle 6" 9113849492
	["Cash.Purchase"] = { Id = 9113728042, Volume = 0.6, RollOff = "Linear", MaxDistance = 0, Pitch = 1, CooldownSeconds = 0.5, Priority = 3, Bus = "Stinger", LengthSeconds = 1.5 }, -- [PSE] "Cash Register 1" 9113728042
	["UI.Denied"] = { Id = ENG_PING, Volume = 0.5, RollOff = "Linear", MaxDistance = 0, Pitch = 0.55, CooldownSeconds = 0.6, Priority = 2, Bus = "Stinger", LengthSeconds = 0.4 }, -- [ENG] electronicpingshort.wav, lowest (failed buy)

	-- ── outposts (TerritoryStateUpdate diffs) ─────────────────────────────────────────────────────────────────
	["Capture.Start"] = { Id = ENG_PING, Volume = 0.6, RollOff = "Linear", MaxDistance = 0, Pitch = 0.85, CooldownSeconds = 3, Priority = 3, Bus = "Stinger", LengthSeconds = 0.4 }, -- [ENG] electronicpingshort.wav ("radio" cue)
	["Capture.Secured"] = { Id = 9113849492, Volume = 0.8, RollOff = "Linear", MaxDistance = 0, Pitch = 0.85, CooldownSeconds = 2, Priority = 4, Bus = "Stinger", LengthSeconds = 1.6 }, -- [PSE] "Coins Or Keys Jingle 6" 9113849492 (+income), low
	["Capture.Lost"] = { Id = 9119236749, Volume = 0.5, RollOff = "Linear", MaxDistance = 0, Pitch = 0.8, CooldownSeconds = 3, Priority = 4, Bus = "Stinger", LengthSeconds = 2 }, -- [PSE] "Small Explosion 1" 9119236749

	-- ── progression ───────────────────────────────────────────────────────────────────────────────────────────
	["Level.Up"] = { Id = 9113849492, Volume = 0.9, RollOff = "Linear", MaxDistance = 0, Pitch = 1.3, CooldownSeconds = 2, Priority = 4, Bus = "Stinger", LengthSeconds = 1.2 }, -- [PSE] "Coins Or Keys Jingle 6" 9113849492, high

	-- ── alarms ────────────────────────────────────────────────────────────────────────────────────────────────
	["Alarm.Raid"] = { Id = 9113073742, Volume = 0.55, RollOff = "Linear", MaxDistance = 0, Pitch = 1.15, CooldownSeconds = 8, Priority = 5, Bus = "Stinger", MaxSeconds = 3 }, -- [PSE] "Air Raid Siren Old Fashioned 1" 9113073742 (ATM being robbed)
	["Alarm.Base"] = { Id = 9113073742, Volume = 0.5, RollOff = "Linear", MaxDistance = 0, Pitch = 1, CooldownSeconds = 60, Priority = 5, Bus = "Stinger", MaxSeconds = 3 }, -- [PSE] same siren ("BASE UNDER ATTACK!" banner; its Reroute rule shows it at most once per 60 s)
	["Alarm.Missile"] = { Id = 9113073742, Volume = 0.6, RollOff = "Linear", MaxDistance = 0, Pitch = 1, CooldownSeconds = 4, Priority = 5, Bus = "Stinger", MaxSeconds = 9 }, -- [PSE] same siren; 9 s = RaidConfig.Strike MaxFlightSeconds

	-- ── music (ClientSettings music toggle) ───────────────────────────────────────────────────────────────────
	["Music.Base"] = { Id = 1844397606, Volume = 0.22, RollOff = "Linear", MaxDistance = 0, Pitch = 1, CooldownSeconds = 0, Bus = "Music" }, -- [APM] "Military March" 1844397606 (159 s), base theme
	["Music.Combat"] = { Id = 1841116989, Volume = 0.3, RollOff = "Linear", MaxDistance = 0, Pitch = 1, CooldownSeconds = 0, Bus = "Music" }, -- [APM] "Military March" 1841116989 (63 s), combat layer

	-- ── ambience: ONE loop channel (ClientSettings SFX toggle) ────────────────────────────────────────────────
	["Amb.Wind"] = { Id = 9114057104, Volume = 0.18, RollOff = "Linear", MaxDistance = 0, Pitch = 1, CooldownSeconds = 0, Bus = "Loop" }, -- [PSE] "Desert Wind Whistley Light Gusts 1" 9114057104 (37 s)
	["Amb.Surf"] = { Id = 9119677135, Volume = 0.3, RollOff = "Linear", MaxDistance = 0, Pitch = 1, CooldownSeconds = 0, Bus = "Loop" }, -- [PSE] "Surf Ocean Wave Impact 1" 9119677135

	-- ── engines: ONE loop channel, pitch follows the chassis speed at Engine.SampleHz ─────────────────────────
	["Engine.Ground"] = { Id = 6417138409, Volume = 0.45, RollOff = "Linear", MaxDistance = 0, Pitch = 1, CooldownSeconds = 0, Bus = "Loop" }, -- [RBX] LUV "Sedan_Loop_Mid" 6417138409
	["Engine.Heavy"] = { Id = 6417179625, Volume = 0.5, RollOff = "Linear", MaxDistance = 0, Pitch = 1, CooldownSeconds = 0, Bus = "Loop" }, -- [RBX] LUV "Sedan_Loop_Low" 6417179625 (tracked)
	["Engine.Jet"] = { Id = 6417165160, Volume = 0.4, RollOff = "Linear", MaxDistance = 0, Pitch = 1, CooldownSeconds = 0, Bus = "Loop" }, -- [RBX] LUV "Sedan_Loop_High" 6417165160 (placeholder jet whine)
	["Engine.Heli"] = { Id = 9113417759, Volume = 0.45, RollOff = "Linear", MaxDistance = 0, Pitch = 1, CooldownSeconds = 0, Bus = "Loop" }, -- [PSE] helicopter "Rises For Takeoff 2" 9113417759 (swap for a seamless rotor loop after preview)
	["Engine.Naval"] = { Id = 6417179625, Volume = 0.4, RollOff = "Linear", MaxDistance = 0, Pitch = 1, CooldownSeconds = 0, Bus = "Loop" }, -- [RBX] LUV "Sedan_Loop_Low" 6417179625, pitched down (boat motor)
} :: { [string]: SoundDef }

SoundConfig.Mix = {
	MaxConcurrent = 12, -- one-shot voices playing at once, 2D + 3D (loops are separate: music, ambience, engine)
	MaxConcurrent2D = 4, -- of those, non-positional (UI + Stinger)
	PoolPerKey = 4, -- pooled Sound instances per key; a 5th overlapping play of one key restarts its oldest voice
	StingerWindowSeconds = 0.35, -- one audible Stinger per window (higher Priority replaces a lower one)
	DefaultLengthSeconds = 2, -- voice busy time when neither the file length nor LengthSeconds is known
	MinDistance = 10, -- 3D RollOffMinDistance default
	DefaultMaxDistance = 250, -- 3D plays of a key whose MaxDistance is 0
	SfxMaster = 1,
	MusicMaster = 1,
	LoopFadeSeconds = 0.3, -- default channel fade (engine on / off)
	-- legacy getters (AudioController.GetSfxVolume / GetMusicVolume): MissileController scales its own siren by it
	LegacySfxVolume = 0.55,
	LegacyMusicVolume = 0.35,
}

SoundConfig.Music = {
	Base = "Music.Base", -- plays from AudioController.Init while the music toggle is on
	Combat = "Music.Combat", -- while HudLayout flags Drawn AND Hurt (and not Dead)
	FadeSeconds = 1.5,
	CombatHoldSeconds = 6, -- keep the combat layer this long after Drawn/Hurt clears
}

SoundConfig.Ambience = {
	Default = "Amb.Wind",
	NearWater = "Amb.Surf", -- camera within NearWaterStuds (XZ) of a WE_Water part (Constants.Tags.Water)
	NearWaterStuds = 60,
	LeaveWaterStuds = 90, -- hysteresis: back to wind past this
	CheckSeconds = 1.5, -- water proximity check period (not per frame)
	FadeSeconds = 1,
}

SoundConfig.Engine = {
	SampleHz = 10, -- chassis speed → pitch; the only periodic audio work while seated
	DefaultMaxSpeed = 60, -- studs/s when the vehicle has no WE_MaxSpeed attribute
	PitchEpsilon = 0.01, -- skip PlaybackSpeed writes smaller than this
	-- first match on the vehicle model's WE_KitFamily prefix, then WE_Category, then Default
	Families = {
		{ Prefix = "Tracked", Key = "Engine.Heavy", PitchMin = 0.7, PitchMax = 1.3 },
		{ Prefix = "Heli", Key = "Engine.Heli", PitchMin = 0.9, PitchMax = 1.25 },
		{ Prefix = "Jet", Key = "Engine.Jet", PitchMin = 1.0, PitchMax = 1.8 },
		{ Prefix = "Naval", Key = "Engine.Naval", PitchMin = 0.6, PitchMax = 1.1 },
	} :: { EngineFamily },
	Categories = {
		Air = { Key = "Engine.Heli", PitchMin = 0.9, PitchMax = 1.25 },
		Naval = { Key = "Engine.Naval", PitchMin = 0.6, PitchMax = 1.1 },
	} :: { [string]: EngineProfile },
	Default = { Key = "Engine.Ground", PitchMin = 0.8, PitchMax = 1.6 } :: EngineProfile,
}

SoundConfig.Hooks = {
	-- Notification remote payload.Type (after NotificationConfig.Rewrite) → the key NotificationController's own
	-- PlayNotification plays for that line. Types not listed (Info, Collect) keep the plain UI.Notify / no sound.
	NotificationTypes = {
		Success = "Toast.Success",
		Reward = "Toast.Reward",
		Warn = "Toast.Warn",
		Error = "Toast.Error",
	} :: { [string]: string },
	NotificationTypeWindowSeconds = 0.25, -- a typed key waits this long for NotificationController's ping
	AlertReroute = "Alarm.Base", -- HudConfig.Toast.Reroute rules with AlertSeconds ("BASE UNDER ATTACK!" banner ping)
	CashGain = "Cash.Collect", -- HudLayout.CashFloatRequested amount > 0
	CashSpend = "Cash.Purchase", -- HudLayout.CashFloatRequested amount < 0
	PurchaseOk = "Cash.Purchase", -- PurchaseResult Ok
	PurchaseFail = "UI.Denied", -- PurchaseResult not Ok
	CaptureStart = "Capture.Start", -- TerritoryStateUpdate LocalCapture.Capturing false → true
	CaptureSecured = "Capture.Secured", -- a territory's OwnerUserId becomes mine
	CaptureLost = "Capture.Lost", -- a territory's OwnerUserId stops being mine
	RaidAlarm = "Alarm.Raid", -- AtmRaidStateUpdate Phase "Alarm" (victim; pushed every 1 s → key cooldown)
	RaidAlarmPhase = "Alarm",
	MissileVictim = "Alarm.Missile", -- MissileStrikeFx with VictimUserId == me (one per StrikeId)
	MissileLateSeconds = 2, -- late joiner: skip when the strike is already over
	-- MissileController's own click-siren Sound (created in SoundService by name). It is muted when
	-- Alarm.Missile has a valid Id, so the victim hears the real siren instead of the click. "" = never mute.
	LegacyMissileSirenName = "WE_MissileSiren",
	LevelUp = "Level.Up", -- XPUpdate LevelUp == true
}

return SoundConfig
