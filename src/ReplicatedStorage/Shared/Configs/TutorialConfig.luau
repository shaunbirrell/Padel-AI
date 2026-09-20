--!strict
--[[ Interactive tutorial steps — short plain copy, one step at a time.
	Worker-first: CC → Recruit → Collect → Barracks → Jeep → Outpost.
]]

export type TutorialStepDef = {
	Id: string,
	Title: string,
	Hint: string,
	MarkerName: string,
	HighlightHint: string?,
	PadStructureId: string?,
	CtaAction: string?,
	CtaLabel: string?,
}

local TutorialConfig = {
	Enabled = true,
	Steps = {
		{
			Id = "ClaimBase",
			Title = "Your base",
			Hint = "Walk to the glowing pad on your plot.",
			MarkerName = "Tutorial_ClaimBase",
			HighlightHint = "BasePad",
			CtaAction = "WatchHud",
			CtaLabel = "GO TO BASE",
		},
		{
			Id = "CommandCenter",
			Title = "Command Center",
			Hint = "Stand on the Command Center pad and tap BUY.",
			MarkerName = "Tutorial_CommandCenter",
			HighlightHint = "BaseMenu",
			PadStructureId = "CommandCenter",
			CtaAction = "PadBuy",
			CtaLabel = "BUY",
		},
		{
			Id = "RecruitSoldiers",
			Title = "Recruit workers",
			Hint = "Open Army and recruit a soldier. Workers earn cash at the Training Yard.",
			MarkerName = "Tutorial_Recruit",
			HighlightHint = "Army",
			CtaAction = "OpenArmy",
			CtaLabel = "ARMY",
		},
		{
			Id = "Income",
			Title = "Collect cash",
			Hint = "Touch the Money Collector (green screen) to claim pending cash.",
			MarkerName = "Tutorial_Income",
			HighlightHint = "CashHUD",
			CtaAction = "WatchHud",
			CtaLabel = "COLLECT",
		},
		{
			Id = "Barracks",
			Title = "Barracks",
			Hint = "Stand on the Barracks pad and tap BUY.",
			MarkerName = "Tutorial_Barracks",
			HighlightHint = "BaseMenu",
			PadStructureId = "Barracks",
			CtaAction = "PadBuy",
			CtaLabel = "BUY",
		},
		{
			Id = "Jeep",
			Title = "Spawn Jeep",
			Hint = "Open Garage (G) and spawn your Military Jeep.",
			MarkerName = "Tutorial_Jeep",
			HighlightHint = "Garage",
			CtaAction = "OpenGarage",
			CtaLabel = "GARAGE",
		},
		{
			Id = "Outpost",
			Title = "Capture outpost",
			Hint = "Stand in a territory zone until it captures.",
			MarkerName = "Tutorial_Outpost",
			HighlightHint = "Territory",
			CtaAction = "Capture",
			CtaLabel = "FIND ZONE",
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
