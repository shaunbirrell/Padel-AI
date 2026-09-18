--!strict
--[[ Root UI coordinator ]]

local UIController = {}

local HUDController = require(script.Parent.HUDController)
local BaseController = require(script.Parent.BaseController)
local NotificationController = require(script.Parent.NotificationController)
local TutorialController = require(script.Parent.TutorialController)
local TerritoryController = require(script.Parent.TerritoryController)
local MissionController = require(script.Parent.MissionController)
local ShopController = require(script.Parent.ShopController)
local ProgressionController = require(script.Parent.ProgressionController)
local ArmyController = require(script.Parent.ArmyController)
local SettingsController = require(script.Parent.SettingsController)

function UIController.Init()
	HUDController.Init()
	BaseController.Init()
	NotificationController.Init()
	TutorialController.Init()
	TerritoryController.Init()
	MissionController.Init()
	ShopController.Init()
	ProgressionController.Init()
	ArmyController.Init()
	SettingsController.Init()
end

return UIController
