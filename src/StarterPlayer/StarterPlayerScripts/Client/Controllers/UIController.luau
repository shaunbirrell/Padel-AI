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

function UIController.Init()
	HUDController.Init()
	BaseController.Init()
	NotificationController.Init()
	TutorialController.Init()
	TerritoryController.Init()
	MissionController.Init()
	ShopController.Init()
	ProgressionController.Init()
end

return UIController
