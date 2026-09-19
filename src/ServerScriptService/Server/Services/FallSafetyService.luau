--!strict
--[[
	FallSafetyService — teleport to plot spawn instead of void-Kill when
	HumanoidRootPart falls below FALL_Y (e.g. off oil decks / past Ground).
	Does not replace collide floor / SafetyCatch; soft recovery layer.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local FallSafetyService = {}

local FALL_Y = -30
local COOLDOWN_SEC = 2.5

local BaseService: any = nil
local NotificationService: any = nil

local lastRescueAt: { [number]: number } = {}

local function rescue(player: Player, root: BasePart)
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
		-- Fallback: origin above Ground
		local character = player.Character
		if character then
			character:PivotTo(CFrame.new(0, 8, 0))
		end
	end

	if NotificationService and NotificationService.Notify then
		NotificationService.Notify(player, "Rescued from fall — returned to base.", "Info", 3)
	end
end

function FallSafetyService.Init(deps: { [string]: any })
	BaseService = deps.BaseService
	NotificationService = deps.NotificationService

	-- Stepped heartbeat: cheap Y check only
	local accum = 0
	RunService.Heartbeat:Connect(function(dt)
		accum += dt
		if accum < 0.2 then
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

	print("[WAR EMPIRE] FallSafetyService ready (teleport if Y < " .. tostring(FALL_Y) .. ")")
end

return FallSafetyService
