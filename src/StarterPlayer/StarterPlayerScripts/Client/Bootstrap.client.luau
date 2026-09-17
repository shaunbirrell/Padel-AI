--!strict
--[[ WAR EMPIRE — Client Bootstrap ]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Wait for shared + remotes from server
ReplicatedStorage:WaitForChild("Shared")
ReplicatedStorage:WaitForChild("Remotes")

local Controllers = script.Parent:WaitForChild("Controllers")
local UIController = require(Controllers.UIController)
local CombatController = require(Controllers.CombatController)
local VehicleController = require(Controllers.VehicleController)

print("[WAR EMPIRE] Client Bootstrap starting...")

UIController.Init()
CombatController.Init()
VehicleController.Init()

print("[WAR EMPIRE] Client Bootstrap ready.")
