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
	VisualPropKey = "OilPumpjack", -- v41 realistic nodding donkey (alt OilPumpjackAlt)
	FolderName = "WE_PlotOilPumps",
	Reason = "plot_oil",
	-- F9 (owner's 11 features): Golden Pumpjacks (MonetizationConfig.DevProducts.GoldenPumpjack). Owners' pumps are
	-- dressed gold Metal with Reflectance (no Neon, no light). Non-owners, while the Id is live, get ONE 7x7 gold pad
	-- (WE_PremiumPad, OfferKind DevProduct, OfferKey GoldenPumpjack) PadOffsetStuds from the pumps toward the plot, with
	-- one stud-scaled label (MaxDistance LabelMaxDistance, never AlwaysOnTop, tagged WorldLabelConfig.BaseLabelTag).
	Golden = {
		Color = Color3.fromRGB(255, 195, 60),
		Material = Enum.Material.Metal,
		Reflectance = 0.2,
		PadOffsetStuds = 10,
		LabelMaxDistance = 20,
	},
}

return PlotOilPumpConfig
