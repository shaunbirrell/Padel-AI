--!strict
--[[ Interactive tutorial steps — short plain copy, one step at a time.
	v71 P1-15: device-neutral copy (about 80% of players are on phones): no key names, no "click"; the chip's GO
	button runs CtaAction. Buy steps point at the structure's own console (console-only buying): at L0 the BUY
	button there reads BUILD. The beam target of every step is the player's OWN plot (TutorialController.ResolveTarget).
	Hints stay <= 42 characters: the objective chip shows 2 hint lines, about 44 characters on an 800x360 phone.

	F6 (owner's 11 features, lane K2), OrderVersion 2, the owner's 7-step order:
	  1 ClaimBase  2 CommandCenter  3 Income (the old ClickDropper step is folded in: a cash drop also counts)
	  4 RecruitSoldiers  5 Barracks  6 Outpost (the own Home Outpost)  7 Jeep
	The outpost-before-4x4 order is only legal with the Home Outpost (F10, TerritoryConfig.Starter): without it the
	nearest zone is a 34-45 s walk, over the 30 s travel rule. So OutpostBeforeJeep() follows Starter.Enabled, and
	while it is false the last two steps swap to Jeep then Outpost (the 4x4 is the shortcut to the zone).
	v72's Ammo Works step 6 is gone: the first war business is introduced after the tutorial by the NEXT chip
	(TycoonGuideConfig.PickMode "Cheapest": Ammo Works L1 $600 is the cheapest pad once the tutorial is done).

	AdvanceOn lists the TutorialService.Notify event types that finish a step (PlotAssigned | Upgrade |
	RecruitSoldiers | PassiveIncome | ManualDrop | SpawnVehicle | CaptureTerritory). An "Upgrade" finishes a step only
	when its detail (the structure id) equals the step's PadStructureId. Step Ids are stable save keys: a saved
	TutorialStep index is read in the order its TutorialOrderVersion names (missing = 1 = LegacyOrderV1) and moved to
	this order by MigrateLegacyStep.

	Lane Z (the Home Outpost switch-on): an order version names ONE fixed order (SavedOrder), so OrderVersion follows
	the switch: 2 = the owner's steps with the 4x4 before the outpost (the order v2 saves were made in, Home Outpost
	off), 3 = the owner's order, outpost before the 4x4 (Home Outpost on). A save made in another known order is
	migrated when it loads, in either direction; a step it already did that the new order puts later (a v2 save that
	spawned the 4x4 and still owes the outpost) is carried as DoneAhead, so it is never asked for twice.
]]

local TerritoryConfig = require(script.Parent.TerritoryConfig)

export type TutorialStepDef = {
	Id: string,
	Title: string,
	Hint: string,
	MarkerName: string,
	HighlightHint: string?,
	PadStructureId: string?,
	CtaAction: string?,
	CtaLabel: string?,
	-- F6: the Notify event types that finish this step (see the header)
	AdvanceOn: { string },
	-- F5 pointer while this step is active (chevrons / GO line): "ATM" = the player's own ATM. nil = the step's
	-- PadStructureId console when it has one, else no floor pointer (Recruit / Outpost / Jeep: GO opens a panel or
	-- the zone beam leads).
	Pointer: string?,
}

