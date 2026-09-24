--!strict
--[[ Interactive tutorial steps — short plain copy, one step at a time.
	v31 first-2-min: Claim → MoneyCollector → ClickDropper → CommandCenter buy,
	then Recruit → Barracks → Jeep (players see "4x4") → Outpost.
	v71 P1-15: device-neutral copy (about 80% of players are on phones): no key names, no "click"; the chip's GO
	button runs CtaAction. Buy steps point at the structure's own console (console-only buying): at L0 the BUY
	button there reads BUILD. The beam target of every step is the player's OWN plot (TutorialController.ResolveTarget).
	Hints stay <= 42 characters: the objective chip shows 2 hint lines, about 44 characters on an 800x360 phone.
	v72: while BusinessConfig.Enabled, step 6 (BusinessStepIndex) is the first war business, Ammo Works, instead of
	the Barracks buy (Barracks moves into TycoonGuideConfig.Opening). No marker part is built for it: GO resolves
	through PadStructureId to the player's own console, so a missing "Tutorial_Business" marker is fine. Businesses
	off: step 6 stays the Barracks buy (exactly as before v72).
]]

local BusinessConfig = require(script.Parent.BusinessConfig)

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
			Id = "Income",
			Title = "Collect cash",
			Hint = "Walk up to your ATM to collect cash.",
			MarkerName = "Tutorial_Income",
			HighlightHint = "CashHUD",
			CtaAction = "WatchHud",
			CtaLabel = "COLLECT",
		},
		{
			Id = "ClickDropper",
			Title = "Grab cash drops",
			Hint = "Grab the green cash drop by your ATM.",
			MarkerName = "Tutorial_Dropper",
			HighlightHint = "CashHUD",
			CtaAction = "WatchHud",
			CtaLabel = "CASH DROP",
		},
		{
			Id = "CommandCenter",
			Title = "Command Center",
			Hint = "Follow the gold line, then press BUILD.",
			MarkerName = "Tutorial_CommandCenter",
			HighlightHint = "Console",
			PadStructureId = "CommandCenter",
			CtaAction = "PadBuy",
			CtaLabel = "GO",
		},
		{
			Id = "RecruitSoldiers",
			Title = "Recruit workers",
			Hint = "Open Army and recruit a soldier.",
			MarkerName = "Tutorial_Recruit",
			HighlightHint = "Army",
			CtaAction = "OpenArmy",
			CtaLabel = "ARMY",
		},
		{
			Id = "Barracks",
			Title = "Barracks",
			Hint = "Follow the gold line, then press BUILD.",
			MarkerName = "Tutorial_Barracks",
			HighlightHint = "Console",
			PadStructureId = "Barracks",
			CtaAction = "PadBuy",
			CtaLabel = "GO",
		},
		{
			Id = "Jeep", -- JEEP-2: the id / marker stay (TutorialService, MapSetup's Tutorial_Jeep); the copy says 4x4
			Title = "Spawn 4x4",
			Hint = "Open the Garage and spawn your 4x4.",
			MarkerName = "Tutorial_Jeep",
			HighlightHint = "Garage",
			CtaAction = "OpenGarage",
			CtaLabel = "GARAGE",
		},
		{
			Id = "Outpost",
			Title = "Capture outpost",
			Hint = "Stand in a zone until it's yours.",
			MarkerName = "Tutorial_Outpost",
			HighlightHint = "Territory",
			CtaAction = "Capture",
			CtaLabel = "FIND ZONE",
		},
	} :: { TutorialStepDef },
}

-- v72: step 6 = the Ammo Works buy while the war businesses are on (TutorialService advances it on a purchase whose
-- id equals Steps[BusinessStepIndex].PadStructureId)
TutorialConfig.BusinessStepIndex = 6
TutorialConfig.BusinessStep = {
	Id = "AmmoWorks",
	Title = "Ammo Works",
	Hint = "Build your Ammo Works. It makes cash.",
	MarkerName = "Tutorial_Business",
	HighlightHint = "Console",
	PadStructureId = "AmmoWorks",
	CtaAction = "PadBuy",
	CtaLabel = "GO",
} :: TutorialStepDef
if BusinessConfig.Enabled then
	TutorialConfig.Steps[TutorialConfig.BusinessStepIndex] = TutorialConfig.BusinessStep
end

function TutorialConfig.GetStep(index: number): TutorialStepDef?
	return TutorialConfig.Steps[index]
end

function TutorialConfig.StepCount(): number
	return #TutorialConfig.Steps
end

return TutorialConfig
