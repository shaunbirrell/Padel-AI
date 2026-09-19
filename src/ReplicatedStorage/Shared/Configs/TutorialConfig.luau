--!strict
--[[ Interactive tutorial steps for MVP polish. Mobile-first CTAs + pad targeting. ]]

export type TutorialStepDef = {
	Id: string,
	Title: string,
	Hint: string,
	MarkerName: string, -- Workspace tutorial marker name (best-effort)
	HighlightHint: string?, -- UI highlight target hint (placeholder)
	-- When set, client beams to the player's WE_UpgradeSlot with this StructureId
	PadStructureId: string?,
	-- Client CTA: "PadBuy" | "OpenBase" | "OpenGarage" | "WatchHud" | "Capture"
	CtaAction: string?,
	CtaLabel: string?,
}

local TutorialConfig = {
	Enabled = true,
	-- Step indices match profile.TutorialStep (1-based while active)
	Steps = {
		{
			Id = "ClaimBase",
			Title = "Claim your base",
			Hint = "Your plot is assigned on join. Follow the gold beam to your glowing base pad.",
			MarkerName = "Tutorial_ClaimBase",
			HighlightHint = "BasePad",
			CtaAction = "WatchHud",
			CtaLabel = "FOLLOW BEAM",
		},
		{
			Id = "CommandCenter",
			Title = "Buy Command Center",
			Hint = "Stand on the Command Center pad, then tap the big BUY button (or B for base menu). Pads show +$/tick.",
			MarkerName = "Tutorial_CommandCenter",
			HighlightHint = "BaseMenu",
			PadStructureId = "CommandCenter",
			CtaAction = "PadBuy",
			CtaLabel = "BUY ON PAD",
		},
		{
			Id = "Income",
			Title = "Watch your income",
			Hint = "HUD Cash ticks every few seconds from your Command Center +$/tick. Wait for the first payday.",
			MarkerName = "Tutorial_Income",
			HighlightHint = "CashHUD",
			CtaAction = "WatchHud",
			CtaLabel = "WATCH CASH",
		},
		{
			Id = "Barracks",
			Title = "Buy Barracks",
			Hint = "Needs Command Center. Walk onto the Barracks pad and tap BUY — bigger +$/tick on the billboard.",
			MarkerName = "Tutorial_Barracks",
			HighlightHint = "BaseMenu",
			PadStructureId = "Barracks",
			CtaAction = "PadBuy",
			CtaLabel = "BUY BARRACKS",
		},
		{
			Id = "Jeep",
			Title = "Spawn a Jeep",
			Hint = "Open Garage (G or dock) and tap SPAWN on Military Jeep. Starter Jeep is already owned.",
			MarkerName = "Tutorial_Jeep",
			HighlightHint = "Garage",
			CtaAction = "OpenGarage",
			CtaLabel = "OPEN GARAGE",
		},
		{
			Id = "Outpost",
			Title = "Capture an outpost",
			Hint = "Follow the beam to a territory zone. Stand inside until capture completes — you own it.",
			MarkerName = "Tutorial_Outpost",
			HighlightHint = "Territory",
			CtaAction = "Capture",
			CtaLabel = "FIND OUTPOST",
		},
	} :: { TutorialStepDef },
}

function TutorialConfig.GetStep(index: number): TutorialStepDef?
	return TutorialConfig.Steps[index]
end

function TutorialConfig.StepCount(): number
	return #TutorialConfig.Steps
end

return TutorialConfig
