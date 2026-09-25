--!strict
--[[
	Root UI coordinator (v70 "clean screen"): inits every controller, binds the left rail (5 tiles — no Base,
	no Settings tile, no "opened" toast), the TopStrip settings gear and cash + chip, registers every panel
	with HudLayout (one open at a time → the Modal flag) and routes interior terminals (WE_OpenPanel) to panels.
]]

local UIController = {}

local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")
local Workspace = game:GetService("Workspace")

local AudioController = require(script.Parent.Parent.Modules.AudioController)
local HudLayout = require(script.Parent.Parent.Modules.HudLayout)
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
local ResearchController = require(script.Parent.ResearchController) -- v69 Research Lab upgrades
local MissileController = require(script.Parent.MissileController) -- v69 Command Center strikes

-- v70 custom ProximityPrompt pills (spec §3.5). Required defensively: a missing or broken module must leave
-- Roblox's Default prompt style in place (spec risk #2), never take the rest of the UI down with it.
local PromptController: any = nil
do
	local mod = script.Parent:FindFirstChild("PromptController")
	if mod and mod:IsA("ModuleScript") then
		local req: any = require
		local ok, res = pcall(req, mod)
		if ok and typeof(res) == "table" then
			PromptController = res
		else
			warn("[WAR EMPIRE] PromptController failed to load — Default prompt style kept:", res)
		end
	end
end

-- Nations (lane C): the "Choose your nation" picker. Required defensively like PromptController: a missing or broken
-- picker must never take the other panels down with it (the flagpole prompt then just warns "unknown panel").
local NationController: any = nil
do
	local mod = script.Parent:FindFirstChild("NationController")
	if mod and mod:IsA("ModuleScript") then
		local req: any = require
		local ok, res = pcall(req, mod)
		if ok and typeof(res) == "table" then
			NationController = res
		else
			warn("[WAR EMPIRE] NationController failed to load — nation picker off:", res)
		end
	end
end

-- Every panel HudLayout keeps exclusive (spec §3.8). A controller that registers itself wins; UIController files a
-- Fallback registration (IsOpen / Close) for the rest. "Orders" = the Army popover (OrdersController).
local PANELS: { { Id: string, Controller: any } } = {
	{ Id = "Shop", Controller = ShopController },
	{ Id = "Rebirth", Controller = ProgressionController },
	{ Id = "Missions", Controller = MissionController },
	{ Id = "Army", Controller = ArmyController },
	{ Id = "Orders", Controller = OrdersController },
	{ Id = "Garage", Controller = VehicleController },
	{ Id = "Settings", Controller = SettingsController },
	{ Id = "Base", Controller = BaseController },
	{ Id = "Research", Controller = ResearchController },
	{ Id = "Missiles", Controller = MissileController },
}
if NationController then
	table.insert(PANELS, { Id = "Nation", Controller = NationController }) -- nations: the country picker
end

local function panelController(id: string): any
	for _, p in ipairs(PANELS) do
		if p.Id == id then
			return p.Controller
		end
	end
	return nil
end

local function controllerIsOpen(ctrl: any): boolean
	local f = ctrl and ctrl.IsOpen
	if typeof(f) ~= "function" then
		return false
	end
	local ok, open = pcall(f)
	return ok and open == true
end

local function registerPanels()
	for _, p in ipairs(PANELS) do
		local ctrl = p.Controller
		if not HudLayout.HasPanel(p.Id) and typeof(ctrl.IsOpen) == "function" and typeof(ctrl.Close) == "function" then
			HudLayout.RegisterPanel(p.Id, function(): boolean
				return controllerIsOpen(ctrl)
			end, function()
				ctrl.Close()
			end, { Fallback = true })
		end
	end
end

-- After an opener ran, tell HudLayout what the panel now reports — only for a panel that did not report itself
-- (see runOpener), so the fallback never races the panel's own PanelOpened / PanelClosed.
local function syncPanel(id: string)
	local ctrl = panelController(id)
	if not ctrl or typeof(ctrl.IsOpen) ~= "function" then
		return
	end
	if controllerIsOpen(ctrl) then
		HudLayout.PanelOpened(id)
	else
		HudLayout.PanelClosed(id)
	end
end

-- Run a panel opener; if the panel made no PanelOpened / PanelClosed call of its own (HudLayout.PanelSerial
-- unchanged, checked one deferred step later so a deferred self-report still counts), sync it from IsOpen.
local function runOpener(panelId: string?, fn: (...any) -> (), ...: any): (boolean, any)
	local serial = HudLayout.PanelSerial()
	local ok, err = pcall(fn :: any, ...)
	if panelId then
		local id: string = panelId
		task.defer(function()
			if HudLayout.PanelSerial() == serial then
				syncPanel(id)
			end
		end)
	end
	return ok, err
end

-- PromptController.Init failed half-way: put every prompt back on Roblox's own UI so nothing becomes unusable.
local function restoreDefaultPrompts()
	pcall(function()
		if PromptController and typeof(PromptController.Shutdown) == "function" then
			PromptController.Shutdown()
		end
	end)
	pcall(function()
		for _, d in ipairs(Workspace:GetDescendants()) do
			if d:IsA("ProximityPrompt") and d.Style ~= Enum.ProximityPromptStyle.Default then
				d.Style = Enum.ProximityPromptStyle.Default
			end
		end
	end)
end

