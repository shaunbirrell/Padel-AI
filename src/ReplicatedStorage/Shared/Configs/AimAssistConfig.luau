--!strict
--[[ W2 Combat Core (mobile plan §4.1, contracts §1.4): server-validated aim assist.

	The server (CombatService/CombatAssist) picks at most ONE target per accepted hitscan shot when the exact ray
	missed and the P0-7 claim did not confirm a target: the alive player or NPC with the smallest sideways distance
	from the fire ray, inside this class's lateral / cone limits, within min(weapon Range, MaxRangeStuds), in front
	of whatever scenery the ray hit, with a clear line of sight. The client (AimTargets) reads Classes and
	MaxRangeStuds to mirror the same cone for its camera aim help; the server stays authoritative.

	The input class comes from the fire payload's Input field and is stored on the Player as ClassAttribute. A
	change is accepted at most once per ClassChangeSeconds. A PC that claims Touch gains at most 2.5 studs / 4°.

	Limits that hold in every version (never tune past these):
	  - assist never extends range and never passes walls;
	  - one target per shot, at the weapon's own fire rate;
	  - no headshot on claims or assist;
	  - no direct assist for projectiles (RocketLauncher, Grenade);
	  - TargetUserId / TargetNpcId never choose an assist target. ]]

export type AssistClass = {
	LateralStuds: number, -- max distance of the target torso from the fire ray
	MaxConeDeg: number, -- max angle between the fire ray and the target torso
}

local AimAssistConfig = {
	Enabled = true,
	Classes = {
		Touch = { LateralStuds = 2.5, MaxConeDeg = 4 },
		Gamepad = { LateralStuds = 2.0, MaxConeDeg = 3 },
		KeyboardAndMouse = { LateralStuds = 1.0, MaxConeDeg = 1.5 },
	} :: { [string]: AssistClass },
	MaxRangeStuds = 150, -- assist range = min(weapon Range, this): sniper assist stops at 150
	DefaultClass = "KeyboardAndMouse",
	ClassChangeSeconds = 5,
	ClassAttribute = "WE_InputClass",
	ExcludeClanAllies = true,
	LosPastTorsoStuds = 2,
}

return AimAssistConfig
