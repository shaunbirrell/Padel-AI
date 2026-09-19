--!strict
--[[
	Attaches ProximityPrompts to StudioSetup-tagged world parts so pads feel clickable.
	Opens client UIs only (Base / Garage) or pings existing capture remote — never trusts
	client for purchases. Capture progress remains server stand-in-zone tick.
]]

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Constants = require(Shared.Constants)
local Remotes = require(Shared.Remotes)

local BaseController = require(script.Parent.BaseController)
local VehicleController = require(script.Parent.VehicleController)
local NotificationController = require(script.Parent.NotificationController)

local WorldPromptController = {}

local PROMPT_NAME = "WE_WorldPrompt"
local attached: { [Instance]: boolean } = {}

local function makePrompt(parent: BasePart, actionText: string, objectText: string, hold: number?, maxDist: number?): ProximityPrompt
	local existing = parent:FindFirstChild(PROMPT_NAME)
	if existing and existing:IsA("ProximityPrompt") then
		existing:Destroy()
	end
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = PROMPT_NAME
	prompt.ActionText = actionText
	prompt.ObjectText = objectText
	prompt.HoldDuration = hold or 0
	prompt.MaxActivationDistance = maxDist or 12
	prompt.RequiresLineOfSight = false
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.GamepadKeyCode = Enum.KeyCode.ButtonX
	prompt.Style = Enum.ProximityPromptStyle.Default
	prompt.Parent = parent
	return prompt
end

local function attachBasePlot(part: BasePart)
	if attached[part] then
		return
	end
	attached[part] = true
	local plotId = part:GetAttribute("PlotId")
	local label = if typeof(plotId) == "number" then ("Base Plot " .. tostring(plotId)) else "Base"
	local prompt = makePrompt(part, "Open Base", label, 0, 14)
	prompt.Triggered:Connect(function(who)
		if who ~= Players.LocalPlayer then
			return
		end
		BaseController.Open()
	end)
end

local function attachUpgradeSlot(part: BasePart)
	if attached[part] then
		return
	end
	attached[part] = true
	local structureId = part:GetAttribute("StructureId")
	local name = if typeof(structureId) == "string" then structureId else part.Name
	local prompt = makePrompt(part, "Upgrade", tostring(name), 0, 10)
	prompt.Triggered:Connect(function(who)
		if who ~= Players.LocalPlayer then
			return
		end
		BaseController.Open()
	end)
end

local function attachCaptureZone(part: BasePart)
	if attached[part] then
		return
	end
	attached[part] = true
	local territoryId = part:GetAttribute("TerritoryId")
	local idStr = if typeof(territoryId) == "string" then territoryId else part.Name
	local prompt = makePrompt(part, "Hold to capture", idStr, 0.4, 18)
	prompt.Triggered:Connect(function(who)
		if who ~= Players.LocalPlayer then
			return
		end
		-- Optional UI ping; server capture remains stand-in-zone tick.
		Remotes.GetEvent(Constants.RemoteNames.RequestCaptureTerritory):FireServer(idStr)
		NotificationController.Show("Stand in the zone to capture — progress fills while you hold ground.", "Info", 3.5)
	end)
end

local function attachVehicleSpawn(part: BasePart)
	if attached[part] then
		return
	end
	attached[part] = true
	local prompt = makePrompt(part, "Open Garage", "Vehicle Pad", 0, 12)
	prompt.Triggered:Connect(function(who)
		if who ~= Players.LocalPlayer then
			return
		end
		VehicleController.Open()
	end)
end

local function attachTutorialMarker(part: BasePart)
	if attached[part] then
		return
	end
	attached[part] = true
	local stepId = part:GetAttribute("TutorialStepId")
	local label = if typeof(stepId) == "string" then stepId else part.Name
	local prompt = makePrompt(part, "Continue", "Tutorial: " .. tostring(label), 0, 10)
	prompt.Triggered:Connect(function(who)
		if who ~= Players.LocalPlayer then
			return
		end
		NotificationController.Show("Follow the gold beam / tutorial panel — or press SKIP.", "Info", 3.5)
	end)
end

local function bindTag(tag: string, handler: (BasePart) -> ())
	for _, inst in ipairs(CollectionService:GetTagged(tag)) do
		if inst:IsA("BasePart") then
			handler(inst)
		end
	end
	CollectionService:GetInstanceAddedSignal(tag):Connect(function(inst)
		if inst:IsA("BasePart") then
			handler(inst)
		end
	end)
end

function WorldPromptController.Init()
	-- Delay slightly so StudioSetup / late tags can land after join.
	task.defer(function()
		task.wait(0.5)
		bindTag(Constants.Tags.BasePlot, attachBasePlot)
		bindTag(Constants.Tags.UpgradeSlot, attachUpgradeSlot)
		bindTag(Constants.Tags.CaptureZone, attachCaptureZone)
		bindTag(Constants.Tags.VehicleSpawn, attachVehicleSpawn)
		bindTag(Constants.Tags.TutorialMarker, attachTutorialMarker)
	end)
end

return WorldPromptController