function UIController.Init()
	local function safeInit(name: string, fn: () -> ()): boolean
		local ok, err = pcall(fn :: any)
		if not ok then
			warn("[WAR EMPIRE] UI Init failed:", name, err)
		end
		return ok
	end
	safeInit("Audio", AudioController.Init)
	-- v60: HUD + WorldPrompt BEFORE Notification — cash never waits on toast remote
	safeInit("HUD", HUDController.Init)
	safeInit("WorldPrompt", WorldPromptController.Init)
	safeInit("Notification", NotificationController.Init)
	if PromptController and typeof(PromptController.Init) == "function" then
		if not safeInit("Prompt", PromptController.Init) then
			restoreDefaultPrompts()
		end
	end
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
	safeInit("Research", ResearchController.Init)
	safeInit("Missiles", MissileController.Init)
	if NationController and typeof(NationController.Init) == "function" then
		safeInit("Nation", NationController.Init) -- nations: join picker (auto-open) + flagpole / Settings opener
	end
	safeInit("Panels", registerPanels)

	-- Rail / gear / cash + press: the opener, ONE click sound, no toast (the panel opening is the feedback).
	local function dockPress(label: string, toggleFn: () -> (), panelId: string?)
		pcall(AudioController.PlayClick)
		local ok, err = runOpener(panelId, toggleFn :: any)
		if not ok then
			warn("[WAR EMPIRE] rail open failed:", label, err)
		end
	end

	-- Cash + (the TopStrip chip since the mobile merge gate) → Shop cash packs (ShopController.OpenCashPacks when
	-- present, else the Shop)
	HUDController.BindShopOpener(function()
		local shop: any = ShopController
		local open: () -> () = if typeof(shop.OpenCashPacks) == "function" then shop.OpenCashPacks else ShopController.Open
		dockPress("Shop", open, "Shop")
	end)
	-- TopStrip gear → Settings (no rail tile, no key)
	HUDController.BindSettingsOpener(function()
		dockPress("Settings", SettingsController.Toggle, "Settings")
	end)

	-- Left rail (spec §3.2): Shop · Rebirth · Army · Garage · Missions. Labels, icons and colours come from
	-- HudConfig.Rail.Tiles; v69's 7-tile dock ({ Name = "DockMissions", Label = "MISSIONS" } …, BASE, SETTINGS)
	-- is gone — Base opens from B / the Command Center terminal, Settings from the TopStrip gear.
	HUDController.BindActionBar({
		{
			Id = "Shop",
			Name = "DockShop",
			OnClick = function()
				dockPress("Shop", ShopController.Toggle, "Shop")
			end,
		},
		{
			Id = "Rebirth",
			Name = "DockRebirth",
			OnClick = function()
				dockPress("Rebirth", ProgressionController.Toggle, "Rebirth")
			end,
		},
		{
			Id = "Army",
			Name = "DockArmy",
			OnClick = function()
				-- the Army popover (OrdersController, spec §3.8); the full Army panel until it exists
				local orders: any = OrdersController
				if typeof(orders.Toggle) == "function" then
					dockPress("Army", orders.Toggle, "Orders")
				else
					dockPress("Army", ArmyController.Toggle, "Army")
				end
			end,
			-- mobile plan P1-6: hold the Army tile to cycle the squad order (the touch twin of T), no popover
			OnLongPress = function()
				local orders: any = OrdersController
				if typeof(orders.CycleOrder) == "function" then
					pcall(AudioController.PlayClick)
					orders.CycleOrder()
				end
			end,
		},
		{
			Id = "Garage",
			Name = "DockGarage",
			OnClick = function()
				dockPress("Garage", VehicleController.Toggle, "Garage")
			end,
		},
		{
			Id = "Missions",
			Name = "DockMissions",
			OnClick = function()
				dockPress("Missions", MissionController.Toggle, "Missions")
			end,
		},
	})
	print("[WAR EMPIRE] UIController: rail bound (Shop/Rebirth/Army/Garage/Missions) + TopStrip gear")

	-- v68: item terminals inside walk-in buildings (server HollowBuildingBuilder + Interiors/*) carry the
	-- panel to open in the prompt attribute WE_OpenPanel. Keep this list in sync with the interior checker.
	local panelOpeners: { [string]: (...any) -> () } = {
		Base = BaseController.Open,
		Shop = ShopController.Open,
		Rebirth = ProgressionController.Open,
		Missions = MissionController.Open,
		Army = ArmyController.Open,
		Garage = VehicleController.Open,
		Settings = SettingsController.Open,
		Research = ResearchController.Open,
		Missiles = MissileController.Open,
	}
	-- nations: the flagpole prompt (server, WE_OpenPanel = "Nation", WE_OpenTab = "flagpole") opens the picker
	if NationController and typeof(NationController.Open) == "function" then
		panelOpeners.Nation = NationController.Open
	end
	ProximityPromptService.PromptTriggered:Connect(function(prompt: ProximityPrompt, who: Player)
		if who ~= Players.LocalPlayer then
			return
		end
		local panel = prompt:GetAttribute("WE_OpenPanel")
		if typeof(panel) ~= "string" then
			return
		end
		local open = panelOpeners[panel]
		if not open then
			warn("[WAR EMPIRE] terminal opens unknown panel:", panel)
			return
		end
		pcall(AudioController.PlayClick)
		-- optional tab hint on the prompt (e.g. the Armory counter opens Shop → Weapons)
		local tab = prompt:GetAttribute("WE_OpenTab")
		local ok, err
		if typeof(tab) == "string" and panel == "Shop" and ShopController.OpenTab then
			ok, err = runOpener(panel, ShopController.OpenTab :: any, tab)
		else
			ok, err = runOpener(panel, open, if typeof(tab) == "string" then tab else nil)
		end
		if not ok then
			warn("[WAR EMPIRE] terminal panel failed:", panel, err)
		end
	end)
end

return UIController
