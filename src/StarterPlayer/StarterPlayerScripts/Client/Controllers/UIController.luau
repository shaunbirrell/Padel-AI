--!strict
--[[ Root UI coordinator — wires mobile action dock after panel controllers Init. ]]

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
local CompassController = require(script.Parent.CompassController)

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
	CompassController.Init()

	-- Mobile advanced dock: large color-coded tiles (Shop / Rebirth / Orders / Army / Settings)
	-- Inspiration-only layout quality — keep WAR EMPIRE hotkeys (P/K/M/A/O).
	local function dockPress(label: string, toggleFn: () -> ())
		print("[WAR EMPIRE] Dock pressed:", label)
		NotificationController.Show(label .. " opened", "Info", 1.6)
		pcall(AudioController.PlayClick)
		local ok, err = pcall(toggleFn)
		if not ok then
			warn("[WAR EMPIRE] Dock Toggle failed:", label, err)
			NotificationController.Show(label .. " failed — check Output", "Warn", 3)
		end
	end

	HUDController.BindActionBar({
		{
			Name = "DockShop",
			Icon = "🛒",
			Label = "SHOP",
			Color = Color3.fromRGB(230, 170, 50),
			OnClick = function()
				dockPress("Shop", ShopController.Toggle)
			end,
		},
		{
			Name = "DockRebirth",
			Icon = "♻",
			Label = "REBIRTH",
			Color = Color3.fromRGB(150, 90, 220),
			OnClick = function()
				dockPress("Rebirth", ProgressionController.Toggle)
			end,
		},
		{
			Name = "DockOrders",
			Icon = "📋",
			Label = "ORDERS",
			Color = Color3.fromRGB(70, 160, 220),
			OnClick = function()
				dockPress("Orders", MissionController.Toggle)
			end,
		},
		{
			Name = "DockArmy",
			Icon = "⚔",
			Label = "ARMY",
			Color = Color3.fromRGB(90, 140, 70),
			OnClick = function()
				dockPress("Army", ArmyController.Toggle)
			end,
		},
		{
			Name = "DockSettings",
			Icon = "⚙",
			Label = "SETTINGS",
			Color = Color3.fromRGB(70, 78, 90),
			OnClick = function()
				dockPress("Settings", SettingsController.Toggle)
			end,
		},
	})
	print("[WAR EMPIRE] UIController: action dock bound (Shop/Rebirth/Orders/Army/Settings)")
end

return UIController
