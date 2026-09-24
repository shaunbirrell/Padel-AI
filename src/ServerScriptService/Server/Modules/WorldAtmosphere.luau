--!strict
--[[
	WAR EMPIRE World v2 Phase 1 — WorldAtmosphere: Lighting, Sky, Atmosphere and the day cycle (gap/world_v2_spec.md §2,
	roadmap §1.3 / §1.5 #6 / §1.6). Replaces the Lighting block and day loop at the top of MapSetup.Run once hooked.
	  * Presets in WorldConfig.Atmosphere.Presets: "V2" (warm dust haze, Decay (150,122,92) = no blue below the horizon,
	    Offset 0.22 to silhouette the canyon) and "Classic" (the pre-v2 look). WorldConfig.Atmosphere.Preset = "Classic"
	    is the one-line revert for Test B.
	  * Ambient = agent F's numbers (HUD spec §5): day (78,72,62), EnvironmentDiffuseScale 0.35, read from
	    StructureVisualConfig.WorldLighting when present (the in-base knob), else from WorldConfig. Night Brightness
	    floor 1.6 so phones never go black.
	  * No Fog writes: Roblox hides Fog while Lighting has an Atmosphere, so they were dead writes.
	  * Day cycle: one step every StepSeconds (6 s; was 1.5 s) with 4x larger steps, so the day is still
	    DayLengthMinutes (20) long. A step writes ClockTime, plus only the properties whose value changed (dawn and
	    dusk), so a daytime step is a single property write. Lights tagged WE_NightLight are Enabled only while
	    night > 0.5, written only when that flips (2 writes per day).

	PUBLIC API (server only; not hooked yet — the post-F hook step replaces MapSetup.Run's Lighting block with Apply):
	  WorldAtmosphere.Apply(opts?: { Preset: string?, DayCycle: boolean?, StartClock: number? }) -> Handle
	      Applies the preset at StartClock and (unless DayCycle == false) starts the day loop. Idempotent: a second
	      Apply replaces Lighting.WE_DayNightMarker (the marker MapSetup's old loop also watches), which stops every
	      earlier loop, and reuses the one Sky / Atmosphere. Handle = { Preset: string, Stop: () -> () }.
	  WorldAtmosphere.Sample(clock: number, preset?: string) -> Values   (pure: every value one step writes)
	  WorldAtmosphere.NightShare(clock: number) -> number                (pure: 0 = day .. 1 = night)
	  WorldAtmosphere.Simulate(hours, clock?, preset?) -> { Steps, Writes, LightFlips, Seconds }  (pure loop replay)
	  WorldAtmosphere.Counters() -> { Steps, Writes, LightFlips }         (the running loop since the last Apply)
]]

local CollectionService = game:GetService("CollectionService")
local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Configs = ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Configs")
local WorldConfig = require(Configs:WaitForChild("WorldConfig"))
local StructureVisualConfig = require(Configs:WaitForChild("StructureVisualConfig"))

export type Values = {
	ClockTime: number,
	Night: number,
	Brightness: number,
	Ambient: Color3,
	OutdoorAmbient: Color3,
	Density: number,
	Offset: number,
	Color: Color3,
	Decay: Color3,
	Glare: number,
	Haze: number,
}
export type Handle = { Preset: string, Stop: () -> () }

local WorldAtmosphere = {}

local MARKER = "WE_DayNightMarker"

local function presetOf(name: string?): (string, any)
	local cfg = WorldConfig.Atmosphere
	local key = name or cfg.Preset
	local p = (cfg.Presets :: any)[key]
	if p == nil then
		key = "V2"
		p = cfg.Presets.V2
	end
	return key, p
end

-- F's in-base knob wins for the day Ambient / diffuse scale (one place to tune interiors)
local function worldLighting(): any
	local wl = (StructureVisualConfig :: any).WorldLighting
	return if type(wl) == "table" then wl else {}
end

function WorldAtmosphere.NightShare(clock: number): number
	local c = WorldConfig.Atmosphere
	local t = clock % 24
	if t < c.NightEnd or t > c.NightStart then
		return 1
	elseif t < c.DawnEnd then
		return 1 - (t - c.NightEnd) / (c.DawnEnd - c.NightEnd)
	elseif t > c.DuskStart then
		return (t - c.DuskStart) / (c.NightStart - c.DuskStart)
	end
	return 0
end

local function r3(v: number): number
	return math.round(v * 1000) / 1000
end

local function lerpColor(a: Color3, b: Color3, t: number): Color3
	local c = a:Lerp(b, t)
	-- quantise to 8-bit so identical steps compare equal (no spurious re-writes)
	return Color3.fromRGB(math.round(c.R * 255), math.round(c.G * 255), math.round(c.B * 255))
end

function WorldAtmosphere.Sample(clock: number, preset: string?): Values
	local _, p = presetOf(preset)
	local night = WorldAtmosphere.NightShare(clock)
	local d, n = p.Day, p.Night
	local wl = worldLighting()
	local dayAmbient: Color3 = if typeof(wl.DayAmbient) == "Color3" then wl.DayAmbient else d.Ambient
	return {
		ClockTime = clock % 24,
		Night = night,
		Brightness = r3(d.Brightness + (n.Brightness - d.Brightness) * night),
		Ambient = lerpColor(dayAmbient, n.Ambient, night),
		OutdoorAmbient = lerpColor(d.OutdoorAmbient, n.OutdoorAmbient, night),
		Density = r3(d.Density + (n.Density - d.Density) * night),
		Offset = r3(d.Offset + (n.Offset - d.Offset) * night),
		Color = lerpColor(d.Color, n.Color, night),
		Decay = lerpColor(d.Decay, n.Decay, night),
		Glare = r3(d.Glare + (n.Glare - d.Glare) * night),
		Haze = r3(d.Haze + (n.Haze - d.Haze) * night),
	}
end

local function ensureSky(): Sky
	local sky = Lighting:FindFirstChildOfClass("Sky")
	if not sky then
		sky = Instance.new("Sky")
		sky.Parent = Lighting
	end
	local s = sky :: Sky
	local cfg = WorldConfig.Atmosphere.Sky
	s.Name = "WE_Sky"
	s.CelestialBodiesShown = true
	s.StarCount = cfg.StarCount
	s.SunAngularSize = cfg.SunAngularSize
	s.MoonAngularSize = cfg.MoonAngularSize
	return s
end

local function ensureAtmosphere(): Atmosphere
	local atm = Lighting:FindFirstChildOfClass("Atmosphere")
	if not atm then
		atm = Instance.new("Atmosphere")
		atm.Parent = Lighting
	end
	return atm :: Atmosphere
end

-- the properties one step can write: { object ("L" = Lighting, "A" = Atmosphere), property }
local FIELDS: { { string } } = {
	{ "L", "ClockTime" },
	{ "L", "Brightness" },
	{ "L", "Ambient" },
	{ "L", "OutdoorAmbient" },
	{ "A", "Density" },
	{ "A", "Offset" },
	{ "A", "Color" },
	{ "A", "Decay" },
	{ "A", "Glare" },
	{ "A", "Haze" },
}

-- write only what differs from the last written values; returns the number of property writes
local function write(atm: Atmosphere?, v: Values, last: Values?): number
	local n = 0
	local cur: any, old: any = v, last or {}
	for _, f in ipairs(FIELDS) do
		local key = f[2]
		if cur[key] ~= old[key] then
			n += 1
			if atm then
				local obj: any = if f[1] == "L" then Lighting else atm
				obj[key] = cur[key]
			end
		end
	end
	return n
end

local function setNightLights(on: boolean)
	for _, inst in ipairs(CollectionService:GetTagged(WorldConfig.Atmosphere.NightLightTag)) do
		if inst:IsA("Light") then
			inst.Enabled = on
		end
	end
end

-- counters of the running loop (Counters() returns a copy)
local stats = { Steps = 0, Writes = 0, LightFlips = 0 }

function WorldAtmosphere.Apply(opts: { Preset: string?, DayCycle: boolean?, StartClock: number? }?): Handle
	local cfg = WorldConfig.Atmosphere
	local key = presetOf(opts and opts.Preset)
	local wl = worldLighting()
	local lc = cfg.Lighting

	Lighting.GeographicLatitude = lc.GeographicLatitude
	Lighting.EnvironmentDiffuseScale = if type(wl.EnvironmentDiffuseScale) == "number" then wl.EnvironmentDiffuseScale else lc.EnvironmentDiffuseScale
	Lighting.EnvironmentSpecularScale = lc.EnvironmentSpecularScale
	pcall(function()
		Lighting.GlobalShadows = lc.GlobalShadows
	end)
	ensureSky()
	local atm = ensureAtmosphere()

	local clock = if opts and opts.StartClock then opts.StartClock else cfg.StartClock
	local last = WorldAtmosphere.Sample(clock, key)
	write(atm, last, nil)
	local nightOn = last.Night > 0.5
	setNightLights(nightOn)

	-- one loop at a time: replacing the marker stops every earlier loop (ours and MapSetup's old one)
	local old = Lighting:FindFirstChild(MARKER)
	if old then
		old:Destroy()
	end
	local marker = Instance.new("Folder")
	marker.Name = MARKER
	marker:SetAttribute("WE_Preset", key)
	marker.Parent = Lighting

	stats.Steps, stats.Writes, stats.LightFlips = 0, 0, 0
	if not (opts and opts.DayCycle == false) then
		local stepSeconds = cfg.StepSeconds
		local stepHours = 24 * stepSeconds / (cfg.DayLengthMinutes * 60)
		task.spawn(function()
			while marker.Parent do
				task.wait(stepSeconds)
				if not marker.Parent then
					break
				end
				clock = (clock + stepHours) % 24
				local v = WorldAtmosphere.Sample(clock, key)
				stats.Steps += 1
				stats.Writes += write(atm, v, last)
				last = v
				local on = v.Night > 0.5
				if on ~= nightOn then
					nightOn = on
					stats.LightFlips += 1
					setNightLights(on)
				end
			end
		end)
	end
	return {
		Preset = key,
		Stop = function()
			if marker.Parent then
				marker:Destroy()
			end
		end,
	}
end

-- Counters of the running loop since the last Apply (steps, property writes, night-light flips).
function WorldAtmosphere.Counters(): { Steps: number, Writes: number, LightFlips: number }
	return { Steps = stats.Steps, Writes = stats.Writes, LightFlips = stats.LightFlips }
end

-- PURE: what the loop would do over `hours` of game time from `clock` at the configured cadence (no writes).
function WorldAtmosphere.Simulate(hours: number, clock: number?, preset: string?): { Steps: number, Writes: number, LightFlips: number, Seconds: number }
	local cfg = WorldConfig.Atmosphere
	local stepHours = 24 * cfg.StepSeconds / (cfg.DayLengthMinutes * 60)
	local t = clock or cfg.StartClock
	local last = WorldAtmosphere.Sample(t, preset)
	local nightOn = last.Night > 0.5
	local out = { Steps = 0, Writes = 0, LightFlips = 0, Seconds = 0 }
	local steps = math.floor(hours / stepHours + 0.5)
	for _ = 1, steps do
		t = (t + stepHours) % 24
		local v = WorldAtmosphere.Sample(t, preset)
		out.Steps += 1
		out.Writes += write(nil, v, last)
		last = v
		if (v.Night > 0.5) ~= nightOn then
			nightOn = v.Night > 0.5
			out.LightFlips += 1
		end
	end
	out.Seconds = out.Steps * cfg.StepSeconds
	return out
end

return WorldAtmosphere
