--!strict
--[[ claude-bud JOB 57: base life. A lived-in base on the OWNER's plot (owner-first by the plot owner; OFF = today):
	  * Props: part-built WorldKits rows (tents, crate / ammo stacks, drum groups, sandbag nests and lines, a container
	    stack) on clear ground (plot-local X / Z, BaseLayoutConfig frame), counted against the ONE per-plot allowance
	    StorePropsConfig.Budget.MaxBasePartsPerPlot (600, JOB 40 C) and never inside StorePropsConfig.BaseKeepOut. The
	    store-model BaseRows (StorePropsConfig) stay empty until a model passes the owner's WE_CHECK2 probe.
	  * Soldiers: a few unarmed ambient soldiers that idle and patrol fixed loops (Routes). Not CombatService NPCs: never
	    hostile, no weapon, CanQuery off (shots pass through), not tagged WE_NPC. PerBase each, at most ServerMax in a
	    server (= CombatConfig.MaxActiveNPCs, 18). One server loop at ThinkHz for all of them. ]]

export type Row = { Kit: string, X: number, Z: number, Yaw: number, Opts: { [string]: any }? }
export type Point = { X: number, Z: number }

local BaseLifeConfig = {
	Enabled = true,
	OwnerFirst = true, -- NEW-OWNER-FIRST (claude-bud JOB 57): Code Bot flips it after Shaun's phone test
	Props = {
		-- the west camp, by the facilities row
		{ Kit = "Tent", X = -80, Z = 22, Yaw = 90 },
		{ Kit = "CrateStack", X = -57, Z = 26, Yaw = 0, Opts = { Variant = "ammo", Count = 3 } },
		{ Kit = "DrumGroup", X = -57, Z = 40, Yaw = 30, Opts = { Count = 3 } },
		-- the depot yard
		{ Kit = "Tent", X = 60, Z = 112, Yaw = -90 },
		{ Kit = "CrateStack", X = 68, Z = 124, Yaw = 15, Opts = { Count = 2 } },
		{ Kit = "DrumGroup", X = 54, Z = 124, Yaw = 0, Opts = { Count = 2 } },
		-- the command centre's east side
		{ Kit = "SandbagNest", X = 50, Z = -10, Yaw = 0 },
		{ Kit = "CrateStack", X = 80, Z = 20, Yaw = -20, Opts = { Variant = "ammo", Count = 2 } },
		-- the rear yard
		{ Kit = "ContainerStack", X = -20, Z = -130, Yaw = 90, Opts = { Count = 2 } },
		-- the side edges
		{ Kit = "SandbagLine", X = -140, Z = 0, Yaw = 90, Opts = { Length = 20 } },
		{ Kit = "SandbagLine", X = 140, Z = 0, Yaw = 90, Opts = { Length = 20 } },
	} :: { Row },
	Soldiers = {
		PerBase = 3,
		ServerMaxFromCombat = true, -- ServerMax = CombatConfig.MaxActiveNPCs (18): one number, never more figures than that
		WalkSpeed = 7,
		IdleSeconds = { 4, 9 },
		ThinkHz = 2,
		ArriveStuds = 2.5,
		LegTimeout = 14, -- a leg that takes longer (blocked) ends in IDLE at once, then the next point
		VisualKind = "Guard", -- VisualAssetService.TryAttachCharacterVisual (the house R6 soldier; RigAnimator walks it)
		Routes = {
			{ { X = -66, Z = 8 }, { X = -48, Z = 8 }, { X = -48, Z = 56 }, { X = -66, Z = 56 } },
			{ { X = 46, Z = 98 }, { X = 78, Z = 98 }, { X = 78, Z = 134 }, { X = 46, Z = 134 } },
			{ { X = 2, Z = -118 }, { X = -42, Z = -118 }, { X = -42, Z = -142 }, { X = 2, Z = -142 } },
		} :: { { Point } },
	},
}

-- the soldier brain (pure; the tests): IDLE -> PATROL when the idle time is up; PATROL -> IDLE on arrival or timeout
function BaseLifeConfig.Next(state: string, ctx: { Now: number, IdleUntil: number, LegStarted: number, Dist: number }): string
	local S = BaseLifeConfig.Soldiers
	if state == "IDLE" then
		return if ctx.Now >= ctx.IdleUntil then "PATROL" else "IDLE"
	end
	if ctx.Dist <= S.ArriveStuds or ctx.Now - ctx.LegStarted >= S.LegTimeout then
		return "IDLE"
	end
	return "PATROL"
end

return BaseLifeConfig
