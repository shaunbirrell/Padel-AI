--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Constants = require(ReplicatedStorage:WaitForChild("Shared").Constants)

local NotificationService = {}

local RemoteSetup: any = nil

function NotificationService.Init(deps: { [string]: any })
	RemoteSetup = deps.RemoteSetup
end

function NotificationService.Notify(player: Player, message: string, notifType: string?, duration: number?)
	local remote = RemoteSetup.Get(Constants.RemoteNames.Notification) :: RemoteEvent
	remote:FireClient(player, {
		Message = message,
		Type = notifType or "Info",
		Duration = duration or 4,
	})
end

function NotificationService.NotifyAll(message: string, notifType: string?)
	for _, player in ipairs(game:GetService("Players"):GetPlayers()) do
		NotificationService.Notify(player, message, notifType)
	end
end

return NotificationService
