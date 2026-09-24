--!strict
--[[ WAR EMPIRE — Client Bootstrap ]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Wait for Shared; WE_Remotes created by server EarlyRemotes (BindEvent handles late)
ReplicatedStorage:WaitForChild("Shared")

local Controllers = script.Parent:WaitForChild("Controllers")
local Modules = script.Parent:WaitForChild("Modules")
local UIController = require(Controllers.UIController)
local CombatController = require(Controllers.CombatController)
local VehicleController = require(Controllers.VehicleController)
local StudioSmokeClient = require(Modules.StudioSmokeClient)
local WorldSpinners = require(Modules.WorldSpinners)

print("[WAR EMPIRE] Client Bootstrap starting...")

UIController.Init()
CombatController.Init()
VehicleController.Init()
StudioSmokeClient.Init()
-- v68: radar dishes on base installations (visual only; never block the rest of the client)
local okSpin, errSpin = pcall(WorldSpinners.Init)
if not okSpin then
	warn("[WAR EMPIRE] WorldSpinners failed:", errSpin)
end

print("[WAR EMPIRE] Client Bootstrap ready.")
