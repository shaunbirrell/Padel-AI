--!strict
--[[
	FallSafetyService — teleport to plot spawn instead of void-Kill when
	HumanoidRootPart falls below FALL_Y (e.g. off oil decks / past Ground).
	Does not replace collide floor / SafetyCatch; soft recovery layer.

	streaming2 S1 (F3), only while Workspace.StreamingEnabled is on (StreamPrefetch.Enabled()):
	- no rescue while player.GameplayPaused: the phone is waiting for the ground to stream in (StreamingIntegrityMode
	  PauseOutsideLoadedArea), it is not falling. A rescue would send it to another spot it has not streamed, again
	  and again, with a toast each time.
	- no rescue while a pre-fetched move (StreamPrefetch) is already taking the player home;
	- the rescue goes through BaseService.TeleportToPlot, which pre-fetches the plot before the move;
	- the toast is NotifyThrottled: at most one per StreamingConfig.FallToastCooldown seconds.
	With streaming off every rescue and its toast are exactly as before.
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local StreamingConfig = require(ReplicatedStorage:WaitForChild("Shared", 60).Configs.StreamingConfig)
local StreamPrefetch = require(script.Parent.Parent.Modules.StreamPrefetch)

local FallSafetyService = {}

local FALL_Y = 0.15 -- Ground top ~0.5; rescue as soon as under / through floor plane
local COOLDOWN_SEC = 0.9
local FALL_TOAST = "Rescued from fall — returned to base."

local BaseService: any = nil
local NotificationService: any = nil

local lastRescueAt: { [number]: number } = {}

local function rescue(player: Player, root: BasePart)
	local streaming = StreamPrefetch.Enabled()
	-- streaming2 S1 (F3): a paused phone waits for its ground; a pre-fetched move home is already on its way
	if streaming and (player.GameplayPaused or StreamPrefetch.IsMoving(player)) then
		return
	end
	local now = os.clock()
	local last = lastRescueAt[player.UserId] or 0
	if now - last < COOLDOWN_SEC then
		return
	end
	lastRescueAt[player.UserId] = now

	-- Stop downward velocity before teleport
	root.AssemblyLinearVelocity = Vector3.zero
	root.AssemblyAngularVelocity = Vector3.zero

	if BaseService and BaseService.TeleportToPlot then
		BaseService.TeleportToPlot(player)
	else
		-- Fallback: origin above Ground (pre-fetched while streaming is on)
		StreamPrefetch.PivotTo(player, CFrame.new(0, 8, 0))
	end

	if NotificationService then
		if streaming and NotificationService.NotifyThrottled then
			NotificationService.NotifyThrottled(player, FALL_TOAST, "Info", 3, StreamingConfig.FallToastCooldown, "FallSafety")
		elseif NotificationService.Notify then
			NotificationService.Notify(player, FALL_TOAST, "Info", 3)
		end
	end
	print("[FallSafety] rescued", player.Name, "from Y<", FALL_Y)
end

function FallSafetyService.Init(deps: { [string]: any })
	BaseService = deps.BaseService
	NotificationService = deps.NotificationService

	-- Stepped heartbeat: cheap Y check only
	local accum = 0
	RunService.Heartbeat:Connect(function(dt)
		accum += dt
		if accum < 0.1 then
			return
		end
		accum = 0
		for _, player in ipairs(Players:GetPlayers()) do
			local character = player.Character
			if not character then
				continue
			end
			local root = character:FindFirstChild("HumanoidRootPart") :: BasePart?
			if not root then
				continue
			end
			local hum = character:FindFirstChildOfClass("Humanoid")
			if hum and hum.Health <= 0 then
				continue
			end
			if root.Position.Y < FALL_Y then
				rescue(player, root)
			end
		end
	end)

	Players.PlayerRemoving:Connect(function(player)
		lastRescueAt[player.UserId] = nil
	end)

	print("[WAR EMPIRE] FallSafetyService ready (teleport if Y < " .. tostring(FALL_Y) .. "; SafetyCatch underfloor remains)")
end

return FallSafetyService
