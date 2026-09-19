--!strict
--[[ Root UI coordinator ]]

local UIController = {}

local AudioController = require(script.Parent.Parent.Modules.AudioController)
local HUDController = require(script.Parent.HUDController)
local NotificationController = require(script.Parent.NotificationController)
local BaseController = require(script.Parent.BaseController)
local TutorialController = require(script.Parent.TutorialController)
local TerritoryController = require(script.Parent.TerritoryController)
local MissionController = require(script.Parent.MissionController)
local ShopController = require(script.Parent.ShopController)
local ProgressionController = require(script.Parent.ProgressionController)
local ArmyController = require(script.Parent.ArmyController)
local SettingsController = require(script.Parent.SettingsController)
local WorldPromptController = require(script.Parent.WorldPromptController)

function UIController.Init()
	AudioController.Init()
	HUDController.Init()
	-- Notifications before Base so first-join toasts have a stack ready.
	NotificationController.Init()
	BaseController.Init()
	TutorialController.Init()
	TerritoryController.Init()
	MissionController.Init()
	ShopController.Init()
	ProgressionController.Init()
	ArmyController.Init()
	SettingsController.Init()
	WorldPromptController.Init()
end

return UIController
