--!strict
--[[ WAR EMPIRE — Client Bootstrap ]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Wait for Shared; WE_Remotes created by server EarlyRemotes (BindEvent handles late)
-- streaming2 C5: every wait is bounded (CLAUDE.md), but a slow phone gets time: up to 180 s for Shared, in 60 s
-- slices with one warn per slice. If Shared never comes, one small "rejoin" notice (only when PlayerGui is there)
-- and a clean stop: nothing is required, so no controller can throw or hang. With Shared here, every module's own
-- 60 s Shared wait returns at once. The numbers live here, not in Shared/Configs: Configs is inside the missing folder.
local SHARED_WAIT_SLICE_S = 60
local SHARED_WAIT_MAX_S = 180
-- PlayerGui gets the same slow-phone time, once, here (see the PlayerGui gate below)
local PLAYERGUI_WAIT_SLICE_S = 60
local PLAYERGUI_WAIT_MAX_S = 180

-- One small, phone-readable notice: top centre under the Roblox top bar (clear of the thumbstick zone, the jump
-- button and the top-bar pills), 20 px text, nothing tappable, no key names.
local function showLoadFailedNotice()
	local player = Players.LocalPlayer
	local pg = if player then player:WaitForChild("PlayerGui", 10) else nil
	if not pg then
		warn("[WAR EMPIRE] Client Bootstrap: no PlayerGui after 10 s; load notice not shown")
		return
	end
	local gui = Instance.new("ScreenGui")
	gui.Name = "WE_LoadFailed"
	gui.ResetOnSpawn = false
	gui.IgnoreGuiInset = false
	gui.DisplayOrder = 100
	local label = Instance.new("TextLabel")
	label.Name = "Notice"
	label.Active = false
	label.AnchorPoint = Vector2.new(0.5, 0)
	label.Position = UDim2.new(0.5, 0, 0, 8)
	label.Size = UDim2.fromOffset(300, 64)
	label.BackgroundColor3 = Color3.fromRGB(18, 20, 24)
	label.BackgroundTransparency = 0.1
	label.BorderSizePixel = 0
	label.Font = Enum.Font.GothamBold
	label.TextSize = 20
	label.TextColor3 = Color3.fromRGB(255, 255, 255)
	label.TextWrapped = true
	label.Text = "Game failed to load.\nPlease rejoin."
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, 10)
	corner.Parent = label
	label.Parent = gui
	gui.Parent = pg
end

local sharedFolder: Instance? = nil
local waitedS = 0
while not sharedFolder and waitedS < SHARED_WAIT_MAX_S do
	sharedFolder = ReplicatedStorage:WaitForChild("Shared", SHARED_WAIT_SLICE_S)
	if not sharedFolder then
		waitedS += SHARED_WAIT_SLICE_S
		warn(string.format("[WAR EMPIRE] Client Bootstrap: no ReplicatedStorage.Shared after %d s; %s", waitedS,
			if waitedS < SHARED_WAIT_MAX_S then "still waiting (slow connection?)" else "giving up, client not started"))
	end
end
if not sharedFolder then
	showLoadFailedNotice()
	return
end

-- PlayerGui gate (streaming2 C5 fix 2): the same 60 s slices up to 180 s, one warn per slice, once for every
-- controller and before any require. Each controller's own 30 s PlayerGui wait then returns at once, so a late
-- PlayerGui can no longer leave the HUD (left rail, cash pill) or any other panel off for the whole session.
-- With no PlayerGui nothing can be shown (not even the rejoin notice), so the client stops cleanly.
local localPlayer = Players.LocalPlayer
local playerGui: Instance? = nil
local pgWaitedS = 0
while localPlayer and not playerGui and pgWaitedS < PLAYERGUI_WAIT_MAX_S do
	playerGui = localPlayer:WaitForChild("PlayerGui", PLAYERGUI_WAIT_SLICE_S)
	if not playerGui then
		pgWaitedS += PLAYERGUI_WAIT_SLICE_S
		warn(string.format("[WAR EMPIRE] Client Bootstrap: no PlayerGui after %d s; %s", pgWaitedS,
			if pgWaitedS < PLAYERGUI_WAIT_MAX_S then "still waiting (slow connection?)" else "giving up, client not started"))
	end
