--!strict
--[[
	claude-bud JOB 17 (2026-09-29): night readable on phones. Every night value in one place. Live for all players.
	  * Night look (WorldAtmosphere reads this while Enabled; false = WorldConfig.Atmosphere's old night, exactly):
	    raised Ambient / OutdoorAmbient (~ (90, 95, 120) at midnight), a Brightness floor, lighter bluish haze, and a
	    moonlit ColorCorrectionEffect ("WE_NightCC": Brightness +0.05, Contrast +0.1, slight blue tint) faded in by the
	    night share instead of darkening everything. Cycle: full night NightStart..NightEnd with Dusk / Dawn ramps
	    (~42 % of the day counted as night).
	  * Night lights (Server/Modules/NightLights, Workspace.WE_NightLights, outside the dressing folders so the world
	    hygiene budget of 24 dressing lights is untouched): warm streetlights along the Town's two main roads, a ring
	    round the Central Plaza and the Town Square, floodlights at every base gate and hangar, and a light on the
	    plaza flag. PointLight / SpotLight, Range 40-60, Shadows = false, tagged WE_NightLight (on only at night).
	  * Glow (Neon only while night, tag GlowTag): lamp heads, lit town windows (on the real front walls), runway edge
	    markers and the plaza flag. By day they are plain SmoothPlastic.
	  * Low quality (client, QualityGovernor): every light with WE_LowOff (every second one) stays off; the Neon glow
	    still shows.
]]

local LightingConfig = {
	Enabled = true,

	Cycle = { NightEnd = 5, DawnEnd = 6, DuskStart = 19, NightStart = 20 },

	Night = {
		Brightness = 2.0, -- floor: moonlight
		Ambient = Color3.fromRGB(80, 86, 112),
		OutdoorAmbient = Color3.fromRGB(90, 95, 120),
		Density = 0.3,
		Offset = 0.22,
		Color = Color3.fromRGB(84, 96, 128),
		Decay = Color3.fromRGB(52, 62, 96),
		Glare = 0.1,
		Haze = 1.8,
	},
	ColorCorrection = {
		Name = "WE_NightCC",
		Brightness = 0.05, -- at full night (0 by day)
		Contrast = 0.1,
		Saturation = -0.05,
		Tint = Color3.fromRGB(214, 224, 255), -- white by day
	},

	LightTag = "WE_NightLight", -- = WorldConfig.Atmosphere.NightLightTag
	GlowTag = "WE_NightGlow",
	MaxLights = 120,
	LowOffAttribute = "WE_LowOff",

	Street = {
		Color = Color3.fromRGB(255, 196, 120),
		Brightness = 1.4,
		Range = 44,
		PoleHeight = 14,
		Spacing = 48, -- along a road
		Offset = 14, -- from the road centre line (the corridor is 12: never on the lane)
		TownHalf = 320, -- the Town's two main roads (RoadX0 / RoadZ0) inside +-TownHalf
		SkipNearPlaza = 80, -- none inside the Central Plaza ring (its own lamps are the ring below)
	},
	PlazaRing = { Count = 6, Radius = 84, Range = 52, Brightness = 1.3 },
	TownSquare = { X = -150, Z = 150, Half = 40, Range = 48, Brightness = 1.2 },
	Flag = { Pole = "CentralPlaza_FlagPole", Flag = "CentralPlaza_Flag", Range = 40, Brightness = 2, Angle = 70 },
	Base = {
		GateRange = 56,
		GateBrightness = 1.6,
		HangarRange = 60,
		HangarBrightness = 1.5,
		Color = Color3.fromRGB(240, 238, 225),
		RunwayMarkerSpacing = 19, -- plot-local runway (BaseLayoutConfig.Roads "Runway"), both long edges
		RunwayMarkerColor = Color3.fromRGB(255, 200, 90),
	},
	-- claude-bud JOB 54: a base that reads at night. Built per OWNED plot (NightLights.SyncPlot from GateDefenseService's
	-- plot sync: claim / rejoin / restart), owner-first by the plot owner. 4 more night lights per base (helipad flood,
	-- dock flood, the gate-sign lamp, the beacon) -> 7 per base; with 10 plots + the town that is <= MaxLights (the
	-- shared counter refuses past it). Glow-only (no light): helipad corner markers, dock bollards, runway thresholds.
	-- Exposure: the client lifts ExposureCompensation at night (owner-first; 0 by day = today's look).
	Night2 = {
		Enabled = true,
		OwnerFirst = false, -- PUBLIC (Code Bot v220: everything public, Shaun 2026-10-02 07:51); was NEW-OWNER-FIRST (claude-bud JOB 54): Code Bot flips it after Shaun's phone test
		PerBaseLights = 4, -- the extra night lights per base (the per-base test: 3 + 4 = 7 <= 40)
		Helipad = { At = { 64, -104 }, Toward = { 40, -125 }, Range = 50, Brightness = 1.5, PadHalf = 12, PadColor = Color3.fromRGB(110, 255, 140) },
		Dock = { At = { 98, -72 }, Toward = { 128, -112 }, Range = 56, Brightness = 1.5, BollardX = 101, BollardZ = { -140, -122, -104, -86 }, BollardColor = Color3.fromRGB(255, 210, 120) },
		Sign = { Up = 11, Out = 3.2, Range = 26, Brightness = 2, Angle = 60, Color = Color3.fromRGB(255, 236, 200) },
		Beacon = { At = { 0, 0 }, MastHeight = 34, Range = 22, Brightness = 1.2, Color = Color3.fromRGB(255, 70, 60) }, -- At: plot-local, 0,0 = filled from the plot's rear corner
		Threshold = { Count = 5, Spacing = 5, Start = Color3.fromRGB(90, 255, 120), End = Color3.fromRGB(255, 80, 70) },
		Exposure = { Day = 0, Night = 0.35, RefreshSeconds = 2 },
	},
	Windows = {
		Enabled = true,
		MaxPerBuilding = 6, -- 2 floors x 3 at most
		Size = Vector3.new(2.2, 2.4, 0.15),
		FloorHeight = 5,
		FirstFloorY = 3.5, -- above the ground under the building
		ColumnSpacing = 5,
		LitShare = 0.6, -- deterministic per window
		DayColor = Color3.fromRGB(58, 66, 76),
		NightColor = Color3.fromRGB(255, 214, 140),
	},
}

return LightingConfig
