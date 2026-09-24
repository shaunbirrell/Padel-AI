--!strict
--[[ Server → client toast. NotifyThrottled debounces identical messages per player. ]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Constants = require(ReplicatedStorage:WaitForChild("Shared").Constants)

local NotificationService = {}

local RemoteSetup: any = nil

-- userId|messageType → last fire clock
local lastByKey: { [string]: number } = {}
local DEFAULT_COOLDOWN = 0.85 -- Shaun: ~1/2–1s between identical pad toasts

function NotificationService.Init(deps: { [string]: any })
	RemoteSetup = deps.RemoteSetup
end

--[[ amount (v71, HUD v70 spec §4.2): money this line is about. With type "Collect" the client shows no lane line,
	only the "+$N" float at the cash pill (negative = the red spend float); other types ignore it. ]]
function NotificationService.Notify(player: Player, message: string, notifType: string?, duration: number?, amount: number?)
	local remote = RemoteSetup.Get(Constants.RemoteNames.Notification) :: RemoteEvent
	remote:FireClient(player, {
		Message = message,
		Type = notifType or "Info",
		Duration = duration or 4,
		Amount = amount,
	})
end

--[[ Throttle by message text (or explicit key). Returns true if sent. ]]
function NotificationService.NotifyThrottled(
	player: Player,
	message: string,
	notifType: string?,
	duration: number?,
	cooldownSec: number?,
	keySuffix: string?
): boolean
	local cd = cooldownSec or DEFAULT_COOLDOWN
	local key = tostring(player.UserId) .. "|" .. (keySuffix or message)
	local now = os.clock()
	local last = lastByKey[key] or 0
	if now - last < cd then
		return false
	end
	lastByKey[key] = now
	NotificationService.Notify(player, message, notifType, duration)
	return true
end

function NotificationService.NotifyAll(message: string, notifType: string?)
	for _, player in ipairs(game:GetService("Players"):GetPlayers()) do
		NotificationService.Notify(player, message, notifType)
	end
end

game:GetService("Players").PlayerRemoving:Connect(function(player)
	local prefix = tostring(player.UserId) .. "|"
	for k in pairs(lastByKey) do
		if string.sub(k, 1, #prefix) == prefix then
			lastByKey[k] = nil
		end
	end
end)

return NotificationService