end
if not playerGui then
	if not localPlayer then
		warn("[WAR EMPIRE] Client Bootstrap: no LocalPlayer; client not started")
	end
	return
end

-- Controllers / Modules ship in this folder with the script, so these return at once (bounded anyway)
local Controllers = script.Parent:WaitForChild("Controllers", 30)
local Modules = script.Parent:WaitForChild("Modules", 30)
if not Controllers or not Modules then
	warn("[WAR EMPIRE] Client Bootstrap: no Controllers / Modules folder after 30 s; client not started")
	return
end
-- v70: every controller loads and starts inside its own pcall, so one failure (e.g. combat) can never take
-- the garage / driving / HUD down with it.
local function safeRequire(name: string, inst: Instance?): any
	if not inst then
		warn("[WAR EMPIRE] require " .. name .. " failed: module missing (bounded wait gave up)")
		return nil
	end
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

local UIController = safeRequire("UIController", Controllers:WaitForChild("UIController", 5))
local CombatController = safeRequire("CombatController", Controllers:WaitForChild("CombatController", 5))
local VehicleController = safeRequire("VehicleController", Controllers:WaitForChild("VehicleController", 5))
local StudioSmokeClient = safeRequire("StudioSmokeClient", Modules:WaitForChild("StudioSmokeClient", 5))
local WorldSpinners = safeRequire("WorldSpinners", Modules:WaitForChild("WorldSpinners", 5))

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
safeInit("FeatureController", safeRequire("FeatureController", Controllers:WaitForChild("FeatureController", 5) :: Instance)) -- claude-bud JOB 4/5: FeaturePush cues (airdrop / bounty markers)
safeInit("QualityGovernor", safeRequire("QualityGovernor", Modules:WaitForChild("QualityGovernor", 5) :: Instance)) -- claude-bud JOB 8: automatic low tier (small screen / low FPS)
safeInit("Juice", safeRequire("Juice", Modules:WaitForChild("Juice", 5) :: Instance)) -- claude-bud JOB 11: purchase burst + rebirth celebration
safeInit("BuildingTipController", safeRequire("BuildingTipController", Controllers:WaitForChild("BuildingTipController", 5) :: Instance)) -- claude-bud JOB 24 §5
safeInit("ArmyDebugClient", safeRequire("ArmyDebugClient", Modules:WaitForChild("ArmyDebugClient", 5) :: Instance)) -- v115: owner-only army slot markers + labels (ArmyConfig.Follow3.Debug + WE_ArmyDebug; /armydebug)
safeInit("PremiumWeaponsClient", safeRequire("PremiumWeaponsClient", Modules:WaitForChild("PremiumWeaponsClient", 5) :: Instance)) -- claude-bud PREMIUM: FIRE / MISSILE while driving a Robux-only vehicle
safeInit("EngagementClient", safeRequire("EngagementClient", Modules:WaitForChild("EngagementClient", 5) :: Instance)) -- claude-bud JOB 13: event banner + leaderboard board
safeInit("GameFeelClient", safeRequire("GameFeelClient", Modules:WaitForChild("GameFeelClient", 5) :: Instance)) -- claude-bud JOB 14: kill feed, vehicle numbers, raid report, sounds
safeInit("StandFx", safeRequire("StandFx", Modules:WaitForChild("StandFx", 5) :: Instance)) -- claude-bud JOB 19: purchase stand hologram spin + ring pulse
safeInit("RigAnimator", safeRequire("RigAnimator", Modules:WaitForChild("RigAnimator", 5) :: Instance)) -- R-RIG: soldier animation, army escorts, far LOD (client only; a no-op while RigConfig.Enabled is false)
safeInit("AircraftBodyClient", safeRequire("AircraftBodyClient", Modules:WaitForChild("AircraftBodyClient", 5) :: Instance)) -- air-looks: store aircraft rotors spin + seated chase camera (client only; nothing to do until a store aircraft body is live)

print("[WAR EMPIRE] Client Bootstrap ready.")
