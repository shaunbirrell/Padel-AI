--!strict
--[[
	v67: rules for world labels (BillboardGuis) inside player bases.
	Applied server-side by Modules/WorldLabelPolicy as labels appear. Labels outside the plots
	(territories, POIs, map signs) are not touched, so navigation labels still read from far away.
]]

local WorldLabelConfig = {
	Enabled = true,
	-- Studs. Base labels further away than this are hidden (default BillboardGui distance is infinite).
	MaxDistance = 45,
	-- BillboardGui names allowed to draw over walls/buildings. Everything else in a base gets AlwaysOnTop = false.
	AllowAlwaysOnTop = {} :: { [string]: boolean },
	-- Studs beyond the plot pad edge still counted as "in the base" (gate, outer sandbags, parked vehicles).
	PlotMargin = 12,
}

return WorldLabelConfig
