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
safeInit("BusinessVisuals", safeRequire("BusinessVisuals", Modules:WaitForChild("BusinessVisuals", 5) :: Instance)) -- v72: own war-business crates + "+$N" pops (client-only look; no-op while BusinessConfig.Enabled is false)
-- F4 / F5 (owner's 11 features): client-only guidance, each a no-op while its flag is off
safeInit("ProducerLabels", safeRequire("ProducerLabels", Modules:WaitForChild("ProducerLabels", 5) :: Instance)) -- owner-only "+$N every 5s" over the nearest own yard / pump (EconomyConfig.ProducerLabels.Enabled)
safeInit("NextPadChevrons", safeRequire("NextPadChevrons", Modules:WaitForChild("NextPadChevrons", 5) :: Instance)) -- gold floor chevrons to the next pad on the own plot (TycoonGuideConfig.Chevrons.Enabled)
safeInit("LabelGovernor", safeRequire("LabelGovernor", Modules:WaitForChild("LabelGovernor", 5) :: Instance)) -- at most 3 base labels on screen (WorldLabelConfig.BaseLabelGovernor.Enabled)
safeInit("OpsController", safeRequire("OpsController", Controllers:WaitForChild("OpsController", 5) :: Instance)) -- W3s2 Phase B Jobs: JOBS rows, job card, hold pill (a no-op while OpsConfig.Enabled is false)

print("[WAR EMPIRE] Client Bootstrap ready.")
