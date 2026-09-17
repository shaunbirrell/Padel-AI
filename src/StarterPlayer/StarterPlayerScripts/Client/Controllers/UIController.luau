--!strict
--[[ Root UI coordinator ]]

local UIController = {}

local HUDController = require(script.Parent.HUDController)
local BaseController = require(script.Parent.BaseController)
local NotificationController = require(script.Parent.NotificationController)
local TutorialController = require(script.Parent.TutorialController)

function UIController.Init()
	HUDController.Init()
	BaseController.Init()
	NotificationController.Init()
	TutorialController.Init()
end

return UIController
