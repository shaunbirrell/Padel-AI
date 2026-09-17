--!strict
--[[ Lightweight tutorial hints for MVP ]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Constants = require(ReplicatedStorage:WaitForChild("Shared").Constants)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Types = require(ReplicatedStorage.Shared.Types)

local TutorialController = {}

function TutorialController.Init()
	Remotes.GetEvent(Constants.RemoteNames.PlayerStateUpdate).OnClientEvent:Connect(function(state: Types.PlayerStatePayload)
		if state.TutorialComplete then
			return
		end
		-- Soft hint once via notification remote path is server-driven;
		-- client shows a one-time tip label.
		local pg = Players.LocalPlayer:FindFirstChild("PlayerGui")
		if not pg or pg:FindFirstChild("WarEmpireTutorialTip") then
			return
		end
		local gui = Instance.new("ScreenGui")
		gui.Name = "WarEmpireTutorialTip"
		gui.ResetOnSpawn = false
		gui.Parent = pg
		local tip = Instance.new("TextLabel")
		tip.AnchorPoint = Vector2.new(0.5, 1)
		tip.Position = UDim2.new(0.5, 0, 1, -80)
		tip.Size = UDim2.fromOffset(360, 40)
		tip.BackgroundColor3 = Constants.Colors.Panel
		tip.TextColor3 = Constants.Colors.Text
		tip.Font = Enum.Font.Gotham
		tip.TextSize = 14
		tip.Text = "Press B or tap Base Upgrades to build your Command Center"
		tip.Parent = gui
		local c = Instance.new("UICorner")
		c.CornerRadius = UDim.new(0, 6)
		c.Parent = tip
		task.delay(12, function()
			gui:Destroy()
		end)
	end)
end

return TutorialController
