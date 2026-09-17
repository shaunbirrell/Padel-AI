--!strict
--[[ Interactive tutorial steps for MVP polish. ]]

export type TutorialStepDef = {
	Id: string,
	Title: string,
	Hint: string,
	MarkerName: string, -- Workspace tutorial marker name (best-effort)
	HighlightHint: string?, -- UI highlight target hint (placeholder)
}

local TutorialConfig = {
	Enabled = true,
	-- Step indices match profile.TutorialStep (0-based before complete)
	Steps = {
		{
			Id = "ClaimBase",
			Title = "Claim your base",
			Hint = "Your plot is assigned on join. Walk to your glowing base pad.",
			MarkerName = "Tutorial_ClaimBase",
			HighlightHint = "BasePad",
		},
		{
			Id = "CommandCenter",
			Title = "Build Command Center",
			Hint = "Press B (or Base Upgrades) and buy Command Center.",
			MarkerName = "Tutorial_CommandCenter",
			HighlightHint = "BaseMenu",
		},
		{
			Id = "Income",
			Title = "Collect income",
			Hint = "Watch Cash tick up from passive income on the HUD.",
			MarkerName = "Tutorial_Income",
			HighlightHint = "CashHUD",
		},
		{
			Id = "Barracks",
			Title = "Build Barracks",
			Hint = "Upgrade Barracks (requires Command Center) to boost income.",
			MarkerName = "Tutorial_Barracks",
			HighlightHint = "BaseMenu",
		},
		{
			Id = "Jeep",
			Title = "Spawn a Jeep",
			Hint = "Press G (Garage) and SPAWN your Military Jeep.",
			MarkerName = "Tutorial_Jeep",
			HighlightHint = "Garage",
		},
		{
			Id = "Outpost",
			Title = "Capture an outpost",
			Hint = "Stand in a territory capture zone until you own it.",
			MarkerName = "Tutorial_Outpost",
			HighlightHint = "Territory",
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
