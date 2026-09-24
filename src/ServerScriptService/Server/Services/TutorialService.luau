--!strict
--[[
	MVP interactive tutorial (v31 first-2-min):
	claim → MoneyCollector → ClickDropper → CommandCenter buy → recruit → barracks → jeep → outpost
	Server-authoritative step advancement; client shows UI + optional markers. SKIP kept.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared.Constants)
local TutorialConfig = require(Shared.Configs.TutorialConfig)
local GameConfig = require(Shared.Configs.GameConfig)
local DevConfig = require(Shared.Configs.DevConfig)

local RemoteGuard = require(script.Parent.Parent.Modules.RemoteGuard)

local TutorialService = {}

local DataService: any = nil
local RemoteSetup: any = nil
local NotificationService: any = nil
local RateLimitService: any = nil

local STEP_CLAIM = 1
local STEP_INCOME = 2
local STEP_DROPPER = 3
local STEP_COMMAND = 4
local STEP_RECRUIT = 5
local STEP_BARRACKS = 6
local STEP_JEEP = 7
local STEP_OUTPOST = 8

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
	})
end

function TutorialService.Push(player: Player)
	pushTutorial(player)
end

--[[ v69: buy steps (PadStructureId) for a structure the player already owns are done — skip them. The HUD goal
	sends new players to buy Command Center before step 4, which then only advanced on ANOTHER CC purchase
	($8,000 for L2); same for Barracks at step 6. Returns the first step that still needs doing. ]]
local function skipOwnedBuySteps(profile: any, step: number): number
	local upgrades = if typeof(profile.BaseUpgrades) == "table" then profile.BaseUpgrades else {}
	local total = TutorialConfig.StepCount()
	while step <= total do
		local def = TutorialConfig.GetStep(step)
		local sid = if def then def.PadStructureId else nil
		if typeof(sid) ~= "string" or (tonumber(upgrades[sid]) or 0) < 1 then
			break
		end
		step += 1
	end
	return step
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

	if eventType == "PlotAssigned" and step == STEP_CLAIM then
		-- v69: server full → no plot yet; the claim step waits until a plot is handed out
		if profile.BasePlotId == nil then
			return
		end
		advanceTo(player, STEP_CLAIM)
	elseif eventType == "PassiveIncome" and step == STEP_INCOME then
		advanceTo(player, STEP_INCOME)
	elseif eventType == "ManualDrop" and step == STEP_DROPPER then
		advanceTo(player, STEP_DROPPER)
	elseif eventType == "Upgrade" and typeof(detail) == "string" then
		if detail == "CommandCenter" and step == STEP_COMMAND then
			advanceTo(player, STEP_COMMAND)
		elseif detail == "Barracks" and step == STEP_BARRACKS then
			advanceTo(player, STEP_BARRACKS)
		end
	elseif eventType == "RecruitSoldiers" and step == STEP_RECRUIT then
		advanceTo(player, STEP_RECRUIT)
	elseif eventType == "SpawnVehicle" and step == STEP_JEEP then
		-- MilitaryJeep or any vehicle spawn satisfies jeep step
		advanceTo(player, STEP_JEEP)
	elseif eventType == "CaptureTerritory" and step == STEP_OUTPOST then
		advanceTo(player, STEP_OUTPOST)
	end
end

function TutorialService.Init(deps: { [string]: any })
	DataService = deps.DataService
	RemoteSetup = deps.RemoteSetup
	NotificationService = deps.NotificationService
	RateLimitService = deps.RateLimitService

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

	DataService.OnProfileLoaded(function(player: Player, profile: any)
		if not tutorialEnabled() then
			profile.TutorialComplete = true
			pushTutorial(player)
			return
		end
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
		pushTutorial(player)
		if profile.TutorialComplete then
			return
		end
		-- Plot assignment counts as claim-base progress
		task.defer(function()
			if profile.BasePlotId then
				TutorialService.Notify(player, "PlotAssigned")
			end
		end)
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
	end)
end

return TutorialService
