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

print("[WAR EMPIRE] Client Bootstrap starting...")

UIController.Init()
CombatController.Init()
VehicleController.Init()
StudioSmokeClient.Init()

print("[WAR EMPIRE] Client Bootstrap ready.")
