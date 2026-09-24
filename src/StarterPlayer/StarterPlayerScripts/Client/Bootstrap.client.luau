--!strict
--[[ WAR EMPIRE — Client Bootstrap ]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Wait for Shared; WE_Remotes created by server EarlyRemotes (BindEvent handles late)
ReplicatedStorage:WaitForChild("Shared")

local Controllers = script.Parent:WaitForChild("Controllers")
local Modules = script.Parent:WaitForChild("Modules")
-- v70: every controller loads and starts inside its own pcall, so one failure (e.g. combat) can never take
-- the garage / driving / HUD down with it.
local function safeRequire(name: string, inst: Instance): any
	local ok, mod = pcall(require, inst :: ModuleScript)
	if not ok then
		warn("[WAR EMPIRE] require " .. name .. " failed:", mod)
		return nil
	end
	return mod
end

local function safeInit(name: string, mod: any)
	if type(mod) ~= "table" or type(mod.Init) ~= "function" then
		return
	end
	local ok, err = pcall(mod.Init)
	if not ok then
		warn("[WAR EMPIRE] " .. name .. ".Init failed:", err)
	end
end

local UIController = safeRequire("UIController", Controllers:WaitForChild("UIController"))
local CombatController = safeRequire("CombatController", Controllers:WaitForChild("CombatController"))
local VehicleController = safeRequire("VehicleController", Controllers:WaitForChild("VehicleController"))
local StudioSmokeClient = safeRequire("StudioSmokeClient", Modules:WaitForChild("StudioSmokeClient"))
local WorldSpinners = safeRequire("WorldSpinners", Modules:WaitForChild("WorldSpinners"))

print("[WAR EMPIRE] Client Bootstrap starting...")

safeInit("UIController", UIController)
safeInit("CombatController", CombatController)
safeInit("VehicleController", VehicleController)
safeInit("StudioSmokeClient", StudioSmokeClient)
-- v68: radar dishes on base installations (visual only; never block the rest of the client)
safeInit("WorldSpinners", WorldSpinners)
safeInit("AudioHooks", safeRequire("AudioHooks", Modules:WaitForChild("AudioHooks", 5) :: Instance)) -- W1 SND: sound cues from existing remotes / HUD signals (client only)

print("[WAR EMPIRE] Client Bootstrap ready.")
