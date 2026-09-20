--!strict
--[[
	Near-plot oil pumpjacks outside DefensiveWalls (toward warzone / map origin).
	Income → PendingCash. Does NOT touch OilRig Alpha/Bravo far POIs.
]]

local PlotOilPumpConfig = {
	Enabled = true,
	MinWallsLevel = 2,
	PumpsPerPlot = 2,
	WallClearanceStuds = 18,
	LateralSpreadStuds = 22,
	CashPerTick = 18,
	TickSeconds = 5,
	BillboardMaxDistance = 80,
	VisualPropKey = "OilPumpjack", -- v41 realistic nodding donkey (alt OilPumpjackAlt)
	FolderName = "WE_PlotOilPumps",
	Reason = "plot_oil",
}

return PlotOilPumpConfig
