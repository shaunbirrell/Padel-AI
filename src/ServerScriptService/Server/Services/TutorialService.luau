--!strict
--[[
	MVP interactive tutorial (v31 first-2-min), F6 order (the owner's 7 steps; TutorialConfig.OrderVersion 3 with the
	Home Outpost on, 2 with it off):
	claim → Command Center buy → collect cash (a cash drop also counts) → recruit → Barracks buy → Home Outpost → 4x4
	While TerritoryConfig.Starter is off, the last two swap (4x4, then outpost: the 30 s travel rule).
	Server-authoritative step advancement; client shows UI + optional markers. SKIP kept.
	F6 dispatch: a Notify advances the ACTIVE step only, when its TutorialConfig AdvanceOn lists the event type (an
	"Upgrade" also needs detail == the step's PadStructureId). No step index is hard-coded here, so the order lives in
	TutorialConfig alone. A save made in an older order (TutorialOrderVersion) is moved to the first step of this order
	it has not done yet (TutorialConfig.MigrateLegacyStep) when the profile loads, then stamped with OrderVersion.
	The tutorial ending (last step or SKIP) ends the F6 novice shield (CombatService.EndNoviceShield, "tutorial").
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared.Constants)
local TutorialConfig = require(Shared.Configs.TutorialConfig)
local GameConfig = require(Shared.Configs.GameConfig)
local DevConfig = require(Shared.Configs.DevConfig)
local MonetizationConfig = require(Shared.Configs.MonetizationConfig)
local TerritoryConfig = require(Shared.Configs.TerritoryConfig)

local RemoteGuard = require(script.Parent.Parent.Modules.RemoteGuard)

local TutorialService = {}

local DataService: any = nil
local RemoteSetup: any = nil
local NotificationService: any = nil
local RateLimitService: any = nil
local MonetizationService: any = nil
local CombatService: any = nil -- F6: EndNoviceShield (batch A lane C API), pcall + nil-check

-- Step 1 (ClaimBase) is the first step in every order; every other step is found through TutorialConfig
local STEP_CLAIM = 1

-- F6: the order the saved TutorialStep index is read in (config; 1 when a build has no OrderVersion)
local function orderVersion(): number
	return tonumber((TutorialConfig :: any).OrderVersion) or 1
end

-- Debounce rapid Notify spam (collector ticks, double hooks) — per step, so a different step's event right
-- after an advance (e.g. CC bought 0.5 s after the dropper step) is never dropped
local lastAdvanceAt: { [number]: number } = {}
local lastAdvanceStep: { [number]: number } = {}
local ADVANCE_COOLDOWN = 0.75

local function tutorialEnabled(): boolean
	if not GameConfig.TutorialEnabled or not TutorialConfig.Enabled then
		return false
	end
	return true
end

local function pushTutorial(player: Player)
	if not DataService then
		return -- v69: before Init
	end
	local profile = DataService.GetProfile(player)
	if not profile then
		return
	end
	local remote = RemoteSetup.Get(Constants.RemoteNames.TutorialStateUpdate) :: RemoteEvent
	local stepIndex = profile.TutorialStep
	local stepDef = if not profile.TutorialComplete then TutorialConfig.GetStep(stepIndex) else nil
	remote:FireClient(player, {
		Step = stepIndex,
		Complete = profile.TutorialComplete == true,
		Total = TutorialConfig.StepCount(),
		Id = if stepDef then stepDef.Id else nil,
		Title = if stepDef then stepDef.Title else nil,
		Hint = if stepDef then stepDef.Hint else nil,
		MarkerName = if stepDef then stepDef.MarkerName else nil,
		HighlightHint = if stepDef then stepDef.HighlightHint else nil,
		PadStructureId = if stepDef then stepDef.PadStructureId else nil,
		CtaAction = if stepDef then stepDef.CtaAction else nil,
		CtaLabel = if stepDef then stepDef.CtaLabel else nil,
		Pointer = if stepDef then stepDef.Pointer else nil, -- F5: "ATM" on the collect step (chevrons / GO line)
	})
end

function TutorialService.Push(player: Player)
	pushTutorial(player)
end

--[[ v71 money (M1, plan §2.1 "Pop-up race"; revenue audit F4 / R3): the Commander Starter Pack offer belongs to the
	end of the tutorial, not to the join (it used to fire 8 s after join mid-tutorial and usually lost its slot to the
	Speed Boost pop-up). TutorialService decides WHEN: StarterBundleOffer.AfterTutorialSeconds (3 s) after the tutorial
	completes (the last step done, or SKIP), or StarterBundleOffer.DelaySeconds (8 s) after the profile loads when the
	tutorial is already done. MonetizationService.TrySoftOfferStarterBundle(player, reason) decides WHETHER and sends
	it (live Id, unoffered = profile.StarterBundleOffered, unowned, the soft-offer slot / D8 budget; true = sent,
	nil = not wanted, false = slot busy) down the existing path: the StarterBundleOffer remote → ShopController's
	StarterBundleToast → NotificationController.ShowOffer, so the HUD throttle still decides when the card shows.
	A busy slot is retried STARTER_RETRIES times, one soft-offer cooldown apart. Nothing here grants or prompts.
	F6: the tutorial can now end in a vehicle (the last step is the 4x4 while the Home Outpost is off, and a capture can
	be made from the driver's seat), so an after-tutorial offer first waits until the player is on foot
	(Humanoid.SeatPart == nil): checked every STARTER_SEATED_CHECK_SECONDS (1 Hz) for up to STARTER_SEATED_WAIT_SECONDS
	(300 s) in total, then the gate is called as before (it and the HUD throttle still decide). A player on foot sees
	no change: the first check passes at once. Optional config keys: StarterBundleOffer.SeatedWaitSeconds /
	SeatedCheckSeconds. ]]
local STARTER_AFTER_TUTORIAL_SECONDS = 3
local STARTER_AT_LOAD_SECONDS = 8
local STARTER_RETRIES = 2
local STARTER_SEATED_WAIT_SECONDS = 300
local STARTER_SEATED_CHECK_SECONDS = 1
local starterToken: { [number]: number } = {} -- userId -> the pending offer schedule (one at a time)
local starterSeq = 0

-- F6: sitting in any seat (driving or riding): no offer card while driving (CLAUDE.md: no pop-ups while driving)
local function isSeated(player: Player): boolean
	local char = player.Character
	local hum = if char then char:FindFirstChildOfClass("Humanoid") else nil
	return hum ~= nil and hum.SeatPart ~= nil
end

local function scheduleStarterOffer(player: Player, afterTutorial: boolean)
	local mon = MonetizationService
	if not mon or typeof(mon.TrySoftOfferStarterBundle) ~= "function" or not DataService then
		return
	end
	local def: any = MonetizationConfig.DevProducts.StarterBundle
	local profile = DataService.GetProfile(player)
	if typeof(def) ~= "table" or (tonumber(def.Id) or 0) == 0 or not profile or profile.StarterBundleOffered == true then
		return
	end
	if typeof(profile.Entitlements) == "table" and profile.Entitlements.StarterBundle == true then
		return -- owned (the gate re-checks ownership when it fires; this only skips a pointless timer)
	end
	local uid = player.UserId
	if starterToken[uid] ~= nil then
		return
	end
	starterSeq += 1
	local my = starterSeq
	starterToken[uid] = my
	local cfg: any = (MonetizationConfig :: any).StarterBundleOffer
	local delaySec = if afterTutorial
		then tonumber(cfg and cfg.AfterTutorialSeconds) or STARTER_AFTER_TUTORIAL_SECONDS
		else tonumber(cfg and cfg.DelaySeconds) or STARTER_AT_LOAD_SECONDS
	local cooldown = tonumber((MonetizationConfig :: any).SoftOfferSessionCooldownSeconds) or 60
	local reason = if afterTutorial then "tutorial_complete" else "session"
	-- F6: the seated wait (after the tutorial only); one budget for the whole schedule, retries included
	local seatedLeft = if afterTutorial then math.max(0, tonumber(cfg and cfg.SeatedWaitSeconds) or STARTER_SEATED_WAIT_SECONDS) else 0
	local seatedStep = math.max(0.25, tonumber(cfg and cfg.SeatedCheckSeconds) or STARTER_SEATED_CHECK_SECONDS)
	local function attempt(n: number)
		if starterToken[uid] ~= my then
			return -- left the server
		end
		if seatedLeft > 0 and player.Parent and isSeated(player) then
			seatedLeft -= seatedStep
			task.delay(seatedStep, attempt, n) -- still in a seat: look again in 1 s
			return
		end
		local sent: boolean? = nil
		if player.Parent then
			local ok, res = pcall(mon.TrySoftOfferStarterBundle, player, reason)
			if ok then
				sent = res
			else
				warn("[TutorialService] Starter offer failed:", res)
			end
		end
		if starterToken[uid] ~= my then
			return
		end
		if sent == false and n <= STARTER_RETRIES and player.Parent then
			task.delay(cooldown, attempt, n + 1) -- the soft-offer slot was busy
		else
			starterToken[uid] = nil
		end
	end
	task.delay(delaySec, attempt, 1)
end

--[[ v69: buy steps (PadStructureId) for a structure the player already owns are done — skip them. The HUD goal
	sends new players to buy Command Center early, which then only advanced on ANOTHER CC purchase ($8,000 for L2);
	same for Barracks. Returns the first step that still needs doing.
	F6 / F10: with the Home Outpost on (TerritoryConfig.Starter.Enabled), the Outpost step is done too once the player
	has taken their own Home Outpost (profile.StarterOutpostTaken, set by the first capture): later sessions own it
	from the start, so it could never be captured again for the step, and the next zone is over the 30 s walk.
	Lane Z: a step the save already finished in its old order but the new order puts later (profile.TutorialDoneAhead,
	set by migrateOrder, e.g. the 4x4 of a v2 save that still owes the outpost) is done too. ]]
local function stepAlreadyDone(profile: any, def: TutorialConfig.TutorialStepDef?): boolean
	if def == nil then
		return false
	end
	local ahead = profile.TutorialDoneAhead
	if typeof(ahead) == "table" and ahead[def.Id] == true then
		return true
	end
	local sid = def.PadStructureId
	if typeof(sid) == "string" then
		local upgrades = if typeof(profile.BaseUpgrades) == "table" then profile.BaseUpgrades else {}
		return (tonumber(upgrades[sid]) or 0) >= 1
	end
	if def.Id == "Outpost" then
		return TerritoryConfig.Starter.Enabled == true and profile.StarterOutpostTaken == true
	end
	return false
end

local function skipOwnedBuySteps(profile: any, step: number): number
	local total = TutorialConfig.StepCount()
	while step <= total and stepAlreadyDone(profile, TutorialConfig.GetStep(step)) do
		step += 1
	end
	return step
end

-- F6: the tutorial is over (last step, SKIP, or already done at load): end the novice shield now. CombatService's
-- own 1 Hz sweep also ends it on TutorialComplete; this call makes it immediate. Harmless when no shield is up.
local function endNoviceShield(player: Player)
	if CombatService and typeof(CombatService.EndNoviceShield) == "function" then
		local ok, err = pcall(CombatService.EndNoviceShield, player, "tutorial")
		if not ok then
			warn("[TutorialService] EndNoviceShield failed:", err)
		end
	end
end

local function setStep(player: Player, step: number, complete: boolean?)
	local profile = DataService.GetProfile(player)
	if not profile then
		return
	end
	profile.TutorialStep = step
	if complete then
		profile.TutorialComplete = true
	end
	DataService.MarkDirty(player)
	pushTutorial(player)
	if complete and NotificationService then
		NotificationService.Notify(player, "Tutorial complete — BUILD. CONQUER. DOMINATE.", "Success")
	end
	if complete then
		endNoviceShield(player) -- F6
		scheduleStarterOffer(player, true) -- v71 money (M1): the Starter Pack offer 3 s after the tutorial
	end
end

local function advanceTo(player: Player, targetStep: number)
	local profile = DataService.GetProfile(player)
	if not profile or profile.TutorialComplete then
		return
	end
	if profile.TutorialStep < targetStep then
		return
	end
	if profile.TutorialStep ~= targetStep then
		return
	end
	local now = os.clock()
	local last = lastAdvanceAt[player.UserId]
	if last and (now - last) < ADVANCE_COOLDOWN and lastAdvanceStep[player.UserId] == targetStep then
		return
	end
	lastAdvanceAt[player.UserId] = now
	lastAdvanceStep[player.UserId] = targetStep
	-- One setStep (one push): the client drops a second TutorialStateUpdate that lands within 0.2 s
	local nextStep = skipOwnedBuySteps(profile, targetStep + 1)
	if nextStep > TutorialConfig.StepCount() then
		setStep(player, nextStep, true)
	else
		-- Panel update only — no toast spam per step
		setStep(player, nextStep, false)
	end
end

function TutorialService.Complete(player: Player)
	if not DataService then
		return -- v69: before Init
	end
	local profile = DataService.GetProfile(player)
	if not profile then
		return
	end
	profile.TutorialComplete = true
	profile.TutorialStep = TutorialConfig.StepCount() + 1
	DataService.MarkDirty(player)
	pushTutorial(player)
	if NotificationService then
		NotificationService.Notify(player, "Tutorial skipped.", "Info", 2)
	end
	endNoviceShield(player) -- F6: SKIP ends the novice shield too
	scheduleStarterOffer(player, true) -- v71 money (M1): the Starter Pack offer 3 s after the tutorial
end

function TutorialService.Reset(player: Player)
	if not DataService then
		return -- v69: before Init
	end
	local profile = DataService.GetProfile(player)
	if not profile then
		return
	end
	profile.TutorialComplete = false
	profile.TutorialStep = STEP_CLAIM
	profile.TutorialOrderVersion = orderVersion() -- F6: step 1 is the same step in every order
	profile.TutorialDoneAhead = nil -- lane Z: a fresh run owes every step
	DataService.MarkDirty(player)
	pushTutorial(player)
end

--[[
	event types: PlotAssigned | Upgrade | RecruitSoldiers | PassiveIncome | ManualDrop | SpawnVehicle | CaptureTerritory
]]
function TutorialService.Notify(player: Player, eventType: string, detail: any?)
	if not tutorialEnabled() then
		return
	end
	if not DataService then
		-- v69: called before Init (BaseService's join hook used to throw here and skip the kit rehydrate).
		-- Init's OnProfileLoaded replays PlotAssigned for every loaded player.
		return
	end
	local profile = DataService.GetProfile(player)
	if not profile or profile.TutorialComplete then
		return
	end

	local step = profile.TutorialStep
	if step < 1 then
		profile.TutorialStep = STEP_CLAIM
		step = STEP_CLAIM
		DataService.MarkDirty(player)
	end

	-- v69: server full → no plot yet; the claim step waits until a plot is handed out
	if eventType == "PlotAssigned" and profile.BasePlotId == nil then
		return
	end
	-- F6: only the ACTIVE step can finish, and only on an event its AdvanceOn lists ("Upgrade" = its own console buy;
	-- any vehicle spawn = the 4x4 step; a collect or a cash drop ("ManualDrop") = the collect step)
	local def = TutorialConfig.GetStep(step)
	if def and typeof(def.AdvanceOn) == "table" and table.find(def.AdvanceOn, eventType)
		and (eventType ~= "Upgrade" or (typeof(detail) == "string" and detail == def.PadStructureId)) then
		advanceTo(player, step)
	end
end

function TutorialService.Init(deps: { [string]: any })
	DataService = deps.DataService
	RemoteSetup = deps.RemoteSetup
	NotificationService = deps.NotificationService
	RateLimitService = deps.RateLimitService
	MonetizationService = deps.MonetizationService -- v71 money (M1): TrySoftOfferStarterBundle (Starter Pack gate)
	CombatService = deps.CombatService -- F6: EndNoviceShield (CombatService.Init runs later; called only at run time)

	local skipRemote = RemoteSetup.Get(Constants.RemoteNames.RequestSkipTutorial) :: RemoteEvent
	skipRemote.OnServerEvent:Connect(function(player: Player)
		if not RateLimitService.Allow(player, "tutorial_skip", 1, 2) then
			return
		end
		if not RemoteGuard.RequireProfile(DataService, player) then
			return
		end
		TutorialService.Complete(player)
	end)

	--[[ F6: a TutorialStep saved in another order (TutorialOrderVersion ~= OrderVersion; missing = 1 = the v1 order)
		moves to the first step of this order the player has not done yet (TutorialConfig.MigrateLegacyStep: v1 steps
		2-4 -> Command Center, never past it), then the profile is stamped with this order. A finished tutorial keeps its
		step (only the stamp changes). Lane Z: every known order migrates, in either direction (OrderVersion follows the
		Home Outpost switch: 2 = 4x4 first, 3 = outpost first); a step already done that the new order puts later is kept
		in TutorialDoneAhead (never asked twice). A save from an order this build does not know (a newer build) is left
		alone (never stamped down, so it is never migrated twice). ]]
	local function migrateOrder(player: Player, profile: any)
		local current = orderVersion()
		local saved = tonumber(profile.TutorialOrderVersion) or 1
		if saved == current or TutorialConfig.SavedOrder(saved) == nil then
			return
		end
		if profile.TutorialComplete ~= true then
			local oldStep = profile.TutorialStep
			profile.TutorialStep = TutorialConfig.MigrateLegacyStep(oldStep, nil, saved)
			-- a done step stays done in every order: keep what an earlier migration carried
			local ahead = TutorialConfig.DoneAhead(oldStep, saved) or {}
			if typeof(profile.TutorialDoneAhead) == "table" then
				for id, v in pairs(profile.TutorialDoneAhead) do
					if typeof(id) == "string" and v == true then
						ahead[id] = true
					end
				end
			end
			profile.TutorialDoneAhead = if next(ahead) ~= nil then ahead else nil
		end
		profile.TutorialOrderVersion = current
		DataService.MarkDirty(player)
	end

	local function onProfileLoaded(player: Player, profile: any)
		if not tutorialEnabled() then
			profile.TutorialComplete = true
			pushTutorial(player)
			return
		end
		migrateOrder(player, profile)
		if RunService:IsStudio() and DevConfig.SkipTutorial then
			-- DataService already may have set TutorialComplete
			pushTutorial(player)
			return
		end
		if profile.TutorialComplete then
			pushTutorial(player)
			return
		end
		if typeof(profile.TutorialStep) ~= "number" or profile.TutorialStep < 1 then
			profile.TutorialStep = STEP_CLAIM
			DataService.MarkDirty(player)
		end
		-- v69: saved on a buy step for a structure already owned (bought early / older build) → move on
		local firstOpen = skipOwnedBuySteps(profile, profile.TutorialStep)
		if firstOpen ~= profile.TutorialStep then
			profile.TutorialStep = firstOpen
			if firstOpen > TutorialConfig.StepCount() then
				profile.TutorialComplete = true
			end
			DataService.MarkDirty(player)
		end
		-- F6: a migrated v1 save past the last step (or everything already done) is a finished tutorial
		if profile.TutorialStep > TutorialConfig.StepCount() and profile.TutorialComplete ~= true then
			profile.TutorialComplete = true
			DataService.MarkDirty(player)
		end
		pushTutorial(player)
		if profile.TutorialComplete then
			endNoviceShield(player) -- F6 (no-op unless a shield is already up)
			return
		end
		-- Plot assignment counts as claim-base progress
		task.defer(function()
			if profile.BasePlotId then
				TutorialService.Notify(player, "PlotAssigned")
			end
		end)
	end
	DataService.OnProfileLoaded(function(player: Player, profile: any)
		onProfileLoaded(player, profile)
		-- v71 money (M1): the tutorial is already done at load → the Starter Pack offer 8 s in (the gate decides)
		if profile.TutorialComplete == true then
			scheduleStarterOffer(player, false)
		end
	end)

	-- Upgrade hook
	if deps.BaseService and deps.BaseService.GetUpgradeChangedEvent then
		deps.BaseService.GetUpgradeChangedEvent().Event:Connect(function(userId: number, _plotId: any, structureId: string, level: number)
			if level < 1 then
				return
			end
			local player = Players:GetPlayerByUserId(userId)
			if player then
				TutorialService.Notify(player, "Upgrade", structureId)
			end
		end)
	end

	Players.PlayerRemoving:Connect(function(player: Player)
		lastAdvanceAt[player.UserId] = nil
		lastAdvanceStep[player.UserId] = nil
		starterToken[player.UserId] = nil
	end)
end

return TutorialService
