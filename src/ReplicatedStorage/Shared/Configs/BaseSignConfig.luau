--!strict
--[[
	claude-bud JOB 25: the "<Name>'s Empire" sign above every base plot (Server/Services/BaseSignService). Server-built
	(everyone sees the same thing), one per plot, updated only when what it shows changes (checked every UpdateSeconds;
	nothing per frame).
	  * Owned plot: the owner's avatar headshot, "<DisplayName>'s Empire" (Roblox display names are already filtered),
	    a line "LV 12 · REBIRTH 2 · ARMY 8", and a small flag PLATE beside the sign: a part dressed with the owner's
	    chosen national flag as Textures (NationFlag / NationTexture, the CLAUDE.md nation rule: flags in the world are
	    Textures, never GUIs; plain army green while no flag art is uploaded or no flag is chosen).
	  * Empty plot: "UNCLAIMED BASE" + "walk in to claim".
	  * Placement: HeightStuds above the plot's main gate (clear of every building), BillboardGui with a fixed pixel size
	    (the same size near and far: readable from the road, not huge up close), MaxDistanceStuds.
	CustomEmpireNames = false: no player-typed names (if ever turned on, they must go through TextService filtering).
	Enabled = false: no signs.
]]

local BaseSignConfig = {
	Enabled = true,
	CustomEmpireNames = false,
	HeightStuds = 26,
	MaxDistanceStuds = 220, -- (a base sign is meant to be read from the road; see ASSUMPTIONS for the world-label rule)
	SizePx = Vector2.new(250, 78),
	UpdateSeconds = 5,
	FlagPlateSize = Vector3.new(5.2, 3.9, 0.14), -- 4:3, the NationFlag face size family
	UnclaimedTitle = "UNCLAIMED BASE",
	UnclaimedLine = "walk in to claim",
	Gold = Color3.fromRGB(235, 200, 110),
	Khaki = Color3.fromRGB(205, 195, 160),
	Plate = Color3.fromRGB(24, 26, 21),
}

return BaseSignConfig