local TutorialConfig = {
	Enabled = true,
	-- F6: the order a profile's TutorialStep index is saved in (ProfileSchema stamps new profiles with it;
	-- TutorialService migrates other known versions with MigrateLegacyStep, then stamps it). Lane Z: 3 while the
	-- Home Outpost is on (outpost, then 4x4), 2 while it is off (4x4, then outpost); see SavedOrders.
	OrderVersion = if TerritoryConfig.Starter.Enabled == true then 3 else 2,
	-- The v1 order (v31 .. v72) by step Id, index = the saved TutorialStep. "ClickDropper" and v72's "AmmoWorks"
	-- (step 6 while the businesses were on) are not steps any more: LegacyAlias names the step that replaces them.
	LegacyOrderV1 = {
		"ClaimBase",
		"Income",
		"ClickDropper",
		"CommandCenter",
		"RecruitSoldiers",
		"Barracks",
		"Jeep",
		"Outpost",
	} :: { string },
	LegacyAlias = { ClickDropper = "Income", AmmoWorks = "Barracks" } :: { [string]: string },
	-- Lane Z: the fixed order of every later OrderVersion, by step Id (index = the saved TutorialStep). 2 is the order
	-- the v2 build shipped with (Home Outpost off: 4x4 6, outpost 7); 3 is the owner's order (outpost 6, 4x4 7).
	SavedOrders = {
		[2] = { "ClaimBase", "CommandCenter", "Income", "RecruitSoldiers", "Barracks", "Jeep", "Outpost" },
		[3] = { "ClaimBase", "CommandCenter", "Income", "RecruitSoldiers", "Barracks", "Outpost", "Jeep" },
	} :: { [number]: { string } },
	-- Lane Z: the steps whose finish is carried (DoneAhead) when a new order puts them after the step a save moves to:
	-- the Outpost / 4x4 pair the Home Outpost switch reorders. Any other done step after it is asked again (K2's "first
	-- step not done" rule: a v1 save that collected before buying the Command Center is taught to collect again).
	CarryDoneIds = { Outpost = true, Jeep = true } :: { [string]: boolean },
	-- The owner's order (OutpostBeforeJeep() true). BuildSteps swaps Outpost and Jeep while it is false.
	Steps = {
		{
			Id = "ClaimBase",
			Title = "Your base",
			Hint = "Walk to the glowing pad on your plot.",
			MarkerName = "Tutorial_ClaimBase",
			HighlightHint = "BasePad",
			CtaAction = "WatchHud",
			CtaLabel = "GO TO BASE",
			AdvanceOn = { "PlotAssigned" },
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
			AdvanceOn = { "Upgrade" },
		},
		{
			Id = "Income",
			Title = "Collect cash",
			Hint = "Walk up to your ATM to collect cash.",
			MarkerName = "Tutorial_Income",
			HighlightHint = "CashHUD",
			CtaAction = "WatchHud",
			CtaLabel = "COLLECT",
			AdvanceOn = { "PassiveIncome", "ManualDrop" },
			Pointer = "ATM",
		},
		{
			Id = "RecruitSoldiers",
			Title = "Recruit soldiers",
			Hint = "Recruit a soldier. They train for cash.",
			MarkerName = "Tutorial_Recruit",
			HighlightHint = "Army",
			CtaAction = "OpenArmy",
			CtaLabel = "ARMY",
			AdvanceOn = { "RecruitSoldiers" },
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
			AdvanceOn = { "Upgrade" },
		},
		{
			Id = "Outpost",
			Title = "Capture outpost",
			Hint = "Stand in a zone until it's yours.",
			MarkerName = "Tutorial_Outpost",
			HighlightHint = "Territory",
			CtaAction = "Capture",
			CtaLabel = "FIND ZONE",
			AdvanceOn = { "CaptureTerritory" },
		},
		{
			Id = "Jeep", -- JEEP-2: the id / marker stay (TutorialService, MapSetup's Tutorial_Jeep); the copy says 4x4
			Title = "Spawn 4x4",
			Hint = "Open the Garage and spawn your 4x4.",
			MarkerName = "Tutorial_Jeep",
			HighlightHint = "Garage",
			CtaAction = "OpenGarage",
			CtaLabel = "GARAGE",
			AdvanceOn = { "SpawnVehicle" },
		},
	} :: { TutorialStepDef },
}

-- F6 / F10: the owner's outpost-then-4x4 order only while the Home Outpost exists (30 s travel rule)
function TutorialConfig.OutpostBeforeJeep(): boolean
	return TerritoryConfig.Starter.Enabled == true
end

local OWNER_STEPS = TutorialConfig.Steps -- the literal list above (never changed)

-- The 7 steps in order; outpostFirst = false swaps Outpost and Jeep (Jeep 6, Outpost 7). Pure: returns a new list.
function TutorialConfig.BuildSteps(outpostFirst: boolean): { TutorialStepDef }
	local steps: { TutorialStepDef } = {}
	local iOutpost, iJeep = 0, 0
	for i, def in ipairs(OWNER_STEPS) do
		steps[i] = def
		if def.Id == "Outpost" then
			iOutpost = i
		elseif def.Id == "Jeep" then
			iJeep = i
		end
	end
	if not outpostFirst and iOutpost > 0 and iJeep > 0 then
		steps[iOutpost], steps[iJeep] = steps[iJeep], steps[iOutpost]
	end
	return steps
end

TutorialConfig.Steps = TutorialConfig.BuildSteps(TutorialConfig.OutpostBeforeJeep())

function TutorialConfig.GetStep(index: number): TutorialStepDef?
	return TutorialConfig.Steps[index]
end

function TutorialConfig.StepCount(): number
	return #TutorialConfig.Steps
end

-- Index of a step Id in `steps` (default: the current Steps), or nil
function TutorialConfig.IndexOf(id: string, steps: { TutorialStepDef }?): number?
	for i, def in ipairs(steps or TutorialConfig.Steps) do
		if def.Id == id then
			return i
		end
	end
	return nil
end

-- true when `eventType` (with `detail`) finishes step `def` (F6 AdvanceOn rule; the dispatcher TutorialService uses)
function TutorialConfig.Advances(def: TutorialStepDef?, eventType: string, detail: any?): boolean
	if def == nil or table.find(def.AdvanceOn, eventType) == nil then
		return false
	end
	if eventType == "Upgrade" then
		return def.PadStructureId ~= nil and detail == def.PadStructureId
	end
	return true
end

-- Lane Z: the step Ids, in order, of a saved OrderVersion (1 or missing = LegacyOrderV1); nil for an order this build
-- does not know (a newer build's save: left alone).
function TutorialConfig.SavedOrder(version: any): { string }?
	local v = tonumber(version) or 1
	if v == 1 then
		return TutorialConfig.LegacyOrderV1
	end
	return TutorialConfig.SavedOrders[v]
end

-- The step Ids (aliases applied) a save at `old` in `legacy` order has finished: every step before it
local function doneBefore(legacy: { string }, old: number): { [string]: boolean }
	local done: { [string]: boolean } = {}
	for i = 1, math.min(old - 1, #legacy) do
		local id = legacy[i]
		done[TutorialConfig.LegacyAlias[id] or id] = true
	end
	return done
end

--[[ F6 migration: a TutorialStep index saved in the v1 order -> the index of the first step of the current order
	(`steps`, default Steps) the player has not done yet. Every v1 step before `oldStep` counts as done, by Id through
	LegacyAlias. So v1 step 2 or 3 (Income / ClickDropper, Command Center not bought) -> 2 (Command Center, never
	skipped), v1 6 (Barracks, or v72's Ammo Works) -> 5, v1 7 (Jeep) -> the first of Outpost / Jeep in this order.
	The caller (TutorialService) then skips buy steps for structures already owned. oldStep < 1 or junk -> 1; oldStep
	past the v1 list -> #steps + 1 (done; TutorialComplete decides on its own). Pure. ]]
-- fromVersion (lane Z): the order oldStep was saved in (default 1 = LegacyOrderV1; see SavedOrder).
function TutorialConfig.MigrateLegacyStep(oldStep: any, steps: { TutorialStepDef }?, fromVersion: number?): number
	local list = steps or TutorialConfig.Steps
	local n = tonumber(oldStep)
	if n == nil or n ~= n or n < 1 then
		return 1
	end
	local old = math.floor(n)
	local legacy = TutorialConfig.SavedOrder(fromVersion) or TutorialConfig.LegacyOrderV1
	if old > #legacy then
		return #list + 1
	end
	local done = doneBefore(legacy, old)
	for i, def in ipairs(list) do
		if not done[def.Id] then
			return i
		end
	end
	return #list + 1
end

--[[ Lane Z: the steps a save already finished that the new order (`steps`, default Steps) puts AFTER the step it
	migrates to (CarryDoneIds only), as { [Id] = true }, or nil when there are none. Only the Outpost / 4x4 swap makes
	one: a v2 (or v1) save that spawned the 4x4 and still owes the outpost moves to Outpost (6 in order 3) with
	{ Jeep = true }, so the 4x4 step is skipped instead of asked for again. TutorialService keeps it on the profile
	(TutorialDoneAhead). Pure. ]]
function TutorialConfig.DoneAhead(oldStep: any, fromVersion: number?, steps: { TutorialStepDef }?): { [string]: boolean }?
	local list = steps or TutorialConfig.Steps
	local n = tonumber(oldStep)
	if n == nil or n ~= n or n < 1 then
		return nil
	end
	local old = math.floor(n)
	local legacy = TutorialConfig.SavedOrder(fromVersion) or TutorialConfig.LegacyOrderV1
	if old > #legacy then
		return nil
	end
	local target = TutorialConfig.MigrateLegacyStep(old, list, fromVersion)
	local done = doneBefore(legacy, old)
	local ahead: { [string]: boolean }? = nil
	for i, def in ipairs(list) do
		if i > target and done[def.Id] and TutorialConfig.CarryDoneIds[def.Id] == true then
			local a: { [string]: boolean } = ahead or {}
			a[def.Id] = true
			ahead = a
		end
	end
	return ahead
end

return TutorialConfig
