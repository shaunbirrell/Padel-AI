--!strict
--[[
	MVP interactive tutorial: claim base → command center → income → barracks → jeep → outpost
	Server-authoritative step advancement; client shows UI + optional markers.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared.Constants)
local TutorialConfig = require(Shared.Configs.TutorialConfig)
local GameConfig = require(Shared.Configs.GameConfig)
local DevConfig = require(Shared.Configs.DevConfig)

local TutorialService = {}

local DataService: any = nil
local RemoteSetup: any = nil
local NotificationService: any = nil
local RateLimitService: any = nil

local STEP_CLAIM = 1
local STEP_COMMAND = 2
local STEP_INCOME = 3
local STEP_BARRACKS = 4
local STEP_JEEP = 5
local STEP_OUTPOST = 6

local function tutorialEnabled(): boolean
	if not GameConfig.TutorialEnabled or not TutorialConfig.Enabled then
		return false
	end
	return true
end

local function pushTutorial(player: Player)
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
	})
end

function TutorialService.Push(player: Player)
	pushTutorial(player)
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
	local nextStep = targetStep + 1
	if nextStep > TutorialConfig.StepCount() then
		setStep(player, nextStep, true)
	else
		setStep(player, nextStep, false)
		local def = TutorialConfig.GetStep(nextStep)
		if def and NotificationService then
			NotificationService.Notify(player, def.Title .. ": " .. def.Hint, "Info", 6)
		end
	end
end

function TutorialService.Complete(player: Player)
	local profile = DataService.GetProfile(player)
	if not profile then
		return
	end
	profile.TutorialComplete = true
	profile.TutorialStep = TutorialConfig.StepCount() + 1
	DataService.MarkDirty(player)
	pushTutorial(player)
	if NotificationService then
		NotificationService.Notify(player, "Tutorial skipped.", "Info")
	end
end

function TutorialService.Reset(player: Player)
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
	event types: PlotAssigned | Upgrade | PassiveIncome | SpawnVehicle | CaptureTerritory
]]
function TutorialService.Notify(player: Player, eventType: string, detail: any?)
	if not tutorialEnabled() then
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
		advanceTo(player, STEP_CLAIM)
	elseif eventType == "Upgrade" and typeof(detail) == "string" then
		if detail == "CommandCenter" and step == STEP_COMMAND then
			advanceTo(player, STEP_COMMAND)
		elseif detail == "Barracks" and step == STEP_BARRACKS then
			advanceTo(player, STEP_BARRACKS)
		end
	elseif eventType == "PassiveIncome" and step == STEP_INCOME then
		advanceTo(player, STEP_INCOME)
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
		pushTutorial(player)
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
end

return TutorialService
