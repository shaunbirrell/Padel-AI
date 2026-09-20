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
local OrdersController = require(script.Parent.OrdersController)
local SettingsController = require(script.Parent.SettingsController)
local WorldPromptController = require(script.Parent.WorldPromptController)
local CompassController = require(script.Parent.CompassController)
local VehicleController = require(script.Parent.VehicleController)
local BankRaidController = require(script.Parent.BankRaidController)

function UIController.Init()
	local function safeInit(name: string, fn: () -> ())
		local ok, err = pcall(fn)
		if not ok then
			warn("[WAR EMPIRE] UI Init failed:", name, err)
		end
	end
	safeInit("Audio", AudioController.Init)
	-- Notifications before Base so first-join toasts have a stack ready.
	safeInit("Notification", NotificationController.Init)
	-- BUY pads BEFORE HUD — HUD may WaitForChild remotes; never block pad CTA
	safeInit("WorldPrompt", WorldPromptController.Init)
	safeInit("HUD", HUDController.Init)
	safeInit("Base", BaseController.Init)
	safeInit("Tutorial", TutorialController.Init)
	safeInit("Territory", TerritoryController.Init)
	safeInit("Mission", MissionController.Init)
	safeInit("Shop", ShopController.Init)
	safeInit("Progression", ProgressionController.Init)
	safeInit("Army", ArmyController.Init)
safeInit("Orders", OrdersController.Init)
	safeInit("Settings", SettingsController.Init)
	safeInit("Compass", CompassController.Init)
	safeInit("BankRaid", BankRaidController.Init)

	-- Mobile advanced dock: large color-coded tiles (Shop / Rebirth / Missions / Army / Settings)
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

	-- Cash HUD `+` / pending pill → Shop (lists stubs; Prompt only when Id ~= 0)
	HUDController.BindShopOpener(function()
		dockPress("Shop", ShopController.Open)
	end)

	HUDController.BindActionBar({
		{
			Name = "DockBase",
			Icon = "🏗",
			Label = "BASE",
			Color = Color3.fromRGB(50, 160, 110),
			OnClick = function()
				dockPress("Base", BaseController.Toggle)
			end,
		},
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
			Name = "DockMissions",
			Icon = "📋",
			Label = "MISSIONS",
			Color = Color3.fromRGB(42, 48, 55), -- gunmetal
			OnClick = function()
				dockPress("Missions", MissionController.Toggle)
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
			Name = "DockGarage",
			Icon = "🚗",
			Label = "GARAGE",
			Color = Color3.fromRGB(90, 160, 200),
			OnClick = function()
				dockPress("Garage", VehicleController.Toggle)
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
	print("[WAR EMPIRE] UIController: action dock bound (Base/Shop/Rebirth/Missions/Army/Garage/Settings)")
end

return UIController
