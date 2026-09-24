--!strict
--[[
	World label rules (CLAUDE.md "World labels"; HUD v70 spec §5).

	Two users:
	  * Modules/WorldLabelPolicy (server) enforces the caps on every BillboardGui in Workspace as it appears.
	    v67 only touched labels inside plots; v70 also caps labels outside them (territories, POIs, NPCs, vehicles,
	    the bank, supply drops). It measures from the label's Adornee, else its first ancestor with a position.
	  * Shared/Util/WorldLabel builds labels that already follow the rules (stud-scaled, 14-20 px text, no card).
	    Its look (box studs, font, default range) is HudConfig.WorldLabels.Default.
]]

local WorldLabelConfig = {
	Enabled = true,
	-- Studs. Labels inside a plot further away than this are hidden (default BillboardGui distance is infinite).
	-- v70: 40 (CLAUDE.md: MaxDistance <= 40; was 45).
	MaxDistance = 40,
	-- v70: labels outside the plots get the same treatment (AlwaysOnTop off, range capped). false = v67 behaviour.
	ApplyOutsidePlots = true,
	OutsideMaxDistance = 40,
	-- BillboardGui names allowed to draw over walls/buildings. Everything else gets AlwaysOnTop = false.
	AllowAlwaysOnTop = {} :: { [string]: boolean },
	-- WE_LabelRole values (WorldLabel.SetRole) allowed AlwaysOnTop: the one active objective marker and a contested
	-- flag. Keeping it to ONE objective at a time is the caller's job.
	AlwaysOnTopRoles = { objective = true, contested = true } :: { [string]: boolean },
	-- Studs beyond the plot pad edge still counted as "in the base" (gate, outer sandbags, parked vehicles).
	PlotMargin = 12,

	-- Shared/Util/WorldLabel ------------------------------------------------------------------------------------
	RoleAttribute = "WE_LabelRole", -- "objective" | "contested" (unset = normal label)
	OwnerAttribute = "WE_LabelOwner", -- UserId: only that player sees the label (client filter; 0/unset = everyone)
	OwnerTag = "WE_OwnerLabel", -- CollectionService tag on owner-only labels (what the client filter watches)
	-- Billboard text, real px (world GUIs are not under the HUD UIScale). Fixed TextSize, never TextScaled.
	TextSize = 16,
	SubTextSize = 14,
	MinTextSize = 14,
	MaxTextSize = 20,
	LinePad = 2, -- px added to each line's height
	StudsAbove = 1.5, -- default gap above a part's top face
	-- Painted signs (WorldLabel.Surface). SurfaceGui budget: MaxDistance <= 80.
	SurfaceMaxDistance = 80,
	SurfaceDefaultMaxDistance = 40,
	SurfacePixelsPerStud = 40,
	SurfaceMaxTextSize = 100, -- Roblox's TextSize ceiling
}

return WorldLabelConfig
